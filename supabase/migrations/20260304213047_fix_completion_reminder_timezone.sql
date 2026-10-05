-- 20260304213047_fix_completion_reminder_timezone.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix completion reminder timezone calculation in ride and favor status change triggers.
-- The triggers were calculating scheduled_for using (date + time)::timestamptz which
-- interprets in server timezone (UTC) instead of the ride/favor's timezone column.
-- This caused reminders to fire hours early for non-UTC timezones.

-- First, delete any pending (non-completed) completion reminders so they get
-- regenerated correctly on next claim action.
DELETE FROM public.completion_reminders WHERE completed = false;

-- Replace notify_ride_status_change with timezone-aware version
CREATE OR REPLACE FUNCTION public.notify_ride_status_change()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
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

    -- Convert local date+time to proper timestamptz using the ride's timezone
    v_scheduled_datetime := (NEW.date::date + NEW.time::time) AT TIME ZONE COALESCE(NEW.timezone, 'America/Los_Angeles');

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

-- Replace notify_favor_status_change with timezone-aware version
CREATE OR REPLACE FUNCTION public.notify_favor_status_change()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
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

    -- Convert local date+time to proper timestamptz using the favor's timezone
    v_scheduled_datetime := (NEW.date::date + COALESCE(NEW.time::time, '12:00:00'::time)) AT TIME ZONE COALESCE(NEW.timezone, 'America/Los_Angeles');

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
