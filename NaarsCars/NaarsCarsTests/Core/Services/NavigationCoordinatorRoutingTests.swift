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
        XCTAssertEqual(NavigationIntent.myCommunities.targetTab, .explore)
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

    func testApplyPendingNavigation_TownHallCommentsSelectsTownHallTab() {
        let id = UUID()
        coordinator.deferNotificationIntent(.openTownHallPost(postId: id, mode: .openComments))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .townHall)
        let consumed = coordinator.consumeTownHallNavigationTarget()
        XCTAssertEqual(consumed?.postId, id)
        XCTAssertEqual(consumed?.mode, .openComments)
    }

    func testApplyPendingNavigation_TownHallHighlightSelectsTownHallTab() {
        let id = UUID()
        coordinator.deferNotificationIntent(.openTownHallPost(postId: id, mode: .highlightPost))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .townHall)
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
        coordinator.selectedTab = .townHall
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

    /// A request push from another community opens the request on Requests. The filter and the
    /// Town Hall community are left alone because nothing on this path touches them (checked on
    /// a device at the gate).
    func testNewRidePushFromAnotherCommunity_OpensOnRequestsAndLeavesTheFilter() {
        let b = CommunityFixtures.communityB, rideId = UUID()
        let link = DeepLinkParser.parse(userInfo: ["type": "new_ride", "ride_id": rideId.uuidString, "community_id": b.uuidString])
        guard case .ride(let id) = link else { return XCTFail("Expected a ride deep link, got \(link)") }
        XCTAssertEqual(id, rideId)
        coordinator.applyPushDeepLink(link)
        XCTAssertEqual(coordinator.pendingIntent, .ride(rideId, anchor: nil))
        XCTAssertEqual(coordinator.pendingIntent?.targetTab, .requests)
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
        XCTAssertEqual(coordinator.selectedTab, .townHall)
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

    func testApplyPushDeepLink_PendingMembersSetsIntentForExploreTab() {
        let communityId = UUID()
        coordinator.applyPushDeepLink(.pendingMembers(communityId: communityId))
        XCTAssertEqual(coordinator.pendingIntent, .pendingMembers(communityId))
        XCTAssertEqual(coordinator.pendingIntent?.targetTab, .explore)
    }

    func testDeferredOpenPendingMembers_SelectsExploreTab() {
        let communityId = UUID()
        coordinator.deferNotificationIntent(.openPendingMembers(communityId: communityId))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .explore)
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
        XCTAssertEqual(NavigationIntent.myCommunities.targetTab, .explore)
    }

    // MARK: - content_reported and account_restricted (multi-community Phase 3)

    func testApplyPushDeepLink_CommunityReportsSetsIntentForExploreTab() {
        let communityId = UUID()
        coordinator.applyPushDeepLink(.communityReports(communityId: communityId))
        XCTAssertEqual(coordinator.pendingIntent, .communityReports(communityId))
        XCTAssertEqual(coordinator.pendingIntent?.targetTab, .explore)

        coordinator.resetNavigation()
        coordinator.applyPushDeepLink(.myCommunities)
        XCTAssertEqual(coordinator.pendingIntent, .myCommunities)
    }

    func testDeferredOpenCommunityReports_SelectsExploreTab() {
        let communityId = UUID()
        coordinator.deferNotificationIntent(.openCommunityReports(communityId: communityId))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .explore)
        XCTAssertEqual(coordinator.pendingIntent, .communityReports(communityId))

        coordinator.resetNavigation()
        coordinator.selectedTab = .requests
        coordinator.deferNotificationIntent(.openMyCommunities)
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .explore)
        XCTAssertEqual(coordinator.pendingIntent, .myCommunities)
    }

    func testRouter_ContentReportedRowForCommunityAdminOpensCommunityReports() {
        let communityId = UUID()
        let notification = AppNotification(
            userId: UUID(),
            type: .contentReported,
            title: "t",
            townHallPostId: UUID(),
            communityId: communityId
        )
        XCTAssertEqual(
            NotificationNavigationRouter(isPlatformAdmin: { false }).notificationIntent(for: notification),
            .openCommunityReports(communityId: communityId)
        )
    }

    /// A platform admin's bell row carries a derived community too; it keeps the platform list.
    func testRouter_ContentReportedRowForPlatformAdminOpensAdminReports() {
        let notification = AppNotification(
            userId: UUID(),
            type: .contentReported,
            title: "t",
            townHallPostId: UUID(),
            communityId: UUID()
        )
        XCTAssertEqual(
            NotificationNavigationRouter(isPlatformAdmin: { true }).notificationIntent(for: notification),
            .openAdminReports
        )
    }

    func testRouter_ContentReportedRowWithoutCommunityOpensAdminReports() {
        let notification = AppNotification(
            userId: UUID(),
            type: .contentReported,
            title: "t"
        )
        XCTAssertEqual(
            NotificationNavigationRouter(isPlatformAdmin: { false }).notificationIntent(for: notification),
            .openAdminReports
        )
    }

    func testRouter_AccountRestrictedRowOpensMyCommunities() {
        let notification = AppNotification(
            userId: UUID(),
            type: .accountRestricted,
            title: "t",
            communityId: UUID()
        )
        XCTAssertEqual(
            NotificationNavigationRouter(isPlatformAdmin: { false }).notificationIntent(for: notification),
            .openMyCommunities
        )
    }

    func testCommunityReportsIsAdminOnlyForGuests() {
        let reports = NavigationIntent.communityReports(UUID())
        XCTAssertTrue(coordinator.intentIsAdminOnly(reports))
        XCTAssertFalse(coordinator.intentRequiresAuth(reports))
        XCTAssertEqual(reports.targetTab, .explore)
    }

    // MARK: - membership_update (multi-community Phase 4)

    func testApplyPushDeepLink_CommunityMembersSetsIntentForExploreTab() {
        let communityId = UUID()
        coordinator.applyPushDeepLink(.communityMembers(communityId: communityId))
        XCTAssertEqual(coordinator.pendingIntent, .communityMembers(communityId))
        XCTAssertEqual(coordinator.pendingIntent?.targetTab, .explore)
    }

    func testDeferredOpenCommunityMembers_SelectsExploreTab() {
        let communityId = UUID()
        coordinator.deferNotificationIntent(.openCommunityMembers(communityId: communityId))
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .explore)
        XCTAssertEqual(coordinator.pendingIntent, .communityMembers(communityId))
        XCTAssertNil(coordinator.deferredNotificationIntent)
    }

    /// An ownership row, read after the push refreshed the memberships: the person administers
    /// the row's community, so it opens that community's members.
    func testRouter_MembershipUpdateRowForAnAdminOpensMembers() {
        let communityId = UUID()
        let notification = AppNotification(
            userId: UUID(),
            type: .membershipUpdate,
            title: "t",
            communityId: communityId
        )
        var askedAbout: UUID?
        let router = NotificationNavigationRouter(
            isPlatformAdmin: { false },
            isAdminOf: { askedAbout = $0; return true }
        )
        XCTAssertEqual(router.notificationIntent(for: notification), .openCommunityMembers(communityId: communityId))
        XCTAssertEqual(askedAbout, communityId)
    }

    /// A further-community approval (the person is a plain member there): My communities.
    func testRouter_MembershipUpdateRowForAMemberOpensMyCommunities() {
        let notification = AppNotification(
            userId: UUID(),
            type: .membershipUpdate,
            title: "t",
            communityId: UUID()
        )
        let router = NotificationNavigationRouter(isPlatformAdmin: { false }, isAdminOf: { _ in false })
        XCTAssertEqual(router.notificationIntent(for: notification), .openMyCommunities)
    }

    func testRouter_MembershipUpdateRowWithoutCommunityOpensMyCommunities() {
        let notification = AppNotification(
            userId: UUID(),
            type: .membershipUpdate,
            title: "t"
        )
        let router = NotificationNavigationRouter(isPlatformAdmin: { true }, isAdminOf: { _ in true })
        XCTAssertEqual(router.notificationIntent(for: notification), .openMyCommunities)
    }

    func testCommunityMembersIsAdminOnlyForGuests() {
        let members = NavigationIntent.communityMembers(UUID())
        XCTAssertTrue(coordinator.intentIsAdminOnly(members))
        XCTAssertFalse(coordinator.intentRequiresAuth(members))
        XCTAssertEqual(members.targetTab, .explore)
    }

    // MARK: - Universal Link (multi-community Phase 4)

    /// A tapped link is an explicit action, like a notification tap: no "open link?" confirmation
    /// even with another intent pending.
    func testApplyExternalDeepLink_JoinCommunitySetsIntentWithoutConfirmation() {
        coordinator.cancelPendingDeepLink()
        coordinator.pendingIntent = .dashboard

        coordinator.applyExternalDeepLink(.joinCommunity(code: "NC7K2PQ9XA"))

        XCTAssertFalse(coordinator.showDeepLinkConfirmation)
        XCTAssertNil(coordinator.pendingDeepLink)
        XCTAssertEqual(coordinator.pendingIntent, .joinCommunity)
        XCTAssertEqual(NavigationIntent.joinCommunity.targetTab, .explore)
    }

    /// An unrecognized URL opens the app where it was.
    func testApplyExternalDeepLink_UnknownLeavesNavigationAlone() {
        coordinator.pendingIntent = nil
        coordinator.selectedTab = .messages

        coordinator.applyExternalDeepLink(.unknown)

        XCTAssertNil(coordinator.pendingIntent)
        XCTAssertEqual(coordinator.selectedTab, .messages)
    }

    func testJoinCommunity_RequiresAuthAndPromptsWithTheJoinReason() {
        XCTAssertTrue(coordinator.intentRequiresAuth(.joinCommunity))
        XCTAssertFalse(coordinator.intentIsAdminOnly(.joinCommunity))
        XCTAssertEqual(coordinator.guestPromptReason(for: .joinCommunity).id, GuestRestrictionReason.joinCommunity.id)
        XCTAssertEqual(coordinator.guestPromptReason(for: .conversation(UUID())).id, GuestRestrictionReason.deepLinkSignIn.id)
    }

    // MARK: - Explore tab (community Release 1)

    func testCommunityAdminIntents_TargetExploreTab() {
        let a = CommunityFixtures.communityA
        for intent: NavigationIntent in [.myCommunities, .joinCommunity, .pendingMembers(a), .communityReports(a), .communityMembers(a), .explore] {
            XCTAssertEqual(intent.targetTab, .explore, "\(intent)")
        }
        for intent: NavigationIntent in [.pendingUsers, .adminPanel, .adminReports, .profile(UUID())] {
            XCTAssertEqual(intent.targetTab, .profile, "\(intent)")
        }
        XCTAssertEqual(NavigationIntent.townHallPost(UUID()).targetTab, .townHall)
    }

    func testDeferredCommunityAdminIntents_SelectExploreTab() {
        let a = CommunityFixtures.communityA
        for intent: NotificationIntent in [.openPendingMembers(communityId: a), .openCommunityReports(communityId: a), .openCommunityMembers(communityId: a), .openMyCommunities] {
            coordinator.selectedTab = .requests
            coordinator.deferNotificationIntent(intent)
            coordinator.applyDeferredNotificationIntentIfNeeded()
            XCTAssertEqual(coordinator.selectedTab, .explore, "\(intent)")
        }
        coordinator.deferNotificationIntent(.openPendingUsers); coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .profile)
    }

    func testExploreIntent_IsGuestSafe() {
        XCTAssertFalse(coordinator.intentRequiresAuth(.explore)); XCTAssertFalse(coordinator.intentIsAdminOnly(.explore))
    }

    func testTabRefreshDomains_ExploreAndProfileHaveNone() {
        XCTAssertEqual(NavigationCoordinator.Tab.requests.refreshDomain, .dashboard)
        XCTAssertEqual(NavigationCoordinator.Tab.messages.refreshDomain, .conversations)
        XCTAssertEqual(NavigationCoordinator.Tab.townHall.refreshDomain, .townHall)
        XCTAssertNil(NavigationCoordinator.Tab.profile.refreshDomain); XCTAssertNil(NavigationCoordinator.Tab.explore.refreshDomain)
    }

    @MainActor
    func testLookAroundFirst_EntersGuestModeOnExplore() {
        let appState = AppState()
        AppLaunchManager.shared.state = .ready(.unauthenticated)

        WelcomeEntryRoute.lookAroundFirst(appState: appState)

        XCTAssertEqual(coordinator.pendingIntent, .explore)
        XCTAssertTrue(appState.isGuestMode)
        XCTAssertEqual(AppLaunchManager.shared.state, .ready(.guest))
    }
}
