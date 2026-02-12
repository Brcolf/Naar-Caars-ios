-- Migration: Performance indexes for messaging search and badge/notification hot paths
--
-- Scope:
-- - Accelerate exact-substring message search (%query%) with pg_trgm
-- - Reduce latency for unread/badge queries over messages.read_by
-- - Improve bell/notification list ordering and request-scoped unread updates
--
-- Safety:
-- - Additive only (no table/column/policy drops)
-- - No RLS policy changes

-- Enable trigram support for ILIKE '%...%' search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Message search: supports substring search used by in-app/global message search.
CREATE INDEX IF NOT EXISTS idx_messages_text_trgm
ON public.messages
USING GIN (text gin_trgm_ops);

-- Unread checks repeatedly evaluate read_by containment; GIN helps @> filters.
CREATE INDEX IF NOT EXISTS idx_messages_read_by_gin
ON public.messages
USING GIN (read_by);

-- Bell feed ordering path (non-message notifications sorted by pinned + recency).
CREATE INDEX IF NOT EXISTS idx_notifications_bell_user_pinned_created
ON public.notifications (user_id, pinned DESC, created_at DESC)
WHERE type <> 'message' AND type <> 'added_to_conversation';

-- Request-scoped unread paths used for mark-read and request badge summaries.
CREATE INDEX IF NOT EXISTS idx_notifications_unread_user_ride_created
ON public.notifications (user_id, ride_id, created_at DESC)
WHERE read = false AND ride_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_unread_user_favor_created
ON public.notifications (user_id, favor_id, created_at DESC)
WHERE read = false AND favor_id IS NOT NULL;
