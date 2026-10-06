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
    /// Set after the first coordinator-backed load; see loadRequests(forceRefresh:).
    private var hasPerformedInitialLoad = false
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

            // Network refresh is forced only for the first load of this ViewModel and for an
            // explicit pull-to-refresh. Every later `.task` re-entry (tab switch, pop back)
            // re-reads SwiftData; staleness-gated refreshes stay with MainTabView's tab-change
            // trigger and app-foreground, as the coordinator contract requires.
            guard forceRefresh || !hasPerformedInitialLoad else {
                await refreshUnseenRequestKeys()
                return
            }

            let result = await RefreshCoordinator.shared.forceFullRefreshAndWait(
                .dashboard,
                trigger: forceRefresh ? "pullToRefresh:requests" : "manualReload:requests"
            )
            guard !Task.isCancelled else { return }
            if case .failed(let error, _)? = result {
                // URLSession cancellation is not a user-facing error (parity with previous handling)
                guard (error as NSError).code != NSURLErrorCancelled else { return }
                // The raw system text goes to the log; the screen gets a sentence a person can
                // act on. The cached rows stay on screen (the view shows this as a banner over
                // them and as a full panel only when there is nothing to list).
                self.error = "requests_load_failed".localized
                AppLogger.error("requests", "Error loading requests: \(error.localizedDescription)")
                return
            }
            // Only a completed (or joined) refresh counts as the initial load, so the ErrorView
            // retry after a failed first fetch reaches the network again.
            hasPerformedInitialLoad = true
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
        // observable behaviour (the network reload cleared `error` on every sync) and takes the
        // "couldn't refresh" banner down once fresh rows have landed.
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

// MARK: - Refresh after the user's own action

/// Brings the Requests list up to date after the signed-in user's own claim, unclaim, complete,
/// create, edit, delete or add-participants. The person who acts gets no push for their own
/// action, so the list used to stay stale (a ride just claimed still read "Open") until
/// pull-to-refresh, a tab switch past the staleness window or the safety poll.
///
/// Called by the request view models once the mutation has succeeded. It goes through the one
/// coordinator call a view model may make (`forceFullRefreshAndWait`), so in-flight dedup is
/// untouched and no engine is called from here. Callers do not wait for it: a dashboard sync
/// fetches every ride, favor and notification, and the success checkmark must not hang on
/// that. The list re-reads SwiftData when it reappears and again on `.ridesDidSync` /
/// `.favorsDidSync`, whichever comes last.
@MainActor
enum RequestsDashboardRefresh {
    private static var refreshTask: Task<Void, Never>?

    /// - Parameter action: Short name for the log trigger, such as "claim" or "deleteRide".
    static func afterUserAction(_ action: String) {
        refreshTask = Task { @MainActor in
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(
                .dashboard,
                trigger: "userAction:\(action)"
            )
        }
    }
}
