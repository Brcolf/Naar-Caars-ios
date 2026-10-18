-- 20261017_0002_communities_rls.sql
-- NOT APPLIED. Phase 0, step 2 of the multi-community build
-- (Docs/superpowers/specs/2026-10-07-multi-community-design.md §3.4 and §4 "Step 2", as amended by
-- Docs/superpowers/specs/2026-10-17-multi-community-decisions.md).
--
-- What this file does
--   * Row-level security for the new community tables: RLS on, client writes revoked (every write is
--     an RPC), SELECT policies, and the own-row column grant on community_members
--     (notifications_muted, muted_until, updated_at; the 20261005_0015 mechanism).
--   * 28 ALTER POLICY statements that add "the row belongs to a community I am an active member of"
--     (or "the parent row is visible to me") to the existing policies on rides, favors,
--     town_hall_posts, town_hall_comments, town_hall_votes, town_hall_post_interactions, request_qa,
--     ride_participants, favor_participants, reviews, conversation_participants and geocoding_cache.
--     Every policy name below was checked against live pg_policies on 2026-10-17 (two are truncated
--     to 63 characters by Postgres and are written that way here).
--   * guest_rides / guest_favors gain community_id (appended last, so CREATE OR REPLACE is legal) and
--     show only rows of public, non-archived communities. public_profiles shows the caller the
--     profiles in public.my_visible_profile_ids(), and a guest the active members of public
--     communities.
--   * reports: no statement. Reports about a community (reported_community_id, filed only by the
--     report_community RPC of step 5) are already readable by platform admins only, through the
--     existing "Admins can view all reports" policy, plus the reporter's own row through "Users can
--     view own reports", the same as every other report. Clients hold no INSERT grant on reports
--     (only SELECT and UPDATE), so the "Users can create reports" policy stays inert. No policy
--     gives a community admin the table; they read reports through get_community_reports (step 5).
--     community_limit_requests (amendment A1) is own rows plus platform admins, writes RPC-only.
--
-- Precondition (step 1, 20261017_0001_communities_core.sql, applied in full). Run before the first
-- statement; each must return 0 rows / true, or stop:
--   select count(*) from public.profiles p where p.approved and not p.is_banned and not exists (
--     select 1 from public.community_members m join public.communities c on c.id = m.community_id
--     where m.user_id = p.id and m.status = 'active' and c.is_default);                       -- 0
--   select count(*) from public.rides where community_id is null;                              -- 0
--   select count(*) from public.favors where community_id is null;                             -- 0
--   select count(*) from public.town_hall_posts where community_id is null;                    -- 0
--   select is_public and archived_at is null from public.communities where is_default;         -- true
--   the fill triggers (fill_community_rides / _favors / _posts) and the helpers of spec §3.2 exist.
-- guest_rides / guest_favors use an inner join on communities, so a ride without a community would
-- vanish from the guest lists: that is why they need backfill Part B first.
--
-- Why this is a no-op for a world with exactly one community
--   With one community (the default, public, not archived) and step 1 applied, every approved and
--   unbanned profile is an active member of it, every ride, favor and post belongs to it, and the
--   helpers answer: my_community_ids() = {default} for every such member and {} for anyone else.
--   Every new condition is therefore true for every row a member can read today, and every
--   ALTER POLICY only ANDs a condition onto the existing test (where the old test was an approval
--   test it is kept, so no policy becomes looser; where it was `true` it is replaced by the scoped
--   condition). Members and guests see the same screens, rows and counts on every build.
--   The only row-level differences, none of which any screen shows, are:
--     (a) a signed-in account that is not an active member (unapproved, or banned while still
--         approved): it already reads no rides or favors (20261006_0006); it now also reads no
--         Town Hall comments or votes, Q&A, reviews, participants or geocoding cache of others, and
--         cannot vote, add a thread participant or a ride/favor participant. Live on 2026-10-17:
--         19 profiles, all approved, 0 banned, so 0 accounts are in this group;
--     (b) the children of a moderated (hidden) Town Hall post, which only the post's author can
--         open: its comments, votes and interactions become invisible to everyone but the post's
--         author (votes and interactions stay visible to their own writer). Live: 3 hidden posts
--         carrying 2 visible comments, 2 votes and 4 interactions;
--     (c) public_profiles hides profiles that are in no shared community, thread or review with the
--         caller (for a guest: that are not active members of a public community). Live: all 19
--         profiles are active members, so a member and a guest both still read 19. Member search
--         already filters approved = true, and the admin screens read profiles, not this view.
--
-- What old clients see: nothing different. guest_rides / guest_favors responses carry one more key,
-- community_id, which the installed decoders ignore (synthesized CodingKeys).
--
-- How to apply: one statement per MCP call, in file order. Order matters in one place: blocks
-- [G1]-[G4] and [N1] must precede [A08] and [A11], because a guest's Town Hall read now looks at
-- communities (anon needs the SELECT grant and the anon policy, or guests read 0 posts).
-- After each call run the short probe of spec §4 (insert a ride and a favor without community_id,
-- claim and complete as a second member, insert a review, read back the community, delete probe
-- accounts) inside begin; ... rollback;.
--
-- Verification (to be filled in by the apply run; the rollout stops at the first failure):
--   md5 of pg_get_viewdef after applying: guest_rides ________, guest_favors ________,
--   public_profiles ________; md5 of each altered policy's qual / with_check: recorded in the run.
--   Probes, under set local role authenticated / anon with request.jwt.claims, rolled back:
--     each of the 19 members reads 106 rides, 61 favors, 31 visible Town Hall posts plus their own
--     hidden ones, 15 reviews, 7 geocoding rows, and 19 rows of public_profiles;
--     anon reads 0 from rides / favors, 106 / 61 from the guest views (community_id set, no
--     addresses), 31 posts, 8 comments, 15 reviews, 19 rows of public_profiles;
--     a member can insert a ride / favor / post without community_id, claim another member's open
--     ride, comment, vote, ask a Q&A question, add a ride participant and a thread participant;
--     a member reads only their own community_members row, and the communities row for the default;
--     a member can update notifications_muted on their own community_members row and gets
--     42501 on role / status; anon reads the default community and no community_members row.
--
-- To undo (each statement alone; the rollback artefact of step 0 holds the same predicates):
--   rides / favors (replace ride with favor for favors):
--     alter policy "Authenticated users can view visible or own hidden rides" on public.rides
--       using ((user_id = (select auth.uid())) or ((hidden_at is null)
--              and (select public.is_active_user((select auth.uid()))));
--     alter policy rides_insert_active_user on public.rides
--       with check (((select auth.uid()) = user_id) and public.is_active_user((select auth.uid())));
--     alter policy "Authenticated users can claim open rides" on public.rides
--       using ((claimed_by is null) and (status = 'open'::public.ride_status)
--              and (user_id <> (select auth.uid())));
--   town_hall_posts:
--     alter policy "Authenticated users can view visible or own hidden town hall po" on public.town_hall_posts
--       using (((hidden_at is null) and coalesce((select p.approved from public.profiles p
--              where p.id = (select auth.uid())), false)) or (user_id = (select auth.uid())));
--     alter policy "Guests can view visible town hall posts" on public.town_hall_posts using (hidden_at is null);
--     alter policy town_hall_posts_insert_active_user on public.town_hall_posts
--       with check (((select auth.uid()) = user_id) and public.is_active_user((select auth.uid())));
--   town_hall_comments:
--     alter policy "Authenticated users can view visible or own hidden town hall co" on public.town_hall_comments
--       using ((hidden_at is null) or (user_id = (select auth.uid())));
--     alter policy "Guests can view visible town hall comments" on public.town_hall_comments using (hidden_at is null);
--     alter policy town_hall_comments_insert_active_user on public.town_hall_comments
--       with check (((select auth.uid()) = user_id) and public.is_active_user((select auth.uid())));
--   town_hall_votes:
--     alter policy "Users can view all votes" on public.town_hall_votes using (true);
--     alter policy "Users can create votes" on public.town_hall_votes with check ((select auth.uid()) = user_id);
--   town_hall_post_interactions:
--     alter policy interactions_select_approved on public.town_hall_post_interactions
--       using (exists (select 1 from public.profiles where profiles.id = (select auth.uid()) and profiles.approved = true));
--   request_qa:
--     alter policy "Approved users can view Q&A" on public.request_qa
--       using ((select profiles.approved from public.profiles where profiles.id = (select auth.uid())) = true);
--     alter policy request_qa_select_anon_guest on public.request_qa using (true);
--     alter policy "Approved users can create Q&A" on public.request_qa
--       with check (((select profiles.approved from public.profiles where profiles.id = (select auth.uid())) = true)
--                   and ((select auth.uid()) = user_id));
--   ride_participants / favor_participants (replace ride with favor):
--     alter policy ride_participants_select on public.ride_participants
--       using (exists (select 1 from public.profiles where profiles.id = (select auth.uid()) and profiles.approved = true));
--     alter policy ride_participants_insert on public.ride_participants
--       with check ((exists (select 1 from public.rides where rides.id = ride_participants.ride_id
--                   and rides.user_id = (select auth.uid()))) and (added_by = (select auth.uid())));
--   reviews:
--     alter policy "Approved users can view reviews" on public.reviews
--       using ((select profiles.approved from public.profiles where profiles.id = (select auth.uid())) = true);
--     alter policy reviews_select_anon_guest on public.reviews using (true);
--   conversation_participants:
--     alter policy authenticated_users_can_add_participants on public.conversation_participants
--       with check (public.is_conversation_creator(conversation_id, (select auth.uid())));
--   geocoding_cache:
--     alter policy geocoding_cache_select_authenticated on public.geocoding_cache using (true);
--     alter policy geocoding_cache_insert_authenticated on public.geocoding_cache with check (true);
--     alter policy geocoding_cache_update_authenticated on public.geocoding_cache using (true) with check (true);
--   views: guest_rides / guest_favors from 20261017_0000 section 3, which drops and recreates them
--     with today's grants (re-applying 20261006_0005 would fail: CREATE OR REPLACE VIEW cannot drop
--     the appended community_id column). Restore the request_qa and reviews anon policies above
--     first: their step-2 versions reference guest_rides / guest_favors, so the drop fails while
--     they do. For public_profiles (column list unchanged, replaced in place):
--     create or replace view public.public_profiles with (security_barrier = true, security_invoker = false) as
--       select p.id, p.name, p.avatar_url, p.car, p.approved, p.created_at, p.updated_at from public.profiles p;
--   new-table policies: they gate tables nothing else reads; leave them, or DROP POLICY in the SQL editor.


