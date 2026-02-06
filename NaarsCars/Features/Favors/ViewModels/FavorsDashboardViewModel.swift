//
//  FavorsDashboardViewModel.swift
//  NaarsCars
//
//  ViewModel for the favors dashboard
//

import Foundation
import SwiftData
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
    
    @Published var filter: FavorFilter = .all
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private let favorService = FavorService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    
    // MARK: - Lifecycle
    
    deinit {
        // Use Task.detached to clean up subscriptions without capturing self
        Task.detached {
            await RealtimeManager.shared.unsubscribe(channelName: "favors-dashboard")
        }
    }
    
    // MARK: - Public Methods
    
    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Get filtered favors from SwiftData models
    func getFilteredFavors(sdFavors: [SDFavor]) -> [Favor] {
        guard let userId = authService.currentUserId else { return [] }
        
        let favors = sdFavors.map { sd in
            Favor(
                id: sd.id,
                userId: sd.userId,
                title: sd.title,
                description: sd.favorDescription,
                location: sd.location,
                duration: FavorDuration(rawValue: sd.duration) ?? .notSure,
                requirements: sd.requirements,
                date: sd.date,
                time: sd.time,
                gift: sd.gift,
                status: FavorStatus(rawValue: sd.status) ?? .open,
                claimedBy: sd.claimedBy,
                reviewed: sd.reviewed,
                reviewSkipped: sd.reviewSkipped,
                reviewSkippedAt: sd.reviewSkippedAt,
                createdAt: sd.createdAt,
                updatedAt: sd.updatedAt,
                qaCount: sd.qaCount
            )
        }
        
        var filtered = favors
        
        switch filter {
        case .all:
            break
        case .mine:
            filtered = filtered.filter { $0.userId == userId || ($0.participants?.contains(where: { $0.id == userId }) ?? false) }
        case .claimed:
            filtered = filtered.filter { $0.claimedBy == userId }
        }
        
        return filtered.sorted { $0.date < $1.date }
    }
    
    /// Load favors based on current filter
    func loadFavors(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let fetchedFavors = try await favorService.fetchFavors()
            
            // Sync to SwiftData
            if let context = modelContext {
                syncFavorsToSwiftData(fetchedFavors, in: context)
                try? context.save()
            }
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("favors", "Error loading favors: \(error.localizedDescription)")
        }
    }
    
    private func syncFavorsToSwiftData(_ favors: [Favor], in context: ModelContext) {
        for favor in favors {
            let id = favor.id
            let fetchDescriptor = FetchDescriptor<SDFavor>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
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
                    qaCount: favor.qaCount ?? 0
                )
                context.insert(sdFavor)
            }
        }
    }
    
    /// Update filter and reload favors
    func filterFavors(_ newFilter: FavorFilter) {
        filter = newFilter
    }
    
    /// Refresh favors (pull-to-refresh)
    func refreshFavors() async {
        await loadFavors(forceRefresh: true)
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





