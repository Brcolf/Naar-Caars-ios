-- 20260207065317_conversation_and_badge_hot_indexes.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Performance indexes for badge counts and conversation list hot paths

-- Badge counts RPC: composite for unread notification filtering
CREATE INDEX IF NOT EXISTS idx_notifications_user_read_type
ON public.notifications (user_id, read, type);

-- Notification type + recency queries for bell badge grouping
CREATE INDEX IF NOT EXISTS idx_notifications_user_type_created
ON public.notifications (user_id, type, created_at DESC);

-- Conversations RPC: creator branch with updated_at ordering
CREATE INDEX IF NOT EXISTS idx_conversations_created_by_updated
ON public.conversations (created_by, updated_at DESC);