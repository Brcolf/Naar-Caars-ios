//
//  RequestsDashboardViewModel.swift
//  NaarsCars
//
//  ViewModel for unified requests dashboard (rides + favors)
//

import Foundation
internal import Combine

/// ViewModel for unified requests dashboard
@MainActor
final class RequestsDashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var requests: [RequestItem] = []
    @Published var filter: RequestFilter = .open
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    
    // MARK: - Public Methods
    
    /// Load requests (rides + favors) based on current filter
    func loadRequests() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            var allRequests: [RequestItem] = []
            
            // Capture filter and userId before async closures to avoid actor isolation issues
            let currentFilter = filter
            let currentUserId = authService.currentUserId
            
            // Fetch rides and favors in parallel
            async let ridesTask: [Ride] = {
                switch currentFilter {
                case .open:
                    // Fetch all open rides (not completed, available to claim)
                    return try await rideService.fetchRides(status: .open)
                case .mine:
                    // Fetch all rides created by current user OR where user is a participant (regardless of status)
                    guard let userId = currentUserId else { return [] }
                    // Fetch rides posted by user
                    let postedRides = try await rideService.fetchRides(userId: userId)
                    // Fetch rides where user is a participant
                    let participantRides = try await rideService.fetchRidesByParticipant(userId: userId)
                    // Combine and deduplicate
                    var allRides = postedRides
                    let postedIds = Set(postedRides.map { $0.id })
                    for ride in participantRides {
                        if !postedIds.contains(ride.id) {
                            allRides.append(ride)
                        }
                    }
                    return allRides
                case .claimed:
                    // Fetch all rides claimed by current user (regardless of status)
                    guard let userId = currentUserId else { return [] }
                    return try await rideService.fetchRides(claimedBy: userId)
                }
            }()
            
            async let favorsTask: [Favor] = {
                switch currentFilter {
                case .open:
                    // Fetch all open favors (not completed, available to claim)
                    return try await favorService.fetchFavors(status: .open)
                case .mine:
                    // Fetch all favors created by current user OR where user is a participant (regardless of status)
                    guard let userId = currentUserId else { return [] }
                    // Fetch favors posted by user
                    let postedFavors = try await favorService.fetchFavors(userId: userId)
                    // Fetch favors where user is a participant
                    let participantFavors = try await favorService.fetchFavorsByParticipant(userId: userId)
                    // Combine and deduplicate
                    var allFavors = postedFavors
                    let postedIds = Set(postedFavors.map { $0.id })
                    for favor in participantFavors {
                        if !postedIds.contains(favor.id) {
                            allFavors.append(favor)
                        }
                    }
                    return allFavors
                case .claimed:
                    // Fetch all favors claimed by current user (regardless of status)
                    guard let userId = currentUserId else { return [] }
                    return try await favorService.fetchFavors(claimedBy: userId)
                }
            }()
            
            let rides = try await ridesTask
            let favors = try await favorsTask
            
            // Convert to RequestItem
            let rideItems = rides.map { RequestItem.ride($0) }
            let favorItems = favors.map { RequestItem.favor($0) }
            allRequests = rideItems + favorItems
            
            // Apply filter-specific logic
            if let userId = currentUserId {
                switch currentFilter {
                case .open:
                    // Open Requests: Show unclaimed requests that user is NOT participating in
                    allRequests = allRequests.filter { request in
                        request.isUnclaimed && !request.isParticipating(userId: userId)
                    }
                case .mine:
                    // My Requests: Show requests user is participating in (poster or participant)
                    // Filter already includes posted + participant requests, just ensure we're filtering correctly
                    allRequests = allRequests.filter { request in
                        request.isParticipating(userId: userId)
                    }
                case .claimed:
                    // Claimed Requests: Show requests user has claimed (already filtered by service)
                    // No additional filtering needed here
                    break
                }
            }
            
            // Filter out completed requests for all filters
            allRequests = allRequests.filter { !$0.isCompleted }
            
            // Filter out requests that are more than 12 hours past their event time
            let now = Date()
            allRequests = allRequests.filter { request in
                let eventTime = request.eventTime
                let hoursSinceEvent = now.timeIntervalSince(eventTime) / 3600
                return hoursSinceEvent <= 12
            }
            
            // Sort by event time (earliest first) instead of created time
            allRequests.sort { $0.eventTime < $1.eventTime }
            
            requests = allRequests
        } catch {
            self.error = error.localizedDescription
            print("❌ Error loading requests: \(error)")
        }
    }
    
    /// Update filter and reload requests
    func filterRequests(_ newFilter: RequestFilter) {
        filter = newFilter
        Task {
            await loadRequests()
        }
    }
    
    /// Refresh requests (pull-to-refresh)
    func refreshRequests() async {
        // Invalidate cache to force fresh fetch
        await CacheManager.shared.invalidateRides()
        await CacheManager.shared.invalidateFavors()
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
        }
    }
    
    /// Cleanup realtime subscription
    func cleanupRealtimeSubscription() {
        Task {
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-rides")
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-favors")
        }
    }
}

