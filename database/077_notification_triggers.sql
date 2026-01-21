-- Migration: Notification Triggers
-- Creates database triggers for all notification events

-- ============================================================================
-- TRIGGER 1: New Ride Request - Notify ALL users (mandatory, cannot be disabled)
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_new_ride()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_destination TEXT;
    v_user_record RECORD;
BEGIN
    -- Get poster name
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.posted_by;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    
    -- Get destination for notification body
    v_destination := COALESCE(NEW.destination_name, 'a destination');
    
    -- Notify ALL approved users (this notification cannot be disabled)
    FOR v_user_record IN 
        SELECT id FROM profiles WHERE approved = true AND id != NEW.posted_by
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
            NEW.posted_by  -- source_user_id
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

DROP TRIGGER IF EXISTS on_ride_created_notify ON rides;
CREATE TRIGGER on_ride_created_notify
AFTER INSERT ON rides
FOR EACH ROW
EXECUTE FUNCTION notify_new_ride();

-- ============================================================================
-- TRIGGER 2: New Favor Request - Notify ALL users (mandatory, cannot be disabled)
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_new_favor()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
BEGIN
    -- Get poster name
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.posted_by;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    
    -- Notify ALL approved users (this notification cannot be disabled)
    FOR v_user_record IN 
        SELECT id FROM profiles WHERE approved = true AND id != NEW.posted_by
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
            NEW.posted_by  -- source_user_id
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

DROP TRIGGER IF EXISTS on_favor_created_notify ON favors;
CREATE TRIGGER on_favor_created_notify
AFTER INSERT ON favors
FOR EACH ROW
EXECUTE FUNCTION notify_new_favor();

-- ============================================================================
-- TRIGGER 3: Ride Claimed/Unclaimed/Completed - Notify requestor + co-requestors
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
BEGIN
    -- Only trigger on status changes
    IF OLD.status = NEW.status AND OLD.claimed_by IS NOT DISTINCT FROM NEW.claimed_by THEN
        RETURN NEW;
    END IF;
    
    -- Get names
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.posted_by;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM profiles WHERE id = NEW.claimed_by;
    END IF;
    
    -- Determine notification type and content
    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        -- Ride was claimed
        v_notification_type := 'ride_claimed';
        v_title := 'Ride Claimed!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your ride';
        
        -- Schedule completion reminder (1 hour after scheduled time)
        INSERT INTO completion_reminders (ride_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, NEW.scheduled_time + INTERVAL '1 hour')
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
    IF NEW.posted_by != COALESCE(NEW.claimed_by, NEW.posted_by) OR v_notification_type = 'ride_unclaimed' THEN
        PERFORM create_notification(
            NEW.posted_by,
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
            NEW.posted_by,
            v_notification_type,
            v_title,
            v_body,
            jsonb_build_object('ride_id', NEW.id::text)
        );
    END IF;
    
    -- Notify co-requestors
    FOR v_co_requestor_id IN 
        SELECT user_id FROM ride_participants WHERE ride_id = NEW.id AND user_id != NEW.posted_by
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
    
    -- If unclaimed, notify the previous claimer too
    IF v_notification_type = 'ride_unclaimed' AND OLD.claimed_by IS NOT NULL THEN
        -- The claimer already knows they unclaimed, but if someone else unclaimed them, notify
        -- Actually, only the claimer can unclaim themselves, so skip this
        NULL;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_ride_status_change_notify ON rides;
CREATE TRIGGER on_ride_status_change_notify
AFTER UPDATE ON rides
FOR EACH ROW
EXECUTE FUNCTION notify_ride_status_change();

