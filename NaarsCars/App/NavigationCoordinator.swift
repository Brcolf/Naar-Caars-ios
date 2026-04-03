//
//  NavigationCoordinator.swift
//  NaarsCars
//
//  Global navigation coordinator for deep link handling
//

import Foundation
import SwiftUI
import Observation

/// Unified intent for notification taps; applied after the notifications sheet has dismissed.
enum NotificationIntent: Equatable {
    case showReview(rideId: UUID?, favorId: UUID?)
    case showRequestCompletion(requestId: UUID, requestType: RequestType)
    case openConversation(conversationId: UUID, scrollTarget: NavigationCoordinator.ConversationScrollTarget?)
    case openRide(rideId: UUID, anchor: RequestNotificationTarget?)
    case openFavor(favorId: UUID, anchor: RequestNotificationTarget?)
    case openTownHallPost(postId: UUID, mode: NavigationCoordinator.TownHallNavigationTarget.Mode)
    case openAnnouncements(scrollToNotificationId: UUID?)
    case openProfile(userId: UUID)
    case openAdminPanel
    case openPendingUsers
    case openAdminReports
    case openDashboard
}

/// Global navigation coordinator for handling deep links from push notifications
@Observable
@MainActor
final class NavigationCoordinator {

    // MARK: - Singleton

    static let shared = NavigationCoordinator()

    // MARK: - Observed Properties
    //
    // selectedTab and pendingIntent use equality-guarded setters to prevent
    // @Observable from firing redundant change notifications on same-value
    // assignments. Without this, the bidirectional tab-sync in MainTabView
    // creates an infinite re-evaluation cascade.

    @ObservationIgnored private var _selectedTab: Tab = .requests
    var selectedTab: Tab {
        get {
            access(keyPath: \.selectedTab)
            return _selectedTab
        }
        set {
            guard _selectedTab != newValue else { return }
            withMutation(keyPath: \.selectedTab) {
                _selectedTab = newValue
            }
        }
    }

    @ObservationIgnored private var _pendingIntent: NavigationIntent?
    var pendingIntent: NavigationIntent? {
        get {
            access(keyPath: \.pendingIntent)
            return _pendingIntent
        }
        set {
            guard _pendingIntent != newValue else { return }
            withMutation(keyPath: \.pendingIntent) {
                _pendingIntent = newValue
            }
        }
    }

    var showReviewPrompt: Bool = false
    var reviewPromptRideId: UUID?
    var reviewPromptFavorId: UUID?
    /// Set when applying deferred .showRequestCompletion; MainTabView enqueues completion prompt then clears.
    var pendingCompletionPromptFromDeferred: (RequestType, UUID)?
    var pendingDeepLink: DeepLink?
    var showDeepLinkConfirmation: Bool = false
    /// Set true when a guest attempts to follow an auth-required navigation intent.
    /// MainTabView presents GuestSignInPromptView in response, then clears this flag.
    var showGuestDeepLinkPrompt: Bool = false
    
    // MARK: - Tab Enum
    
    enum Tab: Int {
        case requests = 0
        case messages = 1
        case community = 2  // Town Hall + Leaderboard
        case profile = 3
    }

    struct ConversationScrollTarget: Equatable {
        let conversationId: UUID
        let messageId: UUID
    }

    struct TownHallNavigationTarget: Equatable {
        enum Mode: String {
            case openComments
            case highlightPost
        }

        let postId: UUID
        let mode: Mode
    }

    struct AnnouncementsNavigationTarget: Identifiable, Equatable {
        let id: UUID
        let scrollToNotificationId: UUID?
    }
    
    // MARK: - Initialization

    private init() {}

    // MARK: - Deep Link Navigation
    
    /// Navigate to a deep link destination
    /// - Parameter deepLink: The deep link to navigate to
    func navigate(to deepLink: DeepLink) {
        if shouldConfirmDeepLink(for: deepLink) {
            pendingDeepLink = deepLink
            showDeepLinkConfirmation = true
            return
        }

        applyDeepLink(deepLink)
    }

    func applyPendingDeepLink() {
        guard let deepLink = pendingDeepLink else { return }
        pendingDeepLink = nil
        showDeepLinkConfirmation = false
        applyDeepLink(deepLink)
    }

    func cancelPendingDeepLink() {
        pendingDeepLink = nil
        showDeepLinkConfirmation = false
    }

