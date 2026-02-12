-- Migration: Fix get_conversations_with_details return type alignment
--
-- Why:
-- PostgreSQL requires RETURN QUERY column types to exactly match the
-- RETURNS TABLE declaration. conversations.title is VARCHAR(100), while
-- the function returns title as TEXT.

CREATE OR REPLACE FUNCTION public.get_conversations_with_details(
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
        SELECT cp.conversation_id AS conv_id
        FROM public.conversation_participants cp
        WHERE cp.user_id = p_user_id
          AND cp.left_at IS NULL
        UNION
        SELECT c.id AS conv_id
        FROM public.conversations c
        WHERE c.created_by = p_user_id
    ),
    conversation_rows AS (
        SELECT c.*
        FROM public.conversations c
        JOIN conversation_ids ci ON ci.conv_id = c.id
        ORDER BY c.updated_at DESC
        LIMIT p_limit OFFSET p_offset
    ),
    last_messages AS (
        SELECT DISTINCT ON (m.conversation_id)
            m.conversation_id,
            to_jsonb(m) || jsonb_build_object('sender', to_jsonb(p)) AS message_json
        FROM public.messages m
        LEFT JOIN public.profiles p ON p.id = m.from_id
        WHERE m.conversation_id IN (SELECT cr.id FROM conversation_rows cr)
        ORDER BY m.conversation_id, m.created_at DESC
    ),
    unread_counts AS (
        SELECT m.conversation_id, COUNT(*)::int AS unread_count
        FROM public.messages m
        WHERE m.conversation_id IN (SELECT cr.id FROM conversation_rows cr)
          AND m.from_id <> p_user_id
          AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[p_user_id]::uuid[])
        GROUP BY m.conversation_id
    ),
    participant_profiles AS (
        SELECT
            cp.conversation_id,
            COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb) AS participants_json
        FROM public.conversation_participants cp
        JOIN public.profiles p ON p.id = cp.user_id
        WHERE cp.conversation_id IN (SELECT cr.id FROM conversation_rows cr)
          AND cp.user_id <> p_user_id
          AND cp.left_at IS NULL
        GROUP BY cp.conversation_id
    )
    SELECT
        c.id AS conversation_id,
        c.created_by,
        c.title::text AS title,
        c.group_image_url::text AS group_image_url,
        c.is_archived,
        c.created_at,
        c.updated_at,
        lm.message_json AS last_message,
        COALESCE(u.unread_count, 0)::int AS unread_count,
        COALESCE(pp.participants_json, '[]'::jsonb) AS other_participants
    FROM conversation_rows c
    LEFT JOIN last_messages lm ON lm.conversation_id = c.id
    LEFT JOIN unread_counts u ON u.conversation_id = c.id
    LEFT JOIN participant_profiles pp ON pp.conversation_id = c.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '';

GRANT EXECUTE ON FUNCTION public.get_conversations_with_details(UUID, INTEGER, INTEGER) TO authenticated;
