//
//  NotificationGroupingManager.swift
//  NaarsCars
//
//  Groups and filters notification payloads for display
//

import Foundation
import SwiftData
internal import Combine

/// Extracted grouping/filtering logic for notifications.
@MainActor
final class NotificationGroupingManager: ObservableObject {
    private let authService: AuthService

    init(authService: AuthService = .shared) {
        self.authService = authService
    }

    /// Get filtered notifications from SwiftData models.
    func getFilteredNotifications(sdNotifications: [SDNotification]) -> [AppNotification] {
        let currentUserId = authService.currentUserId
        let filteredByUser = sdNotifications.filter { sd in
            guard let currentUserId else { return true }
            return sd.userId == currentUserId
        }

        let notifications = filteredByUser.map { sd in
            AppNotification(
                id: sd.id,
                userId: sd.userId,
                type: NotificationType(rawValue: sd.type) ?? .other,
                title: sd.title,
                body: sd.body,
                read: sd.read,
                pinned: sd.pinned,
                createdAt: sd.createdAt,
                rideId: sd.rideId,
                favorId: sd.favorId,
                conversationId: sd.conversationId,
                reviewId: sd.reviewId,
                townHallPostId: sd.townHallPostId,
                sourceUserId: sd.sourceUserId
            )
        }
        return NotificationGrouping.filterBellNotifications(from: notifications)
    }

    /// Get grouped notification cards from SwiftData models.
    func getNotificationGroups(sdNotifications: [SDNotification]) -> [NotificationGroup] {
        let filtered = getFilteredNotifications(sdNotifications: sdNotifications)
        return NotificationGrouping.groupBellNotifications(from: filtered)
    }
}
