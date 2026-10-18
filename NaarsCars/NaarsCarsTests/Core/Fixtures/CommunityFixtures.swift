//
//  CommunityFixtures.swift
//  NaarsCars
//
//  Fixtures and a stub service for community membership tests
//

import Foundation
@testable import NaarsCars

enum CommunityFixtures {
    static let communityA = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    static let communityB = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002")!
    static let communityC = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000003")!
    static let userA = UUID(uuidString: "0A000000-0000-4000-8000-0000000000A1")!
    static let inviteId = UUID(uuidString: "1E000000-0000-4000-8000-000000000001")!

    static let profileStatsJSON: String = """
    {"avg_rating": 4.5, "review_count": 3, "fulfilled_count": 7}
    """

    static let profileStatsEmptyJSON: String = "{}"

    static let communityLeaderboardRowsJSON: String = """
    [
      {
        "user_id": "DDDDDDDD-0000-4000-8000-000000000004",
        "name": "Sam Neighbor",
        "avatar_url": null,
        "xp": 120,
        "badges": ["road_warrior"],
        "streak_weeks": 3,
        "requests_fulfilled": 5,
        "requests_made": 2
      }
    ]
    """

    static let myMembershipsJSON: String = """
    [
      {
        "community_id": "AAAAAAAA-0000-4000-8000-000000000001",
        "name": "Community A",
        "description": null,
        "role": "member",
        "status": "active",
        "is_primary": false,
        "join_policy": "invite",
        "is_public": false,
        "is_default": true,
        "members_can_invite": true,
        "timezone": "America/Los_Angeles",
        "can_invite": true,
        "member_count": 12,
        "pending_count": null,
        "notifications_muted": false,
        "muted_until": null,
        "joined_at": "2026-10-01T12:00:00.123456+00:00",
        "activated_at": "2026-10-01T12:00:01.500000+00:00"
      },
      {
        "community_id": "BBBBBBBB-0000-4000-8000-000000000002",
        "name": "Community B",
        "description": "Second community",
        "role": "admin",
        "status": "active",
        "is_primary": true,
        "join_policy": "approve",
        "is_public": true,
        "is_default": false,
        "members_can_invite": false,
        "timezone": "America/New_York",
        "can_invite": true,
        "member_count": 4,
        "pending_count": 2,
        "notifications_muted": true,
        "muted_until": "2026-12-01T00:00:00.000000+00:00",
        "joined_at": "2026-10-02T12:00:00.123456+00:00",
        "activated_at": "2026-10-02T12:00:01.500000+00:00"
      }
    ]
    """

    static let myMembershipsUnknownEnumsJSON: String = """
    [
      {
        "community_id": "AAAAAAAA-0000-4000-8000-000000000001",
        "name": "Community A",
        "description": null,
        "role": "moderator",
        "status": "suspended",
        "is_primary": false,
        "join_policy": "invite",
        "is_public": false,
        "is_default": true,
        "members_can_invite": true,
        "timezone": "America/Los_Angeles",
        "can_invite": false,
        "member_count": 12,
        "pending_count": null,
        "notifications_muted": false,
        "muted_until": null,
        "joined_at": "2026-10-01T12:00:00.123456+00:00",
        "activated_at": null
      }
    ]
    """

    // MARK: - RPC envelopes (shapes from 20261017_0005_communities_rpcs.sql)

    static let createCommunitySuccessJSON = """
    {"success": true, "community_id": "AAAAAAAA-0000-4000-8000-000000000001"}
    """

    static let ownedLimitRefusalJSON = """
    {"success": false, "error": "You already own 3 communities, the most your account allows.", "code": "owned_limit", "max_owned": 3, "owned_count": 3}
    """

    static let refusalWithoutCodeJSON = """
    {"success": false, "error": "Sign in first"}
    """

    static let unknownCodeRefusalJSON = """
    {"success": false, "error": "Something new", "code": "brand_new_code"}
    """

    static let inviteSuccessJSON = """
    {"success": true, "code": "NC7K2PQ9XA", "invite_id": "1E000000-0000-4000-8000-000000000001", "max_uses": 1, "expires_at": "2026-10-25T12:00:00.123456+00:00"}
    """

