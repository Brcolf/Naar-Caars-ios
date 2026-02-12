-- Migration: Disable legacy queue-based message push trigger
-- Context:
-- - `message_push_webhook` is the authoritative message push pipeline.
-- - `on_message_inserted_push` (notify_message_push) writes queue rows that are
--   not used for delivery in the current setup and can add write/load overhead.
-- - Disable the legacy trigger to reduce duplicated work on message inserts.

DROP TRIGGER IF EXISTS on_message_inserted_push ON public.messages;

-- Mark already-processed legacy message queue rows as sent so they stop showing
-- up as unsent backlog in diagnostics.
UPDATE public.notification_queue
SET sent_at = NOW()
WHERE sent_at IS NULL
  AND processed_at IS NOT NULL
  AND notification_type IN ('message', 'added_to_conversation');
