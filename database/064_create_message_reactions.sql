-- ============================================================================
-- 064_create_message_reactions.sql - Create message_reactions table
-- ============================================================================
-- Creates message_reactions table to support reactions on messages
-- Reactions: 👍 👎 ❤️ 😂 ‼️ and "HaHa" text
-- ============================================================================

-- Create message_reactions table
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reaction TEXT NOT NULL CHECK (reaction IN ('👍', '👎', '❤️', '😂', '‼️', 'HaHa')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Prevent duplicate reactions from same user on same message
    UNIQUE(message_id, user_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON public.message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id ON public.message_reactions(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_reaction ON public.message_reactions(reaction);

-- Enable Row Level Security
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for message_reactions

-- SELECT: Users can see reactions on messages in conversations they're part of
CREATE POLICY message_reactions_select
ON public.message_reactions
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.messages m
        JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
        WHERE m.id = message_reactions.message_id
        AND cp.user_id = auth.uid()
    )
);

-- INSERT: Users can add reactions to messages in conversations they're part of
CREATE POLICY message_reactions_insert
ON public.message_reactions
FOR INSERT
WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM public.messages m
        JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
        WHERE m.id = message_reactions.message_id
        AND cp.user_id = auth.uid()
    )
);

-- UPDATE: Users can only update their own reactions
CREATE POLICY message_reactions_update
ON public.message_reactions
FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- DELETE: Users can only delete their own reactions
CREATE POLICY message_reactions_delete
ON public.message_reactions
FOR DELETE
USING (user_id = auth.uid());

-- Add comment
COMMENT ON TABLE public.message_reactions IS 'Reactions on messages. Supported reactions: 👍 👎 ❤️ 😂 ‼️ and HaHa (text).';

