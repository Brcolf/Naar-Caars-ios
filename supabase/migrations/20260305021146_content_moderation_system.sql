-- 20260305021146_content_moderation_system.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Content Moderation System
-- Extends reports table for posts/comments, adds auto-hide trigger,
-- admin notifications, and admin moderation RPCs.

-- 1. Add post/comment columns to reports table
ALTER TABLE public.reports
    ADD COLUMN IF NOT EXISTS reported_post_id UUID REFERENCES public.town_hall_posts(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS reported_comment_id UUID REFERENCES public.town_hall_comments(id) ON DELETE CASCADE;

-- 2. Update constraint to accept post/comment reports
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS report_target_check;
ALTER TABLE public.reports ADD CONSTRAINT report_target_check CHECK (
    reported_user_id IS NOT NULL
    OR reported_message_id IS NOT NULL
    OR reported_post_id IS NOT NULL
    OR reported_comment_id IS NOT NULL
);

-- 3. Add indexes
CREATE INDEX IF NOT EXISTS idx_reports_reported_post ON public.reports(reported_post_id) WHERE reported_post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_reported_comment ON public.reports(reported_comment_id) WHERE reported_comment_id IS NOT NULL;

-- 4. Add moderation columns to town_hall_posts
ALTER TABLE public.town_hall_posts
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS hidden_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 5. Add moderation columns to town_hall_comments
ALTER TABLE public.town_hall_comments
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS hidden_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 6. Admin RLS: read all reports
CREATE POLICY "Admins can view all reports"
ON public.reports FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
);

-- 7. Admin RLS: update reports
CREATE POLICY "Admins can update reports"
ON public.reports FOR UPDATE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
)
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
);

-- 8. Replace submit_report to accept post/comment IDs + prevent duplicates
CREATE OR REPLACE FUNCTION public.submit_report(
    p_reporter_id UUID,
    p_reported_user_id UUID DEFAULT NULL,
    p_reported_message_id UUID DEFAULT NULL,
    p_reported_post_id UUID DEFAULT NULL,
    p_reported_comment_id UUID DEFAULT NULL,
    p_report_type TEXT DEFAULT 'other',
    p_description TEXT DEFAULT NULL
) RETURNS UUID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_report_id UUID;
BEGIN
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL
       AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, or comment';
    END IF;

    -- Prevent duplicate reports from same user on same content
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
$$;

-- 9. Auto-hide trigger + admin notification on every report
CREATE OR REPLACE FUNCTION public.handle_new_report()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_report_count INT;
    v_content_preview TEXT;
    v_admin RECORD;
    v_notification_id UUID;
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

    -- Notify all admins on every report
    IF v_content_preview IS NULL THEN
        v_content_preview := 'User or message report';
    END IF;

    FOR v_admin IN SELECT id FROM profiles WHERE is_admin = true
    LOOP
        v_notification_id := create_notification(
            v_admin.id,
            'content_reported',
            'Content Reported',
            INITCAP(REPLACE(NEW.report_type, '_', ' ')) || ': ' || LEFT(v_content_preview, 60),
            NULL, NULL, NULL, NULL,
            COALESCE(NEW.reported_post_id, NULL),
            NEW.reporter_id
        );
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_report_created ON public.reports;
CREATE TRIGGER on_report_created
    AFTER INSERT ON public.reports
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_report();

