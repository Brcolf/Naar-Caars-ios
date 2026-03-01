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

    // MARK: - Subscriptions

    private func setupRidesSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "rides:sync",
                table: "rides",
                onInsert: { [weak self] _ in self?.triggerRidesSync() },
                onUpdate: { [weak self] _ in self?.triggerRidesSync() },
                onDelete: { [weak self] _ in self?.triggerRidesSync() }
            )
        }
    }

    private func setupFavorsSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "favors:sync",
                table: "favors",
                onInsert: { [weak self] _ in self?.triggerFavorsSync() },
                onUpdate: { [weak self] _ in self?.triggerFavorsSync() },
                onDelete: { [weak self] _ in self?.triggerFavorsSync() }
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
                onInsert: { [weak self] _ in self?.triggerNotificationsSync() },
                onUpdate: { [weak self] _ in self?.triggerNotificationsSync() },
                onDelete: { [weak self] _ in self?.triggerNotificationsSync() }
            )
        }
    }

    // MARK: - Sync Triggers

    private func triggerRidesSync() {
        ridesSyncTask?.cancel()
        ridesSyncTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
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
            try? await Task.sleep(nanoseconds: 500_000_000)
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
            try? await Task.sleep(nanoseconds: 500_000_000)
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
}
