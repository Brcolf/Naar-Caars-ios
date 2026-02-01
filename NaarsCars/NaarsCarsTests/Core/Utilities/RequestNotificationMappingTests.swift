//
//  RequestNotificationMappingTests.swift
//  NaarsCarsTests
//
//  Unit tests for RequestNotificationMapping
//

import XCTest
@testable import NaarsCars

final class RequestNotificationMappingTests: XCTestCase {
    func testCompletionReminderUsesMainTopAnchor() {
        let target = RequestNotificationMapping.target(
            for: .completionReminder,
            rideId: UUID(),
            favorId: nil
        )
        XCTAssertEqual(target?.anchor, .mainTop)
        XCTAssertEqual(target?.shouldAutoClear, false)
    }
}
