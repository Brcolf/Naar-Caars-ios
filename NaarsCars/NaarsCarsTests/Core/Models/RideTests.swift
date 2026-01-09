//
//  RideTests.swift
//  NaarsCarsTests
//
//  Unit tests for Ride model
//

import XCTest
@testable import NaarsCars

final class RideTests: XCTestCase {
    
    func testRideDecodingWithEnum() throws {
        // Given: JSON with ride status enum
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "type": "request",
            "date": "2025-01-10T00:00:00Z",
            "time": "14:00:00",
            "pickup": "123 Main St",
            "destination": "456 Oak Ave",
            "seats": 2,
            "notes": "Need ride to airport",
            "gift": null,
            "status": "confirmed",
            "claimed_by": "323e4567-e89b-12d3-a456-426614174000",
            "reviewed": false,
            "review_skipped": null,
            "review_skipped_at": null,
            "created_at": "2025-01-05T00:00:00Z",
            "updated_at": "2025-01-05T00:00:00Z"
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ride = try decoder.decode(Ride.self, from: json)
        
        // Then: Enum should be correctly decoded
        XCTAssertEqual(ride.status, .confirmed)
        XCTAssertEqual(ride.pickup, "123 Main St")
        XCTAssertEqual(ride.seats, 2)
        XCTAssertNotNil(ride.claimedBy)
    }
    
    func testRideEncodingWithEnum() throws {
        // Given: A Ride instance with enum
        let ride = Ride(
            userId: UUID(),
            date: Date(),
            time: "10:00:00",
            pickup: "789 Pine Rd",
            destination: "321 Elm St",
            seats: 1,
            status: .open
        )
        
        // When: Encoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(ride)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        
        // Then: Status should be encoded as string
        XCTAssertEqual(json["status"] as? String, "open")
        XCTAssertNotNil(json["user_id"])
    }
    
    func testRideDateHandling() throws {
        // Given: JSON with date string
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "type": "request",
            "date": "2025-01-15T00:00:00Z",
            "time": "16:30:00",
            "pickup": "Test Pickup",
            "destination": "Test Destination",
            "seats": 1,
            "status": "open",
            "reviewed": false,
            "created_at": "2025-01-05T12:00:00Z",
            "updated_at": "2025-01-05T12:00:00Z"
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ride = try decoder.decode(Ride.self, from: json)
        
        // Then: Dates should be correctly parsed
        XCTAssertNotNil(ride.date)
        XCTAssertNotNil(ride.createdAt)
    }
    
    func testCodableDecoding_SnakeCase_Success() throws {
        // Given: JSON with snake_case keys matching database schema
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "type": "request",
            "date": "2025-01-10T00:00:00Z",
            "time": "14:30:00",
            "pickup": "123 Main Street",
            "destination": "456 Oak Avenue",
            "seats": 3,
            "notes": "Need help with luggage",
            "gift": "Coffee and donuts",
            "status": "open",
            "claimed_by": null,
            "reviewed": false,
            "review_skipped": null,
            "review_skipped_at": null,
            "created_at": "2025-01-05T00:00:00Z",
            "updated_at": "2025-01-05T00:00:00Z"
        }
        """.data(using: .utf8)!
        
        // When: Decoding with snake_case keys
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ride = try decoder.decode(Ride.self, from: json)
        
        // Then: All snake_case fields should be correctly mapped to camelCase
        XCTAssertEqual(ride.userId.uuidString, "223e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(ride.pickup, "123 Main Street")
        XCTAssertEqual(ride.destination, "456 Oak Avenue")
        XCTAssertEqual(ride.seats, 3)
        XCTAssertEqual(ride.notes, "Need help with luggage")
        XCTAssertEqual(ride.gift, "Coffee and donuts")
        XCTAssertEqual(ride.status, .open)
        XCTAssertNil(ride.claimedBy)
        XCTAssertEqual(ride.reviewed, false)
        XCTAssertNil(ride.reviewSkipped)
        XCTAssertNil(ride.reviewSkippedAt)
    }
}

