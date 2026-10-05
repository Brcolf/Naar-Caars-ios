-- 20260206230444_fix_avatars_rls_case_sensitivity.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix RLS policies for avatars bucket to handle case-insensitive UUID comparison.
-- iOS UUID.uuidString returns UPPERCASE, Supabase auth.uid() returns lowercase.
-- Use lower() on both sides to ensure consistent comparison.

-- Drop existing policies
DROP POLICY IF EXISTS "avatars_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_update_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_delete_own" ON storage.objects;

-- Recreate with case-insensitive comparison
CREATE POLICY "avatars_insert_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND lower((auth.uid())::text) = lower(split_part(name, '.', 1))
);

CREATE POLICY "avatars_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND lower((auth.uid())::text) = lower(split_part(name, '.', 1))
)
WITH CHECK (
  bucket_id = 'avatars'
  AND lower((auth.uid())::text) = lower(split_part(name, '.', 1))
);

CREATE POLICY "avatars_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND lower((auth.uid())::text) = lower(split_part(name, '.', 1))
);
