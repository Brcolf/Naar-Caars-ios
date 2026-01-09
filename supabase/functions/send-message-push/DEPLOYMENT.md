# Deployment Guide: send-message-push Edge Function

## ⚡ Quick Start

**For detailed step-by-step instructions with screenshots and exact UI navigation, see:**
**[STEP_BY_STEP_SETUP.md](./STEP_BY_STEP_SETUP.md)** ← **Start here for detailed instructions**

---

## Quick Reference

1. **Deploy the function:**
   ```bash
   supabase functions deploy send-message-push
   ```

2. **Set environment variables** in Supabase Dashboard → Edge Functions → send-message-push → Settings

3. **Create Database Webhook** in Supabase Dashboard → Database → Webhooks

## Detailed Steps

### Step 1: Deploy Edge Function

From your project root:

```bash
# Make sure you're logged in to Supabase CLI
supabase login

# Link to your project (if not already linked)
supabase link --project-ref YOUR_PROJECT_REF

# Deploy the function
supabase functions deploy send-message-push
```

### Step 2: Configure Environment Variables

In Supabase Dashboard → Edge Functions → send-message-push → Settings → Secrets:

Add these secrets:

| Variable | Description | Example |
|----------|-------------|---------|
| `APNS_TEAM_ID` | Apple Team ID | `ABC123DEF4` |
| `APNS_KEY_ID` | APNs Key ID | `XYZ987ABC` |
| `APNS_KEY` | APNs private key (base64 encoded .p8 file) | See below |
| `APNS_BUNDLE_ID` | App bundle ID | `com.naarscars.app` |
| `APNS_PRODUCTION` | `true` for production, `false` for sandbox | `false` |

#### Getting APNs Key Content

1. Download your `.p8` file from Apple Developer Portal
2. Base64 encode it:
   ```bash
   # macOS/Linux
   base64 -i AuthKey_XYZ987ABC.p8
   
   # Or using cat
   cat AuthKey_XYZ987ABC.p8 | base64
   ```
3. Copy the **entire output** (including newlines) and paste into `APNS_KEY` secret

**Important**: The key should include the PEM headers:
```
-----BEGIN PRIVATE KEY-----
[base64 content]
-----END PRIVATE KEY-----
```

### Step 3: Create Database Webhook

Since Supabase Edge Functions are HTTP endpoints, we need to connect the database trigger to the Edge Function via a webhook.

#### Option A: Supabase Database Webhooks (Recommended)

1. Go to Supabase Dashboard → Database → Webhooks
2. Click "Create a new hook"
3. Configure:
   - **Name**: `message_push_webhook`
   - **Table**: `messages`
   - **Events**: Check `INSERT`
   - **Type**: `HTTP Request`
   - **URL**: `https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-message-push`
   - **HTTP Method**: `POST`
   - **HTTP Headers**:
     ```
     Authorization: Bearer YOUR_SERVICE_ROLE_KEY
     Content-Type: application/json
     ```
   - **Request Body Template**:
     ```json
     {
       "recipient_user_id": "{{OLD.user_id}}",
       "conversation_id": "{{NEW.conversation_id}}",
       "sender_name": "{{sender_name}}",
       "message_preview": "{{message_preview}}",
       "message_id": "{{NEW.id}}",
       "sender_id": "{{NEW.from_id}}"
     }
     ```

**Note**: Database webhooks have limitations - they can't easily access related tables. The trigger function already fetches `sender_name` and `message_preview`, but webhooks can't use that data directly.

#### Option B: Use pg_net Extension (Advanced)

If your Supabase instance supports `pg_net`, you can modify the trigger to call the Edge Function directly:

```sql
-- Enable pg_net extension
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Update trigger function to call Edge Function
-- (This requires modifying 043_create_message_push_trigger.sql)
```

### Step 4: Test the Function

#### Test via HTTP:

```bash
curl -X POST https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-message-push \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient_user_id": "USER_UUID_HERE",
    "conversation_id": "CONVERSATION_UUID_HERE",
    "sender_name": "Test Sender",
    "message_preview": "Test message preview...",
    "message_id": "MESSAGE_UUID_HERE",
    "sender_id": "SENDER_UUID_HERE"
  }'
```

#### Test by Sending a Message:

1. Send a message in the app
2. Check Edge Function logs in Supabase Dashboard
3. Verify push notification arrives on recipient device

### Step 5: Monitor Logs

Check Edge Function logs in:
- Supabase Dashboard → Edge Functions → send-message-push → Logs

Look for:
- `📨 Processing push notification` - Function called
- `⏭️ Skipping push` - User is viewing or no tokens
- `✅ Sent push notifications` - Success
- Error messages for failures

## Troubleshooting

### Function Not Receiving Requests

- Verify webhook is configured correctly
- Check webhook URL matches your project
- Verify service role key is correct
- Check Edge Function logs for errors

### APNs Authentication Errors

- Verify `APNS_TEAM_ID` matches your Apple Developer Team ID
- Verify `APNS_KEY_ID` matches the Key ID from Apple Developer Portal
- Check `APNS_KEY` is correctly base64 encoded
- Ensure key includes PEM headers (`-----BEGIN PRIVATE KEY-----`)

### Push Notifications Not Arriving

- Verify device token is registered in `push_tokens` table
- Check APNs response in Edge Function logs
- Verify notification permissions are granted in iOS app
- For testing, use `APNS_PRODUCTION=false` (sandbox)
- Ensure device is using sandbox APNs when testing (development builds)

### JWT Creation Errors

- Verify `djwt` library is available (should be auto-imported)
- Check private key format is correct
- Ensure key is for ES256 algorithm

## Production Checklist

- [ ] Deploy Edge Function to production
- [ ] Set `APNS_PRODUCTION=true` in environment variables
- [ ] Test with production APNs endpoint
- [ ] Verify webhook is configured correctly
- [ ] Monitor Edge Function logs for errors
- [ ] Set up alerting for Edge Function failures
- [ ] Test push notifications on real devices

## Performance

Expected latency:
- Database trigger: < 10ms
- Webhook delivery: < 100ms
- Edge Function execution: < 200ms
- APNs delivery: < 500ms
- **Total: < 1 second**

