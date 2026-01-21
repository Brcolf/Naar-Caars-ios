-- Migration: CRITICAL FIX for Notification Triggers
-- Fixes multiple issues that break notifications and ride/favor posting:
-- 1. Wrong column name: posted_by should be user_id (rides/favors tables use user_id)
-- 2. Wrong column name: scheduled_time should be date + time (rides/favors don't have scheduled_time)
-- 3. Missing destination_name column reference (should be destination)

-- ============================================================================
-- PART 1: Fix notify_new_ride trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_new_ride()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_destination TEXT;
    v_user_record RECORD;
BEGIN
    -- Get poster name (FIX: use user_id not posted_by)
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    
    -- Get destination for notification body (FIX: use destination not destination_name)
    v_destination := COALESCE(NEW.destination, 'a destination');
    
    -- Notify ALL approved users (this notification cannot be disabled)
    FOR v_user_record IN 
        SELECT id FROM profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        -- Create in-app notification
        PERFORM create_notification(
            v_user_record.id,
            'new_ride',
            'New Ride Request',
            v_poster_name || ' needs a ride to ' || v_destination,
            NEW.id,  -- ride_id
            NULL,    -- favor_id
            NULL,    -- conversation_id
            NULL,    -- review_id
            NULL,    -- town_hall_post_id
            NEW.user_id  -- source_user_id
        );
        
        -- Queue push notification
        PERFORM queue_push_notification(
            v_user_record.id,
            'new_ride',
            'New Ride Request',
            v_poster_name || ' needs a ride to ' || v_destination,
            jsonb_build_object('ride_id', NEW.id::text)
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 2: Fix notify_new_favor trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_new_favor()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
BEGIN
    -- Get poster name (FIX: use user_id not posted_by)
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    
    -- Notify ALL approved users (this notification cannot be disabled)
    FOR v_user_record IN 
        SELECT id FROM profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        -- Create in-app notification
        PERFORM create_notification(
            v_user_record.id,
            'new_favor',
            'New Favor Request',
            v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
            NULL,    -- ride_id
            NEW.id,  -- favor_id
            NULL,    -- conversation_id
            NULL,    -- review_id
            NULL,    -- town_hall_post_id
            NEW.user_id  -- source_user_id
        );
        
        -- Queue push notification
        PERFORM queue_push_notification(
            v_user_record.id,
            'new_favor',
            'New Favor Request',
            v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
            jsonb_build_object('favor_id', NEW.id::text)
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 3: Fix notify_ride_status_change trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_ride_status_change()
RETURNS TRIGGER AS $$
DECLARE
    v_claimer_name TEXT;
    v_poster_name TEXT;
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_user_id UUID;
    v_co_requestor_id UUID;
    v_scheduled_datetime TIMESTAMPTZ;
BEGIN
    -- Only trigger on status changes
    IF OLD.status = NEW.status AND OLD.claimed_by IS NOT DISTINCT FROM NEW.claimed_by THEN
        RETURN NEW;
    END IF;
    
    -- Get names (FIX: use user_id not posted_by)
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM profiles WHERE id = NEW.claimed_by;
    END IF;
    
    -- Calculate scheduled datetime from date + time (FIX: rides don't have scheduled_time)
    v_scheduled_datetime := (NEW.date::date + NEW.time::time)::timestamptz;
    
    -- Determine notification type and content
    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        -- Ride was claimed
        v_notification_type := 'ride_claimed';
        v_title := 'Ride Claimed!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your ride';
        
        -- Schedule completion reminder (1 hour after scheduled time)
        INSERT INTO completion_reminders (ride_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, v_scheduled_datetime + INTERVAL '1 hour')
        ON CONFLICT DO NOTHING;
        
    ELSIF OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS NULL THEN
        -- Ride was unclaimed
        v_notification_type := 'ride_unclaimed';
        v_title := 'Ride Unclaimed';
        v_body := COALESCE(v_claimer_name, 'The helper') || ' is no longer available for your ride';
        
        -- Remove completion reminder
        DELETE FROM completion_reminders WHERE ride_id = NEW.id;
        
    ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        -- Ride was completed
        v_notification_type := 'ride_completed';
        v_title := 'Ride Completed';
        v_body := 'Your ride has been marked as completed';
        
        -- Mark completion reminder as completed
        UPDATE completion_reminders SET completed = true WHERE ride_id = NEW.id;
        
    ELSE
        -- Other status change
        v_notification_type := 'ride_update';
        v_title := 'Ride Updated';
        v_body := 'Your ride request has been updated';
    END IF;
    
    -- Notify the poster (if they didn't make the change)
    IF NEW.user_id != COALESCE(NEW.claimed_by, NEW.user_id) OR v_notification_type = 'ride_unclaimed' THEN
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            NEW.user_id,
            v_notification_type,
            v_title,
            v_body,
            jsonb_build_object('ride_id', NEW.id::text)
        );
    END IF;
    
    -- Notify co-requestors
    FOR v_co_requestor_id IN 
        SELECT user_id FROM ride_participants WHERE ride_id = NEW.id AND user_id != NEW.user_id
    LOOP
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            v_co_requestor_id,
            v_notification_type,
            v_title,
            v_body,
            jsonb_build_object('ride_id', NEW.id::text)
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 4: Fix notify_favor_status_change trigger
-- ============================================================================

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
BEGIN
    -- Only trigger on status changes
    IF OLD.status = NEW.status AND OLD.claimed_by IS NOT DISTINCT FROM NEW.claimed_by THEN
        RETURN NEW;
    END IF;
    
    -- Get names (FIX: use user_id not posted_by)
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM profiles WHERE id = NEW.claimed_by;
    END IF;
    
    -- Calculate scheduled datetime from date + time (FIX: favors don't have scheduled_time)
    -- Time is optional for favors, so use noon if not specified
    v_scheduled_datetime := (NEW.date::date + COALESCE(NEW.time::time, '12:00:00'::time))::timestamptz;
    
    -- Determine notification type and content
    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        -- Favor was claimed
        v_notification_type := 'favor_claimed';
        v_title := 'Someone Can Help!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your favor';
        
        -- Schedule completion reminder (1 hour after scheduled time)
        INSERT INTO completion_reminders (favor_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, v_scheduled_datetime + INTERVAL '1 hour')
        ON CONFLICT DO NOTHING;
        
    ELSIF OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS NULL THEN
        -- Favor was unclaimed
        v_notification_type := 'favor_unclaimed';
        v_title := 'Favor Unclaimed';
        v_body := COALESCE(v_claimer_name, 'The helper') || ' is no longer available for your favor';
        
        -- Remove completion reminder
        DELETE FROM completion_reminders WHERE favor_id = NEW.id;
        
    ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        -- Favor was completed
        v_notification_type := 'favor_completed';
        v_title := 'Favor Completed';
        v_body := 'Your favor has been marked as completed';
        
        -- Mark completion reminder as completed
        UPDATE completion_reminders SET completed = true WHERE favor_id = NEW.id;
        
    ELSE
        -- Other status change
        v_notification_type := 'favor_update';
        v_title := 'Favor Updated';
        v_body := 'Your favor request has been updated';
    END IF;
    
    -- Notify the poster (if they didn't make the change)
    IF NEW.user_id != COALESCE(NEW.claimed_by, NEW.user_id) OR v_notification_type = 'favor_unclaimed' THEN
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            NEW.user_id,
            v_notification_type,
            v_title,
            v_body,
            jsonb_build_object('favor_id', NEW.id::text)
        );
    END IF;
    
    -- Notify co-requestors
    FOR v_co_requestor_id IN 
        SELECT user_id FROM favor_participants WHERE favor_id = NEW.id AND user_id != NEW.user_id
    LOOP
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            v_co_requestor_id,
            v_notification_type,
            v_title,
            v_body,
            jsonb_build_object('favor_id', NEW.id::text)
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 5: Fix notify_qa_activity trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_qa_activity()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_questioner_name TEXT;
    v_ride RECORD;
    v_favor RECORD;
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_request_id UUID;
    v_request_type TEXT;
    v_is_claimed BOOLEAN := false;
    v_poster_id UUID;
    v_co_requestor_id UUID;
BEGIN
    -- Get questioner name
    SELECT name INTO v_questioner_name FROM profiles WHERE id = NEW.user_id;
    v_questioner_name := COALESCE(v_questioner_name, 'Someone');
    
    -- Determine if this is for a ride or favor and check if claimed
    -- (FIX: use user_id not posted_by)
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
        RETURN NEW;  -- No associated request
    END IF;
    
    -- Don't send Q&A notifications if request is already claimed
    -- (communication should happen through messages at that point)
    IF v_is_claimed THEN
        RETURN NEW;
    END IF;
    
    -- Determine notification type
    -- NOTE: The actual implementation uses question/answer columns on the same row (UPDATE for answers),
    -- not parent_id for threaded replies. This trigger only fires on INSERT (new questions).
    -- Answers are handled by UPDATE triggers or not triggered at all (the answer is just an update).
    v_notification_type := 'qa_question';
    v_title := 'New Question';
    v_body := v_questioner_name || ' asked: "' || LEFT(NEW.question, 50) || '"';
    
    -- Notify the poster (if they didn't ask the question)
    IF v_poster_id != NEW.user_id THEN
        PERFORM create_notification(
            v_poster_id,
            v_notification_type,
            v_title,
            v_body,
            CASE WHEN v_request_type = 'ride' THEN v_request_id ELSE NULL END,
            CASE WHEN v_request_type = 'favor' THEN v_request_id ELSE NULL END,
            NULL,
            NULL,
            NULL,
            NEW.user_id
        );
        
        PERFORM queue_push_notification(
            v_poster_id,
            v_notification_type,
            v_title,
            v_body,
            jsonb_build_object(
                CASE WHEN v_request_type = 'ride' THEN 'ride_id' ELSE 'favor_id' END, 
                v_request_id::text
            )
        );
    END IF;
    
    -- Notify co-requestors
    IF v_request_type = 'ride' THEN
        FOR v_co_requestor_id IN 
            SELECT user_id FROM ride_participants 
            WHERE ride_id = v_request_id AND user_id != v_poster_id AND user_id != NEW.user_id
        LOOP
            PERFORM create_notification(
                v_co_requestor_id,
                v_notification_type,
                v_title,
                v_body,
                v_request_id,
                NULL,
                NULL,
                NULL,
                NULL,
                NEW.user_id
            );
            
            PERFORM queue_push_notification(
                v_co_requestor_id,
                v_notification_type,
                v_title,
                v_body,
                jsonb_build_object('ride_id', v_request_id::text)
            );
        END LOOP;
    ELSE
        FOR v_co_requestor_id IN 
            SELECT user_id FROM favor_participants 
            WHERE favor_id = v_request_id AND user_id != v_poster_id AND user_id != NEW.user_id
        LOOP
            PERFORM create_notification(
                v_co_requestor_id,
                v_notification_type,
                v_title,
                v_body,
                NULL,
                v_request_id,
                NULL,
                NULL,
                NULL,
                NEW.user_id
            );
            
            PERFORM queue_push_notification(
                v_co_requestor_id,
                v_notification_type,
                v_title,
                v_body,
                jsonb_build_object('favor_id', v_request_id::text)
            );
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 6: Ensure triggers are properly attached
-- ============================================================================

-- Drop and recreate triggers to ensure they use the fixed functions
DROP TRIGGER IF EXISTS on_ride_created_notify ON rides;
CREATE TRIGGER on_ride_created_notify
AFTER INSERT ON rides
FOR EACH ROW
EXECUTE FUNCTION notify_new_ride();

DROP TRIGGER IF EXISTS on_favor_created_notify ON favors;
CREATE TRIGGER on_favor_created_notify
AFTER INSERT ON favors
FOR EACH ROW
EXECUTE FUNCTION notify_new_favor();

DROP TRIGGER IF EXISTS on_ride_status_change_notify ON rides;
CREATE TRIGGER on_ride_status_change_notify
AFTER UPDATE ON rides
FOR EACH ROW
EXECUTE FUNCTION notify_ride_status_change();

DROP TRIGGER IF EXISTS on_favor_status_change_notify ON favors;
CREATE TRIGGER on_favor_status_change_notify
AFTER UPDATE ON favors
FOR EACH ROW
EXECUTE FUNCTION notify_favor_status_change();

DROP TRIGGER IF EXISTS on_qa_created_notify ON request_qa;
CREATE TRIGGER on_qa_created_notify
AFTER INSERT ON request_qa
FOR EACH ROW
EXECUTE FUNCTION notify_qa_activity();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION notify_new_ride IS 'FIXED: Uses user_id instead of posted_by, destination instead of destination_name';
COMMENT ON FUNCTION notify_new_favor IS 'FIXED: Uses user_id instead of posted_by';
COMMENT ON FUNCTION notify_ride_status_change IS 'FIXED: Uses user_id instead of posted_by, date+time instead of scheduled_time';
COMMENT ON FUNCTION notify_favor_status_change IS 'FIXED: Uses user_id instead of posted_by, date+time instead of scheduled_time';
COMMENT ON FUNCTION notify_qa_activity IS 'FIXED: Uses user_id instead of posted_by';

