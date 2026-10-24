//
//  LeaderboardViewModel.swift
//  NaarsCars
//
//  ViewModel for leaderboard with caching
//

import Foundation
internal import Combine

/// Cache key: the period and the community the rows were read for (nil = no filter).
struct LeaderboardCacheKey: Hashable {
    let period: LeaderboardPeriod
    let communityId: UUID?
}

/// ViewModel for leaderboard with client-side caching
@MainActor
final class LeaderboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading: Bool = false
    @Published var selectedPeriod: LeaderboardPeriod = .thisMonth
    @Published var error: AppError?
    /// A refresh that failed while rankings are on screen; the view shows it as a banner.
    @Published var bannerMessage: String?
    @Published var currentUserRank: Int?
    @Published var spotlights: [SpotlightEntry] = []

    // MARK: - Private Properties

    private let leaderboardService: any LeaderboardFetching
    private let authService: any AuthServiceProtocol
    private let communityContext: CommunityContext?
    /// A community the rows are pinned to, whatever the Town Hall community is (the community
    /// page). Nil follows `communityContext.communityTabId`.
    private let pinnedCommunityId: UUID?

    // Cache: [Period + community: (entries, spotlights, cachedAt)]
    private var cachedEntries: [LeaderboardCacheKey: (entries: [LeaderboardEntry], spotlights: [SpotlightEntry], cachedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = Constants.CacheTTL.leaderboard
    /// The period and community whose rows are in `entries` and `spotlights`.
    private var displayedKey: LeaderboardCacheKey?

    init(
        leaderboardService: any LeaderboardFetching = LeaderboardService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        communityContext: CommunityContext? = nil,
        communityId: UUID? = nil
    ) {
        self.leaderboardService = leaderboardService
        self.authService = authService
        self.communityContext = communityContext
        self.pinnedCommunityId = communityId
    }

    private var currentKey: LeaderboardCacheKey {
        LeaderboardCacheKey(period: selectedPeriod, communityId: pinnedCommunityId ?? communityContext?.communityTabId)
    }

    /// The Community tab's community changed: load the rows for the new key.
    func communityDidChange() async {
        await loadLeaderboard()
    }

    // MARK: - Public Methods

    /// Load leaderboard with caching.
    /// Rows cached for this period and community within `Constants.CacheTTL.leaderboard` are shown
    /// without a request; pull-to-refresh (`refresh()`) is the way to fetch them again sooner.
    func loadLeaderboard() async {
        let period = currentKey
        error = nil
        bannerMessage = nil

        // Check cache first
        if let cached = cachedEntries[period],
           Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
            show(entries: cached.entries, spotlights: cached.spotlights, for: period)
            // A load still in flight for the period the user just left no longer owns the spinner.
            isLoading = false
            // No background refetch: the view calls this on every appearance (each return to the
            // tab or the segment), and each refetch was two RPCs for rows that are still fresh.
            return
        }

        // Never leave another period's rows under the newly selected segment. Clearing them brings
        // up the skeleton, and a failed load then reaches the error view.
        if displayedKey != period {
            show(entries: [], spotlights: [], for: period)
        }
        await fetchFresh(period: period, showLoading: true, reportsFailure: true)
    }

    /// Refresh leaderboard (pull-to-refresh)
    /// Bypasses cache and fetches fresh data
    func refresh() async {
        let period = currentKey
        cachedEntries.removeValue(forKey: period)
        await fetchFresh(period: period, showLoading: false, reportsFailure: true)
    }

    // MARK: - Private Methods

    /// - Parameter period: Captured by the caller. `selectedPeriod` can change while the request is
    ///   in flight; reading it again afterwards showed, and cached, one period's rows under another.
    private func fetchFresh(period: LeaderboardCacheKey, showLoading: Bool, reportsFailure: Bool) async {
        if showLoading { isLoading = true }
        // A newer load for another period owns the loading state once the selection has moved on.
        defer { if showLoading && period == currentKey { isLoading = false } }

        do {
            async let entriesTask = leaderboardService.fetchLeaderboard(period: period.period, communityId: period.communityId)
            async let spotlightsTask = leaderboardService.fetchSpotlights(period: period.period, communityId: period.communityId)

            let (freshEntries, freshSpotlights) = try await (entriesTask, spotlightsTask)
            BadgeCache.shared.storeBatch(entries: freshEntries)
            cachedEntries[period] = (freshEntries, freshSpotlights, Date())
            // A response for a period the user has since left is cached but not shown.
            guard period == currentKey else { return }
            error = nil
            bannerMessage = nil
            show(entries: freshEntries, spotlights: freshSpotlights, for: period)
        } catch {
            AppLogger.error("leaderboard", "Error loading leaderboard: \(error.localizedDescription)")
            guard reportsFailure, period == currentKey else { return }
            if entries.isEmpty {
                self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            } else {
                bannerMessage = "leaderboard_refresh_failed".localized
            }
        }
    }

    private func show(entries: [LeaderboardEntry], spotlights: [SpotlightEntry], for period: LeaderboardCacheKey) {
        self.entries = entries
        self.spotlights = spotlights
        displayedKey = period
        updateCurrentUserRank()
    }
    
    private func updateCurrentUserRank() {
        guard let currentUserId = authService.currentUserId else {
            currentUserRank = nil
            return
        }
        
        if let index = entries.firstIndex(where: { $0.userId == currentUserId }) {
            currentUserRank = index + 1 // 1-indexed
        } else {
            // User is not in the fetched entries. The leaderboard RPC returns the same
            // list that was just searched, so querying it again cannot yield a rank.
            currentUserRank = nil
        }
    }
}