-- ============================================================================================
-- New tables: RLS on, client writes revoked, read grants, the community_members column grant
-- ============================================================================================

-- [R1] public.communities: row-level security on (idempotent)
alter table public.communities enable row level security;

-- [R2] public.community_members: row-level security on (idempotent)
alter table public.community_members enable row level security;

-- [R3] public.community_invites: row-level security on (idempotent)
alter table public.community_invites enable row level security;

-- [R4] public.community_invite_redemptions: row-level security on (idempotent)
alter table public.community_invite_redemptions enable row level security;

-- [R5] public.community_invite_attempts: row-level security on, and no policy (definer RPCs only)
alter table public.community_invite_attempts enable row level security;

-- [R6] public.community_membership_events: row-level security on (idempotent)
alter table public.community_membership_events enable row level security;

-- [R7] public.community_limit_requests: row-level security on (idempotent)
alter table public.community_limit_requests enable row level security;

-- [G1] all seven new tables: no direct client privilege of any kind (writes are RPC-only; the table-emptying
-- privilege and the table-wide UPDATE must be gone for the column grant in [G4] to be the only write path)
revoke all on public.communities, public.community_members, public.community_invites,
  public.community_invite_redemptions, public.community_invite_attempts,
  public.community_membership_events, public.community_limit_requests
  from public, anon, authenticated;

