-- Migration: Force-disable legacy queue-based message push trigger
-- Why:
-- - Some environments still show `on_message_inserted_push` as enabled.
-- - That trigger writes notification_queue rows that are not the active delivery path.
-- - Keeping it enabled causes duplicate queue load and confusing "sent_at = null" diagnostics.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'on_message_inserted_push'
      AND tgrelid = 'public.messages'::regclass
      AND NOT tgisinternal
  ) THEN
    EXECUTE 'ALTER TABLE public.messages DISABLE TRIGGER on_message_inserted_push';
  END IF;
END
$$;

DROP TRIGGER IF EXISTS on_message_inserted_push ON public.messages;

-- Normalize legacy queue rows created by the disabled path so diagnostics are clean.
UPDATE public.notification_queue
SET sent_at = COALESCE(sent_at, processed_at, NOW())
WHERE sent_at IS NULL
  AND processed_at IS NOT NULL
  AND notification_type IN ('message', 'added_to_conversation');
