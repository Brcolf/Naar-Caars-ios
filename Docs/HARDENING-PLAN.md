# NaarsCars iOS — Hardening Plan (Post-Get-Well)

> Produced 2026-02-12. Prerequisite: All Get-Well Plan phases (0–7) complete.
> Audience: Codex agents + human reviewers.
> **Every file path, line number, and symbol is grounded in the repo at commit `72eebf3`.**

---

## Overview

The Get-Well Plan stabilized 5 contracts (realtime payloads, navigation, badges, sync engines, notification types). This plan addresses the remaining high-blast-radius seams and new risks identified in the post-refactor review.

**Phase 6 (Hardening):** 4 independent PRs — centralize notification names, Sendable safety, error isolation, observability. All low-risk, no behavior change.

**Phase 7 (Optional — Subscription Consolidation):** 3 sequential PRs — reduce 13 realtime subscriptions to 7 by eliminating duplicate table subscriptions. Medium risk, requires smoke testing.

---

## Phase 6 — Hardening (4 Independent PRs)

### PR 6A: Centralize NSNotification.Name Strings

**Problem:** 15 unique notification name strings appear as inline `NSNotification.Name("...")` literals across 37 occurrences in 20 files. A typo in any occurrence silently breaks navigation or signaling with no compile-time safety.

**File to create:**

`NaarsCars/Core/Utilities/NotificationNames.swift`

```swift
//
//  NotificationNames.swift
//  NaarsCars
//
//  Centralized notification name constants for cross-module communication

import Foundation

extension Notification.Name {
    // MARK: - Navigation (AppDelegate → NavigationCoordinator)
    static let navigateToRide = Notification.Name("navigateToRide")
    static let navigateToFavor = Notification.Name("navigateToFavor")
    static let navigateToConversation = Notification.Name("navigateToConversation")
    static let navigateToProfile = Notification.Name("navigateToProfile")
    static let navigateToTownHall = Notification.Name("navigateToTownHall")
    static let navigateToAdminPanel = Notification.Name("navigateToAdminPanel")
    static let navigateToPendingUsers = Notification.Name("navigateToPendingUsers")
    static let navigateToNotifications = Notification.Name("navigateToNotifications")
    static let navigateToAnnouncements = Notification.Name("navigateToAnnouncements")
    static let navigateToDashboard = Notification.Name("navigateToDashboard")
    static let dismissNotificationsSheet = Notification.Name("dismissNotificationsSheet")

    // MARK: - Lifecycle
    static let userDidSignOut = Notification.Name("userDidSignOut")
    static let handleInviteCodeDeepLink = Notification.Name("handleInviteCodeDeepLink")

    // MARK: - Messaging
    static let conversationUpdated = Notification.Name("conversationUpdated")

    // MARK: - Prompts (moved from PushNotificationService.swift)
    static let showReviewPrompt = Notification.Name("showReviewPrompt")
    static let showCompletionPrompt = Notification.Name("showCompletionPrompt")
    static let dismissNotificationsSurface = Notification.Name("dismissNotificationsSurface")
    static let conversationUnreadCountsUpdated = Notification.Name("conversationUnreadCountsUpdated")

    // MARK: - Messaging UI (moved from InAppToastManager.swift)
    static let messageThreadDidAppear = Notification.Name("messageThreadDidAppear")
    static let messageThreadDidDisappear = Notification.Name("messageThreadDidDisappear")

    // MARK: - Town Hall (moved from TownHallSyncEngine.swift)
    static let townHallPostVotesDidChange = Notification.Name("townHallPostVotesDidChange")
    static let townHallCommentVotesDidChange = Notification.Name("townHallCommentVotesDidChange")

    // MARK: - Localization (moved from LocalizationManager.swift)
    static let languageDidChange = Notification.Name("languageDidChange")
}
```

**Files to modify (17 production + 3 test):**

