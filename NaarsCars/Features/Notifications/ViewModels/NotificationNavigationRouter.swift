//
//  NotificationNavigationRouter.swift
//  NaarsCars
//
//  Routes notification taps to deferred navigation intents
//

import Foundation
import Observation

/// Extracted tap-routing/navigation logic for notifications.
@MainActor
@Observable
final class NotificationNavigationRouter {
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

        guard let intent = notificationIntent(for: notification) else {
            AppLogger.info("notifications", "[NotificationNavigationRouter] Notification tapped type=\(notification.type.rawValue) ids=\(notification.rideId?.uuidString ?? "nil")/\(notification.favorId?.uuidString ?? "nil") — no intent; dismissing only")
            NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)
            return
        }

        AppLogger.info("notifications", "[NotificationNavigationRouter] Notification tapped type=\(notification.type.rawValue) intent=\(intent); deferring intent and requesting dismissal")
        NavigationCoordinator.shared.deferNotificationIntent(intent)
        NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)
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
        // If broadcast has a linked town hall post, navigate there instead
        let intent: NotificationIntent
        if let postId = notification.townHallPostId {
            intent = .openTownHallPost(postId: postId, mode: .highlightPost)
            AppLogger.info("notifications", "[NotificationNavigationRouter] Broadcast tapped with town hall post: \(postId); deferring intent")
        } else {
            intent = .openAnnouncements(scrollToNotificationId: notification.id)
            AppLogger.info("notifications", "[NotificationNavigationRouter] Announcement tapped: \(notification.id); deferring intent")
        }
        NavigationCoordinator.shared.deferNotificationIntent(intent)
        NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)
    }

    /// Builds the unified NotificationIntent for a notification tap; applied after sheet dismisses.
    func notificationIntent(for notification: AppNotification) -> NotificationIntent? {
        switch notification.type {
        case .reviewRequest, .reviewReminder:
            return .showReview(rideId: notification.rideId, favorId: notification.favorId)
        case .completionReminder:
            if let rideId = notification.rideId {
                return .showRequestCompletion(requestId: rideId, requestType: .ride)
            }
            if let favorId = notification.favorId {
                return .showRequestCompletion(requestId: favorId, requestType: .favor)
            }
            return nil
        default:
            break
        }

        if let target = RequestNotificationMapping.target(
            for: notification.type,
            rideId: notification.rideId,
            favorId: notification.favorId
        ) {
            AppLogger.info("notifications", "[NotificationNavigationRouter] Request target found: \(target.anchor.rawValue)")
            switch target.requestType {
            case .ride:
                return .openRide(rideId: target.requestId, anchor: target)
            case .favor:
                return .openFavor(favorId: target.requestId, anchor: target)
            }
        }

        switch notification.type {
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
             .qaActivity, .qaQuestion, .qaAnswer:
            return notification.rideId.map { .openRide(rideId: $0, anchor: nil) }
        case .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted:
            return notification.favorId.map { .openFavor(favorId: $0, anchor: nil) }
        case .message, .addedToConversation:
            return notification.conversationId.map { .openConversation(conversationId: $0, scrollTarget: nil) }
        case .townHallPost:
            return notification.townHallPostId.map { .openTownHallPost(postId: $0, mode: .openComments) }
        case .townHallComment, .townHallReaction:
            return notification.townHallPostId.map { .openTownHallPost(postId: $0, mode: .highlightPost) }
        case .pendingApproval:
            return .openPendingUsers
        case .contentReported:
            return .openAdminReports
        case .review:
            if let rideId = notification.rideId { return .openRide(rideId: rideId, anchor: nil) }
            if let favorId = notification.favorId { return .openFavor(favorId: favorId, anchor: nil) }
            if let currentUserId = authService.currentUserId { return .openProfile(userId: currentUserId) }
            return .openDashboard
        case .reviewReceived:
            if let currentUserId = authService.currentUserId { return .openProfile(userId: currentUserId) }
            return .openDashboard
        case .userApproved:
            return .openDashboard
        case .userRejected:
            return nil
        case .adminAnnouncement, .announcement, .broadcast:
            return nil
        case .other:
            return .openDashboard
        default:
            return nil
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
