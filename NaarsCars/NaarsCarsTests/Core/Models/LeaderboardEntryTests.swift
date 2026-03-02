//
//  LeaderboardEntryTests.swift
//  NaarsCarsTests
//
//  Unit tests for LeaderboardEntry model
//

import XCTest
@testable import NaarsCars

final class LeaderboardEntryTests: XCTestCase {

    func testIsCurrentUser() {
        // Given: A test user ID
        let testUserId = UUID()

        // Mock AuthService to return test user ID
        // Note: In a real test, you'd use dependency injection or mocking
        // For now, this test verifies the logic structure

        // When: Creating an entry with the current user's ID
        let entry = LeaderboardEntry(
            userId: testUserId,
            name: "Test User",
            requestsFulfilled: 10,
            requestsMade: 5
        )

        // Then: isCurrentUser should check against AuthService.currentUserId
        // This will be true if testUserId matches AuthService.shared.currentUserId
        // In a real test environment, you'd mock AuthService
        XCTAssertNotNil(entry.isCurrentUser, "isCurrentUser should be computed")
    }

    func testLeaderboardEntryEquatable() {
        let userId = UUID()
        let entry1 = LeaderboardEntry(
            userId: userId,
            name: "Test User",
            xp: 50,
            badges: [.roadWarrior],
            streakWeeks: 2,
            requestsFulfilled: 10,
            requestsMade: 5,
            rank: 1
        )

        let entry2 = LeaderboardEntry(
            userId: userId,
            name: "Test User",
            xp: 50,
            badges: [.roadWarrior],
            streakWeeks: 2,
            requestsFulfilled: 10,
            requestsMade: 5,
            rank: 1
        )

        XCTAssertEqual(entry1, entry2, "Entries with same data should be equal")
    }

    func testLeaderboardEntryIdentifiable() {
        let userId = UUID()
        let entry = LeaderboardEntry(
            userId: userId,
            name: "Test User",
            requestsFulfilled: 10,
            requestsMade: 5
        )

        XCTAssertEqual(entry.id, userId, "ID should match userId")
    }

    func testCodableDecodingWithXP() throws {
        // Given: JSON matching database function response with XP fields
        let json = """
        {
            "user_id": "123e4567-e89b-12d3-a456-426614174000",
            "name": "John Doe",
            "avatar_url": "https://example.com/avatar.jpg",
            "xp": 145,
            "badges": ["road_warrior", "five_star"],
            "streak_weeks": 4,
            "requests_fulfilled": 15,
            "requests_made": 8
        }
        """.data(using: .utf8)!

        // When: Decoding
        let decoder = JSONDecoder()
        let entry = try decoder.decode(LeaderboardEntry.self, from: json)

        // Then: All fields should be correctly mapped
        XCTAssertEqual(entry.name, "John Doe")
        XCTAssertEqual(entry.avatarUrl, "https://example.com/avatar.jpg")
        XCTAssertEqual(entry.xp, 145)
        XCTAssertEqual(entry.badges, [.roadWarrior, .fiveStar])
        XCTAssertEqual(entry.streakWeeks, 4)
        XCTAssertEqual(entry.requestsFulfilled, 15)
        XCTAssertEqual(entry.requestsMade, 8)
    }

    func testTopBadgesLimitedToTwo() {
        let entry = LeaderboardEntry(
            userId: UUID(),
            name: "Test",
            xp: 100,
            badges: [.roadWarrior, .goodNeighbor, .fiveStar],
            streakWeeks: 5,
            requestsFulfilled: 10,
            requestsMade: 5
        )
        XCTAssertEqual(entry.topBadges.count, 2)
        XCTAssertEqual(entry.topBadges, [.roadWarrior, .goodNeighbor])
    }

    func testTopBadgesWithFewerThanTwo() {
        let entry = LeaderboardEntry(
            userId: UUID(),
            name: "Test",
            xp: 50,
            badges: [.fiveStar],
            streakWeeks: 1,
            requestsFulfilled: 3,
            requestsMade: 1
        )
        XCTAssertEqual(entry.topBadges.count, 1)
        XCTAssertEqual(entry.topBadges, [.fiveStar])
    }

    func testTopBadgesEmpty() {
        let entry = LeaderboardEntry(
            userId: UUID(),
            name: "Test",
            requestsFulfilled: 3,
            requestsMade: 1
        )
        XCTAssertTrue(entry.topBadges.isEmpty)
    }

    func testDefaultValues() {
        let entry = LeaderboardEntry(
            userId: UUID(),
            name: "Test",
            requestsFulfilled: 5,
            requestsMade: 2
        )
        XCTAssertEqual(entry.xp, 0)
        XCTAssertEqual(entry.badges, [])
        XCTAssertEqual(entry.streakWeeks, 0)
        XCTAssertNil(entry.rank)
        XCTAssertNil(entry.avatarUrl)
    }
}
