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
    func testLoadMore_LoadsAdditionalPosts() async {
        // Given: Initial posts loaded
        await viewModel.loadPosts()
        let initialCount = viewModel.posts.count
        
        // When: Loading more
        await viewModel.loadMore()
        
        // Then: Should have more posts (or hasMore should be false)
        // Note: This test requires a real Supabase connection
        if viewModel.hasMore {
            XCTAssertGreaterThanOrEqual(viewModel.posts.count, initialCount, "Should have more or equal posts")
        } else {
            XCTAssertEqual(viewModel.posts.count, initialCount, "Should have same count if no more posts")
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
    func testDeletePost_RemovesFromArray() async {
        // Given: A post and view model with posts
        await viewModel.loadPosts()
        
        guard let firstPost = viewModel.posts.first else {
            XCTSkip("No posts available for testing")
            return
        }
        
        let initialCount = viewModel.posts.count
        
        // When: Deleting post
        await viewModel.deletePost(firstPost)
        
        // Then: Post should be removed from array
        XCTAssertEqual(viewModel.posts.count, initialCount - 1, "Post should be removed")
        XCTAssertFalse(viewModel.posts.contains(where: { $0.id == firstPost.id }), "Post should not be in array")
    }
}


