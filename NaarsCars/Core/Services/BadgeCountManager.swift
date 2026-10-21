//
//  BadgeCountManager.swift
//  NaarsCars
//
//  Manager for badge counts on tab bar icons
//

import Foundation
import Observation
import UIKit
import Supabase
import PostgREST

/// Tab badge types
enum BadgeTab: String {
    case requests = "requests"
    case messages = "messages"
    case community = "community"
    case profile = "profile"
}

extension BadgeCountManager: BadgeCountManaging {
    var bellBadgeCount: Int { counts.bell }
}

/// Manager for badge counts on tab bar icons
/// Tracks unread notifications and new content for each tab
@MainActor
@Observable final class BadgeCountManager {

    // MARK: - Singleton

    static let shared = BadgeCountManager()

    // MARK: - Badge Counts

    /// All badge values coalesced into a single struct so that
    /// `refreshAllBadges()` emits only ONE `objectWillChange` per cycle.
    struct BadgeCounts: Equatable {
        var requests: Int = 0
        var messages: Int = 0
        var community: Int = 0
        var profile: Int = 0
        var adminPanel: Int = 0
        var bell: Int = 0
        var totalUnread: Int = 0
        /// Unread Town Hall count per community (`community_details`), positive totals only.
        /// Read by the Community tab's title menu for the communities that are not on screen.
        var communityUnreadById: [UUID: Int] = [:]

        /// The tab counts for one `get_badge_counts` payload. The Profile (and Admin Panel)
        /// badge is `pending_members_total`: pending rows in the communities the caller
        /// administers, counted by the server, so there is no second client-side path.
        static func makeCounts(from payload: BadgeCountsPayload) -> BadgeCounts {
            var counts = BadgeCounts()
            counts.requests = payload.requestsTotal
            counts.messages = payload.messagesTotal
            counts.community = payload.communityTotal
            counts.profile = payload.pendingMembersTotal ?? 0
            counts.adminPanel = counts.profile
            counts.bell = payload.bellTotal
            counts.totalUnread = payload.requestsTotal + payload.messagesTotal + payload.communityTotal
            var byId: [UUID: Int] = [:]
            for detail in payload.communityDetails ?? [] where detail.communityTotal > 0 {
                byId[detail.communityId] = detail.communityTotal
            }
            counts.communityUnreadById = byId
            return counts
        }
    }

    /// Notification types that make up the Community tab badge.
    static let communityBadgeTypes: Set<NotificationType> = [
        .townHallPost, .townHallComment, .townHallReaction
    ]

    /// The unread Town Hall notifications that opening the Community tab marks read: those of
    /// the visible community and those with no community. With no visible community (the
    /// community context has not loaded) every unread Town Hall row, as before Phase 2.
    static func communityNotificationIdsToClear(
        _ notifications: [AppNotification],
        visibleCommunityId: UUID?
    ) -> [UUID] {
        notifications
            .filter { notification in
                guard !notification.read, communityBadgeTypes.contains(notification.type) else { return false }
                guard let visibleCommunityId else { return true }
                return notification.communityId == nil || notification.communityId == visibleCommunityId
            }
            .map(\.id)
    }

    /// Whether opening the Community tab (or switching its community) can find a Town Hall row to
    /// mark read, judged from the server's counts: the visible community's `community_details`
    /// total, or rows with no community (`community_total` minus every community's total). With
    /// no visible community, any unread Town Hall row. Counts that are stale or not loaded yet
    /// always fetch. The counts only decide whether to fetch; no badge is computed here.
    static func communityClearNeedsFetch(
        _ counts: BadgeCounts,
        visibleCommunityId: UUID?,
        countsAreCurrent: Bool
    ) -> Bool {
        guard countsAreCurrent else { return true }
        guard counts.community > 0 else { return false }
        guard let visibleCommunityId else { return true }
        if (counts.communityUnreadById[visibleCommunityId] ?? 0) > 0 { return true }
        let labelled = counts.communityUnreadById.values.reduce(0, +)
        return counts.community > labelled
    }

    private(set) var counts = BadgeCounts()