-- [G2] public.communities: readable by guests (public communities, policy [N1]) and signed-in accounts ([N2])
grant select on public.communities to anon, authenticated;

-- [G3] the other readable new tables: signed-in accounts only, rows bounded by the policies below
grant select on public.community_members, public.community_invites, public.community_invite_redemptions,
  public.community_membership_events, public.community_limit_requests
  to authenticated;

-- [G4] public.community_members: own-row mute settings are the only client write (policy [N4];
-- guard_community_members_client_update from step 1 is the second line)
grant update (notifications_muted, muted_until, updated_at) on public.community_members to authenticated;


-- ============================================================================================
-- New tables: policies
-- ============================================================================================

-- [N1] public.communities / communities_select_anon
create policy communities_select_anon on public.communities
  for select to anon
  using (is_public and archived_at is null);

-- [N2] public.communities / communities_select_authenticated
-- Public communities, the caller's active ones, the ones they administer (platform admins: every
-- non-archived one), and one they have a pending application to. A departed or removed member does
-- not see a private community. The community_members subquery runs with invoker rights and sees only
-- the caller's own row there ([N3]); [N3] never reads communities, so there is no recursion.
create policy communities_select_authenticated on public.communities
  for select to authenticated
  using (
    archived_at is null
    and (
      is_public
      or id = any ((select public.my_community_ids())::uuid[])
      or id = any ((select public.my_admin_community_ids())::uuid[])
      or exists (
        select 1 from public.community_members m
        where m.community_id = communities.id
          and m.user_id = (select auth.uid())
          and m.status = 'pending'
      )
    )
  );

