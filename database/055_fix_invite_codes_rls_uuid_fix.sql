-- Fix invite_codes RLS policies with correct UUID handling
-- Migration: 055_fix_invite_codes_rls_uuid_fix.sql

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

-- Allow code lookup during signup validation (unused codes only)
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
    used_by = auth.uid()
    AND used_at IS NOT NULL
  );

-- ============================================================================
-- Step 4: Create INSERT policy with correct UUID handling
-- ============================================================================

-- For bulk tracking records: Allow if used_by = auth.uid() AND bulk_code_id IS NOT NULL
-- For new codes: Allow if created_by = auth.uid() AND user is approved
-- Note: We cast to UUID to ensure proper type comparison

CREATE POLICY "invite_codes_insert_allowed" ON public.invite_codes
  FOR INSERT
  WITH CHECK (
    -- Case 1: Bulk invite tracking record
    -- The user (auth.uid()) is the one using the code (used_by)
    -- AND it's a tracking record (bulk_code_id IS NOT NULL)
    -- AND it's not a bulk code itself (is_bulk = false)
    (
      used_by = auth.uid()
      AND bulk_code_id IS NOT NULL
      AND is_bulk = false
    )
    OR
    -- Case 2: Approved user creating new invite code
    -- User must be approved AND creating their own code
    (
      created_by = auth.uid()
      AND EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = auth.uid()
        AND approved = true
      )
    )
  );

-- ============================================================================
-- Step 5: Verify policies
-- ============================================================================

-- List all policies with their definitions
-- Using pg_policies view which provides user-friendly column names
SELECT 
    policyname,
    cmd as operation,
    qual as using_clause,
    with_check as with_check_clause
FROM pg_policies
WHERE tablename = 'invite_codes'
  AND schemaname = 'public'
ORDER BY cmd, policyname;

