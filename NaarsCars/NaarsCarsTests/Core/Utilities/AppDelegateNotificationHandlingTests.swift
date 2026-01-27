//
//  AppDelegateNotificationHandlingTests.swift
//  NaarsCarsTests
//
//  Unit tests for AppDelegate notification handling helpers
//

import Foundation
import XCTest
@testable import NaarsCars

final class AppDelegateNotificationHandlingTests: XCTestCase {

    func testShouldShowReviewPrompt_ForReviewRequest() {
        XCTAssertTrue(AppDelegate.shouldShowReviewPrompt(for: "review_request"))
    }

    func testShouldShowReviewPrompt_ForReviewReminder() {
        XCTAssertTrue(AppDelegate.shouldShowReviewPrompt(for: "review_reminder"))
    }

    func testShouldShowReviewPrompt_ForOtherType() {
        XCTAssertFalse(AppDelegate.shouldShowReviewPrompt(for: "ride_completed"))
    }

    func testShouldShowReviewPrompt_ForNilType() {
        XCTAssertFalse(AppDelegate.shouldShowReviewPrompt(for: nil))
    }

    func testAppRefreshTaskFromAny_ReturnsNilForUnexpectedType() {
        XCTAssertNil(AppDelegate.appRefreshTask(from: NSObject()))
    }
}