-- 10. Admin RPC to hide/restore/dismiss content
CREATE OR REPLACE FUNCTION public.admin_moderate_content(
    p_admin_id UUID,
    p_report_id UUID,
    p_action TEXT,
    p_admin_notes TEXT DEFAULT NULL
) RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_report RECORD;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_admin_id AND is_admin = true) THEN
        RAISE EXCEPTION 'Unauthorized: not an admin';
    END IF;

    SELECT * INTO v_report FROM reports WHERE id = p_report_id;
    IF v_report IS NULL THEN
        RAISE EXCEPTION 'Report not found';
    END IF;

    IF p_action = 'hide' THEN
        IF v_report.reported_post_id IS NOT NULL THEN
            UPDATE town_hall_posts SET hidden_at = NOW(), hidden_by = p_admin_id
            WHERE id = v_report.reported_post_id;
        END IF;
        IF v_report.reported_comment_id IS NOT NULL THEN
            UPDATE town_hall_comments SET hidden_at = NOW(), hidden_by = p_admin_id
            WHERE id = v_report.reported_comment_id;
        END IF;
        UPDATE reports SET status = 'action_taken', reviewed_at = NOW(),
            reviewed_by = p_admin_id, admin_notes = p_admin_notes
        WHERE id = p_report_id;

    ELSIF p_action = 'restore' THEN
        IF v_report.reported_post_id IS NOT NULL THEN
            UPDATE town_hall_posts SET hidden_at = NULL, hidden_by = NULL
            WHERE id = v_report.reported_post_id;
        END IF;
        IF v_report.reported_comment_id IS NOT NULL THEN
            UPDATE town_hall_comments SET hidden_at = NULL, hidden_by = NULL
            WHERE id = v_report.reported_comment_id;
        END IF;
        UPDATE reports SET status = 'dismissed', reviewed_at = NOW(),
            reviewed_by = p_admin_id, admin_notes = p_admin_notes
        WHERE id = p_report_id;

    ELSIF p_action = 'dismiss' THEN
        UPDATE reports SET status = 'dismissed', reviewed_at = NOW(),
            reviewed_by = p_admin_id, admin_notes = p_admin_notes
        WHERE id = p_report_id;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_moderate_content(UUID, UUID, TEXT, TEXT) TO authenticated;

-- 11. Admin RPC to fetch reports with content details
CREATE OR REPLACE FUNCTION public.admin_get_reports(
    p_admin_id UUID,
    p_status TEXT DEFAULT NULL
) RETURNS TABLE (
    report_id UUID,
    reporter_id UUID,
    reporter_name TEXT,
    reported_user_id UUID,
    reported_user_name TEXT,
    reported_post_id UUID,
    reported_comment_id UUID,
    report_type TEXT,
    description TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    content_preview TEXT,
    content_hidden BOOLEAN,
    report_count INT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_admin_id AND is_admin = true) THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    RETURN QUERY
    SELECT
        r.id AS report_id,
        r.reporter_id,
        rp.name AS reporter_name,
        r.reported_user_id,
        rup.name AS reported_user_name,
        r.reported_post_id,
        r.reported_comment_id,
        r.report_type,
        r.description,
        r.status,
        r.created_at,
        r.reviewed_at,
        COALESCE(
            LEFT(p.content, 120),
            LEFT(c.content, 120),
            'User/message report'
        ) AS content_preview,
        COALESCE(p.hidden_at IS NOT NULL, c.hidden_at IS NOT NULL, false) AS content_hidden,
        COALESCE(
            (SELECT COUNT(DISTINCT r2.reporter_id)::INT FROM reports r2 WHERE r2.reported_post_id = r.reported_post_id AND r.reported_post_id IS NOT NULL),
            (SELECT COUNT(DISTINCT r2.reporter_id)::INT FROM reports r2 WHERE r2.reported_comment_id = r.reported_comment_id AND r.reported_comment_id IS NOT NULL),
            1
        ) AS report_count
    FROM reports r
    LEFT JOIN profiles rp ON rp.id = r.reporter_id
    LEFT JOIN profiles rup ON rup.id = r.reported_user_id
    LEFT JOIN town_hall_posts p ON p.id = r.reported_post_id
    LEFT JOIN town_hall_comments c ON c.id = r.reported_comment_id
    WHERE (p_status IS NULL OR r.status = p_status)
    ORDER BY
        CASE r.status WHEN 'pending' THEN 0 ELSE 1 END,
        r.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_reports(UUID, TEXT) TO authenticated;
