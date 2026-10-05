-- 20260313015232_fix_submit_report_post_comment.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

CREATE OR REPLACE FUNCTION public.submit_report(p_reporter_id uuid, p_reported_user_id uuid DEFAULT NULL::uuid, p_reported_message_id uuid DEFAULT NULL::uuid, p_reported_post_id uuid DEFAULT NULL::uuid, p_reported_comment_id uuid DEFAULT NULL::uuid, p_report_type text DEFAULT 'other'::text, p_description text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_report_id UUID;
BEGIN
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL
       AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, or comment';
    END IF;

    IF p_reported_post_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports WHERE reporter_id = p_reporter_id AND reported_post_id = p_reported_post_id) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF p_reported_comment_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports WHERE reporter_id = p_reporter_id AND reported_comment_id = p_reported_comment_id) THEN
            RETURN NULL;
        END IF;
    END IF;

    INSERT INTO reports (
        reporter_id, reported_user_id, reported_message_id,
        reported_post_id, reported_comment_id,
        report_type, description
    ) VALUES (
        p_reporter_id, p_reported_user_id, p_reported_message_id,
        p_reported_post_id, p_reported_comment_id,
        p_report_type, p_description
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$function$;