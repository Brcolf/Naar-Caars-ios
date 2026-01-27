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
    
    private let townHallService: TownHallService
    private let voteService: TownHallVoteService
    private let repository: TownHallRepository

    private var postsCancellable: AnyCancellable?
    private var voteCancellable: AnyCancellable?
    private var postVoteCache: [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] = [:]
    
    private let pageSize = 20
    private var currentOffset = 0
    
    init(
        repository: TownHallRepository = .shared,
        townHallService: TownHallService = .shared,
        voteService: TownHallVoteService = .shared
    ) {
        self.repository = repository
        self.townHallService = townHallService
        self.voteService = voteService
        bindPosts()
        bindVoteNotifications()
    }
    
    // MARK: - Public Methods
    
    /// Load initial posts
    func loadPosts() async {
        error = nil
        currentOffset = 0

        let localPosts = (try? repository.getPosts()) ?? []
        if !localPosts.isEmpty {
            isLoading = false
            posts = applyVoteCache(to: localPosts)
            currentOffset = localPosts.count
            hasMore = localPosts.count >= pageSize
            Task {
                await refreshFromNetwork(resetOffset: true, showLoading: false)
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetchedPosts = try await townHallService.fetchPosts(limit: pageSize, offset: 0)
            updateVoteCache(with: fetchedPosts)
            posts = applyVoteCache(to: fetchedPosts)
            currentOffset = fetchedPosts.count
            hasMore = fetchedPosts.count >= pageSize
            try repository.upsertPosts(fetchedPosts)
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
                updateVoteCache(with: fetchedPosts)
                posts = applyVoteCache(to: mergePosts(existing: posts, new: fetchedPosts))
                currentOffset += fetchedPosts.count
                hasMore = fetchedPosts.count >= pageSize
                try repository.upsertPosts(fetchedPosts)
            }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading more posts: \(error.localizedDescription)")
        }
    }
    
    /// Refresh posts (pull-to-refresh)
    func refreshPosts() async {
        await refreshFromNetwork(resetOffset: true, showLoading: false)
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
            try? repository.deletePost(id: post.id)
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
            await refreshVoteCounts(for: [postId])
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error voting on post: \(error.localizedDescription)")
        }
    }

    // MARK: - Local-first helpers

    private func bindPosts() {
        postsCancellable = repository.getPostsPublisher()
            .sink { [weak self] posts in
                guard let self else { return }
                self.posts = self.applyVoteCache(to: posts)
            }
    }

    private func bindVoteNotifications() {
        voteCancellable = NotificationCenter.default.publisher(for: .townHallPostVotesDidChange)
            .compactMap { $0.object as? UUID }
            .sink { [weak self] postId in
                Task { @MainActor in
                    await self?.refreshVoteCounts(for: [postId])
                }
            }
    }

    private func refreshFromNetwork(resetOffset: Bool, showLoading: Bool) async {
        if showLoading {
            isLoading = true
            defer { isLoading = false }
        }

        do {
            let offset = resetOffset ? 0 : currentOffset
            let fetchedPosts = try await townHallService.fetchPosts(limit: pageSize, offset: offset)

            updateVoteCache(with: fetchedPosts)
            let merged = mergePosts(existing: posts, new: fetchedPosts)
            posts = applyVoteCache(to: merged)

            if resetOffset {
                currentOffset = max(currentOffset, fetchedPosts.count)
            } else {
                currentOffset += fetchedPosts.count
            }
            hasMore = fetchedPosts.count >= pageSize
            try repository.upsertPosts(fetchedPosts)
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error refreshing posts: \(error.localizedDescription)")
        }
    }

    private func refreshVoteCounts(for postIds: [UUID]) async {
        guard !postIds.isEmpty else { return }
        let counts = await voteService.fetchPostVoteCounts(
            postIds: postIds,
            userId: AuthService.shared.currentUserId
        )
        for (postId, data) in counts {
            postVoteCache[postId] = (data.upvotes, data.downvotes, data.userVote)
        }
        posts = applyVoteCache(to: posts)
    }

    private func updateVoteCache(with fetchedPosts: [TownHallPost]) {
        for post in fetchedPosts {
            postVoteCache[post.id] = (post.upvotes, post.downvotes, post.userVote)
        }
    }

    private func applyVoteCache(to posts: [TownHallPost]) -> [TownHallPost] {
        posts.map { post in
            var updated = post
            if let cached = postVoteCache[post.id] {
                updated.upvotes = cached.upvotes
                updated.downvotes = cached.downvotes
                updated.userVote = cached.userVote
            }
            return updated
        }
    }

    private func mergePosts(existing: [TownHallPost], new: [TownHallPost]) -> [TownHallPost] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for post in new {
            map[post.id] = post
        }
        return map.values.sorted { $0.createdAt > $1.createdAt }
    }
}


