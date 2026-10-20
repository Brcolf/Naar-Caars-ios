//
//  TownHallService.swift
//  NaarsCars
//
//  Service for town hall operations
//

import Foundation
import Supabase

/// Service for town hall operations
/// Handles fetching, creating, and managing town hall posts
final class TownHallService {
    
    // MARK: - Singleton
    
    static let shared = TownHallService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let rateLimiter = RateLimiter.shared
    /// Joins identical page reads that overlap (see `fetchPostsPage`).
    private let pageRequests = RequestDeduplicator()
    /// The authors whose posts the page read leaves out. Read on the caller's executor after the
    /// shared fetch returns, never inside it (see `fetchPostsPage`). Internal so tests can stand in.
    var blockedAuthorIds: () -> Set<UUID> = { MessageService.shared.cachedBlockedUserIds }

    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Posts
    
    /// Fetch town hall posts with pagination
    /// - Parameters:
    ///   - limit: Maximum number of posts to fetch (default: 20)
    ///   - offset: Number of posts to skip (default: 0)
    /// - Returns: Array of posts ordered by createdAt descending
    /// - Throws: AppError if fetch fails
    func fetchPosts(limit: Int = 20, offset: Int = 0) async throws -> [TownHallPost] {
        try await fetchPostsPage(limit: limit, offset: offset).posts
    }

    /// Same fetch as `fetchPosts`, plus the number of rows the server returned before posts by
    /// blocked authors were filtered out. Paging has to advance and stop on `serverCount`: a page
    /// that lost one post to the block filter is short, but it is not the last page.
    ///
    /// A nil `communityId` means "no community filter": RLS still returns only the caller's
    /// communities. A non-nil id adds `community_id = id` to the query.
    ///
    /// On every Community visit the Town Hall sync (`TownHallSyncEngine.performFullSync`) and the
    /// feed's enrichment fetch (`TownHallFeedViewModel.refreshFromNetwork`) ask for the same first
    /// page at the same moment. An identical call made while one is in flight waits for it and
    /// gets the same result, instead of a second page read plus its four enrichment reads. The key
    /// holds the user, so a read never serves another account across a sign-out.
    ///
    /// The shared fetch runs on the deduplicator's task, off the main thread, so it returns the
    /// posts unfiltered. Posts by blocked authors are removed here, after it returns, on the
    /// caller's executor (the main actor for every caller), because `MessageService` writes
    /// `cachedBlockedUserIds` on the main actor. Each joined caller filters with the set current
    /// when its own call returns.
    func fetchPostsPage(limit: Int = 20, offset: Int = 0, communityId: UUID? = nil) async throws -> (posts: [TownHallPost], serverCount: Int) {
        let userId = AuthService.shared.currentUserId
        let key = "townHallPostsPage:\(limit):\(offset):\(communityId?.uuidString ?? "all"):\(userId?.uuidString ?? "none")"
        let page = try await pageRequests.fetch(key: key) { [self] in
            try await self.fetchPostsPageFromServer(limit: limit, offset: offset, communityId: communityId, userId: userId)
        }
        let blockedIds = blockedAuthorIds()
        guard !blockedIds.isEmpty else { return page }
        return (page.posts.filter { !blockedIds.contains($0.userId) }, page.serverCount)
    }

    /// One page with its enrichment, not filtered for blocked authors (`fetchPostsPage` does that).
    private func fetchPostsPageFromServer(limit: Int, offset: Int, communityId: UUID?, userId: UUID?) async throws -> (posts: [TownHallPost], serverCount: Int) {
        var query = supabase
            .from("town_hall_posts")
            .select()
        if let communityId {
            query = query.eq("community_id", value: communityId.uuidString)
        }
        let response = try await query
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()

        // Decode posts with custom date decoder, off the caller's actor
        var posts: [TownHallPost] = try await Self.decodePosts(response.data)
        let serverCount = posts.count

        // Enrich with author profiles, vote counts, comment counts, and review data.
        // The lookups only depend on this page of posts, so they run concurrently.
        posts = await enrichPosts(posts, userId: userId)

        AppLogger.info("townhall", "Fetched \(posts.count) posts from network")
        return (posts, serverCount)
    }

