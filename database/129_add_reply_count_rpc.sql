-- Add RPC function to batch-fetch reply counts for messages
CREATE OR REPLACE FUNCTION get_reply_counts(p_conversation_id UUID, p_message_ids UUID[])
RETURNS TABLE(parent_id UUID, reply_count BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT reply_to_id, COUNT(*)
  FROM messages
  WHERE conversation_id = p_conversation_id
    AND reply_to_id = ANY(p_message_ids)
    AND deleted_at IS NULL
  GROUP BY reply_to_id;
$$;
