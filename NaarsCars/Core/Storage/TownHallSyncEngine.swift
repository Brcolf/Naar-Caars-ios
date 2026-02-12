//
//  TownHallSyncEngine.swift
//  NaarsCars
//

import Foundation
import SwiftData
import Realtime

extension Notification.Name {
    static let townHallPostVotesDidChange = Notification.Name("townHallPostVotesDidChange")
    static let townHallCommentVotesDidChange = Notification.Name("townHallCommentVotesDidChange")
}

@MainActor
final class TownHallSyncEngine: SyncEngineProtocol {
    static let shared = TownHallSyncEngine()
    let engineName = "townHall"

    private let repository: TownHallRepository
    private let townHallService: TownHallService
    private let commentService: TownHallCommentService
    private let realtimeManager: RealtimeManager

    private var postsRefreshTask: Task<Void, Never>?
    private var commentRefreshTasks: [UUID: Task<Void, Never>] = [:]

    init(
        repository: TownHallRepository? = nil,
        townHallService: TownHallService? = nil,
        commentService: TownHallCommentService? = nil,
        realtimeManager: RealtimeManager? = nil
    ) {
        self.repository = repository ?? .shared
        self.townHallService = townHallService ?? .shared
        self.commentService = commentService ?? .shared
        self.realtimeManager = realtimeManager ?? .shared
    }

    func setup(modelContext: ModelContext) {
        repository.setup(modelContext: modelContext)
    }

    func startSync() {
        setupPostsSubscription()
        setupCommentsSubscription()
        setupVotesSubscription()
    }

    func pauseSync() async {
        postsRefreshTask?.cancel()
        postsRefreshTask = nil

        for task in commentRefreshTasks.values {
            task.cancel()
        }
        commentRefreshTasks.removeAll()

        await realtimeManager.unsubscribe(channelName: "town-hall-posts")
        await realtimeManager.unsubscribe(channelName: "town-hall-comments")
        await realtimeManager.unsubscribe(channelName: "town-hall-votes")
    }

    func resumeSync() async {
        setupPostsSubscription()
        setupCommentsSubscription()
        setupVotesSubscription()
    }

    func teardown() async {
        await pauseSync()
    }

    // MARK: - Subscriptions

    private func setupPostsSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "town-hall-posts",
                table: "town_hall_posts",
                onInsert: { [weak self] record in
                    Task { @MainActor in
                        self?.handlePostUpsert(record)
                    }
                },
                onUpdate: { [weak self] record in
                    Task { @MainActor in
                        self?.handlePostUpsert(record)
                    }
                },
                onDelete: { [weak self] record in
                    Task { @MainActor in
                        self?.handlePostDelete(record)
                    }
                }
            )
        }
    }

    private func setupCommentsSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "town-hall-comments",
                table: "town_hall_comments",
                onInsert: { [weak self] record in
                    Task { @MainActor in
                        self?.handleCommentUpsert(record)
                    }
                },
                onUpdate: { [weak self] record in
                    Task { @MainActor in
                        self?.handleCommentUpsert(record)
                    }
                },
                onDelete: { [weak self] record in
                    Task { @MainActor in
                        self?.handleCommentDelete(record)
                    }
                }
            )
        }
    }

    private func setupVotesSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "town-hall-votes",
                table: "town_hall_votes",
                onInsert: { [weak self] record in
                    self?.handleVoteChange(record)
                },
                onUpdate: { [weak self] record in
                    self?.handleVoteChange(record)
                },
                onDelete: { [weak self] record in
                    self?.handleVoteChange(record)
                }
            )
        }
    }

    // MARK: - Handlers

    private func handlePostUpsert(_ event: RealtimeRecord) {
        guard let post = TownHallPayloadMapper.parsePost(from: event.record) else {
            return
        }

        do {
            try repository.upsertPosts([post])
        } catch {
            AppLogger.error("sync", "Failed to upsert post: \(error)")
        }

        triggerPostsRefresh()
    }

    private func handlePostDelete(_ event: RealtimeRecord) {
        guard let id = TownHallPayloadMapper.parseUUID(event.record["id"]) else {
            return
        }

        do {
            try repository.deletePost(id: id)
        } catch {
            AppLogger.error("sync", "Failed to delete post: \(error)")
        }

        triggerPostsRefresh()
    }

    private func handleCommentUpsert(_ event: RealtimeRecord) {
        guard let comment = TownHallPayloadMapper.parseComment(from: event.record) else {
            return
        }

        do {
            try repository.upsertComments([comment])
        } catch {
            AppLogger.error("sync", "Failed to upsert comment: \(error)")
        }

        triggerCommentsRefresh(postId: comment.postId)
        triggerPostsRefresh()
    }

    private func handleCommentDelete(_ event: RealtimeRecord) {
        guard let id = TownHallPayloadMapper.parseUUID(event.record["id"]),
              let postId = TownHallPayloadMapper.parseUUID(event.record["post_id"]) else {
            return
        }

        do {
            try repository.deleteComment(id: id)
        } catch {
            AppLogger.error("sync", "Failed to delete comment: \(error)")
        }

        triggerCommentsRefresh(postId: postId)
        triggerPostsRefresh()
    }

    private func handleVoteChange(_ event: RealtimeRecord) {
        if let postId = TownHallPayloadMapper.parseUUID(event.record["post_id"]) {
            NotificationCenter.default.post(
                name: .townHallPostVotesDidChange,
                object: postId
            )
        }

        if let commentId = TownHallPayloadMapper.parseUUID(event.record["comment_id"]) {
            NotificationCenter.default.post(
                name: .townHallCommentVotesDidChange,
                object: commentId
            )
        }
    }

    // MARK: - Reconciliation

    private func triggerPostsRefresh() {
        postsRefreshTask?.cancel()
        postsRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let posts = try await townHallService.fetchPosts()
                try repository.upsertPosts(posts)
            } catch {
                AppLogger.error("sync", "Failed to refresh posts: \(error)")
            }
        }
    }

    private func triggerCommentsRefresh(postId: UUID) {
        commentRefreshTasks[postId]?.cancel()
        commentRefreshTasks[postId] = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let comments = try await commentService.fetchComments(for: postId)
                try repository.upsertComments(comments)
            } catch {
                AppLogger.error("sync", "Failed to refresh comments: \(error)")
            }
        }
    }
}