    /// True when badge values are being served from cached/zero data due to RPC failure.
    private(set) var isBadgeStale: Bool = false

    // MARK: - Private Properties

    private let authService = AuthService.shared
    private let supabase = SupabaseService.shared.client

    private var deferredMessagesBadgeRefreshTask: Task<Void, Never>?

    /// Timestamp of last completed refresh
    private var lastRefreshTime: Date = .distantPast
    /// The counts came from a successful badge RPC this session (not the cached or zero fallback).
    private var badgeCountsAreCurrent: Bool {
        !isBadgeStale && lastRefreshTime != .distantPast
    }
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
        }
    }

    // MARK: - Public Methods

    /// Refresh all badge counts
    func refreshAllBadges(reason: String = "manual") async {
        await refreshAllBadges(reason: reason, bypassDebounce: false)
    }

    /// `bypassDebounce` is only for a refresh that follows this device's own server write
    /// (rows just marked read): a debounced skip would leave the counts showing those rows
    /// until the next push or safety poll. Push-driven refreshes keep the debounce. The one
    /// other use is the Community visit's decision refresh (`clearCommunityBadge`).
    private func refreshAllBadges(reason: String, bypassDebounce: Bool) async {
        guard let userId = authService.currentUserId else { return }

        // Simple debounce: skip if refreshed within the debounce window
        let elapsed = Date().timeIntervalSince(lastRefreshTime)
        guard bypassDebounce || elapsed >= Constants.Timing.badgeRefreshDebounce else { return }

        AppLogger.info("badges", "Refreshing badges (\(reason))")

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
                            conversationDetails: [],
                            pendingMembersTotal: nil,
                            communityDetails: nil,
                            total: nil
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
                        conversationDetails: [],
                        pendingMembersTotal: nil,
                        communityDetails: nil,
                        total: nil
                    )
                }
                isBadgeStale = true
            }

            lastRefreshTime = Date()

            // Build a single struct and assign once → one objectWillChange emission
            self.counts = BadgeCounts.makeCounts(from: counts)

            // Broadcast conversation-level unread counts to any active view models
            NotificationCenter.default.post(
                name: .conversationUnreadCountsUpdated,
                object: nil,
                userInfo: ["counts": counts.conversationDetails]
            )

            updateAppIconBadge(self.counts.totalUnread)

            AppLogger.info("badges", "Counts synced: requests=\(counts.requestsTotal), messages=\(counts.messagesTotal), community=\(counts.communityTotal), bell=\(counts.bellTotal)")
        } catch is CancellationError {
            return
        } catch let error as NSError where error.code == NSURLErrorCancelled {
            return
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

            var updated = counts
            updated.messages = max(updated.messages - previousConversationUnread, 0)
            updated.totalUnread = updated.requests + updated.messages + updated.community
            counts = updated
            updateAppIconBadge(counts.totalUnread)
            return
        }

        // Refresh all badges to ensure the tab bar badge is updated correctly
        await refreshAllBadges(reason: "clearMessagesBadge")
    }

    /// Clear Community badge (called when viewing Community tab or switching its community).
    /// Marks read only the visible community's Town Hall rows and rows with no community, so
    /// opening the tab does not clear communities the person did not look at.
    func clearCommunityBadge(visibleCommunityId: UUID?) async {
        guard let userId = authService.currentUserId else { return }

        // The badge RPC already says whether anything here is unread, so do not download the
        // bell list (up to `NotificationService.fetchLimit` rows) when nothing can be cleared.
        if !Self.communityClearNeedsFetch(counts, visibleCommunityId: visibleCommunityId, countsAreCurrent: badgeCountsAreCurrent) {
            // Decide again on fresh counts, so a row that arrived without a push (push off, or a Town
            // Hall push still batched) is cleared on this visit. Not debounced: an entry within 5 s of
            // another tab's refresh would otherwise decide on counts from before the row. One badge
            // RPC per Community entry or switch, user-driven, not a push burst.
            await refreshAllBadges(reason: "clearCommunityBadge.skipped", bypassDebounce: true)
            guard Self.communityClearNeedsFetch(counts, visibleCommunityId: visibleCommunityId, countsAreCurrent: badgeCountsAreCurrent) else { return }
        }

        do {
            // Use cached notifications (no forceRefresh) to avoid a full 30-day network fetch
            let notifications = try await NotificationService.shared.fetchNotifications(userId: userId, forceRefresh: false)

            let communityNotificationIds = Self.communityNotificationIdsToClear(
                notifications,
                visibleCommunityId: visibleCommunityId
            )

            guard !communityNotificationIds.isEmpty else {
                await refreshAllBadges(reason: "clearCommunityBadge.noop")
                return
            }

            // Mark the scoped community notifications as read in a single request
            do {
                try await NotificationService.shared.markAsRead(notificationIds: communityNotificationIds)
            } catch {
                AppLogger.warning("badges", "Failed to mark community notifications read: \(error)")
                await refreshAllBadges(reason: "clearCommunityBadge.markFailed")
                return
            }

            // The rows just changed on the server, so this refresh must not be skipped by the
            // debounce: opening the tab already refreshes, and a community switch within the
            // window would otherwise leave the tab badge and the menu's count for this
            // community stale until the next push or the safety poll.
            await refreshAllBadges(reason: "clearCommunityBadge", bypassDebounce: true)
        } catch {
            AppLogger.warning("badges", "Error clearing community badge: \(error)")
        }
    }

    /// Clear Profile badge (called when approving/denying users)
    func clearProfileBadge() async {
        // Badge count will automatically update when pending users change
        await refreshAllBadges(reason: "clearProfileBadge")
    }

    // MARK: - Deferred Refresh

    private func scheduleDeferredMessagesBadgeRefresh(reason: String) {
        deferredMessagesBadgeRefreshTask?.cancel()
        deferredMessagesBadgeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.badgeClearMessagesRefreshDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            await self.refreshAllBadges(reason: reason)
        }
    }

    // MARK: - Private Methods

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

    /// Per-community unread counts from `get_badge_counts` (`community_details`).
    struct CommunityCountDetail: Decodable, Equatable {
        let communityId: UUID
        let requestsTotal: Int
        let communityTotal: Int
        let bellTotal: Int
    }

    struct BadgeCountsPayload: Decodable {
        let requestsTotal: Int
        let messagesTotal: Int
        let communityTotal: Int
        let bellTotal: Int
        let requestDetails: [RequestCountDetail]
        let conversationDetails: [ConversationCountDetail]
        /// Additive multi-community keys; absent on a server without them. `makeCounts(from:)`
        /// reads `pendingMembersTotal` and `communityDetails`.
        let pendingMembersTotal: Int?
        let communityDetails: [CommunityCountDetail]?
        let total: Int?

        static func decode(_ data: Data) throws -> BadgeCountsPayload {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(BadgeCountsPayload.self, from: data)
        }
    }

    private func fetchBadgeCounts(includeDetails: Bool = false) async throws -> BadgeCountsPayload {
        let response = try await supabase
            .rpc("get_badge_counts", params: [
                "p_include_details": AnyCodable(includeDetails)
            ])
            .execute()

        return try BadgeCountsPayload.decode(response.data)
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

    // MARK: - Sign-out

    /// Zero everything a signed-out device should not keep showing: the tab counts, the cached
    /// fallback payload and the app icon badge. Called from the sign-out teardown, so a guest
    /// or the next account starts from nothing instead of the previous member's numbers
    /// (`lastKnownCounts` is the fallback when the badge RPC fails).
    func resetForSignOut() {
        counts = BadgeCounts()
        isBadgeStale = false
        lastKnownCounts = nil
        lastRefreshTime = .distantPast
        updateAppIconBadge(0)
    }

    // MARK: - Testing Helpers

    /// Reset all badge counts to zero. Intended for test tearDown only.
    func resetCountsForTesting() {
        counts = BadgeCounts()
        isBadgeStale = false
    }

    /// Seed counts without a network refresh. Intended for tests only.
    func setCountsForTesting(_ newCounts: BadgeCounts) {
        counts = newCounts
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
