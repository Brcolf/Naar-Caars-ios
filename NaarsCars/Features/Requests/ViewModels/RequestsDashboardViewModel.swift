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
    /// In-flight load task; cancelled in stop() to avoid use-after-free when view disappears.
    private var loadTask: Task<Void, Never>?
    private var flightEnrichmentObserver: (any NSObjectProtocol)?

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

        realtimeHandler.configure(
            modelContextProvider: { [weak self] in self?.modelContext },
            authUserIdProvider: { [weak self] in self?.authService.currentUserId },
            syncRidesToSwiftData: { [weak self] rides, context in
                _ = self?.syncRidesToSwiftData(rides, in: context)
            },
            syncFavorsToSwiftData: { [weak self] favors, context in
                _ = self?.syncFavorsToSwiftData(favors, in: context)
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
        flightEnrichmentObserver = NotificationCenter.default.addObserver(
            forName: .rideFlightEnrichmentDidComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.loadRequests(forceRefresh: true, showLoadingIndicator: false) }
        }
    }

    deinit {
        // Cleanup is done in stop() from onDisappear. Do not start Task or touch MainActor state here (deinit is nonisolated).
    }

    /// Call from view onDisappear to cancel in-flight work and realtime subscription so VM can tear down safely.
    func stop() {
        AppLogger.info("requests", "[RequestsDashboardVM] stop() called; cancelling loadTask and realtime subscription")
        loadTask?.cancel()
        loadTask = nil
        realtimeHandler.cleanupRealtimeSubscription()
        if let o = flightEnrichmentObserver {
            NotificationCenter.default.removeObserver(o)
            flightEnrichmentObserver = nil
        }
    }

    // MARK: - Public Methods

    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshFilteredRequests()
    }

    func refreshLocalState() async {
        refreshFilteredRequests()
        await refreshUnseenRequestKeys()
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
    func loadRequests(forceRefresh: Bool = false, showLoadingIndicator: Bool = true) async {
        // Guest users viewing user-specific filters have no data — skip the network call
        if authService.currentUserId == nil && (filter == .mine || filter == .claimed) {
            filteredRides = []
            filteredFavors = []
            filteredRequests = []
            isLoading = false
            return
        }

        loadTask?.cancel()
        loadTask = Task { @MainActor in
            defer { loadTask = nil }
            guard !Task.isCancelled else { return }
            error = nil

            // Show cached SwiftData data immediately
            refreshFilteredRequests()

            // Only show loading spinner if there's no cached data to display
            let hasCachedData = !filteredRequests.isEmpty
            if showLoadingIndicator && !hasCachedData { isLoading = true }
            defer { if !Task.isCancelled { isLoading = false } }

            do {
                async let ridesTask = rideService.fetchRides(status: nil, userId: nil, claimedBy: nil, excludeStatus: .completed)
                async let favorsTask = favorService.fetchFavors(status: nil, userId: nil, claimedBy: nil, excludeStatus: .completed)
                let rides = try await ridesTask
                let favors = try await favorsTask
                guard !Task.isCancelled else { return }
                if let context = modelContext {
                    // Compare-before-write: only persist if a synced row actually changed.
                    let ridesChanged = syncRidesToSwiftData(rides, in: context)
                    let favorsChanged = syncFavorsToSwiftData(favors, in: context)
                    if ridesChanged || favorsChanged {
                        try? context.save()
                    }
                }
                refreshFilteredRequests()
                await refreshUnseenRequestKeys()
            } catch is CancellationError {
                return
            } catch let error as NSError where error.code == NSURLErrorCancelled {
                return
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    AppLogger.error("requests", "Error loading requests: \(error.localizedDescription)")
                }
            }
        }
        await loadTask?.value
    }

    /// Upserts rides into SwiftData with field-level change detection.
    /// Returns `true` if at least one row was inserted or actually mutated, so the caller can skip `save()` when nothing changed.
    @discardableResult
    private func syncRidesToSwiftData(_ rides: [Ride], in context: ModelContext) -> Bool {
        var didChange = false
        for ride in rides {
            let id = ride.id
            let fetchDescriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
                // Update existing — only assign fields whose value actually differs.
                if existing.status != ride.status.rawValue { existing.status = ride.status.rawValue; didChange = true }
                if existing.claimedBy != ride.claimedBy { existing.claimedBy = ride.claimedBy; didChange = true }
                if existing.updatedAt != ride.updatedAt { existing.updatedAt = ride.updatedAt; didChange = true }
                if existing.qaCount != (ride.qaCount ?? 0) { existing.qaCount = ride.qaCount ?? 0; didChange = true }
                if existing.date != ride.date { existing.date = ride.date; didChange = true }
                if existing.time != ride.time { existing.time = ride.time; didChange = true }
                if existing.timezone != ride.timezone { existing.timezone = ride.timezone; didChange = true }
                if existing.pickup != ride.pickup { existing.pickup = ride.pickup; didChange = true }
                if existing.destination != ride.destination { existing.destination = ride.destination; didChange = true }
                if existing.seats != ride.seats { existing.seats = ride.seats; didChange = true }
                if existing.notes != ride.notes { existing.notes = ride.notes; didChange = true }
                if existing.gift != ride.gift { existing.gift = ride.gift; didChange = true }
                if existing.reviewed != ride.reviewed { existing.reviewed = ride.reviewed; didChange = true }
                if existing.reviewSkipped != ride.reviewSkipped { existing.reviewSkipped = ride.reviewSkipped; didChange = true }
                if existing.reviewSkippedAt != ride.reviewSkippedAt { existing.reviewSkippedAt = ride.reviewSkippedAt; didChange = true }
                if existing.estimatedCost != ride.estimatedCost { existing.estimatedCost = ride.estimatedCost; didChange = true }
                if existing.flightNormalized != ride.flightNormalized { existing.flightNormalized = ride.flightNormalized; didChange = true }
                if existing.hiddenAt != ride.hiddenAt { existing.hiddenAt = ride.hiddenAt; didChange = true }
                if existing.hiddenBy != ride.hiddenBy { existing.hiddenBy = ride.hiddenBy; didChange = true }
                if existing.hiddenReason != ride.hiddenReason { existing.hiddenReason = ride.hiddenReason; didChange = true }
                if existing.posterName != ride.poster?.name { existing.posterName = ride.poster?.name; didChange = true }
                if existing.posterAvatarUrl != ride.poster?.avatarUrl { existing.posterAvatarUrl = ride.poster?.avatarUrl; didChange = true }
                if existing.claimerName != ride.claimer?.name { existing.claimerName = ride.claimer?.name; didChange = true }
                if existing.claimerAvatarUrl != ride.claimer?.avatarUrl { existing.claimerAvatarUrl = ride.claimer?.avatarUrl; didChange = true }
                let newParticipantIds = ride.participants?.map { $0.id } ?? []
                if existing.participantIds != newParticipantIds { existing.participantIds = newParticipantIds; didChange = true }
            } else {
                // Insert new
                didChange = true
                let sdRide = SDRide(
                    id: ride.id,
                    userId: ride.userId,
                    type: ride.type,
                    date: ride.date,
                    time: ride.time,
                    timezone: ride.timezone,
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
                    hiddenAt: ride.hiddenAt,
                    hiddenBy: ride.hiddenBy,
                    hiddenReason: ride.hiddenReason,
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
        return didChange
    }

    /// Upserts favors into SwiftData with field-level change detection.
    /// Returns `true` if at least one row was inserted or actually mutated, so the caller can skip `save()` when nothing changed.
    @discardableResult
    private func syncFavorsToSwiftData(_ favors: [Favor], in context: ModelContext) -> Bool {
        var didChange = false
        for favor in favors {
            let id = favor.id
            let fetchDescriptor = FetchDescriptor<SDFavor>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
                // Update existing — only assign fields whose value actually differs.
                if existing.status != favor.status.rawValue { existing.status = favor.status.rawValue; didChange = true }
                if existing.claimedBy != favor.claimedBy { existing.claimedBy = favor.claimedBy; didChange = true }
                if existing.updatedAt != favor.updatedAt { existing.updatedAt = favor.updatedAt; didChange = true }
                if existing.qaCount != (favor.qaCount ?? 0) { existing.qaCount = favor.qaCount ?? 0; didChange = true }
                if existing.title != favor.title { existing.title = favor.title; didChange = true }
                if existing.favorDescription != favor.description { existing.favorDescription = favor.description; didChange = true }
                if existing.location != favor.location { existing.location = favor.location; didChange = true }
                if existing.duration != favor.duration.rawValue { existing.duration = favor.duration.rawValue; didChange = true }
                if existing.requirements != favor.requirements { existing.requirements = favor.requirements; didChange = true }
                if existing.date != favor.date { existing.date = favor.date; didChange = true }
                if existing.time != favor.time { existing.time = favor.time; didChange = true }
                if existing.timezone != favor.timezone { existing.timezone = favor.timezone; didChange = true }
                if existing.gift != favor.gift { existing.gift = favor.gift; didChange = true }
                if existing.reviewed != favor.reviewed { existing.reviewed = favor.reviewed; didChange = true }
                if existing.reviewSkipped != favor.reviewSkipped { existing.reviewSkipped = favor.reviewSkipped; didChange = true }
                if existing.reviewSkippedAt != favor.reviewSkippedAt { existing.reviewSkippedAt = favor.reviewSkippedAt; didChange = true }
                if existing.hiddenAt != favor.hiddenAt { existing.hiddenAt = favor.hiddenAt; didChange = true }
                if existing.hiddenBy != favor.hiddenBy { existing.hiddenBy = favor.hiddenBy; didChange = true }
                if existing.hiddenReason != favor.hiddenReason { existing.hiddenReason = favor.hiddenReason; didChange = true }
                if existing.posterName != favor.poster?.name { existing.posterName = favor.poster?.name; didChange = true }
                if existing.posterAvatarUrl != favor.poster?.avatarUrl { existing.posterAvatarUrl = favor.poster?.avatarUrl; didChange = true }
                if existing.claimerName != favor.claimer?.name { existing.claimerName = favor.claimer?.name; didChange = true }
                if existing.claimerAvatarUrl != favor.claimer?.avatarUrl { existing.claimerAvatarUrl = favor.claimer?.avatarUrl; didChange = true }
                let newParticipantIds = favor.participants?.map { $0.id } ?? []
                if existing.participantIds != newParticipantIds { existing.participantIds = newParticipantIds; didChange = true }
            } else {
                // Insert new
                didChange = true
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
                    timezone: favor.timezone,
                    gift: favor.gift,
                    status: favor.status.rawValue,
                    claimedBy: favor.claimedBy,
                    reviewed: favor.reviewed,
                    reviewSkipped: favor.reviewSkipped,
                    reviewSkippedAt: favor.reviewSkippedAt,
                    hiddenAt: favor.hiddenAt,
                    hiddenBy: favor.hiddenBy,
                    hiddenReason: favor.hiddenReason,
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
        return didChange
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
