---
color: yellow
position:
  x: 206
  y: -1532
isContextNode: false
agent_name: Amy
---

# Feature: Notifications

In-app and push notification system.

## Views
- **NotificationsListView.swift** - Notification inbox with grouping
- **NotificationRow.swift** - Individual notification display
- **NotificationSettingsView.swift** - Configure notification preferences

## ViewModels
- **NotificationsListViewModel.swift** - Load/mark read notifications
- **NotificationSettingsViewModel.swift** - Manage preferences

## Services
- **NotificationService.swift** - CRUD for app notifications
- **PushNotificationService.swift** - APNs registration and badge management
- **BadgeCountManager.swift** - Real-time badge count tracking

## Models
- **AppNotification.swift** - Notification data with type, read status, related entities
- **NotificationGrouping.swift** - Smart grouping logic (e.g., "3 new messages")

## Storage
- **NotificationRepository.swift** - SwiftData cache for notifications

## Notification Types

1. **Ride/Favor Posted** - New request available
2. **Request Claimed** - Your request was claimed
3. **Claim Confirmed** - User confirmed your claim
4. **New Message** - Unread message in conversation
5. **Review Received** - Someone reviewed you
6. **Town Hall Reply** - Comment on your post

## Push Notification Flow

1. App registers for APNs on launch (`PushNotificationService`)
2. Device token sent to Supabase (`profiles.push_token`)
3. Server events trigger Edge Function (`send-notification`)
4. Edge Function sends APNs payload with badge count
5. App receives push and updates UI

## Technical Debt

### 🔴 Badge Count Performance Issue
**Issue:** `get_badge_counts` RPC performs multiple `COUNT(*)` queries on every call.

**Impact:** Scales poorly as messages/notifications grow.

**Fix Needed:** Materialized views or counter tables with database triggers.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
