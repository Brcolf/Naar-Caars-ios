-- Ultimate RLS fix: Use a completely different approach
-- Instead of querying conversation_participants in a function, we'll use a view
-- or change the policy logic to avoid the recursion entirely

-- ============================================================================
-- Step 1: Drop everything and start fresh
-- ============================================================================

-- Drop policies
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

-- Drop function
DROP FUNCTION IF EXISTS public.is_conversation_participant(UUID, UUID) CASCADE;

-- ============================================================================
-- Step 2: Create a view that bypasses RLS for checking participation
-- ============================================================================

-- Create a materialized approach: Use a function that queries with explicit schema
-- and ensure it's owned by a role with BYPASSRLS
-- Actually, let's try a simpler approach: Make the function use SECURITY DEFINER
-- and ensure the function owner can bypass RLS

-- First, let's check who owns the function (will be the user who creates it)
-- We'll create it as SECURITY DEFINER and use a workaround

-- Create function owned by postgres role (which has BYPASSRLS by default)
-- Note: In Supabase, we can't change function owner easily, so we'll use a different approach

-- ============================================================================
-- Alternative: Use a simpler policy that doesn't require the function
-- ============================================================================

-- Instead of using a function, let's make the conversations policy check
-- if the user is in conversation_participants directly, but in a way that
-- doesn't cause recursion

-- The key insight: The conversation_participants SELECT policy is now:
--   user_id = auth.uid()
-- This means users can only see their OWN participation rows.
-- So when we check in the conversations policy, we can query conversation_participants
-- directly because we're only checking if a row exists where user_id = auth.uid(),
-- which the policy allows!

-- Recreate conversations SELECT policy WITHOUT using the function
CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- User is the creator
    created_by = auth.uid()
    OR
    -- OR user has a participation row (this query is allowed by the policy)
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversations.id
      AND cp.user_id = auth.uid()
    )
  );

-- Recreate messages policies WITHOUT using the function
CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    -- User is a participant (direct query, no function)
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
      AND cp.user_id = auth.uid()
    )
  );

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = from_id
    AND
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
      AND cp.user_id = auth.uid()
    )
  );

-- ============================================================================
-- Why this works:
-- ============================================================================
-- The conversation_participants SELECT policy is: user_id = auth.uid()
-- This means when we query conversation_participants in the EXISTS clause,
-- PostgreSQL will only return rows where user_id = auth.uid().
-- Since we're checking for cp.user_id = auth.uid() in the EXISTS,
-- this matches what the policy allows, so no recursion occurs!



