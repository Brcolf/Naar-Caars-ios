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
final class DashboardSyncEngine {
    static let shared = DashboardSyncEngine()
    
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let notificationService = NotificationService.shared
    private let realtimeManager = RealtimeManager.shared
    private let authService = AuthService.shared
    
    private var modelContext: ModelContext?
    private var ridesSyncTask: Task<Void, Never>?
    private var favorsSyncTask: Task<Void, Never>?
    private var notificationsSyncTask: Task<Void, Never>?
    
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
        
        // Initial sync
        Task {
            await syncAll()
        }
    }
    
    /// Sync all data from network to SwiftData
    func syncAll() async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            // Parallel fetch
            async let ridesTask = rideService.fetchRides(forceRefresh: true)
            async let favorsTask = favorService.fetchFavors(forceRefresh: true)
            async let notificationsTask = notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            
            let (rides, favors, notifications) = try await (ridesTask, favorsTask, notificationsTask)
            
            if let context = modelContext {
                syncRides(rides, in: context)
                syncFavors(favors, in: context)
                syncNotifications(notifications, in: context)
                try? context.save()
            }
        } catch {
            print("🔴 [DashboardSyncEngine] Error during full sync: \(error)")
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
            if let rides = try? await rideService.fetchRides(forceRefresh: true), let context = modelContext {
                syncRides(rides, in: context)
                try? context.save()
            }
        }
    }
    
    private func triggerFavorsSync() {
        favorsSyncTask?.cancel()
        favorsSyncTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            if let favors = try? await favorService.fetchFavors(forceRefresh: true), let context = modelContext {
                syncFavors(favors, in: context)
                try? context.save()
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
                try? context.save()
            }
        }
    }
    
    // MARK: - Sync Logic (Internal)
    
    private func syncRides(_ rides: [Ride], in context: ModelContext) {
        for ride in rides {
            let id = ride.id
            let fetchDescriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
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
                    createdAt: ride.createdAt,
                    updatedAt: ride.updatedAt,
                    posterName: ride.poster?.name,
                    posterAvatarUrl: ride.poster?.avatarUrl,
                    claimerName: ride.claimer?.name,
                    claimerAvatarUrl: ride.claimer?.avatarUrl,
                    qaCount: ride.qaCount ?? 0
                )
                context.insert(sdRide)
            }
        }
    }
    
    private func syncFavors(_ favors: [Favor], in context: ModelContext) {
        for favor in favors {
            let id = favor.id
            let fetchDescriptor = FetchDescriptor<SDFavor>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
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
                    qaCount: favor.qaCount ?? 0
                )
                context.insert(sdFavor)
            }
        }
    }
    
    private func syncNotifications(_ notifications: [AppNotification], in context: ModelContext) {
        for notification in notifications {
            let id = notification.id
            let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
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
        sd.posterName = ride.poster?.name
        sd.posterAvatarUrl = ride.poster?.avatarUrl
        sd.claimerName = ride.claimer?.name
        sd.claimerAvatarUrl = ride.claimer?.avatarUrl
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
    }
}

