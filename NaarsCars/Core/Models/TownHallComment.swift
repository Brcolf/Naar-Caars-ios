//
//  TownHallComment.swift
//  NaarsCars
//
//  Comment model for town hall posts with nested comment support
//

import Foundation

/// Comment on a town hall post (supports nested comments)
struct TownHallComment: Codable, Identifiable, Equatable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let parentCommentId: UUID?
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let hiddenAt: Date?
    let hiddenBy: UUID?
    let hiddenReason: String?
    
    // Joined data (not from database)
    var author: Profile?
    var replies: [TownHallComment]? // Nested comments
    var upvotes: Int = 0
    var downvotes: Int = 0
    var userVote: VoteType? // Current user's vote on this comment

    var isModerationHidden: Bool {
        hiddenAt != nil
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case parentCommentId = "parent_comment_id"
        case content
        case hiddenAt = "hidden_at"
        case hiddenBy = "hidden_by"
        case hiddenReason = "hidden_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        postId: UUID,
        userId: UUID,
        parentCommentId: UUID? = nil,
        content: String,
        hiddenAt: Date? = nil,
        hiddenBy: UUID? = nil,
        hiddenReason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        author: Profile? = nil,
        replies: [TownHallComment]? = nil,
        upvotes: Int = 0,
        downvotes: Int = 0,
        userVote: VoteType? = nil
    ) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.parentCommentId = parentCommentId
        self.content = content
        self.hiddenAt = hiddenAt
        self.hiddenBy = hiddenBy
        self.hiddenReason = hiddenReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.author = author
        self.replies = replies
        self.upvotes = upvotes
        self.downvotes = downvotes
        self.userVote = userVote
    }
}