-- ============================================================================
-- TRIGGER 4: Favor Claimed/Unclaimed/Completed - Notify requestor + co-requestors
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
BEGIN
    -- Only trigger on status changes
    IF OLD.status = NEW.status AND OLD.claimed_by IS NOT DISTINCT FROM NEW.claimed_by THEN
        RETURN NEW;
    END IF;
    
    -- Get names
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.posted_by;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM profiles WHERE id = NEW.claimed_by;
    END IF;
    
    -- Determine notification type and content
    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        -- Favor was claimed
        v_notification_type := 'favor_claimed';
        v_title := 'Someone Can Help!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your favor';
        
        -- Schedule completion reminder (1 hour after scheduled time)
        INSERT INTO completion_reminders (favor_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, COALESCE(NEW.scheduled_time, NOW()) + INTERVAL '1 hour')
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
    IF NEW.posted_by != COALESCE(NEW.claimed_by, NEW.posted_by) OR v_notification_type = 'favor_unclaimed' THEN
        PERFORM create_notification(
            NEW.posted_by,
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
            NEW.posted_by,
            v_notification_type,
            v_title,
            v_body,
            jsonb_build_object('favor_id', NEW.id::text)
        );
    END IF;
    
    -- Notify co-requestors
    FOR v_co_requestor_id IN 
        SELECT user_id FROM favor_participants WHERE favor_id = NEW.id AND user_id != NEW.posted_by
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

DROP TRIGGER IF EXISTS on_favor_status_change_notify ON favors;
CREATE TRIGGER on_favor_status_change_notify
AFTER UPDATE ON favors
FOR EACH ROW
EXECUTE FUNCTION notify_favor_status_change();

-- ============================================================================
-- TRIGGER 5: Q&A Activity - Notify requestor + co-requestors (only if not claimed)
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
    IF NEW.ride_id IS NOT NULL THEN
        SELECT * INTO v_ride FROM rides WHERE id = NEW.ride_id;
        v_poster_id := v_ride.posted_by;
        v_is_claimed := v_ride.claimed_by IS NOT NULL;
        v_request_type := 'ride';
        v_request_id := NEW.ride_id;
    ELSIF NEW.favor_id IS NOT NULL THEN
        SELECT * INTO v_favor FROM favors WHERE id = NEW.favor_id;
        v_poster_id := v_favor.posted_by;
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
    IF NEW.parent_id IS NULL THEN
        v_notification_type := 'qa_question';
        v_title := 'New Question';
        v_body := v_questioner_name || ' asked: "' || LEFT(NEW.content, 50) || '"';
    ELSE
        v_notification_type := 'qa_answer';
        v_title := 'Question Answered';
        v_body := v_questioner_name || ' replied: "' || LEFT(NEW.content, 50) || '"';
    END IF;
    
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

DROP TRIGGER IF EXISTS on_qa_created_notify ON request_qa;
CREATE TRIGGER on_qa_created_notify
AFTER INSERT ON request_qa
FOR EACH ROW
EXECUTE FUNCTION notify_qa_activity();

