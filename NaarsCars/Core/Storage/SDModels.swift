//
//  SDModels.swift
//  NaarsCars
//
//  SwiftData models for local-first architecture
//

import Foundation
import SwiftData

// MARK: - Messaging Models

@Model
final class SDConversation {
    @Attribute(.unique) var id: UUID
    var title: String?
    var groupImageUrl: String?
    var createdBy: UUID
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \SDMessage.conversation)
    var messages: [SDMessage]? = []
    
    // Participants (stored as simple UUIDs for now to avoid complex Profile sync)
    var participantIds: [UUID] = []
    
    // Cached values for list view
    var unreadCount: Int = 0
    
    init(id: UUID, title: String? = nil, groupImageUrl: String? = nil, createdBy: UUID, isArchived: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date(), participantIds: [UUID] = []) {
        self.id = id
        self.title = title
        self.groupImageUrl = groupImageUrl
        self.createdBy = createdBy
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.participantIds = participantIds
    }
}

@Model
final class SDMessage {
    @Attribute(.unique) var id: UUID
    var conversationId: UUID
    var fromId: UUID
    var text: String
    var imageUrl: String?
    var readBy: [UUID] = []
    var createdAt: Date
    var messageType: String // Store rawValue of MessageType
    
    // Reply support
    var replyToId: UUID?
    
    // Audio
    var audioUrl: String?
    var audioDuration: Double?
    
    // Location
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    
    // Edit/Unsend
    var editedAt: Date?
    var deletedAt: Date?
    
    // Sync status
    var isPending: Bool = false
    var syncError: String?
    
    // Relationship
    var conversation: SDConversation?
    
    init(id: UUID, conversationId: UUID, fromId: UUID, text: String, imageUrl: String? = nil, readBy: [UUID] = [], createdAt: Date = Date(), messageType: String = "text", replyToId: UUID? = nil, audioUrl: String? = nil, audioDuration: Double? = nil, latitude: Double? = nil, longitude: Double? = nil, locationName: String? = nil, editedAt: Date? = nil, deletedAt: Date? = nil, isPending: Bool = false) {
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
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.isPending = isPending
    }
}

// MARK: - Dashboard & Notification Models

@Model
final class SDRide {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var type: String
    var date: Date
    var time: String
    var pickup: String
    var destination: String
    var seats: Int
    var notes: String?
    var gift: String?
    var status: String // Store rawValue of RideStatus
    var claimedBy: UUID?
    var reviewed: Bool
    var reviewSkipped: Bool?
    var reviewSkippedAt: Date?
    var estimatedCost: Double?
    var createdAt: Date
    var updatedAt: Date
    
    // Cached profile metadata for list views
    var posterName: String?
    var posterAvatarUrl: String?
    var claimerName: String?
    var claimerAvatarUrl: String?

    // Relationships (stored as simple UUIDs for now to avoid complex Profile sync)
    var participantIds: [UUID] = []
    var qaCount: Int = 0
    
    init(id: UUID, userId: UUID, type: String = "request", date: Date, time: String, pickup: String, destination: String, seats: Int = 1, notes: String? = nil, gift: String? = nil, status: String = "open", claimedBy: UUID? = nil, reviewed: Bool = false, reviewSkipped: Bool? = nil, reviewSkippedAt: Date? = nil, estimatedCost: Double? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), posterName: String? = nil, posterAvatarUrl: String? = nil, claimerName: String? = nil, claimerAvatarUrl: String? = nil, participantIds: [UUID] = [], qaCount: Int = 0) {
        self.id = id
        self.userId = userId
        self.type = type
        self.date = date
        self.time = time
        self.pickup = pickup
        self.destination = destination
        self.seats = seats
        self.notes = notes
        self.gift = gift
        self.status = status
        self.claimedBy = claimedBy
        self.reviewed = reviewed
        self.reviewSkipped = reviewSkipped
        self.reviewSkippedAt = reviewSkippedAt
        self.estimatedCost = estimatedCost
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.posterName = posterName
        self.posterAvatarUrl = posterAvatarUrl
        self.claimerName = claimerName
        self.claimerAvatarUrl = claimerAvatarUrl
        self.participantIds = participantIds
        self.qaCount = qaCount
    }
}

