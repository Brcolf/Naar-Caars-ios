-- 20260717200001_20260717_0001_lockdown_messaging_definer_rpcs.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Phase 1 security hardening: bind SECURITY DEFINER messaging/read RPCs to auth.uid(),
-- revoke anon EXECUTE, guard is_banned in profiles trigger, drop invite-code enumeration policy.
-- Bodies are reproduced verbatim from pg_get_functiondef with ONLY an auth guard inserted.

-- 1. get_conversations_with_details (SEC-CRIT-1)
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
$function$;

-- 2. send_reply_message (SEC-2) — bind p_from_id to caller
CREATE OR REPLACE FUNCTION public.send_reply_message(p_conversation_id uuid, p_from_id uuid, p_text text, p_reply_to_id uuid, p_image_url text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_message_id UUID;
    v_reply_exists BOOLEAN;
    v_is_participant BOOLEAN;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_from_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    -- Verify user is a participant in the conversation
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_from_id
        AND left_at IS NULL
    ) INTO v_is_participant;

    IF NOT v_is_participant THEN
        RAISE EXCEPTION 'User is not an active participant in this conversation';
    END IF;

    -- Verify the reply_to message exists and is in the same conversation
    IF p_reply_to_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM messages
            WHERE id = p_reply_to_id
            AND conversation_id = p_conversation_id
        ) INTO v_reply_exists;

        IF NOT v_reply_exists THEN
            RAISE EXCEPTION 'Reply target message not found in this conversation';
        END IF;
    END IF;

    -- Insert the message
    INSERT INTO messages (
        conversation_id,
        from_id,
        text,
        image_url,
        reply_to_id,
        message_type,
        read_by
    ) VALUES (
        p_conversation_id,
        p_from_id,
        p_text,
        p_image_url,
        p_reply_to_id,
        CASE WHEN p_image_url IS NOT NULL THEN 'image' ELSE 'text' END,
        ARRAY[p_from_id]::UUID[]
    )
    RETURNING id INTO v_message_id;

    -- Update conversation timestamp
    UPDATE conversations
    SET updated_at = NOW()
    WHERE id = p_conversation_id;

    RETURN v_message_id;
END;
$function$;

-- 3. remove_conversation_participant (SEC-3) — bind p_removed_by to caller
CREATE OR REPLACE FUNCTION public.remove_conversation_participant(p_conversation_id uuid, p_user_id uuid, p_removed_by uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_remover_is_participant BOOLEAN;
    v_target_exists BOOLEAN;
    v_conversation_creator UUID;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_removed_by THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    -- Check if remover is a participant (and not left)
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_removed_by
        AND left_at IS NULL
    ) INTO v_remover_is_participant;

    -- Also check if remover is the conversation creator
    SELECT created_by INTO v_conversation_creator
    FROM conversations
    WHERE id = p_conversation_id;

    IF NOT v_remover_is_participant AND v_conversation_creator != p_removed_by THEN
        RAISE EXCEPTION 'You must be a participant to remove others';
    END IF;

    -- Check if target user exists as participant
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
        AND left_at IS NULL
    ) INTO v_target_exists;

    IF NOT v_target_exists THEN
        RETURN FALSE; -- Target not found or already left
    END IF;

    -- Set left_at timestamp (soft remove)
    UPDATE conversation_participants
    SET left_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id;

    RETURN TRUE;
END;
$function$;

