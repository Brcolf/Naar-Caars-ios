-- Security/functional follow-up: ensure content reports queue push notifications.
-- Live trigger handle_new_report() created in-app notifications for admins but
-- never queued push delivery, which meant admins only saw a bell item and no
-- banner/APNs despite notification settings being enabled.

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
    -- Auto-hide posts at 3+ unique reporters
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

    -- Auto-hide comments at 3+ unique reporters
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

    -- Fallback preview for report types without a content snippet
    IF v_content_preview IS NULL THEN
        v_content_preview := 'User or message report';
    END IF;

    v_body := INITCAP(REPLACE(NEW.report_type, '_', ' ')) || ': ' || LEFT(v_content_preview, 60);

    -- Notify all admins on every report and queue push delivery
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
