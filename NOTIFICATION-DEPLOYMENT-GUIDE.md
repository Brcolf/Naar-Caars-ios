# Notification System Deployment Guide

This guide walks through deploying the comprehensive notification system for Naar's Cars.

## Pre-Deployment Checklist

Before deploying, ensure you have:
- [ ] Access to Supabase Dashboard
- [ ] APNs credentials configured in Supabase (Team ID, Key ID, .p8 key, Bundle ID)
- [ ] Xcode project with Push Notifications capability enabled

---

## Step 1: Deploy Database Migrations

Run these migrations in order via Supabase SQL Editor:

### 1.1 Run Schema Migration (076)

```bash
# File: database/076_notification_system_overhaul.sql
# This adds:
# - notify_town_hall column to profiles
# - town_hall_post_id and source_user_id to notifications
# - notification_queue table for batching
# - completion_reminders table
# - town_hall_post_interactions table
# - Helper functions: should_notify_user, create_notification, queue_push_notification
```

Go to Supabase Dashboard → SQL Editor → Run the contents of `076_notification_system_overhaul.sql`

### 1.2 Run Triggers Migration (077)

```bash
# File: database/077_notification_triggers.sql
# This adds triggers for:
# - New ride/favor → notify all users
# - Ride/favor claimed/unclaimed/completed → notify requestor + co-requestors
# - Q&A activity → notify requestor + co-requestors (only if not claimed)
# - Town Hall post → queue batched notification
# - Town Hall comment/vote → notify poster + interactors
# - New pending user → notify all admins
# - User approved → notify user
# - Added to conversation → notify user
```

Go to Supabase Dashboard → SQL Editor → Run the contents of `077_notification_triggers.sql`

### 1.3 Run pg_cron Migration (078)

```bash
# File: database/078_pg_cron_notification_jobs.sql
# This adds:
# - handle_completion_response function (for Yes/No from notification)
# - process_completion_reminders function
# - process_batched_notifications function
# - last_used_at column to push_tokens
```

Go to Supabase Dashboard → SQL Editor → Run the contents of `078_pg_cron_notification_jobs.sql`

---

## Step 2: Enable pg_cron (Supabase Pro Required)

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
   - **Events**: INSERT
   - **Type**: Supabase Edge Functions
   - **Function**: `send-notification`
3. Save

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