-- [N3] public.community_members / community_members_select_own_or_admin
-- Members do not read each other's rows from the table; the directory is get_community_members.
create policy community_members_select_own_or_admin on public.community_members
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or community_id = any ((select public.my_admin_community_ids())::uuid[])
  );

-- [N4] public.community_members / community_members_update_own (columns limited by [G4])
create policy community_members_update_own on public.community_members
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- [N5] public.community_invites / community_invites_select_creator_or_admin
create policy community_invites_select_creator_or_admin on public.community_invites
  for select to authenticated
  using (
    created_by = (select auth.uid())
    or community_id = any ((select public.my_admin_community_ids())::uuid[])
  );

-- [N6] public.community_invite_redemptions / community_invite_redemptions_select_own_or_admin
-- The table has no community_id; the community comes from the invite.
create policy community_invite_redemptions_select_own_or_admin on public.community_invite_redemptions
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.community_invites i
      where i.id = community_invite_redemptions.invite_id
        and i.community_id = any ((select public.my_admin_community_ids())::uuid[])
    )
  );

-- [N7] public.community_membership_events / community_membership_events_select_own_or_admin
create policy community_membership_events_select_own_or_admin on public.community_membership_events
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or community_id = any ((select public.my_admin_community_ids())::uuid[])
  );

-- [N8] public.community_limit_requests / community_limit_requests_select_own_or_platform_admin
-- Writes only through request_owned_community_limit / decide_owned_community_limit (amendment A1).
create policy community_limit_requests_select_own_or_platform_admin on public.community_limit_requests
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_platform_admin())
  );


-- ============================================================================================
-- Views
-- ============================================================================================

-- [V1] public.guest_rides: community_id appended; public, non-archived communities only
create or replace view public.guest_rides
with (security_barrier = true, security_invoker = false) as
select
    r.id, r.user_id, r.type, r.date, r."time",
    ''::text as pickup,
    ''::text as destination,
    r.seats, r.notes, r.gift, r.status, r.claimed_by, r.reviewed, r.review_skipped, r.review_skipped_at,
    r.created_at, r.updated_at, r.estimated_cost, r.flight_normalized, r.timezone,
    r.hidden_at, r.hidden_by, r.hidden_reason,
    r.community_id
