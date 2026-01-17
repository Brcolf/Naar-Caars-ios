//
//  TownHallFeedViewModel.swift
//  NaarsCars
//
//  ViewModel for town hall feed
//

import Foundation
internal import Combine

/// ViewModel for town hall feed
@MainActor
final class TownHallFeedViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var posts: [TownHallPost] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMore: Bool = true
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let townHallService = TownHallService.shared
    private let realtimeManager = RealtimeManager.shared
    
    private let pageSize = 20
    private var currentOffset = 0
    
    init() {
        setupRealtimeSubscription()
    }
    
    deinit {
        Task.detached {
            await RealtimeManager.shared.unsubscribe(channelName: "town-hall-posts")
        }
    }
    
    // MARK: - Public Methods
    
    /// Load initial posts
    func loadPosts() async {
        isLoading = true
        error = nil
        currentOffset = 0
        defer { isLoading = false }
        
        do {
            let fetchedPosts = try await townHallService.fetchPosts(limit: pageSize, offset: 0)
            posts = fetchedPosts
            currentOffset = fetchedPosts.count
            hasMore = fetchedPosts.count >= pageSize
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading posts: \(error.localizedDescription)")
        }
    }
    
    /// Load more posts for infinite scroll
    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let fetchedPosts = try await townHallService.fetchPosts(limit: pageSize, offset: currentOffset)
            
            if fetchedPosts.isEmpty {
                hasMore = false
            } else {
                posts.append(contentsOf: fetchedPosts)
                currentOffset += fetchedPosts.count
                hasMore = fetchedPosts.count >= pageSize
            }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading more posts: \(error.localizedDescription)")
        }
    }
    
    /// Refresh posts (pull-to-refresh)
    func refreshPosts() async {
        await CacheManager.shared.invalidateTownHallPosts()
        await loadPosts()
    }
    
    /// Delete a post
    /// - Parameter post: Post to delete
    func deletePost(_ post: TownHallPost) async {
        guard let userId = AuthService.shared.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        do {
            try await townHallService.deletePost(postId: post.id, userId: userId)
            // Remove from local array
            posts.removeAll { $0.id == post.id }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error deleting post: \(error.localizedDescription)")
        }
    }
    
    /// Vote on a post
    /// - Parameters:
    ///   - postId: Post ID to vote on
    ///   - voteType: Vote type (nil to remove vote)
    func votePost(postId: UUID, voteType: VoteType?) async {
        guard let userId = AuthService.shared.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        do {
            try await townHallService.votePost(postId: postId, userId: userId, voteType: voteType)
            
            // Update local post state
            if posts.contains(where: { $0.id == postId }) {
                // Reload this post to get updated vote counts
                await refreshPosts()
            }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error voting on post: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Realtime Subscription
    
    private func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "town-hall-posts",
                table: "town_hall_posts",
                onInsert: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadPosts()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadPosts()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadPosts()
                    }
                }
            )
        }
    }
    
    private func unsubscribeFromPosts() async {
        await realtimeManager.unsubscribe(channelName: "town-hall-posts")
    }
}


