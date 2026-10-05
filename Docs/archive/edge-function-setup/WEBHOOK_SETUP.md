# Database Webhook Setup for send-message-push

## Overview

Since Supabase Edge Functions are HTTP endpoints, we need to connect the database trigger to the Edge Function. The trigger uses `pg_notify`, but Supabase doesn't directly support listening to `pg_notify` in Edge Functions.

## Recommended Approach: Database Webhook

Supabase Database Webhooks can trigger on INSERT events, but they have limitations:
- They only have access to the NEW row data
- They can't easily access related tables (like `profiles` for sender name)
- They trigger once per INSERT, not per recipient

## Solution: Edge Function Handles Recipients

The Edge Function is designed to handle both cases:
1. **Full payload** (from trigger with all data) - processes one recipient
2. **Partial payload** (from webhook with just message data) - fetches recipients and processes them

However, since webhooks trigger once per INSERT, we need to either:
- Call the Edge Function multiple times (one per recipient) - requires custom logic
- Process all recipients in one Edge Function call

## Webhook Configuration

### Option A (Recommended): Edge Function webhook

1. Go to Supabase Dashboard → Database → Webhooks
2. Create new webhook:
   - **Name**: `message_push_webhook`
   - **Table**: `messages`
   - **Events**: `INSERT`
   - **Type**: **Supabase Edge Functions**
   - **Function**: `send-message-push`

### Option B: HTTP Request webhook

1. Go to Supabase Dashboard → Database → Webhooks
2. Create new webhook:
   - **Name**: `message_push_webhook`
   - **Table**: `messages`
   - **Events**: `INSERT`
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
       "id": "{{NEW.id}}",
       "conversation_id": "{{NEW.conversation_id}}",
       "from_id": "{{NEW.from_id}}",
       "text": "{{NEW.text}}"
     }
     ```

### Processing Multiple Recipients

The Edge Function will:
1. Receive the message data from webhook
2. Fetch all conversation participants (except sender)
3. For each recipient:
   - Check if they're actively viewing (last_seen)
   - If not viewing, send push notification

This means one webhook call processes all recipients, which is efficient.

## Alternative: Modify Trigger to Call Edge Function Directly

If your Supabase instance supports `pg_net` extension, you can modify the trigger to call the Edge Function directly via HTTP:

```sql
-- Enable pg_net (if available)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Update trigger function
CREATE OR REPLACE FUNCTION notify_message_push()
RETURNS TRIGGER AS $$
DECLARE
  recipient_record RECORD;
  edge_function_url TEXT := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-message-push';
  service_role_key TEXT := 'YOUR_SERVICE_ROLE_KEY';
  request_body JSONB;
  http_response http_response;
BEGIN
  -- ... (get sender_name, message_preview as before)
  
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
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Note**: This requires `pg_net` extension, which may not be available in all Supabase instances. Check with Supabase support.

## Testing

After setting up the webhook:

1. Send a message in the app
2. Check Edge Function logs in Supabase Dashboard
3. Verify push notification arrives on recipient device

## Troubleshooting

### Webhook Not Triggering
- Verify webhook is enabled in Supabase Dashboard
- Check webhook URL is correct
- Verify service role key is correct
- Check Edge Function logs for incoming requests

### Edge Function Not Processing Recipients
- Check logs for errors fetching participants
- Verify `conversation_participants` table has correct data
- Check that recipient user IDs are valid


