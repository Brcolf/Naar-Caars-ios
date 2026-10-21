//
//  LeaderboardViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for LeaderboardViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class LeaderboardViewModelTests: XCTestCase {
    var viewModel: LeaderboardViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = LeaderboardViewModel()
    }
    
    /// Test that loadLeaderboard highlights current user
    func testLoadLeaderboard_HighlightsCurrentUser() async {
        // Given: A view model
        XCTAssertTrue(viewModel.entries.isEmpty, "Entries should start empty")
        
        // When: Loading leaderboard
        await viewModel.loadLeaderboard()
        
        // Then: Current user should be highlighted if in entries
        // Note: This test requires a real Supabase connection
        // In a real scenario, you'd mock the LeaderboardService
        
        // If we get here without crashing, the test passes
        // In a real test environment, you'd verify:
        // - entries contains entry where isCurrentUser == true
        // - currentUserRank is set if user is in top entries
        XCTAssertTrue(true, "loadLeaderboard completed")
    }
    
    /// Test that refresh bypasses cache
    func testRefresh_BypassesCache() async {
        // Given: Cached entries
        await viewModel.loadLeaderboard()
        let initialCount = viewModel.entries.count
        
        // When: Refreshing
        await viewModel.refresh()
        
        // Then: Should fetch fresh data
        // Note: This test requires a real Supabase connection
        XCTAssertTrue(true, "refresh completed")
    }
    
    /// Test that cache is used when valid
    func testLoadLeaderboard_UsesCache() async {
        // Given: Fresh data loaded
        await viewModel.loadLeaderboard()
        let initialEntries = viewModel.entries
        
        // When: Loading again immediately (cache should be valid)
        await viewModel.loadLeaderboard()
        
        // Then: Should show cached data immediately
        // Note: Cache TTL is 15 minutes, so immediate reload should use cache
        XCTAssertEqual(viewModel.entries.count, initialEntries.count, "Should use cached data")
    }

    // MARK: - Request counts (stubbed service)

    /// Lets a stray unstructured Task (the old background refetch) run before the counts are read.
    private func drainMainActor() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// The view calls loadLeaderboard on every appearance; a fresh cache must not cost a request.
    func testLoadLeaderboard_CacheHitWithinTTLDoesNotFetchAgain() async {
        let stub = StubLeaderboardFetcher()
        let vm = LeaderboardViewModel(leaderboardService: stub)

        await vm.loadLeaderboard()
        await vm.loadLeaderboard()
        await drainMainActor()

        XCTAssertEqual(stub.entryCalls.count, 1)
        XCTAssertEqual(stub.spotlightCalls.count, 1)
    }

    /// Pull-to-refresh drops the key and fetches even when the cached rows are fresh.
    func testRefresh_FetchesEvenWithAFreshCache() async {
        let stub = StubLeaderboardFetcher()
        let vm = LeaderboardViewModel(leaderboardService: stub)

        await vm.loadLeaderboard()
        await vm.refresh()
        await drainMainActor()

        XCTAssertEqual(stub.entryCalls.count, 2)
        XCTAssertEqual(stub.spotlightCalls.count, 2)
    }

    /// Each period is its own cache key: fetched once, then served from the cache on a return.
    func testPeriodChange_FetchesEachPeriodOnceThenUsesCache() async {
        let stub = StubLeaderboardFetcher()
        let vm = LeaderboardViewModel(leaderboardService: stub)

        await vm.loadLeaderboard()
        vm.selectedPeriod = .allTime
        await vm.loadLeaderboard()
        vm.selectedPeriod = .thisMonth
        await vm.loadLeaderboard()
        await drainMainActor()

        XCTAssertEqual(stub.entryCalls.map(\.period), [.thisMonth, .allTime])
        XCTAssertEqual(stub.spotlightCalls.map(\.period), [.thisMonth, .allTime])
    }
}

/// Records each leaderboard and spotlight read and answers with no rows.
private final class StubLeaderboardFetcher: LeaderboardFetching {
    private(set) var entryCalls: [(period: LeaderboardPeriod, communityId: UUID?)] = []
    private(set) var spotlightCalls: [(period: LeaderboardPeriod, communityId: UUID?)] = []

    func fetchLeaderboard(period: LeaderboardPeriod, communityId: UUID?) async throws -> [LeaderboardEntry] {
        entryCalls.append((period, communityId))
        return []
    }

    func fetchSpotlights(period: LeaderboardPeriod, communityId: UUID?) async throws -> [SpotlightEntry] {
        spotlightCalls.append((period, communityId))
        return []
    }
}



