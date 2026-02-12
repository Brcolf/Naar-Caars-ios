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

/// Send status for local-first message tracking
enum MessageSendStatus: String, Codable, Sendable {
    /// Message is queued locally and awaiting network send
    case sending
    /// Message was accepted by the server
    case sent
    /// Message was delivered to at least one other participant
    case delivered
    /// Message send failed (tap to retry)
    case failed
    /// Message has been read by all participants
    case read
}

/// Message model
struct Message: Codable, Identifiable, Sendable {
    let id: UUID
    let conversationId: UUID
    let fromId: UUID
    var text: String
    let imageUrl: String?
    var readBy: [UUID] // UUID array from PostgreSQL
    let createdAt: Date
    
    // MARK: - Message Type
    
    /// Type of message (text, image, audio, location, system)
    let messageType: MessageType?
    
    // MARK: - Reply Support
    
    /// ID of the message this is replying to
    let replyToId: UUID?
    
    // MARK: - Edit / Unsend Support
    
    /// Timestamp when the message was last edited (nil if never edited)
    var editedAt: Date?
    
    /// Timestamp when the message was unsent (nil if not unsent)
    var deletedAt: Date?
    
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
    
    // MARK: - Local-First Fields (not in CodingKeys — derived from SwiftData)
    
    /// Local send status for optimistic UI and durable sending
    var sendStatus: MessageSendStatus?
    
    /// Path to a locally-cached attachment (image/audio) still being uploaded
    var localAttachmentPath: String?
    
    /// Sync error description when send fails
    var syncError: String?
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// Profile of the sender
    var sender: Profile?
    
    /// Reactions on this message (not stored in database, populated separately)
    var reactions: MessageReactions?
    
    /// The message this is replying to (populated when fetched)
    var replyToMessage: ReplyContext?
    
    // MARK: - Computed Properties (Edit / Unsend)
    
    /// Whether this message has been edited
    var isEdited: Bool {
        editedAt != nil
    }
    
    /// Whether this message has been unsent
    var isUnsent: Bool {
        deletedAt != nil
    }
    
    /// Whether this message can still be unsent (within 15 minutes of sending)
    var canUnsend: Bool {
        abs(createdAt.timeIntervalSinceNow) < 15 * 60
    }
    
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
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
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
        editedAt: Date? = nil,
        deletedAt: Date? = nil,
        audioUrl: String? = nil,
        audioDuration: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        sendStatus: MessageSendStatus? = nil,
        localAttachmentPath: String? = nil,
        syncError: String? = nil,
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
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.audioUrl = audioUrl
        self.audioDuration = audioDuration
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.sendStatus = sendStatus
        self.localAttachmentPath = localAttachmentPath
        self.syncError = syncError
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
               lhs.editedAt == rhs.editedAt &&
               lhs.deletedAt == rhs.deletedAt &&
               lhs.audioUrl == rhs.audioUrl &&
               lhs.audioDuration == rhs.audioDuration &&
               lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude &&
               lhs.locationName == rhs.locationName &&
               lhs.sendStatus == rhs.sendStatus &&
               lhs.localAttachmentPath == rhs.localAttachmentPath &&
               lhs.syncError == rhs.syncError &&
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
    
    enum CodingKeys: String, CodingKey {
        case blockedId = "blocked_id"
        case blockedName = "blocked_name"
        case blockedAvatarUrl = "blocked_avatar_url"
        case blockedAt = "blocked_at"
        case reason
    }
}