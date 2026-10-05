# How to Test Push Notifications

## ⚠️ Important: Simulators Don't Receive Push Notifications

iOS Simulators **cannot** receive push notifications. You need a **real device** to see the actual notification.

However, you can still verify the system is working by checking logs.

---

## ✅ Recommended Test Method: Send a Real Message

### Step 1: Get Alice's User ID

**Option A: From Xcode Console**
1. Add a breakpoint or print statement in your app
2. Check: `AuthService.shared.currentUserId` or `AuthService.shared.currentProfile?.id`
3. Copy the UUID

**Option B: From Supabase Dashboard**
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/editor
2. Open `profiles` table
3. Find Alice's row (search by name or email)
4. Copy the `id` column (UUID)

### Step 2: Open Edge Function Logs

**Keep this tab open**:
https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs

### Step 3: Send a Message

**From your app**:
1. Log in as Alice (or another user)
2. Open or create a conversation
3. Send a message
4. **Important**: Make sure the recipient's app is **closed** or on a **different screen** (not viewing the conversation)

### Step 4: Watch the Logs

**Within 1-2 seconds**, you should see logs like:

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

## 🔍 What to Check

### 1. Webhook is Triggering
- ✅ Logs appear within 1-2 seconds of sending message
- ✅ Logs show "Processing push notification"

### 2. Edge Function is Working
- ✅ Logs show "Sent push notifications" or "Skipping push" (with reason)
- ❌ If you see errors, check:
  - APNs environment variables are set
  - Service role key is correct
  - Webhook configuration is correct

### 3. Database Trigger is Firing
- ✅ Check `messages` table - your test message should appear
- ✅ Check `conversation_participants` table - `last_seen` should update

### 4. Push Tokens are Registered
- ✅ Check `push_tokens` table - user should have a row with `token` and `platform = 'ios'`
- ❌ If no token: User needs to grant notification permissions in the app

---

## 🧪 Alternative: Test Edge Function Directly

If you want to test the Edge Function directly (bypassing the webhook), you need to:

1. **Make the Edge Function public** (in Supabase Dashboard):
   - Go to: Functions → `send-message-push` → Settings
   - Enable "Public" or configure authentication

2. **Or use the service role key** (not recommended for production):
   - Use service role key instead of anon key
   - ⚠️ **Warning**: Service role key bypasses RLS - only use for testing

---

## 📱 Full Test on Real Device

To see the actual push notification:

1. **Connect a real iPhone/iPad** to your Mac
2. **Build and run** on the real device (not simulator)
3. **Log in as Alice**
4. **Grant notification permissions** when prompted
5. **Verify token registration**:
   - Check `push_tokens` table has a row for Alice
6. **Send a message** from another user
7. **Check the device**:
   - Lock screen should show notification
   - Notification center should show notification
   - Badge count should update

---

## 🐛 Troubleshooting

### "No tokens found" in logs
- **Fix**: User needs to grant notification permissions
- **Check**: `push_tokens` table has a row for the user

### Webhook not triggering
- **Check**: Database → Webhooks → `on_message_inserted_push` is enabled
- **Check**: Webhook URL is correct
- **Check**: Service role key is correct in webhook headers

### Edge Function errors
- **Check logs** for specific error messages
- **Check**: APNs environment variables are set correctly
- **Check**: APNs key is valid and not expired

---

## ✅ Quick Checklist

- [ ] Alice is logged in
- [ ] Alice has granted notification permissions (check `push_tokens` table)
- [ ] Webhook is configured (Database → Webhooks)
- [ ] Edge Function is deployed
- [ ] Edge Function has APNs environment variables set
- [ ] Edge Function logs page is open
- [ ] Send a message to Alice (from another user)
- [ ] Check Edge Function logs for results
- [ ] For full test: Use real device (not simulator)

---

## 📊 Expected Log Output

**Successful push**:
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


