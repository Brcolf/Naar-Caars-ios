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
        markGroupAsRead: @escaping @MainActor (NotificationGroup) -> Void
    ) {
        if NotificationGrouping.announcementTypes.contains(notification.type) {
            // The inbox list handles announcement rows itself and shows the announcements list
            // in place. A caller that comes through here has no such screen, so it keeps the
            // deferred route.
            if handleAnnouncementTap(notification, markAsRead: markAsRead) {
                NavigationCoordinator.shared.deferNotificationIntent(.openAnnouncements(scrollToNotificationId: notification.id))
                NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)
            }
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

    /// Announcement row tap: one navigation per tap.
    ///
    /// A broadcast with a linked Town Hall post defers that intent and asks the inbox to close.
    /// Any other announcement is shown by the caller inside the open sheet, so nothing is
    /// deferred and nothing is dismissed. Deferring `.openAnnouncements` as well made the same
    /// list open a second time, as a new sheet on the Community tab, while the inbox was closing.
    /// - Returns: true when the caller should show the announcements list in place.
    @discardableResult
    func handleAnnouncementTap(
        _ notification: AppNotification,
        markAsRead: @escaping @MainActor (AppNotification) -> Void
    ) -> Bool {
        if !notification.read {
            Task { @MainActor in
                markAsRead(notification)
            }
        }
        guard let postId = notification.townHallPostId else {
            AppLogger.info("notifications", "[NotificationNavigationRouter] Announcement tapped: \(notification.id); showing announcements in place")
            return true
        }
        // The broadcast has a linked town hall post: navigate there instead
        AppLogger.info("notifications", "[NotificationNavigationRouter] Broadcast tapped with town hall post: \(postId); deferring intent")
        NavigationCoordinator.shared.deferNotificationIntent(.openTownHallPost(postId: postId, mode: .highlightPost))
        NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)
        return false
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
        case .contentHidden:
            if let conversationId = notification.conversationId {
                return .openConversation(conversationId: conversationId, scrollTarget: nil)
            }
            if let rideId = notification.rideId {
                return .openRide(rideId: rideId, anchor: nil)
            }
            if let favorId = notification.favorId {
                return .openFavor(favorId: favorId, anchor: nil)
            }
            if let postId = notification.townHallPostId {
                return .openTownHallPost(postId: postId, mode: .highlightPost)
            }
            return .openDashboard
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
