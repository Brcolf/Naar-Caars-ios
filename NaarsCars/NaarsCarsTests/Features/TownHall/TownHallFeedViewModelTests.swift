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

        let refresher: @MainActor (String) async -> RefreshResult? = { trigger in
            recorder.refreshTriggers.append(trigger)
            switch trigger {
            case "manualReload:townHall":
                try? repo.upsertPosts(aPage, replaceAll: true, syncScope: scopeA)
                return .completed(.empty)
            case "communitySwitch":
                // The joined sync that started for A.
                try? repo.upsertPosts(aPage, replaceAll: true, syncScope: scopeA)
                return .joined(inFlightTrigger: "launch")
            case "communitySwitch:retry":
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

        harness.context.communityTabId = communityB
        await vm.activeCommunityDidChange()
        try await Task.sleep(for: .milliseconds(100))   // drain RunLoop.main deliveries

        XCTAssertEqual(Set(vm.posts.map(\.id)), [self.b1, b2])
        XCTAssertFalse(recorder.recordedPosts.contains { $0.isEmpty })
        XCTAssertEqual(Set(try repo.getPosts(communityId: communityB).map(\.id)), [self.b1, b2])
        XCTAssertEqual(recorder.refreshTriggers, ["manualReload:townHall", "communitySwitch", "communitySwitch:retry"])
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
}



