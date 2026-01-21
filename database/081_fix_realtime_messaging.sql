-- Migration: Fix Realtime Messaging
-- Ensures proper configuration for Supabase Realtime to work with messages
-- This includes:
-- 1. Setting REPLICA IDENTITY FULL for realtime to work properly
-- 2. Adding tables to supabase_realtime publication
-- 3. Creating proper RLS policies that allow realtime to broadcast

-- ============================================================================
-- PART 1: Set REPLICA IDENTITY FULL for realtime tables
-- This is REQUIRED for Supabase Realtime to broadcast changes
-- ============================================================================

-- Messages table needs REPLICA IDENTITY FULL for realtime
ALTER TABLE public.messages REPLICA IDENTITY FULL;

-- Conversations table for realtime updates
ALTER TABLE public.conversations REPLICA IDENTITY FULL;

-- Notifications table for realtime
ALTER TABLE public.notifications REPLICA IDENTITY FULL;

-- ============================================================================
-- PART 2: Add tables to supabase_realtime publication
-- Tables must be in this publication for realtime to work
-- ============================================================================

-- Check if publication exists and add tables
DO $$
BEGIN
    -- Add messages to realtime publication if not already there
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
        RAISE NOTICE 'Added messages to supabase_realtime publication';
    END IF;
    
    -- Add conversations to realtime publication
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'conversations'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
        RAISE NOTICE 'Added conversations to supabase_realtime publication';
    END IF;
    
    -- Add notifications to realtime publication
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
        RAISE NOTICE 'Added notifications to supabase_realtime publication';
    END IF;
    
    -- Add notification_queue to realtime publication
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'notification_queue'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_queue;
        RAISE NOTICE 'Added notification_queue to supabase_realtime publication';
    END IF;
EXCEPTION
    WHEN undefined_object THEN
        -- Publication doesn't exist, create it
        CREATE PUBLICATION supabase_realtime FOR TABLE 
            public.messages, 
            public.conversations, 
            public.notifications,
            public.notification_queue;
        RAISE NOTICE 'Created supabase_realtime publication with tables';
END $$;

-- ============================================================================
-- PART 3: Ensure RLS policies allow SELECT for realtime broadcasts
-- Realtime uses RLS to filter which users receive broadcasts
-- ============================================================================

-- Drop and recreate messages SELECT policy to ensure it works with realtime
-- The policy must allow SELECT for users who are conversation participants
DROP POLICY IF EXISTS "messages_select_creator" ON public.messages;
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;

-- Create a policy that allows participants to see messages
-- This is checked by Supabase Realtime to determine who gets broadcasts
CREATE POLICY "messages_select_for_participants" ON public.messages
    FOR SELECT 
    USING (
        -- User is the conversation creator
        EXISTS (
            SELECT 1 FROM public.conversations c
            WHERE c.id = messages.conversation_id
            AND c.created_by = auth.uid()
        )
        OR
        -- User is a conversation participant
        EXISTS (
            SELECT 1 FROM public.conversation_participants cp
            WHERE cp.conversation_id = messages.conversation_id
            AND cp.user_id = auth.uid()
        )
    );

-- Ensure INSERT policy exists
DROP POLICY IF EXISTS "messages_insert_creator" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

CREATE POLICY "messages_insert_for_participants" ON public.messages
    FOR INSERT 
    WITH CHECK (
        auth.uid() = from_id
        AND (
            -- User is the conversation creator
            EXISTS (
                SELECT 1 FROM public.conversations c
                WHERE c.id = conversation_id
                AND c.created_by = auth.uid()
            )
            OR
            -- User is a conversation participant
            EXISTS (
                SELECT 1 FROM public.conversation_participants cp
                WHERE cp.conversation_id = conversation_id
                AND cp.user_id = auth.uid()
            )
        )
    );

-- Ensure UPDATE policy exists for read_by updates
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_update_read_by" ON public.messages;

CREATE POLICY "messages_update_for_participants" ON public.messages
    FOR UPDATE 
    USING (
        -- User is the conversation creator
        EXISTS (
            SELECT 1 FROM public.conversations c
            WHERE c.id = messages.conversation_id
            AND c.created_by = auth.uid()
        )
        OR
        -- User is a conversation participant
        EXISTS (
            SELECT 1 FROM public.conversation_participants cp
            WHERE cp.conversation_id = messages.conversation_id
            AND cp.user_id = auth.uid()
        )
    )
    WITH CHECK (
        -- User is the conversation creator
        EXISTS (
            SELECT 1 FROM public.conversations c
            WHERE c.id = conversation_id
            AND c.created_by = auth.uid()
        )
        OR
        -- User is a conversation participant
        EXISTS (
            SELECT 1 FROM public.conversation_participants cp
            WHERE cp.conversation_id = conversation_id
            AND cp.user_id = auth.uid()
        )
    );

-- ============================================================================
-- PART 4: Ensure notifications RLS allows SELECT for the user
-- ============================================================================

-- Drop and recreate notifications SELECT policy
DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;

CREATE POLICY "notifications_select_own" ON public.notifications
    FOR SELECT 
    USING (user_id = auth.uid());

-- Ensure INSERT is allowed (for triggers/functions)
DROP POLICY IF EXISTS "notifications_insert_system" ON public.notifications;

-- Allow inserts from authenticated users (triggers run as SECURITY DEFINER)
CREATE POLICY "notifications_insert_authenticated" ON public.notifications
    FOR INSERT 
    WITH CHECK (true);  -- Triggers use SECURITY DEFINER, so this is safe

-- Allow UPDATE for marking as read
DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;

CREATE POLICY "notifications_update_own" ON public.notifications
    FOR UPDATE 
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ============================================================================
-- PART 5: Create index for faster realtime filtering
-- ============================================================================

-- Index for faster participant lookups (used by RLS and realtime)
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_conv 
ON public.conversation_participants(user_id, conversation_id);

-- Index for faster message lookups by conversation
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created 
ON public.messages(conversation_id, created_at DESC);

-- Index for notifications by user
CREATE INDEX IF NOT EXISTS idx_notifications_user_created 
ON public.notifications(user_id, created_at DESC);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON POLICY "messages_select_for_participants" ON public.messages IS 
    'Allows conversation participants to see messages. Required for Supabase Realtime broadcasts.';
COMMENT ON POLICY "messages_insert_for_participants" ON public.messages IS 
    'Allows conversation participants to send messages.';
COMMENT ON POLICY "messages_update_for_participants" ON public.messages IS 
    'Allows conversation participants to update messages (e.g., mark as read).';

