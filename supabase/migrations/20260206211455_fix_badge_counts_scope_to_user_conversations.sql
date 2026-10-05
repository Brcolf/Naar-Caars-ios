-- 20260206211455_fix_badge_counts_scope_to_user_conversations.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Fix: Scope message counts to only conversations the user participates in.
-- Previously, unread messages were counted across ALL conversations in the database,
-- not just ones the user is a member of, causing inflated badge counts.

CREATE OR REPLACE FUNCTION public.get_badge_counts(
    p_user_id uuid DEFAULT NULL,
    p_include_details boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id uuid;
    v_messages_total integer;
    v_requests_total integer;
    v_community_total integer;
    v_bell_total integer;
    v_request_details jsonb := '[]'::jsonb;
    v_conversation_details jsonb := '[]'::jsonb;
BEGIN
    v_user_id := coalesce(auth.uid(), p_user_id);
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;

    -- Messages: total unread messages for user (only in their conversations)
    SELECT count(*)
    INTO v_messages_total
    FROM public.messages m
    JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
        AND cp.user_id = v_user_id
    WHERE m.from_id <> v_user_id
      AND NOT (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[]);

    -- Cleanup: Mark 'message' and 'added_to_conversation' notifications as read
    -- if there are no unread messages in that conversation.
    UPDATE public.notifications n
    SET read = true
    WHERE n.user_id = v_user_id
      AND n.read = false
      AND n.type IN ('message', 'added_to_conversation')
      AND n.conversation_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM public.messages m
          JOIN public.conversation_participants cp
              ON cp.conversation_id = m.conversation_id
              AND cp.user_id = v_user_id
          WHERE m.conversation_id = n.conversation_id
            AND m.from_id <> v_user_id
            AND NOT (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
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
    SELECT count(*)
    INTO v_requests_total
    FROM unread_requests
    WHERE request_key IS NOT NULL;

    -- Community: unread Town Hall notifications
    SELECT count(*)
    INTO v_community_total
    FROM public.notifications
    WHERE user_id = v_user_id
      AND read = false
      AND type IN ('town_hall_post', 'town_hall_comment', 'town_hall_reaction');

    -- Bell: unread grouped bell-feed notifications
    WITH bell_fresh AS (
        SELECT *
        FROM public.notifications
        WHERE user_id = v_user_id
          AND type NOT IN ('message', 'added_to_conversation')
          AND (read = false OR created_at > now() - interval '24 hours')
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
        SELECT bf.* FROM bell_fresh bf
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
            bool_or(read = false) AS has_unread
        FROM bell_pruned
        GROUP BY group_key
    )
    SELECT count(*)
    INTO v_bell_total
    FROM bell_groups
    WHERE has_unread = true;

    IF p_include_details THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object(
            'conversation_id', conversation_id,
            'unread_count', unread_count
        )), '[]'::jsonb)
        INTO v_conversation_details
        FROM (
            SELECT m.conversation_id, count(*)::int AS unread_count
            FROM public.messages m
            JOIN public.conversation_participants cp
                ON cp.conversation_id = m.conversation_id
                AND cp.user_id = v_user_id
            WHERE m.from_id <> v_user_id
              AND NOT (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
            GROUP BY m.conversation_id
        ) AS per_conversation;

        SELECT coalesce(jsonb_agg(jsonb_build_object(
            'request_type', request_type,
            'request_id', request_id,
            'unread_count', unread_count
        )), '[]'::jsonb)
        INTO v_request_details
        FROM (
            SELECT
                CASE WHEN ride_id IS NOT NULL THEN 'ride' ELSE 'favor' END AS request_type,
                coalesce(ride_id, favor_id) AS request_id,
                count(*)::int AS unread_count
            FROM public.notifications
            WHERE user_id = v_user_id
              AND read = false
              AND type IN (
                  'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                  'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                  'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                  'review_request', 'review_reminder'
              )
              AND (ride_id IS NOT NULL OR favor_id IS NOT NULL)
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
$function$;