    /// Fetch the town hall post ID associated with a review
    /// - Parameter reviewId: Review ID
    /// - Returns: Post ID if found
    func fetchPostIdForReview(reviewId: UUID) async throws -> UUID? {
        let response = try await supabase
            .from("town_hall_posts")
            .select("id")
            .eq("review_id", value: reviewId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        struct ReviewPostId: Decodable {
            let id: UUID
        }

        let posts = try JSONDecoder().decode([ReviewPostId].self, from: response.data)
        return posts.first?.id
    }
    
    /// Fetch a single town hall post by ID for targeted refresh.
    ///
    /// Zero-row tolerant: returns nil when the post is not readable (hidden, deleted, in a
    /// community the caller is not in, a forwarded push) or is by a blocked author, the same
    /// posts the page fetch leaves out. Throws only on a transport or decoding failure, so an
    /// unreadable post never puts the `.townHall` domain into backoff.
    /// The post is enriched like a page post, so a targeted upsert keeps the cached author
    /// name and comment count instead of overwriting them with nil and 0.
    func fetchPost(id: UUID) async throws -> TownHallPost? {
        let response = try await supabase
            .from("town_hall_posts")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()

        let rows = try await Self.decodePosts(response.data)
        guard let post = rows.first else { return nil }
        if MessageService.shared.cachedBlockedUserIds.contains(post.userId) {
            return nil
        }
        return await enrichPosts([post], userId: AuthService.shared.currentUserId).first
    }

    // MARK: - Create Post
    
    /// Create a new town hall post
    /// - Parameters:
    ///   - userId: The user ID creating the post
    ///   - content: Post content (max 500 characters)
    ///   - imageUrl: Optional image URL
    /// - Returns: Created post
    /// - Throws: AppError if creation fails or rate limited
    func createPost(userId: UUID, content: String, imageUrl: String? = nil, communityId: UUID? = nil) async throws -> TownHallPost {
        // Validate content length
        guard content.count <= 500 else {
            throw AppError.invalidInput("Post content must be 500 characters or less")
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidInput("Post content cannot be empty")
        }
        
        // Rate limit check: 30 seconds between posts
        let rateLimitKey = "town_hall_post_\(userId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: Constants.RateLimits.townHallPost
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait 30 seconds before posting again")
        }
        
        // Create post (title is required by database - use first line of content or truncated content)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = generateTitle(from: trimmedContent)
        
        let newPost = TownHallPost(
            userId: userId,
            content: trimmedContent,
            imageUrl: imageUrl,
            title: title,
            type: nil, // Not stored in database
            communityId: communityId
        )
        
        let response = try await supabase
            .from("town_hall_posts")
            .insert(newPost)
            .select()
            .single()
            .execute()
        
        // Decode created post
        let decoder = createDateDecoder()
        var post: TownHallPost = try decoder.decode(TownHallPost.self, from: response.data)
        
        // Enrich with author profile
        if let author = try? await ProfileService.shared.fetchProfile(userId: userId) {
            post.author = author
        }
        
        AppLogger.info("townhall", "Created post: \(post.id)")
        return post
    }
    
    /// Create a system post for reviews/completions
    /// Used by review system to auto-post to town hall
    /// - Parameters:
    ///   - userId: The user ID (reviewer or completer)
    ///   - content: Formatted post content
    ///   - type: Post type (review or completion)
    /// - Returns: Created post
    /// - Throws: AppError if creation fails
    func createSystemPost(userId: UUID, content: String, type: PostType) async throws -> TownHallPost {
        // Generate title from content for system posts
        let title = generateTitle(from: content)
        
        let newPost = TownHallPost(
            userId: userId,
            content: content,
            imageUrl: nil,
            title: title,
            type: nil // Not stored in database
        )
        
        let response = try await supabase
            .from("town_hall_posts")
            .insert(newPost)
            .select()
            .single()
            .execute()
        
        // Decode created post
        let decoder = createDateDecoder()
        var post: TownHallPost = try decoder.decode(TownHallPost.self, from: response.data)
        
        // Enrich with author profile
        if let author = try? await ProfileService.shared.fetchProfile(userId: userId) {
            post.author = author
        }
        
        AppLogger.info("townhall", "Created system post: \(post.id)")
        return post
    }
    
    /// Delete a post (only by the author)
    /// - Parameters:
    ///   - postId: Post ID to delete
    ///   - userId: User ID attempting to delete (must be author)
    /// - Throws: AppError if deletion fails or user is not author
    func deletePost(postId: UUID, userId: UUID) async throws {
        // Verify user is the author
        let response = try await supabase
            .from("town_hall_posts")
            .select("user_id")
            .eq("id", value: postId.uuidString)
            .single()
            .execute()
        
        struct PostUserId: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let postUserId = try JSONDecoder().decode(PostUserId.self, from: response.data)
        
        guard postUserId.userId == userId else {
            throw AppError.permissionDenied("You can only delete your own posts")
        }
        
        // Delete the post
        try await supabase
            .from("town_hall_posts")
            .delete()
            .eq("id", value: postId.uuidString)
            .execute()
        
        AppLogger.info("townhall", "Deleted post: \(postId)")
    }
    
