# Debug Session 2026-02-08: Freeze, Notification→Ride Hang, Push

## What fixed notification → ride navigation

Navigation from the **notifications sheet** to ride (or favor) details was fixed by **deferring navigation until after the sheet is dismissed**. Previously we set `selectedTab` and `navigateToRide` in the same run loop as the tap while the sheet was still presented, which led to tab switch + push happening under the sheet and could trigger `_UIReparentingView` / broken hierarchy and a mid-load hang. Now we store a `PendingNotificationNavigation` on `NavigationCoordinator` when the user taps a notification, post only the dismiss, and in **MainTabView**’s notifications sheet **`onDismiss`** we call `applyPendingNotificationNavigation()`. Tab and detail navigation run only after the sheet has been dismissed.

---

## Summary of issues

1. **App freezes after background → foreground** – Put app in background, bring back; UI is frozen for a while.
2. **Notification tap → ride details “mid-load” hang** – Tap a notification to open ride details; app doesn’t crash but navigation is stuck mid-load.
3. **Push notifications not working** – On both iPhone 17 Pro and iPhone 12, remote pushes are not received.

---

## 1. Freeze after background → foreground

### What the logs show

- `App entered background, will auto-unsubscribe in 30 seconds`
- `App entered foreground`
- Then: `Refreshing badges (didBecomeActive)`, `Subscribing to channel: notifications:sync`, `Polling every 30s`, `Fetched 10 conversations via RPC`, `Fetched 154 notifications from network`, then unsubscribes from requests-dashboard-* and a lot of channel churn.

### Hypotheses

| # | Hypothesis | Evidence | Status |
|---|------------|----------|--------|
| A | **Main thread saturated** – On `didBecomeActive`, `BadgeCountManager.refreshAllBadges`, `RealtimeManager.restoreTrackedSubscriptionsIfNeeded` (resubscribe all channels), and view `.task`/`onChange` work all run. If too much runs on MainActor in a short window, the UI can feel frozen. | Logs show many “Subscribing/Subscribed/Unsubscribed” and “Fetched … from network” right after foreground. | **Plausible** |
| B | **Realtime resubscribe blocks** – `resubscribeAll()` runs on MainActor and awaits each `subscribe()` in a loop. If any subscribe has synchronous work or the run loop is starved, freeze is possible. | RealtimeManager is `@MainActor`; `restoreTrackedSubscriptionsIfNeeded` → `resubscribeAll()` runs on main. | **Plausible** |
| C | **“Result accumulator timeout”** – Logs show `Result accumulator timeout: 3.000000, exceeded` (likely Supabase/Realtime). Could indicate a stuck or slow operation that affects UI. | No match in app code; likely framework. | **Inconclusive** |
| D | **TabView + sheet state** – Returning to foreground with a sheet (e.g. notifications) or with tab state changing could trigger SwiftUI layout/transition work that blocks. | _UIReparentingView warnings later in logs. | **Possible contributor** |

### Recommended next steps — **partially done**

- **Defer heavy work (done):** Badge refresh and Realtime restore on `didBecomeActive` are now deferred to the **next run loop** (`DispatchQueue.main.async { Task { … } }`) so the first frame after foreground isn’t dominated by them. This may reduce the freeze.
- **Instrument (optional):** If freeze persists, add short timings for `refreshAllBadges` and `restoreTrackedSubscriptionsIfNeeded` to confirm which path correlates with the freeze.
- **Reduce churn (future):** When restoring subscriptions, avoid unnecessary unsubscribe/resubscribe of requests-dashboard when the Requests tab isn’t visible.

---

## 2. Notification tap → ride details “mid-load” hang

### What the logs show

- `[NotificationsListVM] Request target found: mainTop`
- `[NotificationsListView] Dismissing notifications surface`
- `Deep link to mainTop`
- Later: `[RideDetailView] No unread claimAction notifications to clear`, geocoding, etc. So sometimes the flow completes; other times it hangs “mid-load.”

### Code flow (current)

1. User taps notification row → `handleNotificationTap` → posts `.dismissNotificationsSurface` then **immediately** calls `handleNotificationNavigation(for:)`.
2. `handleNotificationNavigation` sets `coordinator.selectedTab = .requests`, `coordinator.requestNavigationTarget = target`, `coordinator.navigateToRide = rideId`.
3. **Same run loop:** NotificationsListView’s observer receives `.dismissNotificationsSurface` and posts `dismissNotificationsSheet`.
4. **Later:** NavigationCoordinator’s observer sets `navigateToNotifications = false` (sheet starts dismissing).
5. MainTabView’s `selectedTab` has already changed → tab switches to Requests.
6. RequestsDashboardView appears; `.onChange(of: navigationCoordinator.navigateToRide)` sets local `navigateToRide = rideId` → `RideDetailView(rideId:)` is pushed via `navigationDestination`.
7. RideDetailView’s `.task { await viewModel.loadRide(id: rideId) }` runs.

So we **switch tab and push RideDetailView before the notifications sheet has been told to dismiss**. The sheet is still presented while the tab and navigation stack under it are changing.

### Hypotheses

| # | Hypothesis | Evidence | Status |
|---|------------|----------|--------|
| A | **_UIReparentingView / broken hierarchy** – Doing tab switch + navigation push while the sheet is still presented can reparent views and trigger “Adding '_UIReparentingView' as a subview of UIHostingController.view is not supported”. That can leave the detail view in a bad hierarchy and not receive updates or inputs (stuck loading or frozen). | Logs show multiple `_UIReparentingView` and `UIHostingController.view` warnings. | **Likely** |
| B | **RideDetailView load never completes** – `loadRide(id:)` is async (network). If something blocks the MainActor or the task is cancelled, the spinner never goes away. | Possible but less likely if the same flow sometimes works. | **Possible** |
| C | **Race with RequestsDashboardView .task** – When we switch to Requests, `.task { viewModel.setup(…); await loadRequests(); setupRealtimeSubscription() }` runs. If that and RideDetailView’s load contend, or if the view hierarchy is broken, we could see a hang. | RequestsDashboardView .task and RideDetailView .task both run on appear. | **Possible** |

