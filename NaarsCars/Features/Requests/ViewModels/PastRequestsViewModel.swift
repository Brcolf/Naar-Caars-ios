//
//  PastRequestsViewModel.swift
//  NaarsCars
//
//  ViewModel for past requests view
//

import Foundation
internal import Combine

/// ViewModel for past requests view
@MainActor
final class PastRequestsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var requests: [RequestItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let authService = AuthService.shared
    
    // MARK: - Public Methods
    
    /// Load past requests based on filter
    /// - Parameter filter: Filter type (My Past Requests or Requests I've Helped With)
    func loadRequests(filter: PastRequestsView.PastRequestFilter) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            var allRequests: [RequestItem] = []
            
            let currentUserId = authService.currentUserId
            let now = Date()
            let twelveHoursAgo = now.addingTimeInterval(-12 * 3600)
            
            switch filter {
            case .myRequests:
                // Fetch all rides and favors created by current user
                guard let userId = currentUserId else {
                    requests = []
                    return
                }
                
                async let ridesTask = rideService.fetchRides(userId: userId)
                async let favorsTask = favorService.fetchFavors(userId: userId)
                
                let rides = try await ridesTask
                let favors = try await favorsTask
                
                // Convert to RequestItem
                let rideItems = rides.map { RequestItem.ride($0) }
                let favorItems = favors.map { RequestItem.favor($0) }
                allRequests = rideItems + favorItems
                
                // Filter to only include requests that are more than 12 hours past their event time
                allRequests = allRequests.filter { request in
                    let eventTime = request.eventTime
                    let hoursSinceEvent = now.timeIntervalSince(eventTime) / 3600
                    return hoursSinceEvent > 12
                }
                
            case .helpedWith:
                // Fetch all rides and favors claimed by current user
                guard let userId = currentUserId else {
                    requests = []
                    return
                }
                
                async let ridesTask = rideService.fetchRides(claimedBy: userId)
                async let favorsTask = favorService.fetchFavors(claimedBy: userId)
                
                let rides = try await ridesTask
                let favors = try await favorsTask
                
                // Convert to RequestItem
                let rideItems = rides.map { RequestItem.ride($0) }
                let favorItems = favors.map { RequestItem.favor($0) }
                allRequests = rideItems + favorItems
                
                // Filter to only include requests that are more than 12 hours past their event time
                allRequests = allRequests.filter { request in
                    let eventTime = request.eventTime
                    let hoursSinceEvent = now.timeIntervalSince(eventTime) / 3600
                    return hoursSinceEvent > 12
                }
            }
            
            // Sort by event time (most recent first - descending)
            allRequests.sort { $0.eventTime > $1.eventTime }
            
            requests = allRequests
        } catch {
            self.error = error.localizedDescription
            print("❌ Error loading past requests: \(error)")
        }
    }
    
    /// Refresh past requests
    /// - Parameter filter: Filter type
    func refreshRequests(filter: PastRequestsView.PastRequestFilter) async {
        // Invalidate cache to force fresh fetch
        await CacheManager.shared.invalidateRides()
        await CacheManager.shared.invalidateFavors()
        await loadRequests(filter: filter)
    }
}

