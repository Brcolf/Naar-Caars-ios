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
    
    /// Get the reaction emoji a specific user placed, if any
    func currentUserReaction(userId: UUID) -> String? {
        reactions.first { $0.value.contains(userId) }?.key
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

/// Structured system message action type. Decoded from server `system_action` field
/// when available; falls back to text-based inference via `resolvedSystemAction`.
enum SystemAction: String, Codable, Sendable {
    case memberAdded = "member_added"
    case memberRemoved = "member_removed"
    case memberLeft = "member_left"
    case groupCreated = "group_created"
    case groupNameChanged = "group_name_changed"
    case groupAvatarChanged = "group_avatar_changed"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = SystemAction(rawValue: raw) ?? .unknown
    }
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

    /// Server-provided system action type (nil for non-system messages or older messages)
    let systemAction: SystemAction?

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
    
    // MARK: - Image Dimension Fields

    /// Width of the image in points (for aspect-ratio rendering)
    let imageWidth: Int?

    /// Height of the image in points (for aspect-ratio rendering)
    let imageHeight: Int?

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

    /// Individual per-user reaction records — single source of truth for reaction state.
    /// `reactions` (aggregated) is derived from this array. Never mutate `reactions` independently.
    var individualReactions: [MessageReaction]?

    /// Centralized setter that maintains the data invariant:
    /// sets `individualReactions`, then derives `reactions` from it.
    /// Use this everywhere instead of setting the two properties independently.
    mutating func setIndividualReactions(_ records: [MessageReaction]?) {
        individualReactions = records?.isEmpty == true ? nil : records
        reactions = MessageReactions.from(records ?? [])
    }

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

    /// Best-effort system action resolution. Prefers server-provided `systemAction`;
    /// falls back to case-insensitive English text matching for older messages.
    var resolvedSystemAction: SystemAction {
        if let systemAction { return systemAction }
        guard messageType == .system else { return .unknown }
        let lower = text.lowercased()
        if lower.contains("added") || lower.contains("joined") { return .memberAdded }
        if lower.contains("left") { return .memberLeft }
        if lower.contains("removed") { return .memberRemoved }
        if lower.contains("name") { return .groupNameChanged }
        if lower.contains("photo") || lower.contains("image") || lower.contains("avatar") { return .groupAvatarChanged }
        if lower.contains("created") { return .groupCreated }
        return .unknown
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
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case latitude
        case longitude
        case locationName = "location_name"
        case systemAction = "system_action"
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
        systemAction: SystemAction? = nil,
        replyToId: UUID? = nil,
        editedAt: Date? = nil,
        deletedAt: Date? = nil,
        audioUrl: String? = nil,
        audioDuration: Double? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        sendStatus: MessageSendStatus? = nil,
        localAttachmentPath: String? = nil,
        syncError: String? = nil,
        sender: Profile? = nil,
        reactions: MessageReactions? = nil,
        replyToMessage: ReplyContext? = nil,
        individualReactions: [MessageReaction]? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.fromId = fromId
        self.text = text
        self.imageUrl = imageUrl
        self.readBy = readBy
        self.createdAt = createdAt
        self.messageType = messageType
        self.systemAction = systemAction
        self.replyToId = replyToId
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.audioUrl = audioUrl
        self.audioDuration = audioDuration
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.sendStatus = sendStatus
        self.localAttachmentPath = localAttachmentPath
        self.syncError = syncError
        self.sender = sender
        self.reactions = reactions
        self.replyToMessage = replyToMessage
        self.individualReactions = individualReactions
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
               lhs.systemAction == rhs.systemAction &&
               lhs.replyToId == rhs.replyToId &&
               lhs.editedAt == rhs.editedAt &&
               lhs.deletedAt == rhs.deletedAt &&
               lhs.audioUrl == rhs.audioUrl &&
               lhs.audioDuration == rhs.audioDuration &&
               lhs.imageWidth == rhs.imageWidth &&
               lhs.imageHeight == rhs.imageHeight &&
               lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude &&
               lhs.locationName == rhs.locationName &&
               lhs.sendStatus == rhs.sendStatus &&
               lhs.localAttachmentPath == rhs.localAttachmentPath &&
               lhs.syncError == rhs.syncError &&
               lhs.sender?.id == rhs.sender?.id &&
               lhs.reactions == rhs.reactions &&
               lhs.individualReactions == rhs.individualReactions &&
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

// MARK: - MessageReactions Derivation

extension MessageReactions {
    /// Derive aggregated reactions from individual records.
    /// This is the only sanctioned way to produce a `MessageReactions` value.
    static func from(_ records: [MessageReaction]) -> MessageReactions? {
        guard !records.isEmpty else { return nil }
        var dict: [String: [UUID]] = [:]
        for record in records {
            dict[record.reaction, default: []].append(record.userId)
        }
        return MessageReactions(reactions: dict)
    }
}
