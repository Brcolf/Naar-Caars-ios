//
//  Conversation.swift
//  NaarsCars
//
//  Conversation model matching database schema
//

import Foundation

/// Conversation model
struct Conversation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let rideId: UUID?
    let favorId: UUID?
    var title: String?
    let createdBy: UUID
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// List of participants
    var participants: [ConversationParticipant]?
    
    /// Last message in conversation
    var lastMessage: Message?
    
    /// Unread message count
    var unreadCount: Int?
    
    // MARK: - Computed Properties
    
    var isActivityBased: Bool {
        rideId != nil || favorId != nil
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case favorId = "favor_id"
        case title
        case createdBy = "created_by"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        // Joined fields are not in CodingKeys - they're populated separately
    }
    
    // Custom decoder to handle missing columns (title, is_archived)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        rideId = try container.decodeIfPresent(UUID.self, forKey: .rideId)
        favorId = try container.decodeIfPresent(UUID.self, forKey: .favorId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        createdBy = try container.decode(UUID.self, forKey: .createdBy)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    // Custom encoder - now includes title since it exists in database
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(rideId, forKey: .rideId)
        try container.encodeIfPresent(favorId, forKey: .favorId)
        try container.encodeIfPresent(title, forKey: .title) // Now encoded since column exists
        try container.encode(createdBy, forKey: .createdBy)
        // isArchived still not encoded - doesn't exist in database
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        title: String? = nil,
        createdBy: UUID,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        participants: [ConversationParticipant]? = nil,
        lastMessage: Message? = nil,
        unreadCount: Int? = nil
    ) {
        self.id = id
        self.rideId = rideId
        self.favorId = favorId
        self.title = title
        self.createdBy = createdBy
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.participants = participants
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
    }
}

/// Conversation with details for list display
struct ConversationWithDetails: Codable, Identifiable, Equatable, Sendable {
    let conversation: Conversation
    let lastMessage: Message?
    let unreadCount: Int
    let otherParticipants: [Profile]
    let requestTitle: String? // Title of the associated ride/favor if activity-based
    
    var id: UUID { conversation.id }
    
    init(
        conversation: Conversation,
        lastMessage: Message? = nil,
        unreadCount: Int = 0,
        otherParticipants: [Profile] = [],
        requestTitle: String? = nil
    ) {
        self.conversation = conversation
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.otherParticipants = otherParticipants
        self.requestTitle = requestTitle
    }
}

/// Conversation participant model
struct ConversationParticipant: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let conversationId: UUID
    let userId: UUID
    let isAdmin: Bool
    let joinedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case userId = "user_id"
        case isAdmin = "is_admin"
        case joinedAt = "joined_at"
    }
    
    init(
        id: UUID = UUID(),
        conversationId: UUID,
        userId: UUID,
        isAdmin: Bool = false,
        joinedAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.userId = userId
        self.isAdmin = isAdmin
        self.joinedAt = joinedAt
    }
}


