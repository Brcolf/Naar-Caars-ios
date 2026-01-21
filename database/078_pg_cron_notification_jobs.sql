-- Migration: Completion Reminder Functions & Batched Notifications
-- Provides database functions for completion reminder handling
-- Completion reminders are scheduled via iOS local notifications (no pg_cron required)
-- Town Hall batching can be handled by external cron or Edge Function scheduler

-- ============================================================================
-- NOTE: This migration does NOT require pg_cron or Supabase Pro
-- - Completion reminders: Scheduled on device via iOS local notifications
-- - Town Hall batching: Optional - notifications send immediately if no cron
-- - The functions are available for manual/external invocation if needed
-- ============================================================================

-- ============================================================================
-- PART 1: Function to handle completion reminder response (Yes/No from notification)
-- Called from iOS when user taps Yes/No on the local notification
-- ============================================================================

CREATE OR REPLACE FUNCTION handle_completion_response(
    p_reminder_id UUID,
    p_completed BOOLEAN
) RETURNS JSONB AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_requestor_id UUID;
BEGIN
    -- Get the reminder
    SELECT * INTO v_reminder FROM completion_reminders WHERE id = p_reminder_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Reminder not found');
    END IF;
    
    IF p_completed THEN
        -- User says YES, request is completed
        IF v_reminder.ride_id IS NOT NULL THEN
            -- Update ride to completed
            UPDATE rides SET status = 'completed' WHERE id = v_reminder.ride_id;
            SELECT posted_by, destination_name INTO v_requestor_id, v_request_title 
            FROM rides WHERE id = v_reminder.ride_id;
        ELSE
            -- Update favor to completed
            UPDATE favors SET status = 'completed' WHERE id = v_reminder.favor_id;
            SELECT posted_by, title INTO v_requestor_id, v_request_title 
            FROM favors WHERE id = v_reminder.favor_id;
        END IF;
        
        -- Mark reminder as completed
        UPDATE completion_reminders SET completed = true WHERE id = p_reminder_id;
        
        -- Send review request notification to requestor
        PERFORM create_notification(
            v_requestor_id,
            'review_request',
            'How was your experience?',
            'Your request has been completed. Leave a review to thank your helper!',
            v_reminder.ride_id,
            v_reminder.favor_id,
            NULL,
            NULL,
            NULL,
            v_reminder.claimer_user_id
        );
        
        PERFORM queue_push_notification(
            v_requestor_id,
            'review_request',
            'How was your experience?',
            'Your request has been completed. Leave a review!',
            jsonb_build_object(
                'ride_id', v_reminder.ride_id::text,
                'favor_id', v_reminder.favor_id::text,
                'action', 'review'
            )
        );
        
        RETURN jsonb_build_object('success', true, 'action', 'completed');
    ELSE
        -- User says NO, snooze for 1 hour
        UPDATE completion_reminders 
        SET 
            scheduled_for = NOW() + INTERVAL '1 hour',
            reminder_count = reminder_count + 1,
            last_reminded_at = NOW()
        WHERE id = p_reminder_id;
        
        RETURN jsonb_build_object('success', true, 'action', 'snoozed', 'next_reminder', NOW() + INTERVAL '1 hour');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION handle_completion_response TO authenticated;
GRANT EXECUTE ON FUNCTION handle_completion_response TO service_role;

-- ============================================================================
-- PART 2: Function to process due completion reminders (OPTIONAL - fallback only)
-- This is NOT used when iOS local notifications are working
-- Kept as a fallback if you add pg_cron or external cron later
-- ============================================================================

