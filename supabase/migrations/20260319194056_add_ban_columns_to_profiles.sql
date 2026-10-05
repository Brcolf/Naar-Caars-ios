-- 20260319194056_add_ban_columns_to_profiles.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Add ban-related columns to profiles table
-- Part of admin ban feature (v1 — client-side enforcement only, no RLS changes)

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_banned BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ban_reason TEXT,
  ADD COLUMN IF NOT EXISTS banned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS banned_by UUID REFERENCES public.profiles(id);

COMMENT ON COLUMN public.profiles.is_banned IS 'Whether this user account is banned/restricted';
COMMENT ON COLUMN public.profiles.ban_reason IS 'Admin-provided reason for the ban (displayed to user)';
COMMENT ON COLUMN public.profiles.banned_at IS 'Timestamp when the ban was applied';
COMMENT ON COLUMN public.profiles.banned_by IS 'Admin user ID who applied the ban';