-- Migration: Performance indexes for badge counts and conversation list hot paths
--
-- Scope:
-- - Accelerate badge counts RPC unread notification filtering (user_id + read + type)
-- - Improve notification type-specific queries with ordering
-- - Speed up conversations RPC ownership lookup with sort ordering
--
-- Safety:
-- - Additive only (no table/column/policy drops)
-- - No RLS policy changes
-- - IF NOT EXISTS guards prevent errors on re-run

-- Badge counts RPC: the get_badge_counts function filters notifications by
-- user_id, read status, and type simultaneously. The existing (user_id, read)
-- index lacks the type column, forcing a filter scan over all unread rows.
CREATE INDEX IF NOT EXISTS idx_notifications_user_read_type
ON public.notifications (user_id, read, type);

-- Notification type + recency queries used for bell badge grouping and
-- type-specific feed ordering across the notifications list.
CREATE INDEX IF NOT EXISTS idx_notifications_user_type_created
ON public.notifications (user_id, type, created_at DESC);

-- Conversations RPC: the get_conversations_with_details function unions
-- participant-based and creator-based conversation sets, then orders by
-- updated_at DESC. This composite covers the creator branch with ordering.
CREATE INDEX IF NOT EXISTS idx_conversations_created_by_updated
ON public.conversations (created_by, updated_at DESC);
