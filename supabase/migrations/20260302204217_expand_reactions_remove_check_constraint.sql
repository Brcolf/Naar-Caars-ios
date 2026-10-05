-- 20260302204217_expand_reactions_remove_check_constraint.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Remove CHECK constraint on reaction column to allow any emoji
ALTER TABLE message_reactions DROP CONSTRAINT IF EXISTS message_reactions_reaction_check;

-- Migrate legacy "HaHa" text reactions to emoji
UPDATE message_reactions SET reaction = '😂' WHERE reaction = 'HaHa';