-- ============================================================================
-- TRIGGER 6: Town Hall Post - Queue for batched notification to all users
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_town_hall_post()
RETURNS TRIGGER AS $$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_batch_key TEXT;
BEGIN
    -- Get poster name
    SELECT name INTO v_poster_name FROM profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    
    -- Create batch key for grouping (5-minute windows)
    v_batch_key := 'town_hall_' || to_char(date_trunc('minute', NOW()) - 
        (EXTRACT(MINUTE FROM NOW())::int % 5) * INTERVAL '1 minute', 'YYYY-MM-DD-HH24-MI');
    
    -- Queue notifications for all users who have town hall notifications enabled
    FOR v_user_record IN 
        SELECT id FROM profiles 
        WHERE approved = true 
        AND id != NEW.user_id 
        AND notify_town_hall = true
    LOOP
        -- Queue push notification with batch key
        PERFORM queue_push_notification(
            v_user_record.id,
            'town_hall_post',
            'New in Town Hall',
            v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
            jsonb_build_object('town_hall_post_id', NEW.id::text),
            v_batch_key
        );
        
        -- Create in-app notification immediately
        PERFORM create_notification(
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
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_town_hall_post_notify ON town_hall_posts;
CREATE TRIGGER on_town_hall_post_notify
AFTER INSERT ON town_hall_posts
FOR EACH ROW
EXECUTE FUNCTION notify_town_hall_post();

-- ============================================================================
-- TRIGGER 7: Town Hall Comment - Notify poster + all who interacted
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_town_hall_comment()
RETURNS TRIGGER AS $$
DECLARE
    v_commenter_name TEXT;
    v_post RECORD;
    v_interactor_id UUID;
BEGIN
    -- Get commenter name
    SELECT name INTO v_commenter_name FROM profiles WHERE id = NEW.user_id;
    v_commenter_name := COALESCE(v_commenter_name, 'Someone');
    
    -- Get post info
    SELECT * INTO v_post FROM town_hall_posts WHERE id = NEW.post_id;
    
    -- Record this interaction
    INSERT INTO town_hall_post_interactions (post_id, user_id, interaction_type)
    VALUES (NEW.post_id, NEW.user_id, 'comment')
    ON CONFLICT (post_id, user_id, interaction_type) DO NOTHING;
    
    -- Notify the post author (if not the commenter)
    IF v_post.user_id != NEW.user_id THEN
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            v_post.user_id,
            'town_hall_comment',
            'New Comment',
            v_commenter_name || ' commented on your post',
            jsonb_build_object('town_hall_post_id', NEW.post_id::text)
        );
    END IF;
    
    -- Notify all users who have interacted with this post (except commenter and poster)
    FOR v_interactor_id IN 
        SELECT DISTINCT user_id FROM town_hall_post_interactions 
        WHERE post_id = NEW.post_id 
        AND user_id != NEW.user_id 
        AND user_id != v_post.user_id
    LOOP
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            v_interactor_id,
            'town_hall_comment',
            'New Comment',
            v_commenter_name || ' also commented on a post you interacted with',
            jsonb_build_object('town_hall_post_id', NEW.post_id::text)
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_town_hall_comment_notify ON town_hall_comments;
CREATE TRIGGER on_town_hall_comment_notify
AFTER INSERT ON town_hall_comments
FOR EACH ROW
EXECUTE FUNCTION notify_town_hall_comment();

-- ============================================================================
-- TRIGGER 8: Town Hall Vote - Notify poster + all who interacted
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_town_hall_vote()
RETURNS TRIGGER AS $$
DECLARE
    v_voter_name TEXT;
    v_post RECORD;
    v_vote_type TEXT;
    v_interactor_id UUID;
BEGIN
    -- Get voter name
    SELECT name INTO v_voter_name FROM profiles WHERE id = NEW.user_id;
    v_voter_name := COALESCE(v_voter_name, 'Someone');
    
    -- Get post info
    SELECT * INTO v_post FROM town_hall_posts WHERE id = NEW.post_id;
    
    -- Determine vote type
    v_vote_type := CASE WHEN NEW.vote_type = 'upvote' THEN 'upvote' ELSE 'downvote' END;
    
    -- Record this interaction
    INSERT INTO town_hall_post_interactions (post_id, user_id, interaction_type)
    VALUES (NEW.post_id, NEW.user_id, v_vote_type)
    ON CONFLICT (post_id, user_id, interaction_type) DO NOTHING;
    
    -- Only notify for upvotes (downvotes are silent)
    IF NEW.vote_type = 'upvote' THEN
        -- Notify the post author (if not the voter)
        IF v_post.user_id != NEW.user_id THEN
            PERFORM create_notification(
                v_post.user_id,
                'town_hall_reaction',
                'Post Upvoted',
                v_voter_name || ' upvoted your post',
                NULL,
                NULL,
                NULL,
                NULL,
                NEW.post_id,
                NEW.user_id
            );
            
            -- Don't send push for every upvote (too noisy) - just in-app
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_town_hall_vote_notify ON town_hall_votes;
CREATE TRIGGER on_town_hall_vote_notify
AFTER INSERT ON town_hall_votes
FOR EACH ROW
EXECUTE FUNCTION notify_town_hall_vote();

-- ============================================================================
-- TRIGGER 9: New Pending User - Notify all admins
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_pending_user()
RETURNS TRIGGER AS $$
DECLARE
    v_admin_id UUID;
    v_user_name TEXT;
