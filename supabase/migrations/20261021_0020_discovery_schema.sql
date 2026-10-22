-- 20261021_0020_discovery_schema.sql
--
-- APPLIED 2026-10-22, all eleven blocks, through the Supabase MCP apply_migration, one call per block, in file order,
-- each block's text sent byte for byte from this file (from its banner to its last statement), after the rolled-back
-- dry run below passed. Migration-history versions (UTC): 20261022121932 20261021_0020_block_1, 20261022122053
-- 20261021_0020_block_2, 20261022122213 20261021_0020_block_3, 20261022122331 20261021_0020_block_4, 20261022122449
-- 20261021_0020_block_5, 20261022122608 20261021_0020_block_6, 20261022122733 20261021_0020_block_7, 20261022122852
-- 20261021_0020_block_8, 20261022123019 20261021_0020_block_9, 20261022123142 20261021_0020_block_10, 20261022123306
-- 20261021_0020_block_11. No deviation: every block ran as written below.
-- Deployed md5(prosrc), each read live after its block and equal to the md5 of the text between this file's
-- $function$ delimiters (python3 -I over this file; for my_visible_profile_ids, of 20261021_0001 Block 1's text with
-- the one replacement Block 9 makes):
--   great_circle_miles(double precision x4)  8c1c86fc15dd29fa96dcc76c51c4af72  definer, immutable, search_path ""
--   can_discover_community(uuid)              dc34406a6a5b18e2ff93684ec43de9a2  definer, stable, search_path ""
--   my_visible_profile_ids()                  c0dcb6110a793c3aafc62414d864bc77  (was d313d5213ce5e5790357dfec161d4087)
--   is_listed_request(uuid, uuid)             6a917931f989d3536a58d2b36788e815  (was dd27ebff7dbe18618e7b57a96cfacfb4)
--   guard_example_content()                   abba0dc60dd3dc370a17cc19a7c42d3f  invoker, volatile, search_path ""
-- ACL (proacl; has_function_privilege anon / authenticated / service_role):
--   great_circle_miles, can_discover_community, guard_example_content: {postgres=X/postgres,service_role=X/postgres};
--     false / false / true.
--   my_visible_profile_ids, is_listed_request: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,
--     service_role=X/postgres}; true / true / true (unchanged; see EXECUTE below).
-- Policies, md5(qual) before -> after (roles, command and permissive unchanged):
--   communities_select_anon                    0558c85ed30574684f06a6df450bd6bc -> c153237e4eb7c059123b8494557e669a
--   communities_select_authenticated           8e45ff0d64c736ee4d07a872354bf488 -> 66e0d5a4f0d075320c7216c550c39f02
--   "Guests can view visible town hall posts"  ea0754c65ea1cd24d7a5dd7c846b870f -> c987187a2598bdcc6398c288f6cd315e
--   "Approved users can view reviews"          07c042cd0afb86dbbeb7e8cc470e762d -> 0fec480f0f124f996f543173319c3293
--     (the deparsed qual after Block 11 is "(" || the qual before || " OR (((SELECT auth.uid() AS uid) IS NOT NULL)
--     AND is_listed_request(ride_id, favor_id)))": the old expression is kept byte for byte as its first arm).
-- Views, md5(pg_get_viewdef) after: guest_rides dce9de015f37434092769372384e59af, guest_favors
--   1c514498aa27170e42d3e68db491bea1, public_profiles 914b214f8a20ec7528565a5ff0d1f1ec; options
--   security_barrier=true, security_invoker=false and grants (anon select on the guest views; anon and authenticated
--   on public_profiles) kept. community_membership_events_event_check after: md5(pg_get_constraintdef)
--   ebaef39ab8b1ee84121bb7e60abdf49b (was b63bdff362732353cb118ae54389df13). The two new tables: RLS on, no policy,
--   relacl {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}. Trigger guard_example_content, BEFORE INSERT
--   OR UPDATE FOR EACH ROW, enabled on rides, favors and town_hall_posts.
-- After the apply: no community is is_test, no row is is_example, both new tables are empty (S5a sets the flags).
--
-- Closing run (task S6), 2026-10-22, after S5a's data (Test Community's area, the four test communities flagged
-- is_test, 4 example rides, 4 example favors and 3 example posts in Test Community). The whole probe file
-- (supabase/probes/communities_probe.sql, unchanged) ran through the MCP in seven rolled-back execute_sql calls,
-- PARAMETERS and HELPERS in each (the call for legacy_bridges .. blocks carried HELPERS up to probe_world, every
-- helper those blocks call), full-line comments stripped, text otherwise as committed: 34 blocks,
-- every one PROBE ... OK (legacy_bridges returns SKIPPED, as it has since 20261019_0060), each call's last row its
-- last block's OK. posts_delete_policy and storage_private are the owner's SQL-editor blocks; the final
-- 'PROBE ALL OK' row comes from the owner's whole-file run. Nothing was left behind (counted afterwards: no probe
-- account, community, request, post, proposal, listing event or merged community; 11 example rows, 4 test
-- communities, the cron job active, the five status and updated_at triggers enabled).
-- EXECUTE matrix (ruling R-G1 as amended after S1), read live: md5(prosrc) of all five functions equal the values
-- above. great_circle_miles, can_discover_community, guard_example_content: anon false, authenticated false.
-- my_visible_profile_ids, is_listed_request: anon true, authenticated true (the anon allow-list: policies and views
-- evaluate them as anon). select count(*) from community_listing_events and from community_merge_proposals raises
-- 42501 as authenticated and as anon; both tables RLS on, no policy, relacl as above. No header or grant changed.
--
-- File A of Community Release 2 (discovery: community areas, search, listing rules, merging, example content;
-- Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md 4.2, 4.6, 4.10, 4.11, 4.12; plan
-- Docs/superpowers/plans/2026-10-21-community-release2-discovery-sql.md, task S1, with the orchestrator's rulings
-- R-G1, R6, R9 and R18-R20). The columns, tables, predicates and the guard every later Release 2 file (0021-0023)
-- builds on.
--
-- What it does.
--   * Block 1, public.communities: a service area (area_name, area_center_lat, area_center_lng, area_radius_miles:
--     all four set or none, radius 1, 2, 5 or 10 miles, the centre inside -90..90 / -180..180, the name 2-80
--     characters after trimming), is_test (default false; set only in SQL by the orchestrator), merged_into_id
--     (on delete set null) and merged_at. CHECK communities_hidden_not_open (is_public or join_policy <> 'open'):
--     join_policy still allows only invite and approve until Release 3b, so no row can break it today. Partial
--     index communities_listed_live (id) where is_public and archived_at is null.
--   * Block 2, public.community_listing_events: why a community became listed or moved its area (created_listed,
--     listed, area_moved), with the area, the overlapping listed communities and the owner's reason (1-300
--     characters). RLS on, no policy, no privilege for public, anon or authenticated: definer code only (0021).
--   * Block 3, public.community_merge_proposals: a merge proposal between two communities (status pending,
--     accepted, declined, withdrawn, expired; expires after 7 days; the survivor is one of the two). At most one
--     pending proposal from and one pending proposal to each community (partial unique indexes). RLS on, no
--     policy, no client privilege: definer code only (0022).
--   * Block 4, community_membership_events_event_check: the 11 live events plus 'merged'.
--   * Block 5, is_example (not null, default false) on rides, favors and town_hall_posts, and
--     town_hall_posts.system_event (null or 'community_merged'); partial indexes <table>_examples (id) where
--     is_example.
--   * Block 6, two internal helpers. great_circle_miles(lat1, lng1, lat2, lng2): the haversine distance in miles
--     (earth radius 3958.8). can_discover_community(p_community_id): the community exists, is listed (is_public),
--     is not archived, and is not a test community unless the caller is a platform admin or an active member of it.
--     This predicate is "discoverable" in 0021-0023.
--   * Block 7, the guest views: guest_rides and guest_favors leave out test communities and gain is_example as their
--     last column; public_profiles' guest arm leaves out people whose only listed communities are test ones.
--   * Block 8, three policies leave out test communities: communities_select_anon (guests), the listed arm of
--     communities_select_authenticated (a signed-in person still reads a test community they belong to, administer,
--     or have applied to; a platform admin reads every one), and "Guests can view visible town hall posts".
--   * Block 9, my_visible_profile_ids() (its listed-member arm) and is_listed_request(uuid, uuid) (both arms) leave
--     out test communities.
--   * Block 10, guard_example_content() and its BEFORE INSERT OR UPDATE trigger on rides, favors and
--     town_hall_posts. For a client role (current_user authenticated or anon; definer code and the table owner
--     return at once): setting is_example at insert or changing it by update, or setting / changing
--     town_hall_posts.system_event, raises 42501 'example_flag_reserved'; changing claimed_by on a ride or favor
--     whose is_example is true raises 42501 'example_request' (the iOS client matches this text). The trigger name
--     sorts before guard_request_claim_membership and guard_request_client_update, so it fires first.
--   * Block 11, policy "Approved users can view reviews" (ruling R9): its live expression, verbatim, or a signed-in
--     caller and a review of a visible request in a listed, non-test community. A signed-in visitor with no
--     membership (approved false; the search-first Get started visitor of spec 4.6) reads the reviews of listed
--     communities, as an approved visitor and a guest already do. Anon is unchanged (the new arm needs a JWT subject;
--     guests keep reviews_select_anon_guest, which reads the guest views).
--
-- EXECUTE (ruling R-G1; the public schema's default ACL grants EXECUTE on every new function to anon, authenticated
-- and service_role, so each block that creates or re-creates a function ends with its ACL):
--   great_circle_miles, can_discover_community, guard_example_content: internal, revoked from public, anon and
--     authenticated (postgres and service_role keep EXECUTE). A trigger function needs no EXECUTE by the writer.
--   my_visible_profile_ids(), is_listed_request(uuid, uuid): the live ACL restated, unchanged: EXECUTE for anon,
--     authenticated and service_role, none for public. Implementer decision: R-G1's "from public, anon" would break
--     guests, because anon evaluates both: public_profiles (anon reads it) calls my_visible_profile_ids(), and the
--     reviews policy above (TO public, so anon evaluates it) calls is_listed_request; PostgreSQL checks EXECUTE when
--     it starts the expression, whether or not the branch is taken.
--
-- What old clients see. Installed builds (Release 1 and earlier) send none of the new columns and no build sets
-- is_example or system_event, so the guard refuses nothing they do. Rows they read with select=* carry the new keys
-- (the client ignores unknown keys); guest_rides and guest_favors gain is_example. Until a community is flagged
-- is_test nothing they read changes, except that a signed-in account with no membership now reads the reviews of
-- listed communities (Block 11), which no installed build asks for before an approval. Once a community is flagged
-- (S5a: the four test communities), guests and signed-in non-members no longer see it, its requests, posts or its
-- only-test members in lists, guest views and public_profiles; its members and platform admins still do. Once
-- example rows exist (S5a), a claim of one from any build is refused with 42501 'example_request', which builds
-- before Release 2 show as their generic claim error.
--
-- Apply order. Blocks 1-11 in file order, one Supabase MCP apply_migration per block, named
-- 20261021_0020_block_<n>, each block's text byte for byte from this file, after the rolled-back dry run
-- (supabase/dryruns/20261021_0020_discovery_schema.dryrun.sql) passed; probe short after each block. Block 11 last.
-- Nothing here is declined by the MCP (no DELETE, no DROP POLICY, no DROP FUNCTION, no DROP TABLE, no DROP TRIGGER;
-- Block 4 drops and re-adds a CHECK constraint in one ALTER TABLE, which the MCP accepted before, 20261019_0001
-- block 1). Block 9 checks the live md5 of my_visible_profile_ids before and after its edit and stops on a mismatch.
--
-- Verification (supabase/probes/communities_probe.sql; every run through execute_sql, rolled back, with the probe
-- PARAMETERS and the whole HELPERS section in the same call). Outcomes, 2026-10-22:
--   P1-P4 read just before the dry run; P1 and P2 read again after it (before Block 1), the two function md5s again
--   before Block 9 and the reviews md5(qual) again before Block 11: each time the values above, unchanged.
--   Dry run: supabase/dryruns/20261021_0020_discovery_schema.dryrun.sql, assembled by script from the committed
--   files, structural check passed (no commit; one begin; one rollback; 9 savepoints and 9 releases; helpers before
--   begin; last two statements the DRYRUN select and rollback;), sent verbatim in one call: DRYRUN 20261021_0020 OK
--   after the nine probe blocks test_flag_visibility, example_guard, listed_reviews, community_preview,
--   listed_profiles, reputation, isolation, noop_default and short (each raises on its first failed check, so the
--   final row means all nine passed). Afterwards none of the new objects existed and every P1 value was unchanged.
--   An earlier rolled-back development run of Blocks 1-11 with the three new probes read the in-transaction md5s and
--   the ACLs above.
--   Implementer check of the EXECUTE decision (rolled back): with anon's EXECUTE revoked, anon's select from
--   public_profiles failed with 42501 "permission denied for function my_visible_profile_ids" and its select from
--   reviews with 42501 "permission denied for function is_listed_request"; the live ACLs were unchanged afterwards.
--   Apply: short after each of the eleven blocks: PROBE short OK eleven times.
--   After Block 11: test_flag_visibility, example_guard, listed_reviews, community_preview, listed_profiles,
--   reputation, isolation and noop_default, one call each: all OK. No probe account, community, request, review,
--   post, proposal or listing event was left behind (counted afterwards).
--
-- Implementer decisions (recorded for the review).
--   1. EXECUTE of the two re-created functions: R-G1 says a re-created function ends with "revoke ... from public,
--      anon" when signed-in clients call it; my_visible_profile_ids and is_listed_request are evaluated by anon
--      (public_profiles, the reviews policy), so Block 9 restates their live ACL instead (the brief's "grants
--      unchanged"); the check above shows the R-G1 form would have broken every guest.
--   2. great_circle_miles is security definer (the plan's Global Constraints: definer unless stated otherwise); it is
--      pure arithmetic and revoked from client roles, so definer changes nothing but inlining.
--   3. Block 11 embeds the deparsed live qual verbatim (unqualified names resolve through the apply session's
--      search_path); its md5 was checked equal to 07c042cd before the apply.
--   4. listed_reviews reads ruling R9's "anon reads none through the table" as: anon reads no review beyond what
--      reviews_select_anon_guest gives it through the guest views, and not the C4 one; anon does read the C2 review
--      through the guest views (the existing guest path), which the block checks as a control.
--   5. noop_default's four guest expectations leave out test communities once communities.is_test exists (to_jsonb,
--      so the block still runs before this file), as the views and policies of Blocks 7-8 do; without it the block
--      would fail once S5a flags a listed community that has rows or test-only members.
--   6. The guest views' comments now say "non-test"; public_profiles' comment is restated unchanged.
--
-- P1, the live values read on 2026-10-22 before this file (the rollback sources):
--   my_visible_profile_ids() md5(prosrc) d313d5213ce5e5790357dfec161d4087 (20261021_0001 Block 1);
--   is_listed_request(uuid, uuid) dd27ebff7dbe18618e7b57a96cfacfb4 (20261021_0001 Block 2); both
--   {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
--   Views (pg_get_viewdef equal to 20261017_0002 [V1]-[V3]): guest_rides md5 c7fb43a5d4dc97241f73b14e34efbf58,
--   guest_favors 506f3a076407f6eeb793231b997ff6cf, public_profiles ec99996a70a7f187709f9083ffc8a47a.
--   Policies md5(qual): communities_select_anon 0558c85ed30574684f06a6df450bd6bc ([N1]),
--   communities_select_authenticated 8e45ff0d64c736ee4d07a872354bf488 ([N2]), "Guests can view visible town hall
--   posts" ea0754c65ea1cd24d7a5dd7c846b870f ([A08]), "Approved users can view reviews"
--   07c042cd0afb86dbbeb7e8cc470e762d (20261021_0001 Block 3).
--   community_membership_events_event_check: the 11 events of 20261017_0001:217.
--   P2: none of the new tables, columns, constraints, indexes, functions or the trigger exists. P3: the seven
--   triggers of the plan exist. P4: no 20261021_0020-0023 file or migration-history entry.
--
-- Rollback (in reverse order, after 0021-0023 are rolled back; Blocks 1-6 only while no Release 2 client is installed).
--   Block 11 (MCP): alter policy "Approved users can view reviews" on public.reviews using (<the P1 qual>), the
--     deparsed text below, one line per "--   | " line (md5(qual) 07c042cd0afb86dbbeb7e8cc470e762d):
--   | (COALESCE(( SELECT p.approved
--   |    FROM profiles p
--   |   WHERE (p.id = ( SELECT auth.uid() AS uid))), false) AND ((reviewer_id = ( SELECT auth.uid() AS uid)) OR (fulfiller_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
--   |    FROM rides r
--   |   WHERE (r.id = reviews.ride_id))) OR (EXISTS ( SELECT 1
--   |    FROM favors f
--   |   WHERE (f.id = reviews.favor_id))) OR is_listed_request(ride_id, favor_id)))
--   Block 10 (SQL editor, owner; the MCP declines DROP TRIGGER and DROP FUNCTION):
--     drop trigger guard_example_content on public.rides;
--     drop trigger guard_example_content on public.favors;
--     drop trigger guard_example_content on public.town_hall_posts;
--     drop function public.guard_example_content();
--   Block 9 (MCP): my_visible_profile_ids() from 20261021_0001 Block 1 and is_listed_request(uuid, uuid) from
--     20261021_0001 Block 2 (the P1 md5 values); the ACLs stay as they are.
--   Block 8 (MCP): the three alter policy statements of 20261017_0002 [N1], [N2] and [A08] (the P1 md5 values).
--   Block 7 (MCP; ruling R6): guest_rides and guest_favors re-created from 20261017_0002 [V1] / [V2] with
--     r.is_example / f.is_example kept as the last column (create or replace view cannot drop a column, and the
--     policies reviews_select_anon_guest and request_qa_select_anon_guest depend on the views), public_profiles
--     from [V3], the comments of [V4] / [V5]. Removing the is_example column from the two views is the owner's
--     SQL-editor step with Block 5 below.
--   Block 6 (SQL editor, owner): drop function public.can_discover_community(uuid);
--     drop function public.great_circle_miles(double precision, double precision, double precision, double precision);
--   Block 5 (SQL editor, owner, after Blocks 7-10): drop policy reviews_select_anon_guest on public.reviews; drop
--     policy request_qa_select_anon_guest on public.request_qa; drop view public.guest_rides; drop view
--     public.guest_favors; re-create both views from [V1] / [V2] with their grants (revoke all from public, anon,
--     authenticated; grant select to anon) and comments [V4] / [V5]; re-create the two policies (TO anon, SELECT,
--     the expressions of 20261017_0002 [A24] and [A17]); then drop index public.rides_examples, public.favors_examples,
--     public.town_hall_posts_examples; alter table public.rides drop column is_example; alter table public.favors drop
--     column is_example; alter table public.town_hall_posts drop column system_event, drop column is_example.
--   Block 4 (MCP or SQL editor): alter table public.community_membership_events drop constraint
--     community_membership_events_event_check, add constraint community_membership_events_event_check check (event in
--     ('applied', 'invited', 'approved', 'rejected', 'removed', 'readmitted', 'left', 'role_changed',
--     'ownership_transferred', 'archived', 'unarchived')). It fails once any 'merged' event row exists (0022 writes
--     them); such rows would have to go first, which is a DELETE (SQL editor, owner).
--   Block 3 (SQL editor, owner): drop table public.community_merge_proposals;
--   Block 2 (SQL editor, owner): drop table public.community_listing_events;
--   Block 1 (SQL editor, owner, after Blocks 6-9): drop index public.communities_listed_live; alter table
--     public.communities drop constraint communities_hidden_not_open, drop constraint communities_area_name, drop
--     constraint communities_area_center, drop constraint communities_area_radius, drop constraint
--     communities_area_all_or_none, drop column merged_at, drop column merged_into_id, drop column is_test, drop column
--     area_radius_miles, drop column area_center_lng, drop column area_center_lat, drop column area_name;


-- ============================================================================================
-- BLOCK 1: public.communities   service area, is_test, merge columns, CHECKs, listed index
-- ============================================================================================
alter table public.communities
  add column area_name text,
  add column area_center_lat double precision,
  add column area_center_lng double precision,
  add column area_radius_miles integer,
  add column is_test boolean not null default false,
  add column merged_into_id uuid references public.communities (id) on delete set null,
  add column merged_at timestamptz,
  add constraint communities_area_all_or_none check (
    (area_name is null and area_center_lat is null and area_center_lng is null and area_radius_miles is null)
    or (area_name is not null and area_center_lat is not null and area_center_lng is not null
        and area_radius_miles is not null)),
  add constraint communities_area_radius check (area_radius_miles in (1, 2, 5, 10)),
  add constraint communities_area_center check (
    area_center_lat between -90 and 90 and area_center_lng between -180 and 180),
  add constraint communities_area_name check (char_length(btrim(area_name)) between 2 and 80),
  add constraint communities_hidden_not_open check (is_public or join_policy <> 'open');

create index communities_listed_live on public.communities (id) where is_public and archived_at is null;


-- ============================================================================================
-- BLOCK 2: public.community_listing_events   (new; definer code only)
-- ============================================================================================
create table public.community_listing_events (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete set null,
  event text not null check (event in ('created_listed', 'listed', 'area_moved')),
  area_name text,
  area_center_lat double precision,
  area_center_lng double precision,
  area_radius_miles integer,
  overlapping_ids uuid[] not null default '{}',
  reason text check (reason is null or char_length(reason) between 1 and 300),
  created_at timestamptz not null default now()
);

create index community_listing_events_community_created
  on public.community_listing_events (community_id, created_at desc);

alter table public.community_listing_events enable row level security;

revoke all on table public.community_listing_events from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 3: public.community_merge_proposals   (new; definer code only)
-- ============================================================================================
create table public.community_merge_proposals (
  id uuid primary key default gen_random_uuid(),
  from_community_id uuid not null references public.communities (id) on delete cascade,
  to_community_id uuid not null references public.communities (id) on delete cascade,
  survivor_community_id uuid not null references public.communities (id) on delete cascade,
  proposed_by uuid references public.profiles (id) on delete set null,
  note text check (note is null or char_length(note) <= 300),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'withdrawn', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  decided_at timestamptz,
  decided_by uuid references public.profiles (id) on delete set null,
  check (from_community_id <> to_community_id),
  check (survivor_community_id in (from_community_id, to_community_id))
);

create unique index community_merge_one_pending_from
  on public.community_merge_proposals (from_community_id) where status = 'pending';

create unique index community_merge_one_pending_to
  on public.community_merge_proposals (to_community_id) where status = 'pending';

create index community_merge_proposals_to_status
  on public.community_merge_proposals (to_community_id, status);

alter table public.community_merge_proposals enable row level security;

revoke all on table public.community_merge_proposals from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 4: community_membership_events_event_check   (the 11 live events plus 'merged')
-- ============================================================================================
alter table public.community_membership_events
  drop constraint community_membership_events_event_check,
  add constraint community_membership_events_event_check check (event in (
    'applied', 'invited', 'approved', 'rejected', 'removed', 'readmitted', 'left', 'role_changed',
    'ownership_transferred', 'archived', 'unarchived', 'merged'));


-- ============================================================================================
-- BLOCK 5: is_example on rides, favors, town_hall_posts; town_hall_posts.system_event
-- ============================================================================================
alter table public.rides add column is_example boolean not null default false;

alter table public.favors add column is_example boolean not null default false;

alter table public.town_hall_posts
  add column is_example boolean not null default false,
  add column system_event text
    constraint town_hall_posts_system_event_check check (system_event is null or system_event = 'community_merged');

create index rides_examples on public.rides (id) where is_example;

create index favors_examples on public.favors (id) where is_example;

create index town_hall_posts_examples on public.town_hall_posts (id) where is_example;


-- ============================================================================================
-- BLOCK 6: public.great_circle_miles(...), public.can_discover_community(uuid)   (new; internal)
-- ============================================================================================
create or replace function public.great_circle_miles(
  lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
parallel safe
security definer
set search_path = ''
as $function$
  select 2 * 3958.8 * asin(least(1, sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2)
         + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))));
