//
//  BadgeCountManager.swift
//  NaarsCars
//
//  Manager for badge counts on tab bar icons
//

import Foundation
import UIKit
internal import Combine
import Supabase
import PostgREST

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

    /// Badge count for Bell (non-message notifications)
    @Published var bellBadgeCount: Int = 0
    
    /// Total unread notification count (for app icon badge)
    @Published var totalUnreadCount: Int = 0
    
    // MARK: - Private Properties
    
    private let notificationService = NotificationService.shared
    private let conversationService = ConversationService.shared
    private let adminService = AdminService.shared
    private let townHallService = TownHallService.shared
    private let authService = AuthService.shared
    private let supabase = SupabaseService.shared.client
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()

    private let connectedPollingInterval: TimeInterval = 10
    private let disconnectedPollingInterval: TimeInterval = 90
    private var pollingTimer: Timer?
    private var pollingInterval: TimeInterval?
    
    /// UserDefaults keys for last viewed timestamps
    private let lastViewedCommunityKey = "lastViewedCommunity"
    private let lastViewedRequestsKey = "lastViewedRequests"
    
    // MARK: - Initialization
    
    private init() {
        // Load initial badge counts when user is authenticated
        Task {
            await refreshAllBadges(reason: "init")
            updatePollingInterval(reason: "init")
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
                await self?.refreshAllBadges(reason: "didBecomeActive")
                self?.updatePollingInterval(reason: "didBecomeActive")
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPolling(reason: "didEnterBackground")
        }

        realtimeManager.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePollingInterval(reason: "realtimeStatusChanged")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Refresh all badge counts
    func refreshAllBadges(reason: String = "manual") async {
        guard let userId = authService.currentUserId else {
            // ...
            return
        }

        AppLogger.info("badges", "Refreshing badges (\(reason))")
        async let profileCount = calculateProfileBadgeCount()

        do {
            // Always include details to update conversation-level unread counts
            let counts = try await fetchBadgeCounts(includeDetails: true)
            let profile = await profileCount

            requestsBadgeCount = counts.requestsTotal
            messagesBadgeCount = counts.messagesTotal
            communityBadgeCount = counts.communityTotal
            profileBadgeCount = profile
            adminPanelBadgeCount = profile  // Same as profile badge for admins
            bellBadgeCount = counts.bellTotal

            // Broadcast conversation-level unread counts to any active view models
            NotificationCenter.default.post(
                name: .conversationUnreadCountsUpdated,
                object: nil,
                userInfo: ["counts": counts.conversationDetails]
            )

            // Calculate total for app icon badge
            totalUnreadCount = counts.requestsTotal + counts.messagesTotal + counts.communityTotal
            updateAppIconBadge(totalUnreadCount)

            AppLogger.info("badges", "Counts synced: requests=\(counts.requestsTotal), messages=\(counts.messagesTotal), community=\(counts.communityTotal), bell=\(counts.bellTotal)")
        } catch {
            AppLogger.error("badges", "Failed to refresh badge counts (\(reason)): \(error)")
        }
    }
    
    /// Update the app icon badge number
    private func updateAppIconBadge(_ count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = count
    }
    
    /// Clear Requests badge (called when navigating to Requests tab)
    func clearRequestsBadge() async {
        // Don't auto-clear all request notifications on tab view
        UserDefaults.standard.set(Date(), forKey: lastViewedRequestsKey)
        await refreshAllBadges(reason: "clearRequestsBadge")
    }
    
    /// Clear Messages badge (called when viewing a conversation)
    func clearMessagesBadge(for conversationId: UUID? = nil) async {
        if let conversationId = conversationId {
            // Optimistically clear the unread count for this specific conversation
            // This ensures the badge disappears immediately when returning to the list
            NotificationCenter.default.post(
                name: .conversationUnreadCountsUpdated,
                object: nil,
                userInfo: ["counts": [ConversationCountDetail(conversationId: conversationId, unreadCount: 0)]]
            )
            
            // Also update the local SwiftData store immediately
            if let sdConv = try? await MessagingRepository.shared.fetchSDConversation(id: conversationId) {
                sdConv.unreadCount = 0
                try? await MessagingRepository.shared.save()
            }
        }
        
        // Refresh all badges to ensure the tab bar badge is updated correctly
        await refreshAllBadges(reason: "clearMessagesBadge")
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
            
            await refreshAllBadges(reason: "clearCommunityBadge")
        } catch {
            AppLogger.warning("badges", "Error clearing community badge: \(error)")
        }
    }
    
    /// Clear Profile badge (called when approving/denying users)
    func clearProfileBadge() async {
        // Badge count will automatically update when pending users change
        await refreshAllBadges(reason: "clearProfileBadge")
    }

    // MARK: - Polling

    private func updatePollingInterval(reason: String) {
        guard authService.currentUserId != nil else {
            stopPolling(reason: "notAuthenticated")
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            stopPolling(reason: "appInactive")
            return
        }

        let interval = realtimeManager.isConnected ? connectedPollingInterval : disconnectedPollingInterval
        guard pollingInterval != interval else { return }

        pollingInterval = interval
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAllBadges(reason: "polling")
            }
        }

        let status = realtimeManager.isConnected ? "connected" : "disconnected"
        AppLogger.info("badges", "Polling every \(Int(interval))s (\(status), \(reason))")
    }

    private func stopPolling(reason: String) {
        pollingTimer?.invalidate()
        pollingTimer = nil
        pollingInterval = nil
        AppLogger.info("badges", "Polling stopped (\(reason))")
    }
    
    // MARK: - Private Methods
    
    /// Calculate Requests badge count
    /// Counts: new rides/favors posted + claim activity + Q&A + completion reminders
    private func calculateRequestsBadgeCount(userId: UUID) async -> Int {
        do {
            // Get unread notifications related to requests
            let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            let requestKeys = NotificationGrouping.unreadRequestKeys(from: notifications)
            return requestKeys.count
        } catch {
            AppLogger.warning("badges", "Error calculating requests badge: \(error)")
            return 0
        }
    }
    
    /// Calculate Messages badge count
    /// Counts: unread conversations
    private func calculateMessagesBadgeCount(userId: UUID) async -> Int {
        do {
            let conversations = try await conversationService.fetchConversations(userId: userId)
            // Sum up unread counts from all conversations
            let totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
            return totalUnread
        } catch {
            AppLogger.warning("badges", "Error calculating messages badge: \(error)")
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
            AppLogger.warning("badges", "Error calculating community badge: \(error)")
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
            AppLogger.warning("badges", "Error calculating profile badge: \(error)")
            return 0
        }
    }

    /// Calculate Bell badge count
    /// Counts: unread grouped bell-feed notifications (non-message)
    private func calculateBellBadgeCount(userId: UUID) async -> Int {
        do {
            let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            let groups = NotificationGrouping.groupBellNotifications(from: notifications)
            let unreadGroups = groups.filter { $0.hasUnread }.count
            return unreadGroups
        } catch {
            AppLogger.warning("badges", "Error calculating bell badge: \(error)")
            return 0
        }
    }

    // MARK: - Authoritative Counts RPC

    struct RequestCountDetail: Decodable {
        let requestType: String
        let requestId: UUID
        let unreadCount: Int
    }

    struct ConversationCountDetail: Decodable {
        let conversationId: UUID
        let unreadCount: Int
    }

    private struct BadgeCountsPayload: Decodable {
        let requestsTotal: Int
        let messagesTotal: Int
        let communityTotal: Int
        let bellTotal: Int
        let requestDetails: [RequestCountDetail]
        let conversationDetails: [ConversationCountDetail]
    }

    private func fetchBadgeCounts(includeDetails: Bool = false) async throws -> BadgeCountsPayload {
        let response = try await supabase
            .rpc("get_badge_counts", params: [
                "p_include_details": AnyCodable(includeDetails)
            ])
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BadgeCountsPayload.self, from: response.data)
    }

    // MARK: - Debug Helpers

    func fetchBadgeCountsPayload(includeDetails: Bool = true) async throws -> String {
        let response = try await supabase
            .rpc("get_badge_counts", params: [
                "p_include_details": AnyCodable(includeDetails)
            ])
            .execute()

        let jsonObject = try JSONSerialization.jsonObject(with: response.data, options: [])
        let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
        return String(data: prettyData, encoding: .utf8) ?? ""
    }
}


