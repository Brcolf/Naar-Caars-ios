-- 20261005_0019_notification_rpc_hardening.sql
--
-- APPLIED 2026-10-05 (Supabase MCP, three calls) and verified with a rolled-back probe.
--
-- 1. notify_creator_of_claim(uuid, uuid, text, text, jsonb) pushed caller-chosen title, body and
--    data (send-notification spreads `data` over the payload, so the aps dictionary and `type`
--    were attacker-controlled) to the poster of any request the caller had claimed, and any
--    signed-in user can claim an open request. Nothing calls it (no Swift, SQL, cron or edge
--    function reference; claim pushes come from the status-change triggers). Client roles lose
--    EXECUTE.
-- 2. should_notify_user(uuid, text) answered for any user id, revealing who is an admin
--    (`pending_approval`) and each user's notify_* preferences. Its callers are SECURITY DEFINER
--    (create_notification, queue_push_notification, send_push_notification_direct). Client roles
--    lose EXECUTE. notify_message_push() is the one invoker-rights caller; it is attached to no
--    trigger. Make it SECURITY DEFINER before ever re-attaching it.
-- 3. is_user_blocked(uuid, uuid) answered for any pair of users. It now requires the caller to
--    be one of the two (the Swift wrapper has no call sites).
-- 4. notify_claimer_of_request_update(uuid, uuid, text, text) inserted caller-chosen title and
--    body into the claimer's notification list without limit and regardless of blocks. The text
--    is now built server-side (the two text parameters are kept for signature compatibility and
--    ignored), a claimer who blocked the creator receives nothing, and there is at most one
--    unread update notice per request.
--
-- Probe (begin/rollback, as a request creator): notify returns an id, a second call returns the
-- same id, the stored title is the server text; is_user_blocked answers for the caller's own
-- pair and raises for a foreign pair; should_notify_user and notify_creator_of_claim are
-- permission-denied; a message insert still succeeds.

revoke all on function public.notify_creator_of_claim(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.should_notify_user(uuid, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_user_blocked(p_user_id uuid, p_other_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    -- Only answer for a pair the caller is part of; it used to reveal any two users' block state.
    IF auth.uid() IS NULL
       OR (auth.uid() IS DISTINCT FROM p_user_id AND auth.uid() IS DISTINCT FROM p_other_user_id) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.blocked_users
        WHERE (blocker_id = p_user_id AND blocked_id = p_other_user_id)
           OR (blocker_id = p_other_user_id AND blocked_id = p_user_id)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_claimer_of_request_update(p_ride_id uuid, p_favor_id uuid, p_title text, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_creator_id      uuid;
    v_claimer_id      uuid;
    v_type            text;
    v_title           text;
    v_body            text;
    v_notification_id uuid;
BEGIN
    -- p_title / p_body are ignored: the text is built here so a poster cannot put arbitrary
    -- wording (for example a fake admin notice) into the claimer's notification list.
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
        v_type  := 'ride_update';
        v_title := 'Ride Details Updated';
        v_body  := 'The ride you claimed has been updated. Check the details.';
    ELSE
        SELECT user_id, claimed_by INTO v_creator_id, v_claimer_id
        FROM public.favors
        WHERE id = p_favor_id;
        v_type  := 'favor_update';
        v_title := 'Favor Details Updated';
        v_body  := 'The favor you claimed has been updated. Check the details.';
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

    -- Respect blocks: a claimer who blocked the creator receives nothing.
    IF EXISTS (
        SELECT 1 FROM public.blocked_users b
        WHERE b.blocker_id = v_claimer_id
          AND b.blocked_id = v_creator_id
    ) THEN
        RETURN NULL;
    END IF;

    -- Dedupe: at most one unread update notice per request.
    SELECT n.id INTO v_notification_id
    FROM public.notifications n
    WHERE n.user_id = v_claimer_id
      AND n.type = v_type
      AND n.read = false
      AND n.source_user_id = v_creator_id
      AND n.ride_id  IS NOT DISTINCT FROM p_ride_id
      AND n.favor_id IS NOT DISTINCT FROM p_favor_id
    LIMIT 1;

    IF v_notification_id IS NOT NULL THEN
        RETURN v_notification_id;
    END IF;

    RETURN public.create_notification(
        v_claimer_id, v_type, v_title, v_body,
        p_ride_id, p_favor_id, NULL, NULL, NULL, v_creator_id
    );
END;
$function$;
