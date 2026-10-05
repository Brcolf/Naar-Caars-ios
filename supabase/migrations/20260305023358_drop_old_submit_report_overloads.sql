-- 20260305023358_drop_old_submit_report_overloads.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Drop the old submit_report overloads that conflict with our new 7-param version.
-- The old 5-param version (reporter, user, message, type, description) and the
-- intermediate 7-param version with different parameter order need to go.

-- Drop the 5-param version
DROP FUNCTION IF EXISTS public.submit_report(UUID, UUID, UUID, TEXT, TEXT);

-- Drop the old 7-param version with wrong parameter order (post_id, comment_id, type, description)
-- Our version has order: reporter, user, message, post, comment, type, description
-- The old one has: reporter, user, message, type, description, post, comment
DROP FUNCTION IF EXISTS public.submit_report(UUID, UUID, UUID, TEXT, TEXT, UUID, UUID);
