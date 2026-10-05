-- 20260717213209_20260717_0005_drop_duplicate_indexes.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- PERF-3: drop exact-duplicate indexes (verified identical definitions). The retained
-- index in each pair provides identical coverage, so this only reduces write amplification.
DROP INDEX IF EXISTS public.idx_notifications_read;          -- identical to idx_notifications_user_read (user_id, read)
DROP INDEX IF EXISTS public.push_tokens_user_device_idx;      -- identical UNIQUE to push_tokens_user_id_device_id_key
