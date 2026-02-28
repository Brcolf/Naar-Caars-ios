# Lifecycle Refactor Audit & Regression Fixes

After the "Task in deinit" / stop() refactor across notification and dashboard ViewModels, this document records regression risks, verification, fixes, and how to manually verify each module.

---

## A) Per-module audit

### 1) Notifications (NotificationsListViewModel + NotificationsListView)

**Potential regression risks introduced by the refactor**
- Notification tap that should open **review modal** only dismissed the sheet; VM deinit ran before the review intent was applied.
- Any tap path that relied on the VM to post a notification (e.g. `.showReviewPrompt`) could race with sheet dismissal and `stop()`.

**What was verified**
- Traced tap flow: `NotificationRow` → `viewModel.handleNotificationTap` → `NotificationNavigationRouter.handleNotificationTap` → for review types called `handleReviewPromptNotification(notification)` (VM) which posts `.showReviewPrompt`. Sheet dismiss is triggered by `.dismissNotificationsSurface` → `.dismissNotificationsSheet` → coordinator sets `pendingIntent = nil` (in a `Task`). So review path depended on VM posting before sheet/VM teardown.

**Fix applied**
- **Review path:** For `reviewRequest` / `reviewReminder`, queue the intent on the **coordinator first** (synchronously): `NavigationCoordinator.shared.showReviewPromptFor(rideId: notification.rideId, favorId: notification.favorId)`, then post `.dismissNotificationsSurface`. No longer call `handleReviewPromptNotification` for review (VM not involved).
- **Logs:** Notification tap type, "Queued pendingReview", "Presenting ReviewModal", "Cleared pendingReview"; `stop()` logs what it cancels.

**Files changed**
- `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift` – review branch sets coordinator state then dismisses; tap logs.
- `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift` – `stop()` log.
- `NaarsCars/Features/Notifications/Views/NotificationsListView.swift` – tap initiation logs (type, id).
- `NaarsCars/App/NavigationCoordinator.swift` – logs in `showReviewPromptFor` and `resetReviewPrompt`.
- `NaarsCars/App/MainTabView.swift` – log when presenting review modal.

**How to manually verify**
1. Open notifications sheet (bell).
2. Tap a notification of type "review request" or "review reminder".
3. Sheet should dismiss and **Review prompt modal** (ReviewPromptSheet) should appear.
4. Console: "[NotificationNavigationRouter] Notification tapped type=review", "Queued pendingReview", "[MainTabView] Presenting ReviewModal", "[NavigationCoordinator] Cleared pendingReview".
5. Tap other notification types (ride, favor, message, announcement): each should navigate or open the expected destination after sheet dismisses.

---

### 2) Requests Dashboard (RequestsDashboardViewModel + RequestsDashboardView)

**Potential regression risks**
- `stop()` cancels `loadTask` and realtime subscription; if user had just triggered refresh and navigated away, load is cancelled (intended).
- Realtime updates might stop when view disappears (tab switch); must re-establish on reappear.

**What was verified**
- `.task` runs on appear and calls `setupRealtimeSubscription()`; `onDisappear` calls `stop()` which calls `realtimeHandler.cleanupRealtimeSubscription()`. No user-triggered navigation goes through the VM in a way that would be cancelled by `stop()` (navigation is via `NavigationLink` / `pendingIntent`).

**Fix applied**
- No code change for behavior; added `stop()` log only.

**Files changed**
- `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift` – log in `stop()`.

**How to manually verify**
1. Open Requests tab, wait for load (or pull-to-refresh).
2. Tap a request card → navigates to ride/favor detail.
3. Switch to another tab then back to Requests → list and realtime should work again (`.task` re-runs).
4. Pull-to-refresh, then immediately switch tab → refresh is cancelled (no crash).
5. Console on tab switch away: "[RequestsDashboardVM] stop() called; cancelling loadTask and realtime subscription".

---

### 3) Conversations List (ConversationsListViewModel + ConversationsListView)

**Potential regression risks**
- `stop()` cancels `loadTask` and `searchTask`; returning to the screen must allow new load and search.

**What was verified**
- `.task` runs on appear and calls `loadConversations()`; `loadTask` is used for the background sync part. When view reappears, a new `.task` runs. Search is re-triggered by user typing; `searchTask` is recreated in `performSearch`.

**Fix applied**
- No behavior change; added `stop()` log only.

**Files changed**
- `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift` – log in `stop()`.

**How to manually verify**
1. Open Messages tab; list loads.
2. Use search; results appear.
3. Switch tab and return; list and search work again.
4. Open a conversation, then pop back; list still works.
5. Console on leaving Messages tab: "[ConversationsListVM] stop() called; cancelling loadTask and searchTask".

---

### 4) Conversation Detail (ConversationDetailViewModel + ConversationSearchManager + ConversationDetailView)

**Potential regression risks**
- `stop()` removes `conversationUpdatedObserver`, stops typing, and calls `searchManager.stop()`. Returning to the same conversation must re-establish observer and typing.

**What was verified**
- View calls `viewModel.stop()` in `onDisappear`. On reappear, `onAppear` runs and calls `viewModel.conversationDidAppear()` and `viewModel.startTypingObservation()`. We already added in `conversationDidAppear()`: if `conversationUpdatedObserver == nil`, call `setupConversationUpdatedObserver()` so the observer is re-established after return.

