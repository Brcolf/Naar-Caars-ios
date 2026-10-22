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


    static let communityPreviewJSON = """
    {
      "success": true,
      "community": {"id": "AAAAAAAA-0000-4000-8000-000000000001", "name": "Test Public A", "description": null,
                    "join_policy": "approve", "is_public": true, "is_default": false, "member_count": 1,
                    "timezone": "America/Los_Angeles"},
      "requests": [
        {"type": "ride", "id": "5A000000-0000-4000-8000-000000000001", "title": null, "date": "2026-10-25", "time": "09:30:00",
         "timezone": "America/Los_Angeles", "seats": 2, "poster_id": "5B000000-0000-4000-8000-000000000001",
         "poster_name": "Sample Poster", "poster_avatar_url": null},
        {"type": "favor", "id": "5A000000-0000-4000-8000-000000000002", "title": "Move a couch", "date": "2026-10-26", "time": null,
         "timezone": null, "seats": null, "poster_id": "5B000000-0000-4000-8000-000000000001",
         "poster_name": "Sample Poster", "poster_avatar_url": null}
      ],
      "posts": [
        {"id": "5C000000-0000-4000-8000-000000000001", "type": null, "title": null, "content": "Welcome to the group",
         "created_at": "2026-10-20T10:00:00.123456+00:00", "author_id": "5B000000-0000-4000-8000-000000000001",
         "author_name": "Sample Poster", "author_avatar_url": null, "comment_count": 3}
      ]
    }
    """

    static func preview(_ id: UUID, name: String, policy: String = "approve") -> CommunityPreview {
        let poster = UUID(uuidString: "5B000000-0000-4000-8000-000000000001")!
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        return CommunityPreview(
            community: .init(id: id, name: name, description: nil, joinPolicy: policy, isPublic: true,
                             isDefault: false, memberCount: 1, timezone: "America/Los_Angeles"),
            requests: [
                .init(type: "ride", id: UUID(uuidString: "5A000000-0000-4000-8000-000000000001")!, title: nil, date: date,
                      time: "09:30:00", timezone: "America/Los_Angeles", seats: 2, posterId: poster,
                      posterName: "Sample Poster", posterAvatarUrl: nil),
                .init(type: "favor", id: UUID(uuidString: "5A000000-0000-4000-8000-000000000002")!, title: "Move a couch", date: date,
                      time: nil, timezone: nil, seats: nil, posterId: poster,
                      posterName: "Sample Poster", posterAvatarUrl: nil)
            ],
            posts: [
                .init(id: UUID(uuidString: "5C000000-0000-4000-8000-000000000001")!, type: nil, title: nil,
                      content: "Welcome to the group", createdAt: date, authorId: poster,
                      authorName: "Sample Poster", authorAvatarUrl: nil, commentCount: 3)
            ]
        )
    }

    // MARK: - Discovery (20261021_0021; names and ids invented)

    static let seattleArea = ServiceArea(name: "Seattle", center: GeoPoint(latitude: 47.6062, longitude: -122.3321), radiusMiles: 10)

    static let searchResultsJSON = """
    {
      "success": true,
      "communities": [
        {"id": "6A000000-0000-4000-8000-000000000001", "name": "Test Community", "description": "Example requests to explore",
         "join_policy": "approve", "area_name": "Seattle", "area_radius_miles": 10, "member_count": 3, "distance_miles": null},
        {"id": "6A000000-0000-4000-8000-000000000002", "name": "Harbor Riders", "description": null,
         "join_policy": "invite", "area_name": "Harbor", "area_radius_miles": 2, "member_count": 214, "distance_miles": 0.4}
      ]
    }
    """

    static func searchResult(_ id: UUID, name: String, distance: Double? = nil) -> CommunitySearchResult {
        CommunitySearchResult(
            id: id, name: name, description: nil, joinPolicy: CommunityJoinPolicy.approve.rawValue,
            areaName: "Seattle", radiusMiles: 2, memberCount: 12, distanceMiles: distance
        )
    }

    // MARK: Merge (20261021_0022). Invented communities.

    static let harborRiders = UUID(uuidString: "6B000000-0000-4000-8000-000000000001")!
    static let fremontPorchClub = UUID(uuidString: "6B000000-0000-4000-8000-000000000002")!
    static let mergeProposalId = UUID(uuidString: "6C000000-0000-4000-8000-000000000001")!

    /// `get_community_merge_proposal` as the server answers it. "Harbor Riders" proposes to "Fremont Porch
    /// Club" and names it the survivor.
    static func mergeProposalJSON(direction: String) -> String {
        """
        {
          "success": true,
          "proposal": {
            "id": "\(mergeProposalId.uuidString)",
            "direction": "\(direction)",
            "from": {"id": "\(harborRiders.uuidString)", "name": "Harbor Riders", "join_policy": "approve", "member_count": 14},
            "to": {"id": "\(fremontPorchClub.uuidString)", "name": "Fremont Porch Club", "join_policy": "open", "member_count": 31},
            "survivor_id": "\(fremontPorchClub.uuidString)",
            "note": "Same neighbours, one place to ask.",
            "proposed_by_name": "Dana Rivera",
            "created_at": "2026-10-22T12:00:00+00:00",
            "expires_at": "2026-10-29T12:00:00+00:00"
          }
        }
        """
    }

    static func mergeProposal(
        direction: CommunityMergeProposal.Direction = .incoming,
        fromPolicy: CommunityJoinPolicy = .approve,
        toPolicy: CommunityJoinPolicy = .open,
        survivorIsFrom: Bool = false
    ) -> CommunityMergeProposal {
        CommunityMergeProposal(
            id: mergeProposalId,
            direction: direction,
            from: .init(id: harborRiders, name: "Harbor Riders", joinPolicy: fromPolicy.rawValue, memberCount: 14),
            to: .init(id: fremontPorchClub, name: "Fremont Porch Club", joinPolicy: toPolicy.rawValue, memberCount: 31),
            survivorId: survivorIsFrom ? harborRiders : fremontPorchClub,
            note: "Same neighbours, one place to ask.",
            proposedByName: "Dana Rivera",
            createdAt: Date(timeIntervalSince1970: 1_792_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_792_604_800)
        )
    }

    /// Release 1's `communityPreviewJSON` plus the area keys and `is_example` (20261021_0021 block 7).
    static let communityPreviewWithAreaJSON = """
    {
      "success": true,
      "community": {"id": "AAAAAAAA-0000-4000-8000-000000000001", "name": "Test Public A", "description": null,
                    "join_policy": "approve", "is_public": true, "is_default": false, "member_count": 1,
                    "timezone": "America/Los_Angeles", "area_name": "Seattle", "area_center_lat": 47.6062,
                    "area_center_lng": -122.3321, "area_radius_miles": 10},
      "requests": [
        {"type": "ride", "id": "5A000000-0000-4000-8000-000000000001", "title": null, "date": "2026-10-25", "time": "09:30:00",
         "timezone": "America/Los_Angeles", "seats": 2, "poster_id": "5B000000-0000-4000-8000-000000000001",
         "poster_name": "Sample Poster", "poster_avatar_url": null, "is_example": true},
        {"type": "favor", "id": "5A000000-0000-4000-8000-000000000002", "title": "Move a couch", "date": "2026-10-26", "time": null,
         "timezone": null, "seats": null, "poster_id": "5B000000-0000-4000-8000-000000000001",
         "poster_name": "Sample Poster", "poster_avatar_url": null, "is_example": false}
      ],
      "posts": [
        {"id": "5C000000-0000-4000-8000-000000000001", "type": null, "title": null, "content": "Welcome to the group",
         "created_at": "2026-10-20T10:00:00.123456+00:00", "author_id": "5B000000-0000-4000-8000-000000000001",
         "author_name": "Sample Poster", "author_avatar_url": null, "comment_count": 3}
      ]
    }
    """

    // MARK: - Admin payloads

    static let pendingMembersAdminJSON = """
    [
      {"id": "DDDDDDDD-0000-4000-8000-000000000004", "name": "Dana Rivera", "avatar_url": null, "car": "Green Subaru",
       "role": "member", "status": "pending", "joined_at": "2026-10-16T09:00:00.123456+00:00", "activated_at": null,
       "heard_about": "A neighbor told me", "join_reason": "Airport rides", "invited_by_name": "Sam Neighbor", "removal_reason": null},
      {"id": "EEEEEEEE-0000-4000-8000-000000000005", "name": null, "avatar_url": null, "car": null,
       "role": "member", "status": "pending", "joined_at": "2026-10-17T09:00:00+00:00", "activated_at": null,
       "heard_about": "Found it in the app", "join_reason": null, "invited_by_name": null, "removal_reason": null}
    ]
    """

    static let activeMembersMemberViewJSON = """
    [
      {"id": "DDDDDDDD-0000-4000-8000-000000000004", "name": "Sam Neighbor", "avatar_url": null, "car": "Blue Civic",
       "role": "owner", "status": "active", "joined_at": "2026-10-01T12:00:00.123456+00:00", "activated_at": "2026-10-01T12:00:01+00:00",
       "heard_about": null, "join_reason": null, "invited_by_name": null, "removal_reason": null}
    ]
    """

    static let platformCommunitiesJSON = """
    {
      "success": true,
      "communities": [
        {"id": "AAAAAAAA-0000-4000-8000-000000000001", "name": "Naar's Cars Seattle", "description": null, "created_by": null, "creator_name": null,
         "created_at": "2026-01-01T00:00:00+00:00", "is_public": true, "is_default": true, "join_policy": "approve",
         "archived_at": null, "archived_by": null, "member_count": 140, "pending_count": 0, "owner_count": 1, "open_report_count": 0},
        {"id": "BBBBBBBB-0000-4000-8000-000000000002", "name": "Old Carpool", "description": "Gone quiet", "created_by": "0A000000-0000-4000-8000-0000000000A1", "creator_name": "Sam Neighbor",
         "created_at": "2026-05-01T00:00:00.500000+00:00", "is_public": false, "is_default": false, "join_policy": "invite",
         "archived_at": "2026-10-01T00:00:00+00:00", "archived_by": null, "member_count": 3, "pending_count": 0, "owner_count": 0, "open_report_count": 1}
      ],
      "limit_requests": [
        {"request_id": "2E000000-0000-4000-8000-000000000002", "user_id": "0A000000-0000-4000-8000-0000000000A1", "user_name": "Sam Neighbor",
         "requested_max": 5, "reason": "Three groups", "created_at": "2026-10-17T09:00:00.500000+00:00", "current_max": 3, "owned_count": 3}
      ]
    }
    """

    static let limitDecisionJSON = """
    {"success": true, "status": "approved", "max_owned": 5}
    """

    static let approveRefusalWithoutCodeJSON = """
    {"success": false, "error": "Not authorized"}
    """

    static let notPendingRefusalJSON = """
    {"success": false, "error": "That request was already handled", "code": "not_pending"}
    """

    static let defaultCommunityRowsJSON = """
    [{"id": "AAAAAAAA-0000-4000-8000-000000000001"}]
    """

    // MARK: - Member management and settings (20261017_0005 blocks 11, 22-25)

    static let removeResultJSON = """
    {"success": true, "reopened": 1, "removed": 1, "cancelled": 0}
    """

    static let lastOwnerRefusalJSON = """
    {"success": false, "error": "Make someone else owner before removing the owner", "code": "last_owner"}
    """

    static let notRemovedRefusalJSON = """
    {"success": false, "error": "This person was not removed", "code": "not_removed"}
    """

    static let communitySettingsRowsJSON = """
    [{"id": "AAAAAAAA-0000-4000-8000-000000000001", "name": "Ballard Neighbors", "description": "Ballard rides and favors.",
      "join_policy": "approve", "members_can_invite": false, "is_public": false, "is_default": false,
      "timezone": "America/Los_Angeles"}]
    """

    static let successJSON = """
    {"success":true}
    """

    // MARK: - AdminService payloads (supabase/migrations/20261018_0001 block 3-4, 20261018_0002 blocks 2-5)

    static let reportA = UUID(uuidString: "3E000000-0000-4000-8000-000000000001")!
    static let reportB = UUID(uuidString: "3E000000-0000-4000-8000-000000000002")!
    static let postA = UUID(uuidString: "4E000000-0000-4000-8000-000000000001")!
    static let rideA = UUID(uuidString: "5E000000-0000-4000-8000-000000000001")!

    static let communityStatsJSON = """
    {"success":true,"fulfilled_count":3,"total_savings":12.5,"active_rides_count":2}
    """

    static let fulfilledRowsJSON = """
    {"success": true, "rows": [
      {"period_start": "2026-10-01", "ride_count": 2, "favor_count": 1, "total_count": 3},
      {"period_start": "2026-09-01", "ride_count": 0, "favor_count": 4, "total_count": 4}
    ]}
    """

    static let savingsRowsJSON = """
    {"success": true, "rows": [
      {"period_start": "2026-10-01", "total_savings": 40.25, "ride_count": 2},
      {"period_start": "2026-09-01", "total_savings": 0, "ride_count": 1}
    ]}
    """

    static let activeRequestRowsJSON = """
    {"success": true, "rows": [
      {"id": "5E000000-0000-4000-8000-000000000001", "type": "ride", "title": "Ballard", "subtitle": "SEA Airport",
       "date": "2026-10-20", "time": "08:30:00", "status": "open", "claimed_by": null,
       "poster_name": "Sam Neighbor", "claimer_name": null},
      {"id": "6E000000-0000-4000-8000-000000000001", "type": "favor", "title": "Water plants", "subtitle": null,
       "date": "2026-10-21", "time": null, "status": "confirmed", "claimed_by": "0A000000-0000-4000-8000-0000000000A1",
       "poster_name": "Dana Rivera", "claimer_name": "Sam Neighbor"}
    ]}
    """

    /// The first report carries stray reporter keys, which must be ignored; the second has no `can_restore` key.
    static let communityReportsJSON = """
    {"success": true, "reports": [
      {"report_id": "3E000000-0000-4000-8000-000000000001", "target_type": "town_hall_post",
       "reported_user_id": null, "reported_user_name": null,
       "author_id": "0A000000-0000-4000-8000-0000000000A1", "author_name": "Sam Neighbor",
       "reported_post_id": "4E000000-0000-4000-8000-000000000001", "reported_comment_id": null,
       "reported_ride_id": null, "reported_favor_id": null,
       "town_hall_post_id": "4E000000-0000-4000-8000-000000000001",
       "report_type": "spam", "description": "Posted three times\\nin one hour", "status": "action_taken",
       "created_at": "2026-10-17T09:00:00.123456+00:00", "reviewed_at": "2026-10-17T10:00:00+00:00",
       "content_preview": "Free couch, come get it", "content_hidden": true,
       "can_restore": true, "platform_handled": false, "report_count": 2,
       "reporter_id": "0A000000-0000-4000-8000-0000000000B2", "reporter_name": "Riley Reporter"},
      {"report_id": "3E000000-0000-4000-8000-000000000002", "target_type": "ride",
       "reported_user_id": null, "reported_user_name": null,
       "author_id": "DDDDDDDD-0000-4000-8000-000000000004", "author_name": "Dana Rivera",
       "reported_post_id": null, "reported_comment_id": null,
       "reported_ride_id": "5E000000-0000-4000-8000-000000000001", "reported_favor_id": null,
       "town_hall_post_id": null,
       "report_type": "inappropriate", "description": null, "status": "action_taken",
       "created_at": "2026-10-16T09:00:00+00:00", "reviewed_at": "2026-10-16T12:00:00+00:00",
       "content_preview": "Ballard -> SEA Airport", "content_hidden": true,
       "platform_handled": true, "report_count": 1}
    ]}
    """

    static let statsRefusalJSON = """
    {"success": false, "error": "Only this community's admins can see its statistics"}
    """

    static let reportsRefusalWithoutCodeJSON = """
    {"success": false, "error": "Only this community's admins can see its reports"}
    """

    static let moderateSuccessJSON = """
    {"success": true}
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
        canInvite: Bool = true,
        timezone: String = "America/Los_Angeles"
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
            timezone: timezone,
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

final class StubCommunityService: CommunityServiceProtocol, CommunityMergeServiceProtocol {
    var result: Result<[CommunityMembership], Error>
    var gate: (() async -> Void)?
    private(set) var fetchCount = 0

    /// Awaited by every write before it returns (a slow request, for double-tap tests).
    var actionGate: (() async -> Void)?

    var createCommunityResult: Result<CreatedCommunity, Error> = .success(CreatedCommunity(communityId: CommunityFixtures.communityA))
    private(set) var createCommunityCalls: [NewCommunityDraft] = []

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

    var fetchCommunityPreviewResult: Result<CommunityPreview, Error> = .success(
        CommunityFixtures.preview(CommunityFixtures.communityA, name: "Community A")
    )
    private(set) var fetchCommunityPreviewCalls: [UUID] = []

    var requestToJoinResult: Result<JoinResult, Error> = .success(JoinResult(communityId: CommunityFixtures.communityA, status: .pending))
    private(set) var requestToJoinCalls: [(communityId: UUID, heardAbout: String?, joinReason: String?)] = []

    var leaveCommunityResult: Result<LeaveResult, Error> = .success(LeaveResult(reopened: 0, removed: 0, cancelled: 0, archived: false))
    private(set) var leaveCommunityCalls: [UUID] = []

    var setCommunityMutedResult: Result<Void, Error> = .success(())
    private(set) var setCommunityMutedCalls: [(communityId: UUID, muted: Bool)] = []

    var reportCommunityResult: Result<CommunityReportResult, Error> = .success(CommunityReportResult(reportId: UUID(), duplicate: false))
    private(set) var reportCommunityCalls: [(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?)] = []

    // MARK: Discovery

    var searchCommunitiesResult: Result<[CommunitySearchResult], Error> = .success([])
    /// When set, answers `searchCommunities` instead of `searchCommunitiesResult` (slow or per-query answers).
    var searchCommunitiesHandler: ((String) async throws -> [CommunitySearchResult])?
    private(set) var searchCommunitiesCalls: [String] = []

    var findCommunitiesNearResult: Result<[CommunitySearchResult], Error> = .success([])
    private(set) var findCommunitiesNearCalls: [GeoPoint] = []

    var checkCommunityAreaResult: Result<[CommunitySearchResult], Error> = .success([])
    private(set) var checkCommunityAreaCalls: [(area: ServiceArea, excluding: UUID?)] = []

    var fetchServiceAreaResult: Result<ServiceArea?, Error> = .success(nil)
    private(set) var fetchServiceAreaCalls: [UUID] = []

    // MARK: Merge (empty answers unless a test sets them)

    var searchMergeTargetsResult: Result<[MergeTarget], Error> = .success([])
    private(set) var searchMergeTargetsCalls: [(communityId: UUID, query: String)] = []

    var proposeMergeResult: Result<UUID, Error> = .success(CommunityFixtures.mergeProposalId)
    private(set) var proposeMergeCalls: [(communityId: UUID, otherId: UUID, survivorId: UUID, note: String?)] = []

    var fetchMergeProposalResult: Result<CommunityMergeProposal?, Error> = .success(nil)
    private(set) var fetchMergeProposalCalls: [UUID] = []

    /// A decline answers nil; an accept answers the outcome.
    var respondToMergeResult: Result<CommunityMergeOutcome?, Error> = .success(nil)
    private(set) var respondToMergeCalls: [(proposalId: UUID, accept: Bool)] = []

    var withdrawMergeResult: Result<Void, Error> = .success(())
    private(set) var withdrawMergeCalls: [UUID] = []

    var fetchMyCommunityMergesResult: Result<[CommunityMerge], Error> = .success([])
    private(set) var fetchMyCommunityMergesCalls = 0

    init(result: Result<[CommunityMembership], Error>) {
        self.result = result
    }

    func fetchMyMemberships() async throws -> [CommunityMembership] {
        fetchCount += 1
        await gate?()
        return try result.get()
    }

    func createCommunity(_ draft: NewCommunityDraft) async throws -> CreatedCommunity {
        createCommunityCalls.append(draft)
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

    func fetchCommunityPreview(communityId: UUID) async throws -> CommunityPreview {
        fetchCommunityPreviewCalls.append(communityId)
        return try fetchCommunityPreviewResult.get()
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

    func searchCommunities(name: String) async throws -> [CommunitySearchResult] {
        searchCommunitiesCalls.append(name)
        if let searchCommunitiesHandler { return try await searchCommunitiesHandler(name) }
        return try searchCommunitiesResult.get()
    }

    func findCommunitiesNear(_ point: GeoPoint) async throws -> [CommunitySearchResult] {
        findCommunitiesNearCalls.append(point)
        return try findCommunitiesNearResult.get()
    }

    func checkCommunityArea(_ area: ServiceArea, excluding communityId: UUID?) async throws -> [CommunitySearchResult] {
        checkCommunityAreaCalls.append((area, communityId))
        return try checkCommunityAreaResult.get()
    }

    func fetchServiceArea(communityId: UUID) async throws -> ServiceArea? {
        fetchServiceAreaCalls.append(communityId)
        return try fetchServiceAreaResult.get()
    }

    func searchMergeTargets(communityId: UUID, query: String) async throws -> [MergeTarget] {
        searchMergeTargetsCalls.append((communityId, query))
        return try searchMergeTargetsResult.get()
    }

    func proposeMerge(communityId: UUID, otherId: UUID, survivorId: UUID, note: String?) async throws -> UUID {
        proposeMergeCalls.append((communityId, otherId, survivorId, note))
        await actionGate?()
        return try proposeMergeResult.get()
    }

    func fetchMergeProposal(communityId: UUID) async throws -> CommunityMergeProposal? {
        fetchMergeProposalCalls.append(communityId)
        return try fetchMergeProposalResult.get()
    }

    func respondToMerge(proposalId: UUID, accept: Bool) async throws -> CommunityMergeOutcome? {
        respondToMergeCalls.append((proposalId, accept))
        await actionGate?()
        return try respondToMergeResult.get()
    }

    func withdrawMerge(proposalId: UUID) async throws {
        withdrawMergeCalls.append(proposalId)
        await actionGate?()
        try withdrawMergeResult.get()
    }

    func fetchMyCommunityMerges() async throws -> [CommunityMerge] {
        fetchMyCommunityMergesCalls += 1
        return try fetchMyCommunityMergesResult.get()
    }
}

final class StubCommunityAdminService: CommunityAdminServiceProtocol {
    /// Awaited by every write before it returns (a slow request, for double-tap tests).
    var actionGate: (() async -> Void)?

    var fetchCommunityMembersResult: Result<[CommunityMember], Error> = .success([])
    private(set) var fetchCommunityMembersCalls: [(communityId: UUID, status: MembershipStatus, limit: Int, offset: Int)] = []

    var approveMemberResult: Result<Void, Error> = .success(())
    private(set) var approveMemberCalls: [(communityId: UUID, userId: UUID)] = []

    var rejectMemberResult: Result<Void, Error> = .success(())
    private(set) var rejectMemberCalls: [(communityId: UUID, userId: UUID)] = []

    var fetchDefaultCommunityIdResult: Result<UUID?, Error> = .success(CommunityFixtures.communityA)
    private(set) var fetchDefaultCommunityIdCalls = 0

    var fetchPlatformCommunitiesResult: Result<PlatformCommunities, Error> = .success(PlatformCommunities(communities: [], limitRequests: []))
    private(set) var fetchPlatformCommunitiesCalls = 0

    var archiveCommunityResult: Result<Void, Error> = .success(())
    private(set) var archiveCommunityCalls: [UUID] = []

    var unarchiveCommunityResult: Result<Void, Error> = .success(())
    private(set) var unarchiveCommunityCalls: [UUID] = []

    var setCommunityPublicResult: Result<Void, Error> = .success(())
    private(set) var setCommunityPublicCalls: [(communityId: UUID, isPublic: Bool)] = []

    var decideOwnedCommunityLimitResult: Result<LimitDecision, Error> = .success(LimitDecision(status: .approved, maxOwned: 5))
    private(set) var decideOwnedCommunityLimitCalls: [(requestId: UUID, approve: Bool)] = []

    func fetchCommunityMembers(communityId: UUID, status: MembershipStatus, limit: Int, offset: Int) async throws -> [CommunityMember] {
        fetchCommunityMembersCalls.append((communityId, status, limit, offset))
        return try fetchCommunityMembersResult.get()
    }

    func approveMember(communityId: UUID, userId: UUID) async throws {
        approveMemberCalls.append((communityId, userId))
        await actionGate?()
        try approveMemberResult.get()
    }

    func rejectMember(communityId: UUID, userId: UUID) async throws {
        rejectMemberCalls.append((communityId, userId))
        await actionGate?()
        try rejectMemberResult.get()
    }

    func fetchDefaultCommunityId() async throws -> UUID? {
        fetchDefaultCommunityIdCalls += 1
        return try fetchDefaultCommunityIdResult.get()
    }

    func fetchPlatformCommunities() async throws -> PlatformCommunities {
        fetchPlatformCommunitiesCalls += 1
        return try fetchPlatformCommunitiesResult.get()
    }

    func archiveCommunity(communityId: UUID) async throws {
        archiveCommunityCalls.append(communityId)
        await actionGate?()
        try archiveCommunityResult.get()
    }

    func unarchiveCommunity(communityId: UUID) async throws {
        unarchiveCommunityCalls.append(communityId)
        await actionGate?()
        try unarchiveCommunityResult.get()
    }

    func setCommunityPublic(communityId: UUID, isPublic: Bool) async throws {
        setCommunityPublicCalls.append((communityId, isPublic))
        await actionGate?()
        try setCommunityPublicResult.get()
    }

    func decideOwnedCommunityLimit(requestId: UUID, approve: Bool) async throws -> LimitDecision {
        decideOwnedCommunityLimitCalls.append((requestId, approve))
        await actionGate?()
        return try decideOwnedCommunityLimitResult.get()
    }

    // MARK: Member management and settings

    var removeMemberResult: Result<RemovalResult, Error> = .success(RemovalResult(reopened: 0, removed: 0, cancelled: 0))
    private(set) var removeMemberCalls: [(communityId: UUID, userId: UUID, reason: String?)] = []

    var readmitMemberResult: Result<Void, Error> = .success(())
    private(set) var readmitMemberCalls: [(communityId: UUID, userId: UUID)] = []

    var setMemberRoleResult: Result<Void, Error> = .success(())
    private(set) var setMemberRoleCalls: [(communityId: UUID, userId: UUID, role: CommunityRole)] = []

    var transferOwnershipResult: Result<Void, Error> = .success(())
    private(set) var transferOwnershipCalls: [(communityId: UUID, userId: UUID)] = []

    var fetchCommunitySettingsResult: Result<CommunitySettings, Error> = .success(CommunitySettings(
        id: CommunityFixtures.communityA, name: "Ballard Neighbors", description: nil, joinPolicy: "approve",
        membersCanInvite: true, isPublic: false, isDefault: false, timezone: "America/Los_Angeles"
    ))
    private(set) var fetchCommunitySettingsCalls: [UUID] = []

    var updateCommunityResult: Result<Void, Error> = .success(())
    private(set) var updateCommunityCalls: [(communityId: UUID, change: CommunitySettingsChange)] = []

    func removeMember(communityId: UUID, userId: UUID, reason: String?) async throws -> RemovalResult {
        removeMemberCalls.append((communityId, userId, reason))
        await actionGate?()
        return try removeMemberResult.get()
    }

    func readmitMember(communityId: UUID, userId: UUID) async throws {
        readmitMemberCalls.append((communityId, userId))
        await actionGate?()
        try readmitMemberResult.get()
    }

    func setMemberRole(communityId: UUID, userId: UUID, role: CommunityRole) async throws {
        setMemberRoleCalls.append((communityId, userId, role))
        await actionGate?()
        try setMemberRoleResult.get()
    }

    func transferOwnership(communityId: UUID, userId: UUID) async throws {
        transferOwnershipCalls.append((communityId, userId))
        await actionGate?()
        try transferOwnershipResult.get()
    }

    func fetchCommunitySettings(communityId: UUID) async throws -> CommunitySettings {
        fetchCommunitySettingsCalls.append(communityId)
        return try fetchCommunitySettingsResult.get()
    }

    func updateCommunity(communityId: UUID, change: CommunitySettingsChange) async throws {
        updateCommunityCalls.append((communityId, change))
        await actionGate?()
        try updateCommunityResult.get()
    }

    var updateCommunityAccessResult: Result<Void, Error> = .success(())
    private(set) var updateCommunityAccessCalls: [(communityId: UUID, change: CommunityAccessChange)] = []

    func updateCommunityAccess(communityId: UUID, change: CommunityAccessChange) async throws {
        updateCommunityAccessCalls.append((communityId, change))
        await actionGate?()
        try updateCommunityAccessResult.get()
    }
}

/// Stub for `AdminServiceProtocol`. One result and one call log per method.
final class StubAdminService: AdminServiceProtocol {
    /// Awaited by `sendBroadcast`, `moderateCommunityContent` and `fetchDashboardStats` before they
    /// return (a slow request).
    var actionGate: (() async -> Void)?

    var fetchDashboardStatsResult: Result<AdminDashboardStats, Error> = .success(
        AdminDashboardStats(fulfilledCount: 0, totalSavings: 0, activeRidesCount: 0)
    )
    private(set) var fetchDashboardStatsCalls: [UUID?] = []

    var fetchFulfilledBreakdownResult: Result<[FulfilledPeriod], Error> = .success([])
    private(set) var fetchFulfilledBreakdownCalls: [(communityId: UUID?, period: String, count: Int)] = []

    var fetchSavingsBreakdownResult: Result<[SavingsPeriod], Error> = .success([])
    private(set) var fetchSavingsBreakdownCalls: [(communityId: UUID?, period: String, count: Int)] = []

    var fetchActiveRequestsResult: Result<[ActiveRequestRow], Error> = .success([])
    private(set) var fetchActiveRequestsCalls: [UUID?] = []

    var sendBroadcastResult: Result<Int, Error> = .success(0)
    private(set) var sendBroadcastCalls: [(communityId: UUID, title: String, message: String, pinToNotifications: Bool)] = []

    var fetchCommunityReportsResult: Result<[CommunityReport], Error> = .success([])
    private(set) var fetchCommunityReportsCalls: [(communityId: UUID, status: String?)] = []

    var moderateCommunityContentResult: Result<Void, Error> = .success(())
    private(set) var moderateCommunityContentCalls: [(reportId: UUID, action: CommunityModerationAction, reason: String?)] = []

    func fetchDashboardStats(communityId: UUID?) async throws -> AdminDashboardStats {
        fetchDashboardStatsCalls.append(communityId)
        await actionGate?()
        return try fetchDashboardStatsResult.get()
    }

    func fetchFulfilledBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [FulfilledPeriod] {
        fetchFulfilledBreakdownCalls.append((communityId, period, count))
        return try fetchFulfilledBreakdownResult.get()
    }

    func fetchSavingsBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [SavingsPeriod] {
        fetchSavingsBreakdownCalls.append((communityId, period, count))
        return try fetchSavingsBreakdownResult.get()
    }

    func fetchActiveRequests(communityId: UUID?) async throws -> [ActiveRequestRow] {
        fetchActiveRequestsCalls.append(communityId)
        return try fetchActiveRequestsResult.get()
    }

    func sendBroadcast(communityId: UUID, title: String, message: String, pinToNotifications: Bool) async throws -> Int {
        sendBroadcastCalls.append((communityId, title, message, pinToNotifications))
        await actionGate?()
        return try sendBroadcastResult.get()
    }

    func fetchCommunityReports(communityId: UUID, status: String?) async throws -> [CommunityReport] {
        fetchCommunityReportsCalls.append((communityId, status))
        return try fetchCommunityReportsResult.get()
    }

    func moderateCommunityContent(reportId: UUID, action: CommunityModerationAction, reason: String?) async throws {
        moderateCommunityContentCalls.append((reportId, action, reason))
        await actionGate?()
        try moderateCommunityContentResult.get()
    }
}

final class StubApplicantContactFetcher: ApplicantContactFetching {
    var result: Result<ApplicantContact, Error> = .success(
        ApplicantContact(email: "dana@example.com", phoneNumber: "+12065550142")
    )
    private(set) var calls: [UUID] = []

    func fetchApplicantContact(userId: UUID) async throws -> ApplicantContact {
        calls.append(userId)
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

/// Stub for `PlaceGeocoding`: forward answers by exact query (and address), one reverse answer,
/// and every call recorded.
final class StubPlaceGeocoder: PlaceGeocoding {
    var forwardResults: [String: GeocodedPlace] = [:]
    private(set) var forwardCalls: [String] = []
    var reverseResult: GeocodedPlace?
    private(set) var reverseCalls: [GeoPoint] = []

    func resolveTownOrZIP(_ query: String) async throws -> GeocodedPlace? {
        forwardCalls.append(query)
        return forwardResults[query]
    }

    func resolveTownOrZIP(at point: GeoPoint) async throws -> GeocodedPlace? {
        reverseCalls.append(point)
        return reverseResult
    }

    func place(forAddress address: String) async throws -> GeocodedPlace? {
        forwardCalls.append(address)
        return forwardResults[address]
    }
}

/// Stub for `OneShotLocating`: a set access state and fix (returned whatever `access` says, so a
/// test controls both), and the number of fixes asked for.
final class StubLocator: OneShotLocating {
    var access: LocationAccess = .allowed
    var location: GeoPoint?
    private(set) var currentLocationCalls = 0

    func currentLocation(timeout: TimeInterval) async -> GeoPoint? {
        currentLocationCalls += 1
        return location
    }
}
