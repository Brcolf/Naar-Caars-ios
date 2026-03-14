//
//  MessageReaction.swift
//  NaarsCars
//
//  Message reaction model
//

import Foundation

/// Message reaction model
struct MessageReaction: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let messageId: UUID
    let userId: UUID
    let reaction: String // Any valid emoji reaction
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case userId = "user_id"
        case reaction
        case createdAt = "created_at"
    }
    
    init(
        id: UUID = UUID(),
        messageId: UUID,
        userId: UUID,
        reaction: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messageId = messageId
        self.userId = userId
        self.reaction = reaction
        self.createdAt = createdAt
    }
    
    /// The 6 standard iMessage tapback reactions.
    /// 😂 is stored as the emoji but rendered as custom "HA HA" artwork by the UI layer.
    static let standardTapbacks = ["❤️", "👍", "👎", "😂", "‼️", "❓"]
}

// MessageReactions is now defined in Message.swift to ensure it's available when Message is compiled
// This avoids compilation order issues

