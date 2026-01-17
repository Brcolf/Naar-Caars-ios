-- SIMPLE Fix for invite_codes RLS policies
-- This version uses simpler, more explicit policy logic
-- Migration: 052_fix_invite_codes_rls_simple.sql

-- ============================================================================
-- Step 1: Ensure RLS is enabled
-- ============================================================================

ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Step 2: Drop ALL existing policies to start fresh
-- ============================================================================

DROP POLICY IF EXISTS "invite_codes_select_own" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_select_for_validation" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_insert_approved" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_insert_tracking_or_approved" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_update_mark_as_used" ON public.invite_codes;

-- ============================================================================
-- Step 3: Recreate SELECT policies (for viewing codes)
-- ============================================================================

-- Users can see their own created codes
CREATE POLICY "invite_codes_select_own" ON public.invite_codes
  FOR SELECT
  USING (auth.uid() = created_by);

-- Allow code lookup during signup (before user is authenticated OR after)
-- This allows anyone to check if a code is unused (for validation)
CREATE POLICY "invite_codes_select_for_validation" ON public.invite_codes
  FOR SELECT
  USING (used_by IS NULL);

-- ============================================================================
-- Step 4: Create UPDATE policy (for marking single-use codes as used)
-- ============================================================================

-- Allow authenticated users to update invite codes to mark them as used
-- Conditions:
-- - Code must be unused (used_by IS NULL) before update
-- - User must be authenticated
-- - After update: used_by = auth.uid() AND used_at IS NOT NULL
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
-- Step 5: Create INSERT policy (for bulk invite tracking records AND new codes)
-- ============================================================================

-- This policy allows TWO scenarios:
-- Scenario 1: Bulk invite tracking record
--   - used_by = auth.uid() (user is tracking their own usage)
--   - bulk_code_id IS NOT NULL (it's a tracking record)
--   - is_bulk = false (tracking records are not bulk codes themselves)
--   Note: created_by can be different (bulk code creator), which is OK
--
-- Scenario 2: Approved user creating a new invite code
--   - created_by = auth.uid() (user is creating their own code)
--   - User must be approved

CREATE POLICY "invite_codes_insert_allowed" ON public.invite_codes
  FOR INSERT
  WITH CHECK (
    -- Scenario 1: Bulk invite tracking record
    (
      used_by = auth.uid()
      AND bulk_code_id IS NOT NULL
      AND is_bulk = false
    )
    OR
    -- Scenario 2: Approved user creating new code
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
-- Step 6: Verify policies were created
-- ============================================================================

SELECT 
    policyname,
    cmd as operation,
    qual as using_expression,
    with_check as with_check_expression
FROM pg_policies
WHERE tablename = 'invite_codes'
  AND schemaname = 'public'
ORDER BY cmd, policyname;

-- ============================================================================
-- Step 7: Test the policies (optional - comment out if you want)
-- ============================================================================

-- Uncomment to test as a specific user (replace USER_ID with actual UUID):
-- SET LOCAL ROLE authenticated;
-- SET LOCAL request.jwt.claim.sub = 'USER_ID_HERE'::text;
-- 
-- -- Test SELECT
-- SELECT * FROM invite_codes WHERE used_by IS NULL LIMIT 1;
-- 
-- -- Test UPDATE (would need an actual unused code ID)
-- -- UPDATE invite_codes SET used_by = auth.uid(), used_at = NOW() WHERE id = 'CODE_ID_HERE';
-- 
-- -- Test INSERT (would need actual values)
-- -- INSERT INTO invite_codes (code, created_by, used_by, bulk_code_id, is_bulk) 
-- -- VALUES ('TEST123', 'CREATOR_ID', auth.uid(), 'BULK_CODE_ID', false);

