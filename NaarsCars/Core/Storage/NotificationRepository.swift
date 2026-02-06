//
//  NotificationRepository.swift
//  NaarsCars
//

import Foundation
import SwiftData
import SwiftUI
internal import Combine

@MainActor
final class NotificationRepository {
    static let shared = NotificationRepository()
    
    private var modelContext: ModelContext?
    
    private init() {}
    
    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Check if there are any unread notifications for a specific request and types
    func hasUnreadNotifications(requestId: UUID, types: [NotificationType]) -> Bool {
        guard let modelContext = modelContext else { return false }
        
        let typeStrings = types.map { $0.rawValue }
        let fetchDescriptor = FetchDescriptor<SDNotification>(
            predicate: #Predicate<SDNotification> { notification in
                !notification.read && 
                (notification.rideId == requestId || notification.favorId == requestId) &&
                typeStrings.contains(notification.type)
            }
        )
        
        do {
            let count = try modelContext.fetchCount(fetchDescriptor)
            return count > 0
        } catch {
            AppLogger.warning("notifications", "Error checking unread notifications: \(error)")
            return false
        }
    }
    
    /// Mark notifications as read locally
    func markAsReadLocally(requestId: UUID, types: [NotificationType]) {
        guard let modelContext = modelContext else { return }
        
        let typeStrings = types.map { $0.rawValue }
        let fetchDescriptor = FetchDescriptor<SDNotification>(
            predicate: #Predicate<SDNotification> { notification in
                !notification.read && 
                (notification.rideId == requestId || notification.favorId == requestId) &&
                typeStrings.contains(notification.type)
            }
        )
        
        do {
            let unread = try modelContext.fetch(fetchDescriptor)
            for notification in unread {
                notification.read = true
            }
            try modelContext.save()
        } catch {
            AppLogger.warning("notifications", "Error marking read locally: \(error)")
        }
    }
}


