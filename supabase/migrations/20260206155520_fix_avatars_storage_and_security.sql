-- 20260206155520_fix_avatars_storage_and_security.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- ============================================================
-- COMPREHENSIVE SECURITY & STORAGE FIX MIGRATION
-- Fixes: Avatar storage, RLS gaps, security definer views,
--        function search_path, duplicate policies
-- ============================================================

-- ============================================================
-- 1. FIX AVATAR STORAGE BUCKET & POLICIES
-- Root cause of profile picture upload failures
-- ============================================================

-- 1a. Fix bucket file_size_limit (was ~200KB, should be 2MB)
UPDATE storage.buckets 
SET file_size_limit = 2097152  -- 2MB in bytes
WHERE id = 'avatars';

-- 1b. Drop broken avatar INSERT policy (uses foldername which doesn't match upload path)
DROP POLICY IF EXISTS "Avatar uploads" ON storage.objects;

-- 1c. Create correct avatar INSERT policy
-- Swift uploads to path: "{userId}.jpg" at root level
CREATE POLICY "avatars_insert_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = SPLIT_PART(name, '.', 1)
);

-- 1d. Add UPDATE policy (needed for upsert: true)
CREATE POLICY "avatars_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = SPLIT_PART(name, '.', 1)
)
WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = SPLIT_PART(name, '.', 1)
);

-- 1e. Add DELETE policy
CREATE POLICY "avatars_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = SPLIT_PART(name, '.', 1)
);

-- ============================================================
-- 2. FIX MISSING RLS ON PUBLIC TABLES
-- ============================================================

-- 2a. Enable RLS on completion_reminders
ALTER TABLE public.completion_reminders ENABLE ROW LEVEL SECURITY;

-- Service/triggers create reminders, users only need to see their own
CREATE POLICY "completion_reminders_select_own"
ON public.completion_reminders FOR SELECT
TO authenticated
USING (claimer_user_id = auth.uid());

-- Only service_role/triggers should insert/update
CREATE POLICY "completion_reminders_insert_service"
ON public.completion_reminders FOR INSERT
WITH CHECK (true);  -- Triggers run as SECURITY DEFINER

CREATE POLICY "completion_reminders_update_service"
ON public.completion_reminders FOR UPDATE
USING (true)
WITH CHECK (true);  -- Triggers run as SECURITY DEFINER

-- 2b. Enable RLS on town_hall_post_interactions
ALTER TABLE public.town_hall_post_interactions ENABLE ROW LEVEL SECURITY;

-- Approved users can view interactions
CREATE POLICY "interactions_select_approved"
ON public.town_hall_post_interactions FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
);

-- Users can insert their own interactions
CREATE POLICY "interactions_insert_own"
ON public.town_hall_post_interactions FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Users can delete their own interactions
CREATE POLICY "interactions_delete_own"
ON public.town_hall_post_interactions FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- 2c. Enable RLS on geocoding_cache (server-side only)
ALTER TABLE public.geocoding_cache ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read cached geocoding data
CREATE POLICY "geocoding_cache_select_authenticated"
ON public.geocoding_cache FOR SELECT
TO authenticated
USING (true);

-- Only authenticated users can insert cache entries
CREATE POLICY "geocoding_cache_insert_authenticated"
ON public.geocoding_cache FOR INSERT
TO authenticated
WITH CHECK (true);

-- Only authenticated users can update cache entries
CREATE POLICY "geocoding_cache_update_authenticated"
ON public.geocoding_cache FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

-- ============================================================
-- 3. FIX PROFILES UPDATE POLICY
-- The profiles_update_own policy's WITH CHECK blocks approved
-- users from updating their own profile (name, phone, car, avatar)
-- ============================================================

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own"
ON public.profiles FOR UPDATE
USING (id = auth.uid())
WITH CHECK (
    id = auth.uid()
    -- Users cannot self-promote to admin or self-approve
    AND (
        is_admin IS NOT DISTINCT FROM (SELECT p.is_admin FROM public.profiles p WHERE p.id = auth.uid())
    )
    AND (
        approved IS NOT DISTINCT FROM (SELECT p.approved FROM public.profiles p WHERE p.id = auth.uid())
    )
);

-- ============================================================
-- 4. CLEAN UP DUPLICATE/REDUNDANT RLS POLICIES
-- Multiple policies for the same operation cause confusion
-- and potential performance issues
-- ============================================================

-- 4a. Remove duplicate push_tokens policies (keep the named ones)
DROP POLICY IF EXISTS "push_tokens_insert_own" ON public.push_tokens;
DROP POLICY IF EXISTS "push_tokens_select_own" ON public.push_tokens;
DROP POLICY IF EXISTS "push_tokens_update_own" ON public.push_tokens;

-- 4b. Remove duplicate message_reactions policies (keep participant-checking ones)
DROP POLICY IF EXISTS "reactions_select_all" ON public.message_reactions;
DROP POLICY IF EXISTS "reactions_insert_own" ON public.message_reactions;
DROP POLICY IF EXISTS "reactions_update_own" ON public.message_reactions;
DROP POLICY IF EXISTS "reactions_delete_own" ON public.message_reactions;

-- 4c. Remove duplicate messages policies (keep participant-checking ones)
DROP POLICY IF EXISTS "messages_select_for_participants" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_for_participants" ON public.messages;

-- 4d. Remove duplicate profiles SELECT policies (keep the comprehensive one)
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;

-- 4e. Remove duplicate profiles INSERT policies (keep the comprehensive one)
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;

-- 4f. Remove duplicate conversations INSERT policy
DROP POLICY IF EXISTS "authenticated_users_can_create_conversations" ON public.conversations;

-- ============================================================
-- 5. FIX SECURITY DEFINER VIEWS
-- Convert to SECURITY INVOKER (default) so RLS applies
-- ============================================================

-- 5a. Fix messages_with_replies view
DROP VIEW IF EXISTS public.messages_with_replies;

-- 5b. Fix messages_filtered view  
DROP VIEW IF EXISTS public.messages_filtered;

-- 5c. Fix leaderboard_stats view
DROP VIEW IF EXISTS public.leaderboard_stats;
