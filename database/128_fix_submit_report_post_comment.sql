-- Fix: Update submit_report RPC to accept post/comment IDs
-- The live DB already has this version, but it was never captured in a migration.
-- Changes from original: adds p_reported_post_id and p_reported_comment_id params,
-- duplicate-prevention for posts/comments, SET search_path = public.
-- SECURITY FIX: validates auth.uid() matches p_reporter_id, uses auth.uid() for
-- all internal operations to prevent reporter spoofing.

CREATE OR REPLACE FUNCTION public.submit_report(
    p_reporter_id uuid,
    p_reported_user_id uuid DEFAULT NULL::uuid,
    p_reported_message_id uuid DEFAULT NULL::uuid,
    p_reported_post_id uuid DEFAULT NULL::uuid,
    p_reported_comment_id uuid DEFAULT NULL::uuid,
    p_report_type text DEFAULT 'other'::text,
    p_description text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_report_id UUID;
BEGIN
    -- Target validation
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL
       AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, or comment';
    END IF;

    -- SECURITY: Verify the caller is the reporter (prevent spoofing)
    IF auth.uid() IS NULL OR auth.uid() != p_reporter_id THEN
        RAISE EXCEPTION 'Reporter ID must match authenticated user';
    END IF;

    -- Prevent duplicate reports (use auth.uid() not p_reporter_id)
    IF p_reported_post_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_post_id = p_reported_post_id) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF p_reported_comment_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_comment_id = p_reported_comment_id) THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Insert using auth.uid() as the trusted reporter identity
    INSERT INTO reports (
        reporter_id, reported_user_id, reported_message_id,
        reported_post_id, reported_comment_id,
        report_type, description
    ) VALUES (
        auth.uid(), p_reported_user_id, p_reported_message_id,
        p_reported_post_id, p_reported_comment_id,
        p_report_type, p_description
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$function$;
