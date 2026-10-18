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
    static let communityId = UUID(uuidString: "34343434-3434-4343-8343-343434343434")!

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

    /// `notificationPushPayload` plus the `community_id` key the community-aware edge function adds.
    static let notificationPushPayloadWithCommunity: [String: Any] = {
        var payload = notificationPushPayload
        payload["community_id"] = communityId.uuidString
        return payload
    }()

    static let townHallPostPushPayload: [String: Any] = [
        "aps": [
            "alert": [
                "title": "New Town Hall post",
                "body": "Someone posted in Town Hall"
            ],
            "sound": "default",
            "badge": 2
        ],
        "type": "town_hall_post",
        "town_hall_post_id": postId.uuidString,
        "community_id": communityId.uuidString
    ]

    /// A Town Hall push from a server without the community key (an older edge function).
    static let townHallCommentPushPayload: [String: Any] = [
        "aps": [
            "alert": [
                "title": "New comment",
                "body": "Someone commented on your post"
            ],
            "sound": "default",
            "badge": 2
        ],
        "type": "town_hall_comment",
        "town_hall_post_id": postId.uuidString
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
