-- 20260313074722_add_image_dimensions_to_messages.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

ALTER TABLE messages ADD COLUMN image_width integer;
ALTER TABLE messages ADD COLUMN image_height integer;