$function$;

revoke all on function public.great_circle_miles(double precision, double precision, double precision, double precision)
  from public, anon, authenticated;

create or replace function public.can_discover_community(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.communities c
     where c.id = p_community_id
       and c.is_public
       and c.archived_at is null
       and (not c.is_test
            or public.is_platform_admin()
            or c.id = any ((select public.my_community_ids())::uuid[])));
$function$;

revoke all on function public.can_discover_community(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 7: views guest_rides, guest_favors (no test communities; is_example appended) and public_profiles (its
-- guest arm leaves out test communities). 20261017_0002 [V1]-[V5] with those changes; grants are kept by
-- create or replace.
-- ============================================================================================
create or replace view public.guest_rides
with (security_barrier = true, security_invoker = false) as
select
    r.id, r.user_id, r.type, r.date, r."time",
    ''::text as pickup,
    ''::text as destination,
    r.seats, r.notes, r.gift, r.status, r.claimed_by, r.reviewed, r.review_skipped, r.review_skipped_at,
    r.created_at, r.updated_at, r.estimated_cost, r.flight_normalized, r.timezone,
    r.hidden_at, r.hidden_by, r.hidden_reason,
    r.community_id,
    r.is_example
from public.rides r
join public.communities c on c.id = r.community_id
where r.hidden_at is null
  and c.is_public
  and c.archived_at is null
  and not c.is_test;

create or replace view public.guest_favors
with (security_barrier = true, security_invoker = false) as
select
    f.id, f.user_id, f.title, f.description,
    ''::text as location,
    f.duration, f.requirements, f.date, f."time", f.gift, f.status, f.claimed_by, f.reviewed,
    f.review_skipped, f.review_skipped_at, f.created_at, f.updated_at, f.timezone,
    f.hidden_at, f.hidden_by, f.hidden_reason,
    f.community_id,
    f.is_example
from public.favors f
join public.communities c on c.id = f.community_id
where f.hidden_at is null
  and c.is_public
  and c.archived_at is null
  and not c.is_test;

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
         and not c.is_test
     )
   );

