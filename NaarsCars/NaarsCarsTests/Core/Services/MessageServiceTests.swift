//
//  MessageServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for MessageService cache invalidation
//

import XCTest
@testable import NaarsCars

@MainActor
final class MessageServiceTests: XCTestCase {
    func testInvalidateConversationCachesClearsCacheForUsers() async throws {
        throw XCTSkip("Cache removed for SwiftData-first flow")
        let userId = UUID()
        let conversation = Conversation(createdBy: userId)
        let details = ConversationWithDetails(conversation: conversation)

        await CacheManager.shared.cacheConversations(userId: userId, [details])
        let cachedBefore = await CacheManager.shared.getCachedConversations(userId: userId)
        XCTAssertNotNil(cachedBefore, "Cache should be populated before invalidation")

        await MessageService.shared.invalidateConversationCaches(for: [userId])

        let cachedAfter = await CacheManager.shared.getCachedConversations(userId: userId)
        XCTAssertNil(cachedAfter, "Cache should be cleared after invalidation")
    }
}

@MainActor
final class ConversationDetailViewModelRealtimeTests: XCTestCase {
    func testRealtimeMessageInsertUpdatesViewModel() async throws {
        let conversationId = UUID()
        let viewModel = ConversationDetailViewModel(conversationId: conversationId)

        let newMessage = Message(
            id: UUID(),
            conversationId: conversationId,
            fromId: UUID(),
            text: "Hello from realtime"
        )

        NotificationCenter.default.post(
            name: NSNotification.Name("conversationUpdated"),
            object: conversationId,
            userInfo: ["message": newMessage]
        )

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline && !viewModel.messages.contains(where: { $0.id == newMessage.id }) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(
            viewModel.messages.contains(where: { $0.id == newMessage.id }),
            "Realtime notification should append message to view model without full reload"
        )
    }
}
