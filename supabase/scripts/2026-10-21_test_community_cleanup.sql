-- 2026-10-21_test_community_cleanup.sql
--
-- STATUS: NOT NEEDED: observed 2026-10-22 that the rows it targets no longer exist (0 rides, 0 favors, 0 posts,
-- 0 comments, 0 Q&A in Test Community); nothing to run.
-- It is a one-off data script, not a migration: do not move it to supabase/migrations, never `supabase db push`,
-- and do not run it through the Supabase MCP (the MCP declines DELETE statements; do not rephrase around that).
--
-- WHAT IT DOES
-- Permanently deletes the member content that was in the default community when it was converted into the
-- example community. On 2026-10-21 that community (id 7a8ed131-cb05-462b-a491-b433d70a3fe5, until then
-- "Naar's Cars Seattle") was renamed "Test Community", and every ride, favor, Town Hall post and Town Hall
-- comment in it was hidden (hidden_at = 2026-10-21 16:48:50.856824+00, hidden_by = the platform owner,
-- hidden_reason = 'Community converted to Test Community (2026-10-21)'). Hidden rows are out of sight for
-- everyone except their own authors; this script removes them for good.
--
-- SCOPE. Only rows of community 7a8ed131-cb05-462b-a491-b433d70a3fe5 created BEFORE the cutover
-- 2026-10-21 16:48:50.856824+00 and still hidden, and the child rows of exactly those. Example content added
-- to Test Community after the cutover is never touched. Every DELETE re-checks the community, the cutover and
-- the hidden state in its own WHERE clause, and step 0 aborts the transaction if the community row or the
-- content is not in the state this script expects.
--
-- ORDER (child rows first). Counts are as read on 2026-10-21; Part A prints the live numbers.
--   1. request_qa on those rides and favors .................... 37
--   2. completion_reminders on those rides and favors ........... 33
--   3. reviews on those rides and favors ........................ 15
--      (must come before step 4: reviews.ride_id / favor_id are ON DELETE SET NULL and the reviews CHECK
--      needs exactly one of them, so deleting a ride that still has a review fails)
--      There is no claims table: a claim is rides.claimed_by / favors.claimed_by and goes with the row.
--   4. rides 107 (100 completed, 6 confirmed, 1 open) and favors 61 (59 completed, 2 confirmed)
--   5. town_hall_comments on those posts ........................ 10
--   6. town_hall_posts .......................................... 34
--      (12 untyped, 6 user posts, 11 review posts, 5 announcements, 4 of them pinned)
-- No statement in this file writes any other table.
--
-- WHAT THE DATABASE DOES ON ITS OWN when those rows go (foreign keys; no statement here does this):
--   ON DELETE CASCADE:  ride_participants (19 rows), favor_participants (0), town_hall_votes (12),
--                       town_hall_post_interactions (21), and replies inside request_qa / town_hall_comments.
--   ON DELETE SET NULL: notifications.ride_id / favor_id / town_hall_post_id / review_id on about 2,450 bell
--                       rows (the rows stay in people's bells; tapping one opens nothing);
--                       reports.reported_ride_id / reported_favor_id / reported_post_id / reported_comment_id
--                       on 11 reports (each also names a reported_user_id, so report_target_check still
--                       holds; step 0 re-checks this, because otherwise the DELETE would fail);
--                       town_hall_posts.review_id (step 3; those posts go in step 6 anyway).
--   No table involved has a DELETE trigger, so nothing here creates a notification, a push, an XP row or
--   any counter change. Storage objects are not deleted (1 Town Hall post image stays in its bucket).
--
-- WHAT IT REMOVES FOR REAL MEMBERS (13 people authored this content; 3 of them are platform admins).
-- Decide with this in mind; none of it can be brought back except from a backup or the CSV export below.
--   * Their request history: every ride and favor they posted or helped with in this community, with the
--     Q&A under them. Hidden today, but each author still sees their own; after this, nobody does.
--   * Reviews: all 15 reviews on the platform today are on these requests. 5 helpers lose every review they
--     have: get_profile_stats then shows no rating and a review count of 0 on their profiles, and the
--     review posts in Town Hall go with step 6.
--   * Profile "fulfilled" count (get_profile_stats counts confirmed and completed requests a person claimed,
--     in any community): drops for the 7 people who helped, by 167 requests in total.
--   * Savings (get_user_savings, confirmed or completed rides the person posted or helped with): 43 rides,
--     about 2,982 in estimated ride cost, go from the totals of the 6 people involved in them.
--   * Spotlights (get_community_spotlights reads rides, favors and reviews) and the admin statistics
--     (get_community_stats*, admin_stats_*) lose these requests, including the platform-wide figures.
--   * Town Hall: their posts, comments, votes and the 5 announcements.
-- WHAT IT DOES NOT REMOVE:
--   * XP. xp_events (244 rows for this community today: requests made, requests fulfilled, first ride and
--     first favor, reviews received) has no foreign key to these tables and is not touched, so XP totals,
--     badges and the XP leaderboard (get_community_leaderboard) stay as they are. Removing XP is a separate
--     owner decision and is not in this file.
--   * profiles, community_members, conversations, messages, notifications rows, auth, storage.
--
-- HOW TO RUN
--   1. Run Part A alone. It only reads. Check the numbers and that blocked_reports is 0.
--   2. Do Part B (export) and keep the files somewhere private: they hold members' ids, addresses and
--      free text. Not in the repository, not in a shared drive.
--   3. Run Part C as one block. It is one transaction: step 0 raises and nothing is deleted if the community
--      or the content is not as expected. Read the last SELECT before COMMIT; if it is not all zeros, replace
--      COMMIT with ROLLBACK and run again.
--   Afterwards, update Docs/qa/test-data.md ("Test Community") to say the content was deleted and when.


-- =====================================================================================================
-- PART A. Read-only preview: what Part C would delete, and what the foreign keys would change.
-- =====================================================================================================
with c as (select '7a8ed131-cb05-462b-a491-b433d70a3fe5'::uuid as id,
                  '2026-10-21 16:48:50.856824+00'::timestamptz as cutover),
r as (select x.id from public.rides x, c
       where x.community_id = c.id and x.created_at < c.cutover and x.hidden_at is not null),
f as (select x.id from public.favors x, c
       where x.community_id = c.id and x.created_at < c.cutover and x.hidden_at is not null),
p as (select x.id from public.town_hall_posts x, c
       where x.community_id = c.id and x.created_at < c.cutover and x.hidden_at is not null),
cm as (select x.id from public.town_hall_comments x where x.post_id in (select id from p)),
rv as (select x.id from public.reviews x where x.ride_id in (select id from r) or x.favor_id in (select id from f))
select
  (select name from public.communities, c where communities.id = c.id)                                as community_name,
  (select count(*) from public.request_qa q where q.ride_id in (select id from r) or q.favor_id in (select id from f)) as del_request_qa,
  (select count(*) from public.completion_reminders x where x.ride_id in (select id from r) or x.favor_id in (select id from f)) as del_completion_reminders,
  (select count(*) from rv)                                                                          as del_reviews,
  (select count(*) from r)                                                                           as del_rides,
  (select count(*) from f)                                                                           as del_favors,
  (select count(*) from cm)                                                                          as del_comments,
  (select count(*) from p)                                                                           as del_posts,
  -- not hidden but in scope: must be 0, or Part C aborts
  (select count(*) from public.rides x, c where x.community_id = c.id and x.created_at < c.cutover and x.hidden_at is null)
   + (select count(*) from public.favors x, c where x.community_id = c.id and x.created_at < c.cutover and x.hidden_at is null)
   + (select count(*) from public.town_hall_posts x, c where x.community_id = c.id and x.created_at < c.cutover and x.hidden_at is null) as in_scope_not_hidden,
  -- cascades (deleted by the database, not by a statement here)
  (select count(*) from public.ride_participants x where x.ride_id in (select id from r))            as cascade_ride_participants,
  (select count(*) from public.favor_participants x where x.favor_id in (select id from f))          as cascade_favor_participants,
  (select count(*) from public.town_hall_votes x where x.post_id in (select id from p) or x.comment_id in (select id from cm)) as cascade_votes,
  (select count(*) from public.town_hall_post_interactions x where x.post_id in (select id from p))  as cascade_post_interactions,
  -- set null (rows stay, a link column is emptied by the database)
  (select count(*) from public.notifications n
    where n.ride_id in (select id from r) or n.favor_id in (select id from f)
       or n.town_hall_post_id in (select id from p) or n.review_id in (select id from rv))           as setnull_notifications,
  (select count(*) from public.reports x
    where x.reported_ride_id in (select id from r) or x.reported_favor_id in (select id from f)
       or x.reported_post_id in (select id from p) or x.reported_comment_id in (select id from cm))  as setnull_reports,
  -- reports that would be left with no target at all: must be 0, or the DELETE fails on report_target_check
  (select count(*) from public.reports x
    where (x.reported_ride_id in (select id from r) or x.reported_favor_id in (select id from f)
        or x.reported_post_id in (select id from p) or x.reported_comment_id in (select id from cm))
      and x.reported_user_id is null and x.reported_message_id is null and x.reported_community_id is null
      and (x.reported_ride_id is null or x.reported_ride_id in (select id from r))
      and (x.reported_favor_id is null or x.reported_favor_id in (select id from f))
      and (x.reported_post_id is null or x.reported_post_id in (select id from p))
      and (x.reported_comment_id is null or x.reported_comment_id in (select id from cm)))            as blocked_reports,
  -- what stays (for the decision; not deleted here)
  (select count(*) from public.xp_events x, c where x.community_id = c.id)                           as kept_xp_events;


-- =====================================================================================================
-- PART B. Recommended export before deleting (read-only). Run each SELECT on its own in the SQL editor and
-- use the results pane's "Export → CSV" (or psql: \copy (<select>) to 'file.csv' csv header).
-- The files hold real members' content: keep them private and out of the repository.
-- =====================================================================================================
-- B1 rides
select x.* from public.rides x
 where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00';
-- B2 favors
select x.* from public.favors x
 where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00';
-- B3 request_qa
select q.* from public.request_qa q
 where q.ride_id in (select x.id from public.rides x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00')
    or q.favor_id in (select x.id from public.favors x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00');
-- B4 completion_reminders
select cr.* from public.completion_reminders cr
 where cr.ride_id in (select x.id from public.rides x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00')
    or cr.favor_id in (select x.id from public.favors x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00');
-- B5 reviews
select rv.* from public.reviews rv
 where rv.ride_id in (select x.id from public.rides x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00')
    or rv.favor_id in (select x.id from public.favors x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00');
-- B6 ride_participants (removed by cascade)
select rp.* from public.ride_participants rp
 where rp.ride_id in (select x.id from public.rides x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00');
-- B7 town_hall_posts
select p.* from public.town_hall_posts p
 where p.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and p.created_at < '2026-10-21 16:48:50.856824+00';
-- B8 town_hall_comments
select tc.* from public.town_hall_comments tc
 where tc.post_id in (select p.id from public.town_hall_posts p where p.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and p.created_at < '2026-10-21 16:48:50.856824+00');
-- B9 town_hall_votes and town_hall_post_interactions (removed by cascade)
select v.* from public.town_hall_votes v
 where v.post_id in (select p.id from public.town_hall_posts p where p.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and p.created_at < '2026-10-21 16:48:50.856824+00')
    or v.comment_id in (select tc.id from public.town_hall_comments tc join public.town_hall_posts p on p.id = tc.post_id
                         where p.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and p.created_at < '2026-10-21 16:48:50.856824+00');
select i.* from public.town_hall_post_interactions i
 where i.post_id in (select p.id from public.town_hall_posts p where p.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and p.created_at < '2026-10-21 16:48:50.856824+00');


-- =====================================================================================================
-- PART C. The deletion. One transaction; run as one block.
-- =====================================================================================================
begin;

-- Step 0. Abort unless the community and its content are exactly in the state this script was written for.
do $$
declare
  v_cid     constant uuid        := '7a8ed131-cb05-462b-a491-b433d70a3fe5';
  v_cutover constant timestamptz := '2026-10-21 16:48:50.856824+00';
  v_bad     bigint;
begin
  if not exists (select 1 from public.communities c
                  where c.id = v_cid and c.name = 'Test Community' and c.is_default and c.archived_at is null) then
    raise exception 'Abort: community % is not the unarchived default community named Test Community', v_cid;
  end if;

  select (select count(*) from public.rides x where x.community_id = v_cid and x.created_at < v_cutover and x.hidden_at is null)
       + (select count(*) from public.favors x where x.community_id = v_cid and x.created_at < v_cutover and x.hidden_at is null)
       + (select count(*) from public.town_hall_posts x where x.community_id = v_cid and x.created_at < v_cutover and x.hidden_at is null)
    into v_bad;
  if v_bad > 0 then
    raise exception 'Abort: % row(s) from before the cutover are no longer hidden; someone restored content', v_bad;
  end if;

  select count(*) into v_bad
    from public.reports x
   where (x.reported_ride_id in (select r.id from public.rides r where r.community_id = v_cid and r.created_at < v_cutover)
       or x.reported_favor_id in (select f.id from public.favors f where f.community_id = v_cid and f.created_at < v_cutover)
       or x.reported_post_id in (select p.id from public.town_hall_posts p where p.community_id = v_cid and p.created_at < v_cutover)
       or x.reported_comment_id in (select tc.id from public.town_hall_comments tc
                                      join public.town_hall_posts p on p.id = tc.post_id
                                     where p.community_id = v_cid and p.created_at < v_cutover))
     and x.reported_user_id is null and x.reported_message_id is null and x.reported_community_id is null;
  if v_bad > 0 then
    raise exception 'Abort: % report(s) would lose every target and fail report_target_check; decide on them first', v_bad;
  end if;
end
$$;

-- Step 1. request_qa on those rides and favors
delete from public.request_qa q
 where q.ride_id in (select r.id from public.rides r
                      where r.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
                        and r.created_at < '2026-10-21 16:48:50.856824+00' and r.hidden_at is not null)
    or q.favor_id in (select f.id from public.favors f
                       where f.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
                         and f.created_at < '2026-10-21 16:48:50.856824+00' and f.hidden_at is not null);

-- Step 2. completion_reminders on those rides and favors
delete from public.completion_reminders cr
 where cr.ride_id in (select r.id from public.rides r
                       where r.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
                         and r.created_at < '2026-10-21 16:48:50.856824+00' and r.hidden_at is not null)
    or cr.favor_id in (select f.id from public.favors f
                        where f.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
                          and f.created_at < '2026-10-21 16:48:50.856824+00' and f.hidden_at is not null);

-- Step 3. reviews on those rides and favors (before step 4; see the header)
delete from public.reviews rv
 where rv.ride_id in (select r.id from public.rides r
                       where r.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
                         and r.created_at < '2026-10-21 16:48:50.856824+00' and r.hidden_at is not null)
    or rv.favor_id in (select f.id from public.favors f
                        where f.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
                          and f.created_at < '2026-10-21 16:48:50.856824+00' and f.hidden_at is not null);

-- Step 4. rides and favors (ride_participants / favor_participants go by cascade)
delete from public.rides r
 where r.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
   and r.created_at < '2026-10-21 16:48:50.856824+00' and r.hidden_at is not null;

delete from public.favors f
 where f.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
   and f.created_at < '2026-10-21 16:48:50.856824+00' and f.hidden_at is not null;

-- Step 5. Town Hall comments on those posts (their votes go by cascade)
delete from public.town_hall_comments tc
 where tc.post_id in (select p.id from public.town_hall_posts p
                       where p.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
                         and p.created_at < '2026-10-21 16:48:50.856824+00' and p.hidden_at is not null);

-- Step 6. Town Hall posts (their votes and interactions go by cascade)
delete from public.town_hall_posts p
 where p.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
   and p.created_at < '2026-10-21 16:48:50.856824+00' and p.hidden_at is not null;

-- Check before committing: every number must be 0.
select
  (select count(*) from public.rides x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00') as rides_left,
  (select count(*) from public.favors x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00') as favors_left,
  (select count(*) from public.town_hall_posts x where x.community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and x.created_at < '2026-10-21 16:48:50.856824+00') as posts_left,
  (select count(*) from public.reviews x where x.ride_id is null and x.favor_id is null) as orphan_reviews,
  (select count(*) from public.request_qa x where x.ride_id is null and x.favor_id is null) as orphan_request_qa;

commit;   -- replace with ROLLBACK if the check above is not all zeros
