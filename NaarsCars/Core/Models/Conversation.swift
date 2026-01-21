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
    var title: String?
    var groupImageUrl: String?
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
    
    /// Whether this is a group conversation (more than 2 participants)
    var isGroup: Bool {
        (participants?.count ?? 0) > 2
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case groupImageUrl = "group_image_url"
        case createdBy = "created_by"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        // Joined fields are not in CodingKeys - they're populated separately
    }
    
    // Custom decoder to handle missing columns (title, is_archived, group_image_url)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        groupImageUrl = try container.decodeIfPresent(String.self, forKey: .groupImageUrl)
        createdBy = try container.decode(UUID.self, forKey: .createdBy)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    // Custom encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(groupImageUrl, forKey: .groupImageUrl)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        groupImageUrl: String? = nil,
        createdBy: UUID,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        participants: [ConversationParticipant]? = nil,
        lastMessage: Message? = nil,
        unreadCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.groupImageUrl = groupImageUrl
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
    
    var id: UUID { conversation.id }
    
    init(
        conversation: Conversation,
        lastMessage: Message? = nil,
        unreadCount: Int = 0,
        otherParticipants: [Profile] = []
    ) {
        self.conversation = conversation
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.otherParticipants = otherParticipants
    }
}

/// Conversation participant model
struct ConversationParticipant: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let conversationId: UUID
    let userId: UUID
    let isAdmin: Bool
    let joinedAt: Date
    var leftAt: Date?
    var lastSeen: Date?
    
    /// Whether this participant has left the conversation
    var hasLeft: Bool {
        leftAt != nil
    }
    
    /// Whether this participant is currently active (joined and not left)
    var isActive: Bool {
        leftAt == nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case userId = "user_id"
        case isAdmin = "is_admin"
        case joinedAt = "joined_at"
        case leftAt = "left_at"
        case lastSeen = "last_seen"
    }
    
    init(
        id: UUID = UUID(),
        conversationId: UUID,
        userId: UUID,
        isAdmin: Bool = false,
        joinedAt: Date = Date(),
        leftAt: Date? = nil,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.userId = userId
        self.isAdmin = isAdmin
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.lastSeen = lastSeen
    }
}


