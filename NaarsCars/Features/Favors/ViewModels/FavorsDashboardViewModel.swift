//
//  FavorsDashboardViewModel.swift
//  NaarsCars
//
//  ViewModel for the favors dashboard
//

import Foundation
internal import Combine

/// Filter type for favors dashboard
enum FavorFilter: String, CaseIterable {
    case all = "All"
    case mine = "Mine"
    case claimed = "Claimed"
}

/// ViewModel for favors dashboard
@MainActor
final class FavorsDashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var favors: [Favor] = []
    @Published var filter: FavorFilter = .all
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private let favorService = FavorService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    
    // MARK: - Public Methods
    
    /// Load favors based on current filter
    func loadFavors() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let currentUserId = authService.currentUserId
            
            var fetchedFavors: [Favor] = []
            
            switch filter {
            case .all:
                fetchedFavors = try await favorService.fetchFavors()
            case .mine:
                guard let userId = currentUserId else {
                    error = "Not authenticated"
                    return
                }
                fetchedFavors = try await favorService.fetchFavors(userId: userId)
            case .claimed:
                guard let userId = currentUserId else {
                    error = "Not authenticated"
                    return
                }
                fetchedFavors = try await favorService.fetchFavors(claimedBy: userId)
            }
            
            favors = fetchedFavors
        } catch {
            self.error = error.localizedDescription
            print("❌ Error loading favors: \(error)")
        }
    }
    
    /// Update filter and reload favors
    func filterFavors(_ newFilter: FavorFilter) {
        filter = newFilter
        Task {
            await loadFavors()
        }
    }
    
    /// Refresh favors (pull-to-refresh)
    func refreshFavors() async {
        // Invalidate cache to force fresh fetch
        await CacheManager.shared.invalidateFavors()
        await loadFavors()
    }
    
    /// Setup realtime subscription for live updates
    func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "favors-dashboard",
                table: "favors",
                filter: nil,
                onInsert: { [weak self] action in
                    Task { @MainActor in
                        await self?.handleFavorInsert(action)
                    }
                },
                onUpdate: { [weak self] action in
                    Task { @MainActor in
                        await self?.handleFavorUpdate(action)
                    }
                },
                onDelete: { [weak self] action in
                    Task { @MainActor in
                        await self?.handleFavorDelete(action)
                    }
                }
            )
        }
    }
    
    /// Cleanup realtime subscription
    func cleanupRealtimeSubscription() {
        Task {
            await realtimeManager.unsubscribe(channelName: "favors-dashboard")
        }
    }
    
    // MARK: - Private Methods
    
    private func handleFavorInsert(_ action: Any) async {
        // Reload favors to get the new one
        await loadFavors()
    }
    
    private func handleFavorUpdate(_ action: Any) async {
        // Reload favors to get updated data
        await loadFavors()
    }
    
    private func handleFavorDelete(_ action: Any) async {
        // Reload favors to remove deleted one
        await loadFavors()
    }
}




