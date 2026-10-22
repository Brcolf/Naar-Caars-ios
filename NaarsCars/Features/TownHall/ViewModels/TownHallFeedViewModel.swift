//
//  TownHallFeedViewModel.swift
//  NaarsCars
//
//  ViewModel for town hall feed
//

import Foundation
import Observation
internal import Combine

/// What the feed view does for a Town Hall target from a push, a bell row or a deep link.
enum TownHallFeedAction: Equatable {
    /// The post is in the list: scroll to it and open its comments.
    case scrollAndOpenComments(UUID)
    /// The post is in the list: scroll to it and highlight it.
    case scrollAndHighlight(UUID)
    /// The post is not in the list after a refresh: open the comments sheet, which loads by id.
    case openComments(UUID)
    /// The post cannot be read (hidden, deleted, or in a community the person is not in).
    case unavailable
}

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
    /// The community the feed shows. Nil means no community filter (no community known yet).
    /// Follows `CommunityContext.communityTabId` through `activeCommunityDidChange()`.
    private(set) var activeCommunityId: UUID?
    /// The action for the last target passed to `open(_:)`; the view performs it and calls
    /// `consumeFeedAction()`.
    @Published private(set) var pendingFeedAction: TownHallFeedAction?
    /// "Now in <community>", set only when `open(_:)` switches the Community tab to the community
    /// of a push, bell row or deep link target. The title menu's switch sets nothing: the person
    /// chose it. The view shows it as an info toast, which clears it when it goes.
    @Published var communitySwitchNotice: String?

    // MARK: - Private Properties

    private let townHallService: TownHallService
    private let voteService: TownHallVoteService
    private let repository: TownHallRepository
    private let authService: any AuthServiceProtocol
    private let messageService: any MessageServiceProtocol
    /// Page and single-post reads (the enrichment fetch and infinite scroll).
    private let postFetcher: any TownHallPostFetching
    private let communityContext: CommunityContext
    /// The awaitable coordinator refresh of `.townHall` (the only coordinator call this
    /// ViewModel makes); a seam so tests can stand in for the coordinator.
    private let refreshTownHall: @MainActor (String) async -> RefreshResult?

    /// Bumped on every community change. A network result that returns after it moved belongs to
    /// the previous community and is dropped before it touches the list, errors or paging.
    private var generation = 0
    /// Post ids of the last successful enrichment page (the store reconciliation after a switch).
    private var lastEnrichmentPostIds: [UUID] = []
    /// The generation whose `refreshFromNetwork` last finished, successfully or not.
    private var finishedRefreshGeneration: Int?
    /// A target whose community is settled, waiting for its post to be resolved against `posts`.
    private var pendingNavigation: NavigationCoordinator.TownHallNavigationTarget?
    /// Bumped by every `open(_:)`; an earlier call that is still resolving its community stops.
    private var navigationRequest = 0
    /// A target that arrived before the first membership load (cold-start push tap). Its community
    /// cannot be checked against the memberships yet, so it waits for the load, or for
    /// `membershipWait` when the load does not come back (offline, a failed load).
    private var targetAwaitingMemberships: NavigationCoordinator.TownHallNavigationTarget?
    private var membershipWaitTask: Task<Void, Never>?
    private let membershipWait: TimeInterval

    private var postsCancellable: AnyCancellable?
    private var voteCancellable: AnyCancellable?
    private var blockedUsersCancellable: AnyCancellable?
    private var postVoteCache: [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] = [:]
    /// Posts with a vote request in flight; further taps on them wait for it.
    private var votesInFlight: Set<UUID> = []

    let pageSize = 20
    /// Number of server rows the list covers (counted before the blocked-author filter).
    private var currentOffset = 0
    /// The last first-page fetch came back short, so that page is the whole feed and nothing in
    /// memory can be a page scrolled in beyond it (see keepingPagedPosts).
    private var firstPageIsWholeFeed = false
    /// `loadPosts` has run its first load; later calls are re-entries of the feed.
    private var hasLoadedPosts = false
    /// When the current community's last `refreshFromNetwork` succeeded (coordinator refresh and
    /// enrichment page). A re-entry within `Constants.Timing.refreshStalenessWindow` of it skips
    /// the refresh.
    private var lastRefreshSucceededAt: Date?

    init(
        repository: TownHallRepository? = nil,
        townHallService: TownHallService? = nil,
        voteService: TownHallVoteService? = nil,
        authService: any AuthServiceProtocol = AuthService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared,
        postFetcher: (any TownHallPostFetching)? = nil,
        communityContext: CommunityContext? = nil,
        refreshTownHall: (@MainActor (String) async -> RefreshResult?)? = nil,
        membershipWait: TimeInterval = Constants.Timing.townHallTargetMembershipWait
    ) {
        self.membershipWait = membershipWait
        self.repository = repository ?? .shared
        let resolvedService = townHallService ?? .shared
        self.townHallService = resolvedService
        self.voteService = voteService ?? .shared
        self.authService = authService
        self.messageService = messageService
        self.postFetcher = postFetcher ?? resolvedService
        let resolvedContext = communityContext ?? .shared
        self.communityContext = resolvedContext
        self.refreshTownHall = refreshTownHall ?? { trigger in
            await RefreshCoordinator.shared.forceFullRefreshAndWait(.townHall, trigger: trigger)
        }
        self.activeCommunityId = resolvedContext.communityTabId
        bindPosts()
        bindVoteNotifications()
        bindBlockedUsersNotifications()
    }

    // MARK: - Public Methods

    /// Load initial posts
    func loadPosts() async {
        // `.task` calls this on every appearance (tab switch, Back from a profile). Once posts are
        // on screen, bindPosts has applied every store save made while the feed was off screen, so
        // re-reading the store only swapped the list for a copy and rendered every visible card
        // again. Only the in-memory enrichment (votes, comment counts, reviews) can be behind.
        if hasLoadedPosts && !posts.isEmpty {
            // A block made on a profile opened from a card: hide that author's posts now, as the
            // store re-read used to.
            if posts.contains(where: { messageService.isBlocked($0.userId) }) {
                posts.removeAll { messageService.isBlocked($0.userId) }
            }
            if error != nil { error = nil }
            if let last = lastRefreshSucceededAt,
               Date().timeIntervalSince(last) < Constants.Timing.refreshStalenessWindow {
                return
            }
            Task {
                await refreshFromNetwork(showLoading: false, trigger: "manualReload:townHall")
            }
            return
        }
        hasLoadedPosts = true

        error = nil
        isLoading = true
        defer { isLoading = false }

        let localPosts = (try? repository.getPosts(communityId: activeCommunityId)) ?? []
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
        let startGeneration = generation

        do {
            let page = try await postFetcher.fetchPostsPage(limit: pageSize, offset: currentOffset, communityId: activeCommunityId)
            // A page of the community the feed showed before a switch.
            guard startGeneration == generation else { return }
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
            guard startGeneration == generation else { return }
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
        let stored = (try? repository.getPosts(communityId: activeCommunityId)) ?? []
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

    /// The Community tab's community changed (the title menu, or the launch membership load
    /// resolving nil to a community). Reads one scope at a time through the coordinator; never
    /// resets the coordinator, invalidates, wipes the store or calls the engine.
    func activeCommunityDidChange() async {
        let newCommunityId = communityContext.communityTabId
        guard newCommunityId != activeCommunityId else { return }
        let wasUnfiltered = activeCommunityId == nil
        activeCommunityId = newCommunityId
        generation += 1
        lastRefreshSucceededAt = nil

        if wasUnfiltered {
            // Launch resolution nil → X: for a member of one community the rows are the same, so
            // the list stays up while the scoped refresh runs. The unfiltered list can also hold
            // another community's posts (a member of two); drop them first, by the repository's
            // own rule, or the merge and the paged-row rule would keep them in this feed.
            replacePosts(with: posts.filter { $0.communityId == newCommunityId || $0.communityId == nil })
            await refreshFromNetwork(showLoading: false, trigger: "communityResolved")
            return
        }

        let switchGeneration = generation
        posts = []
        currentOffset = 0
        hasMore = true
        firstPageIsWholeFeed = false
        error = nil
        isLoading = true
        await refreshFromNetwork(showLoading: false, trigger: "communitySwitch")
        guard switchGeneration == generation else { return }
        isLoading = false

        // The coordinator joins a sync already in flight, which may have started for the previous
        // community. The screen is right after the enrichment page; the store (the offline cache)
        // is checked here and refreshed again, at most twice, until it holds that page.
        for _ in 1...2 {
            let stored = Set(((try? repository.getPosts(communityId: activeCommunityId)) ?? []).map(\.id))
            if Set(lastEnrichmentPostIds).isSubset(of: stored) { break }
            _ = await refreshTownHall("communitySwitch:retry")
            guard switchGeneration == generation else { return }
        }
    }

    // MARK: - Navigation targets

    /// Opens a Town Hall target (push, bell row, deep link). Switches the Community tab to the
    /// post's community when it is another active membership, then publishes the scroll,
    /// highlight or open-comments action through `pendingFeedAction`. Never switches to a
    /// community the person is not an active member of: a post that cannot be read publishes
    /// `.unavailable` and the feed stays where it is. A target that arrives before the first
    /// membership load (cold-start push tap) waits for that load, at most `membershipWait`.
    func open(_ target: NavigationCoordinator.TownHallNavigationTarget) async {
        navigationRequest += 1
        let request = navigationRequest
        pendingNavigation = nil
        targetAwaitingMemberships = nil
        membershipWaitTask?.cancel()
        membershipWaitTask = nil

        // 0. Cold start: the memberships load off the launch path and are still empty, so a
        // target for another community would fail the membership check below and never switch
        // the tab. Hold it until the load returns.
        if communityContext.isAwaitingMemberships {
            holdUntilMembershipsLoad(target, request: request)
            return
        }
        await navigate(to: target, request: request)
    }

    /// Steps 1-3 of `open(_:)`.
    private func navigate(to target: NavigationCoordinator.TownHallNavigationTarget, request: Int) async {
        // 1. The post's community: from the target when it is an active membership, otherwise
        // from the post itself (an old push, a row with no community, or a community not loaded).
        let activeIds = Set(communityContext.activeMemberships.map(\.communityId))
        let communityId: UUID?
        if let given = target.communityId, activeIds.contains(given) {
            communityId = given
        } else {
            do {
                let post = try await postFetcher.fetchPost(id: target.postId)
                guard request == navigationRequest else { return }
                guard let post else {
                    pendingFeedAction = .unavailable
                    return
                }
                communityId = post.communityId
            } catch {
                guard request == navigationRequest else { return }
                guard let given = target.communityId else {
                    AppLogger.warning("townhall", "Post lookup for a navigation target failed: \(error.localizedDescription)")
                    pendingFeedAction = .unavailable
                    return
                }
                communityId = given
            }
        }

        // 2. Switch only to an active membership other than the one shown.
        if let communityId, activeIds.contains(communityId), communityId != activeCommunityId {
            communityContext.communityTabId = communityId
            if let name = communityContext.name(for: communityId) {
                communitySwitchNotice = String(format: "townhall_now_in_community".localized, name)
            }
            await activeCommunityDidChange()
            guard request == navigationRequest else { return }
        }

        // 3. Resolve against the list now, or when the current generation's refresh finishes.
        pendingNavigation = target
        // A target missing from a list this generation has already refreshed can be newer than
        // that refresh: the review flow opens the Town Hall post it has just created. Refresh the
        // way a created post does, or the 30 s re-entry skip in loadPosts leaves the feed without
        // it after its comments sheet closes. The target still resolves now, without waiting.
        if finishedRefreshGeneration == generation, !posts.contains(where: { $0.id == target.postId }) {
            lastRefreshSucceededAt = nil
            Task { await refreshAfterPostCreated() }
        }
        resolvePendingNavigation()
    }

    private func holdUntilMembershipsLoad(_ target: NavigationCoordinator.TownHallNavigationTarget, request: Int) {
        targetAwaitingMemberships = target
        observeMembershipLoad(request: request)
        let wait = membershipWait
        membershipWaitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            // Not cancelled by the release below: this task goes on to run the target's reads.
            self.membershipWaitTask = nil
            await self.releaseTargetAwaitingMemberships(request: request)
        }
    }

    /// Re-registers after each change, since `withObservationTracking` fires once.
    private func observeMembershipLoad(request: Int) {
        let context = communityContext
        withObservationTracking {
            _ = context.hasLoadedMemberships
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, request == self.navigationRequest, self.targetAwaitingMemberships != nil else { return }
                if self.communityContext.isAwaitingMemberships {
                    self.observeMembershipLoad(request: request)
                } else {
                    await self.releaseTargetAwaitingMemberships(request: request)
                }
            }
        }
    }

    private func releaseTargetAwaitingMemberships(request: Int) async {
        guard request == navigationRequest, let target = targetAwaitingMemberships else { return }
        targetAwaitingMemberships = nil
        membershipWaitTask?.cancel()
        membershipWaitTask = nil
        await navigate(to: target, request: request)
    }

    /// The view performed `pendingFeedAction`.
    func consumeFeedAction() {
        pendingFeedAction = nil
    }

    /// Publishes the action for `pendingNavigation` once it can be decided: the post is in the
    /// list, or the current generation has finished a refresh without it. Otherwise it waits;
    /// `refreshFromNetwork` calls this again at its end.
    private func resolvePendingNavigation() {
        guard let target = pendingNavigation else { return }
        if posts.contains(where: { $0.id == target.postId }) {
            switch target.mode {
            case .openComments: pendingFeedAction = .scrollAndOpenComments(target.postId)
            case .highlightPost: pendingFeedAction = .scrollAndHighlight(target.postId)
            }
            pendingNavigation = nil
        } else if finishedRefreshGeneration == generation {
            pendingFeedAction = .openComments(target.postId)
            pendingNavigation = nil
        }
    }

    // MARK: - Local-first helpers

    private func bindPosts() {
        postsCancellable = repository.getPostsPublisher(communityId: { [weak self] in self?.activeCommunityId })
            .sink { [weak self] emission in
                guard let self else { return }
                // A full sync of another community than the one shown (one that started before a
                // switch and was joined) would otherwise empty the list through keepingPagedPosts.
                if let syncedScope = emission.syncedScope, syncedScope.communityId != self.activeCommunityId {
                    return
                }
                let stored = emission.posts
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

    /// A block or unblock made anywhere (a profile, Settings, a comment) changes which authors the
    /// feed may show. Hide newly blocked authors now, and drop the freshness mark so the next
    /// appearance refreshes: an unblocked author's posts were left out of the last page and only a
    /// fetch brings them back. This also covers a block whose refresh returns after the feed has
    /// already reappeared (Back from the profile before `blockUser` finished).
    private func bindBlockedUsersNotifications() {
        blockedUsersCancellable = NotificationCenter.default.publisher(for: .blockedUsersDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.blockedUsersDidChange()
                }
            }
    }

    private func blockedUsersDidChange() {
        lastRefreshSucceededAt = nil
        if posts.contains(where: { messageService.isBlocked($0.userId) }) {
            posts.removeAll { messageService.isBlocked($0.userId) }
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

    /// Full reconciliation of page 1. Persistence is owned by RefreshCoordinator → TownHallSyncEngine →
    /// BackgroundSyncActor (change-detected, off the main actor); the repository publisher re-emits
    /// after that save. Votes and the review join are NOT stored in SDTownHallPost, so a read-only
    /// enrichment fetch keeps them fresh in memory — it must never write to SwiftData.
    /// - Returns: `true` when both the coordinator refresh and the enrichment fetch succeeded.
    @discardableResult
    private func refreshFromNetwork(showLoading: Bool, trigger: String) async -> Bool {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }
        let startGeneration = generation
        let communityId = activeCommunityId

        // Run the enrichment fetch concurrently with the coordinator refresh so pull-to-refresh
        // latency stays at one round trip.
        async let enrichment = postFetcher.fetchPostsPage(limit: pageSize, offset: 0, communityId: communityId)
        let result = await refreshTownHall(trigger)
        let enrichmentResult: Result<(posts: [TownHallPost], serverCount: Int), Error>
        do {
            enrichmentResult = .success(try await enrichment)
        } catch {
            enrichmentResult = .failure(error)
        }
        // Results for the community the feed showed before a switch.
        guard startGeneration == generation else { return false }
        // Whatever the outcome, this generation has now finished a refresh: a held navigation
        // target is resolved after `posts` / `error` are set below, so it never waits forever.
        defer {
            finishedRefreshGeneration = startGeneration
            resolvePendingNavigation()
        }

        var failure: Error?
        if case .failed(let error, _)? = result {
            failure = error
            AppLogger.error("townhall", "Error refreshing posts: \(error.localizedDescription)")
        }

        do {
            let page = try enrichmentResult.get()
            lastEnrichmentPostIds = page.posts.map(\.id)
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
            lastEnrichmentPostIds = []
            AppLogger.error("townhall", "Error refreshing posts: \(error.localizedDescription)")
        }

        guard let failure else {
            lastRefreshSucceededAt = Date()
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


