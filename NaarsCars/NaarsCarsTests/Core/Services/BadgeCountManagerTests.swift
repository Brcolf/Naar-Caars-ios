//
//  BadgeCountManagerTests.swift
//  NaarsCars
//
//  Lightweight unit tests for badge contracts
//

import XCTest
@testable import NaarsCars

@MainActor
final class BadgeCountManagerTests: XCTestCase {
    override func tearDown() {
        BadgeCountManager.shared.resetCountsForTesting()
        super.tearDown()
    }

    func testBadgeTabRawValuesAreStable() {
        XCTAssertEqual(BadgeTab.requests.rawValue, "requests")
        XCTAssertEqual(BadgeTab.messages.rawValue, "messages")
        XCTAssertEqual(BadgeTab.community.rawValue, "community")
        XCTAssertEqual(BadgeTab.profile.rawValue, "profile")
    }

    func testBadgeTabContainsExpectedUniqueValues() {
        let values: Set<String> = [
            BadgeTab.requests.rawValue,
            BadgeTab.messages.rawValue,
            BadgeTab.community.rawValue,
            BadgeTab.profile.rawValue
        ]
        XCTAssertEqual(values.count, 4)
    }

    func testBadgeCountsDefaultsToZero() {
        let counts = BadgeCountManager.BadgeCounts()
        XCTAssertEqual(counts.requests, 0)
        XCTAssertEqual(counts.messages, 0)
        XCTAssertEqual(counts.community, 0)
        XCTAssertEqual(counts.explore, 0)
        XCTAssertEqual(counts.adminPanel, 0)
        XCTAssertEqual(counts.bell, 0)
        XCTAssertEqual(counts.totalUnread, 0)
    }

    func testBadgeCountsEquatable() {
        var a = BadgeCountManager.BadgeCounts()
        let b = BadgeCountManager.BadgeCounts()
        XCTAssertEqual(a, b)

        a.requests = 1
        XCTAssertNotEqual(a, b)
    }

    func testTotalUnreadCountContractMatchesComponentSum() {
        var counts = BadgeCountManager.BadgeCounts()
        counts.requests = 2
        counts.messages = 5
        counts.community = 3
        counts.bell = 7

        let expectedTotal = counts.requests + counts.messages + counts.community
        counts.totalUnread = expectedTotal

        XCTAssertEqual(counts.totalUnread, expectedTotal)
    }

    /// Sign-out invariant: badges zero. The teardown calls `resetForSignOut()` so a guest or
    /// the next account on the device does not inherit the previous member's counts.
    func testResetForSignOutZeroesCounts() {
        var seeded = BadgeCountManager.BadgeCounts()
        seeded.requests = 2
        seeded.messages = 5
        seeded.community = 3
        seeded.bell = 7
        seeded.totalUnread = 10
        BadgeCountManager.shared.setCountsForTesting(seeded)
        XCTAssertEqual(BadgeCountManager.shared.counts, seeded)

        BadgeCountManager.shared.resetForSignOut()

        XCTAssertEqual(BadgeCountManager.shared.counts, BadgeCountManager.BadgeCounts())
        XCTAssertFalse(BadgeCountManager.shared.isBadgeStale)
    }

    // MARK: - get_badge_counts payload keys

    func testBadgePayload_DecodesCommunityKeysWhenPresent() throws {
        let communityId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let json = """
        {
          "requests_total": 1,
          "messages_total": 5,
          "community_total": 3,
          "bell_total": 4,
          "request_details": [],
          "conversation_details": [],
          "pending_members_total": 2,
          "community_details": [
            {"community_id": "\(communityId.uuidString)", "requests_total": 1, "community_total": 3, "bell_total": 4}
          ],
          "total": 9
        }
        """
        let payload = try BadgeCountManager.BadgeCountsPayload.decode(Data(json.utf8))

        XCTAssertEqual(payload.pendingMembersTotal, 2)
        XCTAssertEqual(payload.total, 9)
        XCTAssertEqual(payload.communityDetails, [
            BadgeCountManager.CommunityCountDetail(communityId: communityId, requestsTotal: 1, communityTotal: 3, bellTotal: 4)
        ])
        XCTAssertEqual(payload.requestsTotal, 1)
        XCTAssertEqual(payload.messagesTotal, 5)
        XCTAssertEqual(payload.communityTotal, 3)
        XCTAssertEqual(payload.bellTotal, 4)
    }

