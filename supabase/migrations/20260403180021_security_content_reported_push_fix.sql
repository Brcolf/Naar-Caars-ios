-- 20260403180021_security_content_reported_push_fix.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

CREATE OR REPLACE FUNCTION public.handle_new_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_report_count INT;
    v_content_preview TEXT;
    v_admin RECORD;
    v_notification_id UUID;
    v_body TEXT;
BEGIN
    IF NEW.reported_post_id IS NOT NULL THEN
        SELECT COUNT(DISTINCT reporter_id) INTO v_report_count
        FROM reports WHERE reported_post_id = NEW.reported_post_id;

        SELECT LEFT(content, 80) INTO v_content_preview
        FROM town_hall_posts WHERE id = NEW.reported_post_id;

        IF v_report_count >= 3 THEN
            UPDATE town_hall_posts
            SET hidden_at = NOW(), hidden_by = NULL
            WHERE id = NEW.reported_post_id AND hidden_at IS NULL;
        END IF;
    END IF;

    IF NEW.reported_comment_id IS NOT NULL THEN
        SELECT COUNT(DISTINCT reporter_id) INTO v_report_count
        FROM reports WHERE reported_comment_id = NEW.reported_comment_id;

        SELECT LEFT(content, 80) INTO v_content_preview
        FROM town_hall_comments WHERE id = NEW.reported_comment_id;

        IF v_report_count >= 3 THEN
            UPDATE town_hall_comments
            SET hidden_at = NOW(), hidden_by = NULL
            WHERE id = NEW.reported_comment_id AND hidden_at IS NULL;
        END IF;
    END IF;

    IF v_content_preview IS NULL THEN
        v_content_preview := 'User or message report';
    END IF;

    v_body := INITCAP(REPLACE(NEW.report_type, '_', ' ')) || ': ' || LEFT(v_content_preview, 60);

    FOR v_admin IN
        SELECT id FROM profiles WHERE is_admin = true
    LOOP
        v_notification_id := create_notification(
            v_admin.id,
            'content_reported',
            'Content Reported',
            v_body,
            NULL,
            NULL,
            NULL,
            NULL,
            COALESCE(NEW.reported_post_id, NULL),
            NEW.reporter_id
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_admin.id,
                'content_reported',
                'Content Reported',
                v_body,
                '{}'::jsonb,
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;