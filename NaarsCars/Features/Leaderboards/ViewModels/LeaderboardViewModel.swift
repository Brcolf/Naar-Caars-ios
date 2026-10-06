//
//  LeaderboardViewModel.swift
//  NaarsCars
//
//  ViewModel for leaderboard with caching
//

import Foundation
internal import Combine

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

    private let leaderboardService = LeaderboardService.shared
    private let authService: any AuthServiceProtocol

    // Cache: [Period: (entries, spotlights, cachedAt)]
    private var cachedEntries: [LeaderboardPeriod: (entries: [LeaderboardEntry], spotlights: [SpotlightEntry], cachedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = Constants.CacheTTL.leaderboard
    /// The period whose rows are in `entries` and `spotlights`.
    private var displayedPeriod: LeaderboardPeriod?

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }

    // MARK: - Public Methods

    /// Load leaderboard with caching
    /// Shows cached data immediately, refreshes in background if cache is valid
    func loadLeaderboard() async {
        let period = selectedPeriod
        error = nil
        bannerMessage = nil

        // Check cache first
        if let cached = cachedEntries[period],
           Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
            show(entries: cached.entries, spotlights: cached.spotlights, for: period)
            // A load still in flight for the period the user just left no longer owns the spinner.
            isLoading = false
            // Refresh in background; the rows on screen are still fresh, so a failure stays quiet.
            Task { await fetchFresh(period: period, showLoading: false, reportsFailure: false) }
            return
        }

        // Never leave another period's rows under the newly selected segment. Clearing them brings
        // up the skeleton, and a failed load then reaches the error view.
        if displayedPeriod != period {
            show(entries: [], spotlights: [], for: period)
        }
        await fetchFresh(period: period, showLoading: true, reportsFailure: true)
    }

    /// Refresh leaderboard (pull-to-refresh)
    /// Bypasses cache and fetches fresh data
    func refresh() async {
        let period = selectedPeriod
        cachedEntries.removeValue(forKey: period)
        await fetchFresh(period: period, showLoading: false, reportsFailure: true)
    }

    // MARK: - Private Methods

    /// - Parameter period: Captured by the caller. `selectedPeriod` can change while the request is
    ///   in flight; reading it again afterwards showed, and cached, one period's rows under another.
    private func fetchFresh(period: LeaderboardPeriod, showLoading: Bool, reportsFailure: Bool) async {
        if showLoading { isLoading = true }
        // A newer load for another period owns the loading state once the selection has moved on.
        defer { if showLoading && period == selectedPeriod { isLoading = false } }

        do {
            async let entriesTask = leaderboardService.fetchLeaderboard(period: period)
            async let spotlightsTask = leaderboardService.fetchSpotlights(period: period)

            let (freshEntries, freshSpotlights) = try await (entriesTask, spotlightsTask)
            BadgeCache.shared.storeBatch(entries: freshEntries)
            cachedEntries[period] = (freshEntries, freshSpotlights, Date())
            // A response for a period the user has since left is cached but not shown.
            guard period == selectedPeriod else { return }
            error = nil
            bannerMessage = nil
            show(entries: freshEntries, spotlights: freshSpotlights, for: period)
        } catch {
            AppLogger.error("leaderboard", "Error loading leaderboard: \(error.localizedDescription)")
            guard reportsFailure, period == selectedPeriod else { return }
            if entries.isEmpty {
                self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            } else {
                bannerMessage = "leaderboard_refresh_failed".localized
            }
        }
    }

    private func show(entries: [LeaderboardEntry], spotlights: [SpotlightEntry], for period: LeaderboardPeriod) {
        self.entries = entries
        self.spotlights = spotlights
        displayedPeriod = period
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



