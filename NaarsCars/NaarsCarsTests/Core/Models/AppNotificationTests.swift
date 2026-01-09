//
//  AppNotificationTests.swift
//  NaarsCarsTests
//
//  Unit tests for AppNotification model
//

import XCTest
@testable import NaarsCars

final class AppNotificationTests: XCTestCase {
    
    func testCodableDecoding() throws {
        // Given: JSON with snake_case keys matching database schema
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "type": "message",
            "title": "New Message",
            "body": "You have a new message from John",
            "read": false,
            "pinned": false,
            "created_at": "2025-01-05T12:00:00.000Z",
            "ride_id": null,
            "favor_id": null,
            "conversation_id": "323e4567-e89b-12d3-a456-426614174000",
            "review_id": null
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        
        let notification = try decoder.decode(AppNotification.self, from: json)
        
        // Then: All fields should be correctly mapped
        XCTAssertEqual(notification.id.uuidString, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(notification.userId.uuidString, "223e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(notification.type, .message)
        XCTAssertEqual(notification.title, "New Message")
        XCTAssertEqual(notification.body, "You have a new message from John")
        XCTAssertEqual(notification.read, false)
        XCTAssertEqual(notification.pinned, false)
        XCTAssertNotNil(notification.createdAt)
        XCTAssertNil(notification.rideId)
        XCTAssertNil(notification.favorId)
        XCTAssertEqual(notification.conversationId?.uuidString, "323e4567-e89b-12d3-a456-426614174000")
        XCTAssertNil(notification.reviewId)
    }
    
    func testCodableDecoding_AllNotificationTypes() throws {
        // Test that all notification types can be decoded
        let types: [NotificationType] = [
            .message, .rideUpdate, .rideClaimed, .rideUnclaimed,
            .favorUpdate, .favorClaimed, .favorUnclaimed,
            .review, .reviewReceived, .reviewReminder,
            .announcement, .adminAnnouncement, .qaActivity, .other
        ]
        
        for type in types {
            let json = """
            {
                "id": "123e4567-e89b-12d3-a456-426614174000",
                "user_id": "223e4567-e89b-12d3-a456-426614174000",
                "type": "\(type.rawValue)",
                "title": "Test Notification",
                "body": null,
                "read": false,
                "pinned": false,
                "created_at": "2025-01-05T12:00:00Z",
                "ride_id": null,
                "favor_id": null,
                "conversation_id": null,
                "review_id": null
            }
            """.data(using: .utf8)!
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let notification = try decoder.decode(AppNotification.self, from: json)
            XCTAssertEqual(notification.type, type, "Failed to decode notification type: \(type.rawValue)")
        }
    }
    
    func testCodableDecoding_WithRideId() throws {
        // Given: Notification with ride_id
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "type": "ride_claimed",
            "title": "Ride Claimed",
            "body": "Your ride has been claimed",
            "read": false,
            "pinned": false,
            "created_at": "2025-01-05T12:00:00Z",
            "ride_id": "423e4567-e89b-12d3-a456-426614174000",
            "favor_id": null,
            "conversation_id": null,
            "review_id": null
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notification = try decoder.decode(AppNotification.self, from: json)
        
        // Then: ride_id should be set
        XCTAssertEqual(notification.rideId?.uuidString, "423e4567-e89b-12d3-a456-426614174000")
        XCTAssertNil(notification.favorId)
    }
    
    func testCodableDecoding_WithFavorId() throws {
        // Given: Notification with favor_id
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "type": "favor_claimed",
            "title": "Favor Claimed",
            "body": "Your favor has been claimed",
            "read": false,
            "pinned": false,
            "created_at": "2025-01-05T12:00:00Z",
            "ride_id": null,
            "favor_id": "523e4567-e89b-12d3-a456-426614174000",
            "conversation_id": null,
            "review_id": null
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notification = try decoder.decode(AppNotification.self, from: json)
        
        // Then: favor_id should be set
        XCTAssertEqual(notification.favorId?.uuidString, "523e4567-e89b-12d3-a456-426614174000")
        XCTAssertNil(notification.rideId)
    }
    
    func testNotificationTypeIcon() {
        // Test that all notification types have icons
        let types: [NotificationType] = [
            .message, .rideUpdate, .rideClaimed, .rideUnclaimed,
            .favorUpdate, .favorClaimed, .favorUnclaimed,
            .review, .reviewReceived, .reviewReminder,
            .announcement, .adminAnnouncement, .qaActivity, .other
        ]
        
        for type in types {
            let icon = type.icon
            XCTAssertFalse(icon.isEmpty, "Notification type \(type.rawValue) should have an icon")
        }
    }
    
    func testAppNotificationEquatable() {
        let id = UUID()
        let userId = UUID()
        let date = Date()
        
        let notification1 = AppNotification(
            id: id,
            userId: userId,
            type: .message,
            title: "Test",
            body: "Body",
            read: false,
            pinned: false,
            createdAt: date
        )
        
        let notification2 = AppNotification(
            id: id,
            userId: userId,
            type: .message,
            title: "Test",
            body: "Body",
            read: false,
            pinned: false,
            createdAt: date
        )
        
        XCTAssertEqual(notification1, notification2)
    }
}