| # | File | Lines | Change |
|---|------|-------|--------|
| 1 | `App/AppDelegate.swift` | 127, 268, 284, 298, 306, 314, 321, 329, 336, 344, 352, 359, 366 | Replace `NSNotification.Name("...")` → `.navigateToRide` etc. |
| 2 | `App/NavigationCoordinator.swift` | 212, 228, 244, 267, 282, 301, 312, 323, 333, 346, 358, 368 | Same replacement in `addObserver` calls |
| 3 | `App/ContentView.swift` | 112 | `.userDidSignOut` |
| 4 | `App/AppState.swift` | 88 | `.userDidSignOut` |
| 5 | `App/AppLaunchManager.swift` | 75 | `.userDidSignOut` |
| 6 | `Core/Services/AuthService.swift` | 593 | `.userDidSignOut` |
| 7 | `Core/Services/PushNotificationService.swift` | 702-707 | Remove extension block (moved to central file) |
| 8 | `Core/Services/InAppToastManager.swift` | 54, 142-145 | Remove extension block; use `.conversationUpdated` |
| 9 | `Core/Storage/MessagingSyncEngine.swift` | 102 | `.conversationUpdated` |
| 10 | `Core/Storage/MessagingRepository.swift` | 473 | `.conversationUpdated` |
| 11 | `Core/Storage/TownHallSyncEngine.swift` | 10-12 | Remove extension block (moved) |
| 12 | `Core/Utilities/LocalizationManager.swift` | 100-102 | Remove extension block (moved) |
| 13 | `Features/Messaging/ViewModels/ConversationDetailViewModel.swift` | 181 | `.conversationUpdated` |
| 14 | `Features/Messaging/Views/ConversationDetailView.swift` | 875 | `.conversationUpdated` |
| 15 | `Features/Messaging/Views/MessageDetailsPopup.swift` | 339, 467 | `.conversationUpdated` |
| 16 | `Features/Notifications/Views/NotificationsListView.swift` | 53 | `.dismissNotificationsSheet` |
| 17 | `Features/Reviews/ViewModels/LeaveReviewViewModel.swift` | 76 | `.navigateToTownHall` |
| 18 | `Features/Authentication/Views/SignupInviteCodeView.swift` | 100 | `.handleInviteCodeDeepLink` |
| 19 | `NaarsCarsTests/App/NavigationCoordinatorTests.swift` | 23 | `.dismissNotificationsSheet` |
| 20 | `NaarsCarsTests/Core/Services/MessageServiceTests.swift` | 119 | `.conversationUpdated` |
| 21 | `NaarsCarsTests/Features/Messaging/InAppToastManagerTests.swift` | 64 | `.conversationUpdated` |

**Steps:**
1. Create `NaarsCars/Core/Utilities/NotificationNames.swift` with all 24 constants
2. Remove extension blocks from 4 existing files (PushNotificationService, InAppToastManager, TownHallSyncEngine, LocalizationManager)
3. Replace all 37 inline `NSNotification.Name("...")` occurrences with the static constant
4. User adds `NotificationNames.swift` to Xcode project

**Done criteria:**
```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
grep -rn 'NSNotification.Name("' NaarsCars/ --include="*.swift" | grep -v NotificationNames.swift
# Expected: 0 results
```

**Scope boundary:** Do NOT change any notification posting logic, observer behavior, or notification payloads. Pure string-to-constant replacement.

**Rollback:** `git revert`. All constants revert to inline strings. Zero behavior change.

---

### PR 6B: Make RealtimeRecord Sendable-Safe

**Problem:** `RealtimeRecord` (in `Core/Services/RealtimeManager.swift` lines 21-32) contains `[String: Any]` which is not `Sendable`. Swift 6 strict concurrency will flag every callback crossing an actor boundary.

**File to modify:**

`NaarsCars/Core/Services/RealtimeManager.swift` — lines 20-32

**Steps:**
1. Add `@unchecked Sendable` conformance to `RealtimeRecord`:
   ```swift
   struct RealtimeRecord: @unchecked Sendable {
   ```
2. Add `Sendable` to `EventType`:
   ```swift
   enum EventType: Sendable {
   ```

