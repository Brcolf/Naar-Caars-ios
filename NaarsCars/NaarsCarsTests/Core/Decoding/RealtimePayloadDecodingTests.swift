//
//  RealtimePayloadDecodingTests.swift
//  NaarsCars
//
//  Unit tests for realtime message payload decoding
//

import Foundation
import XCTest
@testable import NaarsCars

final class RealtimePayloadDecodingTests: XCTestCase {
    func testParseMessageFromPayload_WithFullFixtureRecord() {
        guard let message = MessagingMapper.parseMessage(from: RealtimeFixtures.messageRecord) else {
            XCTFail("Expected message to decode from full fixture record")
            return
        }

        XCTAssertEqual(message.id, RealtimeFixtures.messageId)
        XCTAssertEqual(message.conversationId, RealtimeFixtures.conversationId)
        XCTAssertEqual(message.fromId, RealtimeFixtures.senderId)
        XCTAssertEqual(message.text, "Fixture message body")
        XCTAssertEqual(message.messageType, .text)
        XCTAssertEqual(message.readBy, [RealtimeFixtures.senderId])
        XCTAssertEqual(message.replyToId, RealtimeFixtures.replyToId)
        XCTAssertEqual(message.imageUrl, "https://example.com/image.jpg")
        XCTAssertEqual(message.audioUrl, "https://example.com/audio.m4a")
        XCTAssertEqual(message.audioDuration, 12.5)
        XCTAssertEqual(message.latitude, 37.7749)
        XCTAssertEqual(message.longitude, -122.4194)
        XCTAssertEqual(message.locationName, "San Francisco")
        XCTAssertNotNil(message.editedAt)
        XCTAssertNil(message.deletedAt)
    }

    func testParseMessageFromPayload_WithMinimalRequiredFields() {
        let message = MessagingMapper.parseMessage(from: RealtimeFixtures.minimalMessageRecord)
        XCTAssertNotNil(message)
    }

    func testParseMessageFromPayload_MissingRequiredFieldReturnsNil() {
        var missingFrom = RealtimeFixtures.minimalMessageRecord
        missingFrom.removeValue(forKey: "from_id")
        XCTAssertNil(MessagingMapper.parseMessage(from: missingFrom))
    }