    static let limitsWithPendingRequestJSON = """
    {
      "success": true,
      "max_owned": 3,
      "owned_count": 3,
      "next_create_at": null,
      "can_create": false,
      "latest_request": {
        "request_id": "2E000000-0000-4000-8000-000000000002",
        "requested_max": 5,
        "reason": "I run three neighbourhood groups",
        "status": "pending",
        "created_at": "2026-10-17T09:00:00.500000+00:00",
        "decided_at": null
      }
    }
    """

    static let limitRequestReceiptJSON = """
    {"success": true, "request_id": "2E000000-0000-4000-8000-000000000002"}
    """

    /// One live row, one expired, one used up.
    static let liveInvitesJSON = """
    [
      {"id": "1E000000-0000-4000-8000-000000000001", "code": "NC7K2PQ9XA", "max_uses": 1, "use_count": 0,
       "expires_at": "2099-01-01T00:00:00+00:00", "revoked_at": null, "created_at": "2026-10-17T09:00:00.100000+00:00"},
      {"id": "1E000000-0000-4000-8000-000000000002", "code": "NCH3M5RT8W", "max_uses": 5, "use_count": 0,
       "expires_at": "2020-01-01T00:00:00+00:00", "revoked_at": null, "created_at": "2026-10-16T09:00:00.100000+00:00"},
      {"id": "1E000000-0000-4000-8000-000000000003", "code": "NCJ4N6SV9X", "max_uses": 1, "use_count": 1,
       "expires_at": "2099-01-01T00:00:00+00:00", "revoked_at": null, "created_at": "2026-10-15T09:00:00.100000+00:00"}
    ]
    """

    static let validateValidJSON = """
    {"success": true, "valid": true, "expired": false, "requires_approval": true, "community_name": "Ballard Neighbors", "already_member": false, "member_count": 12}
    """

    static let validateExpiredJSON = """
    {"success": true, "valid": false, "expired": true, "community_name": "Ballard Neighbors"}
    """

    static let validateInvalidJSON = """
    {"success": true, "valid": false, "expired": false}
    """

    static let redeemPendingJSON = """
    {"success": true, "community_id": "BBBBBBBB-0000-4000-8000-000000000002", "status": "pending"}
    """

    static let removedRefusalJSON = """
    {"success": false, "error": "A community admin has to let you back in", "code": "removed"}
    """

    static let recentlyRejectedJSON = """
    {"success": false, "error": "You can ask to join again after October 24", "code": "recently_rejected", "retry_after": "2026-10-24T12:00:00.250000+00:00"}
    """

    static let leaveResultJSON = """
    {"success": true, "reopened": 2, "removed": 1, "cancelled": 3, "archived": false}
    """

    static let reportDuplicateJSON = """
    {"success": true, "duplicate": true}
    """

    static let reportSuccessJSON = """
    {"success": true, "report_id": "3E000000-0000-4000-8000-000000000003"}
    """

    static let publicCommunitiesJSON = """
    [
      {"id": "BBBBBBBB-0000-4000-8000-000000000002", "name": "Ballard Neighbors", "description": "Ballard rides", "join_policy": "approve", "is_default": false},
      {"id": "CCCCCCCC-0000-4000-8000-000000000003", "name": "Fremont Families", "description": null, "join_policy": "invite", "is_default": false}
    ]
    """

    static func membership(
        _ id: UUID,
        name: String,
        isPrimary: Bool = false,
        status: MembershipStatus = .active,
        role: CommunityRole = .member,
        memberCount: Int = 1,
        pendingCount: Int? = nil,
        isDefault: Bool = false,
        joinPolicy: String = "invite",
        notificationsMuted: Bool = false,
        canInvite: Bool = true
    ) -> CommunityMembership {
        CommunityMembership(
            communityId: id,
            name: name,
            description: nil,
            role: role,
            status: status,
            isPrimary: isPrimary,
            joinPolicy: joinPolicy,
            isPublic: false,
            isDefault: isDefault,
            membersCanInvite: true,
            timezone: "America/Los_Angeles",
            canInvite: canInvite,
            memberCount: memberCount,
            pendingCount: pendingCount,
            notificationsMuted: notificationsMuted,
            mutedUntil: nil,
            joinedAt: Date(timeIntervalSince1970: 1_790_000_000),
            activatedAt: nil
        )
    }

