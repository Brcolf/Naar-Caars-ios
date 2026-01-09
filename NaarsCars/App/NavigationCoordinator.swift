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
    @Published var navigateToNotifications: Bool = false
    
    // MARK: - Tab Enum
    
    enum Tab: Int {
        case requests = 0
        case messages = 1
        case notifications = 2
        case townHall = 3
        case leaderboard = 4
        case profile = 5
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationListeners()
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
                self.selectedTab = .requests
                self.navigateToRide = rideId
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
                self.selectedTab = .requests
                self.navigateToFavor = favorId
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
                self.selectedTab = .messages
                self.navigateToConversation = conversationId
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
                self.selectedTab = .profile
                self.navigateToProfile = userId
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("navigateToNotifications"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.selectedTab = .notifications
                self.navigateToNotifications = true
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
        navigateToNotifications = false
    }
}

