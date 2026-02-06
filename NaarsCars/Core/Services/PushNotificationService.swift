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
import os
internal import Combine

/// Notification action identifiers
/// IMPORTANT: These must match AppDelegate's action identifiers for response handling
enum NotificationAction: String {
    case yesCompleted = "COMPLETE_YES"
    case noNotYet = "COMPLETE_NO"
    case reply = "MESSAGE_REPLY"
    case markRead = "MESSAGE_MARK_READ"
    case viewRequest = "VIEW_REQUEST"
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
    private let tokenStorageKey = "apns_device_token"
    private let lastRegisteredTokenKey = "apns_last_registered_token"
    private let tokenUserIdKey = "apns_device_token_user_id"
    private let lastPushPayloadKey = "apns_last_push_payload"
    
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
            options: []
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
        
        // Message category with quick-reply and mark-read actions
        let replyAction = UNTextInputNotificationAction(
            identifier: NotificationAction.reply.rawValue,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a reply…"
        )
        
        let markReadAction = UNNotificationAction(
            identifier: NotificationAction.markRead.rawValue,
            title: "Mark as Read",
            options: []
        )
        
        let messageCategory = UNNotificationCategory(
            identifier: NotificationCategory.message.rawValue,
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: []
        )
        
        // New Request category with view action
        let viewRequestAction = UNNotificationAction(
            identifier: NotificationAction.viewRequest.rawValue,
            title: "View Details",
            options: [.foreground]
        )
        
        let newRequestCategory = UNNotificationCategory(
            identifier: NotificationCategory.newRequest.rawValue,
            actions: [viewRequestAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            completionCategory,
            messageCategory,
            newRequestCategory
        ])
        
