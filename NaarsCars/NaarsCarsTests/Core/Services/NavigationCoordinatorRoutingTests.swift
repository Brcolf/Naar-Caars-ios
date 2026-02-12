//
//  NavigationCoordinatorRoutingTests.swift
//  NaarsCars
//
//  Unit tests for NavigationCoordinator deferred routing
//

import XCTest
@testable import NaarsCars

@MainActor
final class NavigationCoordinatorRoutingTests: XCTestCase {
    private let coordinator = NavigationCoordinator.shared

    override func setUp() {
        super.setUp()
        coordinator.resetNavigation()
        coordinator.selectedTab = .requests
    }

    override func tearDown() {
        coordinator.resetNavigation()
        coordinator.selectedTab = .requests
        super.tearDown()
    }

    func testResetNavigationClearsAllKeyRoutingState() {
        coordinator.pendingIntent = .ride(UUID())

        coordinator.resetNavigation()

        XCTAssertNil(coordinator.pendingIntent)
    }

    func testApplyPendingNavigation_RideSelectsRequestsTab() {
        let id = UUID()
        coordinator.pendingIntent = .ride(id)
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .requests)
        if case .ride(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, id)
        } else {
            XCTFail("Expected ride intent")
        }
    }

    func testApplyPendingNavigation_FavorSelectsRequestsTab() {
        let id = UUID()
        coordinator.pendingIntent = .favor(id)
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .requests)
        if case .favor(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, id)
        } else {
            XCTFail("Expected favor intent")
        }
    }

    func testApplyPendingNavigation_ConversationSelectsMessagesTab() {
        let id = UUID()
        coordinator.pendingIntent = .conversation(id)
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .messages)
        if case .conversation(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, id)
        } else {
            XCTFail("Expected conversation intent")
        }
    }

    func testApplyPendingNavigation_TownHallCommentsSelectsCommunityTab() {
        let id = UUID()
        coordinator.pendingIntent = .townHallPost(id, mode: .openComments)
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .community)
        let consumed = coordinator.consumeTownHallNavigationTarget()
        XCTAssertEqual(consumed?.postId, id)
        XCTAssertEqual(consumed?.mode, .openComments)
    }

    func testApplyPendingNavigation_TownHallHighlightSelectsCommunityTab() {
        let id = UUID()
        coordinator.pendingIntent = .townHallPost(id, mode: .highlightPost)
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .community)
        let consumed = coordinator.consumeTownHallNavigationTarget()
        XCTAssertEqual(consumed?.postId, id)
        XCTAssertEqual(consumed?.mode, .highlightPost)
    }

    func testApplyPendingNavigation_PendingUsersSelectsProfileTab() {
        coordinator.pendingIntent = .pendingUsers
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .profile)
    }

    func testApplyPendingNavigation_EnterAppSelectsRequestsTab() {
        coordinator.pendingIntent = .dashboard
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .requests)
    }

    func testApplyPendingNavigation_RequestsTabOnlySelectsRequestsTab() {
        coordinator.selectedTab = .community
        coordinator.pendingIntent = .dashboard
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .requests)
    }

    func testApplyPendingNavigation_RequestTargetRideSelectsRequestsTabAndSetsTarget() {
        let target = RequestNotificationTarget(
            requestType: .ride,
            requestId: UUID(),
            anchor: .mainTop,
            scrollAnchor: nil,
            highlightAnchor: .mainTop,
            shouldAutoClear: true
        )
        coordinator.pendingIntent = .ride(target.requestId, anchor: target)
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .requests)
        let consumed = coordinator.consumeRequestNavigationTarget(for: .ride, requestId: target.requestId)
        XCTAssertEqual(consumed, target)
    }

    func testApplyPendingNavigation_RequestTargetFavorSelectsRequestsTabAndSetsTarget() {
        let target = RequestNotificationTarget(
            requestType: .favor,
            requestId: UUID(),
            anchor: .mainTop,
            scrollAnchor: nil,
            highlightAnchor: .mainTop,
            shouldAutoClear: true
        )
        coordinator.pendingIntent = .favor(target.requestId, anchor: target)
        coordinator.applyDeferredIntentAfterNotificationsDismissal()
        XCTAssertEqual(coordinator.selectedTab, .requests)
        let consumed = coordinator.consumeRequestNavigationTarget(for: .favor, requestId: target.requestId)
        XCTAssertEqual(consumed, target)
    }

    func testConsumeRequestIntentClearsPendingIntentAfterApply() {
        let rideId = UUID()
        let target = RequestNotificationTarget(
            requestType: .ride,
            requestId: rideId,
            anchor: .mainTop,
            scrollAnchor: nil,
            highlightAnchor: nil,
            shouldAutoClear: true
        )
        coordinator.pendingIntent = .ride(rideId, anchor: target)
        _ = coordinator.consumeRequestNavigationTarget(for: .ride, requestId: rideId)
        XCTAssertNil(coordinator.pendingIntent)
    }

    func testDeepLinkParserMessageRoundTripToNavigationState() {
        let conversationId = UUID()
        let payload: [AnyHashable: Any] = [
            "type": "message",
            "conversation_id": conversationId.uuidString
        ]
        let deepLink = DeepLinkParser.parse(userInfo: payload)
        coordinator.navigate(to: deepLink)
        if case .conversation(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, conversationId)
        } else {
            XCTFail("Expected conversation intent")
        }
    }

    func testDeepLinkParserRideRoundTripToNavigationState() {
        let rideId = UUID()
        let payload: [AnyHashable: Any] = [
            "type": "ride_claimed",
            "ride_id": rideId.uuidString
        ]
        let deepLink = DeepLinkParser.parse(userInfo: payload)
        coordinator.navigate(to: deepLink)
        if case .ride(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, rideId)
        } else {
            XCTFail("Expected ride intent")
        }
    }
}
