//
//  TownHallCommentService.swift
//  NaarsCars
//
//  Service for town hall comment operations
//

import Foundation
import Supabase

/// Service for town hall comment operations
/// Handles fetching, creating, and managing comments on posts with nested replies
@MainActor
final class TownHallCommentService {
    
    // MARK: - Singleton
    
    static let shared = TownHallCommentService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let cacheManager = CacheManager.shared
    private let rateLimiter = RateLimiter.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Comments
    
    /// Fetch all comments for a post (with nested replies)
    /// - Parameter postId: Post ID to fetch comments for
    /// - Returns: Array of top-level comments with nested replies
    /// - Throws: AppError if fetch fails
    func fetchComments(for postId: UUID) async throws -> [TownHallComment] {
        // Fetch all comments for this post
        let response = try await supabase
            .from("town_hall_comments")
            .select()
            .eq("post_id", value: postId.uuidString)
            .order("created_at", ascending: true)
            .execute()
        
        // Decode comments
        let decoder = createDateDecoder()
        var allComments: [TownHallComment] = try decoder.decode([TownHallComment].self, from: response.data)
        
        // Enrich with author profiles
        allComments = await enrichCommentsWithProfiles(allComments)
        
        // Enrich with vote counts
        if let userId = AuthService.shared.currentUserId {
            allComments = await enrichCommentsWithVotes(allComments, userId: userId)
        } else {
            allComments = await enrichCommentsWithVotes(allComments, userId: nil)
        }
        
        // Build nested structure
        let nestedComments = buildNestedStructure(allComments)
        
        print("✅ [TownHallCommentService] Fetched \(nestedComments.count) top-level comments for post: \(postId)")
        return nestedComments
    }
    
    // MARK: - Create Comment
    
    /// Create a top-level comment on a post
    /// - Parameters:
    ///   - postId: Post ID to comment on
    ///   - userId: User ID creating the comment
    ///   - content: Comment content
    /// - Returns: Created comment
    /// - Throws: AppError if creation fails or rate limited
    func createComment(postId: UUID, userId: UUID, content: String) async throws -> TownHallComment {
        // Validate content
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidInput("Comment content cannot be empty")
        }
        
        guard content.count <= 5000 else {
            throw AppError.invalidInput("Comment content must be 5000 characters or less")
        }
        