from public.rides r
join public.communities c on c.id = r.community_id
where r.hidden_at is null
  and c.is_public
  and c.archived_at is null;

-- [V2] public.guest_favors: community_id appended; public, non-archived communities only
create or replace view public.guest_favors
with (security_barrier = true, security_invoker = false) as
select
    f.id, f.user_id, f.title, f.description,
    ''::text as location,
    f.duration, f.requirements, f.date, f."time", f.gift, f.status, f.claimed_by, f.reviewed,
    f.review_skipped, f.review_skipped_at, f.created_at, f.updated_at, f.timezone,
    f.hidden_at, f.hidden_by, f.hidden_reason,
    f.community_id
from public.favors f
join public.communities c on c.id = f.community_id
where f.hidden_at is null
  and c.is_public
  and c.archived_at is null;

-- [V3] public.public_profiles: the caller's visible profiles; a guest sees active members of public communities
-- auth.uid() reads the request's JWT claims, so it is the caller even inside this owner-rights view
-- (and inside get_conversations_with_details, a definer function that reads the view).
create or replace view public.public_profiles
with (security_barrier = true, security_invoker = false) as
select p.id, p.name, p.avatar_url, p.car, p.approved, p.created_at, p.updated_at
from public.profiles p
where p.id = any ((select public.my_visible_profile_ids())::uuid[])
   or (
     (select auth.uid()) is null
     and exists (
       select 1 from public.community_members m
       join public.communities c on c.id = m.community_id
       where m.user_id = p.id
         and m.status = 'active'
         and c.is_public
         and c.archived_at is null
     )
   );

-- [V4] public.guest_rides: comment
comment on view public.guest_rides is 'Rides as a guest may see them: visible rows of public, non-archived communities, pickup and destination blanked.';

-- [V5] public.guest_favors: comment
comment on view public.guest_favors is 'Favors as a guest may see them: visible rows of public, non-archived communities, location blanked.';


-- ============================================================================================
-- Existing policies (28 ALTER POLICY)
-- ============================================================================================

-- [A01] public.rides / "Authenticated users can view visible or own hidden rides"
alter policy "Authenticated users can view visible or own hidden rides" on public.rides
  using (
    user_id = (select auth.uid())
    or (
      hidden_at is null
      and (select public.is_active_user((select auth.uid())))
      and community_id = any ((select public.my_community_ids())::uuid[])
    )
  );

-- [A02] public.rides / rides_insert_active_user (community_id is filled by fill_community_rides before this check)
alter policy rides_insert_active_user on public.rides
  with check (
    (select auth.uid()) = user_id
    and (select public.is_active_user((select auth.uid())))
    and community_id = any ((select public.my_community_ids())::uuid[])
  );

-- [A03] public.rides / "Authenticated users can claim open rides"
alter policy "Authenticated users can claim open rides" on public.rides
  using (
    claimed_by is null
    and status = 'open'::public.ride_status
    and user_id <> (select auth.uid())
    and community_id = any ((select public.my_community_ids())::uuid[])
  );

-- [A04] public.favors / "Authenticated users can view visible or own hidden favors"
alter policy "Authenticated users can view visible or own hidden favors" on public.favors
  using (
    user_id = (select auth.uid())
    or (
      hidden_at is null
      and (select public.is_active_user((select auth.uid())))
      and community_id = any ((select public.my_community_ids())::uuid[])
    )
  );

-- [A05] public.favors / favors_insert_active_user (community_id is filled by fill_community_favors before this check)
alter policy favors_insert_active_user on public.favors
  with check (
    (select auth.uid()) = user_id
    and (select public.is_active_user((select auth.uid())))
    and community_id = any ((select public.my_community_ids())::uuid[])
  );

-- [A06] public.favors / "Authenticated users can claim open favors"
alter policy "Authenticated users can claim open favors" on public.favors
  using (
    claimed_by is null
    and status = 'open'::public.favor_status
    and user_id <> (select auth.uid())
    and community_id = any ((select public.my_community_ids())::uuid[])
  );