BEGIN
    -- Only trigger for new unapproved users
    IF NEW.approved = true THEN
        RETURN NEW;
    END IF;
    
    v_user_name := COALESCE(NEW.name, NEW.email);
    
    -- Notify all admins
    FOR v_admin_id IN 
        SELECT id FROM profiles WHERE is_admin = true AND approved = true
    LOOP
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            v_admin_id,
            'pending_approval',
            'New User Pending Approval',
            v_user_name || ' is waiting for approval',
            jsonb_build_object('user_id', NEW.id::text)
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_pending_user_notify ON profiles;
CREATE TRIGGER on_pending_user_notify
AFTER INSERT ON profiles
FOR EACH ROW
EXECUTE FUNCTION notify_pending_user();

-- ============================================================================
-- TRIGGER 10: User Approved - Notify the user
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_user_approved()
RETURNS TRIGGER AS $$
BEGIN
    -- Only trigger when approved changes from false to true
    IF OLD.approved = false AND NEW.approved = true THEN
        PERFORM create_notification(
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
        
        PERFORM queue_push_notification(
            NEW.id,
            'user_approved',
            'Welcome to Naar''s Cars!',
            'Your account has been approved. Tap to enter the app.',
            jsonb_build_object('action', 'enter_app')
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_user_approved_notify ON profiles;
CREATE TRIGGER on_user_approved_notify
AFTER UPDATE ON profiles
FOR EACH ROW
EXECUTE FUNCTION notify_user_approved();

-- ============================================================================
-- TRIGGER 11: Added to Conversation - Notify the added user
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_added_to_conversation()
RETURNS TRIGGER AS $$
DECLARE
    v_conversation RECORD;
    v_adder_name TEXT;
BEGIN
    -- Get conversation info
    SELECT * INTO v_conversation FROM conversations WHERE id = NEW.conversation_id;
    
    -- Get the name of who created the conversation (adder)
    SELECT name INTO v_adder_name FROM profiles WHERE id = v_conversation.created_by;
    v_adder_name := COALESCE(v_adder_name, 'Someone');
    
    -- Don't notify the creator about being added to their own conversation
    IF NEW.user_id = v_conversation.created_by THEN
        RETURN NEW;
    END IF;
    
    PERFORM create_notification(
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
    
    PERFORM queue_push_notification(
        NEW.user_id,
        'added_to_conversation',
        'Added to Conversation',
        v_adder_name || ' added you to a conversation',
        jsonb_build_object('conversation_id', NEW.conversation_id::text)
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_added_to_conversation_notify ON conversation_participants;
CREATE TRIGGER on_added_to_conversation_notify
AFTER INSERT ON conversation_participants
FOR EACH ROW
EXECUTE FUNCTION notify_added_to_conversation();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION notify_new_ride IS 'Notifies ALL users when a new ride is created (mandatory notification)';
COMMENT ON FUNCTION notify_new_favor IS 'Notifies ALL users when a new favor is created (mandatory notification)';
COMMENT ON FUNCTION notify_ride_status_change IS 'Notifies requestor and co-requestors when ride is claimed/unclaimed/completed';
COMMENT ON FUNCTION notify_favor_status_change IS 'Notifies requestor and co-requestors when favor is claimed/unclaimed/completed';
COMMENT ON FUNCTION notify_qa_activity IS 'Notifies requestor and co-requestors of Q&A activity (only if not claimed)';
COMMENT ON FUNCTION notify_town_hall_post IS 'Queues batched notifications for new Town Hall posts';
COMMENT ON FUNCTION notify_town_hall_comment IS 'Notifies post author and interactors of new comments';
COMMENT ON FUNCTION notify_town_hall_vote IS 'Records interaction and notifies author of upvotes';
COMMENT ON FUNCTION notify_pending_user IS 'Notifies all admins when a new user is pending approval';
COMMENT ON FUNCTION notify_user_approved IS 'Notifies user when their account is approved';
COMMENT ON FUNCTION notify_added_to_conversation IS 'Notifies user when added to a conversation';

