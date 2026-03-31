//
//  DashboardSyncEngine.swift
//  NaarsCars
//
//  Sync engine for local-first dashboard and notifications
//

import Foundation
import SwiftData
import Realtime

@MainActor
final class DashboardSyncEngine: SyncEngineProtocol {
    static let shared = DashboardSyncEngine()
    let engineName = "dashboard"

    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let notificationService = NotificationService.shared
    private let realtimeManager = RealtimeManager.shared
    private let authService = AuthService.shared

    private var modelContext: ModelContext?
    private var backgroundActor: BackgroundSyncActor?
    private var ridesSyncTask: Task<Void, Never>?
    private var favorsSyncTask: Task<Void, Never>?
    private var notificationsSyncTask: Task<Void, Never>?
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
        setupRidesSubscription()
        setupFavorsSubscription()
        setupNotificationsSubscription()

        let now = Date()
        guard now.timeIntervalSince(lastStartSyncAt) >= Constants.Timing.syncEngineStartCooldown else {
            return
        }
        lastStartSyncAt = now

        // Initial sync (coalesced so duplicate startSync calls don't stampede the network)
        Task {
            await syncAll()
        }
    }

    func pauseSync() async {
        ridesSyncTask?.cancel()
        favorsSyncTask?.cancel()
        notificationsSyncTask?.cancel()
        ridesSyncTask = nil
        favorsSyncTask = nil
        notificationsSyncTask = nil

        await realtimeManager.unsubscribe(channelName: "rides:sync")
        await realtimeManager.unsubscribe(channelName: "favors:sync")
        await realtimeManager.unsubscribe(channelName: "notifications:sync")
    }

    func resumeSync() async {
        setupRidesSubscription()
        setupFavorsSubscription()
        setupNotificationsSubscription()
    }

    func teardown() async {
        await pauseSync()
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

    /// TEMPORARY STUB — will be replaced in Task 7
    /// Called by RefreshCoordinator to perform a full network-to-SwiftData sync.
    func performFullSync() async throws -> RefreshMetrics {
        await syncAll()
        return .empty
    }

    /// TEMPORARY STUB — will be replaced in Task 7
    /// Called by RefreshCoordinator to sync a single entity by ID.
    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics {
        await syncAll()
        return .empty
    }

    // MARK: - Subscriptions

    private func setupRidesSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "rides:sync",
                table: "rides",
                onInsert: { [weak self] event in self?.handleRideUpsert(event) },
                onUpdate: { [weak self] event in self?.handleRideUpsert(event) },
                onDelete: { [weak self] event in self?.handleRideDelete(event) }
            )
        }
    }

    private func setupFavorsSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "favors:sync",
                table: "favors",
                onInsert: { [weak self] event in self?.handleFavorUpsert(event) },
                onUpdate: { [weak self] event in self?.handleFavorUpsert(event) },
                onDelete: { [weak self] event in self?.handleFavorDelete(event) }
            )
        }
    }

    private func setupNotificationsSubscription() {
        Task {
            guard let userId = authService.currentUserId else { return }
            let userFilter = "user_id=eq.\(userId.uuidString)"
            await realtimeManager.subscribe(
                channelName: "notifications:sync",
                table: "notifications",
                filter: userFilter,
                onInsert: { [weak self] event in self?.handleNotificationUpsert(event) },
                onUpdate: { [weak self] event in self?.handleNotificationUpsert(event) },
                onDelete: { [weak self] event in self?.handleNotificationDelete(event) }
            )
        }
    }

    // MARK: - Sync Triggers

    // Debounce interval: 2 seconds allows multiple rapid events to coalesce into a single fetch
    private let syncDebounceNanos: UInt64 = 2_000_000_000

    private func triggerRidesSync() {
        ridesSyncTask?.cancel()
        ridesSyncTask = Task {
            try? await Task.sleep(nanoseconds: syncDebounceNanos)
            guard !Task.isCancelled else { return }
            if let rides = try? await rideService.fetchRides() {
                do {
                    try await backgroundActor?.syncRides(rides)
                } catch {
                    AppLogger.error("sync", "[dashboard] SwiftData save failed: \(error)")
                    CrashReportingService.shared.recordServiceError(error, operation: "save", service: "DashboardSyncEngine")
                }
                NotificationCenter.default.post(name: .ridesDidSync, object: nil)
            }
        }
    }

    private func triggerFavorsSync() {
        favorsSyncTask?.cancel()
        favorsSyncTask = Task {
            try? await Task.sleep(nanoseconds: syncDebounceNanos)
            guard !Task.isCancelled else { return }
            if let favors = try? await favorService.fetchFavors() {
                do {
                    try await backgroundActor?.syncFavors(favors)
                } catch {
                    AppLogger.error("sync", "[dashboard] SwiftData save failed: \(error)")
                    CrashReportingService.shared.recordServiceError(error, operation: "save", service: "DashboardSyncEngine")
                }
                NotificationCenter.default.post(name: .favorsDidSync, object: nil)
            }
        }
    }

    private func triggerNotificationsSync() {
        notificationsSyncTask?.cancel()
        notificationsSyncTask = Task {
            try? await Task.sleep(nanoseconds: syncDebounceNanos)
            guard !Task.isCancelled, let userId = authService.currentUserId else { return }
            if let notifications = try? await notificationService.fetchNotifications(userId: userId, forceRefresh: true) {
                do {
                    try await backgroundActor?.syncNotifications(notifications)
                } catch {
                    AppLogger.error("sync", "[dashboard] SwiftData save failed: \(error)")
                    CrashReportingService.shared.recordServiceError(error, operation: "save", service: "DashboardSyncEngine")
                }
                NotificationCenter.default.post(name: .notificationsDidSync, object: nil)
            }
        }
    }

    // MARK: - Incremental Notification Handlers

    /// Handle notification insert/update from realtime — upsert locally without full refetch.
    /// Falls back to debounced full sync if payload parsing fails.
    private func handleNotificationUpsert(_ event: RealtimeRecord) {
        guard let notification = NotificationPayloadMapper.notification(from: event) else {
            triggerNotificationsSync()
            return
        }
        Task {
            do {
                try await backgroundActor?.upsertNotification(notification)
                NotificationCenter.default.post(name: .notificationsDidSync, object: nil)
            } catch {
                triggerNotificationsSync()
            }
        }
    }

    /// Handle notification deletion from realtime — delete locally without full refetch.
    private func handleNotificationDelete(_ event: RealtimeRecord) {
        guard let id = NotificationPayloadMapper.notificationId(fromDeleteEvent: event) else {
            triggerNotificationsSync()
            return
        }
        Task {
            do {
                try await backgroundActor?.deleteNotification(id: id)
                NotificationCenter.default.post(name: .notificationsDidSync, object: nil)
            } catch {
                triggerNotificationsSync()
            }
        }
    }

    // MARK: - Incremental Upsert Handlers

    /// Handle ride insert/update from realtime — upsert locally without full refetch.
    /// Falls back to debounced full sync if payload parsing fails.
    private func handleRideUpsert(_ event: RealtimeRecord) {
        guard let ride = DashboardPayloadMapper.ride(from: event) else {
            triggerRidesSync()
            return
        }
        Task {
            do {
                try await backgroundActor?.upsertRide(ride)
                NotificationCenter.default.post(name: .ridesDidSync, object: nil)
            } catch {
                triggerRidesSync()
            }
        }
    }

    /// Handle favor insert/update from realtime — upsert locally without full refetch.
    /// Falls back to debounced full sync if payload parsing fails.
    private func handleFavorUpsert(_ event: RealtimeRecord) {
        guard let favor = DashboardPayloadMapper.favor(from: event) else {
            triggerFavorsSync()
            return
        }
        Task {
            do {
                try await backgroundActor?.upsertFavor(favor)
                NotificationCenter.default.post(name: .favorsDidSync, object: nil)
            } catch {
                triggerFavorsSync()
            }
        }
    }

    // MARK: - Local Delete Handlers

    /// Handle ride deletion from realtime — delete locally without full refetch
    private func handleRideDelete(_ event: RealtimeRecord) {
        guard let idString = event.oldRecord?["id"] as? String ?? event.record["id"] as? String,
              let id = UUID(uuidString: idString) else {
            triggerRidesSync()
            return
        }
        Task {
            do {
                try await backgroundActor?.deleteRide(id: id)
                NotificationCenter.default.post(name: .ridesDidSync, object: nil)
            } catch {
                triggerRidesSync()
            }
        }
    }

    /// Handle favor deletion from realtime — delete locally without full refetch
    private func handleFavorDelete(_ event: RealtimeRecord) {
        guard let idString = event.oldRecord?["id"] as? String ?? event.record["id"] as? String,
              let id = UUID(uuidString: idString) else {
            triggerFavorsSync()
            return
        }
        Task {
            do {
                try await backgroundActor?.deleteFavor(id: id)
                NotificationCenter.default.post(name: .favorsDidSync, object: nil)
            } catch {
                triggerFavorsSync()
            }
        }
    }
}
