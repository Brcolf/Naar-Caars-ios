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
    @Published var navigateToConversation: UUID?
    @Published var navigateToProfile: UUID?
    @Published var navigateToTownHallPost: UUID?
    @Published var navigateToAdminPanel: Bool = false
    @Published var navigateToNotifications: Bool = false
    @Published var showReviewPrompt: Bool = false
    @Published var reviewPromptRideId: UUID?
    @Published var reviewPromptFavorId: UUID?
    
    // MARK: - Tab Enum
    
    enum Tab: Int {
        case requests = 0
        case messages = 1
        case community = 2  // Town Hall + Leaderboard
        case profile = 3
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationListeners()
    }
    
    // MARK: - Deep Link Navigation
    
    /// Navigate to a deep link destination
    /// - Parameter deepLink: The deep link to navigate to
    func navigate(to deepLink: DeepLink) {
        // Reset any existing navigation state first
        resetNavigation()
        
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
            
        case .townHallPost(let postId):
            selectedTab = .community
            navigateToTownHallPost = postId
            
        case .profile(let userId):
            selectedTab = .profile
            navigateToProfile = userId
            
        case .adminPanel:
            selectedTab = .profile
            navigateToAdminPanel = true
            
        case .notifications:
            // Notifications list lives in Profile tab
            selectedTab = .profile
            navigateToNotifications = true
            
        case .enterApp:
            // User was approved - just go to dashboard
            selectedTab = .requests
            
        case .unknown:
            // Unknown deep link - go to dashboard
            selectedTab = .requests
        }
        
        print("📍 [NavigationCoordinator] Navigating to: \(deepLink)")
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
                    self.navigate(to: .townHallPost(id: postId))
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
            forName: NSNotification.Name("navigateToNotifications"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.navigate(to: .notifications)
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
        navigateToTownHallPost = nil
        navigateToAdminPanel = false
        navigateToNotifications = false
    }
    
    /// Reset review prompt state
    func resetReviewPrompt() {
        showReviewPrompt = false
        reviewPromptRideId = nil
        reviewPromptFavorId = nil
    }
}
