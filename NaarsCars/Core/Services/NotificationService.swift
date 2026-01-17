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
    private let cacheManager = CacheManager.shared
    private let requestDeduplicator = RequestDeduplicator()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Notifications
    
    /// Fetch all notifications for a user
    /// Uses request deduplication to prevent concurrent duplicate requests
    /// - Parameter userId: The user ID
    /// - Returns: Array of notifications ordered by pinned first, then createdAt
    /// - Throws: AppError if fetch fails
    func fetchNotifications(userId: UUID) async throws -> [AppNotification] {
        // Check cache first
        if let cached = await cacheManager.getCachedNotifications(userId: userId), !cached.isEmpty {
            print("✅ [NotificationService] Cache hit for notifications. Returning \(cached.count) items.")
            return cached
        }
        
        print("🔄 [NotificationService] Cache miss for notifications. Fetching from network...")
        
        // Use request deduplicator to prevent concurrent requests
        let key = "notifications_\(userId.uuidString)"
        
        return try await requestDeduplicator.fetch(key: key) {
            let response = try await self.supabase
                .from("notifications")
                .select("*")
                .eq("user_id", value: userId.uuidString)
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
                let notifications: [AppNotification] = try decoder.decode([AppNotification].self, from: response.data)
                
                // Cache results
                await self.cacheManager.cacheNotifications(userId: userId, notifications)
                
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
        
        // Invalidate cache
        if let userId = AuthService.shared.currentUserId {
            await cacheManager.invalidateNotifications(userId: userId)
        }
        
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
        
        // Invalidate cache
        await cacheManager.invalidateNotifications(userId: userId)
        
        print("✅ [NotificationService] Marked all notifications as read for user \(userId)")
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
        
        // Invalidate cache for this user
        await cacheManager.invalidateNotifications(userId: userId)
        
        print("✅ [NotificationService] Sent approval notification to user \(userId)")
    }
}



