# CRITICAL: Notification System Fix

## Verification Performed

This fix was thoroughly verified against the existing codebase:

1. **Column names verified** against iOS models:
   - `Ride.swift` - uses `userId = "user_id"` ✓
   - `Favor.swift` - uses `userId = "user_id"` ✓
   - `RequestQA.swift` - uses `question` and `answer` columns ✓
   - `TownHallPost.swift` - uses `content` column ✓

2. **Function signatures verified**:
   - `create_notification()` - 11 params (last one optional) ✓
   - `queue_push_notification()` - 6 params (last 2 optional) ✓
   - All calls match expected signatures ✓

3. **Q&A implementation analyzed**:
   - Questions are INSERTs with `question` column
   - Answers are UPDATEs setting `answer` column (not threaded replies)
   - Trigger correctly handles INSERT-only scenario ✓

---

## Summary of Issues Found

After a comprehensive review of the notification system, I identified **multiple critical bugs** that were breaking:
1. **Posting rides and favors** - triggers were failing due to wrong column names
2. **Push notifications** - not being sent due to queue processing issues
3. **In-app notifications** - not being created due to trigger failures
4. **Real-time messaging** - not working due to missing realtime configuration
5. **Message notifications** - not being sent due to trigger issues

## Root Causes

### 1. Wrong Column Names in Triggers (CRITICAL)
The notification triggers in `077_notification_triggers.sql` referenced columns that don't exist:
- **`posted_by`** - The actual column is **`user_id`** in both `rides` and `favors` tables
- **`destination_name`** - The actual column is **`destination`** in the `rides` table
- **`scheduled_time`** - This column doesn't exist; rides/favors use **`date`** + **`time`** columns
- **`content`** in request_qa - The actual column is **`question`**

This caused ALL triggers to fail silently when inserting rides/favors, which:
- Prevented notifications from being created
- May have caused the entire INSERT to fail in some cases

### 2. Missing Realtime Configuration
The messages table wasn't properly configured for Supabase Realtime:
- Missing `REPLICA IDENTITY FULL` setting
- Not added to `supabase_realtime` publication
- RLS policies not optimized for realtime broadcasts

### 3. Notification Queue Not Being Processed
The `notification_queue` table stores push notifications, but:
- No trigger to mark non-batched notifications as processed
- Edge Function webhook not being triggered properly
- Missing RLS policies on the queue table

## Fixes Applied

### Migration 080: Fix Notification Triggers (CRITICAL)
**File:** `database/080_fix_notification_triggers_critical.sql`

Fixes all trigger functions:
- `notify_new_ride()` - Fixed `posted_by` → `user_id`, `destination_name` → `destination`
- `notify_new_favor()` - Fixed `posted_by` → `user_id`
- `notify_ride_status_change()` - Fixed `posted_by` → `user_id`, `scheduled_time` → `date + time`
- `notify_favor_status_change()` - Fixed `posted_by` → `user_id`, `scheduled_time` → `date + time`
- `notify_qa_activity()` - Fixed `posted_by` → `user_id`, `content` → `question`

### Migration 081: Fix Realtime Messaging
**File:** `database/081_fix_realtime_messaging.sql`

Enables proper realtime for messaging:
- Sets `REPLICA IDENTITY FULL` on messages, conversations, notifications tables
- Adds tables to `supabase_realtime` publication
- Creates optimized RLS policies for realtime broadcasts
- Adds performance indexes

### Migration 082: Fix Notification Queue Processing
**File:** `database/082_fix_notification_queue_processing.sql`

Fixes push notification delivery:
- Adds RLS policies to `notification_queue`
- Creates trigger to immediately process non-batched notifications
- Creates `send_push_notification_direct()` function for immediate push delivery
- Updates message push trigger to use direct notification
- Adds `notification_queue` to realtime publication

## Deployment Instructions

### Step 1: Apply Database Migrations
Run these migrations in order in your Supabase SQL Editor:

```bash
# 1. Critical trigger fixes (MUST RUN FIRST)
database/080_fix_notification_triggers_critical.sql

# 2. Realtime messaging fixes
database/081_fix_realtime_messaging.sql

# 3. Notification queue processing fixes
database/082_fix_notification_queue_processing.sql
```

### Step 2: Verify Triggers Are Working
After applying migrations, test by:

1. **Create a new ride request** - Should create notifications for all users
2. **Create a new favor request** - Should create notifications for all users
3. **Send a message** - Should trigger push notification to recipient
4. **Claim a ride/favor** - Should notify the poster

### Step 3: Check Supabase Dashboard
1. Go to **Database → Tables → notifications** - Verify new notifications appear
2. Go to **Database → Tables → notification_queue** - Verify queue entries are being processed
3. Go to **Database → Replication** - Verify tables are in `supabase_realtime` publication

### Step 4: Verify Edge Functions
Ensure your Edge Functions are deployed and have the correct environment variables:
- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_KEY` (base64 encoded .p8 file)
- `APNS_BUNDLE_ID`
- `APNS_PRODUCTION` (true/false)

### Step 5: Set Up Database Webhook (if not already done)
Create a webhook in Supabase Dashboard:
1. Go to **Database → Webhooks**
2. Create webhook for `notification_queue` table on INSERT
3. Point to your `send-notification` Edge Function URL

## Testing Checklist

After deployment, verify:

- [ ] Creating a ride request works and creates notifications
- [ ] Creating a favor request works and creates notifications
- [ ] Claiming a ride/favor notifies the poster
- [ ] Sending a message shows in real-time for recipient
- [ ] Push notifications are received on device
- [ ] In-app notifications appear in the notifications list
- [ ] Town Hall posts create notifications
- [ ] Q&A questions/answers create notifications (when request is unclaimed)

## Rollback Instructions

If issues occur, you can rollback by:

1. Restore the original trigger functions from `077_notification_triggers.sql`
2. Drop the new policies created in migrations 081 and 082

However, the original triggers had bugs, so rollback will restore the broken state.

## What Was NOT Changed (Preserved)

The following triggers were NOT modified because they were already correct:

1. **Town Hall triggers** - They correctly use:
   - `NEW.user_id` (correct column name)
   - `NEW.content` (correct for TownHallPost model)

2. **User approval triggers** - Already use correct columns

3. **Conversation triggers** - Already use correct columns

4. **All helper functions** - `create_notification()`, `queue_push_notification()`, `should_notify_user()` were NOT modified

---

## Technical Details

### Column Mapping Reference
| Trigger Used | Actual Column |
|--------------|---------------|
| `posted_by` | `user_id` |
| `destination_name` | `destination` |
| `scheduled_time` | `date` + `time` |
| `content` (request_qa) | `question` |

### Tables Requiring Realtime
- `messages` - For real-time chat
- `conversations` - For conversation list updates
- `notifications` - For in-app notification updates
- `notification_queue` - For push notification processing

### RLS Policy Requirements for Realtime
Supabase Realtime uses RLS to filter broadcasts. Policies must allow SELECT for users who should receive updates.

