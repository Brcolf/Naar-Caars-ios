//
//  AppNotification.swift
//  NaarsCars
//
//  In-app notification model matching database schema
//

import Foundation

/// Notification type enum
enum NotificationType: String, Codable {
    case rideClaimed = "ride_claimed"
    case favorClaimed = "favor_claimed"
    case message = "message"
    case reviewReminder = "review_reminder"
    case adminAnnouncement = "admin_announcement"
    case qaActivity = "qa_activity"
    case other = "other"
}

/// In-app notification model
struct AppNotification: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let type: NotificationType
    let title: String
    let body: String?
    let rideId: UUID?
    let favorId: UUID?
    let conversationId: UUID?
    let read: Bool
    let pinned: Bool
    let createdAt: Date
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case title
        case body
        case rideId = "ride_id"
        case favorId = "favor_id"
        case conversationId = "conversation_id"
        case read
        case pinned
        case createdAt = "created_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        type: NotificationType,
        title: String,
        body: String? = nil,
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        conversationId: UUID? = nil,
        read: Bool = false,
        pinned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.body = body
        self.rideId = rideId
        self.favorId = favorId
        self.conversationId = conversationId
        self.read = read
        self.pinned = pinned
        self.createdAt = createdAt
    }
}


