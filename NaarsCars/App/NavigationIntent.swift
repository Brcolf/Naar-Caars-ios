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

    // Town Hall tab
    case townHallPost(UUID, mode: NavigationCoordinator.TownHallNavigationTarget.Mode = .openComments, communityId: UUID? = nil)
    case announcements(scrollToNotificationId: UUID? = nil)

    // Profile tab
    case profile(UUID)
    case adminPanel
    /// The platform admins' Pending approvals: the default community's Requests to join.
    case pendingUsers
    case adminReports

    // Explore tab (My communities is its root)
    /// A community's Requests to join (admin of that community, or a platform admin).
    case pendingMembers(UUID)
    /// A community's reports (an owner or admin of that community).
    case communityReports(UUID)
    /// My communities (an approval into a further community while signed in).
    case myCommunities
    /// A community's members (made an owner of that community: `membership_update`).
    case communityMembers(UUID)
    /// Join a community with the code an invite link carried. The code is in `PendingInviteStore`,
    /// never in the intent; My communities opens Join from the store.
    case joinCommunity
    /// The Explore tab itself (guest-safe). `MainTabView` selects the tab and clears it.
    case explore

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
            return .townHall
        case .profile, .adminPanel, .pendingUsers, .adminReports:
            return .profile
        case .myCommunities, .joinCommunity, .pendingMembers, .communityReports, .communityMembers, .explore:
            return .explore
        }
    }
}
