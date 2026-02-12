-- Migration: RPC to fetch conversations with last message, unread counts, and participants

-- Existing deployments may already have this function with a different OUT row type.
-- PostgreSQL cannot change RETURNS TABLE shape via CREATE OR REPLACE, so drop first.
DO $$
DECLARE
    fn regprocedure;
BEGIN
    FOR fn IN
        SELECT p.oid::regprocedure
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'get_conversations_with_details'
    LOOP
        EXECUTE format('DROP FUNCTION %s', fn);
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION get_conversations_with_details(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 10,
    p_offset INTEGER DEFAULT 0
) RETURNS TABLE (
    conversation_id UUID,
    created_by UUID,
    title TEXT,
    group_image_url TEXT,
    is_archived BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    last_message JSONB,
    unread_count INTEGER,
    other_participants JSONB
) AS $$
BEGIN
    RETURN QUERY
    WITH conversation_ids AS (
        SELECT conversation_id
        FROM conversation_participants
        WHERE user_id = p_user_id
          AND left_at IS NULL
        UNION
        SELECT id AS conversation_id
        FROM conversations
        WHERE created_by = p_user_id
    ),
    conversation_rows AS (
        SELECT c.*
        FROM conversations c
        JOIN conversation_ids ci ON ci.conversation_id = c.id
        ORDER BY c.updated_at DESC
        LIMIT p_limit OFFSET p_offset
    ),
    last_messages AS (
        SELECT DISTINCT ON (m.conversation_id)
            m.conversation_id,
            to_jsonb(m) || jsonb_build_object('sender', to_jsonb(p)) AS message_json
        FROM messages m
        LEFT JOIN profiles p ON p.id = m.from_id
        WHERE m.conversation_id IN (SELECT id FROM conversation_rows)
        ORDER BY m.conversation_id, m.created_at DESC
    ),
    unread_counts AS (
        SELECT m.conversation_id, COUNT(*)::int AS unread_count
        FROM messages m
        WHERE m.conversation_id IN (SELECT id FROM conversation_rows)
          AND m.from_id <> p_user_id
          AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[p_user_id]::uuid[])
        GROUP BY m.conversation_id
    ),
    participant_profiles AS (
        SELECT
            cp.conversation_id,
            COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb) AS participants_json
        FROM conversation_participants cp
        JOIN profiles p ON p.id = cp.user_id
        WHERE cp.conversation_id IN (SELECT id FROM conversation_rows)
          AND cp.user_id <> p_user_id
          AND cp.left_at IS NULL
        GROUP BY cp.conversation_id
    )
    SELECT
        c.id,
        c.created_by,
        c.title,
        c.group_image_url,
        c.is_archived,
        c.created_at,
        c.updated_at,
        lm.message_json,
        COALESCE(u.unread_count, 0),
        COALESCE(pp.participants_json, '[]'::jsonb)
    FROM conversation_rows c
    LEFT JOIN last_messages lm ON lm.conversation_id = c.id
    LEFT JOIN unread_counts u ON u.conversation_id = c.id
    LEFT JOIN participant_profiles pp ON pp.conversation_id = c.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_conversations_with_details(UUID, INTEGER, INTEGER) TO authenticated;
