# Setup Guide: send-message-push Edge Function

## Prerequisites

1. APNs key (.p8 file) uploaded to Supabase Dashboard
2. APNs Key ID and Team ID from Apple Developer Portal
3. App Bundle ID

## Step 1: Deploy Edge Function

```bash
# From project root
supabase functions deploy send-message-push
```

## Step 2: Configure Environment Variables

In Supabase Dashboard → Edge Functions → send-message-push → Settings:

Add these environment variables:

- `APNS_TEAM_ID` - Your Apple Team ID (e.g., `ABC123DEF4`)
- `APNS_KEY_ID` - Your APNs Key ID (e.g., `XYZ987ABC`)
- `APNS_KEY` - Your APNs private key (.p8 file content, base64 encoded)
- `APNS_BUNDLE_ID` - Your app's bundle ID (e.g., `com.naarscars.app`)
- `APNS_PRODUCTION` - `true` for production, `false` for sandbox/testing

### Getting APNs Key Content

1. Download your .p8 file from Apple Developer Portal
2. Base64 encode it:
   ```bash
   base64 -i AuthKey_XYZ987ABC.p8
   ```
3. Copy the entire output (including newlines) to `APNS_KEY`

## Step 3: Set Up Database Webhook

Supabase doesn't directly support `pg_notify` → Edge Function, so we need to use Database Webhooks.

### Option A: Use Supabase Database Webhooks (Recommended)

1. Go to Supabase Dashboard → Database → Webhooks
2. Create new webhook:
   - **Name**: `message_push_webhook`
   - **Table**: `messages`
   - **Events**: `INSERT`
   - **Type**: `HTTP Request`
   - **URL**: `https://YOUR_PROJECT.supabase.co/functions/v1/send-message-push`
   - **HTTP Method**: `POST`
   - **HTTP Headers**: 
     ```
     Authorization: Bearer YOUR_SERVICE_ROLE_KEY
     Content-Type: application/json
     ```
   - **Request Body Template**:
     ```json
     {
       "id": "{{NEW.id}}",
       "conversation_id": "{{NEW.conversation_id}}",
       "from_id": "{{NEW.from_id}}",
       "text": "{{NEW.text}}"
     }
     ```

**Note**: Database webhooks have limitations - they can't easily access related tables (like `profiles` for sender name). We'll need to modify the trigger to include all needed data.

### Option B: Modify Trigger to Call Edge Function Directly

Update the trigger to make an HTTP request to the Edge Function using `http` extension (if available):

```sql
-- This requires the http extension
CREATE EXTENSION IF NOT EXISTS http;

-- Modify notify_message_push function to call Edge Function
CREATE OR REPLACE FUNCTION notify_message_push()
RETURNS TRIGGER AS $$
DECLARE
  recipient_user_id UUID;
  conversation_id_val UUID;
  sender_name TEXT;
  message_preview TEXT;
  recipient_record RECORD;
  edge_function_url TEXT := 'https://YOUR_PROJECT.supabase.co/functions/v1/send-message-push';
  service_role_key TEXT := 'YOUR_SERVICE_ROLE_KEY';
  request_body JSONB;
  http_response http_response;
BEGIN
  -- ... (same logic as before to get recipients)
  
  -- For each recipient, call Edge Function
  FOR recipient_record IN
    SELECT cp.user_id, cp.last_seen
    FROM conversation_participants cp
    WHERE cp.conversation_id = NEW.conversation_id
      AND cp.user_id != NEW.from_id
  LOOP
    -- Check last_seen (same as before)
    IF recipient_record.last_seen IS NOT NULL 
       AND EXTRACT(EPOCH FROM (NOW() - recipient_record.last_seen)) < 60 THEN
      CONTINUE;
    END IF;
    
    -- Build request body
    request_body := json_build_object(
      'recipient_user_id', recipient_record.user_id::text,
      'conversation_id', NEW.conversation_id::text,
      'sender_name', sender_name,
      'message_preview', message_preview,
      'message_id', NEW.id::text,
      'sender_id', NEW.from_id::text
    );
    
    -- Call Edge Function
    SELECT * INTO http_response
    FROM http((
      'POST',
      edge_function_url,
      ARRAY[
        http_header('Authorization', 'Bearer ' || service_role_key),
        http_header('Content-Type', 'application/json')
      ],
      'application/json',
      request_body::text
    )::http_request);
    
    -- Log response (optional)
    RAISE NOTICE 'Edge Function response: %', http_response.status;
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Note**: This requires the `http` extension, which may not be available in all Supabase instances.

## Step 4: Update Trigger to Include Sender Name

Since webhooks can't easily join tables, we need to modify the trigger to fetch sender name:

```sql
-- Update the trigger function to get sender name from profiles
CREATE OR REPLACE FUNCTION notify_message_push()
RETURNS TRIGGER AS $$
DECLARE
  recipient_user_id UUID;
  conversation_id_val UUID;
  sender_name TEXT;
  message_preview TEXT;
  recipient_record RECORD;
BEGIN
  conversation_id_val := NEW.conversation_id;
  
  -- Get sender name from profiles
  SELECT COALESCE(name, 'Someone') INTO sender_name
  FROM profiles
  WHERE id = NEW.from_id;
  
  -- Get message preview
  message_preview := LEFT(NEW.text, 50);
  IF LENGTH(NEW.text) > 50 THEN
    message_preview := message_preview || '...';
  END IF;
  
  -- Rest of the function remains the same...
  -- (loop through recipients, check last_seen, send pg_notify)
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Step 5: Test the Edge Function

Test directly via HTTP:

```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/send-message-push \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient_user_id": "USER_UUID",
    "conversation_id": "CONVERSATION_UUID",
    "sender_name": "Test Sender",
    "message_preview": "Test message preview...",
    "message_id": "MESSAGE_UUID",
    "sender_id": "SENDER_UUID"
  }'
```

## Troubleshooting

### Edge Function not receiving requests
- Check webhook configuration in Supabase Dashboard
- Verify service role key is correct
- Check Edge Function logs in Supabase Dashboard

### APNs errors
- Verify APNs key is correctly base64 encoded
- Check Team ID and Key ID match your Apple Developer account
- Ensure Bundle ID matches your app
- For testing, use `APNS_PRODUCTION=false` (sandbox)

### Push notifications not arriving
- Verify device token is registered in `push_tokens` table
- Check APNs response in Edge Function logs
- Verify notification permissions are granted in iOS app

## Monitoring

Check Edge Function logs in Supabase Dashboard → Edge Functions → send-message-push → Logs

Look for:
- `📨 Processing push notification` - Function called
- `⏭️ Skipping push` - User is viewing or no tokens
- `✅ Sent push notifications` - Success
- Error messages for failures

