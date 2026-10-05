-- 20260320211355_fix_rls_policy_bypasses_and_messages_tautology.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- ============================================================
-- fix_rls_policy_bypasses_and_messages_tautology
--
-- Fixes 3 critical issues in the banned_user_write_enforcement migration:
--
-- 1. messages INSERT policy has cp.conversation_id = cp.conversation_id
--    (self-referencing tautology) instead of cp.conversation_id = messages.conversation_id.
--    This lets ANY active participant write to ANY conversation. CRITICAL FIX.
--
-- 2. reviews table has TWO INSERT policies: old "Reviewers can create reviews"
--    (no ban check) and new "reviews_insert_active_user". PostgreSQL evaluates
--    multiple policies with OR, so the old policy bypasses the ban check.
--
-- 3. town_hall_posts table has TWO INSERT policies: old "Users can create own posts"
--    (no ban check) and new "town_hall_posts_insert_active_user". Same OR bypass.
-- ============================================================

-- 1. Fix messages INSERT policy: qualify conversation_id reference
DROP POLICY IF EXISTS "Users can send messages in their conversations" ON public.messages;

CREATE POLICY "Users can send messages in their conversations" ON public.messages
  FOR INSERT
  WITH CHECK (
    from_id = auth.uid()
    AND is_active_user(auth.uid())
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = messages.conversation_id
          AND c.created_by = auth.uid()
      )
      OR
      EXISTS (
        SELECT 1 FROM public.conversation_participants cp
        WHERE cp.conversation_id = messages.conversation_id
          AND cp.user_id = auth.uid()
          AND cp.left_at IS NULL
      )
    )
  );

-- 2. Drop old reviews INSERT policy that bypasses ban check
DROP POLICY IF EXISTS "Reviewers can create reviews" ON public.reviews;

-- 3. Drop old town_hall_posts INSERT policy that bypasses ban check
DROP POLICY IF EXISTS "Users can create own posts" ON public.town_hall_posts;
