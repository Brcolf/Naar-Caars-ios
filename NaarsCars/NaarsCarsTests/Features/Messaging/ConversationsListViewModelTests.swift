//
//  ConversationsListViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for ConversationsListViewModel helpers
//

import AuthenticationServices
import SwiftData
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

/// Answers the list's page fetches from `pages` (an empty page for any other offset) and records
/// every offset asked for; nothing else is used by these tests.
private final class StubPagingConversationService: ConversationServiceProtocol {
    var pages: [Int: [ConversationWithDetails]] = [:]
    private(set) var requestedOffsets: [Int] = []

    func fetchConversations(userId: UUID, limit: Int, offset: Int) async throws -> [ConversationWithDetails] {
        requestedOffsets.append(offset)
        return pages[offset] ?? []
    }

    func fetchConversationWithDetails(conversationId: UUID, userId: UUID) async throws -> ConversationWithDetails? { nil }
    func getHiddenConversationIds(for userId: UUID) -> Set<UUID> { [] }
    func unhideConversationForUser(conversationId: UUID, userId: UUID) {}
    func getOrCreateDirectConversation(userId: UUID, otherUserId: UUID) async throws -> Conversation {
        throw AppError.processingError("unused")
    }
    func createConversationWithUsers(userIds: [UUID], createdBy: UUID, title: String?) async throws -> Conversation {
        throw AppError.processingError("unused")
    }
    func findConversation(forParticipants userIds: [UUID]) async -> UUID? { nil }
    func updateConversationTitle(conversationId: UUID, title: String?, userId: UUID) async throws {}
    func uploadGroupImage(imageData: Data, conversationId: UUID) async throws -> String { "" }
    func updateGroupImage(conversationId: UUID, imageUrl: String?, userId: UUID) async throws {}
}

@MainActor
final class ConversationsListViewModelTests: XCTestCase {
    /// A private coordinator per test (never `shared`); `reset()` clears the `refresh.lastSync.*` keys it wrote.
    private var coordinator: RefreshCoordinator?
    /// The app's repository context, put back in tearDown after a test pointed the shared
    /// repository at an in-memory store (`storeOnePage`).
    private var originalRepositoryContext: ModelContext?
    private var repositoryContainer: ModelContainer?

