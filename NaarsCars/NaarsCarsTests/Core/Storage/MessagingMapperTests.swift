//
//  MessagingMapperTests.swift
//  NaarsCarsTests
//
//  Unit tests for MessagingMapper payload parsing
//

import Foundation
import XCTest
@testable import NaarsCars

final class MessagingMapperTests: XCTestCase {
    func testParseMessageFromPayload_WithPlainStringValues() {
        let id = UUID()
        let conversationId = UUID()
        let fromId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let payload: [String: Any] = [
            "id": id.uuidString,
            "conversation_id": conversationId.uuidString,
            "from_id": fromId.uuidString,
            "text": "Hello from tests",
            "read_by": [fromId.uuidString],
            "created_at": formatter.string(from: createdAt)
        ]

        guard let message = MessagingMapper.parseMessageFromPayload(payload) else {
            XCTFail("Expected message to parse from payload")
            return
        }

        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.conversationId, conversationId)
        XCTAssertEqual(message.fromId, fromId)
        XCTAssertEqual(message.text, "Hello from tests")
        XCTAssertEqual(message.readBy, [fromId])
    }

    func testParseMessageFromPayload_WithAnyHashableValues() {
        let id = UUID()
        let conversationId = UUID()
        let fromId = UUID()

        let payload: [String: Any] = [
            "id": AnyHashable(id.uuidString),
            "conversation_id": AnyHashable(conversationId.uuidString),
            "from_id": AnyHashable(fromId.uuidString),
            "text": AnyHashable("Wrapped text"),
            "read_by": [AnyHashable(fromId.uuidString)]
        ]

        guard let message = MessagingMapper.parseMessageFromPayload(payload) else {
            XCTFail("Expected message to parse from AnyHashable payload")
            return
        }

        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.conversationId, conversationId)
        XCTAssertEqual(message.fromId, fromId)
        XCTAssertEqual(message.text, "Wrapped text")
        XCTAssertEqual(message.readBy, [fromId])
    }
}
