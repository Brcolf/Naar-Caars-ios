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
@MainActor
final class NotificationService {
    
    // MARK: - Singleton
    
    static let shared = NotificationService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Notifications
    
    /// Fetch all notifications for a user
    /// - Parameter userId: The user ID
    /// - Returns: Array of notifications ordered by pinned first, then createdAt
    /// - Throws: AppError if fetch fails
    func fetchNotifications(userId: UUID, forceRefresh: Bool = false) async throws -> [AppNotification] {
        _ = forceRefresh
        let response = try await supabase
            .from("notifications")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .neq("type", value: NotificationType.message.rawValue)
            .neq("type", value: NotificationType.addedToConversation.rawValue)
            .order("pinned", ascending: false)
            .order("created_at", ascending: false)
            .execute()
        
        // Debug: Print raw response
        if let jsonString = String(data: response.data, encoding: .utf8) {
            print("📄 [NotificationService] Raw response: \(jsonString.prefix(500))")
        }
        
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
            
            print("✅ [NotificationService] Fetched \(notifications.count) notifications from network.")
            return notifications
        } catch {
            print("🔴 [NotificationService] Decoding error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("   Type mismatch: expected \(type), context: \(context)")
                case .valueNotFound(let type, let context):
                    print("   Value not found: \(type), context: \(context)")
                case .keyNotFound(let key, let context):
                    print("   Key not found: \(key.stringValue), context: \(context)")
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
            throw AppError.processingError("Failed to decode notifications: \(error.localizedDescription)")
        }
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
        
        print("✅ [NotificationService] Marked notification \(notificationId) as read")
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
        
        print("✅ [NotificationService] Marked all notifications as read for user \(userId)")
    }

    /// Mark all bell notifications (non-message) as read for a user
    /// - Parameter userId: The user ID
    /// - Throws: AppError if update fails
    func markAllBellNotificationsAsRead(userId: UUID) async throws {
        try await supabase
            .from("notifications")
            .update(["read": true])
            .eq("user_id", value: userId.uuidString)
            .neq("type", value: NotificationType.message.rawValue)
            .neq("type", value: NotificationType.addedToConversation.rawValue)
            .execute()
        
        print("✅ [NotificationService] Marked all bell notifications as read for user \(userId)")
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

            print("✅ [NotificationService] Marked \(updatedCount) request notifications read for \(requestType) \(requestId)")
            return updatedCount
        } catch {
            print("⚠️ [NotificationService] Failed to mark request notifications read: \(error)")
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
        
        print("✅ [NotificationService] Sent approval notification to user \(userId)")
    }
}



