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

struct RequestNotificationSummary {
    let unreadCount: Int
    let latestUnreadType: NotificationType
    let latestUnreadAt: Date
}

/// ViewModel for unified requests dashboard
@MainActor
final class RequestsDashboardViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var filter: RequestFilter = .open
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var filterBadgeCounts: [RequestFilter: Int] = [:]
    @Published var filteredRides: [SDRide] = []
    @Published var filteredFavors: [SDFavor] = []
    @Published var filteredRequests: [RequestItem] = []

    var unseenRequestKeys: Set<String> { summaryManager.unseenRequestKeys }
    var requestNotificationSummaries: [String: RequestNotificationSummary] { summaryManager.requestNotificationSummaries }

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private let rideService: any RideServiceProtocol
    private let favorService: any FavorServiceProtocol
    private let authService: any AuthServiceProtocol
    private let filterManager: RequestFilterManager
    private let summaryManager: RequestNotificationSummaryManager
    private let realtimeHandler: RequestRealtimeHandler
    private var managerCancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init(
        rideService: any RideServiceProtocol = RideService.shared,
        favorService: any FavorServiceProtocol = FavorService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.rideService = rideService
        self.favorService = favorService
        self.authService = authService
        filterManager = RequestFilterManager()
        summaryManager = RequestNotificationSummaryManager()
        realtimeHandler = RequestRealtimeHandler()

        filterManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &managerCancellables)
        summaryManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &managerCancellables)
        realtimeHandler.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &managerCancellables)

        realtimeHandler.configure(
            modelContextProvider: { [weak self] in self?.modelContext },
            authUserIdProvider: { [weak self] in self?.authService.currentUserId },
            syncRidesToSwiftData: { [weak self] rides, context in
                self?.syncRidesToSwiftData(rides, in: context)
            },
            syncFavorsToSwiftData: { [weak self] favors, context in
                self?.syncFavorsToSwiftData(favors, in: context)
            },
            refreshFilteredRequests: { [weak self] in
                self?.refreshFilteredRequests()
            },
            refreshRequestSummaries: { [weak self] in
                await self?.refreshUnseenRequestKeys()
            },
            loadRequestsForceRefresh: { [weak self] in
                await self?.loadRequests(forceRefresh: true)
            }
        )
    }

    deinit {
        let handler = realtimeHandler
        Task { @MainActor in
            handler.cleanupRealtimeSubscription()
        }
    }

    // MARK: - Public Methods

    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshFilteredRequests()
    }

    /// Get filtered requests from SwiftData models
    func getFilteredRequests(
        rides: [SDRide],
        favors: [SDFavor],
        filterOverride: RequestFilter? = nil
    ) -> [RequestItem] {
        let activeFilter = filterOverride ?? filter
        return filterManager.getFilteredRequests(
            rides: rides,
            favors: favors,
            filter: activeFilter
        )
    }

    /// Load requests (rides + favors) from network and sync to SwiftData
    func loadRequests(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            // Fetch everything from Supabase (Full Mirror Sync)
            async let ridesTask = rideService.fetchRides(status: nil, userId: nil, claimedBy: nil)
            async let favorsTask = favorService.fetchFavors(status: nil, userId: nil, claimedBy: nil)
            
            let rides = try await ridesTask
            let favors = try await favorsTask
            
            // Don't update state if the task was cancelled
            guard !Task.isCancelled else { return }
            
            // Sync to SwiftData
            if let context = modelContext {
                syncRidesToSwiftData(rides, in: context)
                syncFavorsToSwiftData(favors, in: context)
                try? context.save()
            }
            refreshFilteredRequests()
            await refreshUnseenRequestKeys()
        } catch is CancellationError {
            // Silently ignore task cancellation — normal during SwiftUI
            // lifecycle (view redraws, pull-to-refresh superseded, etc.)
            return
        } catch let error as NSError where error.code == NSURLErrorCancelled {
            return
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("requests", "Error loading requests: \(error.localizedDescription)")
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
                existing.posterName = ride.poster?.name
                existing.posterAvatarUrl = ride.poster?.avatarUrl
                existing.claimerName = ride.claimer?.name
                existing.claimerAvatarUrl = ride.claimer?.avatarUrl
                existing.participantIds = ride.participants?.map { $0.id } ?? []
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
        refreshFilteredRequests()
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
                existing.posterName = favor.poster?.name
                existing.posterAvatarUrl = favor.poster?.avatarUrl
                existing.claimerName = favor.claimer?.name
                existing.claimerAvatarUrl = favor.claimer?.avatarUrl
                existing.participantIds = favor.participants?.map { $0.id } ?? []
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
        refreshFilteredRequests()
    }

    /// Update filter and reload requests
    func filterRequests(_ newFilter: RequestFilter) {
        filter = filterManager.filterRequests(newFilter)
        refreshFilteredRequests()
    }

    func notificationTarget(for request: RequestItem) -> RequestNotificationTarget? {
        filterManager.notificationTarget(
            for: request,
            requestNotificationSummaries: summaryManager.requestNotificationSummaries
        )
    }

    /// Refresh requests (pull-to-refresh)
    func refreshRequests() async {
        await loadRequests(forceRefresh: true)
    }

    /// Setup realtime subscription for live updates
    func setupRealtimeSubscription() {
        realtimeHandler.setupRealtimeSubscription()
    }

    /// Cleanup realtime subscription
    func cleanupRealtimeSubscription() {
        realtimeHandler.cleanupRealtimeSubscription()
    }

    private func refreshUnseenRequestKeys() async {
        await summaryManager.refreshUnseenRequestKeys(modelContext: modelContext)
        refreshFilterBadgeCounts()
    }

    private func refreshFilteredRequests() {
        guard let context = modelContext else { return }
        filteredRides = filterManager.fetchFilteredRides(in: context, filter: filter)
        filteredFavors = filterManager.fetchFilteredFavors(in: context, filter: filter)
        filteredRequests = filterManager.getFilteredRequests(rides: filteredRides, favors: filteredFavors, filter: filter)
        refreshFilterBadgeCounts()
    }

    private func refreshFilterBadgeCounts() {
        guard let context = modelContext else {
            filterBadgeCounts = [:]
            return
        }
        filterBadgeCounts = filterManager.computeFilterBadgeCounts(
            in: context,
            requestNotificationSummaries: summaryManager.requestNotificationSummaries
        )
    }
}
