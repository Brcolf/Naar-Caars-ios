//
//  PushNotificationService.swift
//  NaarsCars
//
//  Service for push notification operations
//

import Foundation
import UserNotifications
import Supabase

/// Service for push notification operations
/// Handles permission requests, token registration, and notification handling
@MainActor
final class PushNotificationService {
    
    // MARK: - Singleton
    
    static let shared = PushNotificationService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Permission
    
    /// Request push notification permission
    /// - Returns: True if permission granted, false otherwise
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("🔴 [PushNotificationService] Failed to request permission: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check current authorization status
    /// - Returns: Authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Device Token Registration
    
    /// Register device token with Supabase
    /// - Parameters:
    ///   - deviceToken: The APNs device token
    ///   - userId: The current user ID
    /// - Throws: AppError if registration fails
    func registerDeviceToken(deviceToken: Data, userId: UUID) async throws {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        // Get device identifier
        let deviceId = DeviceIdentifier.current
        
        // Check if token already exists for this device
        let existingResponse = try? await supabase
            .from("push_tokens")
            .select("id")
            .eq("device_id", value: deviceId)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        if existingResponse != nil {
            // Update existing token
            try await supabase
                .from("push_tokens")
                .update([
                    "token": AnyCodable(tokenString),
                    "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
                ])
                .eq("device_id", value: deviceId)
                .eq("user_id", value: userId.uuidString)
                .execute()
            
            print("✅ [PushNotificationService] Updated device token for user \(userId)")
        } else {
            // Insert new token
            try await supabase
                .from("push_tokens")
                .insert([
                    "user_id": AnyCodable(userId.uuidString),
                    "device_id": AnyCodable(deviceId),
                    "token": AnyCodable(tokenString),
                    "platform": AnyCodable("ios")
                ])
                .execute()
            
            print("✅ [PushNotificationService] Registered device token for user \(userId)")
        }
    }
    
    /// Remove device token (on logout)
    /// - Parameter userId: The user ID
    /// - Throws: AppError if removal fails
    func removeDeviceToken(userId: UUID) async throws {
        let deviceId = DeviceIdentifier.current
        
        try await supabase
            .from("push_tokens")
            .delete()
            .eq("device_id", value: deviceId)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        print("✅ [PushNotificationService] Removed device token for user \(userId)")
    }
    
    // MARK: - Local Notifications
    
    /// Show a local notification for a new message (when user is not viewing the conversation)
    /// - Parameters:
    ///   - senderName: Name of the message sender
    ///   - messagePreview: Preview of the message text
    ///   - conversationId: The conversation ID for deep linking
    func showLocalMessageNotification(senderName: String, messagePreview: String, conversationId: UUID) async {
        // Check if we have permission first
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            print("ℹ️ [PushNotificationService] Notification permission not granted, skipping local notification")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = messagePreview.count > 100 ? String(messagePreview.prefix(100)) + "..." : messagePreview
        content.sound = .default
        content.userInfo = [
            "type": "message",
            "conversation_id": conversationId.uuidString
        ]
        
        // Use a unique identifier based on conversation and timestamp to avoid duplicates
        let identifier = "message-\(conversationId.uuidString)-\(Date().timeIntervalSince1970)"
        
        // Show immediately (no trigger means immediate delivery)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        do {
            try await notificationCenter.add(request)
            print("✅ [PushNotificationService] Showed local notification for message from \(senderName)")
        } catch {
            print("🔴 [PushNotificationService] Failed to show local notification: \(error.localizedDescription)")
        }
    }
}



