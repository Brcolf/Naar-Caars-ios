//
//  RidesDashboardViewModel.swift
//  NaarsCars
//
//  ViewModel for the rides dashboard
//

import Foundation
import SwiftData
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
    
    @Published var filter: RideFilter = .all
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
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
    
    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Get filtered rides from SwiftData models
    func getFilteredRides(sdRides: [SDRide]) -> [Ride] {
        guard let userId = authService.currentUserId else { return [] }
        
        let rides = sdRides.map { sd in
            Ride(
                id: sd.id,
                userId: sd.userId,
                type: sd.type,
                date: sd.date,
                time: sd.time,
                pickup: sd.pickup,
                destination: sd.destination,
                seats: sd.seats,
                notes: sd.notes,
                gift: sd.gift,
                status: RideStatus(rawValue: sd.status) ?? .open,
                claimedBy: sd.claimedBy,
                reviewed: sd.reviewed,
                reviewSkipped: sd.reviewSkipped,
                reviewSkippedAt: sd.reviewSkippedAt,
                estimatedCost: sd.estimatedCost,
                createdAt: sd.createdAt,
                updatedAt: sd.updatedAt,
                qaCount: sd.qaCount
            )
        }
        
        var filtered = rides
        
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
    
    /// Guard to prevent concurrent loads
    private var isLoadInFlight = false
    /// Debounce task for realtime-triggered reloads
    private var realtimeReloadTask: Task<Void, Never>?
    
    /// Load rides based on current filter
    /// - Parameter showLoadingIndicator: If false, reloads silently (used for realtime updates to avoid flicker)
    func loadRides(forceRefresh: Bool = false, showLoadingIndicator: Bool = true) async {
        guard !isLoadInFlight else { return }
        isLoadInFlight = true
        defer { isLoadInFlight = false }
        
        if showLoadingIndicator {
            isLoading = true
        }
        error = nil
        defer {
            if showLoadingIndicator {
                isLoading = false
            }
        }
        
        do {
            let fetchedRides = try await rideService.fetchRides()
            
            // Sync to SwiftData
            if let context = modelContext {
                syncRidesToSwiftData(fetchedRides, in: context)
                try? context.save()
            }
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("rides", "Error loading rides: \(error)")
        }
    }
    
    private func syncRidesToSwiftData(_ rides: [Ride], in context: ModelContext) {
        for ride in rides {
            let id = ride.id
            let fetchDescriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
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
    
    /// Update filter and reload rides
    func filterRides(_ newFilter: RideFilter) {
        filter = newFilter
    }
    
    /// Refresh rides (pull-to-refresh)
    func refreshRides() async {
        await loadRides(forceRefresh: true)
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
    
    /// Debounced silent reload for realtime events (prevents rapid consecutive reloads and UI flicker)
    private func debouncedSilentReload() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = Task { @MainActor [weak self] in
            // Small debounce to batch rapid consecutive events
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            guard !Task.isCancelled else { return }
            await self?.loadRides(showLoadingIndicator: false)
        }
    }
    
    private func handleRideInsert(_ action: Any) async {
        // Silent reload to avoid loading spinner flash
        debouncedSilentReload()
    }
    
    private func handleRideUpdate(_ action: Any) async {
        // Silent reload to avoid loading spinner flash
        debouncedSilentReload()
    }
    
    private func handleRideDelete(_ action: Any) async {
        // Silent reload to avoid loading spinner flash
        debouncedSilentReload()
    }
}





