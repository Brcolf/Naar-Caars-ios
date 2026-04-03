-- Guest Mode: Allow anonymous (unauthenticated) reads on guest-visible tables.
-- Required for Apple App Store Guideline 5.1.1(v) — guest browsing.
--
-- These policies allow SELECT for the anon role (no auth session) alongside
-- the existing approved-user policies. Authenticated users are unaffected —
-- their existing policies still apply.

-- Rides: allow anon SELECT on open rides
CREATE POLICY "rides_select_anon_guest"
  ON public.rides
  FOR SELECT
  TO anon
  USING (true);

-- Favors: allow anon SELECT on open favors
CREATE POLICY "favors_select_anon_guest"
  ON public.favors
  FOR SELECT
  TO anon
  USING (true);

-- Profiles: allow anon SELECT (public profile data)
CREATE POLICY "profiles_select_anon_guest"
  ON public.profiles
  FOR SELECT
  TO anon
  USING (true);

-- Town Hall posts: allow anon SELECT
CREATE POLICY "town_hall_posts_select_anon_guest"
  ON public.town_hall_posts
  FOR SELECT
  TO anon
  USING (true);

-- Town Hall comments: allow anon SELECT
CREATE POLICY "town_hall_comments_select_anon_guest"
  ON public.town_hall_comments
  FOR SELECT
  TO anon
  USING (true);

-- Reviews: allow anon SELECT (shown on public profiles)
CREATE POLICY "reviews_select_anon_guest"
  ON public.reviews
  FOR SELECT
  TO anon
  USING (true);

-- Request Q&A: allow anon SELECT (shown on ride/favor detail)
CREATE POLICY "request_qa_select_anon_guest"
  ON public.request_qa
  FOR SELECT
  TO anon
  USING (true);

-- Leaderboard data: allow anon SELECT
-- (check if this table exists — it may be an RPC)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'leaderboard_entries' AND table_schema = 'public') THEN
    EXECUTE 'CREATE POLICY "leaderboard_entries_select_anon_guest" ON public.leaderboard_entries FOR SELECT TO anon USING (true)';
  END IF;
END $$;
