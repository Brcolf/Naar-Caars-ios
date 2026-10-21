//
//  ConversationsListViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for ConversationsListViewModel helpers
//

import AuthenticationServices
import XCTest
@testable import NaarsCars

/// Answers only `currentUserId` (the `StubProfileAuthService` pattern); every other method is unused here.
private final class StubListAuthService: AuthServiceProtocol {
    var currentUserId: UUID?
    var currentProfile: Profile? { nil }

    init(currentUserId: UUID?) { self.currentUserId = currentUserId }

    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String, name: String, car: String?) async throws {}
    func signOut() async throws {}
    func sendPasswordReset(email: String) async throws {}
    func signUpWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws {}
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult { .success }
}

@MainActor
final class ConversationsListViewModelTests: XCTestCase {
    /// A private coordinator per test (never `shared`); `reset()` clears the `refresh.lastSync.*` keys it wrote.
    private var coordinator: RefreshCoordinator?

    override func tearDown() async throws {
        await coordinator?.reset()
        coordinator = nil
        try await super.tearDown()
    }

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

    // MARK: - Appearance does not force a sync (performance pass, item 2)

    /// The list's appearance (a tab visit, Back from a thread) used to force a conversations sync on
    /// top of the coordinator's staleness-gated tabAppear sync. It now leaves the network to the
    /// coordinator; the explicit reloads (pull-to-refresh, Retry, the reload after composing) still force.
    func testAppearanceAfterASyncDoesNotForceAnotherConversationsSync() async throws {
        var syncs: [RefreshDomain] = []
        let coordinator = RefreshCoordinator()
        coordinator.fullSyncOverrideForTesting = { domain in
            syncs.append(domain)
            return .empty
        }
        self.coordinator = coordinator
        let viewModel = ConversationsListViewModel(
            authService: StubListAuthService(currentUserId: UUID()),
            refreshCoordinator: coordinator
        )

        await viewModel.refreshConversations()
        XCTAssertEqual(syncs, [.conversations])

        // Past the list's own minimum interval, so only `forceRemote: false` keeps the appearance
        // off the network (the domain is fresh, which a forced call ignores).
        try await Task.sleep(for: .seconds(Constants.Timing.messagingListRemoteSyncMinInterval + 0.2))

        await viewModel.loadConversations(forceRemote: false)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(syncs, [.conversations], "an appearance must not force another conversations sync")

        // Control: the default, used by Retry and the reload after composing, still forces one.
        await viewModel.loadConversations()
        for _ in 0..<200 where syncs.count < 2 { await Task.yield() }
        XCTAssertEqual(syncs, [.conversations, .conversations])
    }

    /// A session's first load with nothing stored still waits on the coordinator, so the skeleton
    /// stays up until that sync lands instead of showing "no conversations".
    func testFirstEmptyAppearanceWaitsOnTheCoordinator() async {
        var syncs: [RefreshDomain] = []
        var release: CheckedContinuation<Void, Never>?
        let coordinator = RefreshCoordinator()
        coordinator.fullSyncOverrideForTesting = { domain in
            syncs.append(domain)
            await withCheckedContinuation { release = $0 }
            return .empty
        }
        self.coordinator = coordinator
        // A random user id: the repository's participant filter returns no stored rows.
        let viewModel = ConversationsListViewModel(
            authService: StubListAuthService(currentUserId: UUID()),
            refreshCoordinator: coordinator
        )

        await viewModel.loadConversations(forceRemote: false)
        for _ in 0..<200 where release == nil { await Task.yield() }

        XCTAssertEqual(syncs, [.conversations], "a first load with nothing stored waits on one coordinator sync")
        XCTAssertTrue(viewModel.isLoading, "the skeleton stays up while that sync is in flight")

        release?.resume()
        for _ in 0..<200 where viewModel.isLoading { await Task.yield() }
        XCTAssertFalse(viewModel.isLoading, "the skeleton clears once the sync lands")
    }
}
