# Notification System Deployment Guide

This guide walks through deploying the comprehensive notification system for Naar's Cars.

## Pre-Deployment Checklist

Before deploying, ensure you have:
- [ ] Access to Supabase Dashboard
- [ ] APNs credentials configured in Supabase (Team ID, Key ID, .p8 key, Bundle ID)
- [ ] Xcode project with Push Notifications capability enabled

---

## Step 1: Deploy Database Migrations

If you use Supabase CLI, migrations apply automatically in timestamp order.
If running manually in SQL Editor, apply these in order:

1. `supabase/migrations/20260120_0000_notification_system_base.sql`
2. `supabase/migrations/20260121101500_notification_system_fixes.sql`
3. `supabase/migrations/20260126_0001_push_tokens.sql`
4. `supabase/migrations/20260126_0002_get_badge_counts.sql`
5. `supabase/migrations/20260126_0003_mark_request_notifications_read.sql`
6. `supabase/migrations/20260126_0004_town_hall_vote_trigger.sql`
7. `supabase/migrations/20260126_0005_notification_queue_processing.sql`
8. `supabase/migrations/20260126_0006_notifications_review_id.sql`
9. `supabase/migrations/20260126_0007_realtime_messaging.sql`
10. `supabase/migrations/20260126_0008_completion_reminders.sql`

---

## Step 2: Enable Server Scheduling (Required)

Completion reminders must be server-scheduled to deliver even when the app is not opened.
Choose one of the options below.

### Option A: Supabase Pro Plan

1. Go to Supabase Dashboard → Database → Extensions
2. Enable `pg_cron` extension
3. Run the following in SQL Editor:

```sql
-- Schedule completion reminder processing every minute
SELECT cron.schedule(
    'process-completion-reminders',
    '* * * * *',
    'SELECT process_completion_reminders();'
);

-- Schedule batched notification processing every 3 minutes
SELECT cron.schedule(
    'process-batched-notifications', 
    '*/3 * * * *',
    'SELECT process_batched_notifications();'
);

-- Verify jobs are scheduled
SELECT * FROM cron.job;
```

### Option B: External Cron (Free Alternative)

If not on Pro plan, use an external service to call the functions:

