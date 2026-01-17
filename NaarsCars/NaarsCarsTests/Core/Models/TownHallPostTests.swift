//
//  TownHallPostTests.swift
//  NaarsCarsTests
//
//  Unit tests for TownHallPost model
//

import XCTest
@testable import NaarsCars

final class TownHallPostTests: XCTestCase {
    
    func testCodableDecoding() throws {
        // Given: JSON with snake_case keys matching database schema
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "title": "Test Post",
            "content": "This is a test post content",
            "image_url": "https://example.com/image.jpg",
            "pinned": false,
            "created_at": "2025-01-05T12:00:00.000Z",
            "updated_at": "2025-01-05T12:00:00.000Z"
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
        
        let post = try decoder.decode(TownHallPost.self, from: json)
        
        // Then: All fields should be correctly mapped
        XCTAssertEqual(post.id.uuidString, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(post.userId.uuidString, "223e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(post.title, "Test Post")
        XCTAssertEqual(post.content, "This is a test post content")
        XCTAssertEqual(post.imageUrl, "https://example.com/image.jpg")
        XCTAssertEqual(post.pinned, false)
        XCTAssertNotNil(post.createdAt)
        XCTAssertNotNil(post.updatedAt)
    }
    
    func testCodableDecoding_WithoutOptionalFields() throws {
        // Given: JSON without optional fields (title, pinned, type)
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "content": "Simple post",
            "created_at": "2025-01-05T12:00:00Z",
            "updated_at": "2025-01-05T12:00:00Z"
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(TownHallPost.self, from: json)
        
        // Then: Should decode successfully with nil optional fields
        XCTAssertEqual(post.content, "Simple post")
        XCTAssertNil(post.title)
        XCTAssertNil(post.pinned)
        XCTAssertNil(post.imageUrl)
    }
    
    func testCodableDecoding_WithPostType() throws {
        // Given: JSON with type field
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "content": "Review post",
            "type": "review",
            "created_at": "2025-01-05T12:00:00Z",
            "updated_at": "2025-01-05T12:00:00Z"
        }
        """.data(using: .utf8)!
        
        // When: Decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(TownHallPost.self, from: json)
        
        // Then: Type should be decoded
        XCTAssertEqual(post.type, .review)
    }
    
    func testTownHallPostEquatable() {
        let id = UUID()
        let userId = UUID()
        let date = Date()
        
        let post1 = TownHallPost(
            id: id,
            userId: userId,
            content: "Test",
            createdAt: date,
            updatedAt: date
        )
        
        let post2 = TownHallPost(
            id: id,
            userId: userId,
            content: "Test",
            createdAt: date,
            updatedAt: date
        )
        
        XCTAssertEqual(post1, post2)
    }
    
    func testPostTypeEnum() {
        // Test all post types
        XCTAssertEqual(PostType.userPost.rawValue, "user_post")
        XCTAssertEqual(PostType.review.rawValue, "review")
        XCTAssertEqual(PostType.completion.rawValue, "completion")
    }
}



