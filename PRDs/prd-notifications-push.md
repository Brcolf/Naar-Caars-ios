# PRD: Push Notifications (APNs)

## Document Information
- **Feature Name**: Push Notifications
- **Phase**: 2 (Communication)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 1 week
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines push notification functionality using Apple Push Notification service (APNs) for the Naar's Cars iOS app.

### Why does this matter?
Push notifications keep users engaged and informed when they're not actively using the app. They're essential for time-sensitive ride coordination.

### What problem does it solve?
- Users need to know when someone claims their request
- Users need alerts for new messages
- Admins need to broadcast announcements
- Users should be notified of new requests they might help with

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| APNs integration | Device tokens registered |
| Permission request | Users prompted appropriately |
| Notification delivery | Notifications received on device |
| Deep linking | Tapping notification opens relevant screen |
| User preferences | Users can control notification types |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| PUSH-01 | User | Be prompted for notification permission | I can enable notifications |
| PUSH-02 | User | Receive notification when request claimed | I know someone is helping |
| PUSH-03 | User | Receive notification for new messages | I can respond quickly |
| PUSH-04 | User | Control which notifications I receive | I'm not overwhelmed |
| PUSH-05 | User | Tap notification to open relevant screen | I can see details immediately |
| PUSH-06 | Admin | Send broadcast to all users | I can make announcements |

---

## 4. Functional Requirements

### 4.1 APNs Setup

**Requirement PUSH-FR-001**: App must request notification permission on first launch after login.

**Requirement PUSH-FR-002**: Device token registration flow:

```swift
// App/NaarsCarsApp.swift
import UserNotifications

@main
struct NaarsCarsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// AppDelegate.swift
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, 
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    func application(_ application: UIApplication, 
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            await PushNotificationService.shared.registerDeviceToken(token)
        }
    }
    
    func application(_ application: UIApplication, 
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.pushError("Failed to register: \(error)")
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await PushNotificationService.shared.handleNotificationTap(userInfo: userInfo)
    }
}
```

---

### 4.2 Push Notification Service

**Requirement PUSH-FR-003**: PushNotificationService implementation:

```swift
// Core/Services/PushNotificationService.swift
import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()
    
    @Published var isAuthorized: Bool = false
    @Published var deviceToken: String?
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Permission
    
    /// Request notification permission from user
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                isAuthorized = true
            }
            
            return granted
        } catch {
            Log.pushError("Permission request failed: \(error)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        await MainActor.run {
            isAuthorized = settings.authorizationStatus == .authorized
        }
        
        return settings.authorizationStatus
    }
    
    // MARK: - Device Token
    
    /// Register device token with server
    func registerDeviceToken(_ token: String) async {
        self.deviceToken = token
        
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            try await supabase
                .from("push_tokens")
                .upsert([
                    "user_id": userId.uuidString,
                    "token": token,
                    "platform": "ios"
                ])
                .execute()
            
            Log.pushInfo("Device token registered")
        } catch {
            Log.pushError("Failed to register token: \(error)")
        }
    }
    
    /// Remove device token (on logout)
    func removeDeviceToken() async {
        guard let token = deviceToken else { return }
        
        do {
            try await supabase
                .from("push_tokens")
                .delete()
                .eq("token", token)
                .execute()
            
            self.deviceToken = nil
            Log.pushInfo("Device token removed")
        } catch {
            Log.pushError("Failed to remove token: \(error)")
        }
    }
    
    // MARK: - Deep Linking
    
    /// Handle notification tap and navigate to relevant screen
    func handleNotificationTap(userInfo: [AnyHashable: Any]) async {
        guard let type = userInfo["type"] as? String else { return }
        
        switch type {
        case "ride_claimed", "ride_update":
            if let rideId = userInfo["ride_id"] as? String {
                // Navigate to ride detail
                NotificationCenter.default.post(
                    name: .navigateToRide,
                    object: nil,
                    userInfo: ["rideId": rideId]
                )
            }
            
        case "favor_claimed", "favor_update":
            if let favorId = userInfo["favor_id"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToFavor,
                    object: nil,
                    userInfo: ["favorId": favorId]
                )
            }
            
        case "new_message":
            if let conversationId = userInfo["conversation_id"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToConversation,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            }
            
        case "new_request":
            NotificationCenter.default.post(
                name: .navigateToDashboard,
                object: nil
            )
            
        default:
            break
        }
    }
}

// Notification names for deep linking
extension Notification.Name {
    static let navigateToRide = Notification.Name("navigateToRide")
    static let navigateToFavor = Notification.Name("navigateToFavor")
    static let navigateToConversation = Notification.Name("navigateToConversation")
    static let navigateToDashboard = Notification.Name("navigateToDashboard")
}
```

