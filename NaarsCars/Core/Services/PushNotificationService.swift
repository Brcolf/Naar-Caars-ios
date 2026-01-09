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
}



