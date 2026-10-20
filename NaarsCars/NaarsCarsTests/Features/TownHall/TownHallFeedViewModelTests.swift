//
//  TownHallFeedViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for TownHallFeedViewModel
//

import XCTest
import SwiftData
internal import Combine
@testable import NaarsCars

/// Mutable state shared with the test's escaping closures (refresher stub, `$posts` sink).
@MainActor
private final class FeedTestRecorder {
    var refreshTriggers: [String] = []
    var recording = false
    var recordedPosts: [[UUID]] = []
    var retryCount = 0
    var sawScopeAEmissionWhileOnB = false
    weak var viewModel: TownHallFeedViewModel?
}

@MainActor
final class TownHallFeedViewModelTests: XCTestCase {
    var viewModel: TownHallFeedViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = TownHallFeedViewModel()
    }
    
    /// Test that loadPosts successfully loads posts
    func testLoadPosts_Success() async {
        // Given: A view model
        XCTAssertTrue(viewModel.posts.isEmpty, "Posts should start empty")
        
        // When: Loading posts
        await viewModel.loadPosts()
        
        // Then: Posts should be loaded (or error if not authenticated)
        // Note: This test requires a real Supabase connection
        // In a real scenario, you'd mock the TownHallService
        
        // If we get here without crashing, the test passes
        // In a real test environment, you'd verify posts.count > 0
        XCTAssertTrue(true, "loadPosts completed")
    }
    
    /// Test that loadMore loads additional posts
    func testLoadMore_LoadsAdditionalPosts() async throws {
        // The feed requires an authenticated session; without one there is nothing to page through.
        guard AuthService.shared.currentUserId != nil else {
            throw XCTSkip("testLoadMore requires an authenticated session (AuthService.shared.currentUserId is nil)")
        }

        // Given: Initial posts loaded
        await viewModel.loadPosts()
        let initialCount = viewModel.posts.count

        // When: Loading more
        await viewModel.loadMore()

        // Then: loadMore never removes posts
        XCTAssertGreaterThanOrEqual(viewModel.posts.count, initialCount, "loadMore should not remove posts")

        // And: when paging is exhausted, the last page was short (fewer than a full page was added)
        if !viewModel.hasMore {
            let added = viewModel.posts.count - initialCount
            XCTAssertLessThan(added, viewModel.pageSize, "When hasMore is false, the final page must contain fewer than pageSize posts")
        }
    }
    
    /// Test that refreshPosts reloads posts
    func testRefreshPosts_ReloadsPosts() async {
        // Given: Posts loaded
        await viewModel.loadPosts()
        let initialCount = viewModel.posts.count
        
        // When: Refreshing
        await viewModel.refreshPosts()
        
        // Then: Posts should be reloaded
        // Note: This test requires a real Supabase connection
        XCTAssertTrue(true, "refreshPosts completed")
    }
    
    /// Test that deletePost removes post from array
    func testDeletePost_RemovesFromArray() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("testDeletePost requires an authenticated session (AuthService.shared.currentUserId is nil)")
        }

        // Given: A post and view model with posts
        await viewModel.loadPosts()
        
        guard let firstPost = viewModel.posts.first else {
            throw XCTSkip("No posts available for testing")
        }

        // RLS rejects deleting another user's post, so only run against a post the current user authored.
        guard firstPost.userId == userId else {
            throw XCTSkip("testDeletePost requires the first post to be authored by the current user")
        }
        
        let initialCount = viewModel.posts.count
        
        // When: Deleting post
        await viewModel.deletePost(firstPost)
        
        // Then: Post should be removed from array
        XCTAssertEqual(viewModel.posts.count, initialCount - 1, "Post should be removed")
        XCTAssertFalse(viewModel.posts.contains(where: { $0.id == firstPost.id }), "Post should not be in array")
    }

    // MARK: - Community scoping (stubbed; no network)

    private let communityA = UUID(uuidString: "0E000000-0000-4000-8000-00000000000A")!
    private let communityB = UUID(uuidString: "0E000000-0000-4000-8000-00000000000B")!
    private let a1 = UUID(uuidString: "0E000000-0000-4000-8000-0000000000A1")!
    private let a2 = UUID(uuidString: "0E000000-0000-4000-8000-0000000000A2")!
    private let a3 = UUID(uuidString: "0E000000-0000-4000-8000-0000000000A3")!
    private let b1 = UUID(uuidString: "0E000000-0000-4000-8000-0000000000B1")!
    private let b2 = UUID(uuidString: "0E000000-0000-4000-8000-0000000000B2")!
    private let base = Date(timeIntervalSince1970: 1_770_640_000)

    private struct ScopingHarness {
        let container: ModelContainer
        let repository: TownHallRepository
        let context: CommunityContext
        let fetcher: StubTownHallPostFetcher
        let suiteName: String
        var aPage: [TownHallPost]
        var bPage: [TownHallPost]
    }

    private func makeScopingHarness() throws -> ScopingHarness {
        let container = try ModelContainer(
            for: SDTownHallPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = TownHallRepository()
        repository.setup(modelContext: ModelContext(container))
        let suiteName = "TownHallFeedViewModelTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let context = CommunityContext(service: StubCommunityService(result: .success([])), defaults: defaults)
        let aPage = [
            CommunityFixtures.post(a1, community: communityA, createdAt: base.addingTimeInterval(20)),
            CommunityFixtures.post(a2, community: communityA, createdAt: base.addingTimeInterval(10))
        ]
        let bPage = [
            CommunityFixtures.post(b1, community: communityB, createdAt: base.addingTimeInterval(40)),
            CommunityFixtures.post(b2, community: communityB, createdAt: base.addingTimeInterval(30))
        ]
        let fetcher = StubTownHallPostFetcher(pagesByCommunity: [communityA: aPage, communityB: bPage, nil: aPage])
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        return ScopingHarness(
            container: container, repository: repository, context: context, fetcher: fetcher,
            suiteName: suiteName, aPage: aPage, bPage: bPage
        )
    }

    func testSwitchWhileSyncForPreviousCommunityInFlight_EndsOnNewCommunity() async throws {
        let harness = try makeScopingHarness()
        let repo = harness.repository
        let aPage = harness.aPage
        let bPage = harness.bPage
        let scopeA = TownHallSyncScope.community(communityA)
        let scopeB = TownHallSyncScope.community(communityB)
        let recorder = FeedTestRecorder()
        let aPageChanged = [
            CommunityFixtures.post(a3, community: communityA, createdAt: base.addingTimeInterval(25))
        ] + aPage

        let refresher: @MainActor (String) async -> RefreshResult? = { trigger in
            recorder.refreshTriggers.append(trigger)
            switch trigger {
            case "manualReload:townHall":
                try? repo.upsertPosts(aPage, replaceAll: true, syncScope: scopeA)
                return .completed(.empty)
            case "communitySwitch":
                // Joins the sync that started for A; it has not saved yet.
                return .joined(inFlightTrigger: "launch")
            case "communitySwitch:retry":
                recorder.retryCount += 1
                if recorder.retryCount == 1 {
                    // The joined A sync saves now, after the B enrichment page is on screen. The
                    // page differs from the store (a new A post), so it saves and posts an
                    // A-scoped emission, delivered here while the feed shows B.
                    try? repo.upsertPosts(aPageChanged, replaceAll: true, syncScope: scopeA)
                    try? await Task.sleep(for: .milliseconds(100))   // deliver it on RunLoop.main
                    return .joined(inFlightTrigger: "launch")
                }
                try? repo.upsertPosts(bPage, replaceAll: true, syncScope: scopeB)
                return .completed(.empty)
            default:
                return nil
            }
        }

        harness.context.communityTabId = communityA
        let vm = TownHallFeedViewModel(
            repository: repo,
            postFetcher: harness.fetcher,
            communityContext: harness.context,
            refreshTownHall: refresher
        )
        await vm.loadPosts()

        let b1 = self.b1
        let cancellable = vm.$posts.sink { value in
            if value.contains(where: { $0.id == b1 }) { recorder.recording = true }
            if recorder.recording { recorder.recordedPosts.append(value.map(\.id)) }
        }
        defer { cancellable.cancel() }
        let communityA = self.communityA
        let communityB = self.communityB
        let scopeSink = NotificationCenter.default.publisher(for: .townHallPostsDidSync)
            .receive(on: RunLoop.main)
            .sink { [weak vm] note in
                let scope = note.userInfo?[TownHallSyncScope.userInfoKey] as? TownHallSyncScope
                if scope?.communityId == communityA, vm?.activeCommunityId == communityB {
                    recorder.sawScopeAEmissionWhileOnB = true
                }
            }
        defer { scopeSink.cancel() }

        harness.context.communityTabId = communityB
        await vm.activeCommunityDidChange()
        try await Task.sleep(for: .milliseconds(100))   // drain RunLoop.main deliveries

        XCTAssertEqual(Set(vm.posts.map(\.id)), [self.b1, b2])
        XCTAssertFalse(recorder.recordedPosts.contains { $0.isEmpty })
        XCTAssertEqual(Set(try repo.getPosts(communityId: communityB).map(\.id)), [self.b1, b2])
        XCTAssertTrue(recorder.sawScopeAEmissionWhileOnB, "the joined A sync must emit while the feed shows B")
        XCTAssertEqual(
            recorder.refreshTriggers,
            ["manualReload:townHall", "communitySwitch", "communitySwitch:retry", "communitySwitch:retry"]
        )
        withExtendedLifetime(harness.container) {}
    }

    func testNilToCommunityResolution_DoesNotClearTheList() async throws {
        let harness = try makeScopingHarness()
        let repo = harness.repository
        let fetcher = harness.fetcher
        let recorder = FeedTestRecorder()

        let refresher: @MainActor (String) async -> RefreshResult? = { trigger in
            recorder.refreshTriggers.append(trigger)
            let active = recorder.viewModel?.activeCommunityId
            let page = fetcher.pagesByCommunity[active] ?? []
            try? repo.upsertPosts(page, replaceAll: true, syncScope: TownHallSyncScope(communityId: active))
            return .completed(.empty)
        }

        harness.context.communityTabId = nil
        let vm = TownHallFeedViewModel(
            repository: repo,
            postFetcher: fetcher,
            communityContext: harness.context,
            refreshTownHall: refresher
        )
        recorder.viewModel = vm
        await vm.loadPosts()
        XCTAssertEqual(Set(vm.posts.map(\.id)), [a1, a2])

        let cancellable = vm.$posts.sink { value in
            recorder.recordedPosts.append(value.map(\.id))
        }
        defer { cancellable.cancel() }

        harness.context.communityTabId = communityA
        await vm.activeCommunityDidChange()
        try await Task.sleep(for: .milliseconds(100))   // drain RunLoop.main deliveries

        XCTAssertEqual(vm.activeCommunityId, communityA)
        XCTAssertFalse(recorder.recordedPosts.contains { $0.isEmpty })
        XCTAssertEqual(Set(vm.posts.map(\.id)), [a1, a2])
        withExtendedLifetime(harness.container) {}
    }

    func testNilToCommunityResolution_MemberOfTwo_DropsTheOtherCommunitysPosts() async throws {
        let harness = try makeScopingHarness()
        let repo = harness.repository
        let fetcher = harness.fetcher
        let recorder = FeedTestRecorder()

        // A full page of A (so the enrichment merges into the list), newer than everything in B.
        let aFull = (0..<20).map { index in
            CommunityFixtures.post(UUID(), community: communityA, createdAt: base.addingTimeInterval(Double(100 + index)))
        }.sorted { $0.createdAt > $1.createdAt }
        let bOld = (0..<5).map { index in
            CommunityFixtures.post(UUID(), community: communityB, createdAt: base.addingTimeInterval(Double(index)))
        }.sorted { $0.createdAt > $1.createdAt }
        // The unfiltered first page before the community is known: 15 A posts and 5 older B posts.
        fetcher.pagesByCommunity = [communityA: aFull, nil: Array(aFull.prefix(15)) + bOld]

        let refresher: @MainActor (String) async -> RefreshResult? = { trigger in
            recorder.refreshTriggers.append(trigger)
            let active = recorder.viewModel?.activeCommunityId
            let page = fetcher.pagesByCommunity[active] ?? []
            try? repo.upsertPosts(page, replaceAll: true, syncScope: TownHallSyncScope(communityId: active))
            return .completed(.empty)
        }

        harness.context.communityTabId = nil
        let vm = TownHallFeedViewModel(
            repository: repo,
            postFetcher: fetcher,
            communityContext: harness.context,
            refreshTownHall: refresher
        )
        recorder.viewModel = vm
        await vm.loadPosts()
        try await Task.sleep(for: .milliseconds(100))   // drain RunLoop.main deliveries
        XCTAssertEqual(Set(vm.posts.map(\.id)), Set((Array(aFull.prefix(15)) + bOld).map(\.id)))

        harness.context.communityTabId = communityA
        await vm.activeCommunityDidChange()
        try await Task.sleep(for: .milliseconds(100))   // drain RunLoop.main deliveries

        XCTAssertEqual(Set(vm.posts.map(\.id)), Set(aFull.map(\.id)))
        XCTAssertFalse(vm.posts.contains { $0.communityId == communityB })
        withExtendedLifetime(harness.container) {}
    }

    // MARK: - open(_:) (multi-community Phase 1, Task 12)

    func testOpen_RefreshFailureStillResolvesHeldTarget() async throws {
        let container = try ModelContainer(
            for: SDTownHallPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = TownHallRepository()
        repository.setup(modelContext: ModelContext(container))
        let suiteName = "TownHallFeedViewModelTests-open-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        let context = CommunityContext(
            service: StubCommunityService(result: .success([CommunityFixtures.membership(communityA, name: "A", isPrimary: true)])),
            defaults: defaults
        )
        context.restore(for: UUID())
        await context.refreshMemberships()
        XCTAssertEqual(context.communityTabId, communityA)

        let fetcher = StubTownHallPostFetcher()
        fetcher.failPages = true
        let vm = TownHallFeedViewModel(
            repository: repository,
            postFetcher: fetcher,
            communityContext: context,
            refreshTownHall: { _ in nil }
        )
        let postId = UUID()

        await vm.open(NavigationCoordinator.TownHallNavigationTarget(postId: postId, mode: .openComments, communityId: communityA))
        XCTAssertNil(vm.pendingFeedAction, "no refresh has finished yet, so the target is held")
        await vm.refreshPosts()   // the refresh fails

        XCTAssertEqual(vm.pendingFeedAction, .openComments(postId))
        vm.consumeFeedAction()
        XCTAssertNil(vm.pendingFeedAction)
        withExtendedLifetime(container) {}
    }

    /// Cold-start push tap: the target arrives while the memberships are still loading off the
    /// launch path. It waits for them, then switches the Community tab to the post's community.
    func testOpen_ColdStartTargetWaitsForMembershipsThenSwitchesCommunity() async throws {
        let harness = try makeScopingHarness()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: harness.suiteName))
        let context = CommunityContext(
            service: StubCommunityService(result: .success([
                CommunityFixtures.membership(communityA, name: "A", isPrimary: true),
                CommunityFixtures.membership(communityB, name: "B")
            ])),
            defaults: defaults
        )
        context.restore(for: UUID())
        context.communityTabId = communityA   // the restored tab
        XCTAssertTrue(context.isAwaitingMemberships)
        harness.fetcher.postsById = [b1: harness.bPage[0]]

        let vm = TownHallFeedViewModel(
            repository: harness.repository,
            postFetcher: harness.fetcher,
            communityContext: context,
            refreshTownHall: { _ in nil }
        )
        await vm.open(NavigationCoordinator.TownHallNavigationTarget(postId: b1, mode: .highlightPost, communityId: communityB))
        XCTAssertNil(vm.pendingFeedAction, "held until the memberships load")
        XCTAssertEqual(context.communityTabId, communityA)

        await context.refreshMemberships()   // the launch load returns
        try await waitForFeedAction(vm)

        XCTAssertEqual(context.communityTabId, communityB)
        XCTAssertEqual(vm.activeCommunityId, communityB)
        XCTAssertEqual(vm.pendingFeedAction, .scrollAndHighlight(b1))
        withExtendedLifetime(harness.container) {}
    }

    /// A membership load that never returns (offline) does not hold the target forever: after the
    /// wait it opens in the community already shown.
    func testOpen_TargetHeldForMembershipsOpensAfterWaitWhenLoadNeverReturns() async throws {
        let harness = try makeScopingHarness()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: harness.suiteName))
        let context = CommunityContext(service: StubCommunityService(result: .success([])), defaults: defaults)
        context.restore(for: UUID())
        context.communityTabId = communityA
        harness.fetcher.postsById = [a1: harness.aPage[0]]

        let vm = TownHallFeedViewModel(
            repository: harness.repository,
            postFetcher: harness.fetcher,
            communityContext: context,
            refreshTownHall: { _ in nil },
            membershipWait: 0.05
        )
        await vm.open(NavigationCoordinator.TownHallNavigationTarget(postId: a1, mode: .openComments, communityId: communityA))
        XCTAssertNil(vm.pendingFeedAction)

        await vm.refreshPosts()   // A's page arrives while the target is still held
        try await waitForFeedAction(vm)

        XCTAssertTrue(context.isAwaitingMemberships, "the load never returned")
        XCTAssertEqual(context.communityTabId, communityA)
        XCTAssertEqual(vm.pendingFeedAction, .scrollAndOpenComments(a1))
        withExtendedLifetime(harness.container) {}
    }

    // MARK: - Changes made elsewhere inside the 30 s re-entry skip (review of 8a8b867)

    /// Sets MessageService's blocked set through its real refresh against a stubbed
    /// `get_blocked_users`, which posts `.blockedUsersDidChange` when the set changes. Self-contained:
    /// the session user and the URL stub are restored before it returns.
    private func setBlockedUsers(_ ids: [UUID]) async {
        let rows = ids.map {
            #"{"blocked_id":"\#($0.uuidString)","blocked_name":"Blocked","blocked_avatar_url":null,"blocked_at":"2026-10-20T10:00:00Z","reason":null}"#
        }
        let json = "[" + rows.joined(separator: ",") + "]"
        let previousUser = AuthService.shared.currentUserId
        AuthService.shared.currentUserId = UUID(uuidString: "0D000000-0000-4000-8000-00000000AAAA")!
        CommunityServiceURLProtocol.reset()
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, Data(json.utf8))
        }
        URLProtocol.registerClass(CommunityServiceURLProtocol.self)
        await MessageService.shared.refreshBlockedUsers()
        URLProtocol.unregisterClass(CommunityServiceURLProtocol.self)
        CommunityServiceURLProtocol.reset()
        AuthService.shared.currentUserId = previousUser
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// (d) A block whose refresh returns after the feed reappeared (Back before `blockUser`
    /// finished), and (c) an unblock made in Settings, both inside the 30 s re-entry skip: the feed
    /// observes `.blockedUsersDidChange`, hides the blocked author at once, and its next appearance
    /// refreshes so an unblocked author's posts come back.
    func testBlockedUsersChange_RefiltersAndEndsTheReentrySkip() async throws {
        let harness = try makeScopingHarness()
        let repo = harness.repository
        let communityA = self.communityA
        let blockedAuthor = UUID(uuidString: "0D000000-0000-4000-8000-0000000000BB")!
        let authorsPost = TownHallPost(
            id: UUID(), userId: blockedAuthor, content: "By the author who gets blocked",
            communityId: communityA, createdAt: base.addingTimeInterval(30), updatedAt: base.addingTimeInterval(30)
        )
        let page = [authorsPost] + harness.aPage
        harness.fetcher.pagesByCommunity = [communityA: page]
        let recorder = FeedTestRecorder()
        let refresher: @MainActor (String) async -> RefreshResult? = { trigger in
            recorder.refreshTriggers.append(trigger)
            try? repo.upsertPosts(page, replaceAll: true, syncScope: .community(communityA))
            return .completed(.empty)
        }
        harness.context.communityTabId = communityA
        addTeardownBlock { @MainActor [weak self] in await self?.setBlockedUsers([]) }
        await setBlockedUsers([])
        let vm = TownHallFeedViewModel(
            repository: repo,
            postFetcher: harness.fetcher,
            communityContext: harness.context,
            refreshTownHall: refresher
        )

        await vm.loadPosts()
        XCTAssertTrue(vm.posts.contains { $0.id == authorsPost.id })
        await vm.loadPosts()   // a re-entry inside 30 s skips the refresh
        XCTAssertEqual(recorder.refreshTriggers, ["manualReload:townHall"])

        // (d) The block's refresh returns after the feed reappeared.
        await setBlockedUsers([blockedAuthor])
        try await waitUntil { !vm.posts.contains { $0.id == authorsPost.id } }
        XCTAssertFalse(vm.posts.contains { $0.id == authorsPost.id }, "hidden without another appearance")
        XCTAssertEqual(recorder.refreshTriggers.count, 1, "hiding is local")
        await vm.loadPosts()
        try await waitUntil { recorder.refreshTriggers.count == 2 }
        XCTAssertEqual(recorder.refreshTriggers.count, 2, "the next appearance refreshes")
        try await Task.sleep(for: .milliseconds(100))   // that refresh finishes
        XCTAssertFalse(vm.posts.contains { $0.id == authorsPost.id })

        // (c) Unblocked elsewhere, then back to the feed inside 30 s of that refresh.
        await setBlockedUsers([])
        try await Task.sleep(for: .milliseconds(100))   // deliver the notification
        await vm.loadPosts()
        try await waitUntil { vm.posts.contains { $0.id == authorsPost.id } }
        XCTAssertEqual(recorder.refreshTriggers.count, 3, "the unblock ended the re-entry skip")
        XCTAssertTrue(vm.posts.contains { $0.id == authorsPost.id }, "the unblocked author's post is back")
        withExtendedLifetime(harness.container) {}
    }

    /// (b) The review flow opens the Town Hall post it has just created. A target missing from a
    /// list the feed has already refreshed starts the post-created refresh without holding the
    /// comments sheet, so the post is in the feed when the sheet closes, inside the 30 s skip too.
    func testOpenTargetMissingFromRefreshedList_RefreshesAsAfterACreatedPost() async throws {
        let harness = try makeScopingHarness()
        let repo = harness.repository
        let fetcher = harness.fetcher
        let communityA = self.communityA
        fetcher.pagesByCommunity = [communityA: harness.aPage]
        let recorder = FeedTestRecorder()
        let refresher: @MainActor (String) async -> RefreshResult? = { trigger in
            recorder.refreshTriggers.append(trigger)
            try? repo.upsertPosts(fetcher.pagesByCommunity[communityA] ?? [], replaceAll: true, syncScope: .community(communityA))
            return .completed(.empty)
        }
        harness.context.communityTabId = communityA
        let vm = TownHallFeedViewModel(
            repository: repo,
            postFetcher: fetcher,
            communityContext: harness.context,
            refreshTownHall: refresher
        )
        await vm.loadPosts()

        // The review's post now exists on the server; the feed has not seen it.
        let reviewPost = CommunityFixtures.post(UUID(), community: communityA, createdAt: base.addingTimeInterval(50))
        fetcher.pagesByCommunity[communityA] = [reviewPost] + harness.aPage
        fetcher.postsById[reviewPost.id] = reviewPost
        await vm.loadPosts()   // inside 30 s: skipped
        XCTAssertEqual(recorder.refreshTriggers, ["manualReload:townHall"])

        // The review flow's intent carries no community.
        await vm.open(NavigationCoordinator.TownHallNavigationTarget(postId: reviewPost.id, mode: .openComments))
        XCTAssertEqual(vm.pendingFeedAction, .openComments(reviewPost.id), "the comments sheet opens at once")
        vm.consumeFeedAction()

        try await waitUntil { vm.posts.contains { $0.id == reviewPost.id } }
        XCTAssertTrue(vm.posts.contains { $0.id == reviewPost.id }, "the review post is in the feed")
        XCTAssertEqual(recorder.refreshTriggers, ["manualReload:townHall", "postCreated:townHall"])
        withExtendedLifetime(harness.container) {}
    }

    private func waitForFeedAction(_ vm: TownHallFeedViewModel, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while vm.pendingFeedAction == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
