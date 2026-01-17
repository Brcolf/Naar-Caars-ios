# Testing Push Notifications

## ⚠️ Important: Simulators Don't Receive Push Notifications

**iOS Simulators cannot receive push notifications** - they only work on **real iOS devices**.

However, you can still test:
1. ✅ Edge Function is working (check logs)
2. ✅ Webhook is triggering correctly
3. ✅ Database trigger is firing
4. ✅ Push notifications on a **real device**

---

## Option 1: Test Edge Function Directly (Works on Simulator)

This tests if the Edge Function can send push notifications, even though the simulator won't receive them.

### Step 1: Get Alice's User ID

**In your app or database**:
1. Check what user ID Alice has
2. Or go to Database → Table Editor → `profiles` → Find Alice's row → Copy the `id` (UUID)

### Step 2: Get Alice's Device Token

**Check if Alice has a push token registered**:
1. Go to: Database → Table Editor → `push_tokens`
2. Find rows where `user_id` = Alice's UUID
3. Copy one of the `token` values

**If no token exists**:
- Alice needs to grant notification permissions in the app
- The app will register the token automatically
- Check `PushNotificationService.registerDeviceToken()` is being called

### Step 3: Test Edge Function via HTTP

**Run this in Terminal** (replace with actual values):

```bash
curl -X POST https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient_user_id": "ALICE_USER_ID_HERE",
    "conversation_id": "SOME_CONVERSATION_ID",
    "sender_name": "Test Sender",
    "message_preview": "This is a test message",
    "message_id": "TEST_MESSAGE_ID",
    "sender_id": "SENDER_USER_ID"
  }'
```

**Or test with webhook format** (simulates what webhook sends):

```bash
curl -X POST https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "TEST_MESSAGE_ID",
    "conversation_id": "SOME_CONVERSATION_ID",
    "from_id": "SENDER_USER_ID",
    "text": "This is a test message from the webhook format"
  }'
```

### Step 4: Check Logs

**Watch Edge Function logs**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs
2. You should see logs like:
   - `📨 Processing push notification for user [UUID]...`
   - `✅ Sent push notifications to user [UUID]: X succeeded, 0 failed`

---

## Option 2: Test on Real Device (Full Test)

### Step 1: Set Up Real Device

1. **Connect a real iPhone/iPad** to your Mac
2. **Build and run** the app on the real device (not simulator)
3. **Log in as Alice** on the real device
4. **Grant notification permissions** when prompted

### Step 2: Verify Token Registration

**Check database**:
1. Go to: Database → Table Editor → `push_tokens`
2. Verify there's a row with:
   - `user_id` = Alice's UUID
   - `token` = a long string (device token)
   - `platform` = "ios"

### Step 3: Send Test Message

**From another user (or different device)**:
1. Log in as a different user (e.g., "Bob")
2. Send a message to Alice
3. **Important**: Make sure Alice's app is **closed** or on a **different screen** (not viewing the conversation)

### Step 4: Verify Push Notification

**On Alice's device**:
- Check lock screen for notification
- Check notification center
- Notification should show: "Message from Bob"

---

## Option 3: Test Webhook Triggering (Simulator OK)

This tests if the webhook is working, even though simulator won't receive push.

### Step 1: Send Message from Simulator

1. **Log in as Alice** on simulator
2. **Send a message** to another user
3. Or have another user send a message to Alice

### Step 2: Check Edge Function Logs

**Watch logs in real-time**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs
2. **Keep this tab open**
3. Send a message from your app
4. **Within 1-2 seconds**, you should see logs appear

**What to look for**:
- `📨 Processing push notification` = Webhook triggered successfully
- `✅ Sent push notifications` = Push was sent (even if simulator can't receive it)
- `⏭️ Skipping push - user viewing` = User is actively viewing (correct behavior)
- `⏭️ Skipping push - no tokens` = User doesn't have push token registered

### Step 3: Check Database

**Verify message was inserted**:
1. Go to: Database → Table Editor → `messages`
2. Check that your test message appears
3. This confirms the trigger fired

---

## Quick Test Script

I can create a test script that:
1. Gets Alice's user ID
2. Gets a conversation ID
3. Calls the Edge Function directly
4. Shows you the response

Would you like me to create that?

---

## Troubleshooting

### "No tokens found" in logs

**Fix**:
- Alice needs to grant notification permissions
- App needs to call `PushNotificationService.registerDeviceToken()`
- Check `push_tokens` table has a row for Alice

### Webhook not triggering

**Check**:
- Webhook is enabled in Database → Webhooks
- Webhook URL is correct
- Service role key is correct in headers

### Edge Function errors

**Check logs** for:
- APNs authentication errors → Verify environment variables
- Missing data → Check webhook request body template
- Network errors → Check Supabase status

---

## What You Can Test on Simulator

✅ **Can test**:
- Webhook triggering (check logs)
- Edge Function execution (check logs)
- Database trigger firing (check messages table)
- `last_seen` updating (check conversation_participants table)

❌ **Cannot test**:
- Actual push notification appearing on device
- Notification tap navigation
- Badge count updates

**For full testing, use a real device.**


