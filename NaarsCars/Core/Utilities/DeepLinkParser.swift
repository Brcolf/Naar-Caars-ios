//
//  DeepLinkParser.swift
//  NaarsCars
//
//  Deep link parser for notification navigation
//

import Foundation

/// Deep link types for navigation
enum DeepLink {
    case ride(id: UUID)
    case favor(id: UUID)
    case conversation(id: UUID)
    case profile(id: UUID)
    case townHallPost(id: UUID)
    case townHall
    case adminPanel
    case dashboard
    case notifications
    case enterApp  // For approved users to enter the main app
    case unknown
}

/// Parser for deep links from push notifications
struct DeepLinkParser {
    /// Parse deep link from notification userInfo
    /// - Parameter userInfo: Notification payload
    /// - Returns: Parsed DeepLink
    static func parse(userInfo: [AnyHashable: Any]) -> DeepLink {
        guard let type = userInfo["type"] as? String else {
            return .unknown
        }
        
        switch type {
        // Ride notifications - navigate to ride detail
        case "new_ride", "ride_claimed", "ride_unclaimed", "ride_update", "ride_completed",
             "completion_reminder", "review_request", "qa_question", "qa_answer":
            if let rideIdString = userInfo["ride_id"] as? String,
               let rideId = UUID(uuidString: rideIdString) {
                return .ride(id: rideId)
            }
            // Check for favor_id as well for completion_reminder and review_request
            if let favorIdString = userInfo["favor_id"] as? String,
               let favorId = UUID(uuidString: favorIdString) {
                return .favor(id: favorId)
            }
            // If new_ride with no specific ID, go to dashboard
            if type == "new_ride" {
                return .dashboard
            }
            
        // Favor notifications - navigate to favor detail
        case "new_favor", "favor_claimed", "favor_unclaimed", "favor_update", "favor_completed":
            if let favorIdString = userInfo["favor_id"] as? String,
               let favorId = UUID(uuidString: favorIdString) {
                return .favor(id: favorId)
            }
            // If new_favor with no specific ID, go to dashboard
            if type == "new_favor" {
                return .dashboard
            }
            
        // Message notifications - navigate to conversation
        case "message", "new_message", "added_to_conversation":
            if let conversationIdString = userInfo["conversation_id"] as? String,
               let conversationId = UUID(uuidString: conversationIdString) {
                return .conversation(id: conversationId)
            }
            
        // Town Hall notifications
        case "town_hall_post", "town_hall_comment", "town_hall_reaction":
            if let postIdString = userInfo["town_hall_post_id"] as? String,
               let postId = UUID(uuidString: postIdString) {
                return .townHallPost(id: postId)
            }
            return .townHall

        case "town_hall":
            return .townHall
            
        // Profile/user notifications
        case "profile_update":
            if let userIdString = userInfo["user_id"] as? String,
               let userId = UUID(uuidString: userIdString) {
                return .profile(id: userId)
            }
            
        // Admin notifications - navigate to admin panel
        case "pending_approval", "admin_panel":
            return .adminPanel
            
        // User approved - navigate to main app
        case "user_approved", "enter_app":
            if userInfo["action"] as? String == "enter_app" {
                return .enterApp
            }
            return .enterApp

        case "dashboard":
            return .dashboard
            
        // Announcement/broadcast notifications
        case "announcement", "admin_announcement", "broadcast":
            return .notifications
            
        // Generic notification
        case "notification":
            return .notifications
            
        default:
            return .unknown
        }
        
        return .unknown
    }
}





