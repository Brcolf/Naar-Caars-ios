//
//  RealtimeFixtures.swift
//  NaarsCars
//
//  Fixture payloads for realtime decoding tests
//

import Foundation

enum RealtimeFixtures {
    static let messageId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let conversationId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let senderId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let replyToId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let rideId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    static let favorId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    static let notificationId = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    static let userId = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
    static let townHallPostId = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!

    static let createdAtFractional = "2026-02-09T12:34:56.123Z"
    static let createdAtNoFractional = "2026-02-09T12:34:56Z"
    static let createdAtEpochSeconds: Double = 1_770_640_496
    static let createdAtEpochMilliseconds: Double = 1_770_640_496_123

    static let messageRecord: [String: Any] = [
        "id": messageId.uuidString,
        "conversation_id": conversationId.uuidString,
        "from_id": senderId.uuidString,
        "text": "Fixture message body",
        "message_type": "text",
        "read_by": [senderId.uuidString],
        "created_at": createdAtFractional,
        "image_url": "https://example.com/image.jpg",
        "reply_to_id": replyToId.uuidString,
        "audio_url": "https://example.com/audio.m4a",
        "audio_duration": 12.5,
        "latitude": 37.7749,
        "longitude": -122.4194,
        "location_name": "San Francisco",
        "edited_at": createdAtNoFractional,
        "deleted_at": NSNull()
    ]

    static let minimalMessageRecord: [String: Any] = [
        "id": messageId.uuidString,
        "conversation_id": conversationId.uuidString,
        "from_id": senderId.uuidString,
        "text": "Minimal message",
        "read_by": [],
        "created_at": createdAtNoFractional
    ]

    static let rideRecord: [String: Any] = [
        "id": rideId.uuidString,
        "user_id": userId.uuidString,
        "type": "offering",
        "date": "2026-02-15",
        "time": "14:00:00",
        "timezone": "America/Los_Angeles",
        "pickup": "North Lot",
        "destination": "Campus Center",
        "seats": 2,
        "notes": NSNull(),
        "gift": NSNull(),
        "status": "open",
        "claimed_by": NSNull(),
        "reviewed": false,
        "review_skipped": NSNull(),
        "review_skipped_at": NSNull(),
        "estimated_cost": NSNull(),
        "flight_normalized": NSNull(),
        "created_at": createdAtNoFractional,
        "updated_at": createdAtNoFractional
    ]

    static let favorRecord: [String: Any] = [
        "id": favorId.uuidString,
        "user_id": userId.uuidString,
        "title": "Need groceries",
        "description": "Pick up items from market",
        "location": "Main Street",
        "duration": "under_hour",
        "requirements": NSNull(),
        "date": "2026-02-15",
        "time": NSNull(),
        "timezone": "America/Los_Angeles",
        "gift": NSNull(),
        "status": "open",
        "claimed_by": NSNull(),
        "reviewed": false,
        "review_skipped": NSNull(),
        "review_skipped_at": NSNull(),
        "created_at": createdAtNoFractional,
        "updated_at": createdAtNoFractional
    ]

    static let notificationRecord: [String: Any] = [
        "id": notificationId.uuidString,
        "user_id": userId.uuidString,
        "type": "ride_claimed",
        "title": "Ride claimed",
        "body": "Your ride has been claimed",
        "read": false,
        "pinned": false,
        "ride_id": rideId.uuidString,
        "favor_id": NSNull(),
        "conversation_id": NSNull(),
        "review_id": NSNull(),
        "town_hall_post_id": NSNull(),
        "source_user_id": senderId.uuidString,
        "created_at": createdAtNoFractional
    ]

    static let townHallPostRecord: [String: Any] = [
        "id": townHallPostId.uuidString,
        "user_id": userId.uuidString,
        "title": "Town Hall Fixture",
        "content": "Fixture content",
        "type": "general",
        "pinned": false,
        "created_at": createdAtNoFractional,
        "updated_at": createdAtNoFractional
    ]

    static let deletePayload: [String: Any] = [
        "old_record": messageRecord
    ]
}
