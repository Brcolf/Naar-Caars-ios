# Notification System Review Tasklist

This tasklist is derived from a code review of the current iOS + Supabase
notification system and the requirements you outlined. It focuses on gaps,
broken paths, and best‑practice improvements.

## Global / Infrastructure

- [ ] Verify Supabase migrations `080_fix_notification_triggers_critical.sql`,
  `081_fix_realtime_messaging.sql`, and `082_fix_notification_queue_processing.sql`
  are deployed to production.
- [ ] Ensure `notification_queue` processing is **actually invoked** in prod:
  configure a DB Webhook on INSERT/UPDATE or a scheduled Edge Function to call
  `send-notification` (the function does not auto-run without a trigger).
- [ ] Confirm APNs env vars are set (`APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY`,
  `APNS_BUNDLE_ID`, `APNS_PRODUCTION`) and match the current bundle + build type.
- [ ] Update push badge calculation in `send-notification` to include **unread
  messages** plus **unread in-app notifications** (currently only unread
  notifications + 1).
- [ ] Add a server-side unread messages count query (per user) or a cached
  counter to compute accurate badges for push payloads.
- [ ] Validate RLS for `notifications`, `notification_queue`, and `messages`
  so realtime + webhook delivery works for the intended recipients.

## iOS Push Setup & Registration

- [ ] Ensure notification categories are registered on app launch (not just
  when `PushNotificationService.shared` is first referenced).
- [ ] Register device tokens after **login** as well as at app launch. Right
  now the app only registers if `currentUserId` exists when APNs returns a token.
- [ ] Store the last APNs token locally and re-register when the user changes.
- [ ] Add defensive logging for push permission state, token registration,
  and APNs errors (device + environment) to speed debugging.

## Push Action Handling (Completion Reminder)

- [ ] Route UNNotification actions to `PushNotificationService.handleNotificationAction`
  from `AppDelegate.userNotificationCenter(_:didReceive:...)`.
- [ ] Remove `.foreground` from the **Yes** action to allow background response
  without opening the app (per requirement).
- [ ] Validate iOS background handling for action responses and that the RPC
  `handle_completion_response` runs even when the app is suspended.
- [ ] Ensure action categories match between APNs payload and iOS registration.

## Deep Linking & Navigation

- [ ] Expand `AppDelegate.handleDeepLink` to handle:
  `townHall`, `townHallPost`, `adminPanel`, `dashboard`, `enterApp`.
- [ ] Implement a real destination for `.notifications` (currently posts an
  event that no view listens to).
- [ ] Align deep‑link source: standardize on `DeepLinkParser` (or the service)
  and remove/merge duplicate parsing logic.
- [ ] Add unit tests for deep links (Town Hall, admin, review_request, user_approved).

## In‑App Notifications List + Read State

- [ ] Decide where the in‑app notifications list lives in the UI (currently
  there is no navigation path to `NotificationsListView`).
- [ ] Fix `NotificationService.fetchNotifications` caching so realtime updates
  are not blocked by stale cache (invalidate on insert/update, or bypass cache
  for notifications).
- [ ] Include `notification_id` in push payloads (from `create_notification`)
  so tapping a push can mark that specific notification as read.
- [ ] Implement “mark-as-read on push tap” and “mark-as-read on deep link”.
- [ ] Ensure clearing behavior is **scoped** (not clearing all request‑related
  notifications when opening the Requests tab).

## Requests Dashboard Flow

- [ ] Confirm new ride/favor triggers run correctly in prod (fixed column names).
- [ ] Add Q&A **answer** notifications (currently only INSERT questions trigger;
  answers are UPDATEs and are not notifying anyone).
- [ ] Notify **all question participants** (anyone who asked a question),
  not just poster + ride/favor participants.
- [ ] Attach `notification_id` to push payloads for new requests, status changes,
  and Q&A to support read clearing.
- [ ] When the request detail screen is opened from a push, mark only the
  related notification(s) as read.

## Completion Reminder & Review Flow

- [ ] Replace or supplement **local-only** reminders with server‑scheduled push
  (cron/Edge) so reminders fire even if the claimer never reopens the app.
