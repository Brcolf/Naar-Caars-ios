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

extension BadgeCountManager: BadgeCountManaging {}

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

    /// True when badge values are being served from cached/zero data due to RPC failure.
    @Published private(set) var isBadgeStale: Bool = false
    
    // MARK: - Private Properties
    
    private let adminService = AdminService.shared
    private let authService = AuthService.shared
    private let supabase = SupabaseService.shared.client
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()

    private let connectedPollingInterval: TimeInterval = 30
    private let disconnectedPollingInterval: TimeInterval = 90
    private var pollingTimer: Timer?
    private var pollingInterval: TimeInterval?
    private var deferredMessagesBadgeRefreshTask: Task<Void, Never>?

    /// Debounce guard: true while a refresh is in-flight
    private var isRefreshing = false
    /// Minimum interval between refreshes (seconds)
    private let minRefreshInterval: TimeInterval = Constants.Timing.badgeRefreshMinInterval
    /// Timestamp of last completed refresh
    private var lastRefreshTime: Date = .distantPast
    /// Consecutive badge RPC failures
    private var badgeRpcFailureCount: Int = 0
    /// Backoff window when badge RPC is failing due schema/function issues
    private var badgeRpcBackoffUntil: Date?
    /// Last successful badge payload returned by RPC.
    private var lastKnownCounts: BadgeCountsPayload?
    
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
            // Defer to next run loop so the first frame after foreground isn't blocked (reduces freeze).
            DispatchQueue.main.async {
                Task { @MainActor [weak self] in
                    await self?.refreshAllBadges(reason: "didBecomeActive")
                    self?.updatePollingInterval(reason: "didBecomeActive")
                }
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
        guard let userId = authService.currentUserId else { return }

        // Debounce: skip if a refresh is already in-flight or was completed very recently
        guard !isRefreshing else { return }
        let elapsed = Date().timeIntervalSince(lastRefreshTime)
        guard elapsed >= minRefreshInterval else { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshTime = Date()
        }

        AppLogger.info("badges", "Refreshing badges (\(reason))")
        async let profileCount = calculateProfileBadgeCount()

        do {
            let counts: BadgeCountsPayload
            if shouldUseBadgeCountsRpc() {
                do {
                    // Always include details to update conversation-level unread counts.
                    counts = try await fetchBadgeCounts(includeDetails: true)
                    if badgeRpcFailureCount > 0 {
                        let recoveredAfterFailures = badgeRpcFailureCount
                        Task {
                            await PerformanceMonitor.shared.record(
                                operation: "badge_rpc_recovery",
                                duration: 0,
                                metadata: ["recovered_after_failures": recoveredAfterFailures]
                            )
                        }
                    }
                    resetBadgeRpcBackoff()
                    lastKnownCounts = counts
                    isBadgeStale = false
                } catch {
                    registerBadgeRpcFailure(error)
                    if FeatureFlags.badgeCountClientFallbackEnabled {
                        AppLogger.warning("badges", "Client fallback flag enabled but fallback computation has been removed; serving cached/zero badge counts")
                    }
                    if let cachedCounts = lastKnownCounts {
                        counts = cachedCounts
                    } else {
                        counts = BadgeCountsPayload(
                            requestsTotal: 0,
                            messagesTotal: 0,
                            communityTotal: 0,
                            bellTotal: 0,
                            requestDetails: [],
                            conversationDetails: []
                        )
                    }
                    isBadgeStale = true
                }
            } else {
                if let cachedCounts = lastKnownCounts {
                    counts = cachedCounts
                } else {
                    counts = BadgeCountsPayload(
                        requestsTotal: 0,
                        messagesTotal: 0,
                        communityTotal: 0,
                        bellTotal: 0,
                        requestDetails: [],
                        conversationDetails: []
                    )
                }
                isBadgeStale = true
            }

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
        } catch is CancellationError {
            _ = await profileCount
            return
        } catch let error as NSError where error.code == NSURLErrorCancelled {
            _ = await profileCount
            return
        } catch {
            // Await profileCount to prevent orphan cancellation of the async let
            _ = await profileCount
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
            var previousConversationUnread = 0
            if let sdConv = try? MessagingRepository.shared.fetchSDConversation(id: conversationId) {
                previousConversationUnread = sdConv.unreadCount
            }

            guard previousConversationUnread > 0 else {
                return
            }

            // Optimistically clear the unread count for this specific conversation
            // This ensures the badge disappears immediately when returning to the list
            NotificationCenter.default.post(
                name: .conversationUnreadCountsUpdated,
                object: nil,
                userInfo: ["counts": [ConversationCountDetail(conversationId: conversationId, unreadCount: 0)]]
            )
            
            // Also update the local SwiftData store immediately
            if let sdConv = try? MessagingRepository.shared.fetchSDConversation(id: conversationId) {
                sdConv.unreadCount = 0
                try? MessagingRepository.shared.save(changedConversationIds: Set([conversationId]))
            }

            messagesBadgeCount = max(messagesBadgeCount - previousConversationUnread, 0)
            totalUnreadCount = requestsBadgeCount + messagesBadgeCount + communityBadgeCount
            updateAppIconBadge(totalUnreadCount)
            return
        }
        
        // Refresh all badges to ensure the tab bar badge is updated correctly
        await refreshAllBadges(reason: "clearMessagesBadge")
    }
    
    /// Clear Community badge (called when viewing Community tab or a post)
    func clearCommunityBadge() async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            let notifications = try await NotificationService.shared.fetchNotifications(userId: userId, forceRefresh: true)
            
            // Community notification types to clear
            let communityTypes: Set<NotificationType> = [
                .townHallPost, .townHallComment, .townHallReaction
            ]
            
            let communityNotificationIds = notifications
                .filter { !$0.read && communityTypes.contains($0.type) }
                .map { $0.id }
            
            for notificationId in communityNotificationIds {
                try? await NotificationService.shared.markAsRead(notificationId: notificationId)
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

    private func scheduleDeferredMessagesBadgeRefresh(reason: String) {
        deferredMessagesBadgeRefreshTask?.cancel()
        deferredMessagesBadgeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.badgeClearMessagesRefreshDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            await self.refreshAllBadges(reason: reason)
        }
    }
    
    // MARK: - Private Methods
    
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
        } catch is CancellationError {
            return 0
        } catch let error as NSError where error.code == NSURLErrorCancelled {
            return 0
        } catch {
            AppLogger.warning("badges", "Error calculating profile badge: \(error)")
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

    private func shouldUseBadgeCountsRpc() -> Bool {
        guard let backoffUntil = badgeRpcBackoffUntil else { return true }
        return Date() >= backoffUntil
    }

    private func resetBadgeRpcBackoff() {
        badgeRpcFailureCount = 0
        badgeRpcBackoffUntil = nil
    }

    private func registerBadgeRpcFailure(_ error: Error) {
        badgeRpcFailureCount += 1

        let postgrestCode = (error as? PostgrestError)?.code ?? ""
        let description = error.localizedDescription.lowercased()
        let isSchemaOrFunctionIssue =
            postgrestCode == "42P01" || // relation does not exist
            postgrestCode == "42883" || // function does not exist
            postgrestCode == "42703" || // column does not exist
            description.contains("relation") ||
            description.contains("does not exist")

        let backoffSeconds: TimeInterval
        if isSchemaOrFunctionIssue {
            backoffSeconds = 5 * 60
        } else {
            let exponential = min(pow(2.0, Double(badgeRpcFailureCount - 1)) * 5.0, 120.0)
            backoffSeconds = exponential
        }

        badgeRpcBackoffUntil = Date().addingTimeInterval(backoffSeconds)
        Task {
            await PerformanceMonitor.shared.record(
                operation: "badge_rpc_failure",
                duration: 0,
                metadata: [
                    "error_code": postgrestCode,
                    "failure_count": badgeRpcFailureCount,
                    "backoff_seconds": Int(backoffSeconds)
                ]
            )
        }
        AppLogger.warning(
            "badges",
            "Badge RPC failed (code=\(postgrestCode)); using fallback counts for \(Int(backoffSeconds))s: \(error.localizedDescription)"
        )
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
