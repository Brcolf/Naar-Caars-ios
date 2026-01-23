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

/// Message type enumeration
enum MessageType: String, Codable, Sendable {
    case text
    case image
    case audio
    case location
    case system
    case link
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
    
    // MARK: - Message Type
    
    /// Type of message (text, image, audio, location, system)
    let messageType: MessageType?
    
    // MARK: - Reply Support
    
    /// ID of the message this is replying to
    let replyToId: UUID?
    
    // MARK: - Audio Message Fields
    
    /// URL to the audio file in storage
    let audioUrl: String?
    
    /// Duration of audio in seconds
    let audioDuration: Double?
    
    // MARK: - Location Message Fields
    
    /// Latitude coordinate for location messages
    let latitude: Double?
    
    /// Longitude coordinate for location messages
    let longitude: Double?
    
    /// Human-readable location name/address
    let locationName: String?
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// Profile of the sender
    var sender: Profile?
    
    /// Reactions on this message (not stored in database, populated separately)
    var reactions: MessageReactions?
    
    /// The message this is replying to (populated when fetched)
    var replyToMessage: ReplyContext?
    
    // MARK: - Computed Properties
    
    /// Check if this is an audio message
    var isAudioMessage: Bool {
        messageType == .audio || audioUrl != nil
    }
    
    /// Check if this is a location message
    var isLocationMessage: Bool {
        messageType == .location || (latitude != nil && longitude != nil)
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case fromId = "from_id"
        case text
        case imageUrl = "image_url"
        case readBy = "read_by"
        case createdAt = "created_at"
        case messageType = "message_type"
        case replyToId = "reply_to_id"
        case audioUrl = "audio_url"
        case audioDuration = "audio_duration"
        case latitude
        case longitude
        case locationName = "location_name"
        case sender
        // reactions and replyToMessage are not in CodingKeys - populated separately
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        conversationId: UUID,
        fromId: UUID,
        text: String = "",
        imageUrl: String? = nil,
        readBy: [UUID] = [],
        createdAt: Date = Date(),
        messageType: MessageType? = .text,
        replyToId: UUID? = nil,
        audioUrl: String? = nil,
        audioDuration: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        sender: Profile? = nil,
        reactions: MessageReactions? = nil,
        replyToMessage: ReplyContext? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.fromId = fromId
        self.text = text
        self.imageUrl = imageUrl
        self.readBy = readBy
        self.createdAt = createdAt
        self.messageType = messageType
        self.replyToId = replyToId
        self.audioUrl = audioUrl
        self.audioDuration = audioDuration
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.sender = sender
        self.reactions = reactions
        self.replyToMessage = replyToMessage
    }
}

// MARK: - Reply Context

/// Lightweight context for the message being replied to
struct ReplyContext: Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let senderName: String
    let senderId: UUID
    let imageUrl: String?
    
    init(id: UUID, text: String, senderName: String, senderId: UUID, imageUrl: String? = nil) {
        self.id = id
        self.text = text
        self.senderName = senderName
        self.senderId = senderId
        self.imageUrl = imageUrl
    }
    
    /// Create reply context from a full message
    init(from message: Message) {
        self.id = message.id
        self.text = message.text
        self.senderName = message.sender?.name ?? "Unknown"
        self.senderId = message.fromId
        self.imageUrl = message.imageUrl
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
               lhs.messageType == rhs.messageType &&
               lhs.replyToId == rhs.replyToId &&
               lhs.audioUrl == rhs.audioUrl &&
               lhs.audioDuration == rhs.audioDuration &&
               lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude &&
               lhs.locationName == rhs.locationName &&
               lhs.sender?.id == rhs.sender?.id &&
               lhs.reactions == rhs.reactions &&
               lhs.replyToMessage == rhs.replyToMessage
    }
}

// MARK: - Typing User

/// Model for a user currently typing in a conversation
struct TypingUser: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let avatarUrl: String?
    
    init(id: UUID, name: String, avatarUrl: String?) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

// MARK: - Blocked User

/// Model for a blocked user
struct BlockedUser: Codable, Identifiable, Sendable {
    var id: UUID { blockedId }
    let blockedId: UUID
    let blockedName: String
    let blockedAvatarUrl: String?
    let blockedAt: Date
    let reason: String?
}