---

### 4.3 Notification Types

**Requirement PUSH-FR-004**: The app MUST support these notification types:

| Type | Title | Body Example | Deep Link |
|------|-------|--------------|-----------|
| `ride_claimed` | "Ride Claimed!" | "Bob is helping with your ride to SEA" | Ride detail |
| `favor_claimed` | "Someone Can Help!" | "Sara is helping with your favor" | Favor detail |
| `new_message` | "Message from Bob" | "I'll be there at 7:45" | Conversation |
| `request_unclaimed` | "Request Unclaimed" | "Your ride is open again" | Request detail |
| `new_request` | "New Request" | "John needs a ride to downtown" | Dashboard |
| `request_completed` | "Request Completed" | "Don't forget to leave a review!" | Request detail |
| `admin_announcement` | "[Title]" | "[Message]" | Dashboard |
| `qa_question` | "New Question" | "Bob asked about your ride" | Request detail |
| `qa_answer` | "Question Answered" | "John replied to your question" | Request detail |

---

### 4.4 Notification Preferences

**Requirement PUSH-FR-005**: Users can control notification types in settings:

| Preference | Default | Description |
|------------|---------|-------------|
| `notify_ride_updates` | ON | Claim/unclaim/complete notifications |
| `notify_messages` | ON | New message notifications |
| `notify_new_requests` | ON | New requests from community |
| `notify_qa_activity` | ON | Q&A on user's requests |
| `notify_announcements` | ON | Admin broadcasts |
| `notify_review_reminders` | ON | Reminder to leave reviews |

**Requirement PUSH-FR-006**: Preferences stored in user profile.

**Requirement PUSH-FR-007**: Preferences UI:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â† Notification Settings           â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   Push Notifications                â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Enable Push          [ON]   â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   ACTIVITY                          â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Ride & Favor Updates [ON]   â”‚   â”‚
â”‚   â”‚ When someone claims, etc.   â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ New Requests         [ON]   â”‚   â”‚
â”‚   â”‚ New posts from community    â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ Q&A Activity         [ON]   â”‚   â”‚
â”‚   â”‚ Questions on your requests  â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   COMMUNICATION                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Messages             [ON]   â”‚   â”‚
â”‚   â”‚ New message received        â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ Announcements        [ON]   â”‚   â”‚
â”‚   â”‚ Admin broadcasts            â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 4.5 Server-Side Integration

**Requirement PUSH-FR-008**: Push notifications are sent from server (Supabase Edge Function or external service).

**Requirement PUSH-FR-009**: Required database table for iOS tokens:

```sql
CREATE TABLE push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT DEFAULT 'ios',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);
```

**Requirement PUSH-FR-010**: Server payload format for APNs:

```json
{
    "aps": {
        "alert": {
            "title": "Ride Claimed!",
            "body": "Bob is helping with your ride to SEA"
        },
        "sound": "default",
        "badge": 3
    },
    "type": "ride_claimed",
    "ride_id": "uuid-here"
}
```

---

### 4.6 Badge Management

**Requirement PUSH-FR-011**: App badge shows unread notification + message count.

**Requirement PUSH-FR-012**: Badge is cleared when user opens app and views content.

```swift
func updateBadgeCount() async {
    let unreadNotifications = try? await NotificationService.shared.getUnreadCount()
    let unreadMessages = try? await MessageService.shared.getUnreadCount(userId: currentUserId)
    
    let total = (unreadNotifications ?? 0) + (unreadMessages ?? 0)
    
    await MainActor.run {
        UIApplication.shared.applicationIconBadgeNumber = total
    }
}
```

