//
//  AppNotification.swift
//  NaarsCars
//
//  In-app notification model
//

import Foundation

/// Notification type enum
enum NotificationType: String, Codable {
    // Messages
    case message = "message"
    case addedToConversation = "added_to_conversation"
    
    // Ride notifications
    case newRide = "new_ride"
    case rideUpdate = "ride_update"
    case rideClaimed = "ride_claimed"
    case rideUnclaimed = "ride_unclaimed"
    case rideCompleted = "ride_completed"
    
    // Favor notifications
    case newFavor = "new_favor"
    case favorUpdate = "favor_update"
    case favorClaimed = "favor_claimed"
    case favorUnclaimed = "favor_unclaimed"
    case favorCompleted = "favor_completed"
    
    // Request completion flow
    case completionReminder = "completion_reminder"
    
    // Q&A notifications (requestor + co-requestors only, before claim)
    case qaActivity = "qa_activity"
    case qaQuestion = "qa_question"
    case qaAnswer = "qa_answer"
    
    // Reviews
    case review = "review"
    case reviewReceived = "review_received"
    case reviewReminder = "review_reminder"
    case reviewRequest = "review_request"
    
    // Town Hall
    // Note: Town Hall votes/reactions create in-app notifications only (no push).
    // This is intentional to avoid push notification overload from high-volume
    // upvote activity. Users see reactions in their bell feed when they open the app.
    case townHallPost = "town_hall_post"
    case townHallComment = "town_hall_comment"
    case townHallReaction = "town_hall_reaction"
    
    // Announcements (admin board announcements - cannot be disabled)
    case announcement = "announcement"
    case adminAnnouncement = "admin_announcement"
    case broadcast = "broadcast"
    
    // Admin notifications
    case pendingApproval = "pending_approval"
    case userApproved = "user_approved"
    case userRejected = "user_rejected"
    
    case other = "other"
    
    /// Icon name for notification type
    var icon: String {
        switch self {
        case .message, .addedToConversation:
            return "message.fill"
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted:
            return "car.fill"
        case .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted:
            return "hand.raised.fill"
        case .completionReminder:
            return "clock.fill"
        case .qaActivity, .qaQuestion, .qaAnswer:
            return "questionmark.circle.fill"
        case .review, .reviewReceived, .reviewReminder, .reviewRequest:
            return "star.fill"
        case .townHallPost, .townHallComment, .townHallReaction:
            return "building.columns.fill"
        case .announcement, .adminAnnouncement, .broadcast:
            return "megaphone.fill"
        case .pendingApproval:
            return "person.badge.clock.fill"
        case .userApproved:
            return "checkmark.circle.fill"
        case .userRejected:
            return "xmark.circle.fill"
        case .other:
            return "bell.fill"
        }
    }
    
    /// Whether this notification type can be disabled by user preferences
    var canBeDisabled: Bool {
        switch self {
        // These cannot be disabled - mandatory notifications
        case .newRide, .newFavor:  // All users must see new requests
            return false
        case .announcement, .adminAnnouncement, .broadcast:  // Board announcements
            return false
        case .userApproved, .userRejected:  // Account status
            return false
        case .pendingApproval:  // Admin must see pending users
            return false
        // Everything else can be disabled
        default:
            return true
        }
    }
    
    /// The user preference key that controls this notification type
    var preferenceKey: String? {
        switch self {
        case .message, .addedToConversation:
            return "notifyMessages"
        case .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
             .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted:
            return "notifyRideUpdates"
        case .qaActivity, .qaQuestion, .qaAnswer:
            return "notifyQaActivity"
        case .review, .reviewReceived, .reviewReminder, .reviewRequest,
             .completionReminder:
            return "notifyReviewReminders"
        case .townHallPost, .townHallComment, .townHallReaction:
            return "notifyTownHall"
        // Non-disableable types return nil
        default:
            return nil
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
    
    // Optional linked IDs for deep linking
    let rideId: UUID?
    let favorId: UUID?
    let conversationId: UUID?
    let reviewId: UUID?
    let townHallPostId: UUID?
    let sourceUserId: UUID?  // Who triggered the notification (sender, claimer, etc.)
    
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
        case townHallPostId = "town_hall_post_id"
        case sourceUserId = "source_user_id"
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
        reviewId: UUID? = nil,
        townHallPostId: UUID? = nil,
        sourceUserId: UUID? = nil
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
        self.townHallPostId = townHallPostId
        self.sourceUserId = sourceUserId
    }
}
