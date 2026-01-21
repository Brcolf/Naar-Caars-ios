-- Migration: Notification System Fixes
-- Adds notification_id to push payloads, fixes Q&A answer notifications,
-- and updates completion reminder handling + unread message badge support.

-- ============================================================================
-- PART 1: Add notification_id to queued push payloads
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_push_notification(
    p_recipient_user_id UUID,
    p_notification_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT '{}'::jsonb,
    p_batch_key TEXT DEFAULT NULL,
    p_notification_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_queue_id UUID;
    v_payload JSONB;
    v_data JSONB;
BEGIN
    -- Check if user wants this notification type
    IF NOT should_notify_user(p_recipient_user_id, p_notification_type) THEN
        RETURN NULL;
    END IF;
    
    v_data := COALESCE(p_data, '{}'::jsonb);
    IF p_notification_id IS NOT NULL THEN
        v_data := v_data || jsonb_build_object('notification_id', p_notification_id::text);
    END IF;
    
    -- Build payload
    v_payload := jsonb_build_object(
        'title', p_title,
        'body', p_body,
        'type', p_notification_type,
        'data', v_data
    );
    
    INSERT INTO notification_queue (
        notification_type, recipient_user_id, payload, batch_key
    ) VALUES (
        p_notification_type, p_recipient_user_id, v_payload, p_batch_key
    )
    RETURNING id INTO v_queue_id;
    
    RETURN v_queue_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION queue_push_notification(UUID, TEXT, TEXT, TEXT, JSONB, TEXT, UUID) TO authenticated;

-- ============================================================================
-- PART 2: Unread message count helper for badges
-- ============================================================================

CREATE OR REPLACE FUNCTION get_unread_message_count(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(m.id) INTO v_count
    FROM messages m
    JOIN conversation_participants cp
        ON cp.conversation_id = m.conversation_id
    WHERE cp.user_id = p_user_id
      AND cp.left_at IS NULL
      AND m.from_id != p_user_id
      AND (m.read_by IS NULL OR NOT (m.read_by @> ARRAY[p_user_id]::UUID[]));
    
    RETURN COALESCE(v_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_unread_message_count TO authenticated;
GRANT EXECUTE ON FUNCTION get_unread_message_count TO service_role;

-- ============================================================================
-- PART 3: Fix completion reminder response + include notification_id
-- ============================================================================

CREATE OR REPLACE FUNCTION handle_completion_response(
    p_reminder_id UUID,
    p_completed BOOLEAN
) RETURNS JSONB AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_requestor_id UUID;
    v_notification_id UUID;
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
            SELECT user_id, destination INTO v_requestor_id, v_request_title
            FROM rides WHERE id = v_reminder.ride_id;
        ELSE
            -- Update favor to completed
            UPDATE favors SET status = 'completed' WHERE id = v_reminder.favor_id;
            SELECT user_id, title INTO v_requestor_id, v_request_title
            FROM favors WHERE id = v_reminder.favor_id;
        END IF;
        
        -- Mark reminder as completed
        UPDATE completion_reminders SET completed = true WHERE id = p_reminder_id;
        
        -- Send review request notification to requestor
        v_notification_id := create_notification(
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
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_requestor_id,
                'review_request',
                'How was your experience?',
                'Your request has been completed. Leave a review!',
                jsonb_build_object(
                    'ride_id', v_reminder.ride_id::text,
                    'favor_id', v_reminder.favor_id::text,
                    'action', 'review'
                ),
                NULL,
                v_notification_id
            );
        END IF;
        
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

-- ============================================================================
-- PART 4: Completion reminder processing uses notification_id
-- ============================================================================

CREATE OR REPLACE FUNCTION process_completion_reminders()
RETURNS INTEGER AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_count INTEGER := 0;
    v_notification_id UUID;
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
            SELECT destination INTO v_request_title FROM rides WHERE id = v_reminder.ride_id;
            v_request_title := 'ride to ' || COALESCE(v_request_title, 'destination');
        ELSE
            SELECT title INTO v_request_title FROM favors WHERE id = v_reminder.favor_id;
            v_request_title := COALESCE(v_request_title, 'your favor');
        END IF;
        
        -- Create notification for claimer
        v_notification_id := create_notification(
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
        IF v_notification_id IS NOT NULL THEN
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
                ),
                NULL,
                v_notification_id
            );
        END IF;
        
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
-- PART 5: Q&A notifications (questions + answers) with participant fanout
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_qa_activity()
RETURNS TRIGGER AS $$
DECLARE
    v_questioner_name TEXT;
    v_ride RECORD;
    v_favor RECORD;
    v_request_id UUID;
    v_request_type TEXT;
    v_is_claimed BOOLEAN := false;
    v_poster_id UUID;
    v_notification_id UUID;
    v_recipient_id UUID;
BEGIN
    -- Get questioner name
    SELECT name INTO v_questioner_name FROM profiles WHERE id = NEW.user_id;
    v_questioner_name := COALESCE(v_questioner_name, 'Someone');
    
    -- Determine request type and claimed state
    IF NEW.ride_id IS NOT NULL THEN
        SELECT * INTO v_ride FROM rides WHERE id = NEW.ride_id;
        v_poster_id := v_ride.user_id;
        v_is_claimed := v_ride.claimed_by IS NOT NULL;
        v_request_type := 'ride';
        v_request_id := NEW.ride_id;
    ELSIF NEW.favor_id IS NOT NULL THEN
        SELECT * INTO v_favor FROM favors WHERE id = NEW.favor_id;
        v_poster_id := v_favor.user_id;
        v_is_claimed := v_favor.claimed_by IS NOT NULL;
        v_request_type := 'favor';
        v_request_id := NEW.favor_id;
    ELSE
        RETURN NEW;
    END IF;
    
    -- Don't send Q&A notifications if request is already claimed
    IF v_is_claimed THEN
        RETURN NEW;
    END IF;
    
    -- Notify poster, co-requestors, and all question participants
    FOR v_recipient_id IN
        SELECT DISTINCT user_id FROM (
            SELECT v_poster_id AS user_id
            UNION
            SELECT user_id FROM request_qa
            WHERE (v_request_type = 'ride' AND ride_id = v_request_id)
               OR (v_request_type = 'favor' AND favor_id = v_request_id)
            UNION
            SELECT user_id FROM ride_participants
            WHERE v_request_type = 'ride' AND ride_id = v_request_id
            UNION
            SELECT user_id FROM favor_participants
            WHERE v_request_type = 'favor' AND favor_id = v_request_id
        ) recipients
        WHERE user_id IS NOT NULL AND user_id != NEW.user_id
    LOOP
        v_notification_id := create_notification(
            v_recipient_id,
            'qa_question',
            'New Question',
            v_questioner_name || ' asked: "' || LEFT(NEW.question, 50) || '"',
            CASE WHEN v_request_type = 'ride' THEN v_request_id ELSE NULL END,
            CASE WHEN v_request_type = 'favor' THEN v_request_id ELSE NULL END,
            NULL,
            NULL,
            NULL,
            NEW.user_id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_recipient_id,
                'qa_question',
                'New Question',
                v_questioner_name || ' asked: "' || LEFT(NEW.question, 50) || '"',
                jsonb_build_object(
                    CASE WHEN v_request_type = 'ride' THEN 'ride_id' ELSE 'favor_id' END,
                    v_request_id::text
                ),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_qa_answer()
RETURNS TRIGGER AS $$
DECLARE
    v_answerer_name TEXT;
    v_ride RECORD;
    v_favor RECORD;
    v_request_id UUID;
    v_request_type TEXT;
    v_is_claimed BOOLEAN := false;
    v_poster_id UUID;
    v_notification_id UUID;
    v_recipient_id UUID;
BEGIN
    -- Only notify on new answers
    IF NEW.answer IS NULL OR NEW.answer = OLD.answer THEN
        RETURN NEW;
    END IF;
    
    -- Determine request type and claimed state
    IF NEW.ride_id IS NOT NULL THEN
        SELECT * INTO v_ride FROM rides WHERE id = NEW.ride_id;
        v_poster_id := v_ride.user_id;
        v_is_claimed := v_ride.claimed_by IS NOT NULL;
        v_request_type := 'ride';
        v_request_id := NEW.ride_id;
    ELSIF NEW.favor_id IS NOT NULL THEN
        SELECT * INTO v_favor FROM favors WHERE id = NEW.favor_id;
        v_poster_id := v_favor.user_id;
        v_is_claimed := v_favor.claimed_by IS NOT NULL;
        v_request_type := 'favor';
        v_request_id := NEW.favor_id;
    ELSE
        RETURN NEW;
    END IF;
    
    -- Don't send Q&A notifications if request is already claimed
    IF v_is_claimed THEN
        RETURN NEW;
    END IF;
    
    SELECT name INTO v_answerer_name FROM profiles WHERE id = v_poster_id;
    v_answerer_name := COALESCE(v_answerer_name, 'Someone');
    
    FOR v_recipient_id IN
        SELECT DISTINCT user_id FROM (
            SELECT v_poster_id AS user_id
            UNION
            SELECT user_id FROM request_qa
            WHERE (v_request_type = 'ride' AND ride_id = v_request_id)
               OR (v_request_type = 'favor' AND favor_id = v_request_id)
            UNION
            SELECT user_id FROM ride_participants
            WHERE v_request_type = 'ride' AND ride_id = v_request_id
            UNION
            SELECT user_id FROM favor_participants
            WHERE v_request_type = 'favor' AND favor_id = v_request_id
        ) recipients
        WHERE user_id IS NOT NULL AND user_id != v_poster_id
    LOOP
        v_notification_id := create_notification(
            v_recipient_id,
            'qa_answer',
            'Question Answered',
            v_answerer_name || ' answered a question',
            CASE WHEN v_request_type = 'ride' THEN v_request_id ELSE NULL END,
            CASE WHEN v_request_type = 'favor' THEN v_request_id ELSE NULL END,
            NULL,
            NULL,
            NULL,
            v_poster_id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_recipient_id,
                'qa_answer',
                'Question Answered',
                v_answerer_name || ' answered a question',
                jsonb_build_object(
                    CASE WHEN v_request_type = 'ride' THEN 'ride_id' ELSE 'favor_id' END,
                    v_request_id::text
                ),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_qa_created_notify ON request_qa;
CREATE TRIGGER on_qa_created_notify
AFTER INSERT ON request_qa
FOR EACH ROW
EXECUTE FUNCTION notify_qa_activity();

DROP TRIGGER IF EXISTS on_qa_answer_notify ON request_qa;
CREATE TRIGGER on_qa_answer_notify
AFTER UPDATE ON request_qa
FOR EACH ROW
EXECUTE FUNCTION notify_qa_answer();

-- ============================================================================
-- PART 6: Notification triggers include notification_id in push payloads
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_new_ride()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_destination TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    v_destination := COALESCE(NEW.destination, 'a destination');
    
    FOR v_user_record IN
        SELECT id FROM profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        v_notification_id := create_notification(
            v_user_record.id,
            'new_ride',
            'New Ride Request',
            v_poster_name || ' needs a ride to ' || v_destination,
            NEW.id,
            NULL,
            NULL,
            NULL,
            NULL,
            NEW.user_id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_user_record.id,
                'new_ride',
                'New Ride Request',
                v_poster_name || ' needs a ride to ' || v_destination,
                jsonb_build_object('ride_id', NEW.id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_new_favor()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    
    FOR v_user_record IN
        SELECT id FROM profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        v_notification_id := create_notification(
            v_user_record.id,
            'new_favor',
            'New Favor Request',
            v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
            NULL,
            NEW.id,
            NULL,
            NULL,
            NULL,
            NEW.user_id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_user_record.id,
                'new_favor',
                'New Favor Request',
                v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
                jsonb_build_object('favor_id', NEW.id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_ride_status_change()
RETURNS TRIGGER AS $$
DECLARE
    v_claimer_name TEXT;
    v_poster_name TEXT;
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_co_requestor_id UUID;
    v_scheduled_datetime TIMESTAMPTZ;
    v_notification_id UUID;
BEGIN
    IF OLD.status = NEW.status AND OLD.claimed_by IS NOT DISTINCT FROM NEW.claimed_by THEN
        RETURN NEW;
    END IF;
    
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM profiles WHERE id = NEW.claimed_by;
    END IF;
    
    v_scheduled_datetime := (NEW.date::date + NEW.time::time)::timestamptz;
    
    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        v_notification_type := 'ride_claimed';
        v_title := 'Ride Claimed!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your ride';
        INSERT INTO completion_reminders (ride_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, v_scheduled_datetime + INTERVAL '1 hour')
        ON CONFLICT DO NOTHING;
    ELSIF OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS NULL THEN
        v_notification_type := 'ride_unclaimed';
        v_title := 'Ride Unclaimed';
        v_body := COALESCE(v_claimer_name, 'The helper') || ' is no longer available for your ride';
        DELETE FROM completion_reminders WHERE ride_id = NEW.id;
    ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        v_notification_type := 'ride_completed';
        v_title := 'Ride Completed';
        v_body := 'Your ride has been marked as completed';
        UPDATE completion_reminders SET completed = true WHERE ride_id = NEW.id;
    ELSE
        v_notification_type := 'ride_update';
        v_title := 'Ride Updated';
        v_body := 'Your ride request has been updated';
    END IF;
    
    IF NEW.user_id != COALESCE(NEW.claimed_by, NEW.user_id) OR v_notification_type = 'ride_unclaimed' THEN
        v_notification_id := create_notification(
            NEW.user_id,
            v_notification_type,
            v_title,
            v_body,
            NEW.id,
            NULL,
            NULL,
            NULL,
            NULL,
            NEW.claimed_by
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                NEW.user_id,
                v_notification_type,
                v_title,
                v_body,
                jsonb_build_object('ride_id', NEW.id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END IF;
    
    FOR v_co_requestor_id IN
        SELECT user_id FROM ride_participants WHERE ride_id = NEW.id AND user_id != NEW.user_id
    LOOP
        v_notification_id := create_notification(
            v_co_requestor_id,
            v_notification_type,
            v_title,
            v_body,
            NEW.id,
            NULL,
            NULL,
            NULL,
            NULL,
            NEW.claimed_by
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_co_requestor_id,
                v_notification_type,
                v_title,
                v_body,
                jsonb_build_object('ride_id', NEW.id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_favor_status_change()
RETURNS TRIGGER AS $$
DECLARE
    v_claimer_name TEXT;
    v_poster_name TEXT;
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_co_requestor_id UUID;
    v_scheduled_datetime TIMESTAMPTZ;
    v_notification_id UUID;
BEGIN
    IF OLD.status = NEW.status AND OLD.claimed_by IS NOT DISTINCT FROM NEW.claimed_by THEN
        RETURN NEW;
    END IF;
    
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM profiles WHERE id = NEW.claimed_by;
    END IF;
    
    v_scheduled_datetime := (NEW.date::date + COALESCE(NEW.time::time, '12:00:00'::time))::timestamptz;
    
    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        v_notification_type := 'favor_claimed';
        v_title := 'Someone Can Help!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your favor';
        INSERT INTO completion_reminders (favor_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, v_scheduled_datetime + INTERVAL '1 hour')
        ON CONFLICT DO NOTHING;
    ELSIF OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS NULL THEN
        v_notification_type := 'favor_unclaimed';
        v_title := 'Favor Unclaimed';
        v_body := COALESCE(v_claimer_name, 'The helper') || ' is no longer available for your favor';
        DELETE FROM completion_reminders WHERE favor_id = NEW.id;
    ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        v_notification_type := 'favor_completed';
        v_title := 'Favor Completed';
        v_body := 'Your favor has been marked as completed';
        UPDATE completion_reminders SET completed = true WHERE favor_id = NEW.id;
    ELSE
        v_notification_type := 'favor_update';
        v_title := 'Favor Updated';
        v_body := 'Your favor request has been updated';
    END IF;
    
    IF NEW.user_id != COALESCE(NEW.claimed_by, NEW.user_id) OR v_notification_type = 'favor_unclaimed' THEN
        v_notification_id := create_notification(
            NEW.user_id,
            v_notification_type,
            v_title,
            v_body,
            NULL,
            NEW.id,
            NULL,
            NULL,
            NULL,
            NEW.claimed_by
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                NEW.user_id,
                v_notification_type,
                v_title,
                v_body,
                jsonb_build_object('favor_id', NEW.id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END IF;
    
    FOR v_co_requestor_id IN
        SELECT user_id FROM favor_participants WHERE favor_id = NEW.id AND user_id != NEW.user_id
    LOOP
        v_notification_id := create_notification(
            v_co_requestor_id,
            v_notification_type,
            v_title,
            v_body,
            NULL,
            NEW.id,
            NULL,
            NULL,
            NULL,
            NEW.claimed_by
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_co_requestor_id,
                v_notification_type,
                v_title,
                v_body,
                jsonb_build_object('favor_id', NEW.id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 7: Town Hall + Admin + Conversation push payloads include notification_id
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_town_hall_post()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_batch_key TEXT;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    
    v_batch_key := 'town_hall_' || to_char(date_trunc('minute', NOW()) -
        (EXTRACT(MINUTE FROM NOW())::int % 5) * INTERVAL '1 minute', 'YYYY-MM-DD-HH24-MI');
    
    FOR v_user_record IN
        SELECT id FROM profiles
        WHERE approved = true
          AND id != NEW.user_id
          AND notify_town_hall = true
    LOOP
        v_notification_id := create_notification(
            v_user_record.id,
            'town_hall_post',
            'New in Town Hall',
            v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
            NULL,
            NULL,
            NULL,
            NULL,
            NEW.id,
            NEW.user_id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_user_record.id,
                'town_hall_post',
                'New in Town Hall',
                v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
                jsonb_build_object('town_hall_post_id', NEW.id::text),
                v_batch_key,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_town_hall_comment()
RETURNS TRIGGER AS $$
DECLARE
    v_commenter_name TEXT;
    v_post RECORD;
    v_interactor_id UUID;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_commenter_name FROM profiles WHERE id = NEW.user_id;
    v_commenter_name := COALESCE(v_commenter_name, 'Someone');
    
    SELECT * INTO v_post FROM town_hall_posts WHERE id = NEW.post_id;
    
    INSERT INTO town_hall_post_interactions (post_id, user_id, interaction_type)
    VALUES (NEW.post_id, NEW.user_id, 'comment')
    ON CONFLICT (post_id, user_id, interaction_type) DO NOTHING;
    
    IF v_post.user_id != NEW.user_id THEN
        v_notification_id := create_notification(
            v_post.user_id,
            'town_hall_comment',
            'New Comment',
            v_commenter_name || ' commented on your post',
            NULL,
            NULL,
            NULL,
            NULL,
            NEW.post_id,
            NEW.user_id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_post.user_id,
                'town_hall_comment',
                'New Comment',
                v_commenter_name || ' commented on your post',
                jsonb_build_object('town_hall_post_id', NEW.post_id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END IF;
    
    FOR v_interactor_id IN
        SELECT DISTINCT user_id FROM town_hall_post_interactions
        WHERE post_id = NEW.post_id
          AND user_id != NEW.user_id
          AND user_id != v_post.user_id
    LOOP
        v_notification_id := create_notification(
            v_interactor_id,
            'town_hall_comment',
            'New Comment',
            v_commenter_name || ' also commented on a post you interacted with',
            NULL,
            NULL,
            NULL,
            NULL,
            NEW.post_id,
            NEW.user_id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_interactor_id,
                'town_hall_comment',
                'New Comment',
                v_commenter_name || ' also commented on a post you interacted with',
                jsonb_build_object('town_hall_post_id', NEW.post_id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_pending_user()
RETURNS TRIGGER AS $$
DECLARE
    v_admin_id UUID;
    v_user_name TEXT;
    v_notification_id UUID;
BEGIN
    -- Only trigger for new unapproved users
    IF NEW.approved = true THEN
        RETURN NEW;
    END IF;
    
    v_user_name := COALESCE(NEW.name, NEW.email);
    
    FOR v_admin_id IN
        SELECT id FROM profiles WHERE is_admin = true AND approved = true
    LOOP
        v_notification_id := create_notification(
            v_admin_id,
            'pending_approval',
            'New User Pending Approval',
            v_user_name || ' is waiting for approval',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NEW.id
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_admin_id,
                'pending_approval',
                'New User Pending Approval',
                v_user_name || ' is waiting for approval',
                jsonb_build_object('user_id', NEW.id::text),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_user_approved()
RETURNS TRIGGER AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    IF OLD.approved = false AND NEW.approved = true THEN
        v_notification_id := create_notification(
            NEW.id,
            'user_approved',
            'Welcome to Naar''s Cars!',
            'Your account has been approved. Tap to enter the app.',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        );
        
        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                NEW.id,
                'user_approved',
                'Welcome to Naar''s Cars!',
                'Your account has been approved. Tap to enter the app.',
                jsonb_build_object('action', 'enter_app'),
                NULL,
                v_notification_id
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_added_to_conversation()
RETURNS TRIGGER AS $$
DECLARE
    v_conversation RECORD;
    v_adder_name TEXT;
    v_notification_id UUID;
BEGIN
    SELECT * INTO v_conversation FROM conversations WHERE id = NEW.conversation_id;
    
    SELECT name INTO v_adder_name FROM profiles WHERE id = v_conversation.created_by;
    v_adder_name := COALESCE(v_adder_name, 'Someone');
    
    IF NEW.user_id = v_conversation.created_by THEN
        RETURN NEW;
    END IF;
    
    v_notification_id := create_notification(
        NEW.user_id,
        'added_to_conversation',
        'Added to Conversation',
        v_adder_name || ' added you to a conversation',
        NULL,
        NULL,
        NEW.conversation_id,
        NULL,
        NULL,
        v_conversation.created_by
    );
    
    IF v_notification_id IS NOT NULL THEN
        PERFORM queue_push_notification(
            NEW.user_id,
            'added_to_conversation',
            'Added to Conversation',
            v_adder_name || ' added you to a conversation',
            jsonb_build_object('conversation_id', NEW.conversation_id::text),
            NULL,
            v_notification_id
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


