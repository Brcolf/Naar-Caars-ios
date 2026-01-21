# Notification Review Handoff

## Remaining Tasks (Blocking)
- Apply `database/090_notification_system_fixes.sql` to Supabase (adds `notification_id` to push payloads, Q&A answer trigger, completion reminder fixes, unread message count RPC).
- Deploy Edge Function `supabase/functions/send-notification` (updated badge logic + completion reminder queue processing).
- Ensure database webhook (or scheduled Edge Function) processes `notification_queue` inserts/updates in prod.
- Confirm APNs env vars on Supabase (`APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY`, `APNS_BUNDLE_ID`, `APNS_PRODUCTION`).
- Run iOS app tests on device “BCSPH” iPhone 17 Pro (push categories, deep links, action handling).
- Commit changes on `main` once DB + tests pass.

## Why These Are Pending
- Supabase CLI not authenticated in this environment (`supabase link` requires access token).
- Docker/CoreSimulator and Xcode cache locations are blocked by filesystem permission restrictions.
- Git writes are blocked in this environment (cannot stage/commit).

## Suggested Command Sequence (Local Machine)
```bash
# From repo root
supabase login
supabase link --project-ref easlpsksbylyceqiqecq

# Apply migration
supabase db push
# or run SQL manually in dashboard:
# database/090_notification_system_fixes.sql

# Deploy Edge Function
supabase functions deploy send-notification

# (Optional) Re-deploy send-message-push if needed
supabase functions deploy send-message-push

# Verify webhook / cron for notification_queue
# Supabase Dashboard → Database → Webhooks

# iOS device validation (BCSPH attached in Xcode)
# Run app from Xcode and execute notification checklist

# Commit
git add NaarsCars supabase database
git commit -m "Fix notification flow, badges, and review prompts"
```

## Manual Test Checklist (Device)
- Completion reminder action Yes/No works in background; Yes shows review prompt.
- `review_request` push opens review modal directly.
- `notification_id` in payload marks only that notification as read on tap.
- Town Hall post/comment push deep-links to Community tab or post.
- Admin pending approval push opens admin panel.
- Messages: foreground push suppressed (no duplicate local alert), badges update on realtime.
- Settings: Announcements/New Requests locked on; Town Hall toggle works.

