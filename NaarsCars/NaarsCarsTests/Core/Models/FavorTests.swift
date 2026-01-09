//
//  FavorTests.swift
//  NaarsCarsTests
//
//  Unit tests for Favor model
//

import XCTest
@testable import NaarsCars

final class FavorTests: XCTestCase {
    
    func testFavorDecodingWithEnums() throws {
        // Given: JSON with favor status and duration enums
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "title": "Help moving boxes",
            "description": "Need help moving 5 boxes",
            "location": "123 Main St",
            "duration": "couple_hours",
            "requirements": null,
            "date": "2025-01-12T00:00:00Z",
            "time": "14:00:00",
            "gift": null,
            "status": "open",
            "claimed_by": null,
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
        let favor = try decoder.decode(Favor.self, from: json)
        
        // Then: Enums should be correctly decoded
        XCTAssertEqual(favor.status, .open)
        XCTAssertEqual(favor.duration, .coupleHours)
        XCTAssertEqual(favor.title, "Help moving boxes")
    }
    
    func testFavorEncodingWithEnums() throws {
        // Given: A Favor instance with enums
        let favor = Favor(
            userId: UUID(),
            title: "Pet sitting",
            location: "789 Pine Rd",
            duration: .coupleDays,
            date: Date(),
            status: .confirmed
        )
        
        // When: Encoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(favor)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        
        // Then: Enums should be encoded as strings
        XCTAssertEqual(json["status"] as? String, "confirmed")
        XCTAssertEqual(json["duration"] as? String, "couple_days")
    }
    
    func testFavorEquatable() {
        let id = UUID()
        let userId = UUID()
        // Use a fixed date to avoid microsecond differences
        let date = Date(timeIntervalSince1970: 1736000000) // Fixed timestamp
        
        let favor1 = Favor(
            id: id,
            userId: userId,
            title: "Test Favor",
            location: "Test Location",
            date: date,
            createdAt: date,
            updatedAt: date
        )
        
        let favor2 = Favor(
            id: id,
            userId: userId,
            title: "Test Favor",
            location: "Test Location",
            date: date,
            createdAt: date,
            updatedAt: date
        )
        
        XCTAssertEqual(favor1, favor2)
    }
    
    func testCodableDecoding_Success() throws {
        // Given: JSON with snake_case keys matching database schema
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "title": "Help with groceries",
            "description": "Need help carrying groceries to apartment",
            "location": "456 Oak Avenue",
            "duration": "under_hour",
            "requirements": "Must be able to lift 20 lbs",
            "date": "2025-01-15T00:00:00Z",
            "time": "16:30:00",
            "gift": "Coffee and cookies",
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
        let favor = try decoder.decode(Favor.self, from: json)
        
        // Then: All snake_case fields should be correctly mapped to camelCase
        XCTAssertEqual(favor.userId.uuidString, "223e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(favor.title, "Help with groceries")
        XCTAssertEqual(favor.description, "Need help carrying groceries to apartment")
        XCTAssertEqual(favor.location, "456 Oak Avenue")
        XCTAssertEqual(favor.duration, .underHour)
        XCTAssertEqual(favor.requirements, "Must be able to lift 20 lbs")
        XCTAssertEqual(favor.time, "16:30:00")
        XCTAssertEqual(favor.gift, "Coffee and cookies")
        XCTAssertEqual(favor.status, .open)
        XCTAssertNil(favor.claimedBy)
        XCTAssertEqual(favor.reviewed, false)
    }
}

