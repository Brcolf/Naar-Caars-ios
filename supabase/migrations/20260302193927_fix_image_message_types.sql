-- 20260302193927_fix_image_message_types.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Fix existing image messages that were incorrectly stored with message_type = 'text'
UPDATE messages
SET message_type = 'image'
WHERE image_url IS NOT NULL
  AND image_url != ''
  AND message_type = 'text';
