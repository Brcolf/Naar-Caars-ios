-- ============================================================================
-- Verify and Create Message Reactions Table
-- ============================================================================
-- This migration ensures the message_reactions table exists with proper schema
-- Based on migration 064 but with verification
-- ============================================================================

-- Create table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reaction TEXT NOT NULL CHECK (reaction IN ('👍', '👎', '❤️', '😂', '‼️', 'HaHa')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Unique constraint: One reaction per user per message
    UNIQUE(message_id, user_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id 
  ON public.message_reactions(message_id);

CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id 
  ON public.message_reactions(user_id);

-- Enable RLS
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "reactions_select_all" ON public.message_reactions;
DROP POLICY IF EXISTS "reactions_insert_own" ON public.message_reactions;
DROP POLICY IF EXISTS "reactions_update_own" ON public.message_reactions;
DROP POLICY IF EXISTS "reactions_delete_own" ON public.message_reactions;

-- SELECT: Anyone can see reactions (they're public within conversations)
CREATE POLICY "reactions_select_all" ON public.message_reactions
  FOR SELECT 
  USING (true);

-- INSERT: Users can add their own reactions
CREATE POLICY "reactions_insert_own" ON public.message_reactions
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

-- UPDATE: Users can update their own reactions (change emoji)
CREATE POLICY "reactions_update_own" ON public.message_reactions
  FOR UPDATE 
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- DELETE: Users can delete their own reactions
CREATE POLICY "reactions_delete_own" ON public.message_reactions
  FOR DELETE 
  USING (user_id = auth.uid());

-- Add comment
COMMENT ON TABLE public.message_reactions IS 
'Message reactions (emoji responses). Valid reactions: 👍 👎 ❤️ 😂 ‼️ HaHa';

-- ============================================================================
-- Verification Query
-- ============================================================================
-- Run this to verify table structure:
-- SELECT column_name, data_type, is_nullable 
-- FROM information_schema.columns 
-- WHERE table_name = 'message_reactions';