**Why `@unchecked`:** The `[String: Any]` dictionary is constructed once by `RealtimePayloadAdapter` and never mutated. All values are value types (strings, numbers, booleans, arrays of value types). True `Sendable` conformance would require changing to `[String: AnyHashable]` or a custom type — a larger change better deferred.

**Done criteria:**
```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
# Zero new warnings
grep -n "struct RealtimeRecord" NaarsCars/Core/Services/RealtimeManager.swift
# Shows: @unchecked Sendable
```

**Scope boundary:** Do NOT change `RealtimePayloadAdapter`, callback signatures, or subscriber code.

**Rollback:** `git revert`. Removes `Sendable` conformance. No behavior change.

---

### PR 6C: Error Isolation in SyncEngineOrchestrator

**Problem:** `SyncEngineOrchestrator` (`Core/Storage/SyncEngineOrchestrator.swift` lines 33-55) iterates engines with no error isolation. If one engine's `pauseSync()` or `teardown()` fails, subsequent engines are skipped.

**File to modify:**

`NaarsCars/Core/Storage/SyncEngineOrchestrator.swift` — lines 33-55

**Steps:**
1. Add logging to `startAll()`:
   ```swift
   func startAll() {
       for engine in engines {
           AppLogger.info("sync", "Starting \(engine.engineName)")
           engine.startSync()
       }
   }
   ```

2. Wrap each engine call in `pauseAll()` with do/catch:
   ```swift
   func pauseAll() async {
       for engine in engines {
           do {
               await engine.pauseSync()
           } catch {
               AppLogger.error("sync", "Failed to pause \(engine.engineName): \(error)")
           }
       }
   }
   ```

3. Same pattern for `resumeAll()` and `teardownAll()`

**Done criteria:**
```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
grep -c "AppLogger" NaarsCars/Core/Storage/SyncEngineOrchestrator.swift
# Expected: >= 4 (one per method)
```

**Scope boundary:** Do NOT change `SyncEngineProtocol` signatures or individual engine implementations.

**Rollback:** `git revert`. Removes error isolation. No behavior change.

---

### PR 6D: Observability for Realtime Decode Failures

**Problem:** When `RealtimePayloadAdapter.decodeInsert/Update/Delete` returns `nil`, the `subscribe()` Task closures in `RealtimeManager.swift` (lines 354-385) silently `continue`. The adapter logs `AppLogger.warning` (lines 57, 84, 109), but there's no metric for production analytics monitoring.

**File to modify:**

`NaarsCars/Core/Services/RealtimeManager.swift` — lines 354-385

**Steps:**
1. In each `guard let record = ... else { continue }` block, add a `PerformanceMonitor` event:
   ```swift
   guard let record = RealtimePayloadAdapter.decodeInsert(action, table: table) else {
       Task {
           await PerformanceMonitor.shared.recordEvent("realtime_decode_failure", metadata: [
               "table": table,
               "event_type": "insert",
               "channel": channelName
           ])
       }
       continue
   }
   ```
2. Repeat for the update and delete blocks (3 total)

**Done criteria:**
```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
grep -c "realtime_decode_failure" NaarsCars/Core/Services/RealtimeManager.swift
# Expected: 3 (one per event type)
```

**Scope boundary:** Do NOT change `RealtimePayloadAdapter` logic, callback types, or subscriber handling.

**Rollback:** `git revert`. Removes telemetry. Decode failures still logged via `AppLogger.warning` in the adapter.

---

## Phase 7 (Optional) — Consolidate Duplicate Realtime Subscriptions

### Current Subscription Map