    private func applyDeepLink(_ deepLink: DeepLink) {
        switch deepLink {
        case .dashboard:
            pendingIntent = .dashboard
            
        case .ride(let rideId):
            pendingIntent = .ride(rideId)
            
        case .favor(let favorId):
            pendingIntent = .favor(favorId)
            
        case .conversation(let conversationId):
            pendingIntent = .conversation(conversationId)
            
        case .townHall:
            selectedTab = .community
            
        case .townHallPostComments(let postId):
            pendingIntent = .townHallPost(postId, mode: .openComments)

        case .townHallPostHighlight(let postId):
            pendingIntent = .townHallPost(postId, mode: .highlightPost)
            
        case .profile(let userId):
            pendingIntent = .profile(userId)
            
        case .adminPanel:
            pendingIntent = .adminPanel
            
        case .pendingUsers:
            pendingIntent = .pendingUsers

        case .adminReports:
            pendingIntent = .adminReports

        case .notifications:
            pendingIntent = .notifications

        case .announcements(let notificationId):
            pendingIntent = .announcements(scrollToNotificationId: notificationId)
            
        case .enterApp:
            pendingIntent = .dashboard
            
        case .unknown:
            pendingIntent = .dashboard
        }
        
        AppLogger.info("navigation", "Navigating to: \(deepLink)")
    }

    private func shouldConfirmDeepLink(for deepLink: DeepLink) -> Bool {
        guard hasActiveNavigation else { return false }
        return !isSameDeepLink(deepLink)
    }

    private var hasActiveNavigation: Bool {
        pendingIntent != nil
    }

    private func isSameDeepLink(_ deepLink: DeepLink) -> Bool {
        switch deepLink {
        case .ride(let id):
            if case .ride(let currentId, _) = pendingIntent {
                return currentId == id
            }
            return false
        case .favor(let id):
            if case .favor(let currentId, _) = pendingIntent {
                return currentId == id
            }
            return false
        case .conversation(let id):
            if case .conversation(let currentId, _) = pendingIntent {
                return currentId == id
            }
            return false
        case .profile(let id):
            if case .profile(let currentId) = pendingIntent {
                return currentId == id
            }
            return false
        case .townHallPostComments(let id), .townHallPostHighlight(let id):
            if case .townHallPost(let postId, _) = pendingIntent {
                return postId == id
            }
            return false
        case .townHall:
            return selectedTab == .community
        case .adminPanel:
            if case .adminPanel = pendingIntent { return true }
            return false
        case .pendingUsers:
            if case .pendingUsers = pendingIntent { return true }
            return false
        case .adminReports:
            if case .adminReports = pendingIntent { return true }
            return false
        case .notifications:
            if case .notifications = pendingIntent { return true }
            return false
        case .announcements:
            if case .announcements = pendingIntent { return true }
            return false
        case .dashboard, .enterApp:
            if case .dashboard = pendingIntent { return true }
            return selectedTab == .requests
        case .unknown:
            return false
        }
    }
    
    // MARK: - Deferred notification intent (apply after notifications sheet dismisses)

    /// Intent stored when user taps a notification; applied in MainTabView sheet onDismiss.
    private(set) var deferredNotificationIntent: NotificationIntent?

    /// Store intent and request dismissal of the notifications sheet; do not set pendingIntent/showReviewPrompt directly from the list.
    func deferNotificationIntent(_ intent: NotificationIntent) {
        AppLogger.info("navigation", "[NavigationCoordinator] deferNotificationIntent: \(intent)")
        deferredNotificationIntent = intent
    }

