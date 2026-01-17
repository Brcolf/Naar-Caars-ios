//
//  Message.swift
//  NaarsCars
//
//  Message model matching database schema
//

import Foundation

/// Aggregated reactions for a message (reaction -> [user IDs])
/// Defined here to ensure it's available when Message is compiled
struct MessageReactions: Equatable, Sendable {
    var reactions: [String: [UUID]]
    
    init(reactions: [String: [UUID]] = [:]) {
        self.reactions = reactions
    }
    
    /// Get all unique user IDs who reacted
    var allUserIds: Set<UUID> {
        Set(reactions.values.flatMap { $0 })
    }
    
    /// Get reaction count for a specific reaction
    func count(for reaction: String) -> Int {
        return reactions[reaction]?.count ?? 0
    }
    
    /// Get all reactions (sorted by count, descending)
    var sortedReactions: [(reaction: String, count: Int, userIds: [UUID])] {
        return reactions.map { (reaction: $0.key, count: $0.value.count, userIds: $0.value) }
            .sorted { $0.count > $1.count }
    }
}

/// Message model
struct Message: Codable, Identifiable, Sendable {
    let id: UUID
    let conversationId: UUID
    let fromId: UUID
    let text: String
    let imageUrl: String?
    var readBy: [UUID] // UUID array from PostgreSQL
    let createdAt: Date
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// Profile of the sender
    var sender: Profile?
    
    /// Reactions on this message (not stored in database, populated separately)
    var reactions: MessageReactions?
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case fromId = "from_id"
        case text
        case imageUrl = "image_url"
        case readBy = "read_by"
        case createdAt = "created_at"
        // reactions is not in CodingKeys - it's populated separately
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        conversationId: UUID,
        fromId: UUID,
        text: String,
        imageUrl: String? = nil,
        readBy: [UUID] = [],
        createdAt: Date = Date(),
        sender: Profile? = nil,
        reactions: MessageReactions? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.fromId = fromId
        self.text = text
        self.imageUrl = imageUrl
        self.readBy = readBy
        self.createdAt = createdAt
        self.sender = sender
        self.reactions = reactions
    }
}

// MARK: - Equatable Conformance
extension Message: Equatable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
               lhs.conversationId == rhs.conversationId &&
               lhs.fromId == rhs.fromId &&
               lhs.text == rhs.text &&
               lhs.imageUrl == rhs.imageUrl &&
               lhs.readBy == rhs.readBy &&
               lhs.createdAt == rhs.createdAt &&
               lhs.sender?.id == rhs.sender?.id &&
               lhs.reactions == rhs.reactions
    }
}


