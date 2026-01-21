//
//  BadgeCountManager.swift
//  NaarsCars
//
//  Manager for badge counts on tab bar icons
//

import Foundation
import UIKit
internal import Combine

/// Tab badge types
enum BadgeTab: String {
    case requests = "requests"
    case messages = "messages"
    case community = "community"
    case profile = "profile"
}

/// Manager for badge counts on tab bar icons
/// Tracks unread notifications and new content for each tab
@MainActor
final class BadgeCountManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = BadgeCountManager()
    
    // MARK: - Published Properties
    
    /// Badge count for Requests tab (new requests + Q&A activity)
    @Published var requestsBadgeCount: Int = 0
    
    /// Badge count for Messages tab (unread messages)
    @Published var messagesBadgeCount: Int = 0
    
    /// Badge count for Community tab (new Town Hall posts/comments)
    @Published var communityBadgeCount: Int = 0
    
    /// Badge count for Profile tab (admin: pending approvals)
    @Published var profileBadgeCount: Int = 0
    
    /// Badge count for Admin Panel within Profile (pending approvals)
    @Published var adminPanelBadgeCount: Int = 0
    
    /// Total unread notification count (for app icon badge)
    @Published var totalUnreadCount: Int = 0
    
    // MARK: - Private Properties
    
    private let notificationService = NotificationService.shared
    private let messageService = MessageService.shared
    private let adminService = AdminService.shared
    private let townHallService = TownHallService.shared
    private let authService = AuthService.shared
    
    /// UserDefaults keys for last viewed timestamps
    private let lastViewedCommunityKey = "lastViewedCommunity"
    private let lastViewedRequestsKey = "lastViewedRequests"
    
    // MARK: - Initialization
    
    private init() {
        // Load initial badge counts when user is authenticated
        Task {
            await refreshAllBadges()
        }
        
        // Listen for notification changes
        setupNotificationListeners()
    }
    
    // MARK: - Setup
    
    private func setupNotificationListeners() {
        // Refresh badges when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAllBadges()
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Refresh all badge counts
    func refreshAllBadges() async {
        guard let userId = authService.currentUserId else {
            // Clear all badges if not authenticated
            requestsBadgeCount = 0
            messagesBadgeCount = 0
            communityBadgeCount = 0
            profileBadgeCount = 0
            adminPanelBadgeCount = 0
            totalUnreadCount = 0
            updateAppIconBadge(0)
            return
        }
        
        // Calculate all badges in parallel
        async let requestsCount = calculateRequestsBadgeCount(userId: userId)
        async let messagesCount = calculateMessagesBadgeCount(userId: userId)
        async let communityCount = calculateCommunityBadgeCount(userId: userId)
        async let profileCount = calculateProfileBadgeCount()
        
        let (requests, messages, community, profile) = await (
            requestsCount, messagesCount, communityCount, profileCount
        )
        
        requestsBadgeCount = requests
        messagesBadgeCount = messages
        communityBadgeCount = community
        profileBadgeCount = profile
        adminPanelBadgeCount = profile  // Same as profile badge for admins
        
        // Calculate total for app icon badge
        totalUnreadCount = requests + messages + community
        updateAppIconBadge(totalUnreadCount)
    }
    
    /// Update the app icon badge number
    private func updateAppIconBadge(_ count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = count
    }
    
    /// Clear Requests badge (called when navigating to Requests tab)
    func clearRequestsBadge() async {
        // Don't auto-clear all request notifications on tab view
        UserDefaults.standard.set(Date(), forKey: lastViewedRequestsKey)
        await refreshAllBadges()
    }
    
    /// Clear Messages badge (called when viewing a conversation)
    func clearMessagesBadge() async {
        // Badge is automatically cleared when messages are marked as read
        // Just refresh the count
        await refreshAllBadges()
    }
    
    /// Clear Community badge (called when viewing Community tab or a post)
    func clearCommunityBadge() async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            
            // Community notification types to clear
            let communityTypes: Set<NotificationType> = [
                .townHallPost, .townHallComment, .townHallReaction
            ]
            
            let communityNotificationIds = notifications
                .filter { !$0.read && communityTypes.contains($0.type) }
                .map { $0.id }
            
            for notificationId in communityNotificationIds {
                try? await notificationService.markAsRead(notificationId: notificationId)
            }
            
            await refreshAllBadges()
        } catch {
            print("⚠️ [BadgeCountManager] Error clearing community badge: \(error)")
        }
    }
    
    /// Clear Profile badge (called when approving/denying users)
    func clearProfileBadge() async {
        // Badge count will automatically update when pending users change
        await refreshAllBadges()
    }
    
    // MARK: - Private Methods
    
    /// Calculate Requests badge count
    /// Counts: new rides/favors posted + claim activity + Q&A + completion reminders
    private func calculateRequestsBadgeCount(userId: UUID) async -> Int {
        do {
            // Get unread notifications related to requests
            let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            
            // Request-related notification types
            let requestTypes: Set<NotificationType> = [
                .newRide, .newFavor,                    // New requests from others
                .rideClaimed, .rideUnclaimed,           // Claim status on user's requests
                .favorClaimed, .favorUnclaimed,
                .rideCompleted, .favorCompleted,        // Completion status
                .qaActivity, .qaQuestion, .qaAnswer,    // Q&A activity
                .completionReminder,                    // Reminder to mark as complete
                .reviewRequest, .reviewReminder         // Review prompts
            ]
            
            let requestNotificationCount = notifications
                .filter { !$0.read && requestTypes.contains($0.type) }
                .count
            
            return requestNotificationCount
        } catch {
            print("⚠️ [BadgeCountManager] Error calculating requests badge: \(error)")
            return 0
        }
    }
    
    /// Calculate Messages badge count
    /// Counts: unread conversations
    private func calculateMessagesBadgeCount(userId: UUID) async -> Int {
        do {
            let conversations = try await messageService.fetchConversations(userId: userId)
            // Sum up unread counts from all conversations
            let totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
            return totalUnread
        } catch {
            print("⚠️ [BadgeCountManager] Error calculating messages badge: \(error)")
            return 0
        }
    }
    
    /// Calculate Community badge count
    /// Counts: unread Town Hall notifications (posts, comments, reactions)
    private func calculateCommunityBadgeCount(userId: UUID) async -> Int {
        do {
            // Get unread notifications related to community/Town Hall
            let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            
            // Community notification types
            let communityTypes: Set<NotificationType> = [
                .townHallPost,      // New posts
                .townHallComment,   // Comments on posts
                .townHallReaction   // Reactions on posts
            ]
            
            let communityNotificationCount = notifications
                .filter { !$0.read && communityTypes.contains($0.type) }
                .count
            
            return communityNotificationCount
        } catch {
            print("⚠️ [BadgeCountManager] Error calculating community badge: \(error)")
            return 0
        }
    }
    
    /// Calculate Profile badge count (admin only)
    /// Counts: pending user approvals
    private func calculateProfileBadgeCount() async -> Int {
        guard let userId = authService.currentUserId,
              let profile = authService.currentProfile,
              profile.isAdmin else {
            return 0
        }
        
        do {
            let pendingUsers = try await adminService.fetchPendingUsers()
            return pendingUsers.count
        } catch {
            print("⚠️ [BadgeCountManager] Error calculating profile badge: \(error)")
            return 0
        }
    }
}

