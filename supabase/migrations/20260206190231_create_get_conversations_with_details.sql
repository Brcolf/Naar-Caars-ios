-- 20260206190231_create_get_conversations_with_details.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Create get_conversations_with_details RPC function
-- Returns conversations with last message, unread count, and other participants in a single query.
-- Replaces the N+1 fallback path that made 4+ queries per conversation.

CREATE OR REPLACE FUNCTION public.get_conversations_with_details(
    p_user_id uuid,
    p_limit integer DEFAULT 10,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(
    conversation_id uuid,
    created_by uuid,
    title varchar,
    group_image_url text,
    is_archived boolean,
    created_at timestamptz,
    updated_at timestamptz,
    last_message jsonb,
    unread_count bigint,
    other_participants jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id AS conversation_id,
        c.created_by,
        c.title,
        c.group_image_url,
        COALESCE(c.is_archived, false) AS is_archived,
        c.created_at,
        c.updated_at,
        -- Last message as JSON
        (
            SELECT jsonb_build_object(
                'id', m.id,
                'conversation_id', m.conversation_id,
                'from_id', m.from_id,
                'text', m.text,
                'image_url', m.image_url,
                'read_by', m.read_by,
                'created_at', m.created_at,
                'message_type', m.message_type,
                'reply_to_id', m.reply_to_id,
                'audio_url', m.audio_url,
                'audio_duration', m.audio_duration,
                'latitude', m.latitude,
                'longitude', m.longitude,
                'location_name', m.location_name,
                'edited_at', m.edited_at,
                'deleted_at', m.deleted_at
            )
            FROM public.messages m
            WHERE m.conversation_id = c.id
            ORDER BY m.created_at DESC
            LIMIT 1
        ) AS last_message,
        -- Unread count
        (
            SELECT COUNT(*)
            FROM public.messages m2
            WHERE m2.conversation_id = c.id
              AND m2.from_id != p_user_id
              AND (m2.read_by IS NULL OR NOT (m2.read_by @> ARRAY[p_user_id]::uuid[]))
              AND m2.deleted_at IS NULL
        ) AS unread_count,
        -- Other participants as JSON array of profiles
        (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'id', p.id,
                    'name', p.name,
                    'email', p.email,
                    'avatar_url', p.avatar_url,
                    'car', p.car,
                    'phone_number', p.phone_number,
                    'is_admin', p.is_admin,
                    'approved', p.approved,
                    'created_at', p.created_at,
                    'updated_at', p.updated_at
                )
            ), '[]'::jsonb)
            FROM public.conversation_participants cp2
            JOIN public.profiles p ON p.id = cp2.user_id
            WHERE cp2.conversation_id = c.id
              AND cp2.user_id != p_user_id
              AND cp2.left_at IS NULL
        ) AS other_participants
    FROM public.conversations c
    JOIN public.conversation_participants cp ON cp.conversation_id = c.id
    WHERE cp.user_id = p_user_id
      AND cp.left_at IS NULL
    ORDER BY c.updated_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;