    override func tearDown() async throws {
        await coordinator?.reset()
        coordinator = nil
        if let originalRepositoryContext {
            MessagingRepository.shared.setup(modelContext: originalRepositoryContext)
        }
        originalRepositoryContext = nil
        repositoryContainer = nil
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
    /// top of the coordinator's staleness-gated tabAppear sync. It now asks with unlessCurrent, so a
    /// current full sync is not repeated; the explicit reloads (pull-to-refresh, Retry, the reload
    /// after composing) still force.
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

        // Past the list's own minimum interval, so only the coordinator's unlessCurrent keeps the
        // appearance off the network (the domain is fresh, which a forced call ignores).
        try await Task.sleep(for: .seconds(Constants.Timing.messagingListRemoteSyncMinInterval + 0.2))

        await viewModel.loadConversations(forceRemote: false)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(syncs, [.conversations], "an appearance must not force another conversations sync")

        // Control: the default, used by Retry and the reload after composing, still forces one
        // (after the minimum interval, which the appearance's coordinator call restarted).
        try await Task.sleep(for: .seconds(Constants.Timing.messagingListRemoteSyncMinInterval + 0.2))
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

    // MARK: - Appearance after a change no push reports (review of the performance pass)

    /// A Back gets no tabAppear. When no full sync covers the appearance (older than the staleness
    /// window, so a muted or push-off thread may have changed), the appearance syncs once.
    func testAppearanceSyncsWhenTheLastFullSyncIsOutsideTheWindow() async throws {
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

        // An earlier load this session (so this is not the first-load path), then the sync ages
        // past the staleness window.
        await viewModel.refreshConversations()
        XCTAssertEqual(syncs, [.conversations])
        coordinator.markSyncedForTesting(.conversations, at: Date().addingTimeInterval(-(coordinator.stalenessWindow + 1)))
        try await Task.sleep(for: .seconds(Constants.Timing.messagingListRemoteSyncMinInterval + 0.2))

        await viewModel.loadConversations(forceRemote: false)
        for _ in 0..<200 where syncs.count < 2 { await Task.yield() }
        XCTAssertEqual(syncs, [.conversations, .conversations], "an appearance with no current full sync syncs")
    }

    /// A conversation created, renamed, re-imaged, joined or left on this device posts
    /// `.conversationUpdated` without a message; no push reports it, and the last full sync can still
    /// be current. The next appearance forces one sync. A realtime message post (with a message) does not.
    func testAppearanceAfterALocalConversationChangeForcesOneSync() async throws {
        var syncs: [RefreshDomain] = []
        let coordinator = RefreshCoordinator()
        coordinator.fullSyncOverrideForTesting = { domain in
            syncs.append(domain)
            return .empty
        }
        self.coordinator = coordinator
        let userId = UUID()
        let viewModel = ConversationsListViewModel(
            authService: StubListAuthService(currentUserId: userId),
            refreshCoordinator: coordinator
        )
        viewModel.start()
        defer { viewModel.stop() }
        let interval = Constants.Timing.messagingListRemoteSyncMinInterval + 0.2

        await viewModel.refreshConversations()
        XCTAssertEqual(syncs, [.conversations])

        // A realtime message event: the repository publisher delivers it; no sync.
        let conversationId = UUID()
        NotificationCenter.default.post(
            name: .conversationUpdated,
            object: conversationId,
            userInfo: ["message": Message(id: UUID(), conversationId: conversationId, fromId: userId, text: "x"), "event": "insert"]
        )
        try await Task.sleep(for: .seconds(interval))
        await viewModel.loadConversations(forceRemote: false)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(syncs, [.conversations], "a message post does not force a sync")

        // A conversation-level change made on this device.
        NotificationCenter.default.post(name: .conversationUpdated, object: conversationId)
        try await Task.sleep(for: .seconds(interval))
        await viewModel.loadConversations(forceRemote: false)
        for _ in 0..<200 where syncs.count < 2 { await Task.yield() }
        XCTAssertEqual(syncs, [.conversations, .conversations], "the appearance after a local change syncs")

        // Once: the next appearance is covered by that sync again.
        try await Task.sleep(for: .seconds(interval))
        await viewModel.loadConversations(forceRemote: false)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(syncs, [.conversations, .conversations], "the flag forces one sync, not every appearance")
    }

    // MARK: - Paging (device check 2026-10-21, finding 1)

    /// Points the shared repository at an in-memory store holding one page of `userId`'s
    /// conversations, newest first, with no other member (so no profile is fetched).
    private func storeOnePage(for userId: UUID) throws {
        originalRepositoryContext = MessagingRepository.shared.modelContextForWorker
        let container = try ModelContainer(
            for: SDConversation.self, SDMessage.self, SDDeletedMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        repositoryContainer = container
        let context = container.mainContext
        let now = Date()
        for index in 0..<Constants.PageSizes.conversations {
            context.insert(SDConversation(
                id: UUID(),
                createdBy: userId,
                updatedAt: now.addingTimeInterval(-Double(index) * 60),
                participantIds: [userId]
            ))
        }
        try context.save()
        MessagingRepository.shared.setup(modelContext: context)
    }

    /// One appearance as the device showed it: the `.task` load and its coordinator wait, then the
    /// invisible bottom anchor. The view renders the anchor while `hasMoreConversations` is true,
    /// and with one page (10 rows) or fewer it is inside the List's preload range, so it fires at once.
    private func appear(_ viewModel: ConversationsListViewModel) async {
        await viewModel.loadConversations(forceRemote: false)
        await viewModel.debugLoadTask?.value
        if viewModel.hasMoreConversations && viewModel.conversations.count <= Constants.PageSizes.conversations {
            await viewModel.loadMoreConversations()
        }
    }

    /// The list's own minimum interval between remote loads (an appearance inside it reads the store only).
    private func waitPastListMinimumInterval() async throws {
        try await Task.sleep(for: .seconds(Constants.Timing.messagingListRemoteSyncMinInterval + 0.2))
    }

    private func fullPageSync(savedToStore: Bool) -> RefreshMetrics {
        RefreshMetrics(
            recordsEvaluated: Constants.PageSizes.conversations,
            recordsMutated: savedToStore ? 1 : 0,
            recordsInserted: 0,
            recordsDeleted: 0,
            savedToStore: savedToStore,
            durationMs: 1
        )
    }

    /// One stored page and nothing beyond it: the first appearance's page fetch finds the end, and
    /// neither an appearance whose sync changed nothing nor one the coordinator skipped fetches it
    /// again. A sync that changed the stored list lets paging continue.
    func testEndOfListIsKeptAcrossAppearancesUntilASyncChangesTheList() async throws {
        let userId = UUID()
        try storeOnePage(for: userId)
        let service = StubPagingConversationService()
        let unchanged = fullPageSync(savedToStore: false)
        let changed = fullPageSync(savedToStore: true)
        var nextSync = unchanged
        var syncs = 0
        let coordinator = RefreshCoordinator()
        coordinator.fullSyncOverrideForTesting = { _ in
            syncs += 1
            return nextSync
        }
        self.coordinator = coordinator
        let viewModel = ConversationsListViewModel(
            conversationService: service,
            authService: StubListAuthService(currentUserId: userId),
            refreshCoordinator: coordinator
        )

        await appear(viewModel)
        XCTAssertEqual(syncs, 1)
        XCTAssertEqual(service.requestedOffsets, [10], "the first appearance pages once and finds the end")
        XCTAssertFalse(viewModel.hasMoreConversations)

        // An appearance whose sync changed nothing (the last one has aged out of the window) ...
        coordinator.markSyncedForTesting(.conversations, at: Date().addingTimeInterval(-(coordinator.stalenessWindow + 1)))
        try await waitPastListMinimumInterval()
        await appear(viewModel)
        // ... and one the coordinator skips (covered by that sync).
        try await waitPastListMinimumInterval()
        await appear(viewModel)
        XCTAssertEqual(syncs, 2)
        XCTAssertEqual(service.requestedOffsets, [10], "two more appearances: the end of the list is not fetched again")

        // A sync that changed the stored list resets the flag, and the anchor pages once more.
        nextSync = changed
        coordinator.markSyncedForTesting(.conversations, at: Date().addingTimeInterval(-(coordinator.stalenessWindow + 1)))
        try await waitPastListMinimumInterval()
        await viewModel.loadConversations(forceRemote: false)
        await viewModel.debugLoadTask?.value
        XCTAssertEqual(syncs, 3)
        XCTAssertTrue(viewModel.hasMoreConversations, "a sync that changed the list lets paging continue")
        await viewModel.loadMoreConversations()
        XCTAssertEqual(service.requestedOffsets, [10, 10])
    }

    /// The owner's account on 2026-10-21: 42 conversations, one page stored. Each appearance put the
    /// stored page back, dropped the paged rows and reset the offset, so the anchor fetched offset 10
    /// again on every visit (17 page fetches in ten minutes). The paged rows now stay, and no page
    /// is fetched twice until a reload.
    func testPagedRowsSurviveAppearancesAndNoPageIsFetchedTwice() async throws {
        let userId = UUID()
        try storeOnePage(for: userId)
        let service = StubPagingConversationService()
        service.pages[10] = (0..<10).map { _ in makeConversationDetails() }
        service.pages[20] = (0..<10).map { _ in makeConversationDetails() }
        let unchanged = fullPageSync(savedToStore: false)
        var syncs = 0
        let coordinator = RefreshCoordinator()
        coordinator.fullSyncOverrideForTesting = { _ in
            syncs += 1
            return unchanged
        }
        self.coordinator = coordinator
        let viewModel = ConversationsListViewModel(
            conversationService: service,
            authService: StubListAuthService(currentUserId: userId),
            refreshCoordinator: coordinator
        )

        await appear(viewModel)
        XCTAssertEqual(service.requestedOffsets, [10])
        XCTAssertEqual(viewModel.conversations.count, 20)

        // Two more appearances: one covered by the last sync, one after a sync that changed nothing.
        try await waitPastListMinimumInterval()
        await appear(viewModel)
        coordinator.markSyncedForTesting(.conversations, at: Date().addingTimeInterval(-(coordinator.stalenessWindow + 1)))
        try await waitPastListMinimumInterval()
        await appear(viewModel)
        XCTAssertEqual(syncs, 2)
        XCTAssertEqual(viewModel.conversations.count, 20, "an appearance keeps the paged rows")
        XCTAssertEqual(service.requestedOffsets, [10], "no appearance fetches page 2 again")

        // A repository emission (the unread-count save when the tab is left) keeps them too, also
        // after profile hydration has re-applied every row it holds, paged ones included (seen on
        // the simulator: the next appearance then dropped them and fetched page 2 again).
        viewModel.applyLocalConversations(try MessagingRepository.shared.getConversations(for: userId))
        XCTAssertEqual(viewModel.conversations.count, 20)
        viewModel.applyLocalConversations(viewModel.conversations)
        viewModel.applyLocalConversations(try MessagingRepository.shared.getConversations(for: userId))
        XCTAssertEqual(viewModel.conversations.count, 20, "a hydration pass does not turn paged rows into stored ones")

        // Scrolling to the bottom asks for the next page, not page 2 again.
        await viewModel.loadMoreConversations()
        XCTAssertEqual(service.requestedOffsets, [10, 20])
        XCTAssertEqual(viewModel.conversations.count, 30)

        // Pull-to-refresh restarts paging from the stored rows.
        await viewModel.refreshConversations()
        XCTAssertEqual(viewModel.conversations.count, 10)
        XCTAssertTrue(viewModel.hasMoreConversations)
    }
}
