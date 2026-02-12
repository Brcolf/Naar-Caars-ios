-- Migration: Fix badge counts RPC search_path and conversation RPC ambiguity
--
-- Why:
-- 1) get_badge_counts was SECURITY DEFINER with search_path='' but used unqualified
--    table names (messages, notifications), causing 42P01 relation errors.
-- 2) get_conversations_with_details could raise 42702 ambiguous reference errors in
--    some deployments due unqualified conversation_id references in PL/pgSQL scope.

CREATE OR REPLACE FUNCTION public.get_badge_counts(
    p_user_id UUID DEFAULT NULL,
    p_include_details BOOLEAN DEFAULT FALSE
) RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_messages_total INTEGER;
    v_requests_total INTEGER;
    v_community_total INTEGER;
    v_bell_total INTEGER;
    v_request_details JSONB := '[]'::jsonb;
    v_conversation_details JSONB := '[]'::jsonb;
BEGIN
    v_user_id := COALESCE(auth.uid(), p_user_id);
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;

    -- Messages: total unread messages for user (only in their conversations)
    SELECT COUNT(*)
    INTO v_messages_total
    FROM public.messages m
    JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
        AND cp.user_id = v_user_id
    WHERE m.from_id <> v_user_id
      AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[v_user_id]::uuid[]);

    -- Cleanup: mark stale message notifications as read when no unread messages remain.
    UPDATE public.notifications n
    SET read = true
    WHERE n.user_id = v_user_id
      AND n.read = false
      AND n.type IN ('message', 'added_to_conversation')
      AND n.conversation_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.messages m
          JOIN public.conversation_participants cp
              ON cp.conversation_id = m.conversation_id
              AND cp.user_id = v_user_id
          WHERE m.conversation_id = n.conversation_id
            AND m.from_id <> v_user_id
            AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[v_user_id]::uuid[])
      );

    -- Requests: distinct requests with unseen activity
    WITH unread_requests AS (
        SELECT DISTINCT
            CASE
                WHEN ride_id IS NOT NULL THEN 'ride:' || ride_id::text
                WHEN favor_id IS NOT NULL THEN 'favor:' || favor_id::text
                ELSE NULL
            END AS request_key
        FROM public.notifications
        WHERE user_id = v_user_id
          AND read = false
          AND type IN (
              'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
              'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
              'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
              'review_request', 'review_reminder'
          )
    )
    SELECT COUNT(*)
    INTO v_requests_total
    FROM unread_requests
    WHERE request_key IS NOT NULL;

    -- Community: unread Town Hall notifications
    SELECT COUNT(*)
    INTO v_community_total
    FROM public.notifications
    WHERE user_id = v_user_id
      AND read = false
      AND type IN ('town_hall_post', 'town_hall_comment', 'town_hall_reaction');

    -- Bell: unread grouped bell-feed notifications (non-message)
    WITH bell_fresh AS (
        SELECT *
        FROM public.notifications
        WHERE user_id = v_user_id
          AND type NOT IN ('message', 'added_to_conversation')
          AND (read = false OR created_at > NOW() - INTERVAL '24 hours')
    ),
    latest_announcement AS (
        SELECT id
        FROM bell_fresh
        WHERE type IN ('announcement', 'admin_announcement', 'broadcast')
        ORDER BY created_at DESC
        LIMIT 1
    ),
    bell_pruned AS (
        SELECT * FROM bell_fresh
        WHERE type NOT IN ('announcement', 'admin_announcement', 'broadcast')
        UNION ALL
        SELECT bf.*
        FROM bell_fresh bf
        WHERE bf.id IN (SELECT id FROM latest_announcement)
    ),
    bell_groups AS (
        SELECT
            CASE
                WHEN type IN ('announcement', 'admin_announcement', 'broadcast')
                    THEN 'announcement:' || id::text
                WHEN type IN ('town_hall_post', 'town_hall_comment', 'town_hall_reaction')
                    AND town_hall_post_id IS NOT NULL
                    THEN 'townHall:' || town_hall_post_id::text
                WHEN type = 'pending_approval'
                    THEN 'admin:pendingApproval'
                WHEN type IN (
                    'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                    'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                    'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                    'review_request', 'review_reminder', 'review_received'
                ) AND ride_id IS NOT NULL
                    THEN 'ride:' || ride_id::text
                WHEN type IN (
                    'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                    'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                    'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                    'review_request', 'review_reminder', 'review_received'
                ) AND favor_id IS NOT NULL
                    THEN 'favor:' || favor_id::text
                ELSE 'notification:' || id::text
            END AS group_key,
            BOOL_OR(read = false) AS has_unread
        FROM bell_pruned
        GROUP BY group_key
    )
    SELECT COUNT(*)
    INTO v_bell_total
    FROM bell_groups
    WHERE has_unread = true;

    IF p_include_details THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'conversation_id', per_conversation.conversation_id,
            'unread_count', per_conversation.unread_count
        )), '[]'::jsonb)
        INTO v_conversation_details
        FROM (
            SELECT m.conversation_id, COUNT(*)::int AS unread_count
            FROM public.messages m
            JOIN public.conversation_participants cp
                ON cp.conversation_id = m.conversation_id
                AND cp.user_id = v_user_id
            WHERE m.from_id <> v_user_id
              AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[v_user_id]::uuid[])
            GROUP BY m.conversation_id
        ) AS per_conversation;

        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'request_type', per_request.request_type,
            'request_id', per_request.request_id,
            'unread_count', per_request.unread_count
        )), '[]'::jsonb)
        INTO v_request_details
        FROM (
            SELECT
                CASE WHEN n.ride_id IS NOT NULL THEN 'ride' ELSE 'favor' END AS request_type,
                COALESCE(n.ride_id, n.favor_id) AS request_id,
                COUNT(*)::int AS unread_count
            FROM public.notifications n
            WHERE n.user_id = v_user_id
              AND n.read = false
              AND n.type IN (
                  'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                  'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                  'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                  'review_request', 'review_reminder'
              )
              AND (n.ride_id IS NOT NULL OR n.favor_id IS NOT NULL)
            GROUP BY request_type, request_id
        ) AS per_request;
    END IF;

    RETURN jsonb_build_object(
        'user_id', v_user_id,
        'messages_total', v_messages_total,
        'requests_total', v_requests_total,
        'community_total', v_community_total,
        'bell_total', v_bell_total,
        'request_details', v_request_details,
        'conversation_details', v_conversation_details
    );
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO '';

GRANT EXECUTE ON FUNCTION public.get_badge_counts(UUID, BOOLEAN) TO authenticated;

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
        c.title,
        c.group_image_url,
        c.is_archived,
        c.created_at,
        c.updated_at,
        lm.message_json AS last_message,
        COALESCE(u.unread_count, 0) AS unread_count,
        COALESCE(pp.participants_json, '[]'::jsonb) AS other_participants
    FROM conversation_rows c
    LEFT JOIN last_messages lm ON lm.conversation_id = c.id
    LEFT JOIN unread_counts u ON u.conversation_id = c.id
    LEFT JOIN participant_profiles pp ON pp.conversation_id = c.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '';

GRANT EXECUTE ON FUNCTION public.get_conversations_with_details(UUID, INTEGER, INTEGER) TO authenticated;
