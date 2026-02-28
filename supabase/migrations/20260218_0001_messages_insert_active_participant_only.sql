-- Require active participation (left_at IS NULL) for inserting messages.
-- Without this, users who have left a conversation could still send messages
-- because the messages INSERT policy only checked existence in conversation_participants.

DROP POLICY IF EXISTS "Users can send messages in their conversations" ON public.messages;

CREATE POLICY "Users can send messages in their conversations" ON public.messages
  FOR INSERT
  WITH CHECK (
    from_id = auth.uid()
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = conversation_id
          AND c.created_by = auth.uid()
      )
      OR
      EXISTS (
        SELECT 1 FROM public.conversation_participants cp
        WHERE cp.conversation_id = conversation_id
          AND cp.user_id = auth.uid()
          AND cp.left_at IS NULL
      )
    )
  );

COMMENT ON POLICY "Users can send messages in their conversations" ON public.messages IS
  'Only conversation creator or active participants (left_at IS NULL) can insert messages.';
