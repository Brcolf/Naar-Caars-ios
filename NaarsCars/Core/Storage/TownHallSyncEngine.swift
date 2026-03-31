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

    func startSync() {
        Task {
            do {
                let metrics = try await performFullSync()
                RefreshCoordinator.shared.markSyncCompleted(.townHall, metrics: metrics)
            } catch {
                RefreshCoordinator.shared.markSyncFailed(.townHall, error: error, partial: nil)
            }
        }
    }

    func pauseSync() async { }

    func resumeSync() async { }

    func teardown() async {
        backgroundActor = nil
    }

    // MARK: - Coordinator Entry Points

    func performFullSync() async throws -> RefreshMetrics {
        let posts = try await townHallService.fetchPosts()
        guard !Task.isCancelled else { throw CancellationError() }
        guard let backgroundActor else {
            try repository.upsertPosts(posts)
            health.recordSuccess()
            return .empty
        }
        let metrics = try await backgroundActor.syncPostsWithChangeDetection(posts)
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
        health.recordSuccess()
        return metrics
    }
}
