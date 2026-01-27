-- Migration: RPC to find an existing direct conversation between two users

CREATE OR REPLACE FUNCTION find_dm_conversation(
    p_user_a UUID,
    p_user_b UUID
) RETURNS UUID AS $$
    SELECT cp1.conversation_id
    FROM conversation_participants cp1
    JOIN conversation_participants cp2
        ON cp1.conversation_id = cp2.conversation_id
    WHERE cp1.user_id = p_user_a
      AND cp2.user_id = p_user_b
      AND cp1.left_at IS NULL
      AND cp2.left_at IS NULL
      AND (
        SELECT COUNT(*)
        FROM conversation_participants cp
        WHERE cp.conversation_id = cp1.conversation_id
          AND cp.left_at IS NULL
      ) = 2
    LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION find_dm_conversation(UUID, UUID) TO authenticated;