@Model
final class SDFavor {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var title: String
    var favorDescription: String? // renamed from description to avoid conflict
    var location: String
    var duration: String // Store rawValue of FavorDuration
    var requirements: String?
    var date: Date
    var time: String?
    var gift: String?
    var status: String // Store rawValue of FavorStatus
    var claimedBy: UUID?
    var reviewed: Bool
    var reviewSkipped: Bool?
    var reviewSkippedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    
    // Cached profile metadata for list views
    var posterName: String?
    var posterAvatarUrl: String?
    var claimerName: String?
    var claimerAvatarUrl: String?

    // Relationships
    var participantIds: [UUID] = []
    var qaCount: Int = 0
    
    init(id: UUID, userId: UUID, title: String, favorDescription: String? = nil, location: String, duration: String = "not_sure", requirements: String? = nil, date: Date, time: String? = nil, gift: String? = nil, status: String = "open", claimedBy: UUID? = nil, reviewed: Bool = false, reviewSkipped: Bool? = nil, reviewSkippedAt: Date? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), posterName: String? = nil, posterAvatarUrl: String? = nil, claimerName: String? = nil, claimerAvatarUrl: String? = nil, participantIds: [UUID] = [], qaCount: Int = 0) {
        self.id = id
        self.userId = userId
        self.title = title
        self.favorDescription = favorDescription
        self.location = location
        self.duration = duration
        self.requirements = requirements
        self.date = date
        self.time = time
        self.gift = gift
        self.status = status
        self.claimedBy = claimedBy
        self.reviewed = reviewed
        self.reviewSkipped = reviewSkipped
        self.reviewSkippedAt = reviewSkippedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.posterName = posterName
        self.posterAvatarUrl = posterAvatarUrl
        self.claimerName = claimerName
        self.claimerAvatarUrl = claimerAvatarUrl
        self.participantIds = participantIds
        self.qaCount = qaCount
    }
}

@Model
final class SDNotification {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var type: String // Store rawValue of NotificationType
    var title: String
    var body: String?
    var read: Bool
    var pinned: Bool
    var createdAt: Date
    
    // Optional linked IDs for deep linking
    var rideId: UUID?
    var favorId: UUID?
    var conversationId: UUID?
    var reviewId: UUID?
    var townHallPostId: UUID?
    var sourceUserId: UUID?
    
    init(id: UUID, userId: UUID, type: String, title: String, body: String? = nil, read: Bool = false, pinned: Bool = false, createdAt: Date = Date(), rideId: UUID? = nil, favorId: UUID? = nil, conversationId: UUID? = nil, reviewId: UUID? = nil, townHallPostId: UUID? = nil, sourceUserId: UUID? = nil) {
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.body = body
        self.read = read
        self.pinned = pinned
        self.createdAt = createdAt
        self.rideId = rideId
        self.favorId = favorId
        self.conversationId = conversationId
        self.reviewId = reviewId
        self.townHallPostId = townHallPostId
        self.sourceUserId = sourceUserId
    }
}

// MARK: - Town Hall Models

@Model
final class SDTownHallPost {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var title: String?
    var content: String
    var imageUrl: String?
    var pinned: Bool
    var type: String?
    var reviewId: UUID?
    var createdAt: Date
    var updatedAt: Date

    // Cached author snapshot
    var authorName: String?
    var authorAvatarUrl: String?

    // Cached aggregates
    var commentCount: Int

    init(
        id: UUID,
        userId: UUID,
        title: String? = nil,
        content: String,
        imageUrl: String? = nil,
        pinned: Bool = false,
        type: String? = nil,
        reviewId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        authorName: String? = nil,
        authorAvatarUrl: String? = nil,
        commentCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.content = content
        self.imageUrl = imageUrl
        self.pinned = pinned
        self.type = type
        self.reviewId = reviewId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.authorName = authorName
        self.authorAvatarUrl = authorAvatarUrl
        self.commentCount = commentCount
    }
}

@Model
final class SDTownHallComment {
    @Attribute(.unique) var id: UUID
    var postId: UUID
    var userId: UUID
    var parentCommentId: UUID?
    var content: String
    var createdAt: Date
    var updatedAt: Date

    // Cached author snapshot
    var authorName: String?
    var authorAvatarUrl: String?

    init(
        id: UUID,
        postId: UUID,
        userId: UUID,
        parentCommentId: UUID? = nil,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        authorName: String? = nil,
        authorAvatarUrl: String? = nil
    ) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.parentCommentId = parentCommentId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.authorName = authorName
        self.authorAvatarUrl = authorAvatarUrl
    }
}
