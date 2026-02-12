//
//  NavigationCoordinator.swift
//  NaarsCars
//
//  Global navigation coordinator for deep link handling
//

import Foundation
import SwiftUI
internal import Combine

/// Global navigation coordinator for handling deep links from push notifications
@MainActor
final class NavigationCoordinator: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NavigationCoordinator()
    
    // MARK: - Published Properties
    
    @Published var selectedTab: Tab = .requests
    @Published var pendingIntent: NavigationIntent?
    @Published var showReviewPrompt: Bool = false
    @Published var reviewPromptRideId: UUID?
    @Published var reviewPromptFavorId: UUID?
    @Published var pendingDeepLink: DeepLink?
    @Published var showDeepLinkConfirmation: Bool = false
    
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
    
    private init() {
        setupNotificationListeners()
    }
    
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
    
    /// Show review prompt for a completed request
    /// - Parameters:
    ///   - rideId: The ride ID (if ride)
    ///   - favorId: The favor ID (if favor)
    func showReviewPromptFor(rideId: UUID? = nil, favorId: UUID? = nil) {
        reviewPromptRideId = rideId
        reviewPromptFavorId = favorId
        showReviewPrompt = true
    }
    
    // MARK: - Notification Handling
    
    private func setupNotificationListeners() {
        // Listen for deep link notifications from AppDelegate
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToRide"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let rideId = userInfo["rideId"] as? UUID else {
                    return
                }
                let target = Self.requestTarget(from: userInfo, requestId: rideId, requestType: .ride)
                self.pendingIntent = .ride(rideId, anchor: target)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToFavor"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let favorId = userInfo["favorId"] as? UUID else {
                    return
                }
                let target = Self.requestTarget(from: userInfo, requestId: favorId, requestType: .favor)
                self.pendingIntent = .favor(favorId, anchor: target)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToConversation"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let conversationId = userInfo["conversationId"] as? UUID else {
                    return
                }
                var scrollTarget: ConversationScrollTarget?
                if let messageId = userInfo["messageId"] as? UUID {
                    scrollTarget = .init(
                        conversationId: conversationId,
                        messageId: messageId
                    )
                    AppLogger.info("navigation", "Message deep link to \(conversationId) (\(messageId))")
                }
                self.pendingIntent = .conversation(conversationId, scrollTarget: scrollTarget)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToProfile"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let userId = userInfo["userId"] as? UUID else {
                    return
                }
                self.pendingIntent = .profile(userId)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToTownHall"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let userInfo = notification.userInfo,
                   let postId = userInfo["postId"] as? UUID {
                    let modeValue = userInfo["mode"] as? String
                    let mode = TownHallNavigationTarget.Mode(rawValue: modeValue ?? "") ?? .openComments
                    self.pendingIntent = .townHallPost(postId, mode: mode)
                } else {
                    self.navigate(to: .townHall)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToAdminPanel"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.pendingIntent = .adminPanel
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToPendingUsers"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.pendingIntent = .pendingUsers
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToNotifications"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pendingIntent = .notifications
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("dismissNotificationsSheet"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .notifications = self.pendingIntent {
                    self.pendingIntent = nil
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToAnnouncements"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let notificationId = (notification.userInfo?["notificationId"] as? UUID)
                self.pendingIntent = .announcements(scrollToNotificationId: notificationId)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToDashboard"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.navigate(to: .dashboard)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("showReviewPrompt"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let userInfo = notification.userInfo else {
                    return
                }
                let rideId = userInfo["rideId"] as? UUID
                let favorId = userInfo["favorId"] as? UUID
                self.showReviewPromptFor(rideId: rideId, favorId: favorId)
            }
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
    
    /// Apply navigation that was deferred until after the notifications sheet dismissed.
    /// Call from MainTabView's notifications sheet onDismiss.
    func applyDeferredIntentAfterNotificationsDismissal() {
        guard let intent = pendingIntent else { return }
        if case .notifications = intent {
            return
        }
        selectedTab = intent.targetTab
    }
    
    /// Reset review prompt state
    func resetReviewPrompt() {
        showReviewPrompt = false
        reviewPromptRideId = nil
        reviewPromptFavorId = nil
    }

    private static func requestTarget(
        from userInfo: [AnyHashable: Any],
        requestId: UUID,
        requestType: RequestType
    ) -> RequestNotificationTarget? {
        guard let anchorRaw = userInfo["requestAnchor"] as? String else {
            return nil
        }
        guard let anchor = RequestDetailAnchor(rawValue: anchorRaw) else {
            AppLogger.warning("navigation", "Unknown request anchor: \(anchorRaw)")
            return nil
        }

        let scrollRaw = userInfo["requestScrollAnchor"] as? String
        let scrollAnchor = scrollRaw.flatMap(RequestDetailAnchor.init(rawValue:))
        if scrollRaw != nil && scrollAnchor == nil {
            AppLogger.warning("navigation", "Unknown request scroll anchor: \(scrollRaw ?? "")")
        }

        let highlightRaw = userInfo["requestHighlightAnchor"] as? String
        let highlightAnchor = highlightRaw.flatMap(RequestDetailAnchor.init(rawValue:))
        if highlightRaw != nil && highlightAnchor == nil {
            AppLogger.warning("navigation", "Unknown request highlight anchor: \(highlightRaw ?? "")")
        }
        let shouldAutoClear = userInfo["requestAutoClear"] as? Bool ?? true

        return RequestNotificationTarget(
            requestType: requestType,
            requestId: requestId,
            anchor: anchor,
            scrollAnchor: scrollAnchor,
            highlightAnchor: highlightAnchor,
            shouldAutoClear: shouldAutoClear
        )
    }
}
