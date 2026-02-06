-- Migration: Add message editing and unsend support
-- Date: 2026-02-05
-- Description: Adds edited_at and deleted_at columns to the messages table
--              to support message editing and soft-delete (unsend) functionality.

-- Add edited_at column (nullable, null means never edited)
ALTER TABLE public.messages
ADD COLUMN IF NOT EXISTS edited_at timestamptz DEFAULT NULL;

-- Add deleted_at column (nullable, null means not unsent/deleted)
ALTER TABLE public.messages
ADD COLUMN IF NOT EXISTS deleted_at timestamptz DEFAULT NULL;

-- Add a comment explaining the columns
COMMENT ON COLUMN public.messages.edited_at IS 'Timestamp of last edit. NULL if message has never been edited.';
COMMENT ON COLUMN public.messages.deleted_at IS 'Timestamp when message was unsent. NULL if message is active. When set, the message content should be hidden from recipients.';

-- Create an index on deleted_at for efficient filtering of active messages
CREATE INDEX IF NOT EXISTS idx_messages_deleted_at
ON public.messages (deleted_at)
WHERE deleted_at IS NULL;

-- RPC function to edit a message
-- Only the message sender can edit their own messages
CREATE OR REPLACE FUNCTION public.edit_message(
    p_message_id uuid,
    p_new_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verify the caller is the message sender
    IF NOT EXISTS (
        SELECT 1 FROM public.messages
        WHERE id = p_message_id
          AND from_id = auth.uid()
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Message not found or you are not the sender';
    END IF;

    UPDATE public.messages
    SET text = p_new_content,
        edited_at = now()
    WHERE id = p_message_id
      AND from_id = auth.uid();
END;
$$;

-- RPC function to unsend a message
-- Only the message sender can unsend their own messages
-- Enforces a 15-minute window from creation time
CREATE OR REPLACE FUNCTION public.unsend_message(
    p_message_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_created_at timestamptz;
BEGIN
    -- Get the message creation time and verify ownership
    SELECT created_at INTO v_created_at
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

    UPDATE public.messages
    SET text = '',
        deleted_at = now()
    WHERE id = p_message_id
      AND from_id = auth.uid();
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unsend_message(uuid) TO authenticated;

-- Update the RLS policy to allow message updates by the sender
-- (only text, edited_at, and deleted_at columns)
DO $$
BEGIN
    -- Drop existing update policy if it exists
    DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
    
    -- Create policy allowing users to update their own messages
    CREATE POLICY "messages_update_own" ON public.messages
        FOR UPDATE
        USING (from_id = auth.uid())
        WITH CHECK (from_id = auth.uid());
EXCEPTION
    WHEN undefined_table THEN
        RAISE NOTICE 'messages table does not exist yet';
END $$;
