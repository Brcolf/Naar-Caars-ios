-- 20260304162508_update_submit_report_for_town_hall.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

CREATE OR REPLACE FUNCTION public.submit_report(
    p_reporter_id uuid,
    p_reported_user_id uuid DEFAULT NULL::uuid,
    p_reported_message_id uuid DEFAULT NULL::uuid,
    p_report_type text DEFAULT 'other'::text,
    p_description text DEFAULT NULL::text,
    p_reported_post_id uuid DEFAULT NULL::uuid,
    p_reported_comment_id uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_report_id UUID;
BEGIN
    -- Validate input: must report at least one thing
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, or comment';
    END IF;

    INSERT INTO public.reports (
        reporter_id,
        reported_user_id,
        reported_message_id,
        reported_post_id,
        reported_comment_id,
        report_type,
        description
    ) VALUES (
        p_reporter_id,
        p_reported_user_id,
        p_reported_message_id,
        p_reported_post_id,
        p_reported_comment_id,
        p_report_type,
        p_description
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$function$;