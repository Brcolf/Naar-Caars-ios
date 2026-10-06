-- 20261006_0006_request_addresses_members_only.sql
-- APPLIED 2026-10-06 through the Supabase MCP (request_addresses_members_only), at the
-- owner's decision to close this at once rather than wait for the next build.
--
-- Before this, pickup, destination (rides) and location (favors) could be read straight from
-- the tables by the anon role ("Guests can view visible rides / favors", USING hidden_at IS
-- NULL) and by any signed-in account, approved or not (sign-up is open, and the authenticated
-- SELECT policies did not look at approval). The app hides addresses from guests on screen and
-- never shows the lists to an account that is waiting for approval, so neither read was
-- something the app needed.
--
-- Now:
--   * anon reads nothing from rides / favors and uses the guest views of 20261006_0005
--     (addresses blanked);
--   * a signed-in account reads other people's requests only when it is approved and not
--     banned (is_active_user); everyone still reads their own requests, hidden or not.
--
-- Effect on a build from before the guest views (anything up to App Store build of
-- 2026-10-06): a guest sees empty Rides and Favors lists, with no error, until they update.
-- Approved members are not affected on any build.
--
-- Verified after applying (probe rows rolled back): each of the 19 approved members still
-- reads all 106 visible rides and 61 visible favors; anon reads 0 rows from rides and favors
-- and 106 / 61 from the guest views, with no address text, over REST as well; a signed-in
-- account with an unapproved profile reads 0 of other people's rides and favors and 1 of its
-- own.
--
-- To undo:
--   alter policy "Guests can view visible rides"  on public.rides  using (hidden_at is null);
--   alter policy "Guests can view visible favors" on public.favors using (hidden_at is null);
--   alter policy "Authenticated users can view visible or own hidden rides"  on public.rides
--     using ((hidden_at is null) or (user_id = (select auth.uid())));
--   alter policy "Authenticated users can view visible or own hidden favors" on public.favors
--     using ((hidden_at is null) or (user_id = (select auth.uid())));

alter policy "Guests can view visible rides" on public.rides using (false);
alter policy "Guests can view visible favors" on public.favors using (false);

alter policy "Authenticated users can view visible or own hidden rides" on public.rides
  using (
    user_id = (select auth.uid())
    or (hidden_at is null and (select public.is_active_user((select auth.uid()))))
  );

alter policy "Authenticated users can view visible or own hidden favors" on public.favors
  using (
    user_id = (select auth.uid())
    or (hidden_at is null and (select public.is_active_user((select auth.uid()))))
  );