    // MARK: - Vote Operations
    
    /// Vote on a post (upvote or downvote, or remove vote if same vote type)
    /// - Parameters:
    ///   - postId: Post ID to vote on
    ///   - userId: User ID voting
    ///   - voteType: Vote type (nil to remove vote)
    /// - Throws: AppError if vote operation fails
    func votePost(postId: UUID, userId: UUID, voteType: VoteType?) async throws {
        // Check if user already voted on this post
        let existingVoteResponse = try? await supabase
            .from("town_hall_votes")
            .select("id, vote_type")
            .eq("post_id", value: postId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        if let existingData = existingVoteResponse?.data {
            struct ExistingVote: Codable {
                let id: UUID
                let voteType: String
                enum CodingKeys: String, CodingKey {
                    case id
                    case voteType = "vote_type"
                }
            }
            
            let existingVote = try JSONDecoder().decode(ExistingVote.self, from: existingData)
            
            if let newVoteType = voteType {
                // Update existing vote
                if existingVote.voteType != newVoteType.rawValue {
                    // Change vote type
                    try await supabase
                        .from("town_hall_votes")
                        .update(["vote_type": AnyCodable(newVoteType.rawValue)])
                        .eq("id", value: existingVote.id.uuidString)
                        .execute()
                }
                // If same vote type, remove vote (toggle off)
                else {
                    try await supabase
                        .from("town_hall_votes")
                        .delete()
                        .eq("id", value: existingVote.id.uuidString)
                        .execute()
                }
            } else {
                // Remove existing vote
                try await supabase
                    .from("town_hall_votes")
                    .delete()
                    .eq("id", value: existingVote.id.uuidString)
                    .execute()
            }
        } else if let newVoteType = voteType {
            // Create new vote
            struct VoteInsert: Codable {
                let userId: String
                let postId: String
                let voteType: String
                
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case postId = "post_id"
                    case voteType = "vote_type"
                }
            }
            
            let voteInsert = VoteInsert(
                userId: userId.uuidString,
                postId: postId.uuidString,
                voteType: newVoteType.rawValue
            )
            
            try await supabase
                .from("town_hall_votes")
                .insert(voteInsert)
                .execute()
        }
        
        AppLogger.info("townhall", "Voted on post: \(postId), type: \(voteType?.rawValue ?? "removed")")
    }
    
    // MARK: - Helper Methods
    
    /// Generate a title from post content
    /// Uses first line or first 100 characters of content
    private func generateTitle(from content: String) -> String {
        // Try to get first line (up to newline)
        let lines = content.components(separatedBy: .newlines)
        if let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !firstLine.isEmpty {
            // Use first line, truncated to 100 characters
            return String(firstLine.prefix(100))
        }
        
        // Fallback: use first 100 characters of content
        return String(content.prefix(100))
    }
    
    /// Enrich posts with author profiles, vote counts, comment counts, user votes, and review data
    /// The four lookups depend only on the page of posts, so they are fetched concurrently
    private func enrichPosts(_ posts: [TownHallPost], userId: UUID?) async -> [TownHallPost] {
        guard !posts.isEmpty else { return posts }
        
        let postIds = posts.map { $0.id }
        let authorIds = Array(Set(posts.map { $0.userId }))
        let reviewIds = posts.compactMap { $0.reviewId }
        
        async let profileMapTask = fetchAuthorProfiles(userIds: authorIds)
        async let voteCountsTask = fetchPostVoteCounts(postIds: postIds, userId: userId)
        async let commentCountsTask = fetchCommentCounts(postIds: postIds)
        async let reviewMapTask = fetchReviews(reviewIds: reviewIds)
        
        let (profileMap, voteCounts, commentCounts, reviewMap) = await (profileMapTask, voteCountsTask, commentCountsTask, reviewMapTask)
        
        // Enrich posts
        return posts.map { post in
            var enriched = post
            enriched.author = profileMap[post.userId]
            if let counts = voteCounts[post.id] {
                enriched.upvotes = counts.upvotes
                enriched.downvotes = counts.downvotes
                enriched.userVote = counts.userVote
            }
            enriched.commentCount = commentCounts[post.id] ?? 0
            if let reviewId = post.reviewId, let review = reviewMap[reviewId] {
                enriched.review = review
            }
            return enriched
        }
    }
    
