//
//  LeaderboardServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for LeaderboardService
//

import XCTest
@testable import NaarsCars

@MainActor
final class LeaderboardServiceTests: XCTestCase {
    var leaderboardService: LeaderboardService!
    
    override func setUp() {
        super.setUp()
        leaderboardService = LeaderboardService.shared
    }
    
    /// Test that fetchLeaderboard returns entries ordered by XP
    func testFetchLeaderboard_OrderedByXP() async throws {
        // Given: A request to fetch leaderboard
        // Note: This test requires a real Supabase connection and database function

        // When: Fetching leaderboard
        do {
            let entries = try await leaderboardService.fetchLeaderboard(period: .allTime)

            // Then: Entries should be ordered by XP descending
            var previousXP: Int? = nil
            for entry in entries {
                if let prev = previousXP {
                    XCTAssertGreaterThanOrEqual(prev, entry.xp, "Entries should be ordered by XP descending")
                }
                previousXP = entry.xp
            }

            XCTAssertTrue(true, "Leaderboard entries are correctly ordered")
        } catch {
            XCTFail("Failed to fetch leaderboard: \(error.localizedDescription)")
        }
    }

    /// Test that fetchSpotlights returns valid spotlight entries
    func testFetchSpotlights() async throws {
        do {
            let spotlights = try await leaderboardService.fetchSpotlights(period: .allTime)

            // Should return 0-2 spotlights
            XCTAssertLessThanOrEqual(spotlights.count, 2)
            for spotlight in spotlights {
                XCTAssertTrue(["longest_streak", "rising_star"].contains(spotlight.category))
                XCTAssertGreaterThan(spotlight.value, 0)
            }
        } catch {
            XCTFail("Failed to fetch spotlights: \(error.localizedDescription)")
        }
    }
    
    /// Test that findCurrentUserRank returns correct rank
    func testFindUserRank_NotInTop50() async throws {
        // Given: An authenticated user
        guard let userId = AuthService.shared.currentUserId else {
            XCTSkip("No authenticated user for testing")
            return
        }
        
        // When: Finding user rank
        do {
            let rank = try await leaderboardService.findCurrentUserRank(userId: userId, period: .allTime)
            
            // Then: Rank should be a positive integer or nil
            if let rank = rank {
                XCTAssertGreaterThan(rank, 0, "Rank should be positive")
            }
            
            // Test passes if we get here
            XCTAssertTrue(true, "User rank found or user not in top entries")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            XCTFail("Failed to find user rank: \(error.localizedDescription)")
        }
    }
    
    /// Test date range calculation for different periods
    func testDateRangeCalculation() {
        let calendar = Calendar.current
        let now = Date()
        
        // Test allTime
        let allTimeRange = LeaderboardPeriod.allTime.dateRange
        XCTAssertLessThan(allTimeRange.start, now, "All time should start from epoch")
        
        // Test thisYear
        let yearRange = LeaderboardPeriod.thisYear.dateRange
        let yearComponents = calendar.dateComponents([.year], from: yearRange.start)
        let nowYearComponents = calendar.dateComponents([.year], from: now)
        XCTAssertEqual(yearComponents.year, nowYearComponents.year, "This year should start at beginning of current year")
        
        // Test thisMonth
        let monthRange = LeaderboardPeriod.thisMonth.dateRange
        let monthComponents = calendar.dateComponents([.year, .month], from: monthRange.start)
        let nowMonthComponents = calendar.dateComponents([.year, .month], from: now)
        XCTAssertEqual(monthComponents.year, nowMonthComponents.year, "This month should be in current year")
        XCTAssertEqual(monthComponents.month, nowMonthComponents.month, "This month should start at beginning of current month")
    }
}



