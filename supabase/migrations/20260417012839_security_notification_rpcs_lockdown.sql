-- 20260417012839_security_notification_rpcs_lockdown.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Security fix: Lock down base notification RPCs behind service_role only.
-- Audit ref: CRIT-5 (final closure).

-- Step A: Convert invoker-privilege callers to SECURITY DEFINER
ALTER FUNCTION public.notify_added_to_conversation() SECURITY DEFINER;
ALTER FUNCTION public.notify_new_favor() SECURITY DEFINER;
ALTER FUNCTION public.notify_new_ride() SECURITY DEFINER;
ALTER FUNCTION public.notify_qa_activity() SECURITY DEFINER;
ALTER FUNCTION public.notify_qa_answer() SECURITY DEFINER;
ALTER FUNCTION public.notify_town_hall_comment() SECURITY DEFINER;
ALTER FUNCTION public.notify_town_hall_post() SECURITY DEFINER;
ALTER FUNCTION public.handle_completion_response(uuid, boolean) SECURITY DEFINER;

-- Step B: Purpose-specific wrapper RPCs for Swift direct callers
CREATE OR REPLACE FUNCTION public.notify_claimer_of_request_update(
    p_ride_id  uuid,
    p_favor_id uuid,
    p_title    text,
    p_body     text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_creator_id     uuid;
    v_claimer_id     uuid;
    v_type           text;
    v_notification_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF (p_ride_id IS NULL) = (p_favor_id IS NULL) THEN
        RAISE EXCEPTION 'Provide exactly one of p_ride_id or p_favor_id';
    END IF;

    IF p_ride_id IS NOT NULL THEN
        SELECT user_id, claimed_by INTO v_creator_id, v_claimer_id
        FROM public.rides
        WHERE id = p_ride_id;
        v_type := 'ride_update';
    ELSE
        SELECT user_id, claimed_by INTO v_creator_id, v_claimer_id
        FROM public.favors
        WHERE id = p_favor_id;
        v_type := 'favor_update';
    END IF;

    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Request not found';
    END IF;

    IF v_creator_id <> auth.uid() THEN
        RAISE EXCEPTION 'Only the request creator can notify the claimer';
    END IF;

    IF v_claimer_id IS NULL THEN
        RETURN NULL;
    END IF;

    v_notification_id := public.create_notification(
        v_claimer_id, v_type, p_title, p_body,
        p_ride_id, p_favor_id, NULL, NULL, NULL, v_creator_id
    );

    RETURN v_notification_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_creator_of_claim(
    p_ride_id  uuid,
    p_favor_id uuid,
    p_title    text,
    p_body     text,
    p_data     jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_creator_id uuid;
    v_claimer_id uuid;
    v_type       text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF (p_ride_id IS NULL) = (p_favor_id IS NULL) THEN
        RAISE EXCEPTION 'Provide exactly one of p_ride_id or p_favor_id';
    END IF;

    IF p_ride_id IS NOT NULL THEN
        SELECT user_id, claimed_by INTO v_creator_id, v_claimer_id
        FROM public.rides
        WHERE id = p_ride_id;
        v_type := 'ride_claimed';
    ELSE
        SELECT user_id, claimed_by INTO v_creator_id, v_claimer_id
        FROM public.favors
        WHERE id = p_favor_id;
        v_type := 'favor_claimed';
    END IF;

    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Request not found';
    END IF;

    IF v_claimer_id IS NULL OR v_claimer_id <> auth.uid() THEN
        RAISE EXCEPTION 'Only the current claimer can notify the creator';
    END IF;

    PERFORM public.queue_push_notification(
        v_creator_id, v_type, p_title, p_body, p_data, NULL, NULL
    );
END;
$$;

REVOKE ALL ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) TO service_role;

-- Step C: Revoke authenticated EXECUTE from the three base RPCs.
REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, text, uuid, uuid, uuid, uuid, uuid, uuid, boolean) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.queue_push_notification(uuid, text, text, text, jsonb, text, uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.send_push_notification_direct(uuid, text, text, text, jsonb) FROM authenticated;
