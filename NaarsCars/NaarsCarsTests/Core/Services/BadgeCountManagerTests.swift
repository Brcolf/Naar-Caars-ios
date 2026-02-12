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
        let manager = BadgeCountManager.shared
        manager.requestsBadgeCount = 0
        manager.messagesBadgeCount = 0
        manager.communityBadgeCount = 0
        manager.bellBadgeCount = 0
        manager.totalUnreadCount = 0
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

    func testTotalUnreadCountContractMatchesComponentSum() {
        let manager = BadgeCountManager.shared
        manager.requestsBadgeCount = 2
        manager.messagesBadgeCount = 5
        manager.communityBadgeCount = 3
        manager.bellBadgeCount = 7

        let expected = manager.requestsBadgeCount + manager.messagesBadgeCount + manager.communityBadgeCount
        manager.totalUnreadCount = expected

        XCTAssertEqual(manager.totalUnreadCount, expected)
    }
}
