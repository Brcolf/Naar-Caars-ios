-- Migration: Batch mark messages as read
-- Adds RPC to mark multiple messages as read for a user atomically.

CREATE OR REPLACE FUNCTION mark_messages_read_batch(
    p_message_ids UUID[],
    p_user_id UUID
) RETURNS VOID AS $$
BEGIN
    UPDATE messages
    SET read_by = array_append(COALESCE(read_by, ARRAY[]::uuid[]), p_user_id)
    WHERE id = ANY(p_message_ids)
      AND NOT (COALESCE(read_by, ARRAY[]::uuid[]) @> ARRAY[p_user_id]);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION mark_messages_read_batch(UUID[], UUID) TO authenticated;