**Fix applied**
- No additional code change; added `stop()` log only.

**Files changed**
- `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift` – log in `stop()`.

**How to manually verify**
1. Open a conversation; send/receive messages; use in-conversation search; see typing indicator.
2. Pop back to list, then open the same conversation again; messages, search, and typing still work.
3. Console when leaving conversation: "[ConversationDetailVM] stop() called; removing conversation observer, stopping typing and search".

---

### 5) Favors Dashboard (FavorsDashboardViewModel + FavorsDashboardView)

**Potential regression risks**
- `stop()` cancels `loadTask`; reappear must trigger load again.

**What was verified**
- `.task` runs on appear and calls `loadFavors()`; `onDisappear` calls `stop()`. No navigation action depends on the VM surviving after disappear.

**Fix applied**
- Log in `stop()` only.

**Files changed**
- `NaarsCars/Features/Favors/ViewModels/FavorsDashboardViewModel.swift` – log in `stop()`.

**How to manually verify**
1. Switch to Favors (if shown in your app flow); list loads.
2. Pull-to-refresh; navigate to a favor detail; return.
3. Switch tab away and back; list loads again.
4. Console: "[FavorsDashboardVM] stop() called; cancelling loadTask".

---

### 6) Rides Dashboard (RidesDashboardViewModel + RidesDashboardView)

**Potential regression risks**
- Same as Favors: `stop()` cancels `loadTask`.

**What was verified**
- Same pattern as Favors; `.task` re-runs on appear.

**Fix applied**
- Log in `stop()` only.

**Files changed**
- `NaarsCars/Features/Rides/ViewModels/RidesDashboardViewModel.swift` – log in `stop()`.

**How to manually verify**
1. Requests tab shows rides/favors; list and refresh work.
2. Tab away and back; list and realtime behavior intact.
3. Console: "[RidesDashboardVM] stop() called; cancelling loadTask".

---

### 7) Pending Users (PendingUsersViewModel + PendingUsersView)

**Potential regression risks**
- `stop()` cancels `loadTask`; approve/reject are fire-and-forget `Task { }` from buttons; VM is retained by view until view is removed.

**What was verified**
- Approve/reject run in one-off tasks; if user leaves the screen mid-action, the VM may still be alive (e.g. pushed detail). No navigation that depends on VM after disappear.

**Fix applied**
- Log in `stop()` only.

**Files changed**
- `NaarsCars/Features/Admin/ViewModels/PendingUsersViewModel.swift` – log in `stop()`.

**How to manually verify**
1. Open Pending Users (admin); list loads; approve or reject a user.
2. Navigate away (e.g. back or tab switch) and return; list reloads.
3. Console: "[PendingUsersVM] stop() called; cancelling loadTask".

---

## B) Robust fix for notification tap → review modal

**Requirement:** Notification tap that should open the review modal must work even when NotificationsListView/VM dismisses immediately.

**Solution:** Queue the review intent on the **long-lived** NavigationCoordinator **before** dismissing the notifications surface. The root (MainTabView) observes `showReviewPrompt` and presents the review modal; it does not depend on the notifications VM.

**Implementation:**
1. In `NotificationNavigationRouter.handleNotificationTap`, for `reviewRequest` and `reviewReminder`:
   - Call `NavigationCoordinator.shared.showReviewPromptFor(rideId: notification.rideId, favorId: notification.favorId)` **first** (synchronous).
   - Then post `.dismissNotificationsSurface`.
   - Return without calling `handleReviewPromptNotification` (VM no longer used for this path).
2. Coordinator already had `showReviewPromptFor` and MainTabView already had `.onChange(of: navigationCoordinator.showReviewPrompt)` presenting the review fullScreenCover; no change there.
3. Logs added: "Notification tapped type=review", "Queued pendingReview", "Presenting ReviewModal", "Cleared pendingReview".

**Files changed**
- `NotificationNavigationRouter.swift` – review branch queues on coordinator then dismisses; tap logs.
- `NavigationCoordinator.swift` – logs in `showReviewPromptFor` and `resetReviewPrompt`.
- `MainTabView.swift` – log when presenting review modal.

---

## Verification checklist (concise)

| Module              | Verify |
|---------------------|--------|
| Notifications       | Tap review notification → sheet dismisses, **review modal appears**. Tap ride/favor/message → correct navigation. |
| Requests Dashboard  | Load, refresh, tap into request, tab away/back; realtime and list still work. |
| Conversations List  | Load, search, open conversation, tab away/back; list and search work. |
| Conversation Detail | Enter conversation, type/search/typing, pop and re-enter; observer and typing re-established. |
| Favors Dashboard    | Load, refresh, navigate to favor, tab away/back. |
| Rides Dashboard     | Same as Favors in Requests tab. |
| Pending Users       | Load, approve/reject, leave and return. |

---

## Constraints kept

1. **No `Task { }` in deinit** – deinit does not start async work.
2. **stop() / cancellation model kept** – All modules still use `stop()` from `onDisappear` and stored tasks for load/refresh.
3. **User actions not tied to dying VM** – Review intent is now on the coordinator before dismiss; other notification intents set `pendingIntent` synchronously after posting dismiss.
4. **stop() does not cancel a just-queued intent** – For review, we queue the intent first, then dismiss; `stop()` runs when the sheet’s view disappears, after the coordinator already has the intent.