| Table | Channel | Owner File | Line | Parses payload? | Action |
|-------|---------|-----------|------|-----------------|--------|
| `rides` | `rides:sync` | `Core/Storage/DashboardSyncEngine.swift` | 106 | No | Full re-fetch → SwiftData |
| `rides` | `requests-dashboard-rides` | `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | 76 | Yes (extracts `id`) | Single-ride fetch → SwiftData |
| `rides` | `rides-dashboard` | `Features/Rides/ViewModels/RidesDashboardViewModel.swift` | 201 | No | Full re-fetch → SwiftData |
| `favors` | `favors:sync` | `Core/Storage/DashboardSyncEngine.swift` | 118 | No | Full re-fetch → SwiftData |
| `favors` | `requests-dashboard-favors` | `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | 85 | Yes (extracts `id`) | Single-favor fetch → SwiftData |
| `favors` | `favors-dashboard` | `Features/Favors/ViewModels/FavorsDashboardViewModel.swift` | 199 | No | Full re-fetch → SwiftData |
| `notifications` | `notifications:sync` | `Core/Storage/DashboardSyncEngine.swift` | 132 | No | Full re-fetch → SwiftData |
| `notifications` | `notifications:all` | `Features/Notifications/ViewModels/NotificationRealtimeHandler.swift` | 42 | Partial (type check) | Debounced reload |
| `notifications` | `requests-dashboard-notifications` | `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | 96 | Partial (type check) | Refresh summaries |
| `messages` | `messages:sync` | `Core/Storage/MessagingSyncEngine.swift` | 118 | Yes (full) | Parse + upsert |
| `typing` | `typing:{id}` | `Features/Messaging/ViewModels/TypingIndicatorManager.swift` | 57 | No | Debounced re-fetch |
| `town_hall_posts` | `town-hall-posts` | `Core/Storage/TownHallSyncEngine.swift` | 78 | Yes (full) | Parse + upsert |
| `town_hall_comments` | `town-hall-comments` | `Core/Storage/TownHallSyncEngine.swift` | 102 | Yes (full) | Parse + upsert |
| `town_hall_votes` | `town-hall-votes` | `Core/Storage/TownHallSyncEngine.swift` | 126 | Partial | Extract IDs → NSNotification |

**No duplicates (no action needed):** messages, typing, town_hall_posts, town_hall_comments, town_hall_votes

**Duplicates to consolidate:**

| Table | Current subs | Target subs | Single owner |
|-------|-------------|------------|--------------|
| `rides` | 3 | 1 | `DashboardSyncEngine` |
| `favors` | 3 | 1 | `DashboardSyncEngine` |
| `notifications` | 3 | 1 | `DashboardSyncEngine` |

### Single-Owner Pattern

**`DashboardSyncEngine`** becomes the sole realtime subscriber for `rides`, `favors`, and `notifications`. It already writes to SwiftData. ViewModels observe changes through:

1. **SwiftData `@Query`** — Views like `FavorsDashboardView`, `RidesDashboardView`, and `NotificationsListView` already use `@Query` on `SDRide`, `SDFavor`, `SDNotification`. These react automatically when DashboardSyncEngine writes to SwiftData.
2. **Post-sync NSNotification** — For ViewModels that need to refresh derived state (filter badges, notification summaries), DashboardSyncEngine posts a notification after each sync completes (e.g., `.ridesDidSync`, `.notificationsDidSync`).

---

### PR 7A: Consolidate Rides Subscriptions (3 → 1)

**Subscriptions to remove:**
1. `RidesDashboardViewModel.swift:201` — `"rides-dashboard"` channel
2. `RequestRealtimeHandler.swift:76` — `"requests-dashboard-rides"` channel

**Subscription to keep:**
- `DashboardSyncEngine.swift:106` — `"rides:sync"` channel

**Files to modify:**

| # | File | Change |
|---|------|--------|
| 1 | `Features/Rides/ViewModels/RidesDashboardViewModel.swift` | Remove `setupRealtimeSubscription()` method and the `subscribe()` call (~lines 197-225). Remove `realtimeManager` property. The view already uses `@Query` for SwiftData rides — it reacts to DashboardSyncEngine's writes automatically. |
| 2 | `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | Remove rides subscription setup (~lines 76-83). Remove `handleRideRealtimeEvent()` method (~lines 145-156) and `scheduleRideRealtimeSync()`. Keep favors and notifications subscriptions (removed in 7B/7C). |
| 3 | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` | Verify `@Query` in `RequestsDashboardView` covers the data path for rides. If `RequestRealtimeHandler` was refreshing derived state (filter badges), wire that to observe a `.ridesDidSync` NSNotification from DashboardSyncEngine instead. |
| 4 | `Core/Storage/DashboardSyncEngine.swift` | Optionally: post `.ridesDidSync` after `syncRides()` completes so ViewModels that need to refresh derived state can observe it. |
| 5 | `Core/Utilities/NotificationNames.swift` | Add `.ridesDidSync` if the post-sync notification approach is used. |

**Done criteria:**
```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
grep -rn '"rides-dashboard"\|"requests-dashboard-rides"' NaarsCars/ --include="*.swift"
# Expected: 0 results
# Manual smoke: create a ride → appears on dashboard. Claim a ride → status updates on both parties.
```

**Scope boundary:** Do NOT touch favors or notifications subscriptions (those are 7B/7C). Do NOT change DashboardSyncEngine's subscription or sync logic.

**Rollback:** `git revert`. ViewModel subscriptions restored. Triple-subscription resumes.

---

### PR 7B: Consolidate Favors Subscriptions (3 → 1)

**Subscriptions to remove:**
1. `FavorsDashboardViewModel.swift:199` — `"favors-dashboard"` channel
2. `RequestRealtimeHandler.swift:85` — `"requests-dashboard-favors"` channel

**Subscription to keep:**
- `DashboardSyncEngine.swift:118` — `"favors:sync"` channel

**Files to modify:**

| # | File | Change |
|---|------|--------|
| 1 | `Features/Favors/ViewModels/FavorsDashboardViewModel.swift` | Remove `setupRealtimeSubscription()` and `subscribe()` call. Remove `realtimeManager` property. View already uses `@Query` for `SDFavor`. |
| 2 | `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | Remove favors subscription setup (~lines 85-92). Remove `handleFavorRealtimeEvent()` and `scheduleFavorRealtimeSync()`. After 7A+7B, only the notifications subscription remains in this file. |
| 3 | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` | Same pattern as 7A — verify `@Query` in `RequestsDashboardView` covers favors. Wire derived state refresh to `.favorsDidSync` if needed. |
| 4 | `Core/Storage/DashboardSyncEngine.swift` | Optionally: post `.favorsDidSync` after `syncFavors()` completes. |
| 5 | `Core/Utilities/NotificationNames.swift` | Add `.favorsDidSync` if used. |

**Done criteria:**
```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
grep -rn '"favors-dashboard"\|"requests-dashboard-favors"' NaarsCars/ --include="*.swift"
# Expected: 0 results
# Manual smoke: create a favor → appears. Claim a favor → status updates.
```

**Scope boundary:** Do NOT touch rides (done in 7A) or notifications (7C).

**Rollback:** `git revert`.

---

### PR 7C: Consolidate Notifications Subscriptions (3 → 1)

> This is the most nuanced PR because the removed subscribers do lightweight payload inspection.

**Subscriptions to remove:**
1. `NotificationRealtimeHandler.swift:42` — `"notifications:all"` channel
2. `RequestRealtimeHandler.swift:96` — `"requests-dashboard-notifications"` channel

**Subscription to keep:**
- `DashboardSyncEngine.swift:132` — `"notifications:sync"` channel

**Current payload inspection in removed subscribers:**
- `NotificationRealtimeHandler` checks `record["type"]` to skip `message`/`added_to_conversation` notifications and decide between immediate reload vs. debounced reload
- `RequestRealtimeHandler` checks `record["type"]` to filter request-related notification types before refreshing summaries

**Proposed approach:** After `DashboardSyncEngine.triggerNotificationsSync()` completes its SwiftData write, post `.notificationsDidSync`. ViewModels observe this to refresh derived state. The type-filtering logic moves to post-sync processing (reading from SwiftData) rather than from the realtime payload.

**Files to modify:**

| # | File | Change |
|---|------|--------|
| 1 | `Core/Storage/DashboardSyncEngine.swift` | In `triggerNotificationsSync()`, after `syncNotifications()` completes, post `NotificationCenter.default.post(name: .notificationsDidSync)`. |
| 2 | `Core/Utilities/NotificationNames.swift` | Add `.notificationsDidSync` |
| 3 | `Features/Notifications/ViewModels/NotificationRealtimeHandler.swift` | Remove `setupSubscription()` and `RealtimeManager.subscribe()` call. Replace with `NotificationCenter.default.addObserver(forName: .notificationsDidSync)` that calls the existing `onRealtimeReload` closure. Type-filtering logic (`type != message/addedToConversation`) can be applied after reading from SwiftData instead of from the realtime payload. |
| 4 | `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | Remove notifications subscription (~lines 96-103) and `handleRequestNotificationEvent()`. Replace with observer for `.notificationsDidSync` that refreshes request notification summaries. After 7A+7B+7C, `RequestRealtimeHandler` has zero RealtimeManager subscriptions. Consider renaming to `RequestChangeHandler` or merging remaining logic back into parent ViewModel if minimal. |
| 5 | `Features/Notifications/ViewModels/NotificationsListViewModel.swift` | Verify that the view's `@Query` on `SDNotification` provides reactivity. The `NotificationRealtimeHandler`'s role shrinks to "call `loadNotifications()` when SwiftData changes." |

