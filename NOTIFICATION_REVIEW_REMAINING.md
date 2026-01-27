# Notification Review Remaining Tasks

These items could not be completed in this environment and should be finished on a local dev machine with Xcode + device access.

## Production Configuration
- Verify a DB webhook (or scheduled Edge Function) calls `send-notification` for `notification_queue` inserts/updates.
- Confirm APNs environment variables on Supabase:
  `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY`, `APNS_BUNDLE_ID`, `APNS_PRODUCTION`.

## iOS Device Validation (BCSPH iPhone 17 Pro)
- Run full notification flow checklist on device:
  - Completion reminder Yes/No in background, review prompt opens.
  - `review_request` push opens review modal directly.
  - Push tap marks only that notification read (via `notification_id`).
  - Town Hall post/comment deep‑links to Community tab or post.
  - Admin pending approval opens admin panel.
  - Messages: no duplicate local alert, badges update on realtime.
  - Settings: Announcements/New Requests locked on; Town Hall toggle works.

## Optional
- Update Supabase CLI to latest version (v2.72.7+) when convenient.


