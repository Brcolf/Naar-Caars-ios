//
//  ConversationsListViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for ConversationsListViewModel helpers
//

import XCTest
@testable import NaarsCars

@MainActor
final class ConversationsListViewModelTests: XCTestCase {
    private func makeConversationDetails(id: UUID = UUID()) -> ConversationWithDetails {
        ConversationWithDetails(conversation: Conversation(id: id, createdBy: UUID()))
    }

    private func makeProfile(id: UUID = UUID(), name: String = "Test User") -> Profile {
        Profile(
            id: id,
            name: name,
            email: "\(id.uuidString)@example.com"
        )
    }

    func testShouldShowLoadingWhenEmpty() {
        XCTAssertTrue(ConversationsListViewModel.shouldShowLoading(conversations: []))
    }

    func testShouldShowLoadingWhenNotEmpty() {
        let conversation = makeConversationDetails()
        XCTAssertFalse(ConversationsListViewModel.shouldShowLoading(conversations: [conversation]))
    }

    func testApplyLocalConversationsUpdatesWhenChanged() {
        let viewModel = ConversationsListViewModel()
        let first = makeConversationDetails()
        let second = makeConversationDetails()

        viewModel.applyLocalConversations([first])
        XCTAssertEqual(viewModel.conversations, [first])

        viewModel.applyLocalConversations([second])
        XCTAssertEqual(viewModel.conversations, [second])
    }

    func testApplyLocalConversationsSkipsIdentical() {
        let viewModel = ConversationsListViewModel()
        let conversation = makeConversationDetails()

        viewModel.applyLocalConversations([conversation])
        let before = viewModel.conversations

        viewModel.applyLocalConversations([conversation])
        XCTAssertEqual(viewModel.conversations, before)
    }

    func testApplyLocalConversationsPreservesParticipantsWhenIncomingEmpty() {
        let viewModel = ConversationsListViewModel()
        let conversationId = UUID()
        let profile = makeProfile()

        let hydrated = ConversationWithDetails(
            conversation: Conversation(id: conversationId, createdBy: UUID()),
            unreadCount: 2,
            otherParticipants: [profile]
        )
        viewModel.applyLocalConversations([hydrated])

        let localUpdate = ConversationWithDetails(
            conversation: hydrated.conversation,
            unreadCount: 0,
            otherParticipants: []
        )
        viewModel.applyLocalConversations([localUpdate])

        XCTAssertEqual(viewModel.conversations.first?.otherParticipants, [profile])
        XCTAssertEqual(viewModel.conversations.first?.unreadCount, 0)
    }
}