**Done criteria:**
```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
grep -rn '"notifications:all"\|"requests-dashboard-notifications"' NaarsCars/ --include="*.swift"
# Expected: 0 results
```

**Post-consolidation subscription count:**
```
Remaining: 7 channels (down from 13)
  messages:sync          → MessagingSyncEngine
  rides:sync             → DashboardSyncEngine
  favors:sync            → DashboardSyncEngine
  notifications:sync     → DashboardSyncEngine
  town-hall-posts        → TownHallSyncEngine
  town-hall-comments     → TownHallSyncEngine
  town-hall-votes        → TownHallSyncEngine
  + per-conversation typing:{id} → TypingIndicatorManager
```

**Manual smoke test:**
- [ ] Receive notification → appears in bell
- [ ] Claim a ride → request notification appears
- [ ] Mark notification as read → badge updates
- [ ] New ride posted → Requests tab badge increments
- [ ] Town Hall comment → notification in bell

**Scope boundary:** Do NOT change `DashboardSyncEngine` sync logic itself (fetch + SwiftData write). Only add post-sync notifications. Do NOT remove `NotificationRealtimeHandler` or `RequestRealtimeHandler` classes entirely — just replace their subscription code with NSNotification observers.

**Rollback:** `git revert`. All 3 notification-table subscriptions restored.

---

## Execution Order

### Phase 6 PRs are independent — any order works:
- **6A** (notification names) — biggest diff, lowest risk
- **6B** (Sendable) — 2-line change
- **6C** (error isolation) — ~15 lines
- **6D** (observability) — ~12 lines

### Phase 7 PRs are sequential:
- **7A** (rides) → **7B** (favors) → **7C** (notifications)

`RequestRealtimeHandler` is progressively gutted across all three. After 7C it has zero `RealtimeManager` subscriptions.

---

## Summary

| PR | Files touched | Subscriptions after | Risk | Effort |
|----|-------------|---------------------|------|--------|
| **6A** | 1 new + 21 modified | 13 (unchanged) | Very low | Medium (many files, simple changes) |
| **6B** | 1 modified (2 lines) | 13 (unchanged) | Very low | Trivial |
| **6C** | 1 modified (~15 lines) | 13 (unchanged) | Very low | Trivial |
| **6D** | 1 modified (~12 lines) | 13 (unchanged) | Very low | Trivial |
| **7A** | 3-5 modified | 11 | Low-medium | Medium |
| **7B** | 3-5 modified | 9 | Low-medium | Medium |
| **7C** | 4-5 modified | 7 | Medium | Medium-high |