        AppLogger.info("push", "Notification categories configured")
    }
    
    // MARK: - Permission
    
    /// Request push notification permission
    /// - Returns: True if permission granted, false otherwise
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            Log.push("Notification permission request result: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            Log.push("Failed to request notification permission: \(error.localizedDescription)", type: .error)
            return false
        }
    }
    
    /// Check current authorization status
    /// - Returns: Authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        Log.push("Notification authorization status: \(settings.authorizationStatus.rawValue)")
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
        try await registerDeviceToken(tokenString: tokenString, userId: userId)
    }
    
    private func registerDeviceToken(tokenString: String, userId: UUID) async throws {
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
            
            AppLogger.info("push", "Updated device token for user \(userId)")
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
            
            AppLogger.info("push", "Registered device token for user \(userId)")
        }

        // Record last registered state for re-registration checks
        UserDefaults.standard.set(tokenString, forKey: lastRegisteredTokenKey)
        UserDefaults.standard.set(userId.uuidString, forKey: tokenUserIdKey)
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
        
        AppLogger.info("push", "Removed device token for user \(userId)")
    }

    /// Store the latest APNs device token locally for later registration
    func storeDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(tokenString, forKey: tokenStorageKey)
        Log.push("Stored APNs token locally: \(tokenString.prefix(12))...")
    }

    /// Register a locally stored token if needed (user changed or token updated)
    func registerStoredDeviceTokenIfNeeded(userId: UUID) async {
        guard let tokenString = UserDefaults.standard.string(forKey: tokenStorageKey) else {
            Log.push("No stored APNs token to register for user \(userId)")
            return
        }

        let lastRegisteredToken = UserDefaults.standard.string(forKey: lastRegisteredTokenKey)
        let lastRegisteredUserId = UserDefaults.standard.string(forKey: tokenUserIdKey)

        if lastRegisteredToken == tokenString && lastRegisteredUserId == userId.uuidString {
            Log.push("APNs token already registered for user \(userId)")
            return
        }

        do {
            try await registerDeviceToken(tokenString: tokenString, userId: userId)
        } catch {
            Log.push("Failed to register stored APNs token: \(error.localizedDescription)", type: .error)
        }
    }

    /// Clear last registered token state on sign out
    func clearRegisteredTokenState() {
        UserDefaults.standard.removeObject(forKey: lastRegisteredTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenUserIdKey)
    }

    /// Persist the last push payload for diagnostics
    func recordLastPushPayload(_ userInfo: [AnyHashable: Any]) {
        let payload: [String: Any] = userInfo.reduce(into: [:]) { result, entry in
            result[String(describing: entry.key)] = entry.value
        }

        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            UserDefaults.standard.set(data, forKey: lastPushPayloadKey)
        } else {
            UserDefaults.standard.set(String(describing: payload), forKey: lastPushPayloadKey)
        }
    }

    /// Read the last push payload for diagnostics
    func lastPushPayloadDescription() -> String? {
        if let data = UserDefaults.standard.data(forKey: lastPushPayloadKey),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return UserDefaults.standard.string(forKey: lastPushPayloadKey)
    }

    /// Read the stored APNs token for diagnostics
    func storedDeviceTokenString() -> String? {
        UserDefaults.standard.string(forKey: tokenStorageKey)
    }
    
    // MARK: - Local Notifications
    //
    // Note on notification_id: Local notifications (completion reminders, message
    // banners) do not carry a server-side notification_id because the local
    // notification is scheduled independently of the notifications table row.
    // This means tapping a local notification cannot directly mark the server
    // row as read via notification_id. This is mitigated by:
    //   - Completion reminders: handled via reminder_id and the
    //     handle_completion_response RPC, which manages state independently.
    //   - Message banners: navigating to the conversation marks messages as read,
    //     and get_badge_counts auto-cleans stale message notification rows.
    //
    // The same applies to message pushes from send-message-push, which don't
    // include notification_id. Navigation to the conversation handles cleanup.
    
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
            AppLogger.warning("push", "Notification permission not granted, skipping completion reminder")
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
            AppLogger.info("push", "Scheduled completion reminder for \(scheduledDate)")
        } catch {
            AppLogger.error("push", "Failed to schedule completion reminder: \(error.localizedDescription)")
        }
    }
    
    /// Cancel a scheduled completion reminder (e.g., when request is unclaimed or manually completed)
    /// - Parameter reminderId: The completion reminder ID
    func cancelCompletionReminder(reminderId: UUID) {
        let identifier = "completion-reminder-\(reminderId.uuidString)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        AppLogger.info("push", "Cancelled completion reminder \(reminderId)")
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
            AppLogger.warning("push", "Notification permission not granted, skipping local notification")
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
            AppLogger.info("push", "Showed local notification for message from \(senderName)")
        } catch {
            AppLogger.error("push", "Failed to show local notification: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Notification Handling
    
    /// Handle notification tap and extract deep link
    /// - Parameter userInfo: The notification payload
    /// - Returns: DeepLink if parseable, nil otherwise
    func handleNotificationTap(userInfo: [AnyHashable: Any]) -> DeepLink? {
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        if case .unknown = deepLink {
            AppLogger.warning("push", "Unknown deep link from payload")
            return nil
        }
        return deepLink
    }
    
    /// Handle notification action (Yes/No buttons)
    /// - Parameters:
    ///   - actionIdentifier: The action that was tapped
    ///   - userInfo: The notification payload
    func handleNotificationAction(actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        AppLogger.info("push", "Handling action: \(actionIdentifier)")

        if let notificationIdString = userInfo["notification_id"] as? String,
           let notificationId = UUID(uuidString: notificationIdString) {
            try? await NotificationService.shared.markAsRead(notificationId: notificationId)
        }
        
        guard let reminderIdString = userInfo["reminder_id"] as? String,
              let reminderId = UUID(uuidString: reminderIdString) else {
            AppLogger.warning("push", "No reminder_id in notification payload")
            return
        }
        
        let completed: Bool
        switch actionIdentifier {
        case NotificationAction.yesCompleted.rawValue:
            completed = true
        case NotificationAction.noNotYet.rawValue:
            completed = false
        default:
            AppLogger.warning("push", "Unknown action: \(actionIdentifier)")
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
            
            AppLogger.info("push", "Completion response sent: \(completed ? "Yes" : "No")")
            
            if completed {
                // Refresh badge counts and post notification for review prompt
                await BadgeCountManager.shared.refreshAllBadges()
                
                // Post notification to show review prompt if applicable
                if let rideIdString = userInfo["ride_id"] as? String,
                   let rideId = UUID(uuidString: rideIdString) {
                    NotificationCenter.default.post(
                        name: .showReviewPrompt,
                        object: nil,
                        userInfo: ["rideId": rideId]
                    )
                } else if let favorIdString = userInfo["favor_id"] as? String,
                          let favorId = UUID(uuidString: favorIdString) {
                    NotificationCenter.default.post(
                        name: .showReviewPrompt,
                        object: nil,
                        userInfo: ["favorId": favorId]
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
            AppLogger.error("push", "Failed to send completion response: \(error)")
        }
    }
    
    // MARK: - Message Quick-Reply
    
    /// Handle quick-reply action from a message notification
    /// - Parameters:
    ///   - replyText: The text the user typed in the notification reply field
    ///   - userInfo: The notification payload (must contain conversation_id)
    func handleMessageReply(replyText: String, userInfo: [AnyHashable: Any]) async {
        guard let conversationIdString = userInfo["conversation_id"] as? String,
              let conversationId = UUID(uuidString: conversationIdString),
              let userId = AuthService.shared.currentUserId else {
            Log.push("Missing conversation_id or user for quick reply", type: .error)
            return
        }
        
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        do {
            _ = try await MessageService.shared.sendMessage(
                conversationId: conversationId,
                fromId: userId,
                text: trimmed
            )
            Log.push("Quick reply sent to conversation \(conversationId)")
        } catch {
            Log.push("Quick reply failed: \(error.localizedDescription)", type: .error)
        }
    }
    
    /// Handle mark-as-read action from a message notification
    /// - Parameter userInfo: The notification payload (must contain conversation_id)
    func handleMessageMarkRead(userInfo: [AnyHashable: Any]) async {
        guard let conversationIdString = userInfo["conversation_id"] as? String,
              let conversationId = UUID(uuidString: conversationIdString),
              let userId = AuthService.shared.currentUserId else {
            Log.push("Missing conversation_id or user for mark-read", type: .error)
            return
        }
        
        do {
            try await MessageService.shared.markAsRead(
                conversationId: conversationId,
                userId: userId
            )
            await BadgeCountManager.shared.refreshAllBadges(reason: "messageMarkedReadFromNotification")
            Log.push("Marked conversation \(conversationId) as read from notification")
        } catch {
            Log.push("Mark-read from notification failed: \(error.localizedDescription)", type: .error)
        }
    }
    
    // MARK: - Badge Management
    
    /// Update the app icon badge count
    func updateBadgeCount() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            let unreadNotifications = try await NotificationService.shared.fetchUnreadCount(userId: userId)
            let conversations = try await ConversationService.shared.fetchConversations(userId: userId)
            let unreadMessages = conversations.reduce(0) { $0 + $1.unreadCount }
            
            let total = unreadNotifications + unreadMessages
            
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = total
            }
            
            AppLogger.info("push", "Updated badge count to \(total)")
        } catch {
            AppLogger.error("push", "Failed to update badge count: \(error)")
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
    static let showCompletionPrompt = Notification.Name("showCompletionPrompt")
    static let dismissNotificationsSurface = Notification.Name("dismissNotificationsSurface")
    static let conversationUnreadCountsUpdated = Notification.Name("conversationUnreadCountsUpdated")
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



