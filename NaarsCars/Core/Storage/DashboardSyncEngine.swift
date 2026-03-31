//
//  DashboardSyncEngine.swift
//  NaarsCars
//
//  Sync engine for local-first dashboard and notifications
//

import Foundation
import SwiftData

@MainActor
final class DashboardSyncEngine: SyncEngineProtocol {
    static let shared = DashboardSyncEngine()
    let engineName = "dashboard"

    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let notificationService = NotificationService.shared
    private let authService = AuthService.shared

    private var modelContext: ModelContext?
    private var backgroundActor: BackgroundSyncActor?
    private var lastStartSyncAt: Date = .distantPast
    let health = SyncHealthMetrics()

    private init() {}

    /// Initialize with model context (SyncEngineProtocol conformance)
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Initialize the background actor for off-MainActor SwiftData writes
    func setupBackgroundActor(container: ModelContainer) {
        self.backgroundActor = BackgroundSyncActor(modelContainer: container)
    }

    /// Start syncing dashboard and notifications
    func startSync() {
        let now = Date()
        guard now.timeIntervalSince(lastStartSyncAt) >= Constants.Timing.syncEngineStartCooldown else {
            return
        }
        lastStartSyncAt = now

        Task {
            do {
                let metrics = try await performFullSync()
                RefreshCoordinator.shared.markSyncCompleted(.dashboard, metrics: metrics)
            } catch {
                RefreshCoordinator.shared.markSyncFailed(.dashboard, error: error, partial: nil)
            }
        }
    }

    func pauseSync() async {
        // No realtime subscriptions to manage anymore
        // In-flight tasks are managed by the coordinator
    }

    func resumeSync() async {
        // No realtime subscriptions to manage anymore
        // Coordinator handles refresh on foreground
    }

    func teardown() async {
        modelContext = nil
        backgroundActor = nil
        lastStartSyncAt = .distantPast
    }

    /// Sync all data from network to SwiftData
    func syncAll() async {
        guard let userId = authService.currentUserId else { return }

        do {
            // Parallel fetch
            async let ridesTask = rideService.fetchRides()
            async let favorsTask = favorService.fetchFavors()
            async let notificationsTask = notificationService.fetchNotifications(userId: userId, forceRefresh: true)

            let (rides, favors, notifications) = try await (ridesTask, favorsTask, notificationsTask)

            do {
                try await backgroundActor?.syncAll(rides: rides, favors: favors, notifications: notifications)
            } catch {
                AppLogger.error("sync", "[dashboard] SwiftData save failed: \(error)")
                CrashReportingService.shared.recordServiceError(error, operation: "save", service: "DashboardSyncEngine")
            }
            health.recordSuccess()
        } catch {
            AppLogger.error("sync", "Error during full sync: \(error)")
            health.recordFailure(error)
        }
    }

    // MARK: - Coordinator Entry Points

    /// Full network-to-SwiftData sync with change detection.
    /// Called by RefreshCoordinator for staleness-based and pull-to-refresh.
    func performFullSync() async throws -> RefreshMetrics {
        guard let userId = authService.currentUserId else { return .empty }

        async let ridesTask = rideService.fetchRides()
        async let favorsTask = favorService.fetchFavors()
        async let notificationsTask = notificationService.fetchNotifications(userId: userId, forceRefresh: true)

        let (rides, favors, notifications) = try await (ridesTask, favorsTask, notificationsTask)
        guard !Task.isCancelled else { throw CancellationError() }

        guard let backgroundActor else { return .empty }
        let metrics = try await backgroundActor.syncAllWithChangeDetection(
            rides: rides, favors: favors, notifications: notifications
        )

        if metrics.savedToStore {
            NotificationCenter.default.post(name: .ridesDidSync, object: nil)
            NotificationCenter.default.post(name: .favorsDidSync, object: nil)
            NotificationCenter.default.post(name: .notificationsDidSync, object: nil)
        }

        health.recordSuccess()
        return metrics
    }

    /// Targeted single-entity sync for push-triggered refresh.
    /// Tries ride first, then favor. Called by RefreshCoordinator.
    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics {
        guard let backgroundActor else { return .empty }

        // Try ride first
        if let ride = try? await rideService.fetchRide(id: entityId) {
            guard !Task.isCancelled else { throw CancellationError() }
            let metrics = try await backgroundActor.upsertRideWithChangeDetection(ride)
            if metrics.savedToStore {
                NotificationCenter.default.post(name: .ridesDidSync, object: nil)
            }
            health.recordSuccess()
            return metrics
        }

        // Try favor
        if let favor = try? await favorService.fetchFavor(id: entityId) {
            guard !Task.isCancelled else { throw CancellationError() }
            let metrics = try await backgroundActor.upsertFavorWithChangeDetection(favor)
            if metrics.savedToStore {
                NotificationCenter.default.post(name: .favorsDidSync, object: nil)
            }
            health.recordSuccess()
            return metrics
        }

        return .empty
    }
}
