# Requests Notification UX Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add filter + card badges for request notifications and auto-scroll/highlight request detail anchors based on the most recent unread notification.

**Architecture:** Client-side aggregation of unread request notifications in `RequestsDashboardViewModel`, with UI badges driven from that summary map and navigation targets derived from the most recent unread type.

**Tech Stack:** SwiftUI, SwiftData, Supabase (notifications), NavigationCoordinator.

---

**Note:** Automated tests and commits are skipped per user request. Manual QA only.

### Task 1: Aggregate unread request notifications

**Files:**
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
- Modify (optional): `NaarsCars/Core/Models/NotificationGrouping.swift`

**Step 1: Write the failing test**
- Skipped (per user request).

**Step 2: Run test to verify it fails**
- Skipped (per user request).

**Step 3: Implement aggregation struct + map**
Add a lightweight summary type and store a map keyed by `requestKey`:
```swift
struct RequestNotificationSummary {
    let unreadCount: Int
    let latestUnreadType: NotificationType
    let latestUnreadAt: Date
}

@Published var requestNotificationSummaries: [String: RequestNotificationSummary] = [:]
```

**Step 4: Build summaries during refresh**
Update `refreshUnseenRequestKeys()` to group unread notifications by request key,
count them, and pick the most recent unread type by `createdAt`.

**Step 5: Manual check**
Use existing debug logs to confirm `requestNotificationSummaries.count` updates.

### Task 2: Compute filter badge counts

**Files:**
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`

**Step 1: Write the failing test**
- Skipped (per user request).

**Step 2: Run test to verify it fails**
- Skipped (per user request).

**Step 3: Add per-filter counts**
Add a published `filterBadgeCounts` map:
```swift
@Published var filterBadgeCounts: [RequestFilter: Int] = [:]
```
Compute counts by matching `RequestItem` to filters and summing
`unreadCount` from `requestNotificationSummaries`.

**Step 4: Manual check**
Verify counts change when filter changes and when new notifications arrive.

### Task 3: Show badges in Requests list UI

**Files:**
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift`
- Modify: `NaarsCars/UI/Components/Cards/RideCard.swift`
- Modify: `NaarsCars/UI/Components/Cards/FavorCard.swift`

**Step 1: Write the failing test**
- Skipped (per user request).

**Step 2: Run test to verify it fails**
- Skipped (per user request).

**Step 3: Filter tile badge**
Extend `FilterTile` to accept a count and render a badge when count > 0.

**Step 4: Card badge**
Replace the dot indicator with a numeric badge using the per-request count.

**Step 5: Manual check**
Verify badges appear on filter tiles and cards with unseen notifications.

### Task 4: Set navigation targets from card taps + deep-link list scroll

**Files:**
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift`
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`

**Step 1: Write the failing test**
- Skipped (per user request).

**Step 2: Run test to verify it fails**
- Skipped (per user request).

**Step 3: Card tap navigation target**
On card tap, if a summary exists, set
`NavigationCoordinator.requestNavigationTarget` using
`RequestNotificationMapping.target(for:latestType, rideId, favorId)`.

**Step 4: Optional list auto-scroll for deep links**
Wrap the list in `ScrollViewReader` and scroll to the request card
only when entering via a notification deep link.

**Step 5: Manual check**
Open a request with unseen notifications and confirm detail auto-scrolls
and highlights the anchor for the most recent notification.

### Task 5: Manual QA (no unit tests)

**Files:**
- None (manual testing only)

**Step 1: Requests tab badge trail**
- Verify filter tile badges point to the correct list.

**Step 2: Card badge**
- Verify numeric badge matches unseen notifications for that request.

**Step 3: Detail anchor highlight**
- Verify detail view scrolls and highlights the correct section.