CREATE OR REPLACE FUNCTION process_completion_reminders()
RETURNS INTEGER AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_count INTEGER := 0;
BEGIN
    -- Find reminders that are due and not yet completed
    FOR v_reminder IN
        SELECT * FROM completion_reminders
        WHERE scheduled_for <= NOW()
          AND completed = false
          AND (last_reminded_at IS NULL OR last_reminded_at < NOW() - INTERVAL '30 minutes')
    LOOP
        -- Get request title
        IF v_reminder.ride_id IS NOT NULL THEN
            SELECT destination_name INTO v_request_title FROM rides WHERE id = v_reminder.ride_id;
            v_request_title := 'ride to ' || COALESCE(v_request_title, 'destination');
        ELSE
            SELECT title INTO v_request_title FROM favors WHERE id = v_reminder.favor_id;
            v_request_title := COALESCE(v_request_title, 'your favor');
        END IF;
        
        -- Create notification for claimer
        PERFORM create_notification(
            v_reminder.claimer_user_id,
            'completion_reminder',
            'Is This Complete?',
            'Did you complete the ' || v_request_title || '?',
            v_reminder.ride_id,
            v_reminder.favor_id,
            NULL,
            NULL,
            NULL,
            NULL
        );
        
        -- Queue push notification with actionable buttons
        PERFORM queue_push_notification(
            v_reminder.claimer_user_id,
            'completion_reminder',
            'Is This Complete?',
            'Did you complete the ' || v_request_title || '?',
            jsonb_build_object(
                'reminder_id', v_reminder.id::text,
                'ride_id', v_reminder.ride_id::text,
                'favor_id', v_reminder.favor_id::text,
                'actionable', true
            )
        );
        
        -- Update last reminded timestamp
        UPDATE completion_reminders 
        SET last_reminded_at = NOW()
        WHERE id = v_reminder.id;
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 3: Function to process batched Town Hall notifications (OPTIONAL)
-- Can be called from external cron or manually - not required for basic operation
-- ============================================================================

CREATE OR REPLACE FUNCTION process_batched_notifications()
RETURNS INTEGER AS $$
DECLARE
    v_batch RECORD;
    v_count INTEGER := 0;
    v_notifications_in_batch INTEGER;
BEGIN
    -- Process batch keys that have been waiting for at least 3 minutes
    -- and haven't been processed yet
    FOR v_batch IN
        SELECT batch_key, recipient_user_id, COUNT(*) as notification_count
        FROM notification_queue
        WHERE batch_key IS NOT NULL
          AND processed_at IS NULL
          AND created_at <= NOW() - INTERVAL '3 minutes'
        GROUP BY batch_key, recipient_user_id
    LOOP
        v_notifications_in_batch := v_batch.notification_count;
        
        IF v_notifications_in_batch = 1 THEN
            -- Single notification - send as-is
            UPDATE notification_queue nq
            SET processed_at = NOW()
            WHERE nq.batch_key = v_batch.batch_key
              AND nq.recipient_user_id = v_batch.recipient_user_id
              AND nq.processed_at IS NULL;
              
            -- The actual send will be handled by the webhook trigger on processed_at update
        ELSE
            -- Multiple notifications - send batched summary
            -- First, mark all as processed
            UPDATE notification_queue
            SET 
                processed_at = NOW(),
                payload = jsonb_set(
                    payload,
                    '{body}',
                    to_jsonb(v_notifications_in_batch || ' new posts in Town Hall')
                ),
                -- Clear the title for non-primary ones so they don't send
                sent_at = CASE 
                    WHEN id = (
                        SELECT id FROM notification_queue nq2
                        WHERE nq2.batch_key = v_batch.batch_key
                          AND nq2.recipient_user_id = v_batch.recipient_user_id
                        ORDER BY created_at ASC
                        LIMIT 1
                    ) THEN NULL  -- Primary one will send
                    ELSE NOW()   -- Mark others as already sent
                END
            WHERE batch_key = v_batch.batch_key
              AND recipient_user_id = v_batch.recipient_user_id
              AND processed_at IS NULL;
        END IF;
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 4: Webhook trigger to send push when notification_queue is processed
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_notification_send()
RETURNS TRIGGER AS $$
BEGIN
    -- Only trigger when processed_at is set and sent_at is still null
    IF NEW.processed_at IS NOT NULL AND NEW.sent_at IS NULL AND OLD.processed_at IS NULL THEN
        -- This will be picked up by the Edge Function webhook on notification_queue
        -- Or you can call the Edge Function directly via pg_net if available
        PERFORM pg_notify('notification_ready', json_build_object('id', NEW.id)::text);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_notification_processed ON notification_queue;
CREATE TRIGGER on_notification_processed
AFTER UPDATE ON notification_queue
FOR EACH ROW
WHEN (NEW.processed_at IS NOT NULL AND NEW.sent_at IS NULL AND OLD.processed_at IS NULL)
EXECUTE FUNCTION trigger_notification_send();

-- ============================================================================
-- PART 5: Add last_used_at column to push_tokens if not exists
-- ============================================================================

ALTER TABLE push_tokens
ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION handle_completion_response IS 'Handles Yes/No response from completion reminder notification. Yes marks request completed and triggers review. No snoozes for 1 hour.';
COMMENT ON FUNCTION process_completion_reminders IS 'Processes due completion reminders and sends notifications to claimers';
COMMENT ON FUNCTION process_batched_notifications IS 'Processes batched notifications (like Town Hall) that have been waiting for 3+ minutes';


