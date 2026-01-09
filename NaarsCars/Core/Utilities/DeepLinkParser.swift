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
    case notifications
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
        case "ride_claimed", "ride_unclaimed", "ride_update":
            if let rideIdString = userInfo["ride_id"] as? String,
               let rideId = UUID(uuidString: rideIdString) {
                return .ride(id: rideId)
            }
            
        case "favor_claimed", "favor_unclaimed", "favor_update":
            if let favorIdString = userInfo["favor_id"] as? String,
               let favorId = UUID(uuidString: favorIdString) {
                return .favor(id: favorId)
            }
            
        case "message", "new_message":
            if let conversationIdString = userInfo["conversation_id"] as? String,
               let conversationId = UUID(uuidString: conversationIdString) {
                return .conversation(id: conversationId)
            }
            
        case "profile_update":
            if let userIdString = userInfo["user_id"] as? String,
               let userId = UUID(uuidString: userIdString) {
                return .profile(id: userId)
            }
            
        case "announcement", "notification":
            return .notifications
            
        default:
            return .unknown
        }
        
        return .unknown
    }
}




