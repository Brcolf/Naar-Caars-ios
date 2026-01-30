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
}
