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

    static let myMembershipsJSON: String = """
    [
      {
        "community_id": "AAAAAAAA-0000-4000-8000-000000000001",
        "name": "Community A",
        "description": null,
        "role": "member",
        "status": "active",
        "is_primary": false,
        "join_policy": "invite_only",
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
        "join_policy": "approval",
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
        "join_policy": "invite_only",
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

    static func membership(
        _ id: UUID,
        name: String,
        isPrimary: Bool = false,
        status: MembershipStatus = .active,
        role: CommunityRole = .member
    ) -> CommunityMembership {
        CommunityMembership(
            communityId: id,
            name: name,
            description: nil,
            role: role,
            status: status,
            isPrimary: isPrimary,
            joinPolicy: "invite_only",
            isPublic: false,
            isDefault: false,
            membersCanInvite: true,
            timezone: "America/Los_Angeles",
            canInvite: true,
            memberCount: 1,
            pendingCount: nil,
            notificationsMuted: false,
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
}

final class StubCommunityService: CommunityServiceProtocol {
    var result: Result<[CommunityMembership], Error>
    var gate: (() async -> Void)?
    private(set) var fetchCount = 0

    init(result: Result<[CommunityMembership], Error>) {
        self.result = result
    }

    func fetchMyMemberships() async throws -> [CommunityMembership] {
        fetchCount += 1
        await gate?()
        return try result.get()
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
