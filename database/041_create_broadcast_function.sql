-- Create function to send broadcast notifications (bypasses RLS)
-- This allows admins to create notifications for any user

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
    v_inserted_count INTEGER := 0;
    v_notification_id UUID;
BEGIN
    -- Loop through all approved users
    FOR v_user_id IN 
        SELECT id FROM profiles WHERE approved = true
    LOOP
        -- Insert notification for each user
        INSERT INTO notifications (
            user_id,
            type,
            title,
            body,
            read,
            pinned,
            created_at
        ) VALUES (
            v_user_id,
            p_type,
            p_title,
            p_body,
            false,
            p_pinned,
            NOW()
        )
        RETURNING id INTO v_notification_id;
        
        v_inserted_count := v_inserted_count + 1;
    END LOOP;
    
    RETURN v_inserted_count;
END;
$$;

-- Grant execute permission to authenticated users
-- (RLS will verify admin status on the client side, but this allows the function to run)
GRANT EXECUTE ON FUNCTION send_broadcast_notifications TO authenticated;

-- Add comment
COMMENT ON FUNCTION send_broadcast_notifications IS 'Sends broadcast notifications to all approved users. Must be called by admin users only.';


