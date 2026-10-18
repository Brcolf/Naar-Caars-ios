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
