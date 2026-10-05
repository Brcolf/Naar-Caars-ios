-- 20260206190200_fix_unqualified_table_references.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix 16 database functions that have search_path="" but use unqualified table names.
-- The migration fix_function_search_paths set search_path="" for security,
-- but these functions still reference tables without "public." prefix.
-- PostgreSQL cannot resolve them, breaking messaging, leaderboard, and notifications.

-- 1. is_conversation_participant - used in RLS for conversation_participants, messages, typing_indicators, message_reactions
CREATE OR REPLACE FUNCTION public.is_conversation_participant(conv_id uuid, check_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_participants
    WHERE conversation_id = conv_id
    AND user_id = check_user_id
  );
$$;

-- 2. get_leaderboard(start_date, end_date) - the date-based version
CREATE OR REPLACE FUNCTION public.get_leaderboard(start_date date DEFAULT '1970-01-01'::date, end_date date DEFAULT CURRENT_DATE)
RETURNS TABLE(user_id uuid, name text, avatar_url text, requests_fulfilled bigint, requests_made bigint)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.name,
        p.avatar_url,
        (
            SELECT COUNT(*) FROM public.rides r
            WHERE r.claimed_by = p.id
            AND r.status = 'completed'
            AND DATE(r.updated_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM public.favors f
            WHERE f.claimed_by = p.id
            AND f.status = 'completed'
            AND DATE(f.updated_at) BETWEEN start_date AND end_date
        ) as requests_fulfilled,
        (
            SELECT COUNT(*) FROM public.rides r
            WHERE r.user_id = p.id
            AND DATE(r.created_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM public.favors f
            WHERE f.user_id = p.id
            AND DATE(f.created_at) BETWEEN start_date AND end_date
        ) as requests_made
    FROM public.profiles p
    WHERE p.approved = true
    ORDER BY requests_fulfilled DESC
    LIMIT 100;
END;
$$;

-- 3. get_unread_message_count
CREATE OR REPLACE FUNCTION public.get_unread_message_count(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(m.id) INTO v_count
    FROM public.messages m
    JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
    WHERE cp.user_id = p_user_id
      AND cp.left_at IS NULL
      AND m.from_id != p_user_id
      AND (m.read_by IS NULL OR NOT (m.read_by @> ARRAY[p_user_id]::UUID[]));

    RETURN COALESCE(v_count, 0);
END;
$$;

-- 4. handle_completion_response
CREATE OR REPLACE FUNCTION public.handle_completion_response(p_reminder_id uuid, p_completed boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_requestor_id UUID;
    v_notification_id UUID;
BEGIN
    SELECT * INTO v_reminder FROM public.completion_reminders WHERE id = p_reminder_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Reminder not found');
    END IF;

    IF p_completed THEN
        IF v_reminder.ride_id IS NOT NULL THEN
            UPDATE public.rides SET status = 'completed' WHERE id = v_reminder.ride_id;
            SELECT user_id, destination INTO v_requestor_id, v_request_title
            FROM public.rides WHERE id = v_reminder.ride_id;
        ELSE
            UPDATE public.favors SET status = 'completed' WHERE id = v_reminder.favor_id;
            SELECT user_id, title INTO v_requestor_id, v_request_title
            FROM public.favors WHERE id = v_reminder.favor_id;
        END IF;

        UPDATE public.completion_reminders SET completed = true WHERE id = p_reminder_id;

        v_notification_id := public.create_notification(
            v_requestor_id, 'review_request', 'How was your experience?',
            'Your request has been completed. Leave a review to thank your helper!',
            v_reminder.ride_id, v_reminder.favor_id, NULL, NULL, NULL, v_reminder.claimer_user_id
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_requestor_id, 'review_request', 'How was your experience?',
                'Your request has been completed. Leave a review!',
                jsonb_build_object('ride_id', v_reminder.ride_id::text, 'favor_id', v_reminder.favor_id::text, 'action', 'review'),
                NULL, v_notification_id
            );
        END IF;

        RETURN jsonb_build_object('success', true, 'action', 'completed');
    ELSE
        UPDATE public.completion_reminders
        SET scheduled_for = NOW() + INTERVAL '1 hour',
            reminder_count = reminder_count + 1,
            last_reminded_at = NOW()
        WHERE id = p_reminder_id;

        RETURN jsonb_build_object('success', true, 'action', 'snoozed', 'next_reminder', NOW() + INTERVAL '1 hour');
    END IF;
END;
$$;

-- 5. notify_added_to_conversation
CREATE OR REPLACE FUNCTION public.notify_added_to_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_conversation RECORD;
    v_adder_name TEXT;
    v_notification_id UUID;
BEGIN
    SELECT * INTO v_conversation FROM public.conversations WHERE id = NEW.conversation_id;
    SELECT name INTO v_adder_name FROM public.profiles WHERE id = v_conversation.created_by;
    v_adder_name := COALESCE(v_adder_name, 'Someone');

    IF NEW.user_id = v_conversation.created_by THEN
        RETURN NEW;
    END IF;

    v_notification_id := public.create_notification(
        NEW.user_id, 'added_to_conversation', 'Added to Conversation',
        v_adder_name || ' added you to a conversation',
        NULL, NULL, NEW.conversation_id, NULL, NULL, v_conversation.created_by
    );

    IF v_notification_id IS NOT NULL THEN
        PERFORM public.queue_push_notification(
            NEW.user_id, 'added_to_conversation', 'Added to Conversation',
            v_adder_name || ' added you to a conversation',
            jsonb_build_object('conversation_id', NEW.conversation_id::text),
            NULL, v_notification_id
        );
    END IF;

    RETURN NEW;
END;
$$;

-- 6. notify_favor_status_change
CREATE OR REPLACE FUNCTION public.notify_favor_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
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

    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM public.profiles WHERE id = NEW.claimed_by;
    END IF;

    v_scheduled_datetime := (NEW.date::date + COALESCE(NEW.time::time, '12:00:00'::time))::timestamptz;

    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        v_notification_type := 'favor_claimed';
        v_title := 'Someone Can Help!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your favor';
        INSERT INTO public.completion_reminders (favor_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, v_scheduled_datetime + INTERVAL '1 hour')
        ON CONFLICT DO NOTHING;
    ELSIF OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS NULL THEN
        v_notification_type := 'favor_unclaimed';
        v_title := 'Favor Unclaimed';
        v_body := COALESCE(v_claimer_name, 'The helper') || ' is no longer available for your favor';
        DELETE FROM public.completion_reminders WHERE favor_id = NEW.id;
    ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        v_notification_type := 'favor_completed';
        v_title := 'Favor Completed';
        v_body := 'Your favor has been marked as completed';
        UPDATE public.completion_reminders SET completed = true WHERE favor_id = NEW.id;
    ELSE
        v_notification_type := 'favor_update';
        v_title := 'Favor Updated';
        v_body := 'Your favor request has been updated';
    END IF;

    IF NEW.user_id != COALESCE(NEW.claimed_by, NEW.user_id) OR v_notification_type = 'favor_unclaimed' THEN
        v_notification_id := public.create_notification(
            NEW.user_id, v_notification_type, v_title, v_body,
            NULL, NEW.id, NULL, NULL, NULL, NEW.claimed_by
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                NEW.user_id, v_notification_type, v_title, v_body,
                jsonb_build_object('favor_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END IF;

    FOR v_co_requestor_id IN
        SELECT user_id FROM public.favor_participants WHERE favor_id = NEW.id AND user_id != NEW.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_co_requestor_id, v_notification_type, v_title, v_body,
            NULL, NEW.id, NULL, NULL, NULL, NEW.claimed_by
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_co_requestor_id, v_notification_type, v_title, v_body,
                jsonb_build_object('favor_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 7. notify_message_push
CREATE OR REPLACE FUNCTION public.notify_message_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    recipient_user_id UUID;
    conversation_id_val UUID;
    sender_name TEXT;
    message_preview TEXT;
    recipient_record RECORD;
BEGIN
    conversation_id_val := NEW.conversation_id;

    SELECT name INTO sender_name FROM public.profiles WHERE id = NEW.from_id;
    IF sender_name IS NULL THEN
        sender_name := 'Someone';
    END IF;

    message_preview := LEFT(NEW.text, 50);
    IF LENGTH(NEW.text) > 50 THEN
        message_preview := message_preview || '...';
    END IF;

    FOR recipient_record IN
        SELECT cp.user_id, cp.last_seen
        FROM public.conversation_participants cp
        WHERE cp.conversation_id = conversation_id_val
        AND cp.user_id != NEW.from_id
    LOOP
        recipient_user_id := recipient_record.user_id;

        IF recipient_record.last_seen IS NOT NULL THEN
            IF EXTRACT(EPOCH FROM (NOW() - recipient_record.last_seen)) < 60 THEN
                CONTINUE;
            END IF;
        END IF;

        IF NOT public.should_notify_user(recipient_user_id, 'message') THEN
            CONTINUE;
        END IF;

        PERFORM public.send_push_notification_direct(
            recipient_user_id, 'message', 'Message from ' || sender_name, message_preview,
            jsonb_build_object('conversation_id', conversation_id_val::text, 'message_id', NEW.id::text, 'sender_id', NEW.from_id::text)
        );
    END LOOP;

    RETURN NEW;
END;
$$;

-- 8. notify_new_favor
CREATE OR REPLACE FUNCTION public.notify_new_favor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    FOR v_user_record IN
        SELECT id FROM public.profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_favor', 'New Favor Request',
            v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
            NULL, NEW.id, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_favor', 'New Favor Request',
                v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
                jsonb_build_object('favor_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 9. notify_new_ride
CREATE OR REPLACE FUNCTION public.notify_new_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_poster_name TEXT;
    v_destination TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    v_destination := COALESCE(NEW.destination, 'a destination');

    FOR v_user_record IN
        SELECT id FROM public.profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_ride', 'New Ride Request',
            v_poster_name || ' needs a ride to ' || v_destination,
            NEW.id, NULL, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_ride', 'New Ride Request',
                v_poster_name || ' needs a ride to ' || v_destination,
                jsonb_build_object('ride_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 10. notify_pending_user
CREATE OR REPLACE FUNCTION public.notify_pending_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_admin_id UUID;
    v_user_name TEXT;
    v_notification_id UUID;
BEGIN
    IF NEW.approved = true THEN
        RETURN NEW;
    END IF;

    v_user_name := COALESCE(NEW.name, NEW.email);

    FOR v_admin_id IN
        SELECT id FROM public.profiles WHERE is_admin = true AND approved = true
    LOOP
        v_notification_id := public.create_notification(
            v_admin_id, 'pending_approval', 'New User Pending Approval',
            v_user_name || ' is waiting for approval',
            NULL, NULL, NULL, NULL, NULL, NEW.id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_admin_id, 'pending_approval', 'New User Pending Approval',
                v_user_name || ' is waiting for approval',
                jsonb_build_object('user_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 11. notify_qa_activity
CREATE OR REPLACE FUNCTION public.notify_qa_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
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
    SELECT name INTO v_questioner_name FROM public.profiles WHERE id = NEW.user_id;
    v_questioner_name := COALESCE(v_questioner_name, 'Someone');

    IF NEW.ride_id IS NOT NULL THEN
        SELECT * INTO v_ride FROM public.rides WHERE id = NEW.ride_id;
        v_poster_id := v_ride.user_id;
        v_is_claimed := v_ride.claimed_by IS NOT NULL;
        v_request_type := 'ride';
        v_request_id := NEW.ride_id;
    ELSIF NEW.favor_id IS NOT NULL THEN
        SELECT * INTO v_favor FROM public.favors WHERE id = NEW.favor_id;
        v_poster_id := v_favor.user_id;
        v_is_claimed := v_favor.claimed_by IS NOT NULL;
        v_request_type := 'favor';
        v_request_id := NEW.favor_id;
    ELSE
        RETURN NEW;
    END IF;

    IF v_is_claimed THEN
        RETURN NEW;
    END IF;

    FOR v_recipient_id IN
        SELECT DISTINCT user_id FROM (
            SELECT v_poster_id AS user_id
            UNION
            SELECT user_id FROM public.request_qa
            WHERE (v_request_type = 'ride' AND ride_id = v_request_id)
               OR (v_request_type = 'favor' AND favor_id = v_request_id)
            UNION
            SELECT user_id FROM public.ride_participants
            WHERE v_request_type = 'ride' AND ride_id = v_request_id
            UNION
            SELECT user_id FROM public.favor_participants
            WHERE v_request_type = 'favor' AND favor_id = v_request_id
        ) recipients
        WHERE user_id IS NOT NULL AND user_id != NEW.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_recipient_id, 'qa_question', 'New Question',
            v_questioner_name || ' asked: "' || LEFT(NEW.question, 50) || '"',
            CASE WHEN v_request_type = 'ride' THEN v_request_id ELSE NULL END,
            CASE WHEN v_request_type = 'favor' THEN v_request_id ELSE NULL END,
            NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_recipient_id, 'qa_question', 'New Question',
                v_questioner_name || ' asked: "' || LEFT(NEW.question, 50) || '"',
                jsonb_build_object(
                    CASE WHEN v_request_type = 'ride' THEN 'ride_id' ELSE 'favor_id' END,
                    v_request_id::text
                ), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 12. notify_qa_answer
CREATE OR REPLACE FUNCTION public.notify_qa_answer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
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
    IF NEW.answer IS NULL OR NEW.answer = OLD.answer THEN
        RETURN NEW;
    END IF;

    IF NEW.ride_id IS NOT NULL THEN
        SELECT * INTO v_ride FROM public.rides WHERE id = NEW.ride_id;
        v_poster_id := v_ride.user_id;
        v_is_claimed := v_ride.claimed_by IS NOT NULL;
        v_request_type := 'ride';
        v_request_id := NEW.ride_id;
    ELSIF NEW.favor_id IS NOT NULL THEN
        SELECT * INTO v_favor FROM public.favors WHERE id = NEW.favor_id;
        v_poster_id := v_favor.user_id;
        v_is_claimed := v_favor.claimed_by IS NOT NULL;
        v_request_type := 'favor';
        v_request_id := NEW.favor_id;
    ELSE
        RETURN NEW;
    END IF;

    IF v_is_claimed THEN
        RETURN NEW;
    END IF;

    SELECT name INTO v_answerer_name FROM public.profiles WHERE id = v_poster_id;
    v_answerer_name := COALESCE(v_answerer_name, 'Someone');

    FOR v_recipient_id IN
        SELECT DISTINCT user_id FROM (
            SELECT v_poster_id AS user_id
            UNION
            SELECT user_id FROM public.request_qa
            WHERE (v_request_type = 'ride' AND ride_id = v_request_id)
               OR (v_request_type = 'favor' AND favor_id = v_request_id)
            UNION
            SELECT user_id FROM public.ride_participants
            WHERE v_request_type = 'ride' AND ride_id = v_request_id
            UNION
            SELECT user_id FROM public.favor_participants
            WHERE v_request_type = 'favor' AND favor_id = v_request_id
        ) recipients
        WHERE user_id IS NOT NULL AND user_id != v_poster_id
    LOOP
        v_notification_id := public.create_notification(
            v_recipient_id, 'qa_answer', 'Question Answered',
            v_answerer_name || ' answered a question',
            CASE WHEN v_request_type = 'ride' THEN v_request_id ELSE NULL END,
            CASE WHEN v_request_type = 'favor' THEN v_request_id ELSE NULL END,
            NULL, NULL, NULL, v_poster_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_recipient_id, 'qa_answer', 'Question Answered',
                v_answerer_name || ' answered a question',
                jsonb_build_object(
                    CASE WHEN v_request_type = 'ride' THEN 'ride_id' ELSE 'favor_id' END,
                    v_request_id::text
                ), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 13. notify_ride_status_change
CREATE OR REPLACE FUNCTION public.notify_ride_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
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

    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    IF NEW.claimed_by IS NOT NULL THEN
        SELECT name INTO v_claimer_name FROM public.profiles WHERE id = NEW.claimed_by;
    END IF;

    v_scheduled_datetime := (NEW.date::date + NEW.time::time)::timestamptz;

    IF OLD.claimed_by IS NULL AND NEW.claimed_by IS NOT NULL THEN
        v_notification_type := 'ride_claimed';
        v_title := 'Ride Claimed!';
        v_body := COALESCE(v_claimer_name, 'Someone') || ' is helping with your ride';
        INSERT INTO public.completion_reminders (ride_id, claimer_user_id, scheduled_for)
        VALUES (NEW.id, NEW.claimed_by, v_scheduled_datetime + INTERVAL '1 hour')
        ON CONFLICT DO NOTHING;
    ELSIF OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS NULL THEN
        v_notification_type := 'ride_unclaimed';
        v_title := 'Ride Unclaimed';
        v_body := COALESCE(v_claimer_name, 'The helper') || ' is no longer available for your ride';
        DELETE FROM public.completion_reminders WHERE ride_id = NEW.id;
    ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        v_notification_type := 'ride_completed';
        v_title := 'Ride Completed';
        v_body := 'Your ride has been marked as completed';
        UPDATE public.completion_reminders SET completed = true WHERE ride_id = NEW.id;
    ELSE
        v_notification_type := 'ride_update';
        v_title := 'Ride Updated';
        v_body := 'Your ride request has been updated';
    END IF;

    IF NEW.user_id != COALESCE(NEW.claimed_by, NEW.user_id) OR v_notification_type = 'ride_unclaimed' THEN
        v_notification_id := public.create_notification(
            NEW.user_id, v_notification_type, v_title, v_body,
            NEW.id, NULL, NULL, NULL, NULL, NEW.claimed_by
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                NEW.user_id, v_notification_type, v_title, v_body,
                jsonb_build_object('ride_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END IF;

    FOR v_co_requestor_id IN
        SELECT user_id FROM public.ride_participants WHERE ride_id = NEW.id AND user_id != NEW.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_co_requestor_id, v_notification_type, v_title, v_body,
            NEW.id, NULL, NULL, NULL, NULL, NEW.claimed_by
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_co_requestor_id, v_notification_type, v_title, v_body,
                jsonb_build_object('ride_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 14. notify_town_hall_comment
CREATE OR REPLACE FUNCTION public.notify_town_hall_comment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_commenter_name TEXT;
    v_post RECORD;
    v_interactor_id UUID;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_commenter_name FROM public.profiles WHERE id = NEW.user_id;
    v_commenter_name := COALESCE(v_commenter_name, 'Someone');

    SELECT * INTO v_post FROM public.town_hall_posts WHERE id = NEW.post_id;

    INSERT INTO public.town_hall_post_interactions (post_id, user_id, interaction_type)
    VALUES (NEW.post_id, NEW.user_id, 'comment')
    ON CONFLICT (post_id, user_id, interaction_type) DO NOTHING;

    IF v_post.user_id != NEW.user_id THEN
        v_notification_id := public.create_notification(
            v_post.user_id, 'town_hall_comment', 'New Comment',
            v_commenter_name || ' commented on your post',
            NULL, NULL, NULL, NULL, NEW.post_id, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_post.user_id, 'town_hall_comment', 'New Comment',
                v_commenter_name || ' commented on your post',
                jsonb_build_object('town_hall_post_id', NEW.post_id::text), NULL, v_notification_id
            );
        END IF;
    END IF;

    FOR v_interactor_id IN
        SELECT DISTINCT user_id FROM public.town_hall_post_interactions
        WHERE post_id = NEW.post_id
          AND user_id != NEW.user_id
          AND user_id != v_post.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_interactor_id, 'town_hall_comment', 'New Comment',
            v_commenter_name || ' also commented on a post you interacted with',
            NULL, NULL, NULL, NULL, NEW.post_id, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_interactor_id, 'town_hall_comment', 'New Comment',
                v_commenter_name || ' also commented on a post you interacted with',
                jsonb_build_object('town_hall_post_id', NEW.post_id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 15. notify_town_hall_post
CREATE OR REPLACE FUNCTION public.notify_town_hall_post()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_batch_key TEXT;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    v_batch_key := 'town_hall_' || to_char(date_trunc('minute', NOW()) -
        (EXTRACT(MINUTE FROM NOW())::int % 5) * INTERVAL '1 minute', 'YYYY-MM-DD-HH24-MI');

    FOR v_user_record IN
        SELECT id FROM public.profiles
        WHERE approved = true
          AND id != NEW.user_id
          AND notify_town_hall = true
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'town_hall_post', 'New in Town Hall',
            v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
            NULL, NULL, NULL, NULL, NEW.id, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'town_hall_post', 'New in Town Hall',
                v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
                jsonb_build_object('town_hall_post_id', NEW.id::text), v_batch_key, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- 16. process_completion_reminders
CREATE OR REPLACE FUNCTION public.process_completion_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_count INTEGER := 0;
    v_notification_id UUID;
BEGIN
    FOR v_reminder IN
        SELECT * FROM public.completion_reminders
        WHERE scheduled_for <= NOW()
          AND completed = false
          AND (last_reminded_at IS NULL OR last_reminded_at < NOW() - INTERVAL '30 minutes')
    LOOP
        IF v_reminder.ride_id IS NOT NULL THEN
            SELECT destination INTO v_request_title FROM public.rides WHERE id = v_reminder.ride_id;
            v_request_title := 'ride to ' || COALESCE(v_request_title, 'destination');
        ELSE
            SELECT title INTO v_request_title FROM public.favors WHERE id = v_reminder.favor_id;
            v_request_title := COALESCE(v_request_title, 'your favor');
        END IF;

        v_notification_id := public.create_notification(
            v_reminder.claimer_user_id, 'completion_reminder', 'Is This Complete?',
            'Did you complete the ' || v_request_title || '?',
            v_reminder.ride_id, v_reminder.favor_id, NULL, NULL, NULL, NULL
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_reminder.claimer_user_id, 'completion_reminder', 'Is This Complete?',
                'Did you complete the ' || v_request_title || '?',
                jsonb_build_object(
                    'reminder_id', v_reminder.id::text,
                    'ride_id', v_reminder.ride_id::text,
                    'favor_id', v_reminder.favor_id::text,
                    'actionable', true
                ), NULL, v_notification_id
            );
        END IF;

        UPDATE public.completion_reminders
        SET last_reminded_at = NOW()
        WHERE id = v_reminder.id;

        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$;
