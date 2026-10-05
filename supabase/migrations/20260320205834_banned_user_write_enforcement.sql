-- 20260320205834_banned_user_write_enforcement.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- ============================================================
-- banned_user_write_enforcement
-- Creates a reusable is_active_user() helper and adds INSERT
-- policy guards on all critical write surfaces so banned users
-- cannot create content via direct API calls.
-- ============================================================

-- 1. Reusable helper: returns true only if user is approved AND not banned
CREATE OR REPLACE FUNCTION public.is_active_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_user_id
      AND approved = true
      AND is_banned = false
  );
$$;

COMMENT ON FUNCTION public.is_active_user IS
  'Returns true if user is approved and not banned. Used in RLS policies to prevent banned users from writing.';

-- 2. Messages — tighten existing INSERT policy
DROP POLICY IF EXISTS "Users can send messages in their conversations" ON public.messages;

CREATE POLICY "Users can send messages in their conversations" ON public.messages
  FOR INSERT
  WITH CHECK (
    from_id = auth.uid()
    AND is_active_user(auth.uid())
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = conversation_id
          AND c.created_by = auth.uid()
      )
      OR
      EXISTS (
        SELECT 1 FROM public.conversation_participants cp
        WHERE cp.conversation_id = conversation_id
          AND cp.user_id = auth.uid()
          AND cp.left_at IS NULL
      )
    )
  );

-- 3. Rides — guard INSERT
DROP POLICY IF EXISTS "Users can create rides" ON public.rides;
DROP POLICY IF EXISTS "rides_insert_authenticated" ON public.rides;

CREATE POLICY "rides_insert_active_user" ON public.rides
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND is_active_user(auth.uid())
  );

-- 4. Favors — guard INSERT
DROP POLICY IF EXISTS "Users can create favors" ON public.favors;
DROP POLICY IF EXISTS "favors_insert_authenticated" ON public.favors;

CREATE POLICY "favors_insert_active_user" ON public.favors
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND is_active_user(auth.uid())
  );

-- 5. Town Hall Posts — guard INSERT
DROP POLICY IF EXISTS "Users can create posts" ON public.town_hall_posts;
DROP POLICY IF EXISTS "town_hall_posts_insert_authenticated" ON public.town_hall_posts;

CREATE POLICY "town_hall_posts_insert_active_user" ON public.town_hall_posts
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND is_active_user(auth.uid())
  );

-- 6. Town Hall Comments — guard INSERT
DROP POLICY IF EXISTS "Users can create comments" ON public.town_hall_comments;
DROP POLICY IF EXISTS "town_hall_comments_insert_authenticated" ON public.town_hall_comments;

CREATE POLICY "town_hall_comments_insert_active_user" ON public.town_hall_comments
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND is_active_user(auth.uid())
  );

-- 7. Reviews — guard INSERT
DROP POLICY IF EXISTS "Users can create reviews" ON public.reviews;
DROP POLICY IF EXISTS "reviews_insert_authenticated" ON public.reviews;

CREATE POLICY "reviews_insert_active_user" ON public.reviews
  FOR INSERT
  WITH CHECK (
    auth.uid() = reviewer_id
    AND is_active_user(auth.uid())
  );
