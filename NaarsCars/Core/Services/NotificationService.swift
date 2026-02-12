//
//  NotificationService.swift
//  NaarsCars
//
//  Service for in-app notification operations
//

import Foundation
import Supabase

/// Service for in-app notification operations
/// Handles fetching, marking as read, and managing notifications
final class NotificationService {
    
    // MARK: - Singleton
    
    static let shared = NotificationService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private var cachedNotificationsByUser: [UUID: (fetchedAt: Date, notifications: [AppNotification])] = [:]
    private var inFlightFetchesByUser: [UUID: Task<[AppNotification], Error>] = [:]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Notifications
    
    /// Fetch all notifications for a user
    /// - Parameter userId: The user ID
    /// - Returns: Array of notifications ordered by pinned first, then createdAt
    /// - Throws: AppError if fetch fails
    /// Notifications older than this are not fetched from the server.
    /// Unread notifications are always relevant, but we rely on the server
    /// returning recent rows plus any unread ones. 30 days is a generous
    /// window that keeps the payload small while covering all realistic cases.
    private static let fetchHorizonDays: Int = 30

    func fetchNotifications(userId: UUID, forceRefresh: Bool = false) async throws -> [AppNotification] {
        if let inFlightTask = inFlightFetchesByUser[userId] {
            return try await inFlightTask.value
        }

        if let cached = cachedNotificationsByUser[userId] {
            let age = Date().timeIntervalSince(cached.fetchedAt)
            let coalesceWindow = forceRefresh
                ? Constants.Timing.notificationsForceRefreshCoalesceWindow
                : Constants.Timing.notificationsFetchCoalesceWindow
            if age <= coalesceWindow {
                return cached.notifications
            }
        }

        let task = Task { [self] in
            try await self.performNetworkNotificationFetch(userId: userId)
        }
        inFlightFetchesByUser[userId] = task

        do {
            let notifications = try await task.value
            cachedNotificationsByUser[userId] = (fetchedAt: Date(), notifications: notifications)
            inFlightFetchesByUser.removeValue(forKey: userId)
            return notifications
        } catch {
            inFlightFetchesByUser.removeValue(forKey: userId)
            if !forceRefresh, let cached = cachedNotificationsByUser[userId] {
                return cached.notifications
            }
            throw error
        }
    }

