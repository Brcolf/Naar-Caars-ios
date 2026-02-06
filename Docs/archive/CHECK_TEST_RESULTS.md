# Check Push Notification Test Results

## ✅ What to Check After Sending a Test Message

### 1️⃣ Edge Function Logs (Most Important)

**Open this page**:
https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs

**What to look for**:

✅ **Success**:
```
📨 Processing push notification for user [UUID]...
✅ Sent push notifications to user [UUID]: 1 succeeded, 0 failed
```

⏭️ **Skipped (User Viewing)**:
```
⏭️ Skipping push for user [UUID] - viewed 5.2s ago
```

⏭️ **Skipped (No Tokens)**:
```
⏭️ Skipping push for user [UUID] - no tokens found
```

❌ **Error**:
```
❌ Error sending push: [error message]
```

---

### 2️⃣ Database - Messages Table

**Go to**: Database → Table Editor → `messages`

**Check**:
- ✅ Your test message appears in the table
- ✅ `conversation_id` is set
- ✅ `from_id` is set (sender's user ID)
- ✅ `text` contains your message
- ✅ `created_at` is recent (within last few minutes)

**If message is missing**: The message wasn't saved, check app logs for errors.

---

### 3️⃣ Database - Conversation Participants

**Go to**: Database → Table Editor → `conversation_participants`

**Check**:
- ✅ Find the row where `conversation_id` matches your message's conversation
- ✅ `last_seen` timestamp should be recent (if user was viewing)
- ✅ If `last_seen` is NULL or old, push should be sent
- ✅ If `last_seen` is within last 60 seconds, push should be skipped

**This confirms**:
- Database trigger fired
- `last_seen` is being updated correctly

---

### 4️⃣ Database - Push Tokens

**Go to**: Database → Table Editor → `push_tokens`

**Check**:
- ✅ Recipient user has a row with their `user_id`
- ✅ `token` is a long string (device token)
- ✅ `platform` = "ios"
- ✅ `created_at` is recent

**If no token**:
- ⚠️ User needs to grant notification permissions
- ⚠️ App needs to call `PushNotificationService.registerDeviceToken()`
- ⚠️ Check app logs for registration errors

---

## 📊 Expected Results

### Scenario 1: User Has Token & Not Viewing
- ✅ Message appears in `messages` table
- ✅ `last_seen` is NULL or > 60 seconds old
- ✅ Edge Function logs show: "✅ Sent push notifications"
- ✅ Push notification sent (on real device)

### Scenario 2: User Has Token & Is Viewing
- ✅ Message appears in `messages` table
- ✅ `last_seen` is recent (< 60 seconds)
- ✅ Edge Function logs show: "⏭️ Skipping push - user viewing"
- ✅ Push notification NOT sent (correct behavior)

### Scenario 3: User Has No Token
- ✅ Message appears in `messages` table
- ✅ Edge Function logs show: "⏭️ Skipping push - no tokens found"
- ✅ Push notification NOT sent (user needs to grant permissions)

### Scenario 4: Webhook Not Triggering
- ❌ Message appears in `messages` table
- ❌ No Edge Function logs appear
- ❌ Check: Database → Webhooks → `on_message_inserted_push` is enabled
- ❌ Check: Webhook URL and headers are correct

---

## 🐛 Troubleshooting

### No Edge Function Logs
**Possible causes**:
1. Webhook not configured
2. Webhook disabled
3. Webhook URL incorrect
4. Service role key incorrect in webhook headers

**Fix**:
- Go to: Database → Webhooks
- Check `on_message_inserted_push` webhook exists and is enabled
- Verify URL: `https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push`
- Verify headers include service role key

### Edge Function Errors
**Check logs for**:
- APNs authentication errors → Verify environment variables
- Missing data → Check webhook request body template
- Network errors → Check Supabase status

### No Push Tokens
**Fix**:
- User needs to grant notification permissions
- Check app logs for `PushNotificationService.registerDeviceToken()` errors
- Verify APNs key is uploaded to Supabase

---

## ✅ Quick Checklist

After sending a test message, verify:

- [ ] Message appears in `messages` table
- [ ] Edge Function logs show activity (check within 1-2 seconds)
- [ ] `conversation_participants.last_seen` updated (if user was viewing)
- [ ] `push_tokens` table has recipient's token (if permissions granted)
- [ ] Edge Function logs show "Sent" or "Skipped" (not errors)

---

## 📱 Next Steps

1. **If logs show "Sent"**: System is working! Test on real device to see notification.
2. **If logs show "Skipped - no tokens"**: User needs to grant permissions.
3. **If logs show "Skipped - user viewing"**: Correct behavior! Close app and test again.
4. **If no logs appear**: Check webhook configuration.


