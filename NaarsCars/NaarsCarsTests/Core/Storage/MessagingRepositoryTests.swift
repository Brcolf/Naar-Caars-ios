//
//  MessagingRepositoryTests.swift
//  NaarsCarsTests
//
//  Unit tests for MessagingRepository unread count updates
//

import SwiftData
import XCTest
@testable import NaarsCars

@MainActor
final class MessagingRepositoryTests: XCTestCase {
    func testUpdatedUnreadCount_DecrementsWhenReadByAddsCurrentUser() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let previousReadBy: [UUID] = []
        let newReadBy: [UUID] = [currentUserId]

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 3,
            fromId: otherUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 2)
    }

    func testUpdatedUnreadCount_IncrementsWhenReadByRemovesCurrentUser() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let previousReadBy: [UUID] = [currentUserId]
        let newReadBy: [UUID] = []

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 1,
            fromId: otherUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 2)
    }

    func testUpdatedUnreadCount_DoesNotChangeForSenderMessages() {
        let currentUserId = UUID()
        let previousReadBy: [UUID] = []
        let newReadBy: [UUID] = [UUID()]

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 5,
            fromId: currentUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 5)
    }

    func testUpdatedUnreadCount_DoesNotGoBelowZero() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let previousReadBy: [UUID] = []
        let newReadBy: [UUID] = [currentUserId]

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 0,
            fromId: otherUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 0)
    }

    func testUpdatedUnreadCountForInsert_IncrementsForUnreadIncoming() {
        let currentUserId = UUID()
        let otherUserId = UUID()

        let result = MessagingRepository.updatedUnreadCountForInsert(
            currentCount: 1,
            fromId: otherUserId,
            currentUserId: currentUserId,
            readBy: []
        )

        XCTAssertEqual(result, 2)
    }

    func testUpdatedUnreadCountForInsert_DoesNotIncrementWhenRead() {
        let currentUserId = UUID()
        let otherUserId = UUID()

        let result = MessagingRepository.updatedUnreadCountForInsert(
            currentCount: 3,
            fromId: otherUserId,
            currentUserId: currentUserId,
            readBy: [currentUserId]
        )

        XCTAssertEqual(result, 3)
    }

    func testUpdatedUnreadCountForInsert_DoesNotIncrementForSender() {
        let currentUserId = UUID()

        let result = MessagingRepository.updatedUnreadCountForInsert(
            currentCount: 2,
            fromId: currentUserId,
            currentUserId: currentUserId,
            readBy: []
        )

        XCTAssertEqual(result, 2)
    }

    // MARK: - Last message when every stored message is unsent (device check 2026-10-21, finding 2)

    /// After a fresh sign-in the store holds only the server's newest message per thread. When that
    /// one was unsent, the thread had no last message, and the list hid it as an empty duplicate of
    /// another thread with the same members (the Alice thread `D15889AA`, 23 messages on the server).
    /// Both threads now stay; a thread with an older visible message still shows that one.
    func testThreadWhoseOnlyStoredMessageIsUnsentStaysInTheList() throws {
        let repository = MessagingRepository.shared
        let originalContext = repository.modelContextForWorker
        let container = try ModelContainer(
            for: SDConversation.self, SDMessage.self, SDDeletedMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        repository.setup(modelContext: container.mainContext)
        defer {
            if let originalContext { repository.setup(modelContext: originalContext) }
        }

        let me = UUID()
        let alice = UUID()
        let now = Date()
        let unsentOnly = UUID()
        let withHistory = UUID()
        let unsentId = UUID()
        let visibleId = UUID()
        let context = container.mainContext
        context.insert(SDConversation(id: unsentOnly, createdBy: me, updatedAt: now, participantIds: [me, alice]))
        context.insert(SDConversation(id: withHistory, createdBy: me, updatedAt: now.addingTimeInterval(-60), participantIds: [me, alice]))
        context.insert(SDMessage(id: unsentId, conversationId: unsentOnly, fromId: me, text: "", createdAt: now.addingTimeInterval(-30), deletedAt: now))
        context.insert(SDMessage(id: visibleId, conversationId: withHistory, fromId: alice, text: "hi", createdAt: now.addingTimeInterval(-120)))
        // Its newest message is unsent as well, but an older visible one is stored: that one stays the preview.
        context.insert(SDMessage(id: UUID(), conversationId: withHistory, fromId: me, text: "", createdAt: now.addingTimeInterval(-90), deletedAt: now))
        try context.save()

        let conversations = try repository.getConversations(for: me)
        let byId = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        XCTAssertEqual(byId[unsentOnly]?.lastMessage?.id, unsentId, "the unsent message is the thread's last message")
        XCTAssertEqual(byId[unsentOnly]?.lastMessage?.isUnsent, true)
        XCTAssertEqual(byId[withHistory]?.lastMessage?.id, visibleId, "a stored visible message still wins")

        let shown = ConversationsListViewModel.removingEmptyDuplicates(
            ConversationsListViewModel.removingEmptyShells(conversations, currentUserId: me),
            currentUserId: me
        )
        XCTAssertEqual(Set(shown.map(\.id)), [unsentOnly, withHistory], "both threads with the same members stay in the list")
    }
}
