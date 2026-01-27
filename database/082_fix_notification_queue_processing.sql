-- Migration: Fix Notification Queue Processing
-- The notification_queue table stores push notifications but they need to be processed
-- This migration adds:
-- 1. A trigger to immediately process non-batched notifications
-- 2. Proper RLS policies for the notification_queue table
-- 3. A function to send push notifications directly (bypassing queue for immediate delivery)

-- ============================================================================
-- PART 1: Enable RLS on notification_queue
-- ============================================================================

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

-- Allow service role and triggers to insert
CREATE POLICY "notification_queue_insert_authenticated" ON public.notification_queue
    FOR INSERT 
    WITH CHECK (true);  -- Triggers use SECURITY DEFINER

-- Allow service role to select/update for processing
CREATE POLICY "notification_queue_select_service" ON public.notification_queue
    FOR SELECT 
    USING (true);  -- Edge functions use service role

CREATE POLICY "notification_queue_update_service" ON public.notification_queue
    FOR UPDATE 
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- PART 2: Create function to immediately process a queued notification
-- This is called by a trigger when a non-batched notification is inserted
-- ============================================================================

CREATE OR REPLACE FUNCTION process_immediate_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process non-batched notifications immediately
    IF NEW.batch_key IS NULL THEN
        -- Mark as processed immediately (Edge Function webhook will pick it up)
        NEW.processed_at := NOW();
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to mark non-batched notifications as processed immediately
DROP TRIGGER IF EXISTS on_notification_queue_insert ON notification_queue;
CREATE TRIGGER on_notification_queue_insert
BEFORE INSERT ON notification_queue
FOR EACH ROW
EXECUTE FUNCTION process_immediate_notification();

-- ============================================================================
-- PART 3: Create a direct push notification function
-- This bypasses the queue for immediate push delivery
-- Can be called from triggers that need instant push notifications
-- ============================================================================

CREATE OR REPLACE FUNCTION send_push_notification_direct(
    p_user_id UUID,
    p_notification_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT '{}'::jsonb
) RETURNS VOID AS $$
DECLARE
    v_token_record RECORD;
    v_payload JSONB;
BEGIN
    -- Check if user wants this notification type
    IF NOT should_notify_user(p_user_id, p_notification_type) THEN
        RETURN;
    END IF;
    
    -- Build the notification payload
    v_payload := jsonb_build_object(
        'recipient_user_id', p_user_id::text,
        'notification_type', p_notification_type,
        'title', p_title,
        'body', p_body,
        'data', p_data
    );
    
    -- Insert into notification_queue with processed_at set
    -- This will trigger the webhook for immediate delivery
    INSERT INTO notification_queue (
        notification_type,
        recipient_user_id,
        payload,
        batch_key,
        processed_at
    ) VALUES (
        p_notification_type,
        p_user_id,
        jsonb_build_object(
            'title', p_title,
            'body', p_body,
            'type', p_notification_type,
            'data', p_data
        ),
        NULL,  -- No batching
        NOW()  -- Mark as processed immediately
    );
    
    -- Use pg_notify to signal the Edge Function
    PERFORM pg_notify(
        'push_notification',
        v_payload::text
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION send_push_notification_direct TO authenticated;

-- ============================================================================
-- PART 4: Update message push trigger to use direct notification
-- This ensures message notifications are sent immediately
-- ============================================================================

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
        IF recipient_record.last_seen IS NOT NULL THEN
            IF EXTRACT(EPOCH FROM (NOW() - recipient_record.last_seen)) < 60 THEN
                -- User is actively viewing, skip push
                CONTINUE;
            END IF;
        END IF;
        
        -- Check if user wants message notifications
        IF NOT should_notify_user(recipient_user_id, 'message') THEN
            CONTINUE;
        END IF;
        
        -- Send push notification directly (bypassing queue for immediate delivery)
        PERFORM send_push_notification_direct(
            recipient_user_id,
            'message',
            'Message from ' || sender_name,
            message_preview,
            jsonb_build_object(
                'conversation_id', conversation_id_val::text,
                'message_id', NEW.id::text,
                'sender_id', NEW.from_id::text
            )
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
DROP TRIGGER IF EXISTS on_message_inserted_push ON messages;
CREATE TRIGGER on_message_inserted_push
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION notify_message_push();

-- ============================================================================
-- PART 5: Add notification_queue to realtime publication
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'notification_queue'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_queue;
    END IF;
EXCEPTION
    WHEN undefined_object THEN
        NULL; -- Publication doesn't exist, skip
END $$;

-- Set REPLICA IDENTITY for realtime
ALTER TABLE public.notification_queue REPLICA IDENTITY FULL;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION process_immediate_notification IS 'Trigger function that marks non-batched notifications as processed immediately';
COMMENT ON FUNCTION send_push_notification_direct IS 'Sends a push notification directly, bypassing the queue for immediate delivery';
COMMENT ON FUNCTION notify_message_push IS 'Updated to use direct push notification for immediate message delivery';


