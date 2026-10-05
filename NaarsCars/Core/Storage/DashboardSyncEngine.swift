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

    /// Session-start hook (SyncEngineProtocol). Setup only — must not fetch.
    /// Initial hydration is owned by RefreshCoordinator, which calls
    /// `performFullSync()` via `refreshIfNeeded(.dashboard, trigger: "launch")`
    /// so the launch fetch participates in in-flight dedup.
    func startSync() {
        // Nothing to set up — this engine has no workers or subscriptions.
    }

    /// Session teardown (sign-out). The ModelContainer outlives the session, so the
    /// container-scoped `modelContext` and `backgroundActor` are kept: nothing re-runs
    /// `setup`/`setupBackgroundActor` on the next sign-in, and dropping them would make
    /// every later `performFullSync()` return `.empty` without saving.
    func teardown() async {
        // No session-scoped work to cancel here; RefreshCoordinator.reset() cancels
        // in-flight refreshes and AuthService wipes the SwiftData cache.
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
        // Guests have no session: rides/favors are still readable (anon RLS, open items only) but
        // notifications are not. Fetch the public data and skip only the notifications call, instead
        // of skipping the whole sync — the Requests tab reads the SwiftData this populates.
        let userId = authService.currentUserId

        async let ridesTask = rideService.fetchRides()
        async let favorsTask = favorService.fetchFavors()
        async let notificationsTask = fetchNotificationsIfAuthenticated(userId)

        let (rides, favors, notifications) = try await (ridesTask, favorsTask, notificationsTask)
        guard !Task.isCancelled else { throw CancellationError() }

        guard let backgroundActor else { return .empty }
        let result = try await backgroundActor.syncAllWithChangeDetection(
            rides: rides, favors: favors, notifications: notifications,
            // Guests fetched no notifications (empty array above); nil keeps that a no-op.
            notificationPruneHorizon: userId == nil ? nil : notificationPruneHorizon
        )
        let metrics = result.metrics

        // Posted ONLY after a successful BackgroundSyncActor save, and only for the entity sets that
        // actually changed. Observers (RequestRealtimeHandler, NotificationRealtimeHandler) must
        // re-read SwiftData only — never fetch from the network — otherwise every coordinator-driven
        // sync would trigger a second full fetch.
        if result.ridesChanged {
            NotificationCenter.default.post(name: .ridesDidSync, object: nil)
        }
        if result.favorsChanged {
            NotificationCenter.default.post(name: .favorsDidSync, object: nil)
        }
        if result.notificationsChanged {
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

    /// Notifications require a session. For guests (nil userId) return an empty set so the public
    /// rides/favors reconciliation still runs. `BackgroundSyncActor.syncAllWithChangeDetection` only
    /// deletes notifications when a prune horizon is passed (never for guests), so an empty array is
    /// a no-op for the notifications table.
    private func fetchNotificationsIfAuthenticated(_ userId: UUID?) async throws -> [AppNotification] {
        guard let userId else { return [] }
        return try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
    }

    /// Read notifications older than this are pruned from SwiftData when the server no longer returns
    /// them. One day beyond `NotificationService.fetchHorizonDays` so the local window is never
    /// narrower than the server's (`fetchNotifications` computes its horizon at a different instant).
    /// Nil (calendar failure) skips pruning.
    private var notificationPruneHorizon: Date? {
        Calendar.current.date(byAdding: .day, value: -(NotificationService.fetchHorizonDays + 1), to: Date())
    }
}
