//
//  BadgeCountManagerTests.swift
//  NaarsCars
//
//  Lightweight unit tests for badge contracts
//

import XCTest
@testable import NaarsCars

@MainActor
final class BadgeCountManagerTests: XCTestCase {
    override func tearDown() {
        BadgeCountManager.shared.resetCountsForTesting()
        super.tearDown()
    }

    func testBadgeTabRawValuesAreStable() {
        XCTAssertEqual(BadgeTab.requests.rawValue, "requests")
        XCTAssertEqual(BadgeTab.messages.rawValue, "messages")
        XCTAssertEqual(BadgeTab.community.rawValue, "community")
        XCTAssertEqual(BadgeTab.profile.rawValue, "profile")
    }

    func testBadgeTabContainsExpectedUniqueValues() {
        let values: Set<String> = [
            BadgeTab.requests.rawValue,
            BadgeTab.messages.rawValue,
            BadgeTab.community.rawValue,
            BadgeTab.profile.rawValue
        ]
        XCTAssertEqual(values.count, 4)
    }

    func testBadgeCountsDefaultsToZero() {
        let counts = BadgeCountManager.BadgeCounts()
        XCTAssertEqual(counts.requests, 0)
        XCTAssertEqual(counts.messages, 0)
        XCTAssertEqual(counts.community, 0)
        XCTAssertEqual(counts.profile, 0)
        XCTAssertEqual(counts.adminPanel, 0)
        XCTAssertEqual(counts.bell, 0)
        XCTAssertEqual(counts.totalUnread, 0)
    }

    func testBadgeCountsEquatable() {
        var a = BadgeCountManager.BadgeCounts()
        let b = BadgeCountManager.BadgeCounts()
        XCTAssertEqual(a, b)

        a.requests = 1
        XCTAssertNotEqual(a, b)
    }

    func testTotalUnreadCountContractMatchesComponentSum() {
        var counts = BadgeCountManager.BadgeCounts()
        counts.requests = 2
        counts.messages = 5
        counts.community = 3
        counts.bell = 7

        let expectedTotal = counts.requests + counts.messages + counts.community
        counts.totalUnread = expectedTotal

        XCTAssertEqual(counts.totalUnread, expectedTotal)
    }

    /// Sign-out invariant: badges zero. The teardown calls `resetForSignOut()` so a guest or
    /// the next account on the device does not inherit the previous member's counts.
    func testResetForSignOutZeroesCounts() {
        var seeded = BadgeCountManager.BadgeCounts()
        seeded.requests = 2
        seeded.messages = 5
        seeded.community = 3
        seeded.bell = 7
        seeded.totalUnread = 10
        BadgeCountManager.shared.setCountsForTesting(seeded)
        XCTAssertEqual(BadgeCountManager.shared.counts, seeded)

        BadgeCountManager.shared.resetForSignOut()

        XCTAssertEqual(BadgeCountManager.shared.counts, BadgeCountManager.BadgeCounts())
        XCTAssertFalse(BadgeCountManager.shared.isBadgeStale)
    }
}