-- [A07] public.town_hall_posts / "Authenticated users can view visible or own hidden town hall po" (name truncated by Postgres)
alter policy "Authenticated users can view visible or own hidden town hall po" on public.town_hall_posts
  using (
    user_id = (select auth.uid())
    or (
      hidden_at is null
      and coalesce((select p.approved from public.profiles p where p.id = (select auth.uid())), false)
      and community_id = any ((select public.my_community_ids())::uuid[])
    )
  );

-- [A08] public.town_hall_posts / "Guests can view visible town hall posts" (needs [G2] and [N1] first)
alter policy "Guests can view visible town hall posts" on public.town_hall_posts
  using (
    hidden_at is null
    and exists (
      select 1 from public.communities c
      where c.id = town_hall_posts.community_id
        and c.is_public
        and c.archived_at is null
    )
  );

-- [A09] public.town_hall_posts / town_hall_posts_insert_active_user (community_id is filled by fill_community_posts)
alter policy town_hall_posts_insert_active_user on public.town_hall_posts
  with check (
    (select auth.uid()) = user_id
    and (select public.is_active_user((select auth.uid())))
    and community_id = any ((select public.my_community_ids())::uuid[])
  );

-- [A10] public.town_hall_comments / "Authenticated users can view visible or own hidden town hall co" (name truncated by Postgres)
-- The posts subquery runs with invoker rights, so the post's own SELECT policy decides.
alter policy "Authenticated users can view visible or own hidden town hall co" on public.town_hall_comments
  using (
    (hidden_at is null or user_id = (select auth.uid()))
    and exists (select 1 from public.town_hall_posts p where p.id = town_hall_comments.post_id)
  );

-- [A11] public.town_hall_comments / "Guests can view visible town hall comments" (needs [G2] and [N1] first)
alter policy "Guests can view visible town hall comments" on public.town_hall_comments
  using (
    hidden_at is null
    and exists (select 1 from public.town_hall_posts p where p.id = town_hall_comments.post_id)
  );

-- [A12] public.town_hall_comments / town_hall_comments_insert_active_user
alter policy town_hall_comments_insert_active_user on public.town_hall_comments
  with check (
    (select auth.uid()) = user_id
    and (select public.is_active_user((select auth.uid())))
    and exists (select 1 from public.town_hall_posts p where p.id = town_hall_comments.post_id)
  );

-- [A13] public.town_hall_votes / "Users can view all votes"
alter policy "Users can view all votes" on public.town_hall_votes
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.town_hall_posts p where p.id = town_hall_votes.post_id)
    or exists (select 1 from public.town_hall_comments c where c.id = town_hall_votes.comment_id)
  );

-- [A14] public.town_hall_votes / "Users can create votes"
alter policy "Users can create votes" on public.town_hall_votes
  with check (
    (select auth.uid()) = user_id
    and (
      exists (select 1 from public.town_hall_posts p where p.id = town_hall_votes.post_id)
      or exists (select 1 from public.town_hall_comments c where c.id = town_hall_votes.comment_id)
    )
  );

-- [A15] public.town_hall_post_interactions / interactions_select_approved
alter policy interactions_select_approved on public.town_hall_post_interactions
  using (
    exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.approved = true)
    and (
      user_id = (select auth.uid())
      or exists (select 1 from public.town_hall_posts tp where tp.id = town_hall_post_interactions.post_id)
    )
  );

-- [A16] public.request_qa / "Approved users can view Q&A"
alter policy "Approved users can view Q&A" on public.request_qa
  using (
    coalesce((select p.approved from public.profiles p where p.id = (select auth.uid())), false)
    and (
      exists (select 1 from public.rides r where r.id = request_qa.ride_id)
      or exists (select 1 from public.favors f where f.id = request_qa.favor_id)
    )
  );

