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
    @Published var selectedPeriod: LeaderboardPeriod = .allTime
    @Published var error: AppError?
    @Published var currentUserRank: Int?
    
    // MARK: - Private Properties
    
    private let leaderboardService = LeaderboardService.shared
    private let authService = AuthService.shared
    
    // Cache: [Period: (entries, cachedAt)]
    private var cachedEntries: [LeaderboardPeriod: (entries: [LeaderboardEntry], cachedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 900 // 15 minutes
    
    // MARK: - Public Methods
    
    /// Load leaderboard with caching
    /// Shows cached data immediately, refreshes in background if cache is valid
    func loadLeaderboard() async {
        // Check cache first
        if let cached = cachedEntries[selectedPeriod],
           Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
            entries = cached.entries
            updateCurrentUserRank()
            // Refresh in background
            Task { await fetchFresh(showLoading: false) }
            return
        }
        
        await fetchFresh(showLoading: true)
    }
    
    /// Refresh leaderboard (pull-to-refresh)
    /// Bypasses cache and fetches fresh data
    func refresh() async {
        cachedEntries.removeValue(forKey: selectedPeriod)
        await fetchFresh(showLoading: false)
    }
    
    // MARK: - Private Methods
    
    private func fetchFresh(showLoading: Bool) async {
        if showLoading { isLoading = true }
        error = nil
        defer { if showLoading { isLoading = false } }
        
        do {
            let freshEntries = try await leaderboardService.fetchLeaderboard(period: selectedPeriod)
            entries = freshEntries
            cachedEntries[selectedPeriod] = (freshEntries, Date())
            updateCurrentUserRank()
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("leaderboard", "Error loading leaderboard: \(error.localizedDescription)")
            
            // Keep showing cached data if available
            if cachedEntries[selectedPeriod] == nil {
                // No cache - entries will be empty, error will be shown
            }
        }
    }
    
    private func updateCurrentUserRank() {
        guard let currentUserId = authService.currentUserId else {
            currentUserRank = nil
            return
        }
        
        if let index = entries.firstIndex(where: { $0.userId == currentUserId }) {
            currentUserRank = index + 1 // 1-indexed
        } else {
            // User not in top entries, try to find their rank
            currentUserRank = nil
            Task {
                do {
                    currentUserRank = try await leaderboardService.findCurrentUserRank(
                        userId: currentUserId,
                        period: selectedPeriod
                    )
                } catch {
                    // Silently fail - rank is optional
                }
            }
        }
    }
}



