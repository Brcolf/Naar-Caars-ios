-- Migration: Create trigger for real-time push notifications on message insert
-- This trigger fires immediately when a message is inserted and notifies
-- recipients via pg_notify, which can be picked up by Edge Functions

-- Function to notify Edge Function about new message for push notification
CREATE OR REPLACE FUNCTION notify_message_push()
RETURNS TRIGGER AS $$
DECLARE
  recipient_user_id UUID;
  conversation_id_val UUID;
  sender_name TEXT;
  message_preview TEXT;
  recipient_record RECORD;
BEGIN
  -- Get conversation ID from new message
  conversation_id_val := NEW.conversation_id;
  
  -- Get sender name for notification
  SELECT name INTO sender_name
  FROM profiles
  WHERE id = NEW.from_id;
  
  -- Fallback if sender name not found
  IF sender_name IS NULL THEN
    sender_name := 'Someone';
  END IF;
  
  -- Get preview of message (first 50 chars)
  message_preview := LEFT(NEW.text, 50);
  IF LENGTH(NEW.text) > 50 THEN
    message_preview := message_preview || '...';
  END IF;
  
  -- Get all participants except the sender
  FOR recipient_record IN
    SELECT cp.user_id, cp.last_seen
    FROM conversation_participants cp
    WHERE cp.conversation_id = conversation_id_val
      AND cp.user_id != NEW.from_id
  LOOP
    recipient_user_id := recipient_record.user_id;
    
    -- Check if recipient is actively viewing (within last 60 seconds)
    -- If they are, skip push notification
    IF recipient_record.last_seen IS NOT NULL THEN
      -- If user viewed conversation within last 60 seconds, they're likely still viewing
      -- Skip push notification in this case
      IF EXTRACT(EPOCH FROM (NOW() - recipient_record.last_seen)) < 60 THEN
        -- User is actively viewing, skip push
        CONTINUE;
      END IF;
    END IF;
    
    -- User is not actively viewing, notify for push
    -- Use pg_notify to send notification that Edge Function can listen to
    -- Note: For Supabase, we'll use Database Webhooks instead of pg_notify
    -- This pg_notify is kept for compatibility, but webhooks are the primary method
    PERFORM pg_notify(
      'message_push',
      json_build_object(
        'recipient_user_id', recipient_user_id::text,
        'conversation_id', conversation_id_val::text,
        'sender_name', sender_name,
        'message_preview', message_preview,
        'message_id', NEW.id::text,
        'sender_id', NEW.from_id::text
      )::text
    );
    
    -- Also insert a record into a notifications queue table for webhook processing
    -- This is a fallback if webhooks don't work directly
    -- You can create a table like: notifications_queue (id, payload, created_at, processed)
    -- Or rely on Supabase Database Webhooks configured in the dashboard
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger that fires on message insert
CREATE TRIGGER on_message_inserted_push
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION notify_message_push();

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION notify_message_push() TO authenticated;

-- Add comments for documentation
COMMENT ON FUNCTION notify_message_push() IS 'Triggered when a message is inserted. Sends pg_notify event for push notification delivery, but only if recipient is not actively viewing the conversation (last_seen < 60 seconds ago).';

COMMENT ON TRIGGER on_message_inserted_push ON messages IS 'Fires immediately after message insert to trigger push notification via Edge Function. Checks last_seen to avoid sending push when user is actively viewing.';

