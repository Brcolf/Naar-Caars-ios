//
//  RidesDashboardViewModel.swift
//  NaarsCars
//
//  ViewModel for the rides dashboard
//

import Foundation
internal import Combine

/// Filter type for rides dashboard
enum RideFilter: String, CaseIterable {
    case all = "All"
    case mine = "Mine"
    case claimed = "Claimed"
}

/// ViewModel for rides dashboard
@MainActor
final class RidesDashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var rides: [Ride] = []
    @Published var filter: RideFilter = .all
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private let rideService = RideService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    
    // MARK: - Lifecycle
    
    deinit {
        // Use Task.detached to clean up subscriptions without capturing self
        Task.detached {
            await RealtimeManager.shared.unsubscribe(channelName: "rides-dashboard")
        }
    }
    
    // MARK: - Public Methods
    
    /// Load rides based on current filter
    func loadRides() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let currentUserId = authService.currentUserId
            
            var fetchedRides: [Ride] = []
            
            switch filter {
            case .all:
                fetchedRides = try await rideService.fetchRides()
            case .mine:
                guard let userId = currentUserId else {
                    error = "Not authenticated"
                    return
                }
                fetchedRides = try await rideService.fetchRides(userId: userId)
            case .claimed:
                guard let userId = currentUserId else {
                    error = "Not authenticated"
                    return
                }
                fetchedRides = try await rideService.fetchRides(claimedBy: userId)
            }
            
            rides = fetchedRides
        } catch {
            self.error = error.localizedDescription
            print("❌ Error loading rides: \(error)")
        }
    }
    
    /// Update filter and reload rides
    func filterRides(_ newFilter: RideFilter) {
        filter = newFilter
        Task {
            await loadRides()
        }
    }
    
    /// Refresh rides (pull-to-refresh)
    func refreshRides() async {
        // Invalidate cache to force fresh fetch
        await CacheManager.shared.invalidateRides()
        await loadRides()
    }
    
    /// Setup realtime subscription for live updates
    func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "rides-dashboard",
                table: "rides",
                filter: nil,
                onInsert: { [weak self] action in
                    Task { @MainActor in
                        await self?.handleRideInsert(action)
                    }
                },
                onUpdate: { [weak self] action in
                    Task { @MainActor in
                        await self?.handleRideUpdate(action)
                    }
                },
                onDelete: { [weak self] action in
                    Task { @MainActor in
                        await self?.handleRideDelete(action)
                    }
                }
            )
        }
    }
    
    /// Cleanup realtime subscription
    func cleanupRealtimeSubscription() {
        Task {
            await realtimeManager.unsubscribe(channelName: "rides-dashboard")
        }
    }
    
    // MARK: - Private Methods
    
    private func handleRideInsert(_ action: Any) async {
        // Reload rides to get the new one
        await loadRides()
    }
    
    private func handleRideUpdate(_ action: Any) async {
        // Reload rides to get updated data
        await loadRides()
    }
    
    private func handleRideDelete(_ action: Any) async {
        // Reload rides to remove deleted one
        await loadRides()
    }
}