comment on view public.guest_rides is 'Rides as a guest may see them: visible rows of public, non-archived, non-test communities, pickup and destination blanked.';

comment on view public.guest_favors is 'Favors as a guest may see them: visible rows of public, non-archived, non-test communities, location blanked.';

comment on view public.public_profiles is 'Non-PII projection of profiles for cross-user display. Bypasses profiles RLS (security_invoker=false). Callers needing full-row data (self, admin) must query profiles directly.';


-- ============================================================================================
-- BLOCK 8: policies communities_select_anon, communities_select_authenticated, "Guests can view visible town hall
-- posts"   (20261017_0002 [N1], [N2], [A08], test communities left out of the listed arm)
-- ============================================================================================
alter policy communities_select_anon on public.communities
  using (is_public and not is_test and archived_at is null);

alter policy communities_select_authenticated on public.communities
  using (
    archived_at is null
    and (
      (is_public and not is_test)
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

alter policy "Guests can view visible town hall posts" on public.town_hall_posts
  using (
    hidden_at is null
    and exists (
      select 1 from public.communities c
      where c.id = town_hall_posts.community_id
        and c.is_public
        and c.archived_at is null
        and not c.is_test
    )
  );


-- ============================================================================================
-- BLOCK 9: public.my_visible_profile_ids()   live md5 d313d5213ce5e5790357dfec161d4087 (20261021_0001 Block 1)
-- Derived from the live definition (the 20261019_0060 block 2 pattern): the passage
--     c.is_public and c.archived_at is null
-- (the listed-member arm) must occur exactly once; it becomes
--     c.is_public and c.archived_at is null and not c.is_test
-- Deployed md5 must be c0dcb6110a793c3aafc62414d864bc77.
-- public.is_listed_request(uuid, uuid)   live md5 dd27ebff7dbe18618e7b57a96cfacfb4 (20261021_0001 Block 2)
-- Rewritten in full: both arms gain "and not c.is_test". Signature unchanged.
-- Both ACLs restated unchanged (anon evaluates both; see EXECUTE in the header).
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.my_visible_profile_ids()'::regprocedure;
  v_old constant text := 'c.is_public and c.archived_at is null';
  v_new constant text := 'c.is_public and c.archived_at is null and not c.is_test';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'd313d5213ce5e5790357dfec161d4087' then
    raise exception 'my_visible_profile_ids is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'my_visible_profile_ids: the listed-member passage was not found exactly once';
  end if;
  execute replace(v_def, v_old, v_new);
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'c0dcb6110a793c3aafc62414d864bc77' then
    raise exception 'my_visible_profile_ids: unexpected body after the edit';
  end if;
end
$derive$;

revoke all on function public.my_visible_profile_ids() from public;
grant execute on function public.my_visible_profile_ids() to anon, authenticated, service_role;

create or replace function public.is_listed_request(p_ride_id uuid, p_favor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (select 1 from public.rides r
                   join public.communities c on c.id = r.community_id
                  where r.id = p_ride_id and r.hidden_at is null and c.is_public and c.archived_at is null
                    and not c.is_test)
      or exists (select 1 from public.favors f
                   join public.communities c on c.id = f.community_id
                  where f.id = p_favor_id and f.hidden_at is null and c.is_public and c.archived_at is null
                    and not c.is_test);
$function$;

revoke all on function public.is_listed_request(uuid, uuid) from public;
grant execute on function public.is_listed_request(uuid, uuid) to anon, authenticated, service_role;


-- ============================================================================================
-- BLOCK 10: public.guard_example_content()   (new; invoker trigger function) and its trigger on rides, favors and
-- town_hall_posts
-- ============================================================================================
create or replace function public.guard_example_content()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  -- definer code and the table owner (the seed, set_example_content, the merge) are not client writes
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.is_example then
      raise exception 'example_flag_reserved' using errcode = '42501';
    end if;
    if tg_table_name = 'town_hall_posts' then
      if new.system_event is not null then
        raise exception 'example_flag_reserved' using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  if new.is_example is distinct from old.is_example then
    raise exception 'example_flag_reserved' using errcode = '42501';
  end if;

  if tg_table_name = 'town_hall_posts' then
    if new.system_event is distinct from old.system_event then
      raise exception 'example_flag_reserved' using errcode = '42501';
    end if;
    return new;
  end if;

  -- rides and favors: an example request cannot be claimed or unclaimed by a client
  if old.is_example and new.claimed_by is distinct from old.claimed_by then
    raise exception 'example_request' using errcode = '42501';
  end if;
  return new;
end
$function$;

revoke all on function public.guard_example_content() from public, anon, authenticated;

create or replace trigger guard_example_content
  before insert or update on public.rides
  for each row execute function public.guard_example_content();

create or replace trigger guard_example_content
  before insert or update on public.favors
  for each row execute function public.guard_example_content();

create or replace trigger guard_example_content
  before insert or update on public.town_hall_posts
  for each row execute function public.guard_example_content();


-- ============================================================================================
-- BLOCK 11: public.reviews / "Approved users can view reviews"   live md5(qual) 07c042cd0afb86dbbeb7e8cc470e762d
-- (20261021_0001 Block 3). Ruling R9: the live qual verbatim (pg_get_expr(polqual, polrelid)) or a signed-in
-- caller and public.is_listed_request(ride_id, favor_id). Apply last.
-- ============================================================================================
alter policy "Approved users can view reviews" on public.reviews
  using ((COALESCE(( SELECT p.approved
   FROM profiles p
  WHERE (p.id = ( SELECT auth.uid() AS uid))), false) AND ((reviewer_id = ( SELECT auth.uid() AS uid)) OR (fulfiller_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM rides r
  WHERE (r.id = reviews.ride_id))) OR (EXISTS ( SELECT 1
   FROM favors f
  WHERE (f.id = reviews.favor_id))) OR is_listed_request(ride_id, favor_id)))
    or ((select auth.uid()) is not null and public.is_listed_request(ride_id, favor_id)));
