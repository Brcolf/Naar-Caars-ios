-- 20260403074005_security_broadcast_admin_check.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Add server-side admin check to send_broadcast_notifications.
-- Live state: SECURITY DEFINER, no is_admin check, granted to PUBLIC/anon/authenticated.
-- Audit ref: CRIT-2 — any authenticated user could broadcast to all members.

CREATE OR REPLACE FUNCTION public.send_broadcast_notifications(
    p_title text,
    p_body text,
    p_type text DEFAULT 'broadcast'::text,
    p_pinned boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user_id UUID;
    v_admin_id UUID;
    v_inserted_count INTEGER := 0;
    v_notification_id UUID;
    v_post_id UUID;
BEGIN
    v_admin_id := auth.uid();

    -- SECURITY FIX: Verify caller is an admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = v_admin_id AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Only admins can send broadcast notifications';
    END IF;

    INSERT INTO town_hall_posts (
        user_id, title, content, pinned, type, created_at, updated_at
    ) VALUES (
        v_admin_id, p_title, p_body, p_pinned, 'announcement', NOW(), NOW()
    )
    RETURNING id INTO v_post_id;

    FOR v_user_id IN
        SELECT id FROM profiles WHERE approved = true
    LOOP
        INSERT INTO notifications (
            user_id, type, title, body, read, pinned,
            town_hall_post_id, source_user_id, created_at
        ) VALUES (
            v_user_id, p_type, p_title, p_body, false, p_pinned,
            v_post_id, v_admin_id, NOW()
        )
        RETURNING id INTO v_notification_id;

        v_inserted_count := v_inserted_count + 1;
    END LOOP;

    RETURN v_inserted_count;
END;
$$;

-- Tighten grants
REVOKE ALL ON FUNCTION public.send_broadcast_notifications FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_broadcast_notifications FROM anon;
GRANT EXECUTE ON FUNCTION public.send_broadcast_notifications TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_broadcast_notifications TO service_role;
