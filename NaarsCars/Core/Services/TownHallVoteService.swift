//
//  TownHallVoteService.swift
//  NaarsCars
//
//  Service for town hall vote operations
//

import Foundation
import Supabase

/// Service for managing votes on town hall posts and comments
@MainActor
final class TownHallVoteService {
    
    // MARK: - Singleton
    
    static let shared = TownHallVoteService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let cacheManager = CacheManager.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Vote on Post
    
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
                // If same vote type, do nothing (or could remove vote - we'll remove it)
                else {
                    // Remove vote (toggle off)
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
            let newVote = TownHallVote(
                userId: userId,
                postId: postId,
                commentId: nil,
                voteType: newVoteType
            )
            
            try await supabase
                .from("town_hall_votes")
                .insert(newVote)
                .execute()
        }
        
        // Invalidate post cache to refresh vote counts
        await cacheManager.invalidateTownHallPosts()
        
        print("✅ [TownHallVoteService] Voted on post: \(postId), type: \(voteType?.rawValue ?? "removed")")
    }
    
    // MARK: - Vote on Comment
    
    /// Vote on a comment (upvote or downvote, or remove vote if same vote type)
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
            let newVote = TownHallVote(
                userId: userId,
                postId: nil,
                commentId: commentId,
                voteType: newVoteType
            )
            
            try await supabase
                .from("town_hall_votes")
                .insert(newVote)
                .execute()
        }
        
        print("✅ [TownHallVoteService] Voted on comment: \(commentId), type: \(voteType?.rawValue ?? "removed")")
    }
    
    // MARK: - Fetch Vote Counts
    
    /// Fetch vote counts for posts
    /// - Parameter postIds: Array of post IDs
    /// - Returns: Dictionary mapping post ID to (upvotes, downvotes, userVote)
    func fetchPostVoteCounts(postIds: [UUID], userId: UUID?) async -> [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] {
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
            let current = counts[vote.postId] ?? (0, 0, nil)
            if vote.voteType == "upvote" {
                counts[vote.postId] = (current.upvotes + 1, current.downvotes, current.userVote)
            } else if vote.voteType == "downvote" {
                counts[vote.postId] = (current.upvotes, current.downvotes + 1, current.userVote)
            }
            
            // Check if this is the user's vote
            if let userId = userId, vote.userId == userId {
                counts[vote.postId]?.2 = VoteType(rawValue: vote.voteType)
            }
        }
        
        return counts
    }
}

