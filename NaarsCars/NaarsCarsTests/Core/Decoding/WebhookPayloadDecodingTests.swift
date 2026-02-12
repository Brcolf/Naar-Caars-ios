//
//  WebhookPayloadDecodingTests.swift
//  NaarsCars
//
//  Unit tests for webhook payload and deep link decoding
//

import XCTest
@testable import NaarsCars

final class WebhookPayloadDecodingTests: XCTestCase {
    func testMessagePushPayloadParsesToConversationDeepLink() {
        let deepLink = DeepLinkParser.parse(userInfo: WebhookFixtures.messagePushPayload)
        guard case .conversation(let id) = deepLink else {
            XCTFail("Expected .conversation deep link for message push payload")
            return
        }
        XCTAssertEqual(id, WebhookFixtures.conversationId)
    }

    func testRideNotificationPayloadParsesToRideDeepLink() {
        let deepLink = DeepLinkParser.parse(userInfo: WebhookFixtures.notificationPushPayload)
        guard case .ride(let id) = deepLink else {
            XCTFail("Expected .ride deep link for ride notification payload")
            return
        }
        XCTAssertEqual(id, WebhookFixtures.rideId)
    }

    func testFavorNotificationPayloadParsesToFavorDeepLink() {
        let payload: [AnyHashable: Any] = [
            "type": "favor_claimed",
            "favor_id": WebhookFixtures.favorId.uuidString
        ]
        let deepLink = DeepLinkParser.parse(userInfo: payload)
        guard case .favor(let id) = deepLink else {
            XCTFail("Expected .favor deep link for favor notification payload")
            return
        }
        XCTAssertEqual(id, WebhookFixtures.favorId)
    }

    func testTownHallCommentPayloadParsesToTownHallHighlight() {
        let payload: [AnyHashable: Any] = [
            "type": "town_hall_comment",
            "town_hall_post_id": WebhookFixtures.postId.uuidString
        ]
        let deepLink = DeepLinkParser.parse(userInfo: payload)
        guard case .townHallPostHighlight(let id) = deepLink else {
            XCTFail("Expected .townHallPostHighlight for town hall comment payload")
            return
        }
        XCTAssertEqual(id, WebhookFixtures.postId)
    }

    func testAnnouncementPayloadParsesToAnnouncementsDeepLink() {
        let payload: [AnyHashable: Any] = [
            "type": "announcement",
            "notification_id": UUID().uuidString
        ]
        let deepLink = DeepLinkParser.parse(userInfo: payload)
        guard case .announcements = deepLink else {
            XCTFail("Expected .announcements deep link for announcement payload")
            return
        }
    }

    func testPendingApprovalPayloadParsesToPendingUsersDeepLink() {
        let payload: [AnyHashable: Any] = [
            "type": "pending_approval"
        ]
        let deepLink = DeepLinkParser.parse(userInfo: payload)
        guard case .pendingUsers = deepLink else {
            XCTFail("Expected .pendingUsers deep link for pending approval payload")
            return
        }
    }

    func testResolveEventTypeSupportsAllSupportedKeyPaths() {
        let expected = ["INSERT", "UPDATE", "DELETE", "INSERT"]
        let resolved = WebhookFixtures.resolveEventTypePayloads.map { WebhookFixtures.resolveEventType(from: $0) }
        XCTAssertEqual(resolved, expected)
    }
}