    func testBadgePayload_DecodesTodaysPayloadWithoutCommunityKeys() throws {
        let requestId = UUID()
        let conversationId = UUID()
        let json = """
        {
          "requests_total": 2,
          "messages_total": 6,
          "community_total": 1,
          "bell_total": 3,
          "request_details": [
            {"request_type": "ride", "request_id": "\(requestId.uuidString)", "unread_count": 2}
          ],
          "conversation_details": [
            {"conversation_id": "\(conversationId.uuidString)", "unread_count": 6}
          ]
        }
        """
        let payload = try BadgeCountManager.BadgeCountsPayload.decode(Data(json.utf8))

        XCTAssertNil(payload.pendingMembersTotal)
        XCTAssertNil(payload.communityDetails)
        XCTAssertNil(payload.total)
        XCTAssertEqual(payload.requestsTotal, 2)
        XCTAssertEqual(payload.messagesTotal, 6)
        XCTAssertEqual(payload.communityTotal, 1)
        XCTAssertEqual(payload.bellTotal, 3)
        XCTAssertEqual(payload.requestDetails.first?.requestId, requestId)
        XCTAssertEqual(payload.requestDetails.first?.unreadCount, 2)
        XCTAssertEqual(payload.conversationDetails.first?.conversationId, conversationId)
        XCTAssertEqual(payload.conversationDetails.first?.unreadCount, 6)
    }

    // MARK: - Counts from the payload (Profile badge, per-community counts)

    private func makePayload(
        pendingMembersTotal: Int? = nil,
        communityDetails: [BadgeCountManager.CommunityCountDetail]? = nil
    ) -> BadgeCountManager.BadgeCountsPayload {
        BadgeCountManager.BadgeCountsPayload(
            requestsTotal: 1,
            messagesTotal: 5,
            communityTotal: 3,
            bellTotal: 4,
            requestDetails: [],
            conversationDetails: [],
            pendingMembersTotal: pendingMembersTotal,
            communityDetails: communityDetails,
            total: nil
        )
    }

    func testMakeCounts_ExploreBadgeReadsPendingMembersTotal() {
        let counts = BadgeCountManager.BadgeCounts.makeCounts(from: makePayload(pendingMembersTotal: 2))

        XCTAssertEqual(counts.explore, 2)
        XCTAssertEqual(counts.adminPanel, 2)
        XCTAssertEqual(counts.requests, 1)
        XCTAssertEqual(counts.messages, 5)
        XCTAssertEqual(counts.community, 3)
        XCTAssertEqual(counts.bell, 4)
        XCTAssertEqual(counts.totalUnread, 1 + 5 + 3)
    }

    func testMakeCounts_MissingPendingMembersTotalIsZero() {
        let counts = BadgeCountManager.BadgeCounts.makeCounts(from: makePayload(pendingMembersTotal: nil))

        XCTAssertEqual(counts.explore, 0)
        XCTAssertEqual(counts.adminPanel, 0)
        XCTAssertEqual(counts.communityUnreadById, [:])
    }

    func testMakeCounts_CommunityUnreadByIdKeepsPositiveTotals() {
        let communityA = UUID()
        let communityB = UUID()
        let payload = makePayload(communityDetails: [
            BadgeCountManager.CommunityCountDetail(communityId: communityA, requestsTotal: 0, communityTotal: 3, bellTotal: 3),
            BadgeCountManager.CommunityCountDetail(communityId: communityB, requestsTotal: 2, communityTotal: 0, bellTotal: 2)
        ])

        let counts = BadgeCountManager.BadgeCounts.makeCounts(from: payload)

        XCTAssertEqual(counts.communityUnreadById, [communityA: 3])
    }

    // MARK: - Scoped Community clear