    private func performNetworkNotificationFetch(userId: UUID) async throws -> [AppNotification] {
        let horizon = Calendar.current.date(byAdding: .day, value: -Self.fetchHorizonDays, to: Date()) ?? Date()
        let horizonString = ISO8601DateFormatter().string(from: horizon)

        let response = try await supabase
            .from("notifications")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .neq("type", value: NotificationType.message.rawValue)
            .neq("type", value: NotificationType.addedToConversation.rawValue)
            .or("read.eq.false,created_at.gte.\(horizonString)")
            .order("pinned", ascending: false)
            .order("created_at", ascending: false)
            .execute()
        
#if DEBUG
        // Verbose payload logging is opt-in in debug to avoid UI/perf noise.
        if FeatureFlags.verbosePerformanceLogsEnabled,
           let jsonString = String(data: response.data, encoding: .utf8) {
            AppLogger.info("notifications", "Raw response: \(jsonString.prefix(500))")
        }
#endif
        
        // Configure decoder for date format (Supabase uses ISO8601 with fractional seconds)
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // Try without fractional seconds
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        
        do {
            let decoded: [AppNotification] = try decoder.decode([AppNotification].self, from: response.data)
            let notifications = NotificationGrouping.filterBellNotifications(from: decoded)
            
            AppLogger.info("notifications", "Fetched \(notifications.count) notifications from network")
            return notifications
        } catch {
            AppLogger.error("notifications", "Decoding error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    AppLogger.error("notifications", "Type mismatch: expected \(type), context: \(context)")
                case .valueNotFound(let type, let context):
                    AppLogger.error("notifications", "Value not found: \(type), context: \(context)")
                case .keyNotFound(let key, let context):
                    AppLogger.error("notifications", "Key not found: \(key.stringValue), context: \(context)")
                case .dataCorrupted(let context):
                    AppLogger.error("notifications", "Data corrupted: \(context)")
                @unknown default:
                    AppLogger.error("notifications", "Unknown decoding error")
                }
            }
            throw AppError.processingError("Failed to decode notifications: \(error.localizedDescription)")
        }
    }

    private func invalidateCachedNotifications(for userId: UUID? = nil) {
        if let userId {
            cachedNotificationsByUser.removeValue(forKey: userId)
            inFlightFetchesByUser[userId]?.cancel()
            inFlightFetchesByUser.removeValue(forKey: userId)
            return
        }

        inFlightFetchesByUser.values.forEach { $0.cancel() }
        inFlightFetchesByUser.removeAll()
        cachedNotificationsByUser.removeAll()
    }
    
    /// Fetch unread count for a user
    /// - Parameter userId: The user ID
    /// - Returns: Unread notification count
    /// - Throws: AppError if fetch fails
    func fetchUnreadCount(userId: UUID) async throws -> Int {
        let response = try await supabase
            .from("notifications")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId.uuidString)
            .eq("read", value: false)
            .neq("type", value: NotificationType.message.rawValue)
            .neq("type", value: NotificationType.addedToConversation.rawValue)
            .execute()
        
        return response.count ?? 0
    }
    
    // MARK: - Mark as Read
    
    /// Mark a notification as read
    /// - Parameter notificationId: The notification ID
    /// - Throws: AppError if update fails
    func markAsRead(notificationId: UUID) async throws {
        try await supabase
            .from("notifications")
            .update(["read": true])
            .eq("id", value: notificationId.uuidString)
            .execute()
        
        invalidateCachedNotifications()
        AppLogger.info("notifications", "Marked notification \(notificationId) as read")
    }
    
    /// Mark all notifications as read for a user
    /// - Parameter userId: The user ID
    /// - Throws: AppError if update fails
    func markAllAsRead(userId: UUID) async throws {
        try await supabase
            .from("notifications")
            .update(["read": true])
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        invalidateCachedNotifications(for: userId)
        AppLogger.info("notifications", "Marked all notifications as read for user \(userId)")
    }

    /// Mark all bell notifications (non-message) as read for a user.
    /// Excludes actionable types (review requests, completion reminders) that
    /// require explicit user action before they should be dismissed.
    /// - Parameter userId: The user ID
    /// - Throws: AppError if update fails
    func markAllBellNotificationsAsRead(userId: UUID) async throws {
        try await supabase
            .from("notifications")
            .update(["read": true])
            .eq("user_id", value: userId.uuidString)
            .neq("type", value: NotificationType.message.rawValue)
            .neq("type", value: NotificationType.addedToConversation.rawValue)
            .neq("type", value: NotificationType.reviewRequest.rawValue)
            .neq("type", value: NotificationType.reviewReminder.rawValue)
            .neq("type", value: NotificationType.completionReminder.rawValue)
            .execute()
        
        invalidateCachedNotifications(for: userId)
        AppLogger.info("notifications", "Marked all bell notifications as read for user \(userId)")
    }

    /// Mark request-scoped notifications as read for the current user
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - notificationTypes: Optional subset of notification types to mark
    ///   - includeReviews: Whether to include review request/reminder notifications
    /// - Returns: Number of notifications updated
    func markRequestScopedRead(
        requestType: String,
        requestId: UUID,
        notificationTypes: [NotificationType]? = nil,
        includeReviews: Bool = false
    ) async -> Int {
        guard let userId = AuthService.shared.currentUserId else { return 0 }

        var params: [String: AnyCodable] = [
            "p_request_type": AnyCodable(requestType),
            "p_request_id": AnyCodable(requestId.uuidString),
            "p_include_reviews": AnyCodable(includeReviews)
        ]

        if let notificationTypes {
            // Format as Postgres array literal: {type1, type2}
            let typeStrings = notificationTypes.map { $0.rawValue }.joined(separator: ",")
            params["p_notification_types"] = AnyCodable("{\(typeStrings)}")
        } else {
            // Explicitly pass nil to let the RPC use its default array
            params["p_notification_types"] = AnyCodable(nil as String?)
        }

        do {
            let response = try await supabase
                .rpc("mark_request_notifications_read", params: params)
                .execute()

            let decoder = JSONDecoder()
            let updatedCount = try decoder.decode(Int.self, from: response.data)

            invalidateCachedNotifications(for: userId)
            AppLogger.info("notifications", "Marked \(updatedCount) request notifications read for \(requestType) \(requestId)")
            return updatedCount
        } catch {
            AppLogger.warning("notifications", "Failed to mark request notifications read: \(error)")
            return 0
        }
    }

    /// Mark review request notifications as read for a specific request
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    func markReviewRequestAsRead(requestType: String, requestId: UUID) async {
        let types: [NotificationType] = [.reviewRequest, .reviewReminder]
        _ = await markRequestScopedRead(
            requestType: requestType,
            requestId: requestId,
            notificationTypes: types
        )
    }
    
    // MARK: - Admin Operations
    
    /// Send approval notification to a newly approved user
    /// Uses database function to bypass RLS
    /// - Parameter userId: The user ID to send notification to
    /// - Throws: AppError if creation fails
    func sendApprovalNotification(to userId: UUID) async throws {
        // Use database function to bypass RLS (similar to broadcast notifications)
        // Capture value explicitly to avoid MainActor isolation
        let userIdValue = userId.uuidString
        
        // Wrap RPC call in Task.detached to avoid MainActor isolation issues
        let task = Task.detached(priority: .userInitiated) { [userIdValue] () async throws -> UUID in
            let params: [String: AnyCodable] = [
                "p_user_id": AnyCodable(userIdValue)
            ]
            let client = await SupabaseService.shared.client
            let response = try await client
                .rpc("send_approval_notification", params: params)
                .execute()
            let decoder = JSONDecoder()
            let notificationId = try decoder.decode(UUID.self, from: response.data)
            return notificationId
        }
        _ = try await task.value
        
        AppLogger.info("notifications", "Sent approval notification to user \(userId)")
    }
}

extension NotificationService: NotificationServiceProtocol {}
