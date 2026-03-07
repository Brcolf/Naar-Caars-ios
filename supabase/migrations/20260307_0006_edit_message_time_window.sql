-- Add 15-minute time window to edit_message (matching unsend_message)
CREATE OR REPLACE FUNCTION public.edit_message(
    p_message_id uuid,
    p_new_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_created_at timestamptz;
BEGIN
    SELECT created_at INTO v_created_at
    FROM public.messages
    WHERE id = p_message_id
      AND from_id = auth.uid()
      AND deleted_at IS NULL;

    IF v_created_at IS NULL THEN
        RAISE EXCEPTION 'Message not found or you are not the sender';
    END IF;

    IF now() - v_created_at > interval '15 minutes' THEN
        RAISE EXCEPTION 'Messages can only be edited within 15 minutes of sending';
    END IF;

    INSERT INTO public.message_audit_log (id, user_id, action, message_id, old_content, created_at)
    SELECT gen_random_uuid(), auth.uid(), 'edit', p_message_id, text, now()
    FROM public.messages WHERE id = p_message_id;

    UPDATE public.messages
    SET text = p_new_content,
        edited_at = now()
    WHERE id = p_message_id
      AND from_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;