private enum TownHallPayloadMapper {
    static func parsePost(from record: [String: Any]) -> TownHallPost? {
        guard let id = parseUUID(record["id"]),
              let userId = parseUUID(record["user_id"]),
              let content = parseString(record["content"]) else {
            return nil
        }

        let createdAt = parseDate(record["created_at"]) ?? Date()
        let updatedAt = parseDate(record["updated_at"]) ?? createdAt

        return TownHallPost(
            id: id,
            userId: userId,
            content: content,
            imageUrl: parseString(record["image_url"]),
            title: parseString(record["title"]),
            pinned: parseBool(record["pinned"]),
            type: parseString(record["type"]).flatMap(PostType.init(rawValue:)),
            reviewId: parseUUID(record["review_id"]),
            createdAt: createdAt,
            updatedAt: updatedAt,
            author: nil,
            review: nil,
            commentCount: 0,
            upvotes: 0,
            downvotes: 0,
            userVote: nil
        )
    }

    static func parseComment(from record: [String: Any]) -> TownHallComment? {
        guard let id = parseUUID(record["id"]),
              let postId = parseUUID(record["post_id"]),
              let userId = parseUUID(record["user_id"]),
              let content = parseString(record["content"]) else {
            return nil
        }

        let createdAt = parseDate(record["created_at"]) ?? Date()
        let updatedAt = parseDate(record["updated_at"]) ?? createdAt

        return TownHallComment(
            id: id,
            postId: postId,
            userId: userId,
            parentCommentId: parseUUID(record["parent_comment_id"]),
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            author: nil,
            replies: nil,
            upvotes: 0,
            downvotes: 0,
            userVote: nil
        )
    }

    static func parseUUID(_ value: Any?) -> UUID? {
        let normalized = normalizeValue(value)
        if let uuidValue = normalized as? UUID { return uuidValue }
        if let nsuuidValue = normalized as? NSUUID { return nsuuidValue as UUID }
        if let stringValue = normalized as? String { return UUID(uuidString: stringValue) }
        if let nsStringValue = normalized as? NSString { return UUID(uuidString: nsStringValue as String) }
        return nil
    }

    static func parseString(_ value: Any?) -> String? {
        let normalized = normalizeValue(value)
        if let stringValue = normalized as? String { return stringValue }
        if let substringValue = normalized as? Substring { return String(substringValue) }
        if let nsStringValue = normalized as? NSString { return nsStringValue as String }
        return nil
    }

    static func parseBool(_ value: Any?) -> Bool? {
        let normalized = normalizeValue(value)
        if let boolValue = normalized as? Bool { return boolValue }
        if let numberValue = normalized as? NSNumber { return numberValue.boolValue }
        if let stringValue = normalized as? String {
            switch stringValue.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    static func parseDate(_ value: Any?) -> Date? {
        let normalized = normalizeValue(value)
        if let dateValue = normalized as? Date { return dateValue }
        if let stringValue = normalized as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: stringValue) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: stringValue)
        }
        if let numberValue = normalized as? NSNumber {
            let rawValue = numberValue.doubleValue
            if rawValue > 10_000_000_000 {
                return Date(timeIntervalSince1970: rawValue / 1000.0)
            }
            return Date(timeIntervalSince1970: rawValue)
        }
        return nil
    }

    private static func normalizeValue(_ value: Any?) -> Any? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let anyJSON = value as? AnyJSON {
            return decodeAnyJSON(anyJSON)
        }
        if type(of: value) == AnyHashable.self, let anyHashable = value as? AnyHashable {
            return normalizeValue(anyHashable.base)
        }
        return value
    }

    private static func decodeAnyJSON(_ anyJSON: AnyJSON) -> Any? {
        if let mirrorValue = decodeAnyJSONMirror(anyJSON) {
            return mirrorValue
        }
        guard let data = try? JSONEncoder().encode(anyJSON),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        if object is NSNull {
            return nil
        }
        return object
    }

    private static func decodeAnyJSONMirror(_ anyJSON: AnyJSON) -> Any? {
        let mirror = Mirror(reflecting: anyJSON)
        for child in mirror.children {
            if child.label == "value" {
                return child.value
            }
        }
        return nil
    }
}
