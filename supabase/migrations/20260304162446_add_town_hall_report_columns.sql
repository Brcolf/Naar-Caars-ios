-- 20260304162446_add_town_hall_report_columns.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Add columns for Town Hall post and comment reporting
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_post_id UUID REFERENCES town_hall_posts(id) ON DELETE SET NULL;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_comment_id UUID REFERENCES town_hall_comments(id) ON DELETE SET NULL;