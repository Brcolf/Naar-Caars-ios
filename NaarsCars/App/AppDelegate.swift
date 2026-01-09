//
//  AppDelegate.swift
//  NaarsCars
//
//  App delegate for push notification handling
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        // Handle deep link if app was opened via URL
        if let url = launchOptions?[.url] as? URL {
            handleURL(url)
        }
        
        return true
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
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Handle deep link navigation
        handleDeepLink(deepLink)
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // MARK: - Deep Link Handling
    
    private func handleDeepLink(_ deepLink: DeepLink) {
        // Post notifications that views can listen to for navigation
        // Views use @State variables and navigationDestination modifiers to handle navigation
        switch deepLink {
        case .ride(let id):
            print("🔗 [AppDelegate] Navigate to ride: \(id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToRide"),
                object: nil,
                userInfo: ["rideId": id]
            )
            
        case .favor(let id):
            print("🔗 [AppDelegate] Navigate to favor: \(id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToFavor"),
                object: nil,
                userInfo: ["favorId": id]
            )
            
        case .conversation(let id):
            print("🔗 [AppDelegate] Navigate to conversation: \(id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToConversation"),
                object: nil,
                userInfo: ["conversationId": id]
            )
            
        case .profile(let id):
            print("🔗 [AppDelegate] Navigate to profile: \(id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToProfile"),
                object: nil,
                userInfo: ["userId": id]
            )
            
        case .notifications:
            print("🔗 [AppDelegate] Navigate to notifications")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToNotifications"),
                object: nil
            )
            
        case .unknown:
            print("🔗 [AppDelegate] Unknown deep link")
        }
    }
}