---

### 4.7 Permission Prompt Timing

**Requirement PUSH-FR-013**: Permission prompt flow:
1. On first login (after approval), show explanation screen
2. User taps "Enable Notifications"
3. System permission dialog appears
4. If denied, show how to enable in Settings

**Requirement PUSH-FR-014**: Permission explanation screen:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                                     â”‚
â”‚            ðŸ””                       â”‚
â”‚                                     â”‚
â”‚    Stay in the Loop!                â”‚
â”‚                                     â”‚
â”‚    Get notified when:               â”‚
â”‚    â€¢ Someone claims your request    â”‚
â”‚    â€¢ You receive a new message      â”‚
â”‚    â€¢ Community posts new requests   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚   Enable Notifications      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚           Maybe Later               â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## 5. Non-Goals

- Rich notifications with images
- Notification actions (reply from notification)
- Silent/background notifications
- Local notifications
- Notification grouping/threading

---

## 6. Technical Considerations

### APNs Setup Requirements

1. **Apple Developer Account**: Required
2. **APNs Key**: Generate in Apple Developer portal
3. **Key ID & Team ID**: Required for server authentication
4. **Bundle ID**: Must match app's bundle identifier

### Server Requirements

The server (Supabase Edge Function or custom) needs:
- APNs authentication key (.p8 file)
- Key ID
- Team ID
- Bundle ID
- Library: `apns2` (Node.js) or similar

---

## 7. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`

### Used By
- `prd-messaging.md`
- `prd-request-claiming.md`

---

## 8. Success Metrics

| Metric | Target |
|--------|--------|
| Permission grant rate | >70% |
| Notification delivery | <5s from trigger |
| Deep link works | Opens correct screen |
| Preferences respected | No unwanted notifications |

---

*End of PRD: Push Notifications*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 4.2 - Push Notification Service (Token Registration)

**Enhance existing token registration with device ID:**

```markdown
### 4.2 Push Notification Service

**Requirement PUSH-FR-003**: Token registration with device deduplication:

```swift
// Core/Services/PushNotificationService.swift
@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()
    
    @Published var deviceToken: String?
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Token Registration
    
    func registerDeviceToken(_ token: String) async {
        self.deviceToken = token
        
        guard let userId = AuthService.shared.currentUserId else { 
            Log.pushWarning("Cannot register token: no user logged in")
            return 
        }
        
        // Get unique device identifier (persisted in Keychain)
        let deviceId = DeviceIdentifier.current
        
        do {
            // First, remove any existing token for this device
            // This handles token refresh and prevents duplicates
            try await supabase
                .from("push_tokens")
                .delete()
                .eq("user_id", userId.uuidString)
                .eq("device_id", deviceId)
                .execute()
            
            // Then insert new token
            try await supabase
                .from("push_tokens")
                .insert([
                    "user_id": userId.uuidString,
                    "token": token,
                    "device_id": deviceId,
                    "platform": "ios",
                    "created_at": ISO8601DateFormatter().string(from: Date())
                ])
                .execute()
            
            Log.pushInfo("Device token registered successfully")
        } catch {
            Log.pushError("Failed to register token: \(error)")
        }
    }
    
    func removeDeviceToken() async {
        let deviceId = DeviceIdentifier.current
        
        do {
            try await supabase
                .from("push_tokens")
                .delete()
                .eq("device_id", deviceId)
                .execute()
            
            self.deviceToken = nil
            Log.pushInfo("Device token removed")
        } catch {
            Log.pushError("Failed to remove token: \(error)")
        }
    }
}
```

**Requirement PUSH-FR-003a**: Token table schema MUST include device_id:

```sql
CREATE TABLE push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL,
    platform TEXT DEFAULT 'ios',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    UNIQUE(user_id, device_id)
);

-- Index for efficient lookup
CREATE INDEX idx_push_tokens_user ON push_tokens(user_id);
CREATE INDEX idx_push_tokens_device ON push_tokens(device_id);
```

**Requirement PUSH-FR-003b**: Token cleanup on logout MUST remove token for current device only (not all user tokens - they may have multiple devices).
```

---

## ADD: Section 4.8 - Token Lifecycle Management

**Insert as new section**

```markdown
### 4.8 Token Lifecycle Management

**Requirement PUSH-FR-015**: Implement `DeviceIdentifier` utility:

```swift
// Core/Utilities/DeviceIdentifier.swift
import Foundation
import Security

enum DeviceIdentifier {
    private static let keychainKey = "com.naarscars.deviceId"
    
    /// Persistent device identifier stored in Keychain
    /// Survives app reinstalls (unlike UserDefaults)
    static var current: String {
        if let existing = readFromKeychain() {
            return existing
        }
        let newId = UUID().uuidString
        saveToKeychain(newId)
        return newId
    }
    
    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    private static func saveToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing if any
        SecItemDelete(query as CFDictionary)
        
        // Add new
        SecItemAdd(query as CFDictionary, nil)
    }
}
```

**Requirement PUSH-FR-016**: Token refresh handling:
- Re-register token in `didRegisterForRemoteNotificationsWithDeviceToken` (called on every app launch)
- This naturally handles APNs token changes
- No special handling needed - upsert pattern handles it

```swift
// In AppDelegate or equivalent
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    
    Task {
        await PushNotificationService.shared.registerDeviceToken(tokenString)
    }
}
```

**Requirement PUSH-FR-017**: Server-side token cleanup (scheduled job):

```sql
-- Run weekly via Supabase cron or Edge Function
-- Delete tokens older than 90 days
DELETE FROM push_tokens 
WHERE last_used_at < NOW() - INTERVAL '90 days'
   OR (last_used_at IS NULL AND created_at < NOW() - INTERVAL '90 days');
```

**Requirement PUSH-FR-018**: Update `last_used_at` when sending notification:

```javascript
// In Edge Function that sends push notifications
async function sendPushNotification(token, payload) {
    // Update last_used_at
    await supabase
        .from('push_tokens')
        .update({ last_used_at: new Date().toISOString() })
        .eq('token', token);
    
    // Send to APNs
    const response = await sendToAPNs(token, payload);
    
    // Handle invalid token
    if (response.status === 410) {
        // Token unregistered - delete it
        await supabase
            .from('push_tokens')
            .delete()
            .eq('token', token);
        
        Log.info(`Removed invalid token: ${token.substring(0, 8)}...`);
    }
    
    return response;
}
```

**Requirement PUSH-FR-019**: APNs error handling:

| APNs Status | Meaning | Action |
|-------------|---------|--------|
| 200 | Success | Update `last_used_at` |
| 400 | Bad request | Log error, investigate |
| 403 | Auth error | Check APNs credentials |
| 410 | Unregistered | Delete token immediately |
| 429 | Too many requests | Implement backoff |
| 500 | APNs error | Retry with backoff |
```

---

## ADD: Section 6.1 - Security Considerations

**Insert in Security section or create new**

```markdown
### 6.1 Security Considerations

**Requirement PUSH-SEC-001**: Token access controlled by RLS:
- Users can only manage their own push tokens
- See `SECURITY.md` for RLS policy

```sql
CREATE POLICY "push_tokens_own" ON public.push_tokens
  FOR ALL USING (auth.uid() = user_id);
```

**Requirement PUSH-SEC-002**: Token security practices:
- Tokens stored with device_id for deduplication
- Old tokens cleaned up automatically
- Invalid tokens removed immediately on APNs 410

**Requirement PUSH-SEC-003**: Notification content security:
- Never include sensitive data in notification payload
- Use notification to trigger app fetch of actual data
- Example: "New message from Sarah" not "Sarah says: <message content>"

```swift
// Good: Generic notification, fetch details in app
{
    "aps": {
        "alert": {
            "title": "New Message",
            "body": "You have a new message from Sarah"
        }
    },
    "conversation_id": "uuid-here"
}

// Bad: Including message content
{
    "aps": {
        "alert": {
            "title": "Sarah",
            "body": "Hey, here's my address: 123 Main St..."  // Don't do this!
        }
    }
}
```
```

---

*End of Push Notifications Addendum*