    func testParseMessageFromPayload_ParsesFractionalISO8601Date() {
        var payload = RealtimeFixtures.minimalMessageRecord
        payload["created_at"] = RealtimeFixtures.createdAtFractional

        guard let message = MessagingMapper.parseMessage(from: payload) else {
            XCTFail("Expected message to decode with fractional seconds date")
            return
        }
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, RealtimeFixtures.createdAtEpochSeconds, accuracy: 1.0)
    }

    func testParseMessageFromPayload_ParsesISO8601DateWithoutFractionalSeconds() {
        var payload = RealtimeFixtures.minimalMessageRecord
        payload["created_at"] = RealtimeFixtures.createdAtNoFractional

        guard let message = MessagingMapper.parseMessage(from: payload) else {
            XCTFail("Expected message to decode without fractional seconds")
            return
        }
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, RealtimeFixtures.createdAtEpochSeconds, accuracy: 1.0)
    }

    func testParseMessageFromPayload_ParsesEpochSeconds() {
        var payload = RealtimeFixtures.minimalMessageRecord
        payload["created_at"] = RealtimeFixtures.createdAtEpochSeconds

        guard let message = MessagingMapper.parseMessage(from: payload) else {
            XCTFail("Expected message to decode with epoch seconds")
            return
        }
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, RealtimeFixtures.createdAtEpochSeconds, accuracy: 0.001)
    }

    func testParseMessageFromPayload_ParsesEpochMilliseconds() {
        var payload = RealtimeFixtures.minimalMessageRecord
        payload["created_at"] = RealtimeFixtures.createdAtEpochMilliseconds

        guard let message = MessagingMapper.parseMessage(from: payload) else {
            XCTFail("Expected message to decode with epoch milliseconds")
            return
        }
        // Milliseconds are divided by 1000, so allow ~1 second accuracy
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, RealtimeFixtures.createdAtEpochSeconds, accuracy: 1.0)
    }

    func testParseMessageFromPayload_ParsesReadByAsEmptyArray() {
        var payload = RealtimeFixtures.minimalMessageRecord
        payload["read_by"] = []

        guard let message = MessagingMapper.parseMessage(from: payload) else {
            XCTFail("Expected message to decode with empty read_by")
            return
        }
        XCTAssertTrue(message.readBy.isEmpty)
    }

    func testParseMessageFromPayload_ParsesReadByUUIDArray() {
        let otherUser = UUID(uuidString: "34343434-3434-3434-3434-343434343434")!
        var payload = RealtimeFixtures.minimalMessageRecord
        payload["read_by"] = [RealtimeFixtures.senderId.uuidString, otherUser.uuidString]

        guard let message = MessagingMapper.parseMessage(from: payload) else {
            XCTFail("Expected message to decode with two read_by UUIDs")
            return
        }
        XCTAssertEqual(message.readBy, [RealtimeFixtures.senderId, otherUser])
    }

    func testRealtimePayloadAdapterDecodeInsert_WithDictionaryPayload() {
        let payload: [String: Any] = [
            "record": [
                "id": UUID().uuidString,
                "name": "inserted"
            ]
        ]

        let decoded = RealtimePayloadAdapter.decodeInsert(payload, table: "messages")

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.table, "messages")
        if case .insert = decoded?.eventType {
            // expected
        } else {
            XCTFail("Expected insert event type")
        }
        XCTAssertEqual(decoded?.record["name"] as? String, "inserted")
        XCTAssertNil(decoded?.oldRecord)
    }

    func testRealtimePayloadAdapterDecodeUpdate_WithDictionaryPayload() {
        let payload: [String: Any] = [
            "record": [
                "id": UUID().uuidString,
                "status": "open"
            ],
            "old_record": [
                "id": UUID().uuidString,
                "status": "draft"
            ]
        ]

        let decoded = RealtimePayloadAdapter.decodeUpdate(payload, table: "rides")

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.table, "rides")
        if case .update = decoded?.eventType {
            // expected
        } else {
            XCTFail("Expected update event type")
        }
        XCTAssertEqual(decoded?.record["status"] as? String, "open")
        XCTAssertEqual(decoded?.oldRecord?["status"] as? String, "draft")
    }

    func testRealtimePayloadAdapterDecodeDelete_WithDictionaryPayload() {
        let payload: [String: Any] = [
            "old_record": [
                "id": UUID().uuidString,
                "deleted_at": "2026-02-10T00:00:00Z"
            ]
        ]

        let decoded = RealtimePayloadAdapter.decodeDelete(payload, table: "messages")

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.table, "messages")
        if case .delete = decoded?.eventType {
            // expected
        } else {
            XCTFail("Expected delete event type")
        }
        XCTAssertEqual(decoded?.record["deleted_at"] as? String, "2026-02-10T00:00:00Z")
        XCTAssertEqual(decoded?.oldRecord?["deleted_at"] as? String, "2026-02-10T00:00:00Z")
    }

    // MARK: - DashboardPayloadMapper Tests

    func testDashboardPayloadMapper_ParsesRideFromFixture() {
        let record = RealtimeRecord(
            table: "rides",
            eventType: .insert,
            record: RealtimeFixtures.rideRecord,
            oldRecord: nil
        )

        let ride = DashboardPayloadMapper.ride(from: record)
        XCTAssertNotNil(ride, "Should parse ride from fixture record")
        XCTAssertEqual(ride?.id, RealtimeFixtures.rideId)
        XCTAssertEqual(ride?.userId, RealtimeFixtures.userId)
        XCTAssertEqual(ride?.type, "offering")
        XCTAssertEqual(ride?.pickup, "North Lot")
        XCTAssertEqual(ride?.destination, "Campus Center")
        XCTAssertEqual(ride?.seats, 2)
        XCTAssertEqual(ride?.status, .open)
        XCTAssertNil(ride?.claimedBy)
    }

    func testDashboardPayloadMapper_ParsesFavorFromFixture() {
        let record = RealtimeRecord(
            table: "favors",
            eventType: .insert,
            record: RealtimeFixtures.favorRecord,
            oldRecord: nil
        )

        let favor = DashboardPayloadMapper.favor(from: record)
        XCTAssertNotNil(favor, "Should parse favor from fixture record")
        XCTAssertEqual(favor?.id, RealtimeFixtures.favorId)
        XCTAssertEqual(favor?.userId, RealtimeFixtures.userId)
        XCTAssertEqual(favor?.title, "Need groceries")
        XCTAssertEqual(favor?.location, "Main Street")
        XCTAssertEqual(favor?.duration, .underHour)
        XCTAssertEqual(favor?.status, .open)
        XCTAssertNil(favor?.claimedBy)
    }

    func testDashboardPayloadMapper_MissingRequiredField_ReturnsNil() {
        var incomplete = RealtimeFixtures.rideRecord
        incomplete.removeValue(forKey: "seats")

        let record = RealtimeRecord(
            table: "rides",
            eventType: .insert,
            record: incomplete,
            oldRecord: nil
        )

        XCTAssertNil(DashboardPayloadMapper.ride(from: record))
    }

    // MARK: - NotificationPayloadMapper Tests

    func testNotificationPayloadMapper_ParsesNotificationFromFixture() {
        let record = RealtimeRecord(
            table: "notifications",
            eventType: .insert,
            record: RealtimeFixtures.notificationRecord,
            oldRecord: nil
        )

        let notification = NotificationPayloadMapper.notification(from: record)
        XCTAssertNotNil(notification, "Should parse notification from fixture record")
        XCTAssertEqual(notification?.id, RealtimeFixtures.notificationId)
        XCTAssertEqual(notification?.userId, RealtimeFixtures.userId)
        XCTAssertEqual(notification?.type, .rideClaimed)
        XCTAssertEqual(notification?.title, "Ride claimed")
        XCTAssertEqual(notification?.body, "Your ride has been claimed")
        XCTAssertEqual(notification?.read, false)
        XCTAssertEqual(notification?.pinned, false)
        XCTAssertEqual(notification?.rideId, RealtimeFixtures.rideId)
        XCTAssertEqual(notification?.sourceUserId, RealtimeFixtures.senderId)
        XCTAssertNil(notification?.favorId)
        XCTAssertNil(notification?.conversationId)
    }

    func testNotificationPayloadMapper_MissingRequiredField_ReturnsNil() {
        var incomplete = RealtimeFixtures.notificationRecord
        incomplete.removeValue(forKey: "type")

        let record = RealtimeRecord(
            table: "notifications",
            eventType: .insert,
            record: incomplete,
            oldRecord: nil
        )

        XCTAssertNil(NotificationPayloadMapper.notification(from: record))
    }

    func testNotificationPayloadMapper_ExtractsIdFromDeleteEvent() {
        let record = RealtimeRecord(
            table: "notifications",
            eventType: .delete,
            record: [:],
            oldRecord: RealtimeFixtures.notificationRecord
        )

        let id = NotificationPayloadMapper.notificationId(fromDeleteEvent: record)
        XCTAssertEqual(id, RealtimeFixtures.notificationId)
    }
}
