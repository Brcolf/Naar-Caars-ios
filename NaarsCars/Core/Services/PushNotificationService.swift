//
//  PushNotificationService.swift
//  NaarsCars
//
//  Service for push notification operations
//

import Foundation
import UserNotifications
import UIKit
import Supabase
internal import Combine

/// Notification action identifiers
enum NotificationAction: String {
    case yesCompleted = "YES_COMPLETED"
    case noNotYet = "NO_NOT_YET"
}

/// Notification category identifiers
enum NotificationCategory: String {
    case completionReminder = "COMPLETION_REMINDER"
    case message = "MESSAGE"
    case newRequest = "NEW_REQUEST"
}

/// Service for push notification operations
/// Handles permission requests, token registration, and notification handling
@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = PushNotificationService()
    
    // MARK: - Published Properties
    
    @Published var isAuthorized: Bool = false
    @Published var pendingDeepLink: DeepLink?
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        setupNotificationCategories()
    }
    
    // MARK: - Setup
    
    /// Configure notification categories with actions
    private func setupNotificationCategories() {
        // Completion Reminder category with Yes/No actions
        let yesAction = UNNotificationAction(
            identifier: NotificationAction.yesCompleted.rawValue,
            title: "Yes, Completed",
            options: [.foreground]
        )
        
        let noAction = UNNotificationAction(
            identifier: NotificationAction.noNotYet.rawValue,
            title: "No, Not Yet",
            options: []
        )
        
        let completionCategory = UNNotificationCategory(
            identifier: NotificationCategory.completionReminder.rawValue,
            actions: [yesAction, noAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Message category (for future quick reply support)
        let messageCategory = UNNotificationCategory(
            identifier: NotificationCategory.message.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        // New Request category
        let newRequestCategory = UNNotificationCategory(
            identifier: NotificationCategory.newRequest.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            completionCategory,
            messageCategory,
            newRequestCategory
        ])
        
        print("✅ [PushNotificationService] Notification categories configured")
    }
    
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
    
    // MARK: - Completion Reminder Local Notifications
    
    /// Schedule a local notification to remind the claimer to confirm completion
    /// Called when a user claims a ride/favor - schedules for 1 hour after the request time
    /// - Parameters:
    ///   - reminderId: The completion reminder ID from the database
    ///   - requestTitle: The title/description of the request
    ///   - rideId: The ride ID (if applicable)
    ///   - favorId: The favor ID (if applicable)
    ///   - scheduledFor: When the notification should fire
    func scheduleCompletionReminder(
        reminderId: UUID,
        requestTitle: String,
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        scheduledFor: Date
    ) async {
        // Check if we have permission first
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            print("ℹ️ [PushNotificationService] Notification permission not granted, skipping completion reminder")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Is This Complete?"
        content.body = "Did you complete the \(requestTitle)?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.completionReminder.rawValue
        
        var userInfo: [String: Any] = [
            "type": "completion_reminder",
            "reminder_id": reminderId.uuidString,
            "actionable": true
        ]
        
        if let rideId = rideId {
            userInfo["ride_id"] = rideId.uuidString
        }
        if let favorId = favorId {
            userInfo["favor_id"] = favorId.uuidString
        }
        
        content.userInfo = userInfo
        
        // Calculate time interval
        let timeInterval = scheduledFor.timeIntervalSinceNow
        
        // If the scheduled time is in the past, schedule for 5 seconds from now
        let finalInterval = max(timeInterval, 5)
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: finalInterval, repeats: false)
        
        // Use reminder ID as the notification identifier for easy cancellation
        let identifier = "completion-reminder-\(reminderId.uuidString)"
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            let scheduledDate = Date().addingTimeInterval(finalInterval)
            print("✅ [PushNotificationService] Scheduled completion reminder for \(scheduledDate)")
        } catch {
            print("🔴 [PushNotificationService] Failed to schedule completion reminder: \(error.localizedDescription)")
        }
    }
    
    /// Cancel a scheduled completion reminder (e.g., when request is unclaimed or manually completed)
    /// - Parameter reminderId: The completion reminder ID
    func cancelCompletionReminder(reminderId: UUID) {
        let identifier = "completion-reminder-\(reminderId.uuidString)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        print("✅ [PushNotificationService] Cancelled completion reminder \(reminderId)")
    }
    
    /// Reschedule a completion reminder for 1 hour later (when user taps "No")
    /// - Parameters:
    ///   - reminderId: The completion reminder ID
    ///   - requestTitle: The title/description of the request
    ///   - rideId: The ride ID (if applicable)
    ///   - favorId: The favor ID (if applicable)
    func rescheduleCompletionReminder(
        reminderId: UUID,
        requestTitle: String,
        rideId: UUID? = nil,
        favorId: UUID? = nil
    ) async {
        // Cancel existing notification
        cancelCompletionReminder(reminderId: reminderId)
        
        // Schedule new one for 1 hour from now
        let oneHourFromNow = Date().addingTimeInterval(3600)
        await scheduleCompletionReminder(
            reminderId: reminderId,
            requestTitle: requestTitle,
            rideId: rideId,
            favorId: favorId,
            scheduledFor: oneHourFromNow
        )
    }
    
    // MARK: - Local Message Notifications
    
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
        content.categoryIdentifier = NotificationCategory.message.rawValue
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
    
    // MARK: - Notification Handling
    
    /// Handle notification tap and extract deep link
    /// - Parameter userInfo: The notification payload
    /// - Returns: DeepLink if parseable, nil otherwise
    func handleNotificationTap(userInfo: [AnyHashable: Any]) -> DeepLink? {
        guard let type = userInfo["type"] as? String else {
            print("⚠️ [PushNotificationService] No type in notification payload")
            return nil
        }
        
        print("📱 [PushNotificationService] Handling notification tap for type: \(type)")
        
        switch type {
        case "new_ride", "ride_claimed", "ride_unclaimed", "ride_completed", "ride_update":
            if let rideIdString = userInfo["ride_id"] as? String,
               let rideId = UUID(uuidString: rideIdString) {
                return .ride(id: rideId)
            }
            return .dashboard
            
        case "new_favor", "favor_claimed", "favor_unclaimed", "favor_completed", "favor_update":
            if let favorIdString = userInfo["favor_id"] as? String,
               let favorId = UUID(uuidString: favorIdString) {
                return .favor(id: favorId)
            }
            return .dashboard
            
        case "message", "added_to_conversation":
            if let conversationIdString = userInfo["conversation_id"] as? String,
               let conversationId = UUID(uuidString: conversationIdString) {
                return .conversation(id: conversationId)
            }
            
        case "qa_question", "qa_answer", "qa_activity":
            // Q&A notifications link to the request
            if let rideIdString = userInfo["ride_id"] as? String,
               let rideId = UUID(uuidString: rideIdString) {
                return .ride(id: rideId)
            } else if let favorIdString = userInfo["favor_id"] as? String,
                      let favorId = UUID(uuidString: favorIdString) {
                return .favor(id: favorId)
            }
            
        case "town_hall_post", "town_hall_comment", "town_hall_reaction":
            if let postIdString = userInfo["town_hall_post_id"] as? String,
               let postId = UUID(uuidString: postIdString) {
                return .townHallPost(id: postId)
            }
            return .townHall
            
        case "review_request", "review_received", "review_reminder":
            if let rideIdString = userInfo["ride_id"] as? String,
               let rideId = UUID(uuidString: rideIdString) {
                return .ride(id: rideId)
            } else if let favorIdString = userInfo["favor_id"] as? String,
                      let favorId = UUID(uuidString: favorIdString) {
                return .favor(id: favorId)
            }
            
        case "completion_reminder":
            // Link to the request for completion
            if let rideIdString = userInfo["ride_id"] as? String,
               let rideId = UUID(uuidString: rideIdString) {
                return .ride(id: rideId)
            } else if let favorIdString = userInfo["favor_id"] as? String,
                      let favorId = UUID(uuidString: favorIdString) {
                return .favor(id: favorId)
            }
            
        case "pending_approval":
            return .adminPanel
            
        case "user_approved":
            // User was approved - just open the app
            return .dashboard
            
        case "announcement", "admin_announcement", "broadcast":
            return .townHall
            
        default:
            print("⚠️ [PushNotificationService] Unknown notification type: \(type)")
            return .dashboard
        }
        
        return nil
    }
    
    /// Handle notification action (Yes/No buttons)
    /// - Parameters:
    ///   - actionIdentifier: The action that was tapped
    ///   - userInfo: The notification payload
    func handleNotificationAction(actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        print("📱 [PushNotificationService] Handling action: \(actionIdentifier)")
        
        guard let reminderIdString = userInfo["reminder_id"] as? String,
              let reminderId = UUID(uuidString: reminderIdString) else {
            print("⚠️ [PushNotificationService] No reminder_id in notification payload")
            return
        }
        
        let completed: Bool
        switch actionIdentifier {
        case NotificationAction.yesCompleted.rawValue:
            completed = true
        case NotificationAction.noNotYet.rawValue:
            completed = false
        default:
            print("⚠️ [PushNotificationService] Unknown action: \(actionIdentifier)")
            return
        }
        
        // Call RPC function to handle the response
        do {
            let params: [String: AnyCodable] = [
                "p_reminder_id": AnyCodable(reminderId.uuidString),
                "p_completed": AnyCodable(completed)
            ]
            
            let response = try await supabase
                .rpc("handle_completion_response", params: params)
                .execute()
            
            print("✅ [PushNotificationService] Completion response sent: \(completed ? "Yes" : "No")")
            
            if completed {
                // Refresh badge counts and post notification for review prompt
                await BadgeCountManager.shared.refreshAllBadges()
                
                // Post notification to show review prompt if applicable
                if let rideIdString = userInfo["ride_id"] as? String,
                   let rideId = UUID(uuidString: rideIdString) {
                    NotificationCenter.default.post(
                        name: .showReviewPrompt,
                        object: nil,
                        userInfo: ["ride_id": rideId]
                    )
                } else if let favorIdString = userInfo["favor_id"] as? String,
                          let favorId = UUID(uuidString: favorIdString) {
                    NotificationCenter.default.post(
                        name: .showReviewPrompt,
                        object: nil,
                        userInfo: ["favor_id": favorId]
                    )
                }
            } else {
                // User tapped "No" - schedule another reminder for 1 hour later
                // Build request title from userInfo
                var requestTitle = "your request"
                if userInfo["ride_id"] != nil {
                    requestTitle = "your ride"
                } else if userInfo["favor_id"] != nil {
                    requestTitle = "your favor"
                }
                
                await rescheduleCompletionReminder(
                    reminderId: reminderId,
                    requestTitle: requestTitle,
                    rideId: (userInfo["ride_id"] as? String).flatMap { UUID(uuidString: $0) },
                    favorId: (userInfo["favor_id"] as? String).flatMap { UUID(uuidString: $0) }
                )
            }
        } catch {
            print("🔴 [PushNotificationService] Failed to send completion response: \(error)")
        }
    }
    
    // MARK: - Badge Management
    
    /// Update the app icon badge count
    func updateBadgeCount() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            let unreadNotifications = try await NotificationService.shared.fetchUnreadCount(userId: userId)
            let conversations = try await MessageService.shared.fetchConversations(userId: userId)
            let unreadMessages = conversations.reduce(0) { $0 + $1.unreadCount }
            
            let total = unreadNotifications + unreadMessages
            
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = total
            }
            
            print("✅ [PushNotificationService] Updated badge count to \(total)")
        } catch {
            print("🔴 [PushNotificationService] Failed to update badge count: \(error)")
        }
    }
    
    /// Clear the app icon badge
    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showReviewPrompt = Notification.Name("showReviewPrompt")
}

// MARK: - Completion Response

/// Response from handle_completion_response RPC
struct CompletionResponse: Codable {
    let success: Bool
    let action: String?
    let error: String?
    let nextReminder: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case action
        case error
        case nextReminder = "next_reminder"
    }
}



