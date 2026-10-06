//
//  NotificationNames.swift
//  NaarsCars
//
//  Centralized notification name constants for cross-module communication

import Foundation

extension Notification.Name {
    // MARK: - Lifecycle
    static let userDidSignOut = Notification.Name("userDidSignOut")
    static let handleInviteCodeDeepLink = Notification.Name("handleInviteCodeDeepLink")

    // MARK: - Messaging
    static let conversationUpdated = Notification.Name("conversationUpdated")
    static let messageReactionChanged = Notification.Name("messageReactionChanged")

    // MARK: - Prompts
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
    /// Contract: posted by `DashboardSyncEngine` only after `BackgroundSyncActor` has saved changed
    /// rows to SwiftData (`RefreshMetrics.savedToStore == true`). Observers must re-read SwiftData
    /// only; they must NOT fetch from the network — `RefreshCoordinator` owns refresh decisions.
    static let ridesDidSync = Notification.Name("ridesDidSync")
    /// See `ridesDidSync` for the posting/observing contract.
    static let favorsDidSync = Notification.Name("favorsDidSync")
    /// See `ridesDidSync` for the posting/observing contract.
    static let notificationsDidSync = Notification.Name("notificationsDidSync")
    /// Posted by `TownHallSyncEngine` (after a `BackgroundSyncActor` save) and `TownHallRepository`
    /// (after a MainActor save) when town hall post rows changed. Same contract as `ridesDidSync`.
    static let townHallPostsDidSync = Notification.Name("townHallPostsDidSync")
    /// Posted by `TownHallRepository` after comment rows changed; `object` is the post's `UUID`.
    static let townHallCommentsDidSync = Notification.Name("townHallCommentsDidSync")

    // MARK: - Ride flight enrichment
    /// Posted when flight_normalized was successfully saved for a ride (background task). userInfo["rideId"] = rideId (UUID). Subscribers should refetch that ride/list so UI shows the flight.
    static let rideFlightEnrichmentDidComplete = Notification.Name("rideFlightEnrichmentDidComplete")
}

/// UserInfo keys for rideFlightEnrichmentDidComplete
enum RideFlightEnrichmentNotification {
    static let rideIdKey = "rideId"
}
