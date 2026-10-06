-- 20261005_0023_edit_message_active_member_gate.sql
--
-- APPLIED 2026-10-05 (Supabase MCP) and verified with a rolled-back probe.
--
-- edit_message() checked only that the caller sent the message. It is SECURITY DEFINER, so the
-- messages INSERT policy's gates did not apply: a banned user, or one who had left or been
-- removed from the conversation, could still rewrite every message they had ever sent there,
-- and anyone could rewrite the text of the system announcements recorded under their id. It now
-- applies the INSERT policy's gates (active account; active member or conversation creator) and
-- refuses system messages.
--
-- Probe (begin/rollback): the sender's own text message is edited and edited_at is set; another
-- member's message and the sender's own system message are rejected.

CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid, p_new_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    -- Same gates as the messages INSERT policy: an approved, unbanned account that is still an
    -- active member of the conversation (or its creator). System messages are not editable.
    IF auth.uid() IS NULL OR NOT COALESCE(public.is_active_user(auth.uid()), false) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.messages m
        WHERE m.id = p_message_id
          AND m.from_id = auth.uid()
          AND m.deleted_at IS NULL
          AND COALESCE(m.message_type, 'text') <> 'system'
          AND (
              EXISTS (
                  SELECT 1 FROM public.conversation_participants cp
                  WHERE cp.conversation_id = m.conversation_id
                    AND cp.user_id = auth.uid()
                    AND cp.left_at IS NULL
              )
              OR EXISTS (
                  SELECT 1 FROM public.conversations c
                  WHERE c.id = m.conversation_id
                    AND c.created_by = auth.uid()
              )
          )
    ) THEN
        RAISE EXCEPTION 'Message not found or you are not the sender';
    END IF;

    UPDATE public.messages
    SET text = p_new_content,
        edited_at = now()
    WHERE id = p_message_id
      AND from_id = auth.uid();
END;
$function$;
