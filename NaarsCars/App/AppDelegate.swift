//
//  AppDelegate.swift
//  NaarsCars
//
//  App delegate for push notification handling and Firebase initialization
//

import UIKit
import UserNotifications
import FirebaseCore
import Supabase

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // MARK: - Notification Action Identifiers
    
    static let completionReminderCategory = "COMPLETION_REMINDER"
    static let actionCompleteYes = "COMPLETE_YES"
    static let actionCompleteNo = "COMPLETE_NO"
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Firebase (must be called before any Firebase services are used)
        FirebaseApp.configure()
        print("🔥 [AppDelegate] Firebase configured")
        
        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Register actionable notification categories
        registerNotificationCategories()
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        // Handle deep link if app was opened via URL
        if let url = launchOptions?[.url] as? URL {
            handleURL(url)
        }
        
        return true
    }
    
    // MARK: - Notification Categories
    
    private func registerNotificationCategories() {
        // Completion Reminder Category with Yes/No actions
        let completeYesAction = UNNotificationAction(
            identifier: Self.actionCompleteYes,
            title: "Yes, Completed ✓",
            options: [.foreground]
        )
        
        let completeNoAction = UNNotificationAction(
            identifier: Self.actionCompleteNo,
            title: "Not Yet",
            options: []
        )
        
        let completionReminderCategory = UNNotificationCategory(
            identifier: Self.completionReminderCategory,
            actions: [completeYesAction, completeNoAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register all categories
        UNUserNotificationCenter.current().setNotificationCategories([
            completionReminderCategory
        ])
        
        print("📱 [AppDelegate] Registered notification categories")
    }
    
    // MARK: - URL Handling
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        handleURL(url)
        return true
    }
    
    private func handleURL(_ url: URL) {
        // Handle invite code deep links: https://naarscars.com/signup?code=CODE
        // This will be handled by SignupInviteCodeView's onOpenURL modifier
        print("🔗 [AppDelegate] Received URL: \(url.absoluteString)")
        
        // Post notification for signup view to handle
        if url.host == "naarscars.com" || url.host == "www.naarscars.com",
           url.path == "/signup" {
            NotificationCenter.default.post(
                name: NSNotification.Name("handleInviteCodeDeepLink"),
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
    
    // MARK: - Remote Notification Registration
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            if let userId = AuthService.shared.currentUserId {
                do {
                    try await PushNotificationService.shared.registerDeviceToken(
                        deviceToken: deviceToken,
                        userId: userId
                    )
                } catch {
                    print("🔴 [AppDelegate] Failed to register device token: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔴 [AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        // Handle actionable notification responses
        switch actionIdentifier {
        case Self.actionCompleteYes:
            // User tapped "Yes, Completed" - mark request as complete
            print("📱 [AppDelegate] User responded YES to completion reminder")
            handleCompletionResponse(userInfo: userInfo, completed: true)
            completionHandler()
            return
            
        case Self.actionCompleteNo:
            // User tapped "Not Yet" - snooze reminder for 1 hour
            print("📱 [AppDelegate] User responded NO to completion reminder")
            handleCompletionResponse(userInfo: userInfo, completed: false)
            completionHandler()
            return
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself - navigate to relevant screen
            break
            
        case UNNotificationDismissActionIdentifier:
            // User dismissed the notification
            completionHandler()
            return
            
        default:
            break
        }
        
        // Handle deep link navigation for default tap
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        handleDeepLink(deepLink)
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // MARK: - Completion Reminder Response
    
    private func handleCompletionResponse(userInfo: [AnyHashable: Any], completed: Bool) {
        guard let reminderId = userInfo["reminder_id"] as? String else {
            print("⚠️ [AppDelegate] Missing reminder_id in notification")
            return
        }
        
        Task {
            do {
                // Call the database function via Supabase RPC
                let params: [String: AnyCodable] = [
                    "p_reminder_id": AnyCodable(reminderId),
                    "p_completed": AnyCodable(completed)
                ]
                
                let response = try await SupabaseService.shared.client
                    .rpc("handle_completion_response", params: params)
                    .execute()
                
                print("✅ [AppDelegate] Completion response handled: \(completed ? "COMPLETED" : "SNOOZED")")
                
                // If completed, navigate to review screen
                if completed {
                    if let rideId = userInfo["ride_id"] as? String, let uuid = UUID(uuidString: rideId) {
                        // Navigate to ride detail for review
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("navigateToRide"),
                                object: nil,
                                userInfo: ["rideId": uuid, "showReview": true]
                            )
                        }
                    } else if let favorId = userInfo["favor_id"] as? String, let uuid = UUID(uuidString: favorId) {
                        // Navigate to favor detail for review
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("navigateToFavor"),
                                object: nil,
                                userInfo: ["favorId": uuid, "showReview": true]
                            )
                        }
                    }
                }
            } catch {
                print("🔴 [AppDelegate] Failed to handle completion response: \(error)")
            }
        }
    }
    
    // MARK: - Deep Link Handling
    
    private func handleDeepLink(_ deepLink: DeepLink) {
        // Use NavigationCoordinator to handle deep links
        // This ensures consistent navigation behavior across the app
        Task { @MainActor in
            NavigationCoordinator.shared.navigate(to: deepLink)
        }
        print("🔗 [AppDelegate] Handling deep link: \(deepLink)")
    }
}



