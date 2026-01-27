## Notification System Review Reference

This document summarizes the full notification review, changes made, and the current state for handoff to another Codex agent.

### Scope
- iOS app notifications (APNs, local notifications, deep links, in‑app list, badges).
- Supabase DB triggers, functions, notification queue, and Edge Function `send-notification`.

### Key Findings Addressed
- Push categories were only registered when `PushNotificationService.shared` was first used.
- APNs tokens were only registered if user was already logged in when token arrived.
- Review prompt deep links and `showReviewPrompt` keys were inconsistent (`ride_id` vs `rideId`).
- Notification list existed but no navigation path; badge clearing was over‑aggressive.
- Realtime notification cache could block updates.
- Foreground message notifications could duplicate local + remote alerts.
- Push payloads didn’t include `notification_id` for mark‑as‑read on tap.
- Completion reminder logic relied on local scheduling only; server processing was not invoked.
- Q&A answers (UPDATE) did not trigger notifications.
- Badge counts for push lacked unread message counts.

### iOS Changes (app)
Files modified (high‑level):
- `NaarsCars/App/AppDelegate.swift`
- `NaarsCars/App/MainTabView.swift`
- `NaarsCars/App/NavigationCoordinator.swift`
- `NaarsCars/Core/Services/AuthService.swift`
- `NaarsCars/Core/Services/BadgeCountManager.swift`
- `NaarsCars/Core/Services/NotificationService.swift`
- `NaarsCars/Core/Services/ProfileService.swift`
- `NaarsCars/Core/Services/PushNotificationService.swift`
- `NaarsCars/Core/Services/ReviewService.swift`
- `NaarsCars/Core/Utilities/DeepLinkParser.swift`
- `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`
- `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift`
- `NaarsCars/Features/Profile/Views/MyProfileView.swift`
- `NaarsCars/Features/Profile/Views/SettingsView.swift`
- `NaarsCars/Features/Reviews/ViewModels/ReviewPromptManager.swift`
- `NaarsCarsTests/Core/Utilities/DeepLinkParserTests.swift`

Key behaviors implemented:
- Push categories registered at app launch (AppDelegate initializes `PushNotificationService`).
- APNs token stored locally and re‑registered on login/user change.
- Token cleanup on sign out.
- Actionable notification responses routed to `handleNotificationAction`.
- `review_request` push opens review modal directly; fixed `rideId`/`favorId` keys.
- Deep links expanded (town hall, admin panel, dashboard, enter app).
- Notifications list accessible from Profile.
- Realtime notification cache invalidated on insert/update.
- Request badge clearing no longer marks all request notifications read on tab switch.
- Foreground message push banners suppressed to avoid duplicates.
- Local message notifications only while app active.
- Badge counts refresh on realtime message insert.
- Town Hall toggle added in Settings; Announcements + New Requests locked on.
- Added Notification Diagnostics view in Settings (permission status, APNs token, last payload).

### Supabase DB Changes
New migration created and applied:
- `supabase/migrations/20260121101500_notification_system_fixes.sql`

Legacy reference SQL (kept but superseded by migration above):
- `database/090_notification_system_fixes.sql`

DB changes include:
- `queue_push_notification` signature now includes `notification_id` (payload includes it).
- `get_unread_message_count` RPC for accurate push badge counts.
- `handle_completion_response` updated to use correct columns + includes `notification_id`.
- `process_completion_reminders` updated to include `notification_id`.
- Q&A answer trigger on UPDATE (`notify_qa_answer`) + participant fanout.
- Updated triggers for ride/favor/new/town hall/admin/added‑to‑conversation to include `notification_id`.

### Edge Function Updates
File:
- `supabase/functions/send-notification/index.ts`

Changes:
- Badge count now includes unread messages via `get_unread_message_count`.
- Calls `process_completion_reminders` before queue processing.
- Processes unsent queue rows regardless of `processed_at` state (uses `sent_at`).

### Commits on `main`
- `baddd28` — “Fix notification flow and badges”
- `d98be1f` — “Add remaining notification verification tasks”

### Supabase CLI Actions Completed
- `supabase link --project-ref easlpsksbylyceqiqecq`
- `supabase db push` applied migration
- `supabase functions deploy send-notification`

### Remaining Manual Tasks
Documented in `NOTIFICATION_REVIEW_REMAINING.md`:
- Verify DB webhook or scheduled function that invokes `send-notification` in production.
- Confirm APNs env vars (`APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY`, `APNS_BUNDLE_ID`, `APNS_PRODUCTION`).
- Run device validation on “BCSPH” iPhone 17 Pro in Xcode (full checklist).
- Optional: update Supabase CLI to v2.72.7+.

### Lint Fixes
Added `import os` in:
- `NaarsCars/App/AppDelegate.swift`
- `NaarsCars/Core/Services/PushNotificationService.swift`

### Notes
- Worktree is clean after commits.
- Supabase migration grant adjusted to avoid function overload ambiguity:
  `GRANT EXECUTE ON FUNCTION queue_push_notification(UUID, TEXT, TEXT, TEXT, JSONB, TEXT, UUID) TO authenticated;`



