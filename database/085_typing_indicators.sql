-- ============================================================================
-- 085_typing_indicators.sql - Real-time typing indicators
-- ============================================================================
-- Adds support for:
-- 1. Typing status table with automatic cleanup
-- 2. RLS policies for typing indicators
-- 3. Functions for updating and querying typing status
-- ============================================================================

-- ============================================================================
-- PART 1: Create typing_indicators table
-- Ephemeral table that tracks who is currently typing in each conversation
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.typing_indicators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Unique constraint: one typing record per user per conversation
    CONSTRAINT unique_typing_per_user_conversation UNIQUE (conversation_id, user_id)
);

-- Add comments
COMMENT ON TABLE public.typing_indicators IS 
    'Ephemeral table tracking users currently typing in conversations.';
COMMENT ON COLUMN public.typing_indicators.started_at IS 
    'When the user started typing. Records older than 5 seconds are considered stale.';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_typing_indicators_conversation 
ON public.typing_indicators(conversation_id);

CREATE INDEX IF NOT EXISTS idx_typing_indicators_started_at 
ON public.typing_indicators(started_at);

-- ============================================================================
-- PART 2: Enable RLS and create policies
-- ============================================================================

ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- Policy: Users can see typing indicators in conversations they're part of
CREATE POLICY "Users can view typing in their conversations"
ON public.typing_indicators FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversation_participants cp
        WHERE cp.conversation_id = typing_indicators.conversation_id
        AND cp.user_id = auth.uid()
        AND cp.left_at IS NULL
    )
);

-- Policy: Users can insert their own typing indicator
CREATE POLICY "Users can insert own typing indicator"
ON public.typing_indicators FOR INSERT
TO authenticated
WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
        SELECT 1 FROM public.conversation_participants cp
        WHERE cp.conversation_id = typing_indicators.conversation_id
        AND cp.user_id = auth.uid()
        AND cp.left_at IS NULL
    )
);

-- Policy: Users can update their own typing indicator
CREATE POLICY "Users can update own typing indicator"
ON public.typing_indicators FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Policy: Users can delete their own typing indicator
CREATE POLICY "Users can delete own typing indicator"
ON public.typing_indicators FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- ============================================================================
-- PART 3: Enable Realtime for typing_indicators
-- ============================================================================

-- Enable realtime for the table
ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;

-- Set replica identity for realtime updates
ALTER TABLE public.typing_indicators REPLICA IDENTITY FULL;

-- ============================================================================
-- PART 4: Function to set typing status
-- Upserts the typing indicator with current timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_typing_status(
    p_conversation_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_participant BOOLEAN;
BEGIN
    -- Check if user is a participant
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
        AND left_at IS NULL
    ) INTO v_is_participant;
    
    IF NOT v_is_participant THEN
        RETURN FALSE;
    END IF;
    
    -- Upsert typing indicator
    INSERT INTO typing_indicators (conversation_id, user_id, started_at)
    VALUES (p_conversation_id, p_user_id, NOW())
    ON CONFLICT (conversation_id, user_id)
    DO UPDATE SET started_at = NOW();
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_typing_status(UUID, UUID) TO authenticated;

COMMENT ON FUNCTION public.set_typing_status IS 
    'Sets or updates typing status for a user in a conversation.';

-- ============================================================================
-- PART 5: Function to clear typing status
-- Removes the typing indicator when user stops typing or sends message
-- ============================================================================

CREATE OR REPLACE FUNCTION public.clear_typing_status(
    p_conversation_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM typing_indicators
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.clear_typing_status(UUID, UUID) TO authenticated;

COMMENT ON FUNCTION public.clear_typing_status IS 
    'Clears typing status for a user in a conversation.';

-- ============================================================================
-- PART 6: Function to get active typing users
-- Returns users who started typing within the last 5 seconds
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_typing_users(
    p_conversation_id UUID
)
RETURNS TABLE (
    user_id UUID,
    user_name TEXT,
    avatar_url TEXT,
    started_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ti.user_id,
        p.name AS user_name,
        p.avatar_url,
        ti.started_at
    FROM typing_indicators ti
    JOIN profiles p ON ti.user_id = p.id
    WHERE ti.conversation_id = p_conversation_id
    AND ti.started_at > NOW() - INTERVAL '5 seconds'
    AND ti.user_id != auth.uid(); -- Don't include current user
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_typing_users(UUID) TO authenticated;

COMMENT ON FUNCTION public.get_typing_users IS 
    'Gets users currently typing in a conversation (within last 5 seconds).';

-- ============================================================================
-- PART 7: Automatic cleanup of stale typing indicators
-- Removes indicators older than 10 seconds
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cleanup_stale_typing_indicators()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM typing_indicators
    WHERE started_at < NOW() - INTERVAL '10 seconds';
    
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_stale_typing_indicators() TO authenticated;

COMMENT ON FUNCTION public.cleanup_stale_typing_indicators IS 
    'Removes typing indicators older than 10 seconds. Can be called periodically or via cron.';

-- Schedule cleanup job (if pg_cron is available)
-- This runs every 30 seconds to clean up stale typing indicators
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'cleanup-typing-indicators',
            '30 seconds',
            'SELECT public.cleanup_stale_typing_indicators();'
        );
    END IF;
EXCEPTION
    WHEN undefined_function THEN
        RAISE NOTICE 'pg_cron not available - skipping cleanup job scheduling';
END $$;

-- ============================================================================
-- PART 8: Verify changes
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 085_typing_indicators.sql completed successfully';
    RAISE NOTICE 'Created table: typing_indicators';
    RAISE NOTICE 'Created functions: set_typing_status, clear_typing_status, get_typing_users, cleanup_stale_typing_indicators';
END $$;

