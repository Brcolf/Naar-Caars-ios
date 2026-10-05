-- 20260319173427_add_application_fields_to_profiles.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Add application fields for public signup flow
-- These replace the invite code requirement for App Store compliance

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS heard_about TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS join_reason TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS application_complete BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS application_submitted_at TIMESTAMPTZ;

-- Backfill: existing approved users have already completed their "application"
-- Without this, approved users would be shown the application fields screen on next login
UPDATE profiles SET application_complete = true WHERE approved = true;

-- Also mark any pending users as application_complete since they went through invite code flow
-- They already provided an invite code which served as the application
UPDATE profiles SET application_complete = true WHERE approved = false AND invited_by IS NOT NULL;
