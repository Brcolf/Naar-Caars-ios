//
//  ProfileTests.swift
//  NaarsCarsTests
//
//  Unit tests for Profile model
//

import XCTest
@testable import NaarsCars

final class ProfileTests: XCTestCase {
    
    func testProfileDecodingFromSnakeCaseJSON() throws {
        // Given: JSON with snake_case keys
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "name": "John Doe",
            "email": "john@example.com",
            "car": "Toyota Camry",
            "phone_number": "+12065551234",
            "avatar_url": "https://example.com/avatar.jpg",
            "is_admin": false,
            "approved": true,
            "invited_by": null,
            "notify_ride_updates": true,
            "notify_messages": true,
            "notify_announcements": true,
            "notify_new_requests": true,
            "notify_qa_activity": true,
            "notify_review_reminders": true,
            "created_at": "2025-01-05T00:00:00Z",
            "updated_at": "2025-01-05T00:00:00Z"
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(Profile.self, from: json)
        
        // Then: All fields should be correctly mapped
        XCTAssertEqual(profile.name, "John Doe")
        XCTAssertEqual(profile.email, "john@example.com")
        XCTAssertEqual(profile.car, "Toyota Camry")
        XCTAssertEqual(profile.phoneNumber, "+12065551234")
        XCTAssertEqual(profile.avatarUrl, "https://example.com/avatar.jpg")
        XCTAssertEqual(profile.isAdmin, false)
        XCTAssertEqual(profile.approved, true)
        XCTAssertNil(profile.invitedBy)
        XCTAssertEqual(profile.notifyRideUpdates, true)
    }
    
    func testProfileEncodingToSnakeCaseJSON() throws {
        // Given: A Profile instance
        let profile = Profile(
            id: UUID(),
            name: "Jane Doe",
            email: "jane@example.com",
            car: "Honda Civic",
            phoneNumber: "+12065551235",
            avatarUrl: "https://example.com/jane.jpg",
            isAdmin: true,
            approved: true
        )
        
        // When: Encoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(profile)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        
        // Then: Keys should be in snake_case
        XCTAssertNotNil(json["phone_number"])
        XCTAssertNotNil(json["avatar_url"])
        XCTAssertNotNil(json["is_admin"])
        XCTAssertNotNil(json["created_at"])
        XCTAssertNil(json["phoneNumber"]) // camelCase should not be present
    }
    
    func testProfileEquatable() {
        let id = UUID()
        let date = Date()
        
        let profile1 = Profile(
            id: id,
            name: "Test User",
            email: "test@example.com",
            createdAt: date,
            updatedAt: date
        )
        
        let profile2 = Profile(
            id: id,
            name: "Test User",
            email: "test@example.com",
            createdAt: date,
            updatedAt: date
        )
        
        XCTAssertEqual(profile1, profile2)
    }
}

