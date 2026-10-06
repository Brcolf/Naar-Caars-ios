-- Security fix: Lock down base notification RPCs behind service_role only.
-- Audit ref: CRIT-5 (final closure).
--
-- Vulnerability: create_notification, queue_push_notification, and
-- send_push_notification_direct accept arbitrary recipient IDs and were
-- granted to authenticated. Any authenticated user could forge in-app
-- notifications and push notifications to any user.
--
-- Live DB reality: 8 of the trigger/function callers are NOT SECURITY
-- DEFINER and so run with the invoker's privileges. A naive revoke of
-- `authenticated` from the base RPCs would break ride creation, favor
-- creation, Q&A, town hall posting, adding to conversations, and
-- completion reminder responses because those flows rely on invoker
-- privileges to call the base RPCs.
--
-- Fix design:
--   A. Convert the 8 invoker-privilege callers to SECURITY DEFINER so
--      their internal calls to the base RPCs run as postgres and bypass
--      grant restrictions. None of the 7 trigger functions use auth.uid()
--      (they read NEW.user_id etc.) so SECURITY DEFINER is semantically
--      a no-op for their authorization logic. handle_completion_response
--      already validates auth.uid() = claimer_user_id explicitly (Batch 3),
--      so SECURITY DEFINER is safe.
--   B. Add two purpose-specific SECURITY DEFINER wrapper RPCs for the
--      three Swift direct call sites (ClaimService, RideService,
--      FavorService). Each wrapper validates the caller's relationship
--      to the referenced ride/favor before invoking the base RPC.
--   C. Revoke EXECUTE from authenticated on the three base RPCs.
--      Only service_role remains (and SECURITY DEFINER functions owned
--      by postgres, which bypass grants).

-- -----------------------------------------------------------------------
-- Step A: Convert invoker-privilege callers to SECURITY DEFINER
-- -----------------------------------------------------------------------

ALTER FUNCTION public.notify_added_to_conversation() SECURITY DEFINER;
ALTER FUNCTION public.notify_new_favor() SECURITY DEFINER;
ALTER FUNCTION public.notify_new_ride() SECURITY DEFINER;
ALTER FUNCTION public.notify_qa_activity() SECURITY DEFINER;
ALTER FUNCTION public.notify_qa_answer() SECURITY DEFINER;
ALTER FUNCTION public.notify_town_hall_comment() SECURITY DEFINER;
ALTER FUNCTION public.notify_town_hall_post() SECURITY DEFINER;
ALTER FUNCTION public.handle_completion_response(uuid, boolean) SECURITY DEFINER;

-- -----------------------------------------------------------------------
-- Step B: Purpose-specific wrapper RPCs for Swift direct callers
-- -----------------------------------------------------------------------

-- Wrapper 1: Creator notifies claimer that request details changed.
-- Replaces direct create_notification calls in RideService and FavorService
-- after a ride or favor UPDATE that changes key fields.
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

    -- Exactly one of ride_id or favor_id must be provided
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

    -- If the request is no longer claimed, there is nobody to notify.
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

-- Wrapper 2: Claimer notifies creator that the request has been claimed.
-- Replaces direct queue_push_notification call in ClaimService.
-- Calendar event data is passed through via p_data.
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

-- Wrapper grants: authenticated users call these; PUBLIC/anon get nothing.
REVOKE ALL ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_claimer_of_request_update(uuid, uuid, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) TO service_role;

-- -----------------------------------------------------------------------
-- Step C: Revoke authenticated EXECUTE from the three base RPCs.
-- SECURITY DEFINER callers owned by postgres bypass grants, so they keep
-- working. Direct REST rpc calls from authenticated clients now fail.
-- -----------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, text, uuid, uuid, uuid, uuid, uuid, uuid, boolean) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.queue_push_notification(uuid, text, text, text, jsonb, text, uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.send_push_notification_direct(uuid, text, text, text, jsonb) FROM authenticated;
