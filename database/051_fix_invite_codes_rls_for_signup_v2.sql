-- Fix RLS policies for invite_codes table to allow signup flow (Version 2)
-- Allows users to mark invite codes as used during signup (before they're approved)
-- Migration: 051_fix_invite_codes_rls_for_signup_v2.sql

-- ============================================================================
-- Step 1: Drop existing policies to recreate them
-- ============================================================================

DROP POLICY IF EXISTS "invite_codes_insert_approved" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_insert_tracking_or_approved" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_update_mark_as_used" ON public.invite_codes;

-- ============================================================================
-- Step 2: Add UPDATE policy to allow users to mark codes as used
-- ============================================================================

-- Allow authenticated users to update invite codes to mark them as used
-- Requirements:
-- - Code must be unused (used_by IS NULL) before update
-- - User must be setting used_by to their own ID (auth.uid())
-- - used_at must be set (not NULL) after update
CREATE POLICY "invite_codes_update_mark_as_used" ON public.invite_codes
  FOR UPDATE
  USING (
    -- Code must be unused before update
    used_by IS NULL
    -- User must be authenticated
    AND auth.uid() IS NOT NULL
  )
  WITH CHECK (
    -- After update, used_by must be set to current user's ID
    used_by = auth.uid()
    -- used_at must be set (not NULL)
    AND used_at IS NOT NULL
  );

-- ============================================================================
-- Step 3: Add INSERT policy for bulk invite tracking records AND new codes
-- ============================================================================

-- Allow two types of inserts:
-- 1. Bulk invite tracking records (used_by = auth.uid(), bulk_code_id IS NOT NULL, is_bulk = false)
--    Note: created_by may be different (bulk code creator), which is OK
-- 2. New invite codes created by approved users (created_by = auth.uid(), approved = true)
CREATE POLICY "invite_codes_insert_tracking_or_approved" ON public.invite_codes
  FOR INSERT
  WITH CHECK (
    -- Case 1: Bulk invite tracking record
    -- User is tracking their own usage of a bulk code
    (
      used_by = auth.uid() 
      AND bulk_code_id IS NOT NULL 
      AND is_bulk = false
    )
    OR
    -- Case 2: Approved user creating a new invite code
    -- User must be approved and creating their own code
    (
      created_by = auth.uid() 
      AND EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() 
        AND approved = true
      )
    )
  );

-- ============================================================================
-- Step 4: Verify RLS is enabled
-- ============================================================================

ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Step 5: List all policies to verify they were created
-- ============================================================================

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

-- ============================================================================
-- Step 6: Add comments for documentation
-- ============================================================================

COMMENT ON POLICY "invite_codes_update_mark_as_used" ON public.invite_codes IS 
'Allows authenticated users to mark unused invite codes as used by setting used_by to their own ID and used_at to current timestamp. Required for signup flow.';

COMMENT ON POLICY "invite_codes_insert_tracking_or_approved" ON public.invite_codes IS 
'Allows: (1) Users to insert bulk invite tracking records (used_by = auth.uid() AND bulk_code_id IS NOT NULL AND is_bulk = false), OR (2) Approved users to create new invite codes (created_by = auth.uid()). Required for signup flow.';

-- ============================================================================
-- Step 7: Test query to verify policies work
-- ============================================================================

-- This query should show all policies and their definitions
-- Run this after the migration to verify everything is correct
SELECT 
    p.policyname,
    p.cmd as operation,
    pg_get_expr(p.qual, p.polrelid) as using_expression,
    pg_get_expr(p.with_check, p.polrelid) as with_check_expression
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = 'invite_codes'
  AND n.nspname = 'public'
ORDER BY p.policyname;

