-- Replace leave_conversation to enforce minimum 3 remaining active members
CREATE OR REPLACE FUNCTION public.leave_conversation(
    p_conversation_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_participant_exists BOOLEAN;
    v_already_left BOOLEAN;
    v_active_count INT;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
    ) INTO v_participant_exists;

    IF NOT v_participant_exists THEN
        RAISE EXCEPTION 'User is not a participant in this conversation';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
        AND left_at IS NOT NULL
    ) INTO v_already_left;

    IF v_already_left THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO v_active_count
    FROM conversation_participants
    WHERE conversation_id = p_conversation_id
      AND left_at IS NULL
      AND user_id != p_user_id;

    IF v_active_count < 3 THEN
        RAISE EXCEPTION 'Cannot leave: group must have at least 3 remaining members';
    END IF;

    UPDATE conversation_participants
    SET left_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.leave_conversation(UUID, UUID) TO authenticated;
