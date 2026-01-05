# Tasks: In-App Notifications

Based on `prd-notifications-in-app.md`

## Affected Flows

- FLOW_NOTIF_002: View In-App Notifications

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/NotificationService.swift` - In-app notification operations
- `Core/Models/AppNotification.swift` - Notification data model
- `Features/Notifications/Views/NotificationsListView.swift` - Notifications screen
- `Features/Notifications/Views/NotificationRow.swift` - Notification row
- `Features/Notifications/ViewModels/NotificationsListViewModel.swift`
- `UI/Components/Common/NotificationBadge.swift` - Badge component

### Test Files
- `NaarsCarsTests/Core/Services/NotificationServiceTests.swift`
- `NaarsCarsTests/Features/Notifications/NotificationsListViewModelTests.swift`
- `NaarsCarsSnapshotTests/Notifications/NotificationRowSnapshots.swift`

## Notes

- Notifications stored in Supabase notifications table
- Pinned announcements shown at top
- Real-time updates via RealtimeManager
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/in-app-notifications`

- [ ] 1.0 Create notification data model
  - [ ] 1.1 Create AppNotification.swift in Core/Models
  - [ ] 1.2 Add fields: id, userId, type, title, body, data, read, pinned, createdAt
  - [ ] 1.3 Create NotificationType enum (message, rideUpdate, claim, review, announcement)
  - [ ] 1.4 🧪 Write AppNotificationTests.testCodableDecoding

- [ ] 2.0 Implement NotificationService
  - [ ] 2.1 Create NotificationService.swift with singleton
  - [ ] 2.2 Implement fetchNotifications(userId:) ordered by pinned, then createdAt
  - [ ] 2.3 Implement fetchUnreadCount(userId:)
  - [ ] 2.4 Implement markAsRead(notificationId:)
  - [ ] 2.5 Implement markAllAsRead(userId:)
  - [ ] 2.6 🧪 Write NotificationServiceTests.testFetchNotifications_PinnedFirst
  - [ ] 2.7 🧪 Write NotificationServiceTests.testMarkAsRead_Success

### 🔒 CHECKPOINT: QA-NOTIF-001
> Run: `./QA/Scripts/checkpoint.sh notifications-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: NotificationService tests pass
> Must pass before continuing

- [ ] 3.0 Build Notifications List View
  - [ ] 3.1 Create NotificationsListView.swift
  - [ ] 3.2 Add @StateObject for NotificationsListViewModel
  - [ ] 3.3 Group notifications by day
  - [ ] 3.4 Show pinned announcements at top
  - [ ] 3.5 Display NotificationRow for each notification
  - [ ] 3.6 Add "Mark All Read" button
  - [ ] 3.7 Add pull-to-refresh

- [ ] 4.0 Implement NotificationsListViewModel
  - [ ] 4.1 Create NotificationsListViewModel.swift
  - [ ] 4.2 Implement loadNotifications()
  - [ ] 4.3 ⭐ Subscribe to notifications via RealtimeManager
  - [ ] 4.4 Implement handleNotificationTap() with deep linking
  - [ ] 4.5 🧪 Write NotificationsListViewModelTests.testLoadNotifications

- [ ] 5.0 Build UI Components
  - [ ] 5.1 Create NotificationRow.swift
  - [ ] 5.2 Show icon based on notification type
  - [ ] 5.3 Style differently for read/unread
  - [ ] 5.4 Create NotificationBadge.swift for tab bar
  - [ ] 5.5 Add Xcode previews

- [ ] 6.0 Add notification bell to navigation
  - [ ] 6.1 Add bell icon to main navigation
  - [ ] 6.2 Show unread count badge
  - [ ] 6.3 Navigate to NotificationsListView on tap

- [ ] 7.0 Verify in-app notifications
  - [ ] 7.1 Test notifications display correctly
  - [ ] 7.2 Test mark as read functionality
  - [ ] 7.3 Test deep linking to content
  - [ ] 7.4 Commit: "feat: implement in-app notifications"

### 🔒 CHECKPOINT: QA-NOTIF-FINAL
> Run: `./QA/Scripts/checkpoint.sh notifications-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_NOTIF_002
> All notification tests must pass
