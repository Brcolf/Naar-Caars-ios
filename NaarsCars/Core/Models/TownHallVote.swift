//
//  TownHallVote.swift
//  NaarsCars
//
//  Vote model for town hall posts and comments
//

import Foundation

/// Vote on a town hall post or comment
struct TownHallVote: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let postId: UUID?
    let commentId: UUID?
    let voteType: VoteType
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case postId = "post_id"
        case commentId = "comment_id"
        case voteType = "vote_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        postId: UUID? = nil,
        commentId: UUID? = nil,
        voteType: VoteType,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.postId = postId
        self.commentId = commentId
        self.voteType = voteType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        // Must have exactly one of postId or commentId
        return (postId != nil) != (commentId != nil)
    }
}

