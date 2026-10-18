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
    private var suiteName = ""
    private var suite: UserDefaults!
    private var savedLaunchState: LaunchState!
    private var savedCommunityContext: CommunityContext!

    override func setUp() {
        super.setUp()
        coordinator.resetNavigation()
        coordinator.selectedTab = .requests
        suiteName = "CommunityContextTests-\(UUID())"
        suite = UserDefaults(suiteName: suiteName)!
        savedLaunchState = AppLaunchManager.shared.state
        savedCommunityContext = AppLaunchManager.shared.communityContext
    }

    override func tearDown() {
        AppLaunchManager.shared.state = savedLaunchState
        AppLaunchManager.shared.communityContext = savedCommunityContext
        suite.removePersistentDomain(forName: suiteName)
        coordinator.resetNavigation()
        coordinator.selectedTab = .requests
        super.tearDown()
    }

    func testEnterAppWhileAuthenticated_DoesNotRelaunch() async {
        let launch = AppLaunchManager.shared
        launch.communityContext = CommunityContext(service: StubCommunityService(result: .success([])), defaults: suite)
        launch.state = .ready(.authenticated)

        await launch.handleEnterAppIntent()

        XCTAssertEqual(launch.state, .ready(.authenticated))
        XCTAssertEqual(coordinator.pendingIntent, .myCommunities)
        XCTAssertEqual(NavigationIntent.myCommunities.targetTab, .profile)
    }

    func testResetNavigationClearsAllKeyRoutingState() {
        coordinator.pendingIntent = .ride(UUID())

        coordinator.resetNavigation()

        XCTAssertNil(coordinator.pendingIntent)
    }

    func testApplyPendingNavigation_RideSelectsRequestsTab() {
        let id = UUID()
        coordinator.deferNotificationIntent(.openRide(rideId: id, anchor: nil))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .requests)
        if case .ride(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, id)
        } else {
            XCTFail("Expected ride intent")
        }
    }

    func testApplyPendingNavigation_FavorSelectsRequestsTab() {
        let id = UUID()
        coordinator.deferNotificationIntent(.openFavor(favorId: id, anchor: nil))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .requests)
        if case .favor(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, id)
        } else {
            XCTFail("Expected favor intent")
        }
    }

    func testApplyPendingNavigation_ConversationSelectsMessagesTab() {
        let id = UUID()
        coordinator.deferNotificationIntent(.openConversation(conversationId: id, scrollTarget: nil))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .messages)
        if case .conversation(let routedId, _) = coordinator.pendingIntent {
            XCTAssertEqual(routedId, id)
        } else {
            XCTFail("Expected conversation intent")
        }
    }

    func testApplyPendingNavigation_TownHallCommentsSelectsCommunityTab() {
        let id = UUID()
        coordinator.deferNotificationIntent(.openTownHallPost(postId: id, mode: .openComments))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .community)
        let consumed = coordinator.consumeTownHallNavigationTarget()
        XCTAssertEqual(consumed?.postId, id)
        XCTAssertEqual(consumed?.mode, .openComments)
    }

    func testApplyPendingNavigation_TownHallHighlightSelectsCommunityTab() {
        let id = UUID()
        coordinator.deferNotificationIntent(.openTownHallPost(postId: id, mode: .highlightPost))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .community)
        let consumed = coordinator.consumeTownHallNavigationTarget()
        XCTAssertEqual(consumed?.postId, id)
        XCTAssertEqual(consumed?.mode, .highlightPost)
    }

    func testApplyPendingNavigation_PendingUsersSelectsProfileTab() {
        coordinator.deferNotificationIntent(.openPendingUsers)
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .profile)
    }

    func testApplyPendingNavigation_EnterAppSelectsRequestsTab() {
        coordinator.deferNotificationIntent(.openDashboard)
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .requests)
    }

    func testApplyPendingNavigation_RequestsTabOnlySelectsRequestsTab() {
        coordinator.selectedTab = .community
        coordinator.deferNotificationIntent(.openDashboard)
        coordinator.applyDeferredNotificationIntentIfNeeded()
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
        coordinator.deferNotificationIntent(.openRide(rideId: target.requestId, anchor: target))
        coordinator.applyDeferredNotificationIntentIfNeeded()
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
        coordinator.deferNotificationIntent(.openFavor(favorId: target.requestId, anchor: target))
        coordinator.applyDeferredNotificationIntentIfNeeded()
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

    // MARK: - Town Hall community_id (multi-community Phase 1)

    func testApplyPushDeepLink_TownHallCommentsCarriesCommunityId() {
        let postId = UUID()
        let communityId = UUID()
        coordinator.applyPushDeepLink(.townHallPostComments(id: postId, communityId: communityId))
        XCTAssertEqual(coordinator.pendingIntent, .townHallPost(postId, mode: .openComments, communityId: communityId))
    }

    func testApplyPushDeepLink_TownHallHighlightWithoutCommunityId() {
        let postId = UUID()
        coordinator.applyPushDeepLink(.townHallPostHighlight(id: postId))
        XCTAssertEqual(coordinator.pendingIntent, .townHallPost(postId, mode: .highlightPost, communityId: nil))
    }

    func testDeferredOpenTownHallPost_ConsumeCarriesCommunityId() {
        let postId = UUID()
        let communityId = UUID()
        coordinator.deferNotificationIntent(.openTownHallPost(postId: postId, mode: .highlightPost, communityId: communityId))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .community)
        let consumed = coordinator.consumeTownHallNavigationTarget()
        XCTAssertEqual(consumed?.postId, postId)
        XCTAssertEqual(consumed?.mode, .highlightPost)
        XCTAssertEqual(consumed?.communityId, communityId)
        XCTAssertNil(coordinator.pendingIntent)
    }

    func testRouter_ContentHiddenBellRowCarriesCommunityId() {
        let userId = UUID()
        let postId = UUID()
        let communityId = UUID()
        let notification = AppNotification(
            userId: userId,
            type: .contentHidden,
            title: "t",
            townHallPostId: postId,
            communityId: communityId
        )
        XCTAssertEqual(
            NotificationNavigationRouter().notificationIntent(for: notification),
            .openTownHallPost(postId: postId, mode: .highlightPost, communityId: communityId)
        )
    }
    // MARK: - pending_approval for a community (multi-community Phase 2)

    func testApplyPushDeepLink_PendingMembersSetsIntentForProfileTab() {
        let communityId = UUID()
        coordinator.applyPushDeepLink(.pendingMembers(communityId: communityId))
        XCTAssertEqual(coordinator.pendingIntent, .pendingMembers(communityId))
        XCTAssertEqual(coordinator.pendingIntent?.targetTab, .profile)
    }

    func testDeferredOpenPendingMembers_SelectsProfileTab() {
        let communityId = UUID()
        coordinator.deferNotificationIntent(.openPendingMembers(communityId: communityId))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .profile)
        XCTAssertEqual(coordinator.pendingIntent, .pendingMembers(communityId))
    }

    func testRouter_PendingApprovalBellRowWithCommunityOpensPendingMembers() {
        let communityId = UUID()
        let notification = AppNotification(
            userId: UUID(),
            type: .pendingApproval,
            title: "t",
            communityId: communityId
        )
        XCTAssertEqual(
            NotificationNavigationRouter().notificationIntent(for: notification),
            .openPendingMembers(communityId: communityId)
        )
    }

    func testRouter_PendingApprovalBellRowWithoutCommunityOpensPendingUsers() {
        let notification = AppNotification(
            userId: UUID(),
            type: .pendingApproval,
            title: "t"
        )
        XCTAssertEqual(
            NotificationNavigationRouter().notificationIntent(for: notification),
            .openPendingUsers
        )
    }

    func testPendingMembersIsAdminOnlyAndMyCommunitiesRequiresAuth() {
        let pending = NavigationIntent.pendingMembers(UUID())
        XCTAssertTrue(coordinator.intentIsAdminOnly(pending))
        XCTAssertFalse(coordinator.intentRequiresAuth(pending))
        XCTAssertTrue(coordinator.intentRequiresAuth(.myCommunities))
        XCTAssertFalse(coordinator.intentIsAdminOnly(.myCommunities))
        XCTAssertEqual(NavigationIntent.myCommunities.targetTab, .profile)
    }
}
