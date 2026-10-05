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
            reloadRequestsFromLocalStore: { [weak self] in
                await self?.reloadRequestsFromLocalStore()
            },
            refreshRequestSummaries: { [weak self] in
                await self?.refreshUnseenRequestKeys()
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

    /// Load requests (rides + favors). Network fetch and SwiftData persistence are owned by
    /// `RefreshCoordinator` → `DashboardSyncEngine` → `BackgroundSyncActor`; this method awaits that
    /// full reconciliation and then re-reads SwiftData on the main actor.
    /// - Parameter forceRefresh: true for pull-to-refresh. Every call is a full reconciliation (as
    ///   before — the previous implementation never read this flag); it only changes the logged trigger.
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

            let result = await RefreshCoordinator.shared.forceFullRefreshAndWait(
                .dashboard,
                trigger: forceRefresh ? "pullToRefresh:requests" : "manualReload:requests"
            )
            guard !Task.isCancelled else { return }
            if case .failed(let error, _)? = result {
                // URLSession cancellation is not a user-facing error (parity with previous handling)
                guard (error as NSError).code != NSURLErrorCancelled else { return }
                self.error = error.localizedDescription
                AppLogger.error("requests", "Error loading requests: \(error.localizedDescription)")
                return
            }
            refreshFilteredRequests()
            await refreshUnseenRequestKeys()
        }
        await loadTask?.value
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

    /// Start observing `DashboardSyncEngine`'s `.ridesDidSync` / `.favorsDidSync` /
    /// `.notificationsDidSync` NotificationCenter posts (no WebSocket channels are opened).
    /// Reactions re-read SwiftData only; network refresh is owned by `RefreshCoordinator`.
    func setupRealtimeSubscription() {
        realtimeHandler.setupRealtimeSubscription()
    }

    /// Stop observing the sync notifications and cancel pending debounced reloads.
    func cleanupRealtimeSubscription() {
        realtimeHandler.cleanupRealtimeSubscription()
    }

    private func refreshUnseenRequestKeys() async {
        await summaryManager.refreshUnseenRequestKeys(modelContext: modelContext)
        refreshFilterBadgeCounts()
    }

    /// Local-only reload used after `DashboardSyncEngine` posts `.ridesDidSync` / `.favorsDidSync`.
    ///
    /// `BackgroundSyncActor` has already written the fresh server rows to SwiftData, so this only
    /// re-reads SwiftData (filtered lists, unread summaries, filter badge counts). It must never
    /// hit the network: `RefreshCoordinator` is the single owner of refresh decisions, and a
    /// network fetch here would turn every coordinator sync into a second full fetch.
    private func reloadRequestsFromLocalStore() async {
        // Without a context there is nothing local to read, and `summaryManager` would fall back
        // to a network fetch — which this path must never do.
        guard modelContext != nil else { return }
        // A completed sync supersedes any earlier load error. This preserves the previous
        // observable behaviour (the network reload cleared `error` on every sync); the view hides
        // the list while `error` is non-nil.
        error = nil
        refreshFilteredRequests()
        await refreshUnseenRequestKeys()
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
