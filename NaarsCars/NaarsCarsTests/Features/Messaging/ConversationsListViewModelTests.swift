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

    // MARK: - Observation lifecycle (regression for the 2026-10-05 render loop)

    /// `init` must not touch the repository publishers: SwiftUI re-runs `@State` initial values
    /// on every parent body pass, and an init-time subscription wrote `conversations` during
    /// `MainTabView.body`, which re-invalidated the tab view in a loop.
    func testInitDoesNotSubscribeBeforeStart() {
        let viewModel = ConversationsListViewModel()
        XCTAssertEqual(viewModel.debugObservationSinkCount, 0, "init must not subscribe to the repository publishers")
        XCTAssertTrue(viewModel.conversations.isEmpty)
        XCTAssertTrue(viewModel.filteredConversations.isEmpty)
        viewModel.start()
        XCTAssertGreaterThan(viewModel.debugObservationSinkCount, 0, "start() installs the publisher subscriptions")
        viewModel.stop()
    }

    func testStartIsIdempotent() {
        let viewModel = ConversationsListViewModel()
        viewModel.start()
        let afterFirst = viewModel.debugObservationSinkCount
        XCTAssertGreaterThan(afterFirst, 0)
        viewModel.start()
        XCTAssertEqual(viewModel.debugObservationSinkCount, afterFirst, "a second start() must not add duplicate subscriptions")
        viewModel.stop()
    }

    // MARK: - One row per member set (2026-10-05)

    private func makeThread(
        id: UUID = UUID(),
        title: String? = nil,
        members: [UUID],
        lastMessageText: String? = nil
    ) -> ConversationWithDetails {
        let participants = members.map { ConversationParticipant(conversationId: id, userId: $0) }
        let conversation = Conversation(id: id, title: title, createdBy: members[0], participants: participants)
        let message = lastMessageText.map { Message(id: UUID(), conversationId: id, fromId: members[0], text: $0) }
        return ConversationWithDetails(conversation: conversation, lastMessage: message)
    }

    /// Conversations whose participant insert failed (the pre-0005 RLS recursion) have no other
    /// member and no message; they rendered as "Unknown — No messages yet" rows.
    func testEmptyShellWithNoOtherMemberIsHidden() {
        let me = UUID()
        let other = UUID()
        let shell = makeThread(members: [me])
        let soloWithHistory = makeThread(members: [me], lastMessageText: "note to self")
        let newThread = makeThread(members: [me, other])

        let result = ConversationsListViewModel.removingEmptyShells(
            [shell, soloWithHistory, newThread], currentUserId: me
        )

        XCTAssertEqual(result.map(\.id), [soloWithHistory.id, newThread.id])
    }

    func testEmptyDuplicateIsHiddenWhenThreadWithSameMembersHasMessages() {
        let me = UUID()
        let alice = UUID()
        let real = makeThread(members: [me, alice], lastMessageText: "hi")
        let emptyDuplicate = makeThread(members: [alice, me])

        let result = ConversationsListViewModel.removingEmptyDuplicates(
            [emptyDuplicate, real], currentUserId: me
        )

        XCTAssertEqual(result.map(\.id), [real.id])
    }

    func testOnlyFirstOfSeveralEmptyDuplicatesIsKept() {
        let me = UUID()
        let alice = UUID()
        let first = makeThread(members: [me, alice])
        let second = makeThread(members: [me, alice])

        let result = ConversationsListViewModel.removingEmptyDuplicates([first, second], currentUserId: me)

        XCTAssertEqual(result.map(\.id), [first.id])
    }

    func testThreadsWithMessagesNamedGroupsAndOtherMemberSetsAreNeverHidden() {
        let me = UUID()
        let alice = UUID()
        let bob = UUID()
        let real = makeThread(members: [me, alice], lastMessageText: "hi")
        let secondRealThread = makeThread(members: [me, alice], lastMessageText: "older history")
        let namedEmptyGroup = makeThread(title: "Carpool", members: [me, alice])
        let differentMembers = makeThread(members: [me, alice, bob])

        let input = [real, secondRealThread, namedEmptyGroup, differentMembers]
        let result = ConversationsListViewModel.removingEmptyDuplicates(input, currentUserId: me)

        XCTAssertEqual(result.map(\.id), input.map(\.id))
    }
}
