-- Create function to send broadcast notifications (bypasses RLS)
-- This allows admins to create notifications for any user
-- Also creates a town hall post linked to the notifications

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

    -- Loop through all approved users
    FOR v_user_id IN
        SELECT id FROM profiles WHERE approved = true
    LOOP
        -- Insert notification for each user, linked to the town hall post
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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION send_broadcast_notifications TO authenticated;

COMMENT ON FUNCTION send_broadcast_notifications IS 'Sends broadcast notifications to all approved users with a linked town hall post. Must be called by admin users only.';