    /// Apply stored intent (set show flags / ids / nav path), then clear. Call from MainTabView notifications sheet onDismiss.
    func applyDeferredNotificationIntentIfNeeded() {
        guard let intent = deferredNotificationIntent else { return }
        deferredNotificationIntent = nil
        AppLogger.info("navigation", "[NavigationCoordinator] applyDeferredNotificationIntentIfNeeded: \(intent)")

        switch intent {
        case .showReview(let rideId, let favorId):
            reviewPromptRideId = rideId
            reviewPromptFavorId = favorId
            showReviewPrompt = true
        case .showRequestCompletion(let requestId, let requestType):
            pendingCompletionPromptFromDeferred = (requestType, requestId)
        case .openConversation(let conversationId, let scrollTarget):
            pendingIntent = .conversation(conversationId, scrollTarget: scrollTarget)
            selectedTab = .messages
        case .openRide(let rideId, let anchor):
            pendingIntent = .ride(rideId, anchor: anchor)
            selectedTab = .requests
        case .openFavor(let favorId, let anchor):
            pendingIntent = .favor(favorId, anchor: anchor)
            selectedTab = .requests
        case .openTownHallPost(let postId, let mode):
            pendingIntent = .townHallPost(postId, mode: mode)
            selectedTab = .community
        case .openAnnouncements(let scrollToNotificationId):
            pendingIntent = .announcements(scrollToNotificationId: scrollToNotificationId)
            selectedTab = .community
        case .openProfile(let userId):
            pendingIntent = .profile(userId)
            selectedTab = .profile
        case .openAdminPanel:
            pendingIntent = .adminPanel
            selectedTab = .profile
        case .openPendingUsers:
            pendingIntent = .pendingUsers
            selectedTab = .profile
        case .openAdminReports:
            pendingIntent = .adminReports
            selectedTab = .profile
        case .openDashboard:
            pendingIntent = .dashboard
            selectedTab = .requests
        }
    }

    /// - Parameters:
    ///   - rideId: The ride ID (if ride)
    ///   - favorId: The favor ID (if favor)
    func showReviewPromptFor(rideId: UUID? = nil, favorId: UUID? = nil) {
        AppLogger.info("navigation", "[NavigationCoordinator] Queued pendingReview rideId=\(rideId?.uuidString ?? "nil") favorId=\(favorId?.uuidString ?? "nil")")
        reviewPromptRideId = rideId
        reviewPromptFavorId = favorId
        showReviewPrompt = true
    }
    
    // MARK: - Guest Gating

    /// Returns true if this intent requires an authenticated user.
    /// Guest-safe intents (ride, favor, townHallPost, profile, dashboard, requestListScroll)
    /// pass through. Admin-only intents (adminPanel, pendingUsers, adminReports) are
    /// treated as silently ignorable — guests should never encounter them via deep link.
    func intentRequiresAuth(_ intent: NavigationIntent) -> Bool {
        switch intent {
        case .ride, .favor, .requestListScroll, .townHallPost, .profile, .dashboard:
            return false
        case .conversation, .announcements, .notifications:
            return true
        case .adminPanel, .pendingUsers, .adminReports:
            // Admin-only: silently ignore rather than prompt
            return false
        }
    }

    /// Returns true if the intent is admin-only and should be silently dropped for guests.
    func intentIsAdminOnly(_ intent: NavigationIntent) -> Bool {
        switch intent {
        case .adminPanel, .pendingUsers, .adminReports:
            return true
        default:
            return false
        }
    }

    // MARK: - Public Methods

    func consumeRequestNavigationTarget(for requestType: RequestType, requestId: UUID) -> RequestNotificationTarget? {
        switch pendingIntent {
        case .ride(let id, let anchor):
            guard requestType == .ride, id == requestId, let anchor else { return nil }
            pendingIntent = nil
            return anchor
        case .favor(let id, let anchor):
            guard requestType == .favor, id == requestId, let anchor else { return nil }
            pendingIntent = nil
            return anchor
        default:
            return nil
        }
    }

    func consumeConversationScrollTarget(for conversationId: UUID) -> ConversationScrollTarget? {
        guard case .conversation(let intentId, let scrollTarget) = pendingIntent,
              intentId == conversationId,
              let scrollTarget else {
            return nil
        }
        pendingIntent = nil
        return scrollTarget
    }

    func consumeTownHallNavigationTarget() -> TownHallNavigationTarget? {
        guard case .townHallPost(let postId, let mode) = pendingIntent else {
            return nil
        }
        pendingIntent = nil
        return .init(postId: postId, mode: mode)
    }

    func consumeAnnouncementsNavigationTarget() -> AnnouncementsNavigationTarget? {
        guard case .announcements(let scrollId) = pendingIntent else {
            return nil
        }
        pendingIntent = nil
        return .init(id: UUID(), scrollToNotificationId: scrollId)
    }

    /// Reset navigation state after navigation completes
    func resetNavigation() {
        pendingIntent = nil
    }
    
    /// Reset review prompt state
    func resetReviewPrompt() {
        AppLogger.info("navigation", "[NavigationCoordinator] Cleared pendingReview")
        showReviewPrompt = false
        reviewPromptRideId = nil
        reviewPromptFavorId = nil
    }

}
