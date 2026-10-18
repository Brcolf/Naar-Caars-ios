//
//  TownHallSyncEngine.swift
//  NaarsCars
//

import Foundation
import SwiftData

@MainActor
final class TownHallSyncEngine: SyncEngineProtocol {
    static let shared = TownHallSyncEngine()
    let engineName = "townHall"

    private let repository: TownHallRepository
    private let postFetcher: any TownHallPostFetching
    private let commentService: TownHallCommentService
    /// The community a full sync fetches (nil = no community filter).
    private let communityScope: @MainActor () -> UUID?
    private var backgroundActor: BackgroundSyncActor?

    let health = SyncHealthMetrics()

    /// - Parameter communityScope: nil reads the Community tab's community from
    ///   `CommunityContext.shared`.
    init(
        repository: TownHallRepository? = nil,
        postFetcher: (any TownHallPostFetching)? = nil,
        commentService: TownHallCommentService? = nil,
        communityScope: (@MainActor () -> UUID?)? = nil
    ) {
        self.repository = repository ?? .shared
        self.postFetcher = postFetcher ?? TownHallService.shared
        self.commentService = commentService ?? .shared
        self.communityScope = communityScope ?? { CommunityContext.shared.communityTabId }
    }

    func setup(modelContext: ModelContext) {
        repository.setup(modelContext: modelContext)
    }

    func setupBackgroundActor(container: ModelContainer) {
        backgroundActor = BackgroundSyncActor(modelContainer: container)
    }

    /// Session-start hook (SyncEngineProtocol). Setup only — must not fetch.
    /// Initial hydration is owned by RefreshCoordinator
    /// (`refreshIfNeeded(.townHall, trigger: "launch")` → `performFullSync()`).
    func startSync() {
        // Nothing to set up — this engine has no workers or subscriptions.
    }

    /// Session teardown (sign-out). The container-scoped `backgroundActor` is kept
    /// because nothing re-runs `setupBackgroundActor` on the next sign-in.
    func teardown() async {
        // No session-scoped work to cancel here.
    }

    // MARK: - Coordinator Entry Points

    func performFullSync() async throws -> RefreshMetrics {
        // Read once, at fetch start: a switch made while this sync runs is reconciled by the feed,
        // which ignores an emission stamped with another scope.
        let communityId = communityScope()
        let syncScope = TownHallSyncScope(communityId: communityId)
        let posts = try await postFetcher.fetchPostsPage(
            limit: Constants.PageSizes.townHall, offset: 0, communityId: communityId
        ).posts
        guard !Task.isCancelled else { throw CancellationError() }
        guard let backgroundActor else {
            try repository.upsertPosts(posts, replaceAll: true, syncScope: syncScope)
            health.recordSuccess()
            return .empty
        }
        // Prunes every local post absent from this page: the store holds the first page of the
        // scope synced last.
        let metrics = try await backgroundActor.syncPostsWithChangeDetection(posts)
        // Posted ONLY after a successful BackgroundSyncActor save; TownHallRepository's posts
        // publisher re-reads SwiftData on it (same contract as DashboardSyncEngine's *DidSync).
        if metrics.savedToStore {
            NotificationCenter.default.post(
                name: .townHallPostsDidSync,
                object: nil,
                userInfo: [TownHallSyncScope.userInfoKey: syncScope]
            )
        }
        health.recordSuccess()
        return metrics
    }

    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics {
        let fetched = try await postFetcher.fetchPost(id: entityId)
        guard !Task.isCancelled else { throw CancellationError() }
        guard let post = fetched else {
            // Not readable (hidden, deleted, another community, a forwarded push, a blocked
            // author): drop the cached row if there is one and succeed. Never throw here, or
            // the coordinator would put the whole .townHall domain into backoff.
            return await deleteUnreadablePost(id: entityId)
        }
        guard let backgroundActor else {
            try repository.upsertPosts([post])
            health.recordSuccess()
            return .empty
        }
        let metrics = try await backgroundActor.upsertPostWithChangeDetection(post)
        if metrics.savedToStore {
            NotificationCenter.default.post(name: .townHallPostsDidSync, object: nil)
        }
        health.recordSuccess()
        return metrics
    }

    /// Removes the cached copy of a post the server no longer returns. Does not throw: a
    /// local delete failure is logged and the refresh still counts as a success (the next full
    /// sync prunes the row anyway).
    private func deleteUnreadablePost(id: UUID) async -> RefreshMetrics {
        defer { health.recordSuccess() }
        do {
            guard let backgroundActor else {
                // The repository posts .townHallPostsDidSync itself, only when it deleted a row.
                try repository.deletePost(id: id)
                return .empty
            }
            let metrics = try await backgroundActor.deletePostWithChangeDetection(id: id)
            if metrics.recordsDeleted > 0 {
                NotificationCenter.default.post(name: .townHallPostsDidSync, object: nil)
            }
            return metrics
        } catch {
            AppLogger.error("townhall", "Could not drop unreadable post \(id) from the cache: \(error.localizedDescription)")
            return .empty
        }
    }
}
