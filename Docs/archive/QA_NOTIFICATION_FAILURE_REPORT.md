# QA Investigation: In-App Notifications & Badges Failure

## 🚨 Root Cause: Missing Database Functions
The primary reason none of the in-app notifications or badges are appearing is that the **required database RPC functions are missing** from the Supabase schema. The console logs show repeated `PGRST202` errors:

- `Could not find the function public.get_badge_counts(p_include_details) in the schema cache`
- `Could not find the function public.mark_request_notifications_read(...) in the schema cache`

These functions were defined in migrations `091_request_notification_read_scoped.sql` and `092_badge_counts_rpc.sql`. **These migrations must be applied to the database for the system to function.**

---

## 1. Badge Logic Failure
- **Behavior:** All tab badges and the global bell badge remain at `0`.
- **Reason:** `BadgeCountManager` relies on `get_badge_counts` as the "Single Source of Truth." When this call fails, the manager logs an error and aborts the update, leaving the UI state stale.
- **Impact:** Users have no visual indication of new messages or request activity.

## 2. Notification Clearing Failure
- **Behavior:** Even if notifications were visible, they would never clear when viewing a request.
- **Reason:** `NotificationService.markRequestScopedRead` calls the missing `mark_request_notifications_read` RPC.
- **Impact:** "Phantom" badges that persist even after the user has acted on the content.

## 3. In-App Toast Scope (Architectural Issue)
- **Requirement:** `R-OUTSIDE-3` requires in-app UI alerts when the user is anywhere in the app (foreground).
- **Current Implementation:** The `toastOverlay` for new messages is currently defined inside `ConversationsListView.swift`.
- **Bug:** If a user is on the **Requests**, **Community**, or **Profile** tabs, they will **never see the in-app toast** for a new message.
- **Fix:** The toast logic needs to be moved to a global level (e.g., `MainTabView` or a global `OverlayManager`).

## 4. Foreground Push Behavior
- **Requirement:** `R-OUTSIDE-3` explicitly states: *"If the app is in the foreground, do not rely on APNS push delivery... Use in-app UI only."*
- **Observation:** You mentioned not seeing anything in the "notification center." This is **expected behavior** for the foreground state per the PRD. However, because the in-app UI (badges and toasts) is failing due to the missing RPCs, the user receives no alert at all.

---

## Recommended Fixes
1.  **Apply Migrations:** Run `091_request_notification_read_scoped.sql` and `092_badge_counts_rpc.sql` in the Supabase SQL Editor.
2.  **Globalize Toasts:** Move the `latestToast` state and rendering from `ConversationsListViewModel/View` to a global state manager so it can appear over any tab.
3.  **Verify Approval Status:** Ensure the test accounts are marked as `approved = true` in the `profiles` table, as the notification triggers (e.g., `notify_new_ride`) filter for approved users only.