-- [A17] public.request_qa / request_qa_select_anon_guest
alter policy request_qa_select_anon_guest on public.request_qa
  using (
    exists (select 1 from public.guest_rides g where g.id = request_qa.ride_id)
    or exists (select 1 from public.guest_favors g where g.id = request_qa.favor_id)
  );

-- [A18] public.request_qa / "Approved users can create Q&A"
alter policy "Approved users can create Q&A" on public.request_qa
  with check (
    coalesce((select p.approved from public.profiles p where p.id = (select auth.uid())), false)
    and (select auth.uid()) = user_id
    and (
      exists (select 1 from public.rides r where r.id = request_qa.ride_id)
      or exists (select 1 from public.favors f where f.id = request_qa.favor_id)
    )
  );

-- [A19] public.ride_participants / ride_participants_select
alter policy ride_participants_select on public.ride_participants
  using (
    exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.approved = true)
    and exists (select 1 from public.rides r where r.id = ride_participants.ride_id)
  );

-- [A20] public.ride_participants / ride_participants_insert (the added person must be an active member of the ride's community)
alter policy ride_participants_insert on public.ride_participants
  with check (
    exists (
      select 1 from public.rides r
      where r.id = ride_participants.ride_id
        and r.user_id = (select auth.uid())
    )
    and added_by = (select auth.uid())
    and public.community_has_member(
      (select r.community_id from public.rides r where r.id = ride_participants.ride_id),
      ride_participants.user_id
    )
  );

-- [A21] public.favor_participants / favor_participants_select
alter policy favor_participants_select on public.favor_participants
  using (
    exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.approved = true)
    and exists (select 1 from public.favors f where f.id = favor_participants.favor_id)
  );

-- [A22] public.favor_participants / favor_participants_insert (the added person must be an active member of the favor's community)
alter policy favor_participants_insert on public.favor_participants
  with check (
    exists (
      select 1 from public.favors f
      where f.id = favor_participants.favor_id
        and f.user_id = (select auth.uid())
    )
    and added_by = (select auth.uid())
    and public.community_has_member(
      (select f.community_id from public.favors f where f.id = favor_participants.favor_id),
      favor_participants.user_id
    )
  );

-- [A23] public.reviews / "Approved users can view reviews"
-- Scopes the list of written reviews; the headline numbers come from get_profile_stats (step 3).
alter policy "Approved users can view reviews" on public.reviews
  using (
    coalesce((select p.approved from public.profiles p where p.id = (select auth.uid())), false)
    and (
      reviewer_id = (select auth.uid())
      or fulfiller_id = (select auth.uid())
      or exists (select 1 from public.rides r where r.id = reviews.ride_id)
      or exists (select 1 from public.favors f where f.id = reviews.favor_id)
    )
  );

-- [A24] public.reviews / reviews_select_anon_guest
alter policy reviews_select_anon_guest on public.reviews
  using (
    exists (select 1 from public.guest_rides g where g.id = reviews.ride_id)
    or exists (select 1 from public.guest_favors g where g.id = reviews.favor_id)
  );

-- [A25] public.conversation_participants / authenticated_users_can_add_participants
-- Creator-relative on purpose (spec rule 7): the creator may add only people who share a community with them.
alter policy authenticated_users_can_add_participants on public.conversation_participants
  with check (
    public.is_conversation_creator(conversation_id, (select auth.uid()))
    and public.shares_community_with(user_id)
  );

-- [A26] public.geocoding_cache / geocoding_cache_select_authenticated
alter policy geocoding_cache_select_authenticated on public.geocoding_cache
  using ((select public.is_active_user((select auth.uid()))));

-- [A27] public.geocoding_cache / geocoding_cache_insert_authenticated
alter policy geocoding_cache_insert_authenticated on public.geocoding_cache
  with check ((select public.is_active_user((select auth.uid()))));

-- [A28] public.geocoding_cache / geocoding_cache_update_authenticated
alter policy geocoding_cache_update_authenticated on public.geocoding_cache
  using ((select public.is_active_user((select auth.uid()))))
  with check ((select public.is_active_user((select auth.uid()))));
