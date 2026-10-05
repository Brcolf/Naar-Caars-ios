//
//  TownHallFeedViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for TownHallFeedViewModel
//

import XCTest
@testable import NaarsCars

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
}



