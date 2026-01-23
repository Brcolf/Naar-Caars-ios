//
//  NotificationGrouping.swift
//  NaarsCars
//
//  Grouping utilities for bell notifications
//

import Foundation

struct NotificationGroup: Identifiable, Equatable {
    let id: String
    let notifications: [AppNotification]
    let primaryNotification: AppNotification
    let totalCount: Int
    let unreadCount: Int
    let hasUnread: Bool
    let isPinned: Bool

    init(id: String, notifications: [AppNotification]) {
        let sorted = notifications.sorted { $0.createdAt > $1.createdAt }
        let pinned = sorted.filter { $0.pinned }
        let primary = pinned.first ?? sorted.first!
        let unread = notifications.filter { !$0.read }.count

        self.id = id
        self.notifications = notifications
        self.primaryNotification = primary
        self.totalCount = notifications.count
        self.unreadCount = unread
        self.hasUnread = unread > 0
        self.isPinned = notifications.contains { $0.pinned }
    }
}

enum NotificationGrouping {
    static let messageTypes: Set<NotificationType> = [
        .message,
        .addedToConversation
    ]

    static let announcementTypes: Set<NotificationType> = [
        .announcement,
        .adminAnnouncement,
        .broadcast
    ]

    static let requestTypes: Set<NotificationType> = [
        .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
        .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted,
        .completionReminder, .qaActivity, .qaQuestion, .qaAnswer,
        .reviewRequest, .reviewReminder, .reviewReceived
    ]

    // Request badge uses Model A: distinct requests with unseen activity.
    // Note: reviewReceived is not request-scoped for badge purposes.
    static let requestBadgeTypes: Set<NotificationType> = [
        .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
        .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted,
        .completionReminder, .qaActivity, .qaQuestion, .qaAnswer,
        .reviewRequest, .reviewReminder
    ]

    static let townHallTypes: Set<NotificationType> = [
        .townHallPost, .townHallComment, .townHallReaction
    ]

    static func filterBellNotifications(from notifications: [AppNotification]) -> [AppNotification] {
        notifications.filter { !messageTypes.contains($0.type) }
    }

    static func groupBellNotifications(from notifications: [AppNotification]) -> [NotificationGroup] {
        let filtered = filterBellNotifications(from: notifications)
        let grouped = Dictionary(grouping: filtered) { notification in
            groupKey(for: notification)
        }
        return grouped
            .map { NotificationGroup(id: $0.key, notifications: $0.value) }
            .sorted { $0.primaryNotification.createdAt > $1.primaryNotification.createdAt }
    }

    static func groupKey(for notification: AppNotification) -> String {
        if announcementTypes.contains(notification.type) {
            return "announcement:\(notification.id)"
        }

        if townHallTypes.contains(notification.type), let postId = notification.townHallPostId {
            return "townHall:\(postId)"
        }

        if notification.type == .pendingApproval {
            return "admin:pendingApproval"
        }

        if requestTypes.contains(notification.type) {
            if let rideId = notification.rideId {
                return "ride:\(rideId)"
            }
            if let favorId = notification.favorId {
                return "favor:\(favorId)"
            }
        }

        return "notification:\(notification.id)"
    }

    static func requestKey(for notification: AppNotification) -> String? {
        guard requestBadgeTypes.contains(notification.type) else { return nil }
        if let rideId = notification.rideId {
            return "ride:\(rideId)"
        }
        if let favorId = notification.favorId {
            return "favor:\(favorId)"
        }
        return nil
    }

    static func unreadRequestKeys(from notifications: [AppNotification]) -> Set<String> {
        let keys = notifications.compactMap { notification -> String? in
            guard !notification.read else { return nil }
            return requestKey(for: notification)
        }
        return Set(keys)
    }
}

