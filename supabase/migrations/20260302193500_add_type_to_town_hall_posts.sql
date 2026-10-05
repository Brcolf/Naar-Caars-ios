-- 20260302193500_add_type_to_town_hall_posts.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Add type column to town_hall_posts for distinguishing post types
ALTER TABLE town_hall_posts ADD COLUMN IF NOT EXISTS type TEXT DEFAULT NULL;

-- Backfill: set type = 'review' for posts that have a review_id
UPDATE town_hall_posts SET type = 'review' WHERE review_id IS NOT NULL AND type IS NULL;

-- Update broadcast function to set type = 'announcement' on town hall post
CREATE OR REPLACE FUNCTION send_broadcast_notifications(
    p_title TEXT,
    p_body TEXT,
    p_type TEXT DEFAULT 'broadcast',
    p_pinned BOOLEAN DEFAULT false
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_admin_id UUID;
    v_inserted_count INTEGER := 0;
    v_notification_id UUID;
    v_post_id UUID;
BEGIN
    v_admin_id := auth.uid();

    -- Create a town hall post for this broadcast with type = 'announcement'
    INSERT INTO town_hall_posts (
        user_id,
        title,
        content,
        pinned,
        type,
        created_at,
        updated_at
    ) VALUES (
        v_admin_id,
        p_title,
        p_body,
        p_pinned,
        'announcement',
        NOW(),
        NOW()
    )
    RETURNING id INTO v_post_id;

    FOR v_user_id IN
        SELECT id FROM profiles WHERE approved = true
    LOOP
        INSERT INTO notifications (
            user_id,
            type,
            title,
            body,
            read,
            pinned,
            town_hall_post_id,
            source_user_id,
            created_at
        ) VALUES (
            v_user_id,
            p_type,
            p_title,
            p_body,
            false,
            p_pinned,
            v_post_id,
            v_admin_id,
            NOW()
        )
        RETURNING id INTO v_notification_id;

        v_inserted_count := v_inserted_count + 1;
    END LOOP;

    RETURN v_inserted_count;
END;
$$;