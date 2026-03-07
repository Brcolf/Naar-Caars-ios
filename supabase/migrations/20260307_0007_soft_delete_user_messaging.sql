-- Helper function to soft-delete a user's messaging presence during account deletion
-- Called BEFORE the hard delete cascade so messages show "Deleted User" instead of disappearing
CREATE OR REPLACE FUNCTION public.soft_delete_user_messaging(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Soft-delete all participant records (set left_at)
    UPDATE conversation_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;

    -- Soft-delete all messages sent by user (set deleted_at, clear text)
    UPDATE messages
    SET deleted_at = NOW(),
        text = '[Message from deleted user]'
    WHERE from_id = p_user_id
      AND deleted_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.soft_delete_user_messaging(UUID) TO service_role;