### Recommended fix (high confidence) — **IMPLEMENTED**

**Defer applying notification navigation until after the notifications sheet has been dismissed.**

- **Current:** We set `selectedTab` and `navigateToRide` (and `requestNavigationTarget`) in the same synchronous path as the tap, then the sheet dismiss is triggered asynchronously. So we change the tab and push the detail view while the sheet is still up.
- **Change (done):** When the user taps a notification in the sheet, we now store a `PendingNotificationNavigation` on `NavigationCoordinator` and only post `dismissNotificationsSurface`. In **MainTabView**’s notifications sheet **`onDismiss`**, we call `applyPendingNotificationNavigation()` so tab and detail navigation run only after the sheet has been dismissed.

This removes the simultaneous “dismiss sheet + change tab + push” and should eliminate or reduce the _UIReparentingView path and the mid-load hang.

---

## 3. Push notifications not working

### What the logs show

- `Stored APNs token locally: 1fb2a7903b18...`
- `APNs token received before login; will register after login.`
- `Updated device token for user 0DA568D8-924C-4420-8853-206A48D277B6`

So the app **does** get an APNs token and **does** register it for the user (we see “Updated device token”). Client-side registration appears to work.

### Hypotheses

| # | Hypothesis | Evidence | Status |
|---|------------|----------|--------|
| A | **Edge Functions not triggered** – `send-notification` / `send-message-push` are invoked by DB triggers or cron. If triggers aren’t firing or functions aren’t deployed for the right project, no push is sent. | Need to check Supabase dashboard / logs for trigger and function invocations. | **Check first** |
| B | **APNs environment mismatch** – TestFlight builds must use **production** APNs. If the backend (e.g. Supabase Edge or _shared/apns) uses sandbox URL for TestFlight devices, pushes fail. | send-notification and _shared/apns.ts use env to choose sandbox vs production. | **Verify** |
| C | **No push when app is in foreground** – If you only test with app open, some flows might skip sending (e.g. “don’t push if user is viewing conversation”). | Docs mention “Skipping push - user is viewing”. | **Possible** |
| D | **Token not in DB or RLS** – Row might not be inserted/updated in `push_tokens` (e.g. RLS or unique constraint). | Log says “Updated device token” which usually means upsert succeeded. | **Less likely** |
| E | **Permission or provisioning** – Push capability, provisioning profile, or entitlement wrong for TestFlight. | Would often affect “Updated device token” too; token is present. | **Less likely** |

### Recommended next steps

- **Checklist**: See **`Docs/PUSH-NOTIFICATIONS-CHECKLIST.md`** for a step-by-step push checklist (APNS_PRODUCTION, Database Webhooks, push_tokens, entitlements).
- Confirm **Supabase Edge** is using **production** APNs for TestFlight: set **`APNS_PRODUCTION`** = **`true`** in Edge Function secrets.
- In Supabase Database → Webhooks, verify a webhook on **`notification_queue`** (INSERT/UPDATE) invokes **`send-notification`**.
- Test with **app fully backgrounded or killed** and trigger a notification to rule out “skip when foreground” behavior.

---

## 4. Other log noise (no action needed for this session)

- **Firebase** – `firebaselogging-pa.googleapis.com` failures (hostname could not be found). Unrelated to the three issues above; can be disabled or ignored if Firebase isn’t used.
- **PerfPowerTelemetryClientRegistrationService / Sandbox restriction** – System telemetry; safe to ignore.
- **CAMetalLayer setDrawableSize width=0 height=0** – Common during transitions; usually harmless.
- **RTIInputSystemClient … valid sessionID** – Keyboard/input system; can be ignored unless you see keyboard-specific bugs.

---

## 5. Implementation plan

| Priority | Item | Owner | Notes |
|----------|------|--------|--------|
| 1 | **Defer notification navigation until sheet onDismiss** | Dev | ✅ Done. `PendingNotificationNavigation` + `applyPendingNotificationNavigation()` in coordinator; NotificationsListViewModel sets pending and posts dismiss; MainTabView sheet onDismiss applies pending. |
| 2 | **Instrument foreground freeze** | Dev | Optional if freeze persists; add timings for `refreshAllBadges` and `restoreTrackedSubscriptionsIfNeeded`. |
| 3 | **Defer or throttle foreground work** | Dev | ✅ Done. Badge refresh and Realtime restore on didBecomeActive deferred to next run loop in BadgeCountManager and RealtimeManager. |
| 4 | **Verify push: APNs env + Edge logs** | Dev/Ops | See **`Docs/PUSH-NOTIFICATIONS-CHECKLIST.md`**: set `APNS_PRODUCTION=true`, verify Database Webhooks for `notification_queue` → `send-notification`, confirm `push_tokens` row. |

---

## 6. Questions for you

1. **Freeze:** How long does the freeze last (seconds)? Does it eventually recover or do you have to kill the app?
2. **Push:** Are you testing with the app in background or force-quit when you expect the push? Have you ever seen a push in TestFlight on this project?
3. **Repro:** For the notification→ride hang, does it happen when you tap from the **bell dropdown/sheet** only, or also when opening the app from a **remote notification** tap (and if so, does the hang look the same)?

Once we have the deferred-navigation fix in place, we can re-test notification→ride and then use the same repro for any remaining foreground freeze, with instrumentation to confirm which path to optimize.
