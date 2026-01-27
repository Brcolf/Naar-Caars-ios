//
//  TownHallRepository.swift
//  NaarsCars
//

import Foundation
import SwiftData
import SwiftUI
import CoreData
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

    func getPostsPublisher() -> AnyPublisher<[TownHallPost], Never> {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: RunLoop.main)
            .map { _ in (try? self.getPosts()) ?? [] }
            .eraseToAnyPublisher()
    }

    func upsertPosts(_ posts: [TownHallPost]) throws {
        guard let modelContext = modelContext else { return }

        for post in posts {
            let id = post.id
            let fetchDescriptor = FetchDescriptor<SDTownHallPost>(predicate: #Predicate { $0.id == id })
            if let existing = try modelContext.fetch(fetchDescriptor).first {
                update(existing, with: post)
            } else {
                let sdPost = mapToSDTownHallPost(post)
                modelContext.insert(sdPost)
            }
        }

        try modelContext.save()
    }

    func deletePost(id: UUID) throws {
        guard let modelContext = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<SDTownHallPost>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
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

    func getCommentsPublisher(postId: UUID) -> AnyPublisher<[TownHallComment], Never> {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: RunLoop.main)
            .map { _ in (try? self.getComments(postId: postId)) ?? [] }
            .eraseToAnyPublisher()
    }

    func upsertComments(_ comments: [TownHallComment]) throws {
        guard let modelContext = modelContext else { return }

        let flattened = flattenComments(comments)
        for comment in flattened {
            let id = comment.id
            let fetchDescriptor = FetchDescriptor<SDTownHallComment>(predicate: #Predicate { $0.id == id })
            if let existing = try modelContext.fetch(fetchDescriptor).first {
                update(existing, with: comment)
            } else {
                let sdComment = mapToSDTownHallComment(comment)
                modelContext.insert(sdComment)
            }
        }

        try modelContext.save()
    }

    func deleteComment(id: UUID) throws {
        guard let modelContext = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<SDTownHallComment>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
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
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
            authorName: post.author?.name,
            authorAvatarUrl: post.author?.avatarUrl,
            commentCount: post.commentCount
        )
    }

    private func update(_ sdPost: SDTownHallPost, with post: TownHallPost) {
        sdPost.title = post.title
        sdPost.content = post.content
        sdPost.imageUrl = post.imageUrl
        sdPost.pinned = post.pinned ?? false
        sdPost.type = post.type?.rawValue
        sdPost.reviewId = post.reviewId
        sdPost.createdAt = post.createdAt
        sdPost.updatedAt = post.updatedAt
        sdPost.authorName = post.author?.name
        sdPost.authorAvatarUrl = post.author?.avatarUrl
        sdPost.commentCount = post.commentCount
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
            createdAt: comment.createdAt,
            updatedAt: comment.updatedAt,
            authorName: comment.author?.name,
            authorAvatarUrl: comment.author?.avatarUrl
        )
    }

    private func update(_ sdComment: SDTownHallComment, with comment: TownHallComment) {
        sdComment.postId = comment.postId
        sdComment.userId = comment.userId
        sdComment.parentCommentId = comment.parentCommentId
        sdComment.content = comment.content
        sdComment.createdAt = comment.createdAt
        sdComment.updatedAt = comment.updatedAt
        sdComment.authorName = comment.author?.name
        sdComment.authorAvatarUrl = comment.author?.avatarUrl
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
        var commentMap: [UUID: TownHallComment] = [:]
        for comment in comments {
            commentMap[comment.id] = comment
        }

        var topLevel: [TownHallComment] = []
        var processedIds = Set<UUID>()

        for comment in comments {
            guard !processedIds.contains(comment.id) else { continue }
            if let parentId = comment.parentCommentId {
                if var parent = commentMap[parentId] {
                    if parent.replies == nil {
                        parent.replies = []
                    }
                    parent.replies?.append(comment)
                    commentMap[parentId] = parent
                    processedIds.insert(comment.id)
                }
            } else {
                var commentWithReplies = comment
                commentWithReplies.replies = buildReplies(for: comment.id, in: commentMap, processedIds: &processedIds)
                topLevel.append(commentWithReplies)
                processedIds.insert(comment.id)
            }
        }

        return topLevel
    }

    private func buildReplies(
        for parentId: UUID,
        in commentMap: [UUID: TownHallComment],
        processedIds: inout Set<UUID>
    ) -> [TownHallComment]? {
        var replies: [TownHallComment] = []
        for (id, comment) in commentMap {
            if comment.parentCommentId == parentId, !processedIds.contains(id) {
                var commentWithReplies = comment
                commentWithReplies.replies = buildReplies(for: id, in: commentMap, processedIds: &processedIds)
                replies.append(commentWithReplies)
                processedIds.insert(id)
            }
        }
        return replies.isEmpty ? nil : replies
    }
}
