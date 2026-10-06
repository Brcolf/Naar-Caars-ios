-- 20261006_0002_reviews_insert_requires_own_completed_request.sql
-- APPLIED 2026-10-06 through the Supabase MCP (reviews_insert_requires_own_completed_request).
--
-- A review may only be written by the poster of a completed request, about the person who
-- helped with it. The old check (reviewer_id = caller, active account) let any member review
-- any helper on any completed request: a public Town Hall "New Review" post, a rating change
-- and review XP for a request the reviewer had nothing to do with. Verified 2026-10-06 with a
-- rolled-back insert as a second account (one row inserted before this change).
--
-- Probes after applying (rolled back): a review of a stranger's ride, a review naming the
-- wrong helper and a review of a request that is not completed all fail with 42501; the
-- poster's review of their own helper on a completed ride still succeeds. The existing
-- constraints still apply (one review per request per reviewer, no self review, a ride or a
-- favor is required).
--
-- This is what the app already does: ReviewPromptProvider and the detail screens only offer a
-- review to the poster of a completed request (ride.userId == currentUser, claimedBy != nil).

alter policy reviews_insert_active_user on public.reviews
with check (
  (select auth.uid()) = reviewer_id
  and public.is_active_user((select auth.uid()))
  and (
    (ride_id is not null and exists (
       select 1 from public.rides r
       where r.id = reviews.ride_id and r.user_id = (select auth.uid())
         and r.claimed_by = reviews.fulfiller_id and r.status = 'completed'))
    or
    (favor_id is not null and exists (
       select 1 from public.favors f
       where f.id = reviews.favor_id and f.user_id = (select auth.uid())
         and f.claimed_by = reviews.fulfiller_id and f.status = 'completed'))
  )
);
