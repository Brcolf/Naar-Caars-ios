//
//  LeaderboardBadgeTests.swift
//  NaarsCarsTests
//
//  Unit tests for LeaderboardBadge enum
//

import XCTest
@testable import NaarsCars

final class LeaderboardBadgeTests: XCTestCase {

    func testDecodingFromString() throws {
        let json = "\"road_warrior\"".data(using: .utf8)!
        let badge = try JSONDecoder().decode(LeaderboardBadge.self, from: json)
        XCTAssertEqual(badge, .roadWarrior)
    }

    func testAllBadgesHaveDisplayName() {
        for badge in LeaderboardBadge.allCases {
            XCTAssertFalse(badge.displayName.isEmpty)
        }
    }

    func testAllBadgesHaveIcon() {
        for badge in LeaderboardBadge.allCases {
            XCTAssertFalse(badge.iconName.isEmpty)
        }
    }

    func testDecodingArray() throws {
        let json = "[\"road_warrior\",\"five_star\"]".data(using: .utf8)!
        let badges = try JSONDecoder().decode([LeaderboardBadge].self, from: json)
        XCTAssertEqual(badges, [.roadWarrior, .fiveStar])
    }

    func testAllBadgesHaveEmoji() {
        for badge in LeaderboardBadge.allCases {
            XCTAssertFalse(badge.emoji.isEmpty)
        }
    }
}
