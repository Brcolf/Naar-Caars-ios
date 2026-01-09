# Deployment Complete! ✅

**Edge Function deployed successfully!**

**Project Ref**: `easlpsksbylyceqiqecq`  
**Project Name**: Naars-cars  
**Function**: `send-message-push`

**Dashboard URL**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions

---

## Next Steps (Manual Configuration)

### Step 1: Set Environment Variables

**Direct Link**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/settings

**Or navigate manually**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq
2. Click **"Edge Functions"** in left sidebar
3. Click **"send-message-push"**
4. Click **"Settings"** tab
5. Scroll to **"Secrets"** section

**Add these 5 secrets** (click "+ New Secret" for each):

#### Secret 1: `APNS_TEAM_ID`
- **Name**: `APNS_TEAM_ID`
- **Value**: Your Apple Team ID (e.g., `ABC123DEF4`)
- **Where to find**: https://developer.apple.com/account → Membership → Team ID

#### Secret 2: `APNS_KEY_ID`
- **Name**: `APNS_KEY_ID`
- **Value**: Your APNs Key ID (e.g., `XYZ987ABC`)
- **Where to find**: https://developer.apple.com/account/resources/authkeys/list → Find your key → Copy Key ID

#### Secret 3: `APNS_KEY`
- **Name**: `APNS_KEY`
- **Value**: Your base64 encoded .p8 file content
- **How to get**: Run in Terminal:
  ```bash
  cd ~/Downloads  # or wherever your .p8 file is
  base64 -i AuthKey_YOUR_KEY_ID.p8
  ```
  Copy the entire output and paste it here

#### Secret 4: `APNS_BUNDLE_ID`
- **Name**: `APNS_BUNDLE_ID`
- **Value**: Your app bundle ID (e.g., `com.naarscars.app`)
- **Where to find**: Xcode → Project → Target → General → Bundle Identifier

#### Secret 5: `APNS_PRODUCTION`
- **Name**: `APNS_PRODUCTION`
- **Value**: `false` (for testing) or `true` (for production)
- **For now, use**: `false`

---

### Step 2: Get Service Role Key

**Direct Link**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/settings/api

**Or navigate manually**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq
2. Click **"Settings"** (gear icon) in left sidebar
3. Click **"API"** in submenu
4. Scroll to **"Project API keys"**
5. Find **"service_role"** key (red background)
6. Click **"Copy"** or eye icon to reveal, then copy
7. **Save this key** - you'll need it for the webhook

---

### Step 3: Create Database Webhook

**Direct Link**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks

**Or navigate manually**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq
2. Click **"Database"** in left sidebar
3. Click **"Webhooks"** in submenu
4. Click **"Create a new hook"** button

**Fill in the form**:

#### Name
- **Value**: `message_push_webhook`

#### Table
- **Value**: `messages` (select from dropdown)

#### Events
- **Check**: `INSERT` only
- **Uncheck**: UPDATE and DELETE

#### Type
- **Value**: `HTTP Request`

#### URL
- **Value**: 
```
https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push
```

#### HTTP Method
- **Value**: `POST`

#### HTTP Headers

**Add Header 1**:
- **Key**: `Authorization`
- **Value**: `Bearer YOUR_SERVICE_ROLE_KEY`
  - Replace `YOUR_SERVICE_ROLE_KEY` with the key you copied in Step 2
  - Include the word "Bearer" followed by a space

**Add Header 2**:
- **Key**: `Content-Type`
- **Value**: `application/json`

#### Request Body Template
- **Value**: Copy and paste exactly:
```json
{
  "id": "{{NEW.id}}",
  "conversation_id": "{{NEW.conversation_id}}",
  "from_id": "{{NEW.from_id}}",
  "text": "{{NEW.text}}"
}
```

**Important**: Copy it exactly, including `{{` and `}}`

#### Save
- **Click**: "Create webhook" or "Save" button

---

## Step 4: Verify Deployment

### Check Function Logs

**Direct Link**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs

**Or navigate manually**:
1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq
2. Click **"Edge Functions"** → **"send-message-push"** → **"Logs"** tab
3. Send a test message from your app
4. Look for log entries like:
   - `📨 Processing push notification`
   - `✅ Sent push notifications`
   - `⏭️ Skipping push` (if user is viewing)

### Test Push Notification

1. Open your iOS app on a real device (simulator doesn't receive push)
2. Make sure recipient is NOT viewing the conversation (app closed or different screen)
3. Send a message
4. Check if push notification arrives on recipient device

---

## Quick Links Summary

- **Function Settings**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/settings
- **Function Logs**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs
- **Service Role Key**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/settings/api
- **Database Webhooks**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks

---

## Troubleshooting

### Function Not Receiving Requests

**Check**:
1. Webhook is enabled (green/active status in webhooks list)
2. Webhook URL is correct: `https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push`
3. Service role key is correct in webhook headers
4. Webhook request body template includes `{{NEW.id}}`, etc.

### APNs Errors

**Check Function Logs** for errors like:
- "Missing APNs environment variables" → Verify all 5 secrets are set
- "Invalid key" or "Authentication failed" → Check APNS_KEY format (should be base64)
- "Team ID mismatch" → Verify APNS_TEAM_ID matches your Apple Developer account

### Push Notifications Not Arriving

**Check**:
1. Device token is registered in `push_tokens` table (Database → Table Editor → push_tokens)
2. Notification permissions are granted in iOS app
3. Using real device (not simulator)
4. `APNS_PRODUCTION` is set to `false` for testing (sandbox)
5. Device is using sandbox APNs (development builds automatically use sandbox)

---

## Success Checklist

- [x] Edge Function deployed
- [ ] All 5 environment variables set (APNS_TEAM_ID, APNS_KEY_ID, APNS_KEY, APNS_BUNDLE_ID, APNS_PRODUCTION)
- [ ] Service role key copied
- [ ] Database webhook created and enabled
- [ ] Test message sent from app
- [ ] Function logs show activity
- [ ] Push notification received on device

