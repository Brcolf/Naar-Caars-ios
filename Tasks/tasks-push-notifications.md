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

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/push-notifications`

- [ ] 1.0 Configure push notification capabilities
  - [ ] 1.1 Enable Push Notifications in Xcode Signing & Capabilities
  - [ ] 1.2 Enable Background Modes > Remote notifications
  - [ ] 1.3 Create APNs key in Apple Developer Portal
  - [ ] 1.4 Upload APNs key to Supabase Dashboard

- [ ] 2.0 Implement PushNotificationService
  - [ ] 2.1 Create PushNotificationService.swift
  - [ ] 2.2 Implement requestPermission() using UNUserNotificationCenter
  - [ ] 2.3 Implement registerDeviceToken() to save to push_tokens table
  - [ ] 2.4 Implement removeDeviceToken() for logout cleanup
  - [ ] 2.5 🧪 Write PushNotificationServiceTests.testRegisterToken_SavesToDB

- [ ] 3.0 Create DeepLinkParser
  - [ ] 3.1 Create DeepLinkParser.swift in Core/Utilities
  - [ ] 3.2 Define DeepLink enum with cases for all screens
  - [ ] 3.3 Implement parse(userInfo:) method
  - [ ] 3.4 🧪 Write DeepLinkParserTests.testParse_RideNotification
  - [ ] 3.5 🧪 Write DeepLinkParserTests.testParse_MessageNotification

### 🔒 CHECKPOINT: QA-PUSH-001
> Run: `./QA/Scripts/checkpoint.sh push-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: DeepLinkParser tests pass
> Must pass before continuing

- [ ] 4.0 Handle notification registration
  - [ ] 4.1 Create AppDelegate.swift for push notification delegates
  - [ ] 4.2 Implement didRegisterForRemoteNotificationsWithDeviceToken
  - [ ] 4.3 Implement didFailToRegisterForRemoteNotificationsWithError
  - [ ] 4.4 Call PushNotificationService.registerDeviceToken()

- [ ] 5.0 Handle notification taps
  - [ ] 5.1 Implement userNotificationCenter didReceive response
  - [ ] 5.2 Parse deep link from notification
  - [ ] 5.3 Navigate to appropriate screen using router

- [ ] 6.0 Request permission at appropriate time
  - [ ] 6.1 Add permission request after first claim
  - [ ] 6.2 Show custom prompt explaining benefits
  - [ ] 6.3 Handle denial gracefully

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