    static func post(_ id: UUID, community: UUID?, createdAt: Date) -> TownHallPost {
        TownHallPost(
            id: id,
            userId: UUID(uuidString: "0D000000-0000-4000-8000-000000000001")!,
            content: "Post \(id.uuidString.prefix(8))",
            communityId: community,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static let searchMemberRowsJSON: String = """
    [
      {
        "id": "DDDDDDDD-0000-4000-8000-000000000004",
        "name": "Sam Neighbor",
        "avatar_url": null,
        "car": "Blue Civic",
        "approved": true,
        "created_at": "2026-01-02T10:00:00Z",
        "updated_at": "2026-02-03T11:00:00.123Z"
      }
    ]
    """
}

final class StubCommunityService: CommunityServiceProtocol {
    var result: Result<[CommunityMembership], Error>
    var gate: (() async -> Void)?
    private(set) var fetchCount = 0

    /// Awaited by every write before it returns (a slow request, for double-tap tests).
    var actionGate: (() async -> Void)?

    var createCommunityResult: Result<CreatedCommunity, Error> = .success(CreatedCommunity(communityId: CommunityFixtures.communityA))
    private(set) var createCommunityCalls: [(name: String, description: String?, joinPolicy: CommunityJoinPolicy)] = []

    var fetchMyCommunityLimitsResult: Result<CommunityLimits, Error> = .success(
        CommunityLimits(maxOwned: 3, ownedCount: 0, nextCreateAt: nil, canCreate: true, latestRequest: nil)
    )
    private(set) var fetchMyCommunityLimitsCalls = 0

    var requestOwnedCommunityLimitResult: Result<LimitRequestReceipt, Error> = .success(LimitRequestReceipt(requestId: UUID()))
    private(set) var requestOwnedCommunityLimitCalls: [(requested: Int, reason: String)] = []

    var createInviteResult: Result<CommunityInvite, Error> = .success(
        CommunityInvite(code: "NC7K2PQ9XA", inviteId: CommunityFixtures.inviteId, maxUses: 1, expiresAt: Date(timeIntervalSince1970: 1_791_000_000))
    )
    private(set) var createInviteCalls: [(communityId: UUID, maxUses: Int?, expiresAt: Date?)] = []

    var fetchLiveInvitesResult: Result<[CommunityInviteRow], Error> = .success([])
    private(set) var fetchLiveInvitesCalls: [(communityId: UUID, createdBy: UUID)] = []

    var revokeInviteResult: Result<Void, Error> = .success(())
    private(set) var revokeInviteCalls: [UUID] = []

    var validateInviteResult: Result<InvitePreview, Error> = .success(
        InvitePreview(valid: true, expired: false, requiresApproval: false, communityName: "Community A", alreadyMember: false, memberCount: nil)
    )
    private(set) var validateInviteCalls: [String] = []

    var redeemInviteResult: Result<JoinResult, Error> = .success(JoinResult(communityId: CommunityFixtures.communityA, status: .active))
    private(set) var redeemInviteCalls: [(code: String, heardAbout: String?, joinReason: String?)] = []

    var fetchPublicCommunitiesResult: Result<[PublicCommunity], Error> = .success([])
    private(set) var fetchPublicCommunitiesCalls = 0

    var requestToJoinResult: Result<JoinResult, Error> = .success(JoinResult(communityId: CommunityFixtures.communityA, status: .pending))
    private(set) var requestToJoinCalls: [(communityId: UUID, heardAbout: String?, joinReason: String?)] = []

    var leaveCommunityResult: Result<LeaveResult, Error> = .success(LeaveResult(reopened: 0, removed: 0, cancelled: 0, archived: false))
    private(set) var leaveCommunityCalls: [UUID] = []

    var setCommunityMutedResult: Result<Void, Error> = .success(())
    private(set) var setCommunityMutedCalls: [(communityId: UUID, muted: Bool)] = []

    var reportCommunityResult: Result<CommunityReportResult, Error> = .success(CommunityReportResult(reportId: UUID(), duplicate: false))
    private(set) var reportCommunityCalls: [(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?)] = []

    init(result: Result<[CommunityMembership], Error>) {
        self.result = result
    }

    func fetchMyMemberships() async throws -> [CommunityMembership] {
        fetchCount += 1
        await gate?()
        return try result.get()
    }

    func createCommunity(name: String, description: String?, joinPolicy: CommunityJoinPolicy) async throws -> CreatedCommunity {
        createCommunityCalls.append((name, description, joinPolicy))
        await actionGate?()
        return try createCommunityResult.get()
    }

    func fetchMyCommunityLimits() async throws -> CommunityLimits {
        fetchMyCommunityLimitsCalls += 1
        return try fetchMyCommunityLimitsResult.get()
    }

    func requestOwnedCommunityLimit(requested: Int, reason: String) async throws -> LimitRequestReceipt {
        requestOwnedCommunityLimitCalls.append((requested, reason))
        await actionGate?()
        return try requestOwnedCommunityLimitResult.get()
    }

    func createInvite(communityId: UUID, maxUses: Int?, expiresAt: Date?) async throws -> CommunityInvite {
        createInviteCalls.append((communityId, maxUses, expiresAt))
        await actionGate?()
        return try createInviteResult.get()
    }

    func fetchLiveInvites(communityId: UUID, createdBy: UUID) async throws -> [CommunityInviteRow] {
        fetchLiveInvitesCalls.append((communityId, createdBy))
        return try fetchLiveInvitesResult.get()
    }

    func revokeInvite(inviteId: UUID) async throws {
        revokeInviteCalls.append(inviteId)
        await actionGate?()
        try revokeInviteResult.get()
    }

    func validateInvite(code: String) async throws -> InvitePreview {
        validateInviteCalls.append(code)
        return try validateInviteResult.get()
    }

    func redeemInvite(code: String, heardAbout: String?, joinReason: String?) async throws -> JoinResult {
        redeemInviteCalls.append((code, heardAbout, joinReason))
        await actionGate?()
        return try redeemInviteResult.get()
    }

    func fetchPublicCommunities() async throws -> [PublicCommunity] {
        fetchPublicCommunitiesCalls += 1
        return try fetchPublicCommunitiesResult.get()
    }

    func requestToJoin(communityId: UUID, heardAbout: String?, joinReason: String?) async throws -> JoinResult {
        requestToJoinCalls.append((communityId, heardAbout, joinReason))
        await actionGate?()
        return try requestToJoinResult.get()
    }

    func leaveCommunity(communityId: UUID) async throws -> LeaveResult {
        leaveCommunityCalls.append(communityId)
        await actionGate?()
        return try leaveCommunityResult.get()
    }

    func setCommunityMuted(communityId: UUID, muted: Bool) async throws {
        setCommunityMutedCalls.append((communityId, muted))
        await actionGate?()
        try setCommunityMutedResult.get()
    }

    func reportCommunity(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?) async throws -> CommunityReportResult {
        reportCommunityCalls.append((communityId, code, type, description))
        await actionGate?()
        return try reportCommunityResult.get()
    }
}

/// Stub for `TownHallSyncEngine`'s post reads. Offset 0 returns the page stored for the
/// requested community and its count; any other offset returns an empty page.
final class StubTownHallPostFetcher: TownHallPostFetching {
    var pagesByCommunity: [UUID?: [TownHallPost]]
    var postsById: [UUID: TownHallPost]
    /// When set, every `fetchPostsPage` throws (offline).
    var failPages = false
    private(set) var requestedCommunityIds: [UUID?] = []

    init(pagesByCommunity: [UUID?: [TownHallPost]] = [:], postsById: [UUID: TownHallPost] = [:]) {
        self.pagesByCommunity = pagesByCommunity
        self.postsById = postsById
    }

    func fetchPostsPage(limit: Int, offset: Int, communityId: UUID?) async throws -> (posts: [TownHallPost], serverCount: Int) {
        requestedCommunityIds.append(communityId)
        if failPages { throw URLError(.notConnectedToInternet) }
        guard offset == 0 else { return ([], 0) }
        let page = Array((pagesByCommunity[communityId] ?? []).prefix(limit))
        return (page, page.count)
    }

    func fetchPost(id: UUID) async throws -> TownHallPost? {
        postsById[id]
    }
}
