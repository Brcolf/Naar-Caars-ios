# Quick Push Notification Test Guide

## ⚠️ Simulator Limitation

**iOS Simulators cannot receive push notifications** - you'll need a **real device** to see the actual notification.

However, you can still test:
- ✅ Edge Function is working (check logs)
- ✅ Webhook is triggering
- ✅ Database trigger is firing

---

## Method 1: Test by Sending a Real Message (Easiest)

### Step 1: Get Alice's User ID

**Option A: From Xcode Console**
1. In your app, add a print statement or breakpoint
2. Check `AuthService.shared.currentUserId` or `AuthService.shared.currentProfile?.id`
3. Copy the UUID

**Option B: From Supabase Dashboard**
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/editor
2. Open `profiles` table
3. Find the row where `name` = "alice" (or email contains "alice")
4. Copy the `id` column (UUID)

### Step 2: Send a Message to Alice

**From another user (or different device)**:
1. Log in as a different user (e.g., "Bob")
2. Open or create a conversation with Alice
3. Send a message
4. **Important**: Make sure Alice's app is **closed** or on a **different screen** (not viewing the conversation)

### Step 3: Check Edge Function Logs

**Watch logs in real-time**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs
2. **Keep this tab open**
3. Send the message
4. **Within 1-2 seconds**, you should see logs appear

**What to look for**:
- `📨 Processing push notification for user [UUID]...` = ✅ Webhook triggered
- `✅ Sent push notifications to user [UUID]: X succeeded, 0 failed` = ✅ Push sent
- `⏭️ Skipping push - user viewing conversation` = ✅ Correctly detected active viewing
- `⏭️ Skipping push - no tokens found` = ⚠️ Alice needs to grant permissions

---

## Method 2: Test Edge Function Directly (Advanced)

### Step 1: Get Required Values

**Get Alice's User ID** (see Method 1, Step 1)

**Get a Conversation ID**:
1. Go to: Database → Table Editor → `conversations`
2. Find a conversation where Alice is a participant
3. Copy the `id` (UUID)

**Or create a test conversation**:
- Just use any UUID for testing (the Edge Function will still run)

### Step 2: Get Supabase Anon Key

1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/settings/api
2. Copy the **"anon public"** key

### Step 3: Call Edge Function

**Run this in Terminal** (replace values):

```bash
curl -X POST https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push \
  -H "Authorization: Bearer YOUR_ANON_KEY_HERE" \
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

**Or use the test script**:
```bash
cd /Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs
./supabase/functions/send-message-push/test_push.sh
```

### Step 4: Check Response

**Success response**:
```json
{
  "sent": true,
  "skipped": false,
  "recipient_user_id": "...",
  "tokens_sent": 1
}
```

**Skipped (user viewing)**:
```json
{
  "sent": false,
  "skipped": true,
  "reason": "User is actively viewing this conversation"
}
```

**No tokens**:
```json
{
  "sent": false,
  "skipped": true,
  "reason": "No push tokens found for user"
}
```

---

## Method 3: Test on Real Device (Full Test)

### Step 1: Connect Real Device

1. **Connect iPhone/iPad** to your Mac
2. **Build and run** on the real device (not simulator)
3. **Log in as Alice**
4. **Grant notification permissions** when prompted

### Step 2: Verify Token Registration

**Check database**:
1. Go to: Database → Table Editor → `push_tokens`
2. Find row where `user_id` = Alice's UUID
3. Verify `token` exists (long string)
4. Verify `platform` = "ios"

**If no token**:
- Alice needs to grant permissions
- Check app logs for `PushNotificationService.registerDeviceToken()` errors

### Step 3: Send Test Message

**From another user**:
1. Log in as different user (e.g., "Bob")
2. Send message to Alice
3. **Make sure Alice's app is closed or in background**

### Step 4: Check Device

**On Alice's device**:
- Lock screen should show notification
- Notification center should show notification
- Badge count should update

---

## Troubleshooting

### "No tokens found" in logs

**Fix**:
- Alice needs to grant notification permissions
- Check `push_tokens` table has a row for Alice
- Check app logs for registration errors

### Webhook not triggering

**Check**:
- Database → Webhooks → `on_message_inserted_push` is enabled
- Webhook URL is correct
- Service role key is correct

### Edge Function errors

**Check logs** for:
- APNs auth errors → Verify environment variables
- Missing data → Check webhook request body
- Network errors → Check Supabase status

---

## Quick Checklist

- [ ] Alice is logged in
- [ ] Alice has granted notification permissions (check `push_tokens` table)
- [ ] Webhook is configured (Database → Webhooks)
- [ ] Edge Function is deployed
- [ ] Edge Function has APNs environment variables set
- [ ] Send a message to Alice (from another user)
- [ ] Check Edge Function logs
- [ ] For full test: Use real device (not simulator)

---

## Next Steps

1. **Test on simulator**: Check logs to verify webhook/Edge Function work
2. **Test on real device**: See actual push notification
3. **Test navigation**: Tap notification to verify deep linking works


