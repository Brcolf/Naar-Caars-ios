//
//  RequestsDashboardViewModel.swift
//  NaarsCars
//
//  ViewModel for unified requests dashboard (rides + favors)
//

import Foundation
import SwiftData
internal import Combine
import Realtime

/// ViewModel for unified requests dashboard
@MainActor
final class RequestsDashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var filter: RequestFilter = .open
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var unseenRequestKeys: Set<String> = []
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let authService = AuthService.shared
    private let notificationService = NotificationService.shared
    private let realtimeManager = RealtimeManager.shared
    private let badgeManager = BadgeCountManager.shared
    
    // MARK: - Lifecycle
    
    deinit {
        // Use Task.detached to clean up subscriptions without capturing self
        Task.detached {
            await RealtimeManager.shared.unsubscribe(channelName: "requests-dashboard-rides")
            await RealtimeManager.shared.unsubscribe(channelName: "requests-dashboard-favors")
        }
    }
    
    // MARK: - Public Methods
    
    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Get filtered requests from SwiftData models
    func getFilteredRequests(rides: [SDRide], favors: [SDFavor]) -> [RequestItem] {
        guard let userId = authService.currentUserId else { return [] }
        
        // 1. Convert SDRide/SDFavor to Ride/Favor (minimal conversion for UI)
        // In a full implementation, we'd have a way to convert SD models back to domain models
        // or make the UI work directly with SD models.
        
        var allRequests: [RequestItem] = []
        
        // Convert SDRide to Ride
        let ridesConverted = rides.map { sdRide in
            Ride(
                id: sdRide.id,
                userId: sdRide.userId,
                type: sdRide.type,
                date: sdRide.date,
                time: sdRide.time,
                pickup: sdRide.pickup,
                destination: sdRide.destination,
                seats: sdRide.seats,
                notes: sdRide.notes,
                gift: sdRide.gift,
                status: RideStatus(rawValue: sdRide.status) ?? .open,
                claimedBy: sdRide.claimedBy,
                reviewed: sdRide.reviewed,
                reviewSkipped: sdRide.reviewSkipped,
                reviewSkippedAt: sdRide.reviewSkippedAt,
                estimatedCost: sdRide.estimatedCost,
                createdAt: sdRide.createdAt,
                updatedAt: sdRide.updatedAt,
                qaCount: sdRide.qaCount
            )
        }
        
        // Convert SDFavor to Favor
        let favorsConverted = favors.map { sdFavor in
            Favor(
                id: sdFavor.id,
                userId: sdFavor.userId,
                title: sdFavor.title,
                description: sdFavor.favorDescription,
                location: sdFavor.location,
                duration: FavorDuration(rawValue: sdFavor.duration) ?? .notSure,
                requirements: sdFavor.requirements,
                date: sdFavor.date,
                time: sdFavor.time,
                gift: sdFavor.gift,
                status: FavorStatus(rawValue: sdFavor.status) ?? .open,
                claimedBy: sdFavor.claimedBy,
                reviewed: sdFavor.reviewed,
                reviewSkipped: sdFavor.reviewSkipped,
                reviewSkippedAt: sdFavor.reviewSkippedAt,
                createdAt: sdFavor.createdAt,
                updatedAt: sdFavor.updatedAt,
                qaCount: sdFavor.qaCount
            )
        }
        
        let rideItems = ridesConverted.map { RequestItem.ride($0) }
        let favorItems = favorsConverted.map { RequestItem.favor($0) }
        allRequests = rideItems + favorItems
        
        // 2. Apply filtering
        switch filter {
        case .open:
            // Open Requests: Show unclaimed requests that user is NOT participating in
            allRequests = allRequests.filter { request in
                request.isUnclaimed && !request.isParticipating(userId: userId)
            }
        case .mine:
            // My Requests: Show requests user is participating in (poster or participant)
            allRequests = allRequests.filter { request in
                request.isParticipating(userId: userId)
            }
        case .claimed:
            // Claimed Requests: Show requests user has claimed
            allRequests = allRequests.filter { request in
                request.claimedBy == userId
            }
        }
        
        // 3. Filter out completed and old requests
        let now = Date()
        allRequests = allRequests.filter { request in
            if request.isCompleted { return false }
            let hoursSinceEvent = now.timeIntervalSince(request.eventTime) / 3600
            return hoursSinceEvent <= 12
        }
        
        // 4. Sort by event time
        allRequests.sort { $0.eventTime < $1.eventTime }
        
        return allRequests
    }
    
    /// Load requests (rides + favors) from network and sync to SwiftData
    func loadRequests() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            // Fetch everything from Supabase (Full Mirror Sync)
            async let ridesTask = rideService.fetchRides()
            async let favorsTask = favorService.fetchFavors()
            
            let rides = try await ridesTask
            let favors = try await favorsTask
            
            // Sync to SwiftData
            if let context = modelContext {
                syncRidesToSwiftData(rides, in: context)
                syncFavorsToSwiftData(favors, in: context)
                try? context.save()
            }
            
            await refreshUnseenRequestKeys()
        } catch {
            self.error = error.localizedDescription
            print("❌ Error loading requests: \(error)")
        }
    }
    
    private func syncRidesToSwiftData(_ rides: [Ride], in context: ModelContext) {
        for ride in rides {
            let id = ride.id
            let fetchDescriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
                // Update existing
                existing.status = ride.status.rawValue
                existing.claimedBy = ride.claimedBy
                existing.updatedAt = ride.updatedAt
                existing.qaCount = ride.qaCount ?? 0
                existing.date = ride.date
                existing.time = ride.time
                existing.pickup = ride.pickup
                existing.destination = ride.destination
                existing.seats = ride.seats
                existing.notes = ride.notes
                existing.gift = ride.gift
                existing.reviewed = ride.reviewed
                existing.reviewSkipped = ride.reviewSkipped
                existing.reviewSkippedAt = ride.reviewSkippedAt
                existing.estimatedCost = ride.estimatedCost
            } else {
                // Insert new
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
                    qaCount: ride.qaCount ?? 0
                )
                context.insert(sdRide)
            }
        }
    }
    
    private func syncFavorsToSwiftData(_ favors: [Favor], in context: ModelContext) {
        for favor in favors {
            let id = favor.id
            let fetchDescriptor = FetchDescriptor<SDFavor>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
                // Update existing
                existing.status = favor.status.rawValue
                existing.claimedBy = favor.claimedBy
                existing.updatedAt = favor.updatedAt
                existing.qaCount = favor.qaCount ?? 0
                existing.title = favor.title
                existing.favorDescription = favor.description
                existing.location = favor.location
                existing.duration = favor.duration.rawValue
                existing.requirements = favor.requirements
                existing.date = favor.date
                existing.time = favor.time
                existing.gift = favor.gift
                existing.reviewed = favor.reviewed
                existing.reviewSkipped = favor.reviewSkipped
                existing.reviewSkippedAt = favor.reviewSkippedAt
            } else {
                // Insert new
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
                    qaCount: favor.qaCount ?? 0
                )
                context.insert(sdFavor)
            }
        }
    }
    
    /// Update filter and reload requests
    func filterRequests(_ newFilter: RequestFilter) {
        filter = newFilter
        // No need to reload from network, @Query will handle the UI update
    }
    
    /// Refresh requests (pull-to-refresh)
    func refreshRequests() async {
        await loadRequests()
    }
    
    /// Setup realtime subscription for live updates
    func setupRealtimeSubscription() {
        Task {
            // Subscribe to rides changes
            await realtimeManager.subscribe(
                channelName: "requests-dashboard-rides",
                table: "rides",
                filter: nil,
                onInsert: { [weak self] payload in
                    Task { @MainActor in
                        // Upsert into SwiftData
                        if let self = self, let context = self.modelContext, 
                           let record = self.extractRecord(from: payload) {
                            // Minimal sync for realtime
                            await self.loadRequests() 
                        }
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor in
                        await self?.loadRequests()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor in
                        await self?.loadRequests()
                    }
                }
            )
            
            // Subscribe to favors changes
            await realtimeManager.subscribe(
                channelName: "requests-dashboard-favors",
                table: "favors",
                filter: nil,
                onInsert: { [weak self] _ in
                    Task { @MainActor in
                        await self?.loadRequests()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor in
                        await self?.loadRequests()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor in
                        await self?.loadRequests()
                    }
                }
            )

            if let userId = authService.currentUserId {
                let userFilter = "user_id=eq.\(userId.uuidString)"
                await realtimeManager.subscribe(
                    channelName: "requests-dashboard-notifications",
                    table: "notifications",
                    filter: userFilter,
                    onInsert: { [weak self] _ in
                        Task { @MainActor in
                            await self?.refreshUnseenRequestKeys()
                            await self?.badgeManager.refreshAllBadges()
                        }
                    },
                    onUpdate: { [weak self] _ in
                        Task { @MainActor in
                            await self?.refreshUnseenRequestKeys()
                            await self?.badgeManager.refreshAllBadges()
                        }
                    },
                    onDelete: { [weak self] _ in
                        Task { @MainActor in
                            await self?.refreshUnseenRequestKeys()
                            await self?.badgeManager.refreshAllBadges()
                        }
                    }
                )
            }
        }
    }
    
    /// Cleanup realtime subscription
    func cleanupRealtimeSubscription() {
        Task {
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-rides")
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-favors")
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-notifications")
        }
    }

    private func refreshUnseenRequestKeys() async {
        guard let userId = authService.currentUserId else {
            unseenRequestKeys = []
            return
        }

        do {
            // Use a detached task or check for cancellation to avoid NSURLErrorDomain Code=-999
            let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            
            // Check if we are still on the main actor and not cancelled before updating published properties
            if !Task.isCancelled {
                unseenRequestKeys = NotificationGrouping.unreadRequestKeys(from: notifications)
                print("🔔 [RequestsDashboardViewModel] Unseen request keys: \(unseenRequestKeys.count)")
            }
        } catch {
            // Ignore cancellation errors to clean up logs
            if (error as NSError).code != NSURLErrorCancelled {
                print("⚠️ [RequestsDashboardViewModel] Failed to refresh request keys: \(error)")
            }
        }
    }
    
    private func extractRecord(from payload: Any) -> [String: Any]? {
        if let insertAction = payload as? InsertAction {
            return insertAction.record
        }
        if let dict = payload as? [String: Any] {
            return dict["record"] as? [String: Any] ?? dict
        }
        return nil
    }
}

