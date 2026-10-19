//
//  DeepLinkParserTests.swift
//  NaarsCarsTests
//
//  Unit tests for DeepLinkParser
//

import XCTest
@testable import NaarsCars

final class DeepLinkParserTests: XCTestCase {
    
    /// Test parsing ride notification
    func testParse_RideNotification() {
        // Given: A ride notification payload
        let rideId = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "ride_claimed",
            "ride_id": rideId.uuidString
        ]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return ride deep link with correct ID
        if case .ride(let id) = deepLink {
            XCTAssertEqual(id, rideId, "Should parse ride ID correctly")
        } else {
            XCTFail("Expected .ride deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing favor notification
    func testParse_FavorNotification() {
        // Given: A favor notification payload
        let favorId = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "favor_claimed",
            "favor_id": favorId.uuidString
        ]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return favor deep link with correct ID
        if case .favor(let id) = deepLink {
            XCTAssertEqual(id, favorId, "Should parse favor ID correctly")
        } else {
            XCTFail("Expected .favor deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing message notification
    func testParse_MessageNotification() {
        // Given: A message notification payload
        let conversationId = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "new_message",
            "conversation_id": conversationId.uuidString
        ]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return conversation deep link with correct ID
        if case .conversation(let id) = deepLink {
            XCTAssertEqual(id, conversationId, "Should parse conversation ID correctly")
        } else {
            XCTFail("Expected .conversation deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing profile notification
    func testParse_ProfileNotification() {
        // Given: A profile notification payload
        let userId = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "profile_update",
            "user_id": userId.uuidString
        ]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return profile deep link with correct ID
        if case .profile(let id) = deepLink {
            XCTAssertEqual(id, userId, "Should parse user ID correctly")
        } else {
            XCTFail("Expected .profile deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing announcements notification
    func testParse_NotificationsNotification() {
        // Given: A notifications list notification payload
        let userInfo: [AnyHashable: Any] = [
            "type": "announcement",
            "notification_id": UUID().uuidString
        ]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return announcements deep link
        if case .announcements = deepLink {
            XCTAssertTrue(true, "Should parse announcements deep link")
        } else {
            XCTFail("Expected .announcements deep link, got \(deepLink)")
        }
    }

    /// Test parsing town hall post notification
    func testParse_TownHallPostNotification() {
        let postId = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "town_hall_post",
            "town_hall_post_id": postId.uuidString
        ]
        
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        if case .townHallPostComments(let id, _) = deepLink {
            XCTAssertEqual(id, postId, "Should parse town hall post ID correctly")
        } else {
            XCTFail("Expected .townHallPostComments deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing pending approval notification
    func testParse_AdminNotification() {
        let userInfo: [AnyHashable: Any] = [
            "type": "pending_approval"
        ]
        
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        if case .pendingUsers = deepLink {
            XCTAssertTrue(true, "Should parse pending users deep link")
        } else {
            XCTFail("Expected .pendingUsers deep link, got \(deepLink)")
        }
    }
    
    /// `pending_approval` for a community (multi-community Phase 2) opens that community's
    /// Requests to join.
    func testParse_PendingApprovalWithCommunityIdRoutesToPendingMembers() {
        let communityId = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "pending_approval",
            "user_id": UUID().uuidString,
            "community_id": communityId.uuidString
        ]

        let deepLink = DeepLinkParser.parse(userInfo: userInfo)

        if case .pendingMembers(let routedId) = deepLink {
            XCTAssertEqual(routedId, communityId)
        } else {
            XCTFail("Expected .pendingMembers deep link, got \(deepLink)")
        }
    }

    /// A `community_id` that is not a UUID keeps the platform route.
    func testParse_PendingApprovalWithMalformedCommunityIdStaysPendingUsers() {
        let userInfo: [AnyHashable: Any] = [
            "type": "pending_approval",
            "community_id": "not-a-uuid"
        ]

        let deepLink = DeepLinkParser.parse(userInfo: userInfo)

        if case .pendingUsers = deepLink {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .pendingUsers deep link, got \(deepLink)")
        }
    }

    /// Test parsing review request notification
    func testParse_ReviewRequestNotification() {
        let rideId = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "review_request",
            "ride_id": rideId.uuidString
        ]
        
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        if case .ride(let id) = deepLink {
            XCTAssertEqual(id, rideId, "Should parse review_request ride ID correctly")
        } else {
            XCTFail("Expected .ride deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing user approved notification
    func testParse_UserApprovedNotification() {
        let userInfo: [AnyHashable: Any] = [
            "type": "user_approved",
            "action": "enter_app"
        ]
        
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        if case .enterApp = deepLink {
            XCTAssertTrue(true, "Should parse enter app deep link")
        } else {
            XCTFail("Expected .enterApp deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing unknown notification
    func testParse_UnknownNotification() {
        // Given: An unknown notification payload
        let userInfo: [AnyHashable: Any] = [
            "type": "unknown_type"
        ]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return unknown deep link
        if case .unknown = deepLink {
            XCTAssertTrue(true, "Should return unknown for unrecognized types")
        } else {
            XCTFail("Expected .unknown deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing notification without type
    func testParse_NoType() {
        // Given: A notification payload without type
        let userInfo: [AnyHashable: Any] = [:]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return unknown deep link
        if case .unknown = deepLink {
            XCTAssertTrue(true, "Should return unknown when type is missing")
        } else {
            XCTFail("Expected .unknown deep link, got \(deepLink)")
        }
    }
    
    /// Test parsing ride notification with invalid UUID
    func testParse_RideNotification_InvalidUUID() {
        // Given: A ride notification payload with invalid UUID
        let userInfo: [AnyHashable: Any] = [
            "type": "ride_claimed",
            "ride_id": "invalid-uuid"
        ]
        
        // When: Parsing the deep link
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Then: Should return unknown deep link
        if case .unknown = deepLink {
            XCTAssertTrue(true, "Should return unknown for invalid UUID")
        } else {
            XCTFail("Expected .unknown deep link for invalid UUID, got \(deepLink)")
        }
    }

    // MARK: - Town Hall community_id (multi-community Phase 1)

    func testParse_TownHallTypesCarryCommunityIdWhenPresent() {
        let postId = UUID()
        let communityId = UUID()
        for type in ["town_hall_post", "town_hall_comment", "town_hall_reaction"] {
            let deepLink = DeepLinkParser.parse(userInfo: [
                "type": type,
                "town_hall_post_id": postId.uuidString,
                "community_id": communityId.uuidString
            ])
            switch deepLink {
            case .townHallPostComments(let id, let community) where type == "town_hall_post":
                XCTAssertEqual(id, postId, type)
                XCTAssertEqual(community, communityId, type)
            case .townHallPostHighlight(let id, let community) where type != "town_hall_post":
                XCTAssertEqual(id, postId, type)
                XCTAssertEqual(community, communityId, type)
            default:
                XCTFail("Unexpected deep link for \(type): \(deepLink)")
            }
        }
    }

    func testParse_TownHallTypesWithoutCommunityIdParseAsBefore() {
        let postId = UUID()
        for type in ["town_hall_post", "town_hall_comment", "town_hall_reaction"] {
            let deepLink = DeepLinkParser.parse(userInfo: [
                "type": type,
                "town_hall_post_id": postId.uuidString
            ])
            switch deepLink {
            case .townHallPostComments(let id, let community) where type == "town_hall_post":
                XCTAssertEqual(id, postId, type)
                XCTAssertNil(community, type)
            case .townHallPostHighlight(let id, let community) where type != "town_hall_post":
                XCTAssertEqual(id, postId, type)
                XCTAssertNil(community, type)
            default:
                XCTFail("Unexpected deep link for \(type): \(deepLink)")
            }
        }
    }

    func testParse_ContentHiddenTownHallPostCarriesCommunityId() {
        let postId = UUID()
        let communityId = UUID()

        let withCommunity = DeepLinkParser.parse(userInfo: [
            "type": "content_hidden",
            "town_hall_post_id": postId.uuidString,
            "community_id": communityId.uuidString
        ])
        guard case .townHallPostHighlight(let id, let community) = withCommunity else {
            return XCTFail("Expected .townHallPostHighlight, got \(withCommunity)")
        }
        XCTAssertEqual(id, postId)
        XCTAssertEqual(community, communityId)

        let withoutCommunity = DeepLinkParser.parse(userInfo: [
            "type": "content_hidden",
            "town_hall_post_id": postId.uuidString
        ])
        guard case .townHallPostHighlight(let idWithout, let communityWithout) = withoutCommunity else {
            return XCTFail("Expected .townHallPostHighlight, got \(withoutCommunity)")
        }
        XCTAssertEqual(idWithout, postId)
        XCTAssertNil(communityWithout)
    }

    // MARK: - content_reported and account_restricted (multi-community Phase 3)

    /// A community owner's or admin's `content_reported` push carries `community_id` and opens
    /// that community's reports.
    func testParse_ContentReportedWithCommunityIdRoutesToCommunityReports() {
        let communityId = UUID()
        let deepLink = DeepLinkParser.parse(userInfo: [
            "type": "content_reported",
            "report_id": UUID().uuidString,
            "target_type": "town_hall_post",
            "town_hall_post_id": UUID().uuidString,
            "community_id": communityId.uuidString
        ])

        guard case .communityReports(let routedId) = deepLink else {
            return XCTFail("Expected .communityReports deep link, got \(deepLink)")
        }
        XCTAssertEqual(routedId, communityId)
    }

    /// A platform admin's push has no `community_id` and keeps the platform reports route.
    func testParse_ContentReportedWithoutCommunityIdStaysAdminReports() {
        let deepLink = DeepLinkParser.parse(userInfo: [
            "type": "content_reported",
            "report_id": UUID().uuidString,
            "target_type": "town_hall_post",
            "town_hall_post_id": UUID().uuidString
        ])

        guard case .adminReports = deepLink else {
            return XCTFail("Expected .adminReports deep link, got \(deepLink)")
        }
    }

    /// A `community_id` that is not a UUID keeps the platform route.
    func testParse_ContentReportedWithMalformedCommunityIdStaysAdminReports() {
        let deepLink = DeepLinkParser.parse(userInfo: [
            "type": "content_reported",
            "community_id": "not-a-uuid"
        ])

        guard case .adminReports = deepLink else {
            return XCTFail("Expected .adminReports deep link, got \(deepLink)")
        }
    }

    /// A removal (`account_restricted`) opens My communities, with or without `community_id`.
    func testParse_AccountRestrictedRoutesToMyCommunities() {
        let withCommunity = DeepLinkParser.parse(userInfo: [
            "type": "account_restricted",
            "community_id": UUID().uuidString
        ])
        guard case .myCommunities = withCommunity else {
            return XCTFail("Expected .myCommunities deep link, got \(withCommunity)")
        }

        let withoutCommunity = DeepLinkParser.parse(userInfo: ["type": "account_restricted"])
        guard case .myCommunities = withoutCommunity else {
            return XCTFail("Expected .myCommunities deep link, got \(withoutCommunity)")
        }
    }
}
