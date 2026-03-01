//
//  NotificationGroupingManager.swift
//  NaarsCars
//
//  Groups and filters notification payloads for display
//

import Foundation
import Observation
import SwiftData

/// Precomputed notification sections ready for display.
struct GroupedNotifications {
    let pinned: [NotificationGroup]
    let sections: [(date: Date, groups: [NotificationGroup])]

    /// All groups across pinned and sections, for emptiness / count checks.
    var allGroups: [NotificationGroup] {
        pinned + sections.flatMap { $0.groups }
    }

    var isEmpty: Bool {
        pinned.isEmpty && sections.isEmpty
    }

    static let empty = GroupedNotifications(pinned: [], sections: [])
}

/// Extracted grouping/filtering logic for notifications.
@MainActor
@Observable
final class NotificationGroupingManager {
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

    /// Precompute pinned groups and date-sectioned regular groups for display.
    func computeGroupedNotifications(sdNotifications: [SDNotification]) -> GroupedNotifications {
        let allGroups = getNotificationGroups(sdNotifications: sdNotifications)
        let pinned = allGroups.filter { $0.isPinned }
        let regular = allGroups.filter { !$0.isPinned }
        let dict = Dictionary(grouping: regular) { group in
            Calendar.current.startOfDay(for: group.primaryNotification.createdAt)
        }
        let sections = dict.keys.sorted(by: >).map { date in
            (date: date, groups: dict[date] ?? [])
        }
        return GroupedNotifications(pinned: pinned, sections: sections)
    }
}
