//
//  NavigationCoordinatorTests.swift
//  NaarsCarsTests
//
//  Unit tests for NavigationCoordinator notifications handling
//

import XCTest
@testable import NaarsCars

@MainActor
final class NavigationCoordinatorTests: XCTestCase {
    override func tearDown() {
        NavigationCoordinator.shared.requestNavigationTarget = nil
        super.tearDown()
    }

    func testDismissNotificationsSheetClearsNavigateFlag() async {
        let coordinator = NavigationCoordinator.shared
        coordinator.navigateToNotifications = true

        NotificationCenter.default.post(
            name: NSNotification.Name("dismissNotificationsSheet"),
            object: nil
        )

        await Task.yield()
        XCTAssertFalse(coordinator.navigateToNotifications)
    }

    func testConsumeRequestNavigationTargetReturnsMatchAndClears() async {
        let coordinator = NavigationCoordinator.shared
        let rideId = UUID()
        coordinator.requestNavigationTarget = RequestNotificationTarget(
            requestType: .ride,
            requestId: rideId,
            anchor: .completeSheet,
            scrollAnchor: nil,
            highlightAnchor: .completeAction,
            shouldAutoClear: true
        )

        let consumed = coordinator.consumeRequestNavigationTarget(for: .ride, requestId: rideId)

        XCTAssertEqual(consumed?.anchor, .completeSheet)
        XCTAssertNil(coordinator.requestNavigationTarget)
    }

    func testConsumeRequestNavigationTargetIgnoresMismatchedRequest() async {
        let coordinator = NavigationCoordinator.shared
        let rideId = UUID()
        coordinator.requestNavigationTarget = RequestNotificationTarget(
            requestType: .ride,
            requestId: rideId,
            anchor: .completeSheet,
            scrollAnchor: nil,
            highlightAnchor: .completeAction,
            shouldAutoClear: true
        )

        let consumed = coordinator.consumeRequestNavigationTarget(for: .ride, requestId: UUID())

        XCTAssertNil(consumed)
        XCTAssertNotNil(coordinator.requestNavigationTarget)
    }
}
