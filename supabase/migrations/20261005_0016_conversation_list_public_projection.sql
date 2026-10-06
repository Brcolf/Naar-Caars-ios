-- 20261005_0016_conversation_list_public_projection.sql
--
-- APPLIED 2026-10-05 (Supabase MCP) and verified against the previous output.
--
-- get_conversations_with_details() serialised whole public.profiles rows for the last-message
-- sender and for every other participant: email, phone_number, is_admin, ban fields, invited_by,
-- join_reason and the notify_* preferences of other members reached every device on each
-- conversation-list load, bypassing the public_profiles projection split. Both joins now read
-- public.public_profiles (id, name, avatar_url, car, approved, created_at, updated_at).
-- Profile.init(from:) requires only id and name (working tree and origin/main), and no consumer of
-- this RPC reads anything beyond id, name and avatar_url.
--
-- last_messages now mirrors the messages SELECT policy: a message hidden by moderation is no
-- longer returned as the list preview to other members, and nothing outside the caller's
-- membership window (joined_at .. left_at) is returned. The caller's own message stays eligible
-- so legacy conversations without participant rows keep their preview.
--
-- Not changed: unread_counts (same predicates would change badge numbers; decide separately) and
-- the creator branch of conversation_ids.
--
-- Verification (rolled-back transaction, 2026-10-05): for two accounts the row count, number of
-- previews, unread total and participant totals are identical before and after. One preview
-- changed, as intended: a group its creator left on 2026-02-18 no longer previews a message sent
-- on 2026-03-03. Participant and sender objects now carry exactly the seven public columns.

CREATE OR REPLACE FUNCTION public.get_conversations_with_details(p_user_id uuid, p_limit integer DEFAULT 10, p_offset integer DEFAULT 0)
 RETURNS TABLE(conversation_id uuid, created_by uuid, title text, group_image_url text, is_archived boolean, created_at timestamp with time zone, updated_at timestamp with time zone, last_message jsonb, unread_count integer, other_participants jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
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
        -- Mirrors the messages SELECT policy: no moderated (hidden) message from someone else and
        -- nothing outside the caller's membership window. The caller's own message is always
        -- eligible (legacy conversations that have no participant rows).
        SELECT DISTINCT ON (m.conversation_id)
            m.conversation_id,
            to_jsonb(m) || jsonb_build_object('sender', to_jsonb(p)) AS message_json
        FROM public.messages m
        LEFT JOIN public.public_profiles p ON p.id = m.from_id
        WHERE m.conversation_id IN (SELECT cr.id FROM conversation_rows cr)
          AND (m.hidden_at IS NULL OR m.from_id = p_user_id)
          AND (
              m.from_id = p_user_id
              OR EXISTS (
                  SELECT 1
                  FROM public.conversation_participants x
                  WHERE x.conversation_id = m.conversation_id
                    AND x.user_id = p_user_id
                    AND m.created_at >= x.joined_at
                    AND (x.left_at IS NULL OR m.created_at <= x.left_at)
              )
          )
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
        -- public_profiles (id, name, avatar_url, car, approved, created_at, updated_at) instead of
        -- the full profiles row: no email, phone, ban or admin data leaves the server.
        SELECT
            cp.conversation_id,
            COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb) AS participants_json
        FROM public.conversation_participants cp
        JOIN public.public_profiles p ON p.id = cp.user_id
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
$function$;
