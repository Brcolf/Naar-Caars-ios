//
//  InAppToastManagerTests.swift
//  NaarsCarsTests
//
//  Tests for global in-app message toast manager
//

import XCTest
import UIKit
@testable import NaarsCars

@MainActor
final class InAppToastManagerTests: XCTestCase {
    func testToastCreatedForIncomingMessage() async {
        let notificationCenter = NotificationCenter()
        let manager = InAppToastManager(
            notificationCenter: notificationCenter,
            appStateProvider: { .active }
        )

        let currentUserId = UUID()
        AuthService.shared.currentUserId = currentUserId

        let senderId = UUID()
        let conversationId = UUID()
        let messageId = UUID()

        let sender = Profile(
            id: senderId,
            name: "Test Sender",
            email: "sender@example.com",
            car: nil,
            phoneNumber: nil,
            avatarUrl: nil,
            isAdmin: false,
            approved: true,
            invitedBy: nil,
            notifyRideUpdates: true,
            notifyMessages: true,
            notifyAnnouncements: true,
            notifyNewRequests: true,
            notifyQaActivity: true,
            notifyReviewReminders: true,
            notifyTownHall: true,
            guidelinesAccepted: true,
            guidelinesAcceptedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        var message = Message(
            id: messageId,
            conversationId: conversationId,
            fromId: senderId,
            text: "Hello",
            imageUrl: nil,
            readBy: [],
            createdAt: Date(),
            messageType: .text
        )
        message.sender = sender

        notificationCenter.post(
            name: NSNotification.Name("conversationUpdated"),
            object: conversationId,
            userInfo: [
                "message": message,
                "event": "insert"
            ]
        )

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.latestToast?.conversationId, conversationId)
        XCTAssertEqual(manager.latestToast?.messageId, messageId)
        XCTAssertEqual(manager.latestToast?.senderName, "Test Sender")
    }
}