    /// Fetch author profiles for a set of user IDs in one query
    private func fetchAuthorProfiles(userIds: [UUID]) async -> [UUID: Profile] {
        guard !userIds.isEmpty else { return [:] }
        
        let response = try? await supabase
            .from("public_profiles")
            .select()
            .in("id", values: userIds.map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return [:] }
        
        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        let profiles = (try? decoder.decode([Profile].self, from: data)) ?? []
        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }
    
    /// Fetch vote counts for posts (helper method)
    private func fetchPostVoteCounts(postIds: [UUID], userId: UUID?) async -> [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] {
        guard !postIds.isEmpty else { return [:] }
        
        let response = try? await supabase
            .from("town_hall_votes")
            .select("post_id, vote_type, user_id")
            .in("post_id", values: postIds.map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return [:] }
        
        struct VoteRecord: Codable {
            let postId: UUID
            let voteType: String
            let userId: UUID
            
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case voteType = "vote_type"
                case userId = "user_id"
            }
        }
        
        let votes = (try? JSONDecoder().decode([VoteRecord].self, from: data)) ?? []
        
        var counts: [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] = [:]
        
        for postId in postIds {
            counts[postId] = (0, 0, nil)
        }
        
        for vote in votes {
            var current = counts[vote.postId] ?? (0, 0, nil)
            if vote.voteType == "upvote" {
                current.0 += 1
            } else if vote.voteType == "downvote" {
                current.1 += 1
            }
            
            // Check if this is the user's vote
            if let userId = userId, vote.userId == userId {
                current.2 = VoteType(rawValue: vote.voteType)
            }
            
            counts[vote.postId] = current
        }
        
        return counts
    }
    
    /// Fetch comment counts for posts
    private func fetchCommentCounts(postIds: [UUID]) async -> [UUID: Int] {
        guard !postIds.isEmpty else { return [:] }
        
        // Use raw SQL to count comments per post
        // PostgreSQL COUNT with GROUP BY
        let response = try? await supabase
            .from("town_hall_comments")
            .select("post_id")
            .in("post_id", values: postIds.map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return [:] }
        
        struct CommentRecord: Codable {
            let postId: UUID
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
            }
        }
        
        let comments = (try? JSONDecoder().decode([CommentRecord].self, from: data)) ?? []
        
        // Count comments per post
        var counts: [UUID: Int] = [:]
        for postId in postIds {
            counts[postId] = 0
        }
        for comment in comments {
            counts[comment.postId, default: 0] += 1
        }
        
        return counts
    }
    
    /// Fetch review data for review IDs, enriched with fulfiller names
    private func fetchReviews(reviewIds: [UUID]) async -> [UUID: Review] {
        guard !reviewIds.isEmpty else { return [:] }

        let response = try? await supabase
            .from("reviews")
            .select()
            .in("id", values: reviewIds.map { $0.uuidString })
            .execute()

        guard let data = response?.data else { return [:] }

        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        var reviews = (try? decoder.decode([Review].self, from: data)) ?? []

        // Fetch fulfiller names
        let fulfillerIds = Set(reviews.map { $0.fulfillerId })
        if !fulfillerIds.isEmpty {
            let profileResponse = try? await supabase
                .from("public_profiles")
                .select("id, name")
                .in("id", values: fulfillerIds.map { $0.uuidString })
                .execute()

            if let profileData = profileResponse?.data {
                struct ProfileName: Decodable {
                    let id: UUID
                    let name: String
                }
                let profiles = (try? JSONDecoder().decode([ProfileName].self, from: profileData)) ?? []
                let nameMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })

                reviews = reviews.map { review in
                    var enriched = review
                    enriched.fulfillerName = nameMap[review.fulfillerId]
                    return enriched
                }
            }
        }

        return Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
    }
    
    /// Create date decoder for town hall posts
    private func createDateDecoder() -> JSONDecoder {
        DateDecoderFactory.makeMessagingDecoder()
    }

    /// Decodes `town_hall_posts` rows on the concurrent pool. A nonisolated async method runs on
    /// its caller's executor (Approachable Concurrency), and the page and single-post fetches are
    /// called from `@MainActor` (`TownHallSyncEngine`, `TownHallFeedViewModel`), so an inline
    /// decode would run on the main thread.
    @concurrent
    private static func decodePosts(_ data: Data) async throws -> sending [TownHallPost] {
        try DateDecoderFactory.makeMessagingDecoder().decode([TownHallPost].self, from: data)
    }
}

extension TownHallService: TownHallPostFetching {}
