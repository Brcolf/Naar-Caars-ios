//
//  AppNotification.swift
//  NaarsCars
//
//  In-app notification model
//

import Foundation

/// Notification type enum
enum NotificationType: String, Codable {
    case message = "message"
    case rideUpdate = "ride_update"
    case rideClaimed = "ride_claimed"
    case rideUnclaimed = "ride_unclaimed"
    case favorUpdate = "favor_update"
    case favorClaimed = "favor_claimed"
    case favorUnclaimed = "favor_unclaimed"
    case review = "review"
    case reviewReceived = "review_received"
    case reviewReminder = "review_reminder"
    case announcement = "announcement"
    case adminAnnouncement = "admin_announcement"
    case broadcast = "broadcast"
    case userApproved = "user_approved"
    case qaActivity = "qa_activity"
    case other = "other"
    
    /// Icon name for notification type
    var icon: String {
        switch self {
        case .message: return "message.fill"
        case .rideUpdate, .rideClaimed, .rideUnclaimed: return "car.fill"
        case .favorUpdate, .favorClaimed, .favorUnclaimed: return "hand.raised.fill"
        case .review, .reviewReceived, .reviewReminder: return "star.fill"
        case .announcement, .adminAnnouncement, .broadcast: return "megaphone.fill"
        case .userApproved: return "checkmark.circle.fill"
        case .qaActivity: return "questionmark.circle.fill"
        case .other: return "bell.fill"
        }
    }
}

/// In-app notification model
struct AppNotification: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID
    let type: NotificationType
    let title: String
    let body: String?
    var read: Bool
    var pinned: Bool
    let createdAt: Date
    
    // Optional linked IDs
    let rideId: UUID?
    let favorId: UUID?
    let conversationId: UUID?
    let reviewId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case title
        case body
        case read
        case pinned
        case createdAt = "created_at"
        case rideId = "ride_id"
        case favorId = "favor_id"
        case conversationId = "conversation_id"
        case reviewId = "review_id"
    }
    
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        type: NotificationType,
        title: String,
        body: String? = nil,
        read: Bool = false,
        pinned: Bool = false,
        createdAt: Date = Date(),
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        conversationId: UUID? = nil,
        reviewId: UUID? = nil
    ) {
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
    }
}
