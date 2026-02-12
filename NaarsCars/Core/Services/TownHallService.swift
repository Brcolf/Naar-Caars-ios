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
        let response = try await supabase
            .from("town_hall_posts")
            .select()
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
        
        // Decode posts with custom date decoder
        let decoder = createDateDecoder()
        var posts: [TownHallPost] = try decoder.decode([TownHallPost].self, from: response.data)
        
        // Enrich with author profiles
        posts = await enrichPostsWithProfiles(posts)
        
        // Enrich with vote counts and comment counts
        if let userId = AuthService.shared.currentUserId {
            posts = await enrichPostsWithVotesAndComments(posts, userId: userId)
        } else {
            posts = await enrichPostsWithVotesAndComments(posts, userId: nil)
        }
        
        AppLogger.info("townhall", "Fetched \(posts.count) posts from network")
        return posts
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
    
    // MARK: - Create Post
    
    /// Create a new town hall post
    /// - Parameters:
    ///   - userId: The user ID creating the post
    ///   - content: Post content (max 500 characters)
    ///   - imageUrl: Optional image URL
    /// - Returns: Created post
    /// - Throws: AppError if creation fails or rate limited
    func createPost(userId: UUID, content: String, imageUrl: String? = nil) async throws -> TownHallPost {
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
    
    /// Enrich posts with author profiles
    private func enrichPostsWithProfiles(_ posts: [TownHallPost]) async -> [TownHallPost] {
        // Collect all user IDs
        var userIds = Set<UUID>()
        for post in posts {
            userIds.insert(post.userId)
        }
        
        guard !userIds.isEmpty else { return posts }
        
        // Fetch all profiles in one query
        let response = try? await supabase
            .from("profiles")
            .select()
            .in("id", values: Array(userIds).map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return posts }
        
        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        let profiles = (try? decoder.decode([Profile].self, from: data)) ?? []
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        
        // Enrich posts
        return posts.map { post in
            var enriched = post
            enriched.author = profileMap[post.userId]
            return enriched
        }
    }
    
    /// Enrich posts with vote counts, comment counts, and user votes
    private func enrichPostsWithVotesAndComments(_ posts: [TownHallPost], userId: UUID?) async -> [TownHallPost] {
        guard !posts.isEmpty else { return posts }
        
        let postIds = posts.map { $0.id }
        
        // Fetch vote counts for all posts
        let voteCounts = await fetchPostVoteCounts(postIds: postIds, userId: userId)
        
        // Fetch comment counts for all posts
        let commentCounts = await fetchCommentCounts(postIds: postIds)
        
        // Fetch review data if any posts have reviewId
        let reviewIds = posts.compactMap { $0.reviewId }
        var reviewMap: [UUID: Review] = [:]
        if !reviewIds.isEmpty {
            reviewMap = await fetchReviews(reviewIds: reviewIds)
        }
        
        // Enrich posts
        return posts.map { post in
            var enriched = post
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
    
    /// Fetch review data for review IDs
    private func fetchReviews(reviewIds: [UUID]) async -> [UUID: Review] {
        guard !reviewIds.isEmpty else { return [:] }
        
        let response = try? await supabase
            .from("reviews")
            .select()
            .in("id", values: reviewIds.map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return [:] }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reviews = (try? decoder.decode([Review].self, from: data)) ?? []
        
        return Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
    }
    
    /// Create date decoder for town hall posts
    private func createDateDecoder() -> JSONDecoder {
        DateDecoderFactory.makeMessagingDecoder()
    }
}

