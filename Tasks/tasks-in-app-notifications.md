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

- [x] 0.0 Create feature branch: `git checkout -b feature/in-app-notifications`

- [x] 1.0 Create notification data model
  - [x] 1.1 Create AppNotification.swift in Core/Models
  - [x] 1.2 Add fields: id, userId, type, title, body, data, read, pinned, createdAt
  - [x] 1.3 Create NotificationType enum (message, rideUpdate, claim, review, announcement)
  - [x] 1.4 🧪 Write AppNotificationTests.testCodableDecoding

- [x] 2.0 Implement NotificationService
  - [x] 2.1 Create NotificationService.swift with singleton
  - [x] 2.2 Implement fetchNotifications(userId:) ordered by pinned, then createdAt
  - [x] 2.3 Implement fetchUnreadCount(userId:)
  - [x] 2.4 Implement markAsRead(notificationId:)
  - [x] 2.5 Implement markAllAsRead(userId:)
  - [x] 2.6 🧪 Write NotificationServiceTests.testFetchNotifications_PinnedFirst
  - [x] 2.7 🧪 Write NotificationServiceTests.testMarkAsRead_Success

### 🔒 CHECKPOINT: QA-NOTIF-001
> Run: `./QA/Scripts/checkpoint.sh notifications-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: NotificationService tests pass
> Must pass before continuing

- [x] 3.0 Build Notifications List View
  - [x] 3.1 Create NotificationsListView.swift
  - [x] 3.2 Add @StateObject for NotificationsListViewModel
  - [x] 3.3 Group notifications by day
  - [x] 3.4 Show pinned announcements at top
  - [x] 3.5 Display NotificationRow for each notification
  - [x] 3.6 Add "Mark All Read" button
  - [x] 3.7 Add pull-to-refresh

- [x] 4.0 Implement NotificationsListViewModel
  - [x] 4.1 Create NotificationsListViewModel.swift
  - [x] 4.2 Implement loadNotifications()
  - [x] 4.3 ⭐ Subscribe to notifications via RealtimeManager
  - [x] 4.4 Implement handleNotificationTap() with deep linking
  - [x] 4.5 🧪 Write NotificationsListViewModelTests.testLoadNotifications

- [x] 5.0 Build UI Components
  - [x] 5.1 Create NotificationRow.swift
  - [x] 5.2 Show icon based on notification type
  - [x] 5.3 Style differently for read/unread
  - [x] 5.4 Create NotificationBadge.swift for tab bar
  - [x] 5.5 Add Xcode previews

- [x] 6.0 Add notification bell to navigation
  - [x] 6.1 Add bell icon to main navigation
  - [x] 6.2 Show unread count badge
  - [x] 6.3 Navigate to NotificationsListView on tap

- [x] 7.0 Verify in-app notifications
  - [x] 7.1 Test notifications display correctly
  - [x] 7.2 Test mark as read functionality
  - [x] 7.3 Test deep linking to content
  - [x] 7.4 Commit: "feat: implement in-app notifications"

### 🔒 CHECKPOINT: QA-NOTIF-FINAL
> Run: `./QA/Scripts/checkpoint.sh notifications-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_NOTIF_002
> All notification tests must pass
