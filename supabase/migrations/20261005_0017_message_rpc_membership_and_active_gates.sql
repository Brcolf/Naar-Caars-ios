-- 20261005_0017_message_rpc_membership_and_active_gates.sql
--
-- APPLIED 2026-10-05 (Supabase MCP, one function per call) and verified with rolled-back probes.
--
-- 1. mark_messages_read / mark_messages_read_batch checked only auth.uid() = p_user_id. Any
--    signed-in user could append their id to read_by on messages in conversations they are not
--    in, which the client renders as a "Read" receipt and which realtime broadcasts. Membership
--    is now checked per row: a non-member matches nothing; an active member behaves as before
--    (the single-conversation variant still marks the whole conversation, which late joiners
--    need to clear pre-join unread counts); a member who left can only stamp messages sent up to
--    left_at, which the messages SELECT policy still shows them. The read_by test is NULL-safe
--    in both.
-- 2. send_reply_message is SECURITY DEFINER, so it bypassed the messages INSERT policy's
--    is_active_user() gate: an unapproved or banned account that was still a participant could
--    keep sending through the RPC. It now applies the same gate.
--
-- Probes (begin/rollback as authenticated): member send_reply returns an id; member mark-read
-- clears the conversation; mark_messages_read on a foreign conversation and a batch containing
-- three foreign message ids leave read_by untouched while the caller's own message is marked.

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
    -- Membership is checked per row: a non-member matches nothing; an active member marks the
    -- whole conversation (unchanged); a member who left may only mark messages sent up to
    -- left_at, which the messages SELECT policy still shows them.
    UPDATE public.messages m
    SET read_by = array_append(COALESCE(m.read_by, ARRAY[]::uuid[]), p_user_id)
    WHERE m.conversation_id = p_conversation_id
      AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[p_user_id])
      AND EXISTS (
          SELECT 1
          FROM public.conversation_participants cp
          WHERE cp.conversation_id = m.conversation_id
            AND cp.user_id = p_user_id
            AND (cp.left_at IS NULL OR m.created_at <= cp.left_at)
      );
END;
$function$;

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
    -- Same per-row membership rule as mark_messages_read: only messages in conversations the
    -- caller belongs to (and, for a member who left, only those sent up to left_at).
    UPDATE public.messages m
    SET read_by = array_append(COALESCE(m.read_by, ARRAY[]::uuid[]), p_user_id)
    WHERE m.id = ANY(p_message_ids)
      AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[p_user_id])
      AND EXISTS (
          SELECT 1
          FROM public.conversation_participants cp
          WHERE cp.conversation_id = m.conversation_id
            AND cp.user_id = p_user_id
            AND (cp.left_at IS NULL OR m.created_at <= cp.left_at)
      );
END;
$function$;

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
    -- Same gate as the messages INSERT policy: unapproved or banned accounts cannot send.
    -- (This function is SECURITY DEFINER, so the policy itself is bypassed here.)
    IF NOT COALESCE(public.is_active_user(p_from_id), false) THEN
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
