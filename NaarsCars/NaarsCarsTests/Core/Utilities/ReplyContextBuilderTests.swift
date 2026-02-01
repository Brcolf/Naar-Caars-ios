//
//  ReplyContextBuilderTests.swift
//  NaarsCarsTests
//
//  Tests for reply context enrichment
//

import XCTest
@testable import NaarsCars

final class ReplyContextBuilderTests: XCTestCase {
    func testApplyReplyContextsUsesParentSender() {
        let conversationId = UUID()
        let parentSender = Profile(id: UUID(), name: "Alex Chen", email: "alex@example.com")
        let parentMessage = Message(
            conversationId: conversationId,
            fromId: parentSender.id,
            text: "Original message",
            sender: parentSender
        )
        let replyMessage = Message(
            conversationId: conversationId,
            fromId: UUID(),
            text: "Reply message",
            replyToId: parentMessage.id
        )

        let enriched = ReplyContextBuilder.applyReplyContexts(
            messages: [parentMessage, replyMessage],
            profilesById: [:]
        )

        let reply = enriched.last
        XCTAssertEqual(reply?.replyToMessage?.id, parentMessage.id)
        XCTAssertEqual(reply?.replyToMessage?.senderName, "Alex Chen")
        XCTAssertEqual(reply?.replyToMessage?.text, "Original message")
    }

    func testApplyReplyContextsUsesCachedProfileWhenSenderMissing() {
        let conversationId = UUID()
        let parentSenderId = UUID()
        let cachedProfile = Profile(id: parentSenderId, name: "Jordan Lee", email: "jordan@example.com")
        let parentMessage = Message(
            conversationId: conversationId,
            fromId: parentSenderId,
            text: "Parent without sender"
        )
        let replyMessage = Message(
            conversationId: conversationId,
            fromId: UUID(),
            text: "Reply message",
            replyToId: parentMessage.id
        )

        let enriched = ReplyContextBuilder.applyReplyContexts(
            messages: [parentMessage, replyMessage],
            profilesById: [parentSenderId: cachedProfile]
        )

        let reply = enriched.last
        XCTAssertEqual(reply?.replyToMessage?.senderName, "Jordan Lee")
    }

    func testApplyReplyContextsDoesNotOverrideExistingContext() {
        let conversationId = UUID()
        let parentSender = Profile(id: UUID(), name: "Priya Patel", email: "priya@example.com")
        let parentMessage = Message(
            conversationId: conversationId,
            fromId: parentSender.id,
            text: "Original message",
            sender: parentSender
        )
        let existingContext = ReplyContext(
            id: parentMessage.id,
            text: "Pinned context",
            senderName: "Custom Name",
            senderId: parentSender.id
        )
        var replyMessage = Message(
            conversationId: conversationId,
            fromId: UUID(),
            text: "Reply message",
            replyToId: parentMessage.id
        )
        replyMessage.replyToMessage = existingContext

        let enriched = ReplyContextBuilder.applyReplyContexts(
            messages: [parentMessage, replyMessage],
            profilesById: [:]
        )

        let reply = enriched.last
        XCTAssertEqual(reply?.replyToMessage, existingContext)
    }
}

