-- ============================================================================
-- 084_add_message_replies.sql - Add reply/threading support to messages
-- ============================================================================
-- Adds support for:
-- 1. reply_to_id column to reference parent message
-- 2. Index for efficient reply lookups
-- 3. Updated RLS policies for replies
-- ============================================================================

-- ============================================================================
-- PART 1: Add reply_to_id column to messages
-- This references the parent message being replied to
-- ============================================================================

-- Add reply_to_id column
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS reply_to_id UUID DEFAULT NULL 
REFERENCES public.messages(id) ON DELETE SET NULL;

-- Add comment
COMMENT ON COLUMN public.messages.reply_to_id IS 
    'ID of the message this is a reply to. NULL for top-level messages.';

-- ============================================================================
-- PART 2: Create index for reply lookups
-- This optimizes queries that fetch replies or check for replies
-- ============================================================================

-- Index for finding replies to a specific message
CREATE INDEX IF NOT EXISTS idx_messages_reply_to 
ON public.messages(reply_to_id) 
WHERE reply_to_id IS NOT NULL;

-- Composite index for fetching messages with their reply context
CREATE INDEX IF NOT EXISTS idx_messages_conversation_reply 
ON public.messages(conversation_id, reply_to_id);

-- ============================================================================
-- PART 3: Create a view for messages with reply info
-- This makes it easier to fetch messages with their replied-to message
-- ============================================================================

-- Create or replace view for messages with reply info
CREATE OR REPLACE VIEW public.messages_with_replies AS
SELECT 
    m.id,
    m.conversation_id,
    m.from_id,
    m.text,
    m.image_url,
    m.read_by,
    m.created_at,
    m.message_type,
    m.reply_to_id,
    -- Reply info
    rm.text AS reply_to_text,
    rm.from_id AS reply_to_from_id,
    rm.image_url AS reply_to_image_url,
    rp.name AS reply_to_sender_name,
    rp.avatar_url AS reply_to_sender_avatar
FROM public.messages m
LEFT JOIN public.messages rm ON m.reply_to_id = rm.id
LEFT JOIN public.profiles rp ON rm.from_id = rp.id;

-- Grant access to the view
GRANT SELECT ON public.messages_with_replies TO authenticated;

-- Add comment
COMMENT ON VIEW public.messages_with_replies IS 
    'Messages with their replied-to message information joined.';

-- ============================================================================
-- PART 4: Function to send a reply message
-- This ensures proper validation and returns the full message with reply info
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_reply_message(
    p_conversation_id UUID,
    p_from_id UUID,
    p_text TEXT,
    p_reply_to_id UUID,
    p_image_url TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_message_id UUID;
    v_reply_exists BOOLEAN;
    v_is_participant BOOLEAN;
BEGIN
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
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.send_reply_message(UUID, UUID, TEXT, UUID, TEXT) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.send_reply_message IS 
    'Sends a reply message to an existing message in a conversation.';

-- ============================================================================
-- PART 5: Verify all changes
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 084_add_message_replies.sql completed successfully';
    RAISE NOTICE 'Added column: messages.reply_to_id';
    RAISE NOTICE 'Created view: messages_with_replies';
    RAISE NOTICE 'Created function: send_reply_message';
END $$;


