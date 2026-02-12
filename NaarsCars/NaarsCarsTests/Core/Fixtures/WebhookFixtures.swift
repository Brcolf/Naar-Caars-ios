//
//  WebhookFixtures.swift
//  NaarsCars
//
//  Fixture payloads for webhook and deep link decoding tests
//

import Foundation

enum WebhookFixtures {
    static let conversationId = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    static let messageId = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    static let senderId = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    static let rideId = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
    static let favorId = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
    static let postId = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
    static let userId = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!

    static let messagePushPayload: [String: Any] = [
        "aps": [
            "alert": [
                "title": "Message from Alex",
                "body": "Hey there"
            ],
            "sound": "default",
            "badge": 3,
            "priority": 10,
            "category": "MESSAGE"
        ],
        "type": "message",
        "conversation_id": conversationId.uuidString,
        "message_id": messageId.uuidString,
        "sender_id": senderId.uuidString
    ]

    static let notificationPushPayload: [String: Any] = [
        "aps": [
            "alert": [
                "title": "Ride claimed",
                "body": "Someone claimed your ride"
            ],
            "sound": "default",
            "badge": 4,
            "mutable-content": 1,
            "category": "NEW_REQUEST"
        ],
        "type": "ride_claimed",
        "ride_id": rideId.uuidString,
        "user_id": userId.uuidString
    ]

    static let resolveEventTypePayloads: [[String: Any]] = [
        ["type": "INSERT"],
        ["eventType": "UPDATE"],
        ["event_type": "DELETE"],
        ["data": ["type": "INSERT"]]
    ]

    static func resolveEventType(from payload: [String: Any]) -> String? {
        return payload["type"] as? String ??
            payload["eventType"] as? String ??
            payload["event_type"] as? String ??
            ((payload["data"] as? [String: Any])?["type"] as? String) ??
            ((payload["data"] as? [String: Any])?["eventType"] as? String) ??
            ((payload["data"] as? [String: Any])?["event_type"] as? String)
    }
}
