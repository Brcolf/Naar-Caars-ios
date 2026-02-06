-- Audit log for message edit/unsend operations
-- Tracks content modifications for accountability

CREATE TABLE IF NOT EXISTS public.message_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('edit', 'unsend')),
    message_id UUID NOT NULL,
    old_content TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for querying by user
CREATE INDEX IF NOT EXISTS idx_message_audit_log_user_id ON public.message_audit_log(user_id);

-- Index for querying by message
CREATE INDEX IF NOT EXISTS idx_message_audit_log_message_id ON public.message_audit_log(message_id);

-- RLS: users can read their own audit entries
ALTER TABLE public.message_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_log_select_own" ON public.message_audit_log
    FOR SELECT USING (user_id = auth.uid());

-- Only service role can insert (via RPC functions)
CREATE POLICY "audit_log_insert_service" ON public.message_audit_log
    FOR INSERT WITH CHECK (auth.role() = 'service_role');

-- Update edit_message and unsend_message RPCs to log to audit table
CREATE OR REPLACE FUNCTION public.edit_message(
    p_message_id uuid,
    p_new_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_content TEXT;
BEGIN
    -- Verify the caller is the message sender
    SELECT text INTO v_old_content
    FROM public.messages
    WHERE id = p_message_id
      AND from_id = auth.uid()
      AND deleted_at IS NULL;

    IF v_old_content IS NULL THEN
        RAISE EXCEPTION 'Message not found or you are not the sender';
    END IF;

    -- Log the edit
    INSERT INTO public.message_audit_log (user_id, action, message_id, old_content)
    VALUES (auth.uid(), 'edit', p_message_id, v_old_content);

    -- Perform the edit
    UPDATE public.messages
    SET text = p_new_content,
        edited_at = now()
    WHERE id = p_message_id
      AND from_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.unsend_message(
    p_message_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_created_at timestamptz;
    v_old_content TEXT;
BEGIN
    -- Get the message creation time, content, and verify ownership
    SELECT created_at, text INTO v_created_at, v_old_content
    FROM public.messages
    WHERE id = p_message_id
      AND from_id = auth.uid()
      AND deleted_at IS NULL;

    IF v_created_at IS NULL THEN
        RAISE EXCEPTION 'Message not found or you are not the sender';
    END IF;

    -- Enforce 15-minute window
    IF now() - v_created_at > interval '15 minutes' THEN
        RAISE EXCEPTION 'Messages can only be unsent within 15 minutes of sending';
    END IF;

    -- Log the unsend
    INSERT INTO public.message_audit_log (user_id, action, message_id, old_content)
    VALUES (auth.uid(), 'unsend', p_message_id, v_old_content);

    -- Perform the unsend
    UPDATE public.messages
    SET text = '',
        deleted_at = now()
    WHERE id = p_message_id
      AND from_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unsend_message(uuid) TO authenticated;
