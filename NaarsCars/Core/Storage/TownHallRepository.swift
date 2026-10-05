//
//  TownHallRepository.swift
//  NaarsCars
//

import Foundation
import SwiftData
import SwiftUI
internal import Combine

@MainActor
final class TownHallRepository {
    static let shared = TownHallRepository()

    private var modelContext: ModelContext?

    init() {}

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Posts

    func getPosts() throws -> [TownHallPost] {
        guard let modelContext = modelContext else { return [] }
        let descriptor = FetchDescriptor<SDTownHallPost>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let sdPosts = try modelContext.fetch(descriptor)
        return sdPosts.map { mapToTownHallPost($0) }
    }

    /// Re-emits the local posts whenever town hall post rows were saved — by this repository or by
    /// `TownHallSyncEngine` after a `BackgroundSyncActor` save (`.townHallPostsDidSync`). Unrelated
    /// SwiftData saves (messages, rides, badges) do not trigger a re-fetch.
    func getPostsPublisher() -> AnyPublisher<[TownHallPost], Never> {
        NotificationCenter.default.publisher(for: .townHallPostsDidSync)
            .receive(on: RunLoop.main)
            .map { _ in (try? self.getPosts()) ?? [] }
            .eraseToAnyPublisher()
    }

    /// Upsert posts with change detection; saves (and posts `.townHallPostsDidSync`) only when a row
    /// actually changed.
    /// - Parameter replaceAll: `true` when `posts` is the complete first page, so local posts missing
    ///   from it (e.g. hidden by moderation) are removed. Pass `false` for later pages or single posts.
    func upsertPosts(_ posts: [TownHallPost], replaceAll: Bool = false) throws {
        guard let modelContext = modelContext else { return }
        // Nothing to upsert and no stale check requested: avoid an empty `contains` predicate.
        guard replaceAll || !posts.isEmpty else { return }

        let ids = posts.map { $0.id }

        // One batched lookup instead of a fetch per post. A full-page sync needs every local row for
        // the stale check anyway, so fetch all in that case and reuse it for the lookup.
        let localPosts: [SDTownHallPost]
        if replaceAll {
            localPosts = try modelContext.fetch(FetchDescriptor<SDTownHallPost>())
        } else {
            localPosts = try modelContext.fetch(FetchDescriptor<SDTownHallPost>(predicate: #Predicate { ids.contains($0.id) }))
        }
        let existingById = Dictionary(uniqueKeysWithValues: localPosts.map { ($0.id, $0) })
        var didMutate = false

        // Upsert posts from server
        for post in posts {
            if let existing = existingById[post.id] {
                if updateIfChanged(existing, with: post) { didMutate = true }
            } else {
                let sdPost = mapToSDTownHallPost(post)
                modelContext.insert(sdPost)
                didMutate = true
            }
        }

        // Remove local posts not in the server response (e.g. hidden by moderation)
        if replaceAll {
            let serverIds = Set(ids)
            for local in localPosts where !serverIds.contains(local.id) {
                modelContext.delete(local)
                didMutate = true
            }
        }

        guard didMutate else { return }
        try modelContext.save()
        NotificationCenter.default.post(name: .townHallPostsDidSync, object: nil)
    }

    func deletePost(id: UUID) throws {
        guard let modelContext = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<SDTownHallPost>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
            NotificationCenter.default.post(name: .townHallPostsDidSync, object: nil)
        }
    }

    // MARK: - Comments

    func getComments(postId: UUID) throws -> [TownHallComment] {
        guard let modelContext = modelContext else { return [] }
        let descriptor = FetchDescriptor<SDTownHallComment>(
            predicate: #Predicate { $0.postId == postId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let sdComments = try modelContext.fetch(descriptor)
        let flatComments = sdComments.map { mapToTownHallComment($0) }
        return buildNestedStructure(flatComments)
    }

    /// Re-emits the thread whenever comment rows for `postId` were saved (`.townHallCommentsDidSync`
    /// with the post's `UUID` as `object`). Saves for other posts or other entities are ignored.
    func getCommentsPublisher(postId: UUID) -> AnyPublisher<[TownHallComment], Never> {
        NotificationCenter.default.publisher(for: .townHallCommentsDidSync)
            .filter { ($0.object as? UUID) == postId }
            .receive(on: RunLoop.main)
            .map { _ in (try? self.getComments(postId: postId)) ?? [] }
            .eraseToAnyPublisher()
    }

    /// Upsert comments with change detection; saves (and posts `.townHallCommentsDidSync` per post)
    /// only when a row actually changed. Never deletes local comments.
    func upsertComments(_ comments: [TownHallComment]) throws {
        guard let modelContext = modelContext else { return }

        let flattened = flattenComments(comments)
        guard !flattened.isEmpty else { return }

        // One batched lookup instead of a fetch per comment
        let ids = flattened.map { $0.id }
        let fetchDescriptor = FetchDescriptor<SDTownHallComment>(predicate: #Predicate { ids.contains($0.id) })
        let localComments = try modelContext.fetch(fetchDescriptor)
        let existingById = Dictionary(uniqueKeysWithValues: localComments.map { ($0.id, $0) })
        var didMutate = false

        for comment in flattened {
            if let existing = existingById[comment.id] {
                if updateIfChanged(existing, with: comment) { didMutate = true }
            } else {
                let sdComment = mapToSDTownHallComment(comment)
                modelContext.insert(sdComment)
                didMutate = true
            }
        }

        guard didMutate else { return }
        try modelContext.save()
        for postId in Set(flattened.map { $0.postId }) {
            NotificationCenter.default.post(name: .townHallCommentsDidSync, object: postId)
        }
    }

    func deleteComment(id: UUID) throws {
        guard let modelContext = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<SDTownHallComment>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            let postId = existing.postId
            modelContext.delete(existing)
            try modelContext.save()
            NotificationCenter.default.post(name: .townHallCommentsDidSync, object: postId)
        }
    }

    // MARK: - Mapping

    private func mapToTownHallPost(_ sdPost: SDTownHallPost) -> TownHallPost {
        let author = makeProfileSnapshot(
            id: sdPost.userId,
            name: sdPost.authorName,
            avatarUrl: sdPost.authorAvatarUrl
        )

        return TownHallPost(
            id: sdPost.id,
            userId: sdPost.userId,
            content: sdPost.content,
            imageUrl: sdPost.imageUrl,
            title: sdPost.title,
            pinned: sdPost.pinned,
            type: sdPost.type.flatMap(PostType.init(rawValue:)),
            reviewId: sdPost.reviewId,
            hiddenAt: sdPost.hiddenAt,
            hiddenBy: sdPost.hiddenBy,
            hiddenReason: sdPost.hiddenReason,
            createdAt: sdPost.createdAt,
            updatedAt: sdPost.updatedAt,
            author: author,
            review: nil,
            commentCount: sdPost.commentCount,
            upvotes: 0,
            downvotes: 0,
            userVote: nil
        )
    }

    private func mapToSDTownHallPost(_ post: TownHallPost) -> SDTownHallPost {
        SDTownHallPost(
            id: post.id,
            userId: post.userId,
            title: post.title,
            content: post.content,
            imageUrl: post.imageUrl,
            pinned: post.pinned ?? false,
            type: post.type?.rawValue,
            reviewId: post.reviewId,
            hiddenAt: post.hiddenAt,
            hiddenBy: post.hiddenBy,
            hiddenReason: post.hiddenReason,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
            authorName: post.author?.name,
            authorAvatarUrl: post.author?.avatarUrl,
            commentCount: post.commentCount
        )
    }

    /// Returns true if any field was actually modified.
    /// IMPORTANT: Must cover every field mapToSDTownHallPost sets (mirrors BackgroundSyncActor.updateSDPostIfChanged).
    private func updateIfChanged(_ sdPost: SDTownHallPost, with post: TownHallPost) -> Bool {
        var changed = false
        if sdPost.title != post.title { sdPost.title = post.title; changed = true }
        if sdPost.content != post.content { sdPost.content = post.content; changed = true }
        if sdPost.imageUrl != post.imageUrl { sdPost.imageUrl = post.imageUrl; changed = true }
        if sdPost.pinned != (post.pinned ?? false) { sdPost.pinned = post.pinned ?? false; changed = true }
        if sdPost.type != post.type?.rawValue { sdPost.type = post.type?.rawValue; changed = true }
        if sdPost.reviewId != post.reviewId { sdPost.reviewId = post.reviewId; changed = true }
        if sdPost.hiddenAt != post.hiddenAt { sdPost.hiddenAt = post.hiddenAt; changed = true }
        if sdPost.hiddenBy != post.hiddenBy { sdPost.hiddenBy = post.hiddenBy; changed = true }
        if sdPost.hiddenReason != post.hiddenReason { sdPost.hiddenReason = post.hiddenReason; changed = true }
        if sdPost.createdAt != post.createdAt { sdPost.createdAt = post.createdAt; changed = true }
        if sdPost.updatedAt != post.updatedAt { sdPost.updatedAt = post.updatedAt; changed = true }
        if sdPost.authorName != post.author?.name { sdPost.authorName = post.author?.name; changed = true }
        if sdPost.authorAvatarUrl != post.author?.avatarUrl { sdPost.authorAvatarUrl = post.author?.avatarUrl; changed = true }
        if sdPost.commentCount != post.commentCount { sdPost.commentCount = post.commentCount; changed = true }
        return changed
    }

    private func mapToTownHallComment(_ sdComment: SDTownHallComment) -> TownHallComment {
        let author = makeProfileSnapshot(
            id: sdComment.userId,
            name: sdComment.authorName,
            avatarUrl: sdComment.authorAvatarUrl
        )

        return TownHallComment(
            id: sdComment.id,
            postId: sdComment.postId,
            userId: sdComment.userId,
            parentCommentId: sdComment.parentCommentId,
            content: sdComment.content,
            hiddenAt: sdComment.hiddenAt,
            hiddenBy: sdComment.hiddenBy,
            hiddenReason: sdComment.hiddenReason,
            createdAt: sdComment.createdAt,
            updatedAt: sdComment.updatedAt,
            author: author,
            replies: nil,
            upvotes: 0,
            downvotes: 0,
            userVote: nil
        )
    }

    private func mapToSDTownHallComment(_ comment: TownHallComment) -> SDTownHallComment {
        SDTownHallComment(
            id: comment.id,
            postId: comment.postId,
            userId: comment.userId,
            parentCommentId: comment.parentCommentId,
            content: comment.content,
            hiddenAt: comment.hiddenAt,
            hiddenBy: comment.hiddenBy,
            hiddenReason: comment.hiddenReason,
            createdAt: comment.createdAt,
            updatedAt: comment.updatedAt,
            authorName: comment.author?.name,
            authorAvatarUrl: comment.author?.avatarUrl
        )
    }

    /// Returns true if any field was actually modified.
    /// IMPORTANT: Must cover every field mapToSDTownHallComment sets (mirrors BackgroundSyncActor.updateSDCommentIfChanged).
    private func updateIfChanged(_ sdComment: SDTownHallComment, with comment: TownHallComment) -> Bool {
        var changed = false
        if sdComment.postId != comment.postId { sdComment.postId = comment.postId; changed = true }
        if sdComment.userId != comment.userId { sdComment.userId = comment.userId; changed = true }
        if sdComment.parentCommentId != comment.parentCommentId { sdComment.parentCommentId = comment.parentCommentId; changed = true }
        if sdComment.content != comment.content { sdComment.content = comment.content; changed = true }
        if sdComment.hiddenAt != comment.hiddenAt { sdComment.hiddenAt = comment.hiddenAt; changed = true }
        if sdComment.hiddenBy != comment.hiddenBy { sdComment.hiddenBy = comment.hiddenBy; changed = true }
        if sdComment.hiddenReason != comment.hiddenReason { sdComment.hiddenReason = comment.hiddenReason; changed = true }
        if sdComment.createdAt != comment.createdAt { sdComment.createdAt = comment.createdAt; changed = true }
        if sdComment.updatedAt != comment.updatedAt { sdComment.updatedAt = comment.updatedAt; changed = true }
        if sdComment.authorName != comment.author?.name { sdComment.authorName = comment.author?.name; changed = true }
        if sdComment.authorAvatarUrl != comment.author?.avatarUrl { sdComment.authorAvatarUrl = comment.author?.avatarUrl; changed = true }
        return changed
    }

    private func makeProfileSnapshot(id: UUID, name: String?, avatarUrl: String?) -> Profile? {
        guard let name, !name.isEmpty else { return nil }
        return Profile(
            id: id,
            name: name,
            email: "\(id.uuidString)@naarscars.local",
            avatarUrl: avatarUrl
        )
    }

    private func flattenComments(_ comments: [TownHallComment]) -> [TownHallComment] {
        var output: [TownHallComment] = []
        func walk(_ comment: TownHallComment) {
            output.append(comment)
            if let replies = comment.replies {
                replies.forEach(walk)
            }
        }
        comments.forEach(walk)
        return output
    }

    private func buildNestedStructure(_ comments: [TownHallComment]) -> [TownHallComment] {
        // Pass 1: Collect all parent (top-level) comments first
        var topLevel: [TownHallComment] = []
        var childrenByParent: [UUID: [TownHallComment]] = [:]

        for comment in comments {
            if let parentId = comment.parentCommentId {
                childrenByParent[parentId, default: []].append(comment)
            } else {
                topLevel.append(comment)
            }
        }

        // Pass 2: Recursively attach children to their parents
        func attachReplies(to comment: TownHallComment) -> TownHallComment {
            var result = comment
            if let children = childrenByParent[comment.id] {
                result.replies = children.map { attachReplies(to: $0) }
            }
            return result
        }

        return topLevel.map { attachReplies(to: $0) }
    }
}