- [ ] Ensure completion reminder push fires in both background and foreground.
- [ ] Fix `showReviewPrompt` userInfo keys (`rideId`/`favorId` vs `ride_id`/`favor_id`).
- [ ] When `review_request` push is tapped, open the review prompt directly
  (not just the request detail screen).
- [ ] Ensure review completion clears the `review_request` notification.

## Messaging

- [ ] Avoid duplicate alerts: app currently shows **local** notifications for
  realtime messages even when a remote push also arrives. Decide on a single
  foreground strategy (e.g., suppress local if remote is expected).
- [ ] Update the **Messages tab badge** immediately on realtime inserts
  (BadgeCountManager currently refreshes only on app‑active).
- [ ] Validate `last_seen` logic for suppressing push when a user is actively
  viewing a conversation (60s window).
- [ ] Confirm “added to conversation” push deep‑links into the correct thread.

## Town Hall

- [ ] Add a **Town Hall notifications** toggle in Settings and wire it to
  `profiles.notify_town_hall` (currently no UI to change this preference).
- [ ] Ensure Town Hall push taps deep‑link to Town Hall or the specific post.
- [ ] Keep reactions as **in‑app only** (no push).
- [ ] Ensure **posts/comments/replies** send push notifications (not just in‑app).

## Profile / Admin

- [ ] Ensure “pending approval” push deep‑links to the admin panel.
- [ ] Decide whether admin badges should be driven by **pending user count**
  (current) or by read status of notifications, and align behavior with “clear
  on view” requirement.
- [ ] Add a clear action when navigating from push to the admin queue to mark
  any pending_approval notifications as read.

## Pending Approval / Signup

- [ ] Confirm the permission prompt is shown on the pending approval screen
  and does not block normal flow.
- [ ] Route `user_approved` push to **login** (as requested) or to “enter app”
  and reconcile with current DeepLink behavior.
- [ ] Consider auto‑transition from PendingApprovalView when a `user_approved`
  push is received (in addition to periodic polling).

## QA / Validation

- [ ] Add a diagnostic screen or logging to inspect:
  notification permission status, current APNs token, and last push payload.
- [ ] Add end‑to‑end test checklist per flow (requests, Q&A, messages, town hall,
  admin approvals, completion reminders, review prompts).

## Settings UX for Mandatory Types

- [ ] Make “Announcements” and “New Requests” toggles **locked on** in Settings.
  Show them as mandatory with a short explanation, and prevent disabling.

## Review Request UX

- [ ] On `review_request` push tap, open the **review modal directly** (even if
  the request detail screen loads underneath).

## Verification Checklist (Must Follow)

- [ ] Confirm APNs env vars are set and correct (bundle ID + prod flag).
- [ ] Confirm device token registration after login and on first launch.
- [ ] Verify notification categories/actions registered on launch.
- [ ] Create ride request: in‑app + push to all users; tap push deep‑links to ride.
- [ ] Create favor request: in‑app + push to all users; tap push deep‑links to favor.
- [ ] Ask a question on a request: requestor + all question participants get in‑app + push.
- [ ] Answer a question: requestor + all question participants get in‑app + push.
- [ ] Claim/unclaim request: requestor + participants get in‑app + push.
- [ ] Completion reminder fires **without opening the app** (server‑scheduled or local).
- [ ] Completion reminder actions (Yes/No) work in background; Yes triggers review request.
- [ ] `review_request` push tap opens the **review modal** directly.
- [ ] Review submit posts to Town Hall automatically.
- [ ] New Town Hall post sends push (unless user disabled Town Hall notifications).
- [ ] Town Hall comment/reply sends push to poster + interactors.
- [ ] Town Hall reaction is in‑app only (no push).
- [ ] Message received while thread not visible sends push + updates message badges.
- [ ] Opening a conversation clears unread count and related in‑app notifications.
- [ ] Added to conversation sends push; tap opens correct thread.
- [ ] Admin pending approvals: push + profile/admin badges; tap opens admin panel.
- [ ] Approve user: user_approved push routes to login and works from cold start.
- [ ] In‑app notifications list shows new items in realtime (no stale cache).
- [ ] Tapping in‑app notification marks only that item read and clears correct badges.

