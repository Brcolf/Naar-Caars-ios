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
    /// A load that failed with nothing to show (the view's full-screen error).
    @Published var error: AppError?
    /// A failure while posts are on screen (vote, delete, next page, refresh). The view shows it
    /// as a banner so the loaded feed stays readable.
    @Published var bannerMessage: String?

    // MARK: - Private Properties

    private let townHallService: TownHallService
    private let voteService: TownHallVoteService
    private let repository: TownHallRepository
    private let authService: any AuthServiceProtocol
    private let messageService: any MessageServiceProtocol

    private var postsCancellable: AnyCancellable?
    private var voteCancellable: AnyCancellable?
    private var postVoteCache: [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] = [:]
    /// Posts with a vote request in flight; further taps on them wait for it.
    private var votesInFlight: Set<UUID> = []

    let pageSize = 20
    /// Number of server rows the list covers (counted before the blocked-author filter).
    private var currentOffset = 0
    /// The last first-page fetch came back short, so that page is the whole feed and nothing in
    /// memory can be a page scrolled in beyond it (see keepingPagedPosts).
    private var firstPageIsWholeFeed = false

    init(
        repository: TownHallRepository? = nil,
        townHallService: TownHallService? = nil,
        voteService: TownHallVoteService? = nil,
        authService: any AuthServiceProtocol = AuthService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared
    ) {
        self.repository = repository ?? .shared
        self.townHallService = townHallService ?? .shared
        self.voteService = voteService ?? .shared
        self.authService = authService
        self.messageService = messageService
        bindPosts()
        bindVoteNotifications()
    }

    // MARK: - Public Methods

    /// Load initial posts
    func loadPosts() async {
        error = nil
        isLoading = true
        defer { isLoading = false }

        let localPosts = (try? repository.getPosts()) ?? []
        if !localPosts.isEmpty {
            // This also runs when the feed reappears (tab switch, back from a profile). Pages the
            // user already scrolled in stay; see keepingPagedPosts.
            let merged = keepingPagedPosts(from: posts, withStored: preserveReviewEnrichment(from: posts, to: localPosts))
            posts = sortWithPinnedFirst(applyVoteCache(to: merged))
            if merged.count <= localPosts.count {
                currentOffset = localPosts.count
                hasMore = localPosts.count >= pageSize
            }
            Task {
                await refreshFromNetwork(showLoading: false, trigger: "manualReload:townHall")
            }
            return
        }

        // No local cache: block on the coordinator-owned reconciliation (skeleton stays up via isLoading).
        currentOffset = 0
        await refreshFromNetwork(showLoading: false, trigger: "manualReload:townHall")
    }

    /// Load more posts for infinite scroll
    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await townHallService.fetchPostsPage(limit: pageSize, offset: currentOffset)
            // The page loaded, so an earlier "couldn't load more" banner is out of date.
            if bannerMessage == "townhall_load_more_failed".localized { bannerMessage = nil }
            // Advance and stop on what the server sent, not on what survived the blocked-author
            // filter: a page with one blocked author is short but is not the last page.
            currentOffset += page.serverCount
            hasMore = page.serverCount >= pageSize
            // Later pages stay in memory only. Every full sync prunes the store back to the first
            // page anyway, and a store holding scattered pages would make keepingPagedPosts treat
            // the pages in between as removed.
            if !page.posts.isEmpty {
                updateVoteCache(with: page.posts)
                posts = applyVoteCache(to: mergePosts(existing: posts, new: page.posts))
            }
        } catch {
            bannerMessage = "townhall_load_more_failed".localized
            AppLogger.error("townhall", "Error loading more posts: \(error.localizedDescription)")
        }
    }

    /// Refresh posts (pull-to-refresh)
    func refreshPosts() async {
        guard await refreshFromNetwork(showLoading: false, trigger: "pullToRefresh:townHall") else { return }
        // Pull-to-refresh asks for the current feed, and it starts at the top of the list: drop
        // the pages kept in memory beyond the window the sync just stored (keepingPagedPosts) and
        // let them reload on scroll, so a post deleted or hidden further down cannot linger.
        let stored = (try? repository.getPosts()) ?? []
        guard !stored.isEmpty else { return }
        let windowEnd = stored[min(stored.count, pageSize) - 1].createdAt
        replacePosts(with: posts.filter { $0.createdAt >= windowEnd })
    }

    /// Explicit user action (the Create Post sheet reported success); same awaitable path as
    /// pull-to-refresh with its own trigger label.
    func refreshAfterPostCreated() async {
        await refreshFromNetwork(showLoading: false, trigger: "postCreated:townHall")
    }
    
    /// Explicit user action (the user added or deleted a comment in the comments sheet); same
    /// awaitable path as pull-to-refresh so the card's comment count is current.
    func refreshAfterCommentsChanged() async {
        await refreshFromNetwork(showLoading: false, trigger: "commentsChanged:townHall")
    }

    /// Explicit user action (the user blocked `authorId` from a post or comment). Their posts
    /// leave the list immediately; the refresh then prunes the stored page, because
    /// TownHallService leaves blocked authors out of every fetch.
    func handleAuthorBlocked(_ authorId: UUID) async {
        posts.removeAll { $0.userId == authorId }
        await refreshFromNetwork(showLoading: false, trigger: "authorBlocked:townHall")
    }

    /// Delete a post
    /// - Parameter post: Post to delete
    func deletePost(_ post: TownHallPost) async {
        guard let userId = authService.currentUserId else {
            bannerMessage = AppError.notAuthenticated.localizedDescription
            return
        }
        // A new attempt replaces the banner an earlier failed action left up.
        bannerMessage = nil

        do {
            try await townHallService.deletePost(postId: post.id, userId: userId)
            // Remove from local array
            posts.removeAll { $0.id == post.id }
            // The server list is one row shorter too, so the next page starts one row earlier.
            currentOffset = max(0, currentOffset - 1)
            try? repository.deletePost(id: post.id)
            HapticManager.success()
        } catch {
            bannerMessage = "townhall_delete_post_failed".localized
            AppLogger.error("townhall", "Error deleting post: \(error.localizedDescription)")
        }
    }

    /// Vote on a post
    /// - Parameters:
    ///   - postId: Post ID to vote on
    ///   - voteType: Vote type (nil to remove vote)
    func votePost(postId: UUID, voteType: VoteType?) async {
        guard let userId = authService.currentUserId else {
            bannerMessage = AppError.notAuthenticated.localizedDescription
            return
        }
        // One request per post at a time. A second tap used to be computed from the stale vote and
        // either undid the first or failed on the unique vote index.
        guard !votesInFlight.contains(postId) else { return }
        votesInFlight.insert(postId)
        defer { votesInFlight.remove(postId) }
        // A new attempt replaces the banner an earlier failed action left up.
        bannerMessage = nil

        HapticManager.selectionChanged()

        // Show the vote straight away; the server counts replace it when the write returns.
        let previous = posts.first(where: { $0.id == postId }).map {
            (upvotes: $0.upvotes, downvotes: $0.downvotes, userVote: $0.userVote)
        }
        if let previous {
            postVoteCache[postId] = VoteTally.applying(voteType, to: previous)
            posts = applyVoteCache(to: posts)
        }

        do {
            try await townHallService.votePost(postId: postId, userId: userId, voteType: voteType)
            await refreshVoteCounts(for: [postId])
        } catch {
            if let previous {
                postVoteCache[postId] = previous
                posts = applyVoteCache(to: posts)
            }
            bannerMessage = "townhall_vote_failed".localized
            AppLogger.error("townhall", "Error voting on post: \(error.localizedDescription)")
        }
    }

    // MARK: - Local-first helpers

    private func bindPosts() {
        postsCancellable = repository.getPostsPublisher()
            .sink { [weak self] stored in
                guard let self else { return }
                let enriched = self.preserveReviewEnrichment(from: self.posts, to: stored)
                let merged = self.keepingPagedPosts(from: self.posts, withStored: enriched)
                self.replacePosts(with: self.sortWithPinnedFirst(self.applyVoteCache(to: merged)))
            }
    }

    /// Replaces the list. When it got shorter, paging continues from its new end; the old offset
    /// would skip every post between the two.
    private func replacePosts(with newPosts: [TownHallPost]) {
        let countBefore = posts.count
        posts = newPosts
        if newPosts.count < countBefore {
            currentOffset = min(currentOffset, newPosts.count)
            hasMore = true
        }
    }

    /// A full sync prunes the store back to the newest page, so pages the user scrolled in beyond
    /// it exist only in memory. Keeping them stops a refresh from cutting the list back to 20
    /// posts mid-scroll. Inside the stored window the store stays authoritative, so posts deleted
    /// or hidden there still disappear; an empty store empties the list. Pull-to-refresh
    /// (`refreshPosts`) drops the kept pages.
    private func keepingPagedPosts(from existing: [TownHallPost], withStored stored: [TownHallPost]) -> [TownHallPost] {
        // `stored` is newest first; its newest page is the window the last sync covered.
        guard !stored.isEmpty else { return stored }
        // A feed that fits in one page has no pages beyond the store, so the store is the whole
        // list: a post the sync removed (deleted, or hidden by a moderator) goes even when it is
        // older than every post that is left.
        if firstPageIsWholeFeed && stored.count < pageSize {
            return stored.filter { !messageService.isBlocked($0.userId) }
        }
        let windowEnd = stored[min(stored.count, pageSize) - 1].createdAt
        let storedIds = Set(stored.map(\.id))
        let paged = existing.filter { $0.createdAt < windowEnd && !storedIds.contains($0.id) }
        return (stored + paged).filter { !messageService.isBlocked($0.userId) }
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

    /// Full reconciliation of page 1. Persistence is owned by RefreshCoordinator → TownHallSyncEngine →
    /// BackgroundSyncActor (change-detected, off the main actor); the repository publisher re-emits
    /// after that save. Votes and the review join are NOT stored in SDTownHallPost, so a read-only
    /// enrichment fetch keeps them fresh in memory — it must never write to SwiftData.
    /// - Returns: `true` when both the coordinator refresh and the enrichment fetch succeeded.
    @discardableResult
    private func refreshFromNetwork(showLoading: Bool, trigger: String) async -> Bool {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }

        // Run the enrichment fetch concurrently with the coordinator refresh so pull-to-refresh
        // latency stays at one round trip.
        async let enrichment = townHallService.fetchPostsPage(limit: pageSize, offset: 0)
        let result = await RefreshCoordinator.shared.forceFullRefreshAndWait(.townHall, trigger: trigger)
        var failure: Error?
        if case .failed(let error, _)? = result {
            failure = error
            AppLogger.error("townhall", "Error refreshing posts: \(error.localizedDescription)")
        }

        do {
            let page = try await enrichment
            updateVoteCache(with: page.posts)
            // A short first page is the whole feed: nothing older exists on the server, so a post it
            // no longer returns (deleted, or hidden by a moderator) must not survive as a "paged" row.
            let isWholeFeed = page.serverCount < pageSize
            firstPageIsWholeFeed = isWholeFeed
            posts = applyVoteCache(to: mergePosts(existing: isWholeFeed ? [] : posts, new: page.posts))
            // Counted before the blocked-author filter, like loadMore.
            currentOffset = isWholeFeed ? page.serverCount : max(currentOffset, page.serverCount)
            hasMore = !isWholeFeed
        } catch {
            failure = error
            AppLogger.error("townhall", "Error refreshing posts: \(error.localizedDescription)")
        }

        guard let failure else {
            error = nil
            // A refresh that worked supersedes an earlier "couldn't refresh" banner.
            if bannerMessage == "townhall_refresh_failed".localized { bannerMessage = nil }
            return true
        }
        // Keep whatever is loaded (cached posts when offline) and say the refresh failed; the
        // full-screen error is only for a feed with nothing to show.
        if posts.isEmpty {
            error = failure as? AppError ?? AppError.processingError(failure.localizedDescription)
        } else {
            bannerMessage = "townhall_refresh_failed".localized
        }
        return false
    }

    private func refreshVoteCounts(for postIds: [UUID]) async {
        guard !postIds.isEmpty else { return }
        let counts = await voteService.fetchPostVoteCounts(
            postIds: postIds,
            userId: authService.currentUserId
        )
        for (postId, data) in counts {
            postVoteCache[postId] = (data.upvotes, data.downvotes, data.userVote)
        }
        posts = applyVoteCache(to: posts)
    }

    private func updateVoteCache(with fetchedPosts: [TownHallPost]) {
        // A page fetched while a vote is being written may predate it; keep the optimistic counts.
        for post in fetchedPosts where !votesInFlight.contains(post.id) {
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
        // `new` comes from the service without blocked authors; rows already in memory may predate the block.
        return sortWithPinnedFirst(map.values.filter { !messageService.isBlocked($0.userId) })
    }

    /// Preserve review enrichment data when repository emits un-enriched posts.
    /// The repository doesn't store joined review data, so when it fires after
    /// a save, the emitted posts have review == nil. This merges the review data
    /// from the current (network-enriched) posts back in.
    private func preserveReviewEnrichment(from existing: [TownHallPost], to newPosts: [TownHallPost]) -> [TownHallPost] {
        let reviewMap = Dictionary(uniqueKeysWithValues: existing.compactMap { post -> (UUID, Review)? in
            guard let review = post.review else { return nil }
            return (post.id, review)
        })
        guard !reviewMap.isEmpty else { return newPosts }
        return newPosts.map { post in
            var updated = post
            if updated.review == nil, let review = reviewMap[post.id] {
                updated.review = review
            }
            return updated
        }
    }

    /// Sort posts with pinned announcements (< 7 days old) at top
    private func sortWithPinnedFirst(_ posts: [TownHallPost]) -> [TownHallPost] {
        let pinWindow = Date().addingTimeInterval(-7 * 24 * 3600)
        return posts.sorted { a, b in
            let aIsPinned = a.pinned == true && a.createdAt > pinWindow
            let bIsPinned = b.pinned == true && b.createdAt > pinWindow
            if aIsPinned != bIsPinned { return aIsPinned }
            return a.createdAt > b.createdAt
        }
    }
}

/// Vote counts as they read once a vote is applied locally. Shared by the post feed and the
/// comment thread for their optimistic update.
enum VoteTally {
    typealias Counts = (upvotes: Int, downvotes: Int, userVote: VoteType?)

    /// - Parameter newVote: The vote the user ends up with (`nil` removes their vote).
    static func applying(_ newVote: VoteType?, to current: Counts) -> Counts {
        var upvotes = current.upvotes
        var downvotes = current.downvotes
        switch current.userVote {
        case .upvote: upvotes -= 1
        case .downvote: downvotes -= 1
        case nil: break
        }
        switch newVote {
        case .upvote: upvotes += 1
        case .downvote: downvotes += 1
        case nil: break
        }
        return (max(0, upvotes), max(0, downvotes), newVote)
    }
}


