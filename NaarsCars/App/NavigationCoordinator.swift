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
    @Published var navigateToRide: UUID?
    @Published var navigateToFavor: UUID?
    @Published var requestNavigationTarget: RequestNotificationTarget?
    @Published var navigateToConversation: UUID?
    @Published var conversationScrollTarget: ConversationScrollTarget?
    @Published var navigateToProfile: UUID?
    @Published var townHallNavigationTarget: TownHallNavigationTarget?
    @Published var navigateToAdminPanel: Bool = false
    @Published var navigateToPendingUsers: Bool = false
    @Published var navigateToNotifications: Bool = false
    @Published var profileScrollTarget: String?
    @Published var announcementsNavigationTarget: AnnouncementsNavigationTarget?
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
        clearConflictingNavigation(for: deepLink)

        switch deepLink {
        case .dashboard:
            selectedTab = .requests
            
        case .ride(let rideId):
            selectedTab = .requests
            navigateToRide = rideId
            
        case .favor(let favorId):
            selectedTab = .requests
            navigateToFavor = favorId
            
        case .conversation(let conversationId):
            selectedTab = .messages
            navigateToConversation = conversationId
            
        case .townHall:
            selectedTab = .community
            
        case .townHallPostComments(let postId):
            selectedTab = .community
            townHallNavigationTarget = .init(postId: postId, mode: .openComments)

        case .townHallPostHighlight(let postId):
            selectedTab = .community
            townHallNavigationTarget = .init(postId: postId, mode: .highlightPost)
            
        case .profile(let userId):
            selectedTab = .profile
            navigateToProfile = userId
            
        case .adminPanel:
            selectedTab = .profile
            navigateToAdminPanel = true
            
        case .pendingUsers:
            selectedTab = .profile
            navigateToPendingUsers = true

        case .notifications:
            navigateToNotifications = true

        case .announcements(let notificationId):
            announcementsNavigationTarget = .init(
                id: UUID(),
                scrollToNotificationId: notificationId
            )
            
        case .enterApp:
            // User was approved - just go to dashboard
            selectedTab = .requests
            
        case .unknown:
            // Unknown deep link - go to dashboard
            selectedTab = .requests
        }
        
        print("📍 [NavigationCoordinator] Navigating to: \(deepLink)")
    }

    private func clearConflictingNavigation(for deepLink: DeepLink) {
        switch deepLink {
        case .ride:
            navigateToFavor = nil
            requestNavigationTarget = nil
        case .favor:
            navigateToRide = nil
            requestNavigationTarget = nil
        case .conversation:
            conversationScrollTarget = nil
        case .profile:
            profileScrollTarget = nil
        case .townHall, .townHallPostComments, .townHallPostHighlight:
            townHallNavigationTarget = nil
        case .adminPanel, .pendingUsers:
            navigateToAdminPanel = false
            navigateToPendingUsers = false
        case .notifications, .announcements:
            announcementsNavigationTarget = nil
        case .dashboard, .enterApp, .unknown:
            break
        }

        requestNavigationTarget = nil
        profileScrollTarget = nil
        conversationScrollTarget = nil
    }

    private func shouldConfirmDeepLink(for deepLink: DeepLink) -> Bool {
        guard hasActiveNavigation else { return false }
        return !isSameDeepLink(deepLink)
    }

    private var hasActiveNavigation: Bool {
        navigateToRide != nil ||
        navigateToFavor != nil ||
        navigateToConversation != nil ||
        navigateToProfile != nil ||
        townHallNavigationTarget != nil ||
        navigateToAdminPanel ||
        navigateToPendingUsers ||
        navigateToNotifications ||
        announcementsNavigationTarget != nil ||
        requestNavigationTarget != nil ||
        conversationScrollTarget != nil ||
        profileScrollTarget != nil
    }

    private func isSameDeepLink(_ deepLink: DeepLink) -> Bool {
        switch deepLink {
        case .ride(let id):
            return navigateToRide == id
        case .favor(let id):
            return navigateToFavor == id
        case .conversation(let id):
            return navigateToConversation == id
        case .profile(let id):
            return navigateToProfile == id
        case .townHallPostComments(let id), .townHallPostHighlight(let id):
            return townHallNavigationTarget?.postId == id
        case .townHall:
            return selectedTab == .community
        case .adminPanel:
            return navigateToAdminPanel
        case .pendingUsers:
            return navigateToPendingUsers
        case .notifications:
            return navigateToNotifications
        case .announcements:
            return announcementsNavigationTarget != nil
        case .dashboard, .enterApp:
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
                self.navigate(to: .ride(id: rideId))
                if let target = Self.requestTarget(from: userInfo, requestId: rideId, requestType: .ride) {
                    self.requestNavigationTarget = target
                }
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
                self.navigate(to: .favor(id: favorId))
                if let target = Self.requestTarget(from: userInfo, requestId: favorId, requestType: .favor) {
                    self.requestNavigationTarget = target
                }
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
                self.navigate(to: .conversation(id: conversationId))
                if let messageId = userInfo["messageId"] as? UUID {
                    self.conversationScrollTarget = .init(
                        conversationId: conversationId,
                        messageId: messageId
                    )
                    print("📍 [NavigationCoordinator] Message deep link to \(conversationId) (\(messageId))")
                }
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
                self.navigate(to: .profile(id: userId))
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
                    self.selectedTab = .community
                    self.townHallNavigationTarget = .init(postId: postId, mode: mode)
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
                self.navigate(to: .adminPanel)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToPendingUsers"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.selectedTab = .profile
                self.navigateToPendingUsers = true
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToNotifications"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.navigate(to: .notifications)
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
                self.announcementsNavigationTarget = .init(
                    id: UUID(),
                    scrollToNotificationId: notificationId
                )
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
    
    /// Reset navigation state after navigation completes
    func resetNavigation() {
        navigateToRide = nil
        navigateToFavor = nil
        navigateToConversation = nil
        navigateToProfile = nil
        townHallNavigationTarget = nil
        navigateToAdminPanel = false
        navigateToPendingUsers = false
        navigateToNotifications = false
        profileScrollTarget = nil
        announcementsNavigationTarget = nil
        requestNavigationTarget = nil
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
            print("⚠️ [NavigationCoordinator] Unknown request anchor: \(anchorRaw)")
            return nil
        }

        let scrollRaw = userInfo["requestScrollAnchor"] as? String
        let scrollAnchor = scrollRaw.flatMap(RequestDetailAnchor.init(rawValue:))
        if scrollRaw != nil && scrollAnchor == nil {
            print("⚠️ [NavigationCoordinator] Unknown request scroll anchor: \(scrollRaw ?? "")")
        }

        let highlightRaw = userInfo["requestHighlightAnchor"] as? String
        let highlightAnchor = highlightRaw.flatMap(RequestDetailAnchor.init(rawValue:))
        if highlightRaw != nil && highlightAnchor == nil {
            print("⚠️ [NavigationCoordinator] Unknown request highlight anchor: \(highlightRaw ?? "")")
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
