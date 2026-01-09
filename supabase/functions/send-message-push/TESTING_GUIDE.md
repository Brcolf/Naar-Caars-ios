# Testing Guide: Push Notifications

## Setup Complete! ✅

All components are now configured:
- ✅ Edge Function deployed
- ✅ All 5 APNs environment variables set
- ✅ Database webhook created
- ✅ Database trigger active

---

## How to Test

### Step 1: Verify Webhook is Active

**Check in Dashboard**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks
2. Verify `message_push_webhook` is listed
3. Check it shows **"Active"** status (green dot/indicator)

### Step 2: Send a Test Message

**From your iOS app**:
1. Open the app on a **real device** (simulator doesn't receive push notifications)
2. Make sure you're logged in as User A
3. Send a message to User B
4. **Important**: User B should NOT be viewing the conversation (app closed or on different screen)

### Step 3: Check Edge Function Logs

**Watch logs in real-time**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs
2. Keep this tab open
3. Send a message from your app
4. Look for log entries within 1-2 seconds:

**Success logs**:
- `📨 Processing push notification for user [UUID], conversation [UUID]`
- `✅ Sent push notifications to user [UUID]: X succeeded, 0 failed`

**Skip logs** (if user is viewing):
- `⏭️ Skipping push - user viewed conversation X.Xs ago`
- `⏭️ Skipping push for user [UUID] - viewed X.Xs ago`

**Error logs** (if something's wrong):
- Red error messages
- Check what they say

### Step 4: Verify Push Notification Arrived

**On recipient device**:
- Check lock screen for notification
- Check notification center
- Notification should show: "Message from [Sender Name]"

---

## Test Scenarios

### Scenario 1: User Not Viewing (Should Get Push)

1. **User A** sends message to **User B**
2. **User B** has app closed or is on different screen
3. **Expected**: Push notification appears on User B's device

### Scenario 2: User Viewing Conversation (Should NOT Get Push)

1. **User B** opens conversation with **User A** in app
2. **User A** sends message while **User B** is viewing
3. **Expected**: 
   - Message appears in app immediately (via Realtime)
   - **No push notification** (user is viewing)

### Scenario 3: User Was Viewing But Closed App

1. **User B** views conversation
2. **User B** closes app or switches screens
3. **User A** sends message after 60+ seconds
4. **Expected**: Push notification appears (last_seen > 60 seconds ago)

---

## Troubleshooting

### No Logs Appearing

**Check**:
1. Webhook is enabled/active
2. Webhook URL is correct
3. Service role key is correct in webhook headers
4. Try sending another message

### Logs Show "Skipping push - no tokens"

**Fix**:
1. Verify user has granted notification permissions in iOS app
2. Check `push_tokens` table in database:
   - Go to: Database → Table Editor → `push_tokens`
   - Verify row exists for the recipient user

### Logs Show APNs Errors

**Check**:
1. All environment variables are set correctly
2. APNS_KEY is base64 encoded correctly
3. APNS_TEAM_ID matches your Apple Developer account
4. APNS_KEY_ID matches your APNs key
5. APNS_PRODUCTION is `false` for testing (sandbox)

### Push Notification Not Arriving

**Check**:
1. Using **real device** (not simulator)
2. Notification permissions granted in iOS app
3. Device is using sandbox APNs (development builds automatically use sandbox)
4. Check Edge Function logs for errors
5. Verify device token is in `push_tokens` table

### User Receiving Push While Viewing

**This shouldn't happen**, but if it does:
1. Check Edge Function logs - should show "Skipping push - user viewing"
2. Verify `last_seen` is updating in `conversation_participants` table
3. Check that `updateLastSeen` is being called in the app

---

## Monitoring

### Check Logs Regularly

**Direct Link**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs

### Check Database

**Verify webhook triggered**:
1. Go to: Database → Table Editor → `messages`
2. Check that new messages are being inserted
3. If messages exist but no logs, webhook might not be triggering

**Verify last_seen updating**:
1. Go to: Database → Table Editor → `conversation_participants`
2. Check that `last_seen` column updates when viewing conversations
3. If NULL, the app might not be calling `updateLastSeen`

---

## Success Checklist

- [ ] Webhook is active/enabled
- [ ] Edge Function logs show activity when message sent
- [ ] Push notification arrives when recipient is NOT viewing
- [ ] No push notification when recipient IS viewing
- [ ] Logs show correct sender name and message preview
- [ ] No errors in Edge Function logs

---

## Next Steps

1. **Test all scenarios** above
2. **Monitor logs** for any errors
3. **Switch to production** when ready:
   - Set `APNS_PRODUCTION=true` in Edge Function settings
   - Re-test with production APNs

**You're all set!** The push notification system is now fully configured and ready to test. 🎉

