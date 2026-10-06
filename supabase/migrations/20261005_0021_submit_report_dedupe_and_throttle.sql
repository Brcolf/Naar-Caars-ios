-- 20261005_0021_submit_report_dedupe_and_throttle.sql
--
-- APPLIED 2026-10-05 (Supabase MCP, two calls) and verified with a rolled-back probe.
--
-- submit_report() had duplicate checks only for post, comment, ride and favor reports. A
-- user-only or message report could be repeated without limit, and each row makes
-- handle_new_report notify and push every admin. It also accepted a message id from a
-- conversation the reporter was never in. The same abuse was possible by inserting into
-- public.reports directly (INSERT policy: reporter_id = auth.uid()).
--
-- Changes (signature, defaults and return contract unchanged; NULL still means "duplicate" and the
-- client treats it as success):
--   * a message can be reported only by a current or former member of its conversation (or its
--     creator);
--   * message and user-only reports: one PENDING report per reporter per target (a new one is
--     accepted after an admin resolves the previous one);
--   * 20 reports per reporter per hour (the client already rate-limits to one per 10 s);
--   * description capped at 2000 characters; tables schema-qualified, search_path emptied;
--   * client roles can no longer INSERT into public.reports directly. authenticated keeps UPDATE
--     because the "Admins can update reports" policy depends on it. The "Users can create
--     reports" INSERT policy is left in place (inert without the grant).
--
-- Probe (begin/rollback, as a signed-in member): user, message, post, comment, ride and favor
-- reports each return an id and their immediate repeat returns NULL (6 rows inserted in total); a
-- message from a foreign conversation raises "Message not found"; a spoofed reporter id raises.
--
-- See 20261005_0022 for the related reporter-privacy policy drop, which needs the SQL editor.

CREATE OR REPLACE FUNCTION public.submit_report(p_reporter_id uuid, p_reported_user_id uuid DEFAULT NULL::uuid, p_reported_message_id uuid DEFAULT NULL::uuid, p_reported_post_id uuid DEFAULT NULL::uuid, p_reported_comment_id uuid DEFAULT NULL::uuid, p_reported_ride_id uuid DEFAULT NULL::uuid, p_reported_favor_id uuid DEFAULT NULL::uuid, p_report_type text DEFAULT 'other'::text, p_description text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_report_id uuid;
BEGIN
    -- Target validation
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL
       AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL
       AND p_reported_ride_id IS NULL AND p_reported_favor_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, comment, ride, or favor';
    END IF;

    -- SECURITY: the caller is the reporter (prevents spoofing)
    IF v_uid IS NULL OR v_uid <> p_reporter_id THEN
        RAISE EXCEPTION 'Reporter ID must match authenticated user';
    END IF;

    -- Serialize per reporter so the duplicate and throttle checks cannot be raced.
    PERFORM pg_advisory_xact_lock(hashtextextended('submit_report:' || v_uid::text, 0));

    -- A message can only be reported by someone who is or was in its conversation (or created it).
    IF p_reported_message_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.messages m
        WHERE m.id = p_reported_message_id
          AND (
              EXISTS (SELECT 1 FROM public.conversation_participants cp
                      WHERE cp.conversation_id = m.conversation_id AND cp.user_id = v_uid)
              OR EXISTS (SELECT 1 FROM public.conversations c
                         WHERE c.id = m.conversation_id AND c.created_by = v_uid)
          )
    ) THEN
        RAISE EXCEPTION 'Message not found';
    END IF;

    -- Duplicates return NULL (unchanged contract; the client treats it as success).
    --   post / comment / ride / favor: once per reporter per target (unchanged rule)
    --   message, user-only: one PENDING report per reporter per target, so a new report is
    --   accepted again after an admin has resolved the previous one
    IF EXISTS (
        SELECT 1 FROM public.reports r
        WHERE r.reporter_id = v_uid
          AND (   (p_reported_post_id    IS NOT NULL AND r.reported_post_id    = p_reported_post_id)
               OR (p_reported_comment_id IS NOT NULL AND r.reported_comment_id = p_reported_comment_id)
               OR (p_reported_ride_id    IS NOT NULL AND r.reported_ride_id    = p_reported_ride_id)
               OR (p_reported_favor_id   IS NOT NULL AND r.reported_favor_id   = p_reported_favor_id)
               OR (p_reported_message_id IS NOT NULL AND r.reported_message_id = p_reported_message_id
                   AND r.status = 'pending')
               OR (p_reported_user_id IS NOT NULL
                   AND p_reported_message_id IS NULL AND p_reported_post_id IS NULL
                   AND p_reported_comment_id IS NULL AND p_reported_ride_id IS NULL AND p_reported_favor_id IS NULL
                   AND r.reported_user_id = p_reported_user_id
                   AND r.reported_message_id IS NULL AND r.reported_post_id IS NULL
                   AND r.reported_comment_id IS NULL AND r.reported_ride_id IS NULL AND r.reported_favor_id IS NULL
                   AND r.status = 'pending'))
    ) THEN
        RETURN NULL;
    END IF;

    -- Throttle: bounds the per-admin notification/push fan-out in handle_new_report.
    -- The iOS client already limits itself to one report per 10 seconds.
    IF (SELECT count(*) FROM public.reports r
        WHERE r.reporter_id = v_uid
          AND r.created_at > now() - interval '1 hour') >= 20 THEN
        RAISE EXCEPTION 'Too many reports, try again later';
    END IF;

    INSERT INTO public.reports (
        reporter_id, reported_user_id, reported_message_id,
        reported_post_id, reported_comment_id,
        reported_ride_id, reported_favor_id,
        report_type, description
    ) VALUES (
        v_uid, p_reported_user_id, p_reported_message_id,
        p_reported_post_id, p_reported_comment_id,
        p_reported_ride_id, p_reported_favor_id,
        p_report_type, left(p_description, 2000)
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$function$;

revoke insert, update, delete, truncate, references, trigger on public.reports from anon;
revoke insert, delete, truncate, references, trigger on public.reports from authenticated;
