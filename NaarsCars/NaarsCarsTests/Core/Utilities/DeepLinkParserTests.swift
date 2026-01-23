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
        
        if case .townHallPostComments(let id) = deepLink {
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
}



