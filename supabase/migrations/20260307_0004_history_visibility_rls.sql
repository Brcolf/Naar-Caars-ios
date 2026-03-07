-- Drop existing SELECT policy on messages
DROP POLICY IF EXISTS "messages_select_for_participants" ON public.messages;

-- Recreate with joined_at visibility boundary
-- Users can see messages if:
--   1. They are the conversation creator, OR
--   2. They are a participant AND the message was created after their joined_at timestamp
CREATE POLICY "messages_select_for_participants" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND c.created_by = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
        AND cp.user_id = auth.uid()
        AND messages.created_at >= cp.joined_at
    )
  );
