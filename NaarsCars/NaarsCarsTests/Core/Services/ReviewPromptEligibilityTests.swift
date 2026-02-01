//
//  ReviewPromptEligibilityTests.swift
//  NaarsCarsTests
//
//  Tests for review prompt eligibility logic
//

import XCTest
@testable import NaarsCars

final class ReviewPromptEligibilityTests: XCTestCase {
    func testPromptEligibleImmediatelyAfterEvent() {
        let event = Date()
        let now = event.addingTimeInterval(60) // 1 minute later
        XCTAssertTrue(ReviewService.isReviewPromptEligible(eventTime: event, now: now))
    }
}
