//
//  AppDelegate.swift
//  NaarsCars
//
//  App delegate for push notification handling
//

import UIKit
import UserNotifications
import BackgroundTasks
import os

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Initialize push service to register categories on launch
        _ = PushNotificationService.shared
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        // Register background tasks
        registerBackgroundTasks()
        
        // Handle deep link if app was opened via URL
        if let url = launchOptions?[.url] as? URL {
            handleURL(url)
        }
        
        return true
    }
    
    // MARK: - Background Tasks
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.naarscars.app.refresh", using: nil) { task in
            guard let refreshTask = Self.appRefreshTask(from: task) else {
                print("🔴 [AppDelegate] Expected BGAppRefreshTask, received \(type(of: task))")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(task: refreshTask)
        }
    }

    static func appRefreshTask(from task: Any) -> BGAppRefreshTask? {
        task as? BGAppRefreshTask
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh
        scheduleAppRefresh()
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        
        task.expirationHandler = {
            queue.cancelAllOperations()
        }
        
        Task {
            // Perform sync
            await DashboardSyncEngine.shared.syncAll()
            task.setTaskCompleted(success: true)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.naarscars.app.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 [AppDelegate] Scheduled background refresh")
        } catch {
            print("🔴 [AppDelegate] Could not schedule app refresh: \(error)")
        }
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
            PushNotificationService.shared.storeDeviceToken(deviceToken)
            if let userId = AuthService.shared.currentUserId {
                do {
                    try await PushNotificationService.shared.registerDeviceToken(
                        deviceToken: deviceToken,
                        userId: userId
                    )
                } catch {
                    print("🔴 [AppDelegate] Failed to register device token: \(error.localizedDescription)")
                }
            } else {
                print("ℹ️ [AppDelegate] APNs token received before login; will register after login.")
            }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.push("Failed to register for remote notifications: \(error.localizedDescription)", type: .error)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let notificationType = userInfo["type"] as? String
        PushNotificationService.shared.recordLastPushPayload(userInfo)
        
        // Handle actionable responses without opening the app
        if response.actionIdentifier != UNNotificationDefaultActionIdentifier &&
            response.actionIdentifier != UNNotificationDismissActionIdentifier {
            Task { @MainActor in
                switch response.actionIdentifier {
                case NotificationAction.reply.rawValue:
                    // Quick-reply from message notification
                    if let textResponse = response as? UNTextInputNotificationResponse {
                        await PushNotificationService.shared.handleMessageReply(
                            replyText: textResponse.userText,
                            userInfo: userInfo
                        )
                    }
                case NotificationAction.markRead.rawValue:
                    // Mark conversation as read from notification
                    await PushNotificationService.shared.handleMessageMarkRead(userInfo: userInfo)
                case NotificationAction.viewRequest.rawValue:
                    // View Details opens the app and deep-links (foreground option)
                    let deepLink = DeepLinkParser.parse(userInfo: userInfo)
                    self.handleDeepLink(deepLink, userInfo: userInfo)
                default:
                    // Completion reminder Yes/No actions
                    await PushNotificationService.shared.handleNotificationAction(
                        actionIdentifier: response.actionIdentifier,
                        userInfo: userInfo
                    )
                }
                completionHandler()
            }
            return
        }
        
        // Mark the specific notification as read when tapped (if available)
        if let notificationIdString = userInfo["notification_id"] as? String,
           let notificationId = UUID(uuidString: notificationIdString) {
            if !Self.shouldSkipAutoRead(for: notificationType) {
                Task { @MainActor in
                    try? await NotificationService.shared.markAsRead(notificationId: notificationId)
                }
            }
        }
        
        // Review requests should open the review modal directly
        if Self.shouldShowReviewPrompt(for: notificationType) {
            postReviewPrompt(from: userInfo)
        }

        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        
        // Handle deep link navigation
        handleDeepLink(deepLink, userInfo: userInfo)
        
        // Post completion prompt if needed (after deep link handling)
        if Self.shouldShowCompletionPrompt(for: notificationType) {
            postCompletionPrompt(from: userInfo)
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        PushNotificationService.shared.recordLastPushPayload(userInfo)
        
        // Avoid duplicate alerts when in Messages; allow banners elsewhere in foreground.
        if let type = userInfo["type"] as? String,
           type == "message" || type == "added_to_conversation" {
            Task { @MainActor in
                let isMessagesTab = NavigationCoordinator.shared.selectedTab == .messages
                print("🔔 [AppDelegate] Foreground message banner: \(isMessagesTab ? "suppressed" : "shown")")
                completionHandler(isMessagesTab ? [] : [.banner, .sound, .badge])
            }
            return
        }
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // MARK: - Deep Link Handling
    
    private func handleDeepLink(_ deepLink: DeepLink, userInfo: [AnyHashable: Any]? = nil) {
        // Post notifications that views can listen to for navigation
        // Views use @State variables and navigationDestination modifiers to handle navigation
        switch deepLink {
        case .ride(let id):
            print("🔗 [AppDelegate] Navigate to ride: \(id)")
            var payload: [AnyHashable: Any] = ["rideId": id]
            if let userInfo, let requestPayload = requestNavigationPayload(
                from: userInfo,
                requestId: id,
                requestType: .ride
            ) {
                payload.merge(requestPayload) { _, new in new }
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToRide"),
                object: nil,
                userInfo: payload
            )
            
        case .favor(let id):
            print("🔗 [AppDelegate] Navigate to favor: \(id)")
            var payload: [AnyHashable: Any] = ["favorId": id]
            if let userInfo, let requestPayload = requestNavigationPayload(
                from: userInfo,
                requestId: id,
                requestType: .favor
            ) {
                payload.merge(requestPayload) { _, new in new }
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToFavor"),
                object: nil,
                userInfo: payload
            )
            
        case .conversation(let id):
            print("🔗 [AppDelegate] Navigate to conversation: \(id)")
            var payload: [AnyHashable: Any] = ["conversationId": id]
            if let userInfo,
               let messageIdString = userInfo["message_id"] as? String,
               let messageId = UUID(uuidString: messageIdString) {
                payload["messageId"] = messageId
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToConversation"),
                object: nil,
                userInfo: payload
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

        case .announcements(let notificationId):
            print("🔗 [AppDelegate] Navigate to announcements")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToAnnouncements"),
                object: nil,
                userInfo: ["notificationId": notificationId as Any]
            )
            
        case .townHall:
            print("🔗 [AppDelegate] Navigate to town hall")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToTownHall"),
                object: nil
            )
            
        case .townHallPostComments(let id):
            print("🔗 [AppDelegate] Navigate to town hall post comments: \(id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToTownHall"),
                object: nil,
                userInfo: ["postId": id, "mode": NavigationCoordinator.TownHallNavigationTarget.Mode.openComments.rawValue]
            )
            
        case .townHallPostHighlight(let id):
            print("🔗 [AppDelegate] Navigate to town hall post highlight: \(id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToTownHall"),
                object: nil,
                userInfo: ["postId": id, "mode": NavigationCoordinator.TownHallNavigationTarget.Mode.highlightPost.rawValue]
            )

        case .adminPanel:
            print("🔗 [AppDelegate] Navigate to admin panel")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToAdminPanel"),
                object: nil
            )
            
        case .pendingUsers:
            print("🔗 [AppDelegate] Navigate to pending users list")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToPendingUsers"),
                object: nil
            )

        case .dashboard:
            print("🔗 [AppDelegate] Navigate to dashboard")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateToDashboard"),
                object: nil
            )
            
        case .enterApp:
            print("🔗 [AppDelegate] Enter app")
            Task { @MainActor in
                await AppLaunchManager.shared.performCriticalLaunch()
            }
            
        case .unknown:
            print("🔗 [AppDelegate] Unknown deep link")
        }
    }

    private func requestNavigationPayload(
        from userInfo: [AnyHashable: Any],
        requestId: UUID,
        requestType: RequestType
    ) -> [AnyHashable: Any]? {
        guard let typeRaw = userInfo["type"] as? String,
              let type = NotificationType(rawValue: typeRaw) else {
            return nil
        }

        let rideId = (requestType == .ride) ? requestId : nil
        let favorId = (requestType == .favor) ? requestId : nil

        guard let target = RequestNotificationMapping.target(
            for: type,
            rideId: rideId,
            favorId: favorId
        ) else {
            return nil
        }

        var payload: [AnyHashable: Any] = [
            "requestAnchor": target.anchor.rawValue,
            "requestAutoClear": target.shouldAutoClear
        ]

        if let scrollAnchor = target.scrollAnchor {
            payload["requestScrollAnchor"] = scrollAnchor.rawValue
        }

        if let highlightAnchor = target.highlightAnchor {
            payload["requestHighlightAnchor"] = highlightAnchor.rawValue
        }

        return payload
    }

    private func postReviewPrompt(from userInfo: [AnyHashable: Any]) {
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
    }

    private func postCompletionPrompt(from userInfo: [AnyHashable: Any]) {
        if let rideIdString = userInfo["ride_id"] as? String,
           let rideId = UUID(uuidString: rideIdString) {
            NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["rideId": rideId])
        } else if let favorIdString = userInfo["favor_id"] as? String,
                  let favorId = UUID(uuidString: favorIdString) {
            NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["favorId": favorId])
        }
    }

    static func shouldShowReviewPrompt(for notificationType: String?) -> Bool {
        guard let notificationType else {
            return false
        }
        return notificationType == "review_request" || notificationType == "review_reminder"
    }

    static func shouldShowCompletionPrompt(for notificationType: String?) -> Bool {
        notificationType == "completion_reminder"
    }

    static func shouldSkipAutoRead(for notificationType: String?) -> Bool {
        guard let notificationType else { return false }
        return notificationType == "review_request" ||
               notificationType == "review_reminder" ||
               notificationType == "completion_reminder"
    }
}


