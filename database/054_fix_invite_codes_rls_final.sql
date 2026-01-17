-- FINAL Fix for invite_codes RLS policies - Simplified and explicit
-- This version should definitely work for signup flow
-- Migration: 054_fix_invite_codes_rls_final.sql

-- ============================================================================
-- Step 1: Drop ALL existing policies
-- ============================================================================

DROP POLICY IF EXISTS "invite_codes_select_own" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_select_for_validation" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_insert_approved" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_insert_tracking_or_approved" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_insert_allowed" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_update_mark_as_used" ON public.invite_codes;

-- ============================================================================
-- Step 2: Recreate SELECT policies
-- ============================================================================

-- Users can see their own created codes
CREATE POLICY "invite_codes_select_own" ON public.invite_codes
  FOR SELECT
  USING (auth.uid() = created_by);

-- Allow code lookup during signup validation (unused codes)
CREATE POLICY "invite_codes_select_for_validation" ON public.invite_codes
  FOR SELECT
  USING (used_by IS NULL);

-- ============================================================================
-- Step 3: Create UPDATE policy for marking codes as used
-- ============================================================================

CREATE POLICY "invite_codes_update_mark_as_used" ON public.invite_codes
  FOR UPDATE
  USING (
    used_by IS NULL
    AND auth.uid() IS NOT NULL
  )
  WITH CHECK (
    used_by = auth.uid()::text
    AND used_at IS NOT NULL
  );

-- ============================================================================
-- Step 4: Create INSERT policy - SIMPLIFIED VERSION
-- ============================================================================

-- Allow INSERT if ANY of these conditions are met:
-- 1. User is inserting a record with used_by = their own ID (bulk tracking OR new code)
--    AND bulk_code_id IS NOT NULL (it's a bulk tracking record)
-- 2. User is approved AND creating their own code (created_by = auth.uid())

-- Note: We're using ::text conversion to ensure UUID comparison works
CREATE POLICY "invite_codes_insert_allowed" ON public.invite_codes
  FOR INSERT
  WITH CHECK (
    -- Case 1: Bulk tracking record - user is tracking their own usage
    (
      used_by = auth.uid()::text
      AND bulk_code_id IS NOT NULL
      AND is_bulk = false
    )
    OR
    -- Case 2: Approved user creating new code
    (
      created_by = auth.uid()::text
      AND EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id::text = auth.uid()::text
        AND approved = true
      )
    )
  );

-- ============================================================================
-- Step 5: Verify RLS is enabled
-- ============================================================================

ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Step 6: List all policies to verify
-- ============================================================================

SELECT 
    policyname,
    cmd as operation,
    pg_get_expr(qual, polrelid) as using_clause,
    pg_get_expr(with_check, polrelid) as with_check_clause
FROM pg_policies
WHERE tablename = 'invite_codes'
  AND schemaname = 'public'
ORDER BY cmd, policyname;

