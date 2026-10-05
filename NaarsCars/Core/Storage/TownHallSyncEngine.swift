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
    private let townHallService: TownHallService
    private let commentService: TownHallCommentService
    private var backgroundActor: BackgroundSyncActor?

    let health = SyncHealthMetrics()

    init(
        repository: TownHallRepository? = nil,
        townHallService: TownHallService? = nil,
        commentService: TownHallCommentService? = nil
    ) {
        self.repository = repository ?? .shared
        self.townHallService = townHallService ?? .shared
        self.commentService = commentService ?? .shared
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
        let posts = try await townHallService.fetchPosts()
        guard !Task.isCancelled else { throw CancellationError() }
        guard let backgroundActor else {
            try repository.upsertPosts(posts, replaceAll: true)
            health.recordSuccess()
            return .empty
        }
        let metrics = try await backgroundActor.syncPostsWithChangeDetection(posts)
        // Posted ONLY after a successful BackgroundSyncActor save; TownHallRepository's posts
        // publisher re-reads SwiftData on it (same contract as DashboardSyncEngine's *DidSync).
        if metrics.savedToStore {
            NotificationCenter.default.post(name: .townHallPostsDidSync, object: nil)
        }
        health.recordSuccess()
        return metrics
    }

    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics {
        let post = try await townHallService.fetchPost(id: entityId)
        guard !Task.isCancelled else { throw CancellationError() }
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
}