1. Create a scheduled Edge Function or use services like:
   - [EasyCron](https://www.easycron.com/)
   - [cron-job.org](https://cron-job.org/)
   - GitHub Actions with `cron` trigger

2. Call these URLs every minute/3 minutes respectively:
   - `POST /rest/v1/rpc/process_completion_reminders`
   - `POST /rest/v1/rpc/process_batched_notifications`

---

## Step 3: Deploy Edge Function

### 3.1 Deploy send-notification Function

```bash
cd supabase/functions
supabase functions deploy send-notification
```

### 3.2 Configure Webhook

Go to Supabase Dashboard → Database → Webhooks:

1. Click "Create a new hook"
2. Configure:
   - **Name**: `notification-queue-processor`
   - **Table**: `notification_queue`
   - **Events**: INSERT, UPDATE
   - **Type**: Supabase Edge Functions
   - **Function**: `send-notification`
3. Save

3. Configure message webhook (if using `send-message-push`):
   - **Name**: `message-push-processor`
   - **Table**: `messages`
   - **Events**: INSERT
   - **Type**: Supabase Edge Functions (preferred) or HTTP Request (legacy)
   - **Function**: `send-message-push`

---

## Step 4: Verify APNs Configuration

1. Go to Supabase Dashboard → Project Settings → Auth
2. Scroll to "Push Notifications"
3. Ensure these are configured:
   - APNs Key (.p8 file content)
   - APNs Key ID
   - APNs Team ID
   - Bundle ID

Or set them as Edge Function secrets:

```bash
supabase secrets set APNS_KEY="<base64-encoded .p8 file>"
supabase secrets set APNS_KEY_ID="your-key-id"
supabase secrets set APNS_TEAM_ID="your-team-id"
supabase secrets set APNS_BUNDLE_ID="your.bundle.id"
supabase secrets set APNS_PRODUCTION="false"  # Set to "true" for production
```

---

## Step 5: Build and Test iOS App

### 5.1 Archive and Upload to TestFlight

```bash
# In Xcode:
# 1. Select "Any iOS Device" as destination
# 2. Product → Archive
# 3. Distribute App → App Store Connect
# 4. Upload
```

### 5.2 Test Notification Scenarios

| Test | Expected Result |
|------|----------------|
| Create new ride | All users receive notification |
| Create new favor | All users receive notification |
| Claim a ride | Requestor + co-requestors notified |
| Post Q&A question (unclaimed) | Requestor + co-requestors notified |
| Post Q&A question (claimed) | No notification (use messages) |
| New Town Hall post | Users notified (batched every 3 min) |
| Comment on Town Hall post | Poster + interactors notified |
| New user signs up | All admins notified |
| Admin approves user | User notified, app transitions |
| 1 hour after claimed request time | Claimer gets completion reminder |
| Tap "Yes" on completion reminder | Request marked complete, requestor gets review prompt |
| Tap "No" on completion reminder | Reminder rescheduled +1 hour |

---

## Step 6: Monitor and Debug

### View Notification Queue

```sql
-- Check pending notifications
SELECT * FROM notification_queue 
WHERE sent_at IS NULL 
ORDER BY created_at DESC 
LIMIT 50;

-- Check completion reminders
SELECT * FROM completion_reminders 
WHERE completed = false 
ORDER BY scheduled_for;
```

### View Edge Function Logs

```bash
supabase functions logs send-notification
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Notifications not sending | Check APNs credentials, verify tokens in push_tokens table |
| Badge count wrong | Call BadgeCountManager.shared.refreshAllBadges() |
| Completion reminder not firing | Check pg_cron job status, verify completion_reminders table |
| Town Hall notifications too frequent | Verify batch_key is being set correctly |

---

## Rollback Plan

If issues occur, disable triggers:

```sql
-- Disable all notification triggers
ALTER TABLE rides DISABLE TRIGGER on_ride_created_notify;
ALTER TABLE favors DISABLE TRIGGER on_favor_created_notify;
ALTER TABLE rides DISABLE TRIGGER on_ride_status_change_notify;
ALTER TABLE favors DISABLE TRIGGER on_favor_status_change_notify;
ALTER TABLE request_qa DISABLE TRIGGER on_qa_created_notify;
ALTER TABLE town_hall_posts DISABLE TRIGGER on_town_hall_post_notify;
ALTER TABLE town_hall_comments DISABLE TRIGGER on_town_hall_comment_notify;
ALTER TABLE town_hall_votes DISABLE TRIGGER on_town_hall_vote_notify;
ALTER TABLE profiles DISABLE TRIGGER on_pending_user_notify;
ALTER TABLE profiles DISABLE TRIGGER on_user_approved_notify;
ALTER TABLE conversation_participants DISABLE TRIGGER on_added_to_conversation_notify;

-- Re-enable when ready
-- ALTER TABLE <table> ENABLE TRIGGER <trigger_name>;
```

---

## Files Changed Summary

### Database Migrations
- `076_notification_system_overhaul.sql` - Schema + helper functions
- `077_notification_triggers.sql` - All notification triggers
- `078_pg_cron_notification_jobs.sql` - Cron job functions

### Edge Functions
- `supabase/functions/send-notification/index.ts` - Unified push sender

### iOS Files
- `AppNotification.swift` - New notification types
- `Profile.swift` - notifyTownHall preference
- `AppDelegate.swift` - Actionable notification categories
- `NavigationCoordinator.swift` - New deep link handling
- `DeepLinkParser.swift` - New notification type parsing
- `BadgeCountManager.swift` - Enhanced badge counting
- `PendingApprovalView.swift` - Push permission on pending

---

## Post-Deployment

After successful deployment:

1. [ ] Monitor Edge Function logs for errors
2. [ ] Test all notification scenarios manually
3. [ ] Verify badge counts update correctly
4. [ ] Test completion reminder flow end-to-end
5. [ ] Verify Town Hall batching works (wait 3+ minutes)
6. [ ] Test admin approval notification flow