-- 4. mark_messages_read (SEC-5)
CREATE OR REPLACE FUNCTION public.mark_messages_read(p_conversation_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    UPDATE public.messages
    SET read_by = array_append(read_by, p_user_id)
    WHERE conversation_id = p_conversation_id
    AND NOT (p_user_id = ANY(read_by));
END;
$function$;

-- 5. mark_messages_read_batch (SEC-5)
CREATE OR REPLACE FUNCTION public.mark_messages_read_batch(p_message_ids uuid[], p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    UPDATE messages
    SET read_by = array_append(COALESCE(read_by, ARRAY[]::uuid[]), p_user_id)
    WHERE id = ANY(p_message_ids)
      AND NOT (COALESCE(read_by, ARRAY[]::uuid[]) @> ARRAY[p_user_id]);
END;
$function$;

-- 6. get_unread_counts (SEC-5)
CREATE OR REPLACE FUNCTION public.get_unread_counts(p_user_id uuid)
 RETURNS TABLE(unread_notifications bigint, unread_messages bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM public.notifications WHERE user_id = p_user_id AND read = false)::BIGINT as unread_notifications,
        (SELECT COUNT(*) FROM public.messages m
         JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
         WHERE cp.user_id = p_user_id AND NOT (p_user_id = ANY(m.read_by)))::BIGINT as unread_messages;
END;
$function$;

-- 7. get_pending_reviews (SEC-5)
CREATE OR REPLACE FUNCTION public.get_pending_reviews(p_user_id uuid)
 RETURNS TABLE(request_type text, request_id uuid, fulfiller_id uuid, fulfiller_name text, completed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    RETURN QUERY
    SELECT
        'ride'::TEXT as request_type,
        r.id as request_id,
        r.claimed_by as fulfiller_id,
        p.name as fulfiller_name,
        r.updated_at as completed_at
    FROM public.rides r
    JOIN public.profiles p ON r.claimed_by = p.id
    WHERE r.user_id = p_user_id
    AND r.status = 'completed'
    AND r.reviewed = false
    AND r.review_skipped = false
    AND r.updated_at >= NOW() - INTERVAL '7 days'

    UNION ALL

    SELECT
        'favor'::TEXT as request_type,
        f.id as request_id,
        f.claimed_by as fulfiller_id,
        p.name as fulfiller_name,
        f.updated_at as completed_at
    FROM public.favors f
    JOIN public.profiles p ON f.claimed_by = p.id
    WHERE f.user_id = p_user_id
    AND f.status = 'completed'
    AND f.reviewed = false
    AND f.review_skipped = false
    AND f.updated_at >= NOW() - INTERVAL '7 days';
END;
$function$;

-- 8. get_or_create_request_conversation (SEC-5) — bind p_user_id to caller
CREATE OR REPLACE FUNCTION public.get_or_create_request_conversation(p_user_id uuid, p_ride_id uuid DEFAULT NULL::uuid, p_favor_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_conversation_id UUID;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    -- Try to find existing conversation
    SELECT id INTO v_conversation_id
    FROM public.conversations
    WHERE (p_ride_id IS NOT NULL AND ride_id = p_ride_id)
       OR (p_favor_id IS NOT NULL AND favor_id = p_favor_id)
    LIMIT 1;

    -- Create if doesn't exist
    IF v_conversation_id IS NULL THEN
        INSERT INTO public.conversations (ride_id, favor_id, created_by)
        VALUES (p_ride_id, p_favor_id, p_user_id)
        RETURNING id INTO v_conversation_id;

        -- Add participants
        IF p_ride_id IS NOT NULL THEN
            INSERT INTO public.conversation_participants (conversation_id, user_id)
            SELECT v_conversation_id, user_id FROM public.rides WHERE id = p_ride_id
            UNION
            SELECT v_conversation_id, claimed_by FROM public.rides WHERE id = p_ride_id AND claimed_by IS NOT NULL;
        ELSIF p_favor_id IS NOT NULL THEN
            INSERT INTO public.conversation_participants (conversation_id, user_id)
            SELECT v_conversation_id, user_id FROM public.favors WHERE id = p_favor_id
            UNION
            SELECT v_conversation_id, claimed_by FROM public.favors WHERE id = p_favor_id AND claimed_by IS NOT NULL;
        END IF;
    END IF;

    RETURN v_conversation_id;
END;
$function$;

-- 9. find_dm_conversation (SEC-5) — require caller to be one of the two participants
CREATE OR REPLACE FUNCTION public.find_dm_conversation(p_user_a uuid, p_user_b uuid)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT cp1.conversation_id
    FROM conversation_participants cp1
    JOIN conversation_participants cp2
        ON cp1.conversation_id = cp2.conversation_id
    WHERE cp1.user_id = p_user_a
      AND cp2.user_id = p_user_b
      AND cp1.left_at IS NULL
      AND cp2.left_at IS NULL
      AND (SELECT auth.uid()) IN (p_user_a, p_user_b)
      AND (
        SELECT COUNT(*)
        FROM conversation_participants cp
        WHERE cp.conversation_id = cp1.conversation_id
          AND cp.left_at IS NULL
      ) = 2
    LIMIT 1;
$function$;

-- 10. Revoke anon EXECUTE on all hardened RPCs (defense in depth; guards already block anon)
REVOKE EXECUTE ON FUNCTION public.get_conversations_with_details(uuid,integer,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.send_reply_message(uuid,uuid,text,uuid,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.remove_conversation_participant(uuid,uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_messages_read(uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_messages_read_batch(uuid[],uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_unread_counts(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_pending_reviews(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_or_create_request_conversation(uuid,uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.find_dm_conversation(uuid,uuid) FROM anon;

-- 11. Guard is_banned in the profiles admin-fields trigger (SEC-4)
CREATE OR REPLACE FUNCTION public.protect_admin_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    -- Only admins can modify is_admin, approved, or is_banned
    IF (OLD.is_admin != NEW.is_admin
        OR OLD.approved != NEW.approved
        OR (OLD.is_banned IS DISTINCT FROM NEW.is_banned)) THEN
        IF NOT (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) THEN
            RAISE EXCEPTION 'Only admins can modify is_admin, approved, or is_banned fields';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

-- 12. Drop the invite-code enumeration policy (SEC-7). Validation flows through the
-- validate_invite_code DEFINER RPC; owners still see their own codes via the other policy.
DROP POLICY IF EXISTS "Users can view unused codes" ON public.invite_codes;
