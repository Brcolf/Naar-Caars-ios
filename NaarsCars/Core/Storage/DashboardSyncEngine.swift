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
    private var ridesSyncTask: Task<Void, Never>?
    private var favorsSyncTask: Task<Void, Never>?
    private var notificationsSyncTask: Task<Void, Never>?
    private var lastStartSyncAt: Date = .distantPast
    let health = SyncHealthMetrics()

    private init() {}
    
    /// Initialize with model context
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
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
            
            if let context = modelContext {
                syncRides(rides, in: context)
                syncFavors(favors, in: context)
                syncNotifications(notifications, in: context)
                do {
                    try context.save()
                } catch {
                    AppLogger.error("sync", "[dashboard] SwiftData save failed: \(error)")
                    CrashReportingService.shared.recordServiceError(error, operation: "save", service: "DashboardSyncEngine")
                }
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
            if let rides = try? await rideService.fetchRides(), let context = modelContext {
                syncRides(rides, in: context)
                do {
                    try context.save()
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
            if let favors = try? await favorService.fetchFavors(), let context = modelContext {
                syncFavors(favors, in: context)
                do {
                    try context.save()
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
            if let notifications = try? await notificationService.fetchNotifications(userId: userId, forceRefresh: true),
               let context = modelContext {
                syncNotifications(notifications, in: context)
                do {
                    try context.save()
                } catch {
                    AppLogger.error("sync", "[dashboard] SwiftData save failed: \(error)")
                    CrashReportingService.shared.recordServiceError(error, operation: "save", service: "DashboardSyncEngine")
                }
                NotificationCenter.default.post(name: .notificationsDidSync, object: nil)
            }
        }
    }
    
    // MARK: - Sync Logic (Internal)
    
    private func syncRides(_ rides: [Ride], in context: ModelContext) {
        guard !rides.isEmpty else { return }

        // Single batch fetch: get ALL existing SDRides at once
        let allLocalDescriptor = FetchDescriptor<SDRide>()
        let allLocal = (try? context.fetch(allLocalDescriptor)) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        let serverIds = Set(rides.map { $0.id })

        // Upsert
        for ride in rides {
            if let existing = existingById[ride.id] {
                updateSDRide(existing, with: ride)
            } else {
                let sdRide = SDRide(
                    id: ride.id,
                    userId: ride.userId,
                    type: ride.type,
                    date: ride.date,
                    time: ride.time,
                    pickup: ride.pickup,
                    destination: ride.destination,
                    seats: ride.seats,
                    notes: ride.notes,
                    gift: ride.gift,
                    status: ride.status.rawValue,
                    claimedBy: ride.claimedBy,
                    reviewed: ride.reviewed,
                    reviewSkipped: ride.reviewSkipped,
                    reviewSkippedAt: ride.reviewSkippedAt,
                    estimatedCost: ride.estimatedCost,
                    flightNormalized: ride.flightNormalized,
                    createdAt: ride.createdAt,
                    updatedAt: ride.updatedAt,
                    posterName: ride.poster?.name,
                    posterAvatarUrl: ride.poster?.avatarUrl,
                    claimerName: ride.claimer?.name,
                    claimerAvatarUrl: ride.claimer?.avatarUrl,
                    participantIds: ride.participants?.map { $0.id } ?? [],
                    qaCount: ride.qaCount ?? 0
                )
                context.insert(sdRide)
            }
        }

        // Delete stale (reuse allLocal from batch fetch)
        for local in allLocal where !serverIds.contains(local.id) {
            context.delete(local)
        }
    }
    
    private func syncFavors(_ favors: [Favor], in context: ModelContext) {
        guard !favors.isEmpty else { return }

        // Single batch fetch: get ALL existing SDFavors at once
        let allLocalDescriptor = FetchDescriptor<SDFavor>()
        let allLocal = (try? context.fetch(allLocalDescriptor)) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        let serverIds = Set(favors.map { $0.id })

        // Upsert
        for favor in favors {
            if let existing = existingById[favor.id] {
                updateSDFavor(existing, with: favor)
            } else {
                let sdFavor = SDFavor(
                    id: favor.id,
                    userId: favor.userId,
                    title: favor.title,
                    favorDescription: favor.description,
                    location: favor.location,
                    duration: favor.duration.rawValue,
                    requirements: favor.requirements,
                    date: favor.date,
                    time: favor.time,
                    gift: favor.gift,
                    status: favor.status.rawValue,
                    claimedBy: favor.claimedBy,
                    reviewed: favor.reviewed,
                    reviewSkipped: favor.reviewSkipped,
                    reviewSkippedAt: favor.reviewSkippedAt,
                    createdAt: favor.createdAt,
                    updatedAt: favor.updatedAt,
                    posterName: favor.poster?.name,
                    posterAvatarUrl: favor.poster?.avatarUrl,
                    claimerName: favor.claimer?.name,
                    claimerAvatarUrl: favor.claimer?.avatarUrl,
                    participantIds: favor.participants?.map { $0.id } ?? [],
                    qaCount: favor.qaCount ?? 0
                )
                context.insert(sdFavor)
            }
        }

        // Delete stale (reuse allLocal from batch fetch)
        for local in allLocal where !serverIds.contains(local.id) {
            context.delete(local)
        }
    }
    
    private func syncNotifications(_ notifications: [AppNotification], in context: ModelContext) {
        guard !notifications.isEmpty else { return }

        // Single batch fetch: get ALL existing SDNotifications at once
        let allLocalDescriptor = FetchDescriptor<SDNotification>()
        let allLocal = (try? context.fetch(allLocalDescriptor)) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        // Upsert
        for notification in notifications {
            if let existing = existingById[notification.id] {
                existing.read = notification.read
                existing.pinned = notification.pinned
                existing.title = notification.title
                existing.body = notification.body
            } else {
                let sd = SDNotification(
                    id: notification.id,
                    userId: notification.userId,
                    type: notification.type.rawValue,
                    title: notification.title,
                    body: notification.body,
                    read: notification.read,
                    pinned: notification.pinned,
                    createdAt: notification.createdAt,
                    rideId: notification.rideId,
                    favorId: notification.favorId,
                    conversationId: notification.conversationId,
                    reviewId: notification.reviewId,
                    townHallPostId: notification.townHallPostId,
                    sourceUserId: notification.sourceUserId
                )
                context.insert(sd)
            }
        }
    }
    
    private func updateSDRide(_ sd: SDRide, with ride: Ride) {
        sd.status = ride.status.rawValue
        sd.claimedBy = ride.claimedBy
        sd.updatedAt = ride.updatedAt
        sd.qaCount = ride.qaCount ?? 0
        sd.date = ride.date
        sd.time = ride.time
        sd.pickup = ride.pickup
        sd.destination = ride.destination
        sd.seats = ride.seats
        sd.notes = ride.notes
        sd.gift = ride.gift
        sd.reviewed = ride.reviewed
        sd.reviewSkipped = ride.reviewSkipped
        sd.reviewSkippedAt = ride.reviewSkippedAt
        sd.estimatedCost = ride.estimatedCost
        sd.flightNormalized = ride.flightNormalized
        sd.posterName = ride.poster?.name
        sd.posterAvatarUrl = ride.poster?.avatarUrl
        sd.claimerName = ride.claimer?.name
        sd.claimerAvatarUrl = ride.claimer?.avatarUrl
        sd.participantIds = ride.participants?.map { $0.id } ?? []
    }
    
    private func updateSDFavor(_ sd: SDFavor, with favor: Favor) {
        sd.status = favor.status.rawValue
        sd.claimedBy = favor.claimedBy
        sd.updatedAt = favor.updatedAt
        sd.qaCount = favor.qaCount ?? 0
        sd.title = favor.title
        sd.favorDescription = favor.description
        sd.location = favor.location
        sd.duration = favor.duration.rawValue
        sd.requirements = favor.requirements
        sd.date = favor.date
        sd.time = favor.time
        sd.gift = favor.gift
        sd.reviewed = favor.reviewed
        sd.reviewSkipped = favor.reviewSkipped
        sd.reviewSkippedAt = favor.reviewSkippedAt
        sd.posterName = favor.poster?.name
        sd.posterAvatarUrl = favor.poster?.avatarUrl
        sd.claimerName = favor.claimer?.name
        sd.claimerAvatarUrl = favor.claimer?.avatarUrl
        sd.participantIds = favor.participants?.map { $0.id } ?? []
    }
}
