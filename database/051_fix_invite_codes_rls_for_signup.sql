-- Fix RLS policies for invite_codes table to allow signup flow
-- Allows users to mark invite codes as used during signup (before they're approved)
-- Migration: 051_fix_invite_codes_rls_for_signup.sql

-- ============================================================================
-- Step 1: Drop existing restrictive INSERT policy if it exists
-- ============================================================================

DROP POLICY IF EXISTS "invite_codes_insert_approved" ON public.invite_codes;

-- ============================================================================
-- Step 2: Add UPDATE policy to allow users to mark codes as used
-- ============================================================================

-- Allow users to update invite codes to mark them as used (set used_by and used_at)
-- This is allowed for:
-- 1. Unused codes (used_by IS NULL)
-- 2. Where the user is setting used_by to their own ID (auth.uid())
CREATE POLICY "invite_codes_update_mark_as_used" ON public.invite_codes
  FOR UPDATE
  USING (
    -- Code must be unused (used_by IS NULL)
    used_by IS NULL
    -- Only allow setting used_by to current user's ID
    AND (SELECT auth.uid()) IS NOT NULL
  )
  WITH CHECK (
    -- After update, used_by must be set to current user's ID
    used_by = auth.uid()
    AND used_at IS NOT NULL
  );

-- ============================================================================
-- Step 3: Add INSERT policy for bulk invite tracking records
-- ============================================================================

-- Allow users to insert tracking records for bulk invites
-- This is allowed when:
-- 1. The user is inserting a record with used_by = auth.uid() (tracking their own usage)
-- 2. The record has bulk_code_id set (indicating it's a tracking record, not a new code)
-- 3. The record has is_bulk = false (tracking records are not bulk codes themselves)
-- OR
-- 4. Approved users can create new invite codes (must have created_by = auth.uid())
-- Note: For bulk tracking records, created_by matches the bulk code's creator (not auth.uid()),
-- but we allow this since used_by = auth.uid() and bulk_code_id is set (proves it's a valid tracking record)
CREATE POLICY "invite_codes_insert_tracking_or_approved" ON public.invite_codes
  FOR INSERT
  WITH CHECK (
    -- Allow if this is a tracking record (bulk invite usage)
    -- Must have used_by = current user AND bulk_code_id IS NOT NULL AND is_bulk = false
    -- Note: created_by may be different (bulk code creator), which is OK for tracking records
    (used_by = auth.uid() AND bulk_code_id IS NOT NULL AND is_bulk = false)
    OR
    -- Allow if user is approved AND creating their own invite code
    -- Must have created_by = current user (they're creating it themselves)
    (created_by = auth.uid() AND EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND approved = true
    ))
  );

-- ============================================================================
-- Step 4: Verify policies are in place
-- ============================================================================

-- List all policies on invite_codes table
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'invite_codes'
ORDER BY policyname;

-- Add comment
COMMENT ON POLICY "invite_codes_update_mark_as_used" ON public.invite_codes IS 
'Allows authenticated users to mark unused invite codes as used by setting used_by to their own ID. Required for signup flow.';

COMMENT ON POLICY "invite_codes_insert_tracking_or_approved" ON public.invite_codes IS 
'Allows users to insert bulk invite tracking records (used_by = auth.uid() AND bulk_code_id IS NOT NULL) OR approved users to create new invite codes. Required for signup flow.';

