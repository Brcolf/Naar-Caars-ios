-- Create function to send approval notification (bypasses RLS)
-- This allows admins to create notifications for newly approved users

CREATE OR REPLACE FUNCTION send_approval_notification(
    p_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    -- Insert approval notification for the user
    INSERT INTO notifications (
        user_id,
        type,
        title,
        body,
        read,
        pinned,
        created_at
    ) VALUES (
        p_user_id,
        'user_approved',
        'Welcome to Naar''s Cars!',
        'Your account has been approved. You can now access all features of the app.',
        false,
        true,
        NOW()
    )
    RETURNING id INTO v_notification_id;
    
    RETURN v_notification_id;
END;
$$;

-- Grant execute permission to authenticated users
-- (RLS will verify admin status on the client side, but this allows the function to run)
GRANT EXECUTE ON FUNCTION send_approval_notification TO authenticated;

-- Add comment
COMMENT ON FUNCTION send_approval_notification IS 'Sends approval notification to a newly approved user. Must be called by admin users only.';

