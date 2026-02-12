//
//  NotificationNavigationRouter.swift
//  NaarsCars
//
//  Routes notification taps to deferred navigation intents
//

import Foundation
internal import Combine

/// Extracted tap-routing/navigation logic for notifications.
@MainActor
final class NotificationNavigationRouter: ObservableObject {
    private let authService: AuthService

    init(authService: AuthService = .shared) {
        self.authService = authService
    }

    func handleNotificationTap(
        _ notification: AppNotification,
        group: NotificationGroup?,
        markAsRead: @escaping @MainActor (AppNotification) -> Void,
        markGroupAsRead: @escaping @MainActor (NotificationGroup) -> Void,
        handleReviewPromptNotification: @escaping @MainActor (AppNotification) -> Void
    ) {
        if NotificationGrouping.announcementTypes.contains(notification.type) {
            handleAnnouncementTap(notification, markAsRead: markAsRead)
            return
        }

        if let group = group {
            markGroupAsRead(group)
        } else if shouldMarkReadOnTap(notification.type) && !notification.read {
            Task { @MainActor in
                markAsRead(notification)
            }
        }

        // Dismiss sheet/surface first, then apply deferred intent.
        NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)

        if notification.type == .reviewRequest || notification.type == .reviewReminder {
            handleReviewPromptNotification(notification)
            return
        }

        if notification.type == .completionReminder {
            if let rideId = notification.rideId {
                NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["rideId": rideId])
            } else if let favorId = notification.favorId {
                NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["favorId": favorId])
            }
        }

        if let pending = pendingNavigation(for: notification) {
            NavigationCoordinator.shared.pendingIntent = pending
        } else {
            handleNotificationNavigation(for: notification)
        }
    }

    func handleAnnouncementTap(
        _ notification: AppNotification,
        markAsRead: @escaping @MainActor (AppNotification) -> Void
    ) {
        if !notification.read {
            Task { @MainActor in
                markAsRead(notification)
            }
        }

        NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)
        AppLogger.info("notifications", "[NotificationNavigationRouter] Announcement tapped: \(notification.id)")
    }

    /// Builds deferred navigation intent for notifications sheet onDismiss.
    func pendingNavigation(for notification: AppNotification) -> NavigationIntent? {
        if let target = RequestNotificationMapping.target(
            for: notification.type,
            rideId: notification.rideId,
            favorId: notification.favorId
        ) {
            AppLogger.info("notifications", "[NotificationNavigationRouter] Request target found: \(target.anchor.rawValue)")
            switch target.requestType {
            case .ride:
                return .ride(target.requestId, anchor: target)
            case .favor:
                return .favor(target.requestId, anchor: target)
            }
        }

        switch notification.type {
        case .completionReminder:
            if let rideId = notification.rideId { return .ride(rideId) }
            if let favorId = notification.favorId { return .favor(favorId) }
            return nil
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
             .qaActivity, .qaQuestion, .qaAnswer:
            return notification.rideId.map { .ride($0, anchor: nil) }
        case .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted:
            return notification.favorId.map { .favor($0, anchor: nil) }
        case .message, .addedToConversation:
            return notification.conversationId.map { .conversation($0, scrollTarget: nil) }
        case .townHallPost:
            return notification.townHallPostId.map { .townHallPost($0, mode: .openComments) }
        case .townHallComment, .townHallReaction:
            return notification.townHallPostId.map { .townHallPost($0, mode: .highlightPost) }
        case .pendingApproval:
            return .pendingUsers
        case .review:
            if let rideId = notification.rideId { return .ride(rideId) }
            if let favorId = notification.favorId { return .favor(favorId) }
            if let currentUserId = authService.currentUserId {
                return .profile(currentUserId)
            }
            return .dashboard
        case .reviewReceived:
            if let currentUserId = authService.currentUserId {
                return .profile(currentUserId)
            }
            return .dashboard
        case .userApproved:
            return .dashboard
        case .userRejected:
            return nil
        case .adminAnnouncement, .announcement, .broadcast:
            return nil
        case .other:
            return .dashboard
        default:
            return nil
        }
    }

    private func handleNotificationNavigation(for notification: AppNotification) {
        let coordinator = NavigationCoordinator.shared

        if notification.type == .reviewRequest || notification.type == .reviewReminder {
            NotificationCenter.default.post(name: .showReviewPrompt, object: nil)
            return
        }

        if let target = RequestNotificationMapping.target(
            for: notification.type,
            rideId: notification.rideId,
            favorId: notification.favorId
        ) {
            switch target.requestType {
            case .ride:
                coordinator.pendingIntent = .ride(target.requestId, anchor: target)
            case .favor:
                coordinator.pendingIntent = .favor(target.requestId, anchor: target)
            }
            return
        }

        switch notification.type {
        case .completionReminder:
            if let rideId = notification.rideId {
                coordinator.pendingIntent = .ride(rideId)
            } else if let favorId = notification.favorId {
                coordinator.pendingIntent = .favor(favorId)
            }
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
             .qaActivity, .qaQuestion, .qaAnswer:
            if let rideId = notification.rideId { coordinator.pendingIntent = .ride(rideId) }
        case .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted:
            if let favorId = notification.favorId { coordinator.pendingIntent = .favor(favorId) }
        case .message, .addedToConversation:
            if let conversationId = notification.conversationId { coordinator.pendingIntent = .conversation(conversationId) }
        case .townHallPost:
            if let postId = notification.townHallPostId { coordinator.pendingIntent = .townHallPost(postId, mode: .openComments) }
        case .townHallComment, .townHallReaction:
            if let postId = notification.townHallPostId { coordinator.pendingIntent = .townHallPost(postId, mode: .highlightPost) }
        case .pendingApproval:
            coordinator.pendingIntent = .pendingUsers
        case .review:
            if let rideId = notification.rideId {
                coordinator.pendingIntent = .ride(rideId)
            } else if let favorId = notification.favorId {
                coordinator.pendingIntent = .favor(favorId)
            } else if let currentUserId = authService.currentUserId {
                coordinator.pendingIntent = .profile(currentUserId)
            }
        case .reviewReceived:
            if let currentUserId = authService.currentUserId { coordinator.pendingIntent = .profile(currentUserId) }
        case .userApproved, .other:
            coordinator.pendingIntent = .dashboard
        case .userRejected, .adminAnnouncement, .announcement, .broadcast:
            break
        default:
            break
        }
    }

    private func shouldMarkReadOnTap(_ type: NotificationType) -> Bool {
        switch type {
        case .reviewRequest, .reviewReminder, .completionReminder:
            return false
        default:
            return true
        }
    }
}
