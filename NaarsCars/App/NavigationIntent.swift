//
//  NavigationIntent.swift
//  NaarsCars
//
//  Unified app navigation intent model
//

import Foundation

/// Unified navigation intent consumed by tab roots and detail screens.
enum NavigationIntent: Equatable {
    // Requests tab
    case ride(UUID, anchor: RequestNotificationTarget? = nil)
    case favor(UUID, anchor: RequestNotificationTarget? = nil)
    case requestListScroll(key: String)

    // Messages tab
    case conversation(UUID, scrollTarget: NavigationCoordinator.ConversationScrollTarget? = nil)

    // Community tab
    case townHallPost(UUID, mode: NavigationCoordinator.TownHallNavigationTarget.Mode = .openComments)
    case announcements(scrollToNotificationId: UUID? = nil)

    // Profile tab
    case profile(UUID)
    case adminPanel
    case pendingUsers

    // Cross-tab surfaces
    case notifications
    case dashboard

    /// The tab that should be selected for this intent.
    var targetTab: NavigationCoordinator.Tab {
        switch self {
        case .ride, .favor, .requestListScroll, .notifications, .dashboard:
            return .requests
        case .conversation:
            return .messages
        case .townHallPost, .announcements:
            return .community
        case .profile, .adminPanel, .pendingUsers:
            return .profile
        }
    }
}
