-- 20260313015224_fix_reports_add_post_comment_columns.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_post_id UUID REFERENCES town_hall_posts(id);
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_comment_id UUID REFERENCES town_hall_comments(id);

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_target_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_check CHECK (
    reported_user_id IS NOT NULL OR
    reported_message_id IS NOT NULL OR
    reported_post_id IS NOT NULL OR
    reported_comment_id IS NOT NULL
);