        // Rate limit check: 10 seconds between comments
        let rateLimitKey = "town_hall_comment_\(userId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: 10.0
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait 10 seconds before commenting again")
        }
        
        // Create comment
        struct CommentInsert: Codable {
            let postId: String
            let userId: String
            let content: String
            
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case userId = "user_id"
                case content
            }
        }
        
        let commentInsert = CommentInsert(
            postId: postId.uuidString,
            userId: userId.uuidString,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        let response = try await supabase
            .from("town_hall_comments")
            .insert(commentInsert)
            .select()
            .single()
            .execute()
        
        // Decode created comment
        let decoder = createDateDecoder()
        var comment: TownHallComment = try decoder.decode(TownHallComment.self, from: response.data)
        
        // Enrich with author profile
        if let author = try? await ProfileService.shared.fetchProfile(userId: userId) {
            comment.author = author
        }
        
        // Invalidate post cache to refresh comment count
        await cacheManager.invalidateTownHallPosts()
        
        print("✅ [TownHallCommentService] Created comment: \(comment.id)")
        return comment
    }
    
    /// Create a reply to a comment (nested comment)
    /// - Parameters:
    ///   - parentCommentId: Parent comment ID to reply to
    ///   - userId: User ID creating the reply
    ///   - content: Reply content
    /// - Returns: Created reply comment
    /// - Throws: AppError if creation fails or rate limited
    func createReply(parentCommentId: UUID, userId: UUID, content: String) async throws -> TownHallComment {
        // First, get the parent comment to find the postId
        let parentResponse = try await supabase
            .from("town_hall_comments")
            .select("post_id")
            .eq("id", value: parentCommentId.uuidString)
            .single()
            .execute()
        
        struct ParentComment: Codable {
            let postId: UUID
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
            }
        }
        
        let parent = try JSONDecoder().decode(ParentComment.self, from: parentResponse.data)
        
        // Validate content
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidInput("Reply content cannot be empty")
        }
        
        guard content.count <= 5000 else {
            throw AppError.invalidInput("Reply content must be 5000 characters or less")
        }
        
        // Rate limit check: 10 seconds between comments
        let rateLimitKey = "town_hall_comment_\(userId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: 10.0
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait 10 seconds before commenting again")
        }
        
        // Create reply
        struct ReplyInsert: Codable {
            let postId: String
            let userId: String
            let parentCommentId: String
            let content: String
            
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case userId = "user_id"
                case parentCommentId = "parent_comment_id"
                case content
            }
        }
        
        let replyInsert = ReplyInsert(
            postId: parent.postId.uuidString,
            userId: userId.uuidString,
            parentCommentId: parentCommentId.uuidString,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        let response = try await supabase
            .from("town_hall_comments")
            .insert(replyInsert)
            .select()
            .single()
            .execute()
        
        // Decode created reply
        let decoder = createDateDecoder()
        var reply: TownHallComment = try decoder.decode(TownHallComment.self, from: response.data)
        
        // Enrich with author profile
        if let author = try? await ProfileService.shared.fetchProfile(userId: userId) {
            reply.author = author
        }
        
        // Invalidate post cache to refresh comment count
        await cacheManager.invalidateTownHallPosts()
        
        print("✅ [TownHallCommentService] Created reply: \(reply.id)")
        return reply
    }
    
    // MARK: - Delete Comment
    
    /// Delete a comment (only by the author)
    /// - Parameters:
    ///   - commentId: Comment ID to delete
    ///   - userId: User ID attempting to delete (must be author)
    /// - Throws: AppError if deletion fails or user is not author
    func deleteComment(commentId: UUID, userId: UUID) async throws {
        // Verify user is the author
        let response = try await supabase
            .from("town_hall_comments")
            .select("user_id")
            .eq("id", value: commentId.uuidString)
            .single()
            .execute()
        
        struct CommentUserId: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let commentUserId = try JSONDecoder().decode(CommentUserId.self, from: response.data)
        
        guard commentUserId.userId == userId else {
            throw AppError.permissionDenied("You can only delete your own comments")
        }
        
        // Delete the comment (cascade will handle nested replies)
        try await supabase
            .from("town_hall_comments")
            .delete()
            .eq("id", value: commentId.uuidString)
            .execute()
        
        // Invalidate post cache to refresh comment count
        await cacheManager.invalidateTownHallPosts()
        
        print("✅ [TownHallCommentService] Deleted comment: \(commentId)")
    }
    
    // MARK: - Vote Comment
    
    /// Vote on a comment (upvote or downvote, or remove vote)
    /// - Parameters:
    ///   - commentId: Comment ID to vote on
    ///   - userId: User ID voting
    ///   - voteType: Vote type (nil to remove vote)
    /// - Throws: AppError if vote operation fails
    func voteComment(commentId: UUID, userId: UUID, voteType: VoteType?) async throws {
        // Check if user already voted on this comment
        let existingVoteResponse = try? await supabase
            .from("town_hall_votes")
            .select("id, vote_type")
            .eq("comment_id", value: commentId.uuidString)
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
                let commentId: String
                let voteType: String
                
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case commentId = "comment_id"
                    case voteType = "vote_type"
                }
            }
            
            let voteInsert = VoteInsert(
                userId: userId.uuidString,
                commentId: commentId.uuidString,
                voteType: newVoteType.rawValue
            )
            
            try await supabase
                .from("town_hall_votes")
                .insert(voteInsert)
                .execute()
        }
        
        print("✅ [TownHallCommentService] Voted on comment: \(commentId), type: \(voteType?.rawValue ?? "removed")")
    }
    
    // MARK: - Helper Methods
    
    /// Enrich comments with author profiles
    private func enrichCommentsWithProfiles(_ comments: [TownHallComment]) async -> [TownHallComment] {
        // Collect all user IDs
        var userIds = Set<UUID>()
        for comment in comments {
            userIds.insert(comment.userId)
        }
        
        guard !userIds.isEmpty else { return comments }
        
        // Fetch all profiles in one query
        let response = try? await supabase
            .from("profiles")
            .select()
            .in("id", values: Array(userIds).map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return comments }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profiles = (try? decoder.decode([Profile].self, from: data)) ?? []
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        
        // Enrich comments
        return comments.map { comment in
            var enriched = comment
            enriched.author = profileMap[comment.userId]
            return enriched
        }
    }
    
    /// Enrich comments with vote counts and user votes
    private func enrichCommentsWithVotes(_ comments: [TownHallComment], userId: UUID?) async -> [TownHallComment] {
        guard !comments.isEmpty else { return comments }
        
        let commentIds = comments.map { $0.id }
        
        // Fetch vote counts for all comments
        let voteCounts = await fetchCommentVoteCounts(commentIds: commentIds, userId: userId)
        
        // Enrich comments
        return comments.map { comment in
            var enriched = comment
            if let counts = voteCounts[comment.id] {
                enriched.upvotes = counts.upvotes
                enriched.downvotes = counts.downvotes
                enriched.userVote = counts.userVote
            }
            return enriched
        }
    }
    
    /// Fetch vote counts for comments
    private func fetchCommentVoteCounts(commentIds: [UUID], userId: UUID?) async -> [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] {
        guard !commentIds.isEmpty else { return [:] }
        
        let response = try? await supabase
            .from("town_hall_votes")
            .select("comment_id, vote_type, user_id")
            .in("comment_id", values: commentIds.map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return [:] }
        
        struct VoteRecord: Codable {
            let commentId: UUID
            let voteType: String
            let userId: UUID
            
            enum CodingKeys: String, CodingKey {
                case commentId = "comment_id"
                case voteType = "vote_type"
                case userId = "user_id"
            }
        }
        
        let votes = (try? JSONDecoder().decode([VoteRecord].self, from: data)) ?? []
        
        var counts: [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] = [:]
        
        for commentId in commentIds {
            counts[commentId] = (0, 0, nil)
        }
        
        for vote in votes {
            var current = counts[vote.commentId] ?? (0, 0, nil)
            if vote.voteType == "upvote" {
                current.0 += 1
            } else if vote.voteType == "downvote" {
                current.1 += 1
            }
            
            // Check if this is the user's vote
            if let userId = userId, vote.userId == userId {
                current.2 = VoteType(rawValue: vote.voteType)
            }
            
            counts[vote.commentId] = current
        }
        
        return counts
    }
    
    /// Build nested comment structure from flat list
    private func buildNestedStructure(_ comments: [TownHallComment]) -> [TownHallComment] {
        // Create a map of comments by ID for quick lookup
        var commentMap: [UUID: TownHallComment] = [:]
        for comment in comments {
            commentMap[comment.id] = comment
        }
        
        // Build nested structure
        var topLevelComments: [TownHallComment] = []
        var processedIds = Set<UUID>()
        
        for comment in comments {
            // Skip if already processed (as a reply)
            guard !processedIds.contains(comment.id) else { continue }
            
            if let parentId = comment.parentCommentId {
                // This is a reply, add it to parent's replies
                if var parent = commentMap[parentId] {
                    if parent.replies == nil {
                        parent.replies = []
                    }
                    parent.replies?.append(comment)
                    commentMap[parentId] = parent
                    processedIds.insert(comment.id)
                }
            } else {
                // Top-level comment
                // First, find and attach all its replies recursively
                var commentWithReplies = comment
                commentWithReplies.replies = buildReplies(for: comment.id, in: commentMap, processedIds: &processedIds)
                topLevelComments.append(commentWithReplies)
                processedIds.insert(comment.id)
            }
        }
        
        return topLevelComments
    }
    
    /// Recursively build replies for a comment
    private func buildReplies(for parentId: UUID, in commentMap: [UUID: TownHallComment], processedIds: inout Set<UUID>) -> [TownHallComment]? {
        var replies: [TownHallComment] = []
        
        for (id, comment) in commentMap {
            if comment.parentCommentId == parentId && !processedIds.contains(id) {
                var commentWithReplies = comment
                commentWithReplies.replies = buildReplies(for: id, in: commentMap, processedIds: &processedIds)
                replies.append(commentWithReplies)
                processedIds.insert(id)
            }
        }
        
        return replies.isEmpty ? nil : replies
    }
    
    /// Create date decoder for comments
    private func createDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }
}
