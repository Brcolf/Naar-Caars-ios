-- Migration: Add Community Guidelines Acceptance to Profiles
-- Description: Adds fields to track when users accept community guidelines
-- Date: 2026-01-19

-- Add guidelines_accepted and guidelines_accepted_at to profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS guidelines_accepted BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS guidelines_accepted_at TIMESTAMPTZ;

-- Add index for quick lookup of users who haven't accepted guidelines
CREATE INDEX IF NOT EXISTS idx_profiles_guidelines_not_accepted 
ON public.profiles (guidelines_accepted) 
WHERE guidelines_accepted = false;

-- Add comment to document the fields
COMMENT ON COLUMN public.profiles.guidelines_accepted IS 'Whether user has accepted community guidelines';
COMMENT ON COLUMN public.profiles.guidelines_accepted_at IS 'Timestamp when user accepted community guidelines';

-- Update RLS policies to allow users to update their own guidelines acceptance
-- Users should be able to mark guidelines as accepted for themselves
-- (Existing profile RLS policies should already cover this, but documenting intent)

-- Verify the migration
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND column_name IN ('guidelines_accepted', 'guidelines_accepted_at');

-- Expected results:
-- guidelines_accepted | boolean | NO | false
-- guidelines_accepted_at | timestamp with time zone | YES | NULL

COMMIT;

