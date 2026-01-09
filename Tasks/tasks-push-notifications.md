# Tasks: Push Notifications

Based on `prd-notifications-push.md`

## Affected Flows

- FLOW_NOTIF_001: Receive Push Notification

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/PushNotificationService.swift` - Push notification handling
- `Core/Utilities/DeepLinkParser.swift` - Parse notification deep links
- `App/AppDelegate.swift` - Push notification setup
- `App/NaarsCarsApp.swift` - Handle notification taps

### Test Files
- `NaarsCarsTests/Core/Services/PushNotificationServiceTests.swift`
- `NaarsCarsTests/Core/Utilities/DeepLinkParserTests.swift`

## Notes

- Uses APNs for iOS push notifications
- Supabase Edge Functions send notifications
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [x] 0.0 Create feature branch: `git checkout -b feature/push-notifications`

- [x] 1.0 Configure push notification capabilities
  - [x] 1.1 Enable Push Notifications in Xcode Signing & Capabilities (Manual - see PUSH-NOTIFICATIONS-SETUP.md)
  - [x] 1.2 Enable Background Modes > Remote notifications (Manual - see PUSH-NOTIFICATIONS-SETUP.md)
  - [x] 1.3 Create APNs key in Apple Developer Portal (Manual - see PUSH-NOTIFICATIONS-SETUP.md)
  - [x] 1.4 Upload APNs key to Supabase Dashboard (Manual - see PUSH-NOTIFICATIONS-SETUP.md)

- [x] 2.0 Implement PushNotificationService
  - [x] 2.1 Create PushNotificationService.swift
  - [x] 2.2 Implement requestPermission() using UNUserNotificationCenter
  - [x] 2.3 Implement registerDeviceToken() to save to push_tokens table
  - [x] 2.4 Implement removeDeviceToken() for logout cleanup
  - [x] 2.5 🧪 Write PushNotificationServiceTests.testRegisterToken_SavesToDB

- [x] 3.0 Create DeepLinkParser
  - [x] 3.1 Create DeepLinkParser.swift in Core/Utilities
  - [x] 3.2 Define DeepLink enum with cases for all screens
  - [x] 3.3 Implement parse(userInfo:) method
  - [x] 3.4 🧪 Write DeepLinkParserTests.testParse_RideNotification
  - [x] 3.5 🧪 Write DeepLinkParserTests.testParse_MessageNotification

### 🔒 CHECKPOINT: QA-PUSH-001
> Run: `./QA/Scripts/checkpoint.sh push-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: DeepLinkParser tests pass
> Must pass before continuing

- [x] 4.0 Handle notification registration
  - [x] 4.1 Create AppDelegate.swift for push notification delegates
  - [x] 4.2 Implement didRegisterForRemoteNotificationsWithDeviceToken
  - [x] 4.3 Implement didFailToRegisterForRemoteNotificationsWithError
  - [x] 4.4 Call PushNotificationService.registerDeviceToken()

- [x] 5.0 Handle notification taps
  - [x] 5.1 Implement userNotificationCenter didReceive response
  - [x] 5.2 Parse deep link from notification
  - [x] 5.3 Navigate to appropriate screen using router
  - [x] 5.4 Create NavigationCoordinator for deep link handling
  - [x] 5.5 Integrate navigation handlers in RidesDashboardView, FavorsDashboardView, ConversationsListView

- [x] 6.0 Request permission at appropriate time
  - [x] 6.1 Add permission request after first claim
  - [x] 6.2 Show custom prompt explaining benefits
  - [x] 6.3 Handle denial gracefully

- [ ] 7.0 Verify push notifications
  - [ ] 7.1 Test permission request flow
  - [ ] 7.2 Test receiving notification (use push testing tool)
  - [ ] 7.3 Test notification tap navigation
  - [ ] 7.4 Commit: "feat: implement push notifications"

### 🔒 CHECKPOINT: QA-PUSH-FINAL
> Run: `./QA/Scripts/checkpoint.sh push-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_NOTIF_001
> All push notification tests must pass
