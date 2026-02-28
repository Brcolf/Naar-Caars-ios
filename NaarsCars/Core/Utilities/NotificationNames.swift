//
//  NotificationNames.swift
//  NaarsCars
//
//  Centralized notification name constants for cross-module communication

import Foundation

extension Notification.Name {
    // MARK: - Navigation (AppDelegate -> NavigationCoordinator)
    static let navigateToRide = Notification.Name("navigateToRide")
    static let navigateToFavor = Notification.Name("navigateToFavor")
    static let navigateToConversation = Notification.Name("navigateToConversation")
    static let navigateToProfile = Notification.Name("navigateToProfile")
    static let navigateToTownHall = Notification.Name("navigateToTownHall")
    static let navigateToAdminPanel = Notification.Name("navigateToAdminPanel")
    static let navigateToPendingUsers = Notification.Name("navigateToPendingUsers")
    static let navigateToNotifications = Notification.Name("navigateToNotifications")
    static let navigateToAnnouncements = Notification.Name("navigateToAnnouncements")
    static let navigateToDashboard = Notification.Name("navigateToDashboard")
    static let dismissNotificationsSheet = Notification.Name("dismissNotificationsSheet")

    // MARK: - Lifecycle
    static let userDidSignOut = Notification.Name("userDidSignOut")
    static let handleInviteCodeDeepLink = Notification.Name("handleInviteCodeDeepLink")

    // MARK: - Messaging
    static let conversationUpdated = Notification.Name("conversationUpdated")

    // MARK: - Prompts (moved from PushNotificationService.swift)
    static let showReviewPrompt = Notification.Name("showReviewPrompt")
    static let showCompletionPrompt = Notification.Name("showCompletionPrompt")
    static let dismissNotificationsSurface = Notification.Name("dismissNotificationsSurface")
    static let conversationUnreadCountsUpdated = Notification.Name("conversationUnreadCountsUpdated")

    // MARK: - Messaging UI (moved from InAppToastManager.swift)
    static let messageThreadDidAppear = Notification.Name("messageThreadDidAppear")
    static let messageThreadDidDisappear = Notification.Name("messageThreadDidDisappear")

    // MARK: - Town Hall (moved from TownHallSyncEngine.swift)
    static let townHallPostVotesDidChange = Notification.Name("townHallPostVotesDidChange")
    static let townHallCommentVotesDidChange = Notification.Name("townHallCommentVotesDidChange")

    // MARK: - Localization (moved from LocalizationManager.swift)
    static let languageDidChange = Notification.Name("languageDidChange")

    // MARK: - Sync notifications (Phase 7)
    static let ridesDidSync = Notification.Name("ridesDidSync")
    static let favorsDidSync = Notification.Name("favorsDidSync")
    static let notificationsDidSync = Notification.Name("notificationsDidSync")

    // MARK: - Ride flight enrichment
    /// Posted when flight_normalized was successfully saved for a ride (background task). userInfo["rideId"] = rideId (UUID). Subscribers should refetch that ride/list so UI shows the flight.
    static let rideFlightEnrichmentDidComplete = Notification.Name("rideFlightEnrichmentDidComplete")
}

/// UserInfo keys for rideFlightEnrichmentDidComplete
enum RideFlightEnrichmentNotification {
    static let rideIdKey = "rideId"
}
