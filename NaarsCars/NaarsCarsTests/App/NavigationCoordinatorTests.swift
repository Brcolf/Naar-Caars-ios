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
        NavigationCoordinator.shared.pendingIntent = nil
        super.tearDown()
    }

    func testDismissNotificationsSheetClearsNavigateFlag() async {
        let coordinator = NavigationCoordinator.shared
        coordinator.pendingIntent = .notifications

        NotificationCenter.default.post(
            name: NSNotification.Name("dismissNotificationsSheet"),
            object: nil
        )

        await Task.yield()
        XCTAssertNil(coordinator.pendingIntent)
    }

    func testConsumeRequestNavigationTargetReturnsMatchAndClears() async {
        let coordinator = NavigationCoordinator.shared
        let rideId = UUID()
        let target = RequestNotificationTarget(
            requestType: .ride,
            requestId: rideId,
            anchor: .completeSheet,
            scrollAnchor: nil,
            highlightAnchor: .completeAction,
            shouldAutoClear: true
        )
        coordinator.pendingIntent = .ride(rideId, anchor: target)

        let consumed = coordinator.consumeRequestNavigationTarget(for: .ride, requestId: rideId)

        XCTAssertEqual(consumed?.anchor, .completeSheet)
        XCTAssertNil(coordinator.pendingIntent)
    }

    func testConsumeRequestNavigationTargetIgnoresMismatchedRequest() async {
        let coordinator = NavigationCoordinator.shared
        let rideId = UUID()
        let target = RequestNotificationTarget(
            requestType: .ride,
            requestId: rideId,
            anchor: .completeSheet,
            scrollAnchor: nil,
            highlightAnchor: .completeAction,
            shouldAutoClear: true
        )
        coordinator.pendingIntent = .ride(rideId, anchor: target)

        let consumed = coordinator.consumeRequestNavigationTarget(for: .ride, requestId: UUID())

        XCTAssertNil(consumed)
        XCTAssertNotNil(coordinator.pendingIntent)
    }
}