    private struct ClearFixture {
        let communityA = UUID()
        let communityB = UUID()
        let userId = UUID()
        let aPostUnread: AppNotification
        let bCommentUnread: AppNotification
        let nilReactionUnread: AppNotification
        let aPostRead: AppNotification
        let aRideClaimedUnread: AppNotification

        init() {
            aPostUnread = AppNotification(userId: userId, type: .townHallPost, title: "A post", communityId: communityA)
            bCommentUnread = AppNotification(userId: userId, type: .townHallComment, title: "B comment", communityId: communityB)
            nilReactionUnread = AppNotification(userId: userId, type: .townHallReaction, title: "Reaction")
            aPostRead = AppNotification(userId: userId, type: .townHallPost, title: "A post read", read: true, communityId: communityA)
            aRideClaimedUnread = AppNotification(userId: userId, type: .rideClaimed, title: "Claimed", communityId: communityA)
        }

        var all: [AppNotification] {
            [aPostUnread, bCommentUnread, nilReactionUnread, aPostRead, aRideClaimedUnread]
        }
    }

    func testCommunityIdsToClear_ScopesToVisibleAndUnlabelledRows() {
        let fixture = ClearFixture()

        let ids = BadgeCountManager.communityNotificationIdsToClear(fixture.all, visibleCommunityId: fixture.communityA)

        XCTAssertEqual(ids, [fixture.aPostUnread.id, fixture.nilReactionUnread.id])
    }

    func testCommunityIdsToClear_NilVisibleClearsEveryCommunityRow() {
        let fixture = ClearFixture()

        let ids = BadgeCountManager.communityNotificationIdsToClear(fixture.all, visibleCommunityId: nil)

        XCTAssertEqual(ids, [fixture.aPostUnread.id, fixture.bCommentUnread.id, fixture.nilReactionUnread.id])
    }

    // The guard that decides from `community_total` / `community_details` whether a Community
    // visit downloads the bell list to look for rows to mark read.

    private func makeCommunityCounts(community: Int, unreadById: [UUID: Int]) -> BadgeCountManager.BadgeCounts {
        var counts = BadgeCountManager.BadgeCounts()
        counts.community = community
        counts.communityUnreadById = unreadById
        return counts
    }

    func testCommunityClearNeedsFetch_NothingUnreadSkips() {
        let counts = makeCommunityCounts(community: 0, unreadById: [:])

        XCTAssertFalse(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: UUID(), countsAreCurrent: true))
    }

    func testCommunityClearNeedsFetch_VisibleCommunityUnreadFetches() {
        let communityA = UUID()
        let counts = makeCommunityCounts(community: 2, unreadById: [communityA: 2])

        XCTAssertTrue(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: communityA, countsAreCurrent: true))
    }

    func testCommunityClearNeedsFetch_OnlyAnotherCommunityUnreadSkips() {
        let communityA = UUID()
        let communityB = UUID()
        let counts = makeCommunityCounts(community: 1, unreadById: [communityB: 1])

        XCTAssertFalse(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: communityA, countsAreCurrent: true))
    }

    func testCommunityClearNeedsFetch_RowsWithNoCommunityFetch() {
        let communityA = UUID()
        let communityB = UUID()
        let counts = makeCommunityCounts(community: 2, unreadById: [communityB: 1])

        XCTAssertTrue(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: communityA, countsAreCurrent: true))
    }

    func testCommunityClearNeedsFetch_NoVisibleCommunityFetchesWhenAnyUnread() {
        let counts = makeCommunityCounts(community: 1, unreadById: [UUID(): 1])

        XCTAssertTrue(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: nil, countsAreCurrent: true))
    }

    func testCommunityClearNeedsFetch_ServerWithoutDetailsFetches() {
        let counts = makeCommunityCounts(community: 1, unreadById: [:])

        XCTAssertTrue(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: UUID(), countsAreCurrent: true))
    }

    func testCommunityClearNeedsFetch_CountsNotCurrentAlwaysFetch() {
        let counts = makeCommunityCounts(community: 0, unreadById: [:])

        XCTAssertTrue(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: UUID(), countsAreCurrent: false))
        XCTAssertTrue(BadgeCountManager.communityClearNeedsFetch(counts, visibleCommunityId: nil, countsAreCurrent: false))
    }
}
