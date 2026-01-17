//
//  BadgeCountManager.swift
//  NaarsCars
//
//  Manager for badge counts on tab bar icons
//

import Foundation
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
    
    /// Badge count for Requests tab
    @Published var requestsBadgeCount: Int = 0
    
    /// Badge count for Messages tab
    @Published var messagesBadgeCount: Int = 0
    
    /// Badge count for Community tab
    @Published var communityBadgeCount: Int = 0
    
    /// Badge count for Profile tab (admin only)
    @Published var profileBadgeCount: Int = 0
    
    // MARK: - Private Properties
    
    private let notificationService = NotificationService.shared
    private let messageService = MessageService.shared
    private let adminService = AdminService.shared
    private let townHallService = TownHallService.shared
    private let authService = AuthService.shared
    
    /// UserDefaults keys for last viewed timestamps
    private let lastViewedCommunityKey = "lastViewedCommunity"
    
    // MARK: - Initialization
    
    private init() {
        // Load initial badge counts when user is authenticated
        Task {
            await refreshAllBadges()
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
            return
        }
        
        // Calculate all badges in parallel
        async let requestsCount = calculateRequestsBadgeCount(userId: userId)
        async let messagesCount = calculateMessagesBadgeCount(userId: userId)
        async let communityCount = calculateCommunityBadgeCount()
        async let profileCount = calculateProfileBadgeCount()
        
        let (requests, messages, community, profile) = await (
            requestsCount, messagesCount, communityCount, profileCount
        )
        
        requestsBadgeCount = requests
        messagesBadgeCount = messages
        communityBadgeCount = community
        profileBadgeCount = profile
    }
    
    /// Clear Requests badge (called when navigating to Requests tab)
    func clearRequestsBadge() async {
        // Mark all request-related notifications as read
        guard let userId = authService.currentUserId else { return }
        
        do {
            // Mark all qaActivity notifications as read
            let notifications = try await notificationService.fetchNotifications(userId: userId)
            let requestNotificationIds = notifications
                .filter { !$0.read && ($0.type == .qaActivity) }
                .map { $0.id }
            
            for notificationId in requestNotificationIds {
                try? await notificationService.markAsRead(notificationId: notificationId)
            }
            
            await refreshAllBadges()
        } catch {
            print("⚠️ [BadgeCountManager] Error clearing requests badge: \(error)")
        }
    }
    
    /// Clear Messages badge (called when viewing a conversation)
    func clearMessagesBadge() async {
        // Badge is automatically cleared when messages are marked as read
        // Just refresh the count
        await refreshAllBadges()
    }
    
    /// Clear Community badge (called when viewing Community tab or a post)
    func clearCommunityBadge() {
        // Update last viewed timestamp
        UserDefaults.standard.set(Date(), forKey: lastViewedCommunityKey)
        
        // Refresh badge count
        Task {
            await refreshAllBadges()
        }
    }
    
    /// Clear Profile badge (called when approving/denying users)
    func clearProfileBadge() async {
        // Badge count will automatically update when pending users change
        await refreshAllBadges()
    }
    
    // MARK: - Private Methods
    
    /// Calculate Requests badge count
    /// Counts: new rides/favors posted + new questions/comments on user's requests
    private func calculateRequestsBadgeCount(userId: UUID) async -> Int {
        do {
            // Get unread notifications related to requests
            let notifications = try await notificationService.fetchNotifications(userId: userId)
            
            // Count unread qaActivity notifications (questions/comments on user's requests)
            let qaActivityCount = notifications
                .filter { !$0.read && $0.type == .qaActivity }
                .count
            
            // For now, we'll use qaActivity notifications as the main indicator
            // New rides/favors posted by others could be added as a separate notification type
            // or we could query the rides/favors table directly
            // For simplicity, we'll focus on qaActivity for now
            return qaActivityCount
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
    /// Counts: new posts/comments since last viewed
    private func calculateCommunityBadgeCount() async -> Int {
        // Get last viewed timestamp
        let lastViewed = UserDefaults.standard.object(forKey: lastViewedCommunityKey) as? Date ?? Date.distantPast
        
        do {
            // Count new posts since last viewed (limit to recent posts for performance)
            let posts = try await townHallService.fetchPosts(limit: 50)
            let newPostsCount = posts.filter { $0.createdAt > lastViewed }.count
            
            // Count new comments since last viewed on recent posts only
            // Fetch comments on posts created after last viewed, or posts with new comments
            var newCommentsCount = 0
            for post in posts {
                // Only check comments on posts that are new or might have new comments
                if post.createdAt > lastViewed || post.updatedAt > lastViewed {
                    let comments = try? await TownHallCommentService.shared.fetchComments(for: post.id)
                    if let comments = comments {
                        // Flatten nested comments to count all comments (including replies)
                        let allComments = flattenComments(comments)
                        newCommentsCount += allComments.filter { $0.createdAt > lastViewed }.count
                    }
                }
            }
            
            return newPostsCount + newCommentsCount
        } catch {
            print("⚠️ [BadgeCountManager] Error calculating community badge: \(error)")
            return 0
        }
    }
    
    /// Flatten nested comments to a single array
    private func flattenComments(_ comments: [TownHallComment]) -> [TownHallComment] {
        var result: [TownHallComment] = []
        for comment in comments {
            result.append(comment)
            if let replies = comment.replies {
                result.append(contentsOf: flattenComments(replies))
            }
        }
        return result
    }
    
    /// Calculate Profile badge count (admin only)
    /// Counts: pending user approvals
    private func calculateProfileBadgeCount() async -> Int {
        guard let _ = authService.currentUserId,
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

