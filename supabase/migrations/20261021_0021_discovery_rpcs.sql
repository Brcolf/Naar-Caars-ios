-- 20261021_0021_discovery_rpcs.sql
--
-- APPLIED 2026-10-22, all eight blocks, through the Supabase MCP apply_migration, one call per block, in file order,
-- each block's text sent byte for byte from this file (from its banner to its last statement), after the rolled-back
-- dry run below passed. Migration-history versions (UTC): 20261022132829 20261021_0021_block_1, 20261022133037
-- 20261021_0021_block_2, 20261022133201 20261021_0021_block_3, 20261022133337 20261021_0021_block_4, 20261022133515
-- 20261021_0021_block_5, 20261022133639 20261021_0021_block_6, 20261022133811 20261021_0021_block_7, 20261022133935
-- 20261021_0021_block_8. No deviation: every block ran as written below.
-- Deployed md5(prosrc), each read live after the apply and equal to the md5 of the text between this file's
-- $function$ delimiters (python3 -I over this file):
--   search_communities_by_name(text)                          b4b529dab1ea723987508b284ed8dcc9  plpgsql, stable
--   find_communities_near(double precision, double precision) 4bbcb758ef3a22dd27b9f445cf26a965  plpgsql, stable
--   overlapping_listed_communities(double precision, double precision, integer, uuid)
--                                                             6bba53d116095861adb7ff5e24541780  sql, stable
--   check_community_area(double precision, double precision, integer, uuid)
--                                                             fe1c01768f86e4cc3018482707cf4c09  plpgsql, stable
--   create_community_with_area(text, text, text, text, boolean, text, double precision, double precision, integer,
--     text)                                                   7ab0ac7ca0e4f3d0069b1c3f3a07028c  plpgsql, volatile
--   update_community_access(uuid, boolean, text, text, double precision, double precision, integer, text)
--                                                             fe5d0583912df0735db4ba877e5216ab  plpgsql, volatile
--   set_community_public(uuid, boolean)   c003b61d4204febf019f33e55b771639 (was be06eb7f873a1631bd743a572f9cee11)
--   get_community_preview(uuid)           82e74630b0502ec7b661c7b2afb12791 (was 6cf9b87e5ed8cb8214f1e1f4b8a5035c)
--   get_platform_communities()            a44cdb53dbbd040504e56bf7aa853494 (was 7e6f81c814ef2affa0382b86d73e4d02).
--     Ruling R5: 20261021_0022 derives its edit of get_platform_communities() and that edit's rollback from this
--     deployed body (md5 a44cdb53dbbd040504e56bf7aa853494), not from 20261017_0005.
--   All nine are security definer with search_path "". create_community(text, text, text, text) is unchanged
--   (b499c74a3371cc051f02a4bcd19b54f3, its ACL unchanged) and stays for Release 1 builds.
-- ACL (proacl; has_function_privilege anon / authenticated / service_role), read live after the apply:
--   search_communities_by_name, find_communities_near, get_community_preview:
--     {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}; true / true / true.
--   check_community_area, create_community_with_area, update_community_access, set_community_public,
--     get_platform_communities: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres};
--     false / true / true. For set_community_public and get_platform_communities this is the live ACL restated
--     unchanged (read before the apply: the same text).
--   overlapping_listed_communities: {postgres=X/postgres,service_role=X/postgres}; false / false / true.
-- After the apply: no community has a service area and community_listing_events is empty (S5a gives the live
-- communities their areas). Read in a rolled-back transaction as anon: search_communities_by_name('test') answered
-- success with the 3 listed communities, find_communities_near at a Seattle point success with no row.
--
-- File B of Community Release 2 (discovery: community areas, search, listing rules, merging, example content;
-- Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md 4.2, 4.6, 4.10; plan
-- Docs/superpowers/plans/2026-10-21-community-release2-discovery-sql.md, task S2, with the orchestrator's rulings
-- R-G1, R-G4, R5, R8, R12 and R21). The client-facing discovery RPCs, built on File A (20261021_0020): the area
-- columns, can_discover_community(uuid) ("discoverable": listed, not archived, and not a test community unless the
-- caller is a platform admin or an active member of it), great_circle_miles(...) and community_listing_events.
--
-- What it does.
--   * Shared row shape of Blocks 1-3 (key "communities", at most 20 rows): {id, name, description, join_policy,
--     area_name, area_radius_miles, member_count (active members whose account is not banned), distance_miles
--     (round(<miles>::numeric, 1), or null)}. Refusals are {"success": false, "error", "code"}.
--   * Block 1, search_communities_by_name(p_query) -> jsonb (new; stable): the query is trimmed and cut to 60
--     characters; fewer than 2 characters answers {success: true, communities: []}; otherwise the discoverable
--     communities whose name contains the text, case-insensitive (strpos, no LIKE, so % _ and \ are literal),
--     names that start with it first, then by name and id; distance_miles null.
--   * Block 2, find_communities_near(p_lat, p_lng) -> jsonb (new; stable): a null point, a latitude outside
--     -90..90 or a longitude outside -180..180 (NaN included) answers code invalid_area; otherwise the discoverable
--     communities with an area whose circle covers the point, nearest first, then by name and id; distance_miles
--     from the point.
--   * Spec 4.2 privacy: Blocks 1 and 2 write nothing, raise nothing that carries their arguments, and are stable;
--     the device coordinate reaches only find_communities_near.
--   * Block 3, overlapping_listed_communities(p_center_lat, p_center_lng, p_radius_miles, p_exclude) (new; internal):
--     the discoverable communities with an area, other than p_exclude, whose circle overlaps the given one (centre
--     distance < their radius + p_radius_miles), nearest first, at most 20, distance_miles between the centres; and
--     check_community_area(p_center_lat, p_center_lng, p_radius_miles, p_community_id default null) -> jsonb (new;
--     stable; signed-in callers): an invalid point or a radius other than 1, 2, 5 or 10 answers invalid_area,
--     otherwise {success: true, communities: <the helper's rows>}.
--   * Block 4, create_community_with_area(p_name, p_description, p_join_policy, p_timezone, p_listed, p_area_name,
--     p_center_lat, p_center_lng, p_radius_miles, p_reason) -> jsonb {success, community_id} (new name; the live
--     create_community(text, text, text, text) stays for Release 1 builds). The live text of create_community
--     (20261019_0001 Block 3, md5 b499c74a3371cc051f02a4bcd19b54f3) with, in order: an unknown join policy (only
--     invite and approve) refused with code invalid; when p_listed, no area argument at all -> needs_area, and any
--     one missing, out of range, a radius not in (1, 2, 5, 10), an area name that is not 2-80 characters after
--     trimming or that holds a house number ('(^|[[:space:]])[0-9]{1,6}[[:space:]]+[[:alpha:]]') -> invalid_area;
--     after the two limits, a listed community whose area overlaps discoverable ones needs a reason
--     (reason_required when none); any reason longer than 300 characters -> reason_required (ruling R12). The row
--     is inserted with is_public = p_listed and, when listed, the area; a listed creation writes a created_listed
--     community_listing_events row (the area, the overlapping ids in distance order, the reason only when the
--     overlap list is not empty). Platform admins' bell rows (the live loop, no push) read 'Created by <name>.',
--     then ' Listed · <area> (<r> mi).' when listed and ' Reason: <reason>' when one was stored. A hidden creation
--     ignores the area arguments and stores no reason.
--   * Block 5, update_community_access(p_community_id, p_listed, p_join_policy, p_area_name, p_center_lat,
--     p_center_lng, p_radius_miles, p_reason) -> jsonb {success, changed} (new; the owner only, platform admins are
--     not owners here). Refusals in this order (ruling R8): no auth.uid() -> not_owner; no unarchived community with
--     that id -> invalid; my_community_role(id) is distinct from 'owner' -> not_owner; p_listed or p_join_policy null,
--     or a policy other than invite / approve -> invalid; the default community with p_listed false ->
--     default_stays_listed; area arguments sent but not all valid (Block 4's rules) -> invalid_area; the resulting
--     area (the new one when sent, else the stored one) missing while listed -> needs_area; a reason longer than 300
--     characters, or becoming listed (or staying listed with a new area different from the stored one) while
--     overlapping discoverable communities (itself excluded) with no reason -> reason_required. The row is locked
--     (select ... for update) and updated once, only when something changed (changed columns only; area columns
--     only when an area was sent). community_listing_events: 'listed' for hidden -> listed, 'area_moved' for a
--     listed community that stays listed with a changed area. Hidden -> listed also gives every platform admin a
--     bell row (no push) 'Now listed: <name>' / '<area> (<r> mi).' [+ ' Reason: <reason>']. A change of is_public or
--     join_policy gives every other active member (account not banned) an announcement bell row (no push)
--     '<name> changed how people join' / '<Listed|Hidden> · <Ask to join|Invite only>.'.
--   * Block 6, set_community_public(uuid, boolean): the live text (20261017_0005 Block 12, md5
--     be06eb7f873a1631bd743a572f9cee11) with the select also reading area_center_lat and, before the update,
--     {success: false, error: 'A listed community needs a service area', code: 'needs_area'} when p_is_public and
--     the community has no area. Platform admins keep it for unlisting (A2).
--   * Block 7, get_community_preview(uuid): the live text (20261021_0001 Block 4, md5
--     6cf9b87e5ed8cb8214f1e1f4b8a5035c) with the community read whether or not archived; an archived community
--     merged into one the caller may discover answers {success: false, error: 'Community merged', code: 'merged',
--     merged_into_id, merged_into_name}; any other archived, hidden, or test community the caller may not discover
--     answers not_listed (members of a test community and platform admins pass); the community object gains
--     area_name, area_center_lat, area_center_lng and area_radius_miles, and each request object gains is_example.
--   * Block 8, get_platform_communities(): the live text (20261017_0005 Block 32, md5
--     7e6f81c814ef2affa0382b86d73e4d02) with every community row gaining area_name, area_center_lat,
--     area_center_lng, area_radius_miles, is_test, merged_into_id, merged_into_name, listing_event, listing_reason,
--     listing_overlaps (the names of the newest listing event's overlapping_ids, in its order; [] for an event with
--     none; null without an event) and listing_event_at, all from the community's newest community_listing_events
--     row; the top level gains merge_proposals ('[]' here; 20261021_0022 fills it from this body, ruling R5).
--
-- EXECUTE (ruling R-G1; the public schema's default ACL grants EXECUTE on every new function to anon, authenticated
-- and service_role, so each block ends with its ACL):
--   search_communities_by_name(text), find_communities_near(double precision, double precision): revoked from
--     public; anon, authenticated and service_role.
--   check_community_area, create_community_with_area, update_community_access: revoked from public and anon;
--     authenticated and service_role.
--   overlapping_listed_communities: internal; revoked from public, anon and authenticated (service_role keeps it).
--   set_community_public(uuid, boolean), get_platform_communities(): the live ACL restated (revoked from public and
--     anon; authenticated and service_role). get_community_preview(uuid): the live ACL restated (revoked from
--     public; anon, authenticated and service_role).
--
-- What old clients see. Installed builds (Release 1 and earlier) call none of Blocks 1-5. get_community_preview now
-- refuses a test community to a caller who is not its member or a platform admin (no community is is_test until
-- S5a), which a Release 1 build shows as its "community unavailable" state (code not_listed); an archived merged
-- community answers code 'merged' (no merge exists until 20261021_0022), which a Release 1 build does not know and
-- shows as its generic load-failed state (CommunityPageViewModel). It ignores the added area and is_example keys.
-- set_community_public(id, true) now refuses a community without a service area with code needs_area, which the
-- installed Admin -> Communities screen shows as its generic error; unlisting is unchanged. No community has an
-- area until S5a or an owner sets one, so until then a platform admin cannot list a hidden community from an
-- installed build. get_platform_communities() answers the same keys plus new ones, which installed builds ignore.
--
-- Apply order. Blocks 1-8 in file order, one Supabase MCP apply_migration per block, named
-- 20261021_0021_block_<n>, each block's text byte for byte from this file (banner to last statement), after the
-- rolled-back dry run (supabase/dryruns/20261021_0021_discovery_rpcs.dryrun.sql) passed; probe short after each
-- block. Nothing here is declined by the MCP (no DELETE, no DROP of any kind).
--
-- Verification (supabase/probes/communities_probe.sql; every run through execute_sql, rolled back, with the probe
-- PARAMETERS and the whole HELPERS section in the same call). Outcomes, 2026-10-22:
--   P0-P4 read before the file was written: get_community_preview(uuid) and is_listed_request(uuid, uuid) exist and
--   20261021_0001 reads APPLIED; the P1 md5 values below equal the live bodies and the source files' text; none of
--   the six new functions existed; no 20261021_0021 file or migration-history entry.
--   Dry run: supabase/dryruns/20261021_0021_discovery_rpcs.dryrun.sql, assembled by script from the committed files,
--   structural check passed (no commit; one begin; one rollback; 4 savepoints and 4 releases; 4 PROBE selects;
--   helpers before begin; last two statements the DRYRUN select and rollback;), sent verbatim in one call:
--   DRYRUN 20261021_0021 OK after discovery_search, listing_rules, community_preview and short (each raises on its
--   first failed check, so the final row means all four passed). The first full attempt stopped in listing_rules
--   at its members' notice check: probe_world's open C1 ride had already written new_ride bell rows for C1's
--   members, u4 included. That check and the no-push check were narrowed to the two titles this file writes, the
--   script re-assembled, and the second full run passed; the functions were not changed. An earlier rolled-back
--   development run of Blocks 1-8 with discovery_search passed. Afterwards none of the six new functions existed
--   and the P1 md5 values were unchanged.
--   Apply: short after each of the eight blocks: PROBE short OK eight times (after Block 1 also an earlier run with
--   only the helpers short calls, then the whole HELPERS section). The three P1 md5 values were read again just
--   before Block 6: unchanged.
--   After Block 8: discovery_search with listing_rules in one call, community_preview with test_flag_visibility in
--   another (each block its own begin; ... rollback;): all OK. No probe community, profile, listing event or notice
--   was left behind (counted afterwards).
--
-- Implementer decisions (recorded for the review).
--   1. Area names are trimmed of all leading and trailing white space ([[:space:]], not only the spaces btrim
--      removes, as the S1 review asked) before the 2-80 check and the house-number check, and stored trimmed;
--      communities_area_name (btrim) then always holds.
--   2. Ruling R12 is applied literally: a reason over 300 characters (after btrim) is refused with reason_required
--      in every call of Blocks 4 and 5, including a hidden creation (which otherwise ignores the reason) and an
--      update that computes no overlap. The client caps the reason at 300, so this is unreachable from the app.
--   3. "Every other active member" (Block 5) leaves out banned accounts, as my_community_ids() does; the platform
--      admins' loops are the live create loop's (not banned, not the caller).
--   4. Block 5 runs its single update only when something changed, with case expressions that keep unchanged
--      columns (no column trigger depends on them; set_updated_at_communities bumps updated_at anyway).
--   5. The brief names the refusal codes; the error texts not given by it are mine: 'Choose a service area'
--      (invalid_area outside Block 2), 'A listed community needs a service area' (needs_area, as Block 6), 'Only the
--      owner can change how people join' (not_owner), 'Community not found' / 'Choose listed or hidden and how
--      people join' (invalid), 'The default community stays listed' (default_stays_listed), and 'Say why this
--      community is needed beside the listed ones that cover this area (up to 300 characters)' (reason_required).
--   6. Ties: Blocks 1-3 order by name, then id after the brief's keys. Block 8 picks the newest listing event by
--      created_at desc, id desc; two events written in one transaction share created_at, which no RPC call does.
--   7. Probes: "nothing written by the searches" is checked with pg_stat_xact_user_tables (this transaction's own
--      inserts, updates and deletes in every user table, communities, notifications and community_listing_events
--      included) rather than table row counts, which concurrent live notifications could change between two reads.
--      C1's area in discovery_search is set by its owner through update_community_access (hidden, no event). The
--      probes add, beyond the brief: the EXECUTE and definer checks of all nine functions, the prefix order, a
--      literal '0%' match, the 60-character cut, a circle's edge, NaN and Infinity points, a banned member not
--      counted, merged previews, check_community_area's cases, a policy change, an area move, unlisting, R12 in
--      both functions, a hidden creation that ignores area arguments, and get_platform_communities' keys.
--
-- P1, the live values read on 2026-10-22 before this file (the rollback sources; each equal to the md5 of the text
-- between its source file's delimiters, python3 -I):
--   create_community(text, text, text, text)  b499c74a3371cc051f02a4bcd19b54f3 (20261019_0001 Block 3; unchanged)
--   set_community_public(uuid, boolean)        be06eb7f873a1631bd743a572f9cee11 (20261017_0005 Block 12)
--   get_community_preview(uuid)                6cf9b87e5ed8cb8214f1e1f4b8a5035c (20261021_0001 Block 4)
--   get_platform_communities()                 7e6f81c814ef2affa0382b86d73e4d02 (20261017_0005 Block 32)
--
-- Rollback (in reverse order; Blocks 1-5 only while no Release 2 client is installed).
--   Block 8 (MCP): get_platform_communities() from 20261017_0005 Block 32 (md5 7e6f81c814ef2affa0382b86d73e4d02);
--     the ACL stays as it is. Once 20261021_0022 has re-created it, roll that file back first.
--   Block 7 (MCP): get_community_preview(uuid) from 20261021_0001 Block 4 (md5 6cf9b87e5ed8cb8214f1e1f4b8a5035c).
--   Block 6 (MCP): set_community_public(uuid, boolean) from 20261017_0005 Block 12 (md5
--     be06eb7f873a1631bd743a572f9cee11).
--   Blocks 1-5 (SQL editor, owner; the MCP declines DROP FUNCTION):
--     drop function public.update_community_access(uuid, boolean, text, text, double precision, double precision,
--       integer, text);
--     drop function public.create_community_with_area(text, text, text, text, boolean, text, double precision,
--       double precision, integer, text);
--     drop function public.check_community_area(double precision, double precision, integer, uuid);
--     drop function public.overlapping_listed_communities(double precision, double precision, integer, uuid);
--     drop function public.find_communities_near(double precision, double precision);
--     drop function public.search_communities_by_name(text);
--   community_listing_events rows written by Blocks 4-5 stay (File A's table; its own rollback drops it).


-- ============================================================================================
-- BLOCK 1: public.search_communities_by_name(text)   (new; anon, authenticated, service_role)
-- ============================================================================================
create or replace function public.search_communities_by_name(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_q text := left(btrim(coalesce(p_query, '')), 60);
  v_rows jsonb;
begin
  -- Spec 4.2: the text is used for this answer only; nothing is written, raised or logged.
  if char_length(v_q) < 2 then
    return jsonb_build_object('success', true, 'communities', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'name', s.name,
           'description', s.description,
           'join_policy', s.join_policy,
           'area_name', s.area_name,
           'area_radius_miles', s.area_radius_miles,
           'member_count', s.member_count,
           'distance_miles', null::numeric)
         order by s.starts_with desc, s.name, s.id), '[]'::jsonb)
    into v_rows
    from (
      select c.id, c.name, c.description, c.join_policy, c.area_name, c.area_radius_miles,
             strpos(lower(c.name), lower(v_q)) = 1 as starts_with,
             (select count(*) from public.community_members m
                join public.profiles p on p.id = m.user_id
               where m.community_id = c.id and m.status = 'active'
                 and not coalesce(p.is_banned, false))::integer as member_count
        from public.communities c
       where c.is_public and c.archived_at is null
         and strpos(lower(c.name), lower(v_q)) > 0
         and public.can_discover_community(c.id)
       order by strpos(lower(c.name), lower(v_q)) = 1 desc, c.name, c.id
       limit 20
    ) s;

  return jsonb_build_object('success', true, 'communities', v_rows);
end
$function$;

revoke all on function public.search_communities_by_name(text) from public;
grant execute on function public.search_communities_by_name(text) to anon, authenticated, service_role;


-- ============================================================================================
-- BLOCK 2: public.find_communities_near(double precision, double precision)   (new; anon, authenticated,
-- service_role)
-- ============================================================================================
create or replace function public.find_communities_near(p_lat double precision, p_lng double precision)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_rows jsonb;
begin
  -- Spec 4.2: the point is used for this answer only; nothing is written, raised or logged.
  if p_lat is null or p_lng is null
     or not (p_lat between -90 and 90) or not (p_lng between -180 and 180) then
    return jsonb_build_object('success', false, 'error', 'Choose a town or ZIP code', 'code', 'invalid_area');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'name', s.name,
           'description', s.description,
           'join_policy', s.join_policy,
           'area_name', s.area_name,
           'area_radius_miles', s.area_radius_miles,
           'member_count', s.member_count,
           'distance_miles', round(s.miles::numeric, 1))
         order by s.miles, s.name, s.id), '[]'::jsonb)
    into v_rows
    from (
      select d.id, d.name, d.description, d.join_policy, d.area_name, d.area_radius_miles, d.miles,
             (select count(*) from public.community_members m
                join public.profiles p on p.id = m.user_id
               where m.community_id = d.id and m.status = 'active'
                 and not coalesce(p.is_banned, false))::integer as member_count
        from (
          select c.id, c.name, c.description, c.join_policy, c.area_name, c.area_radius_miles,
                 public.great_circle_miles(c.area_center_lat, c.area_center_lng, p_lat, p_lng) as miles
            from public.communities c
           where c.is_public and c.archived_at is null and c.area_radius_miles is not null
        ) d
       where d.miles <= d.area_radius_miles
         and public.can_discover_community(d.id)
       order by d.miles, d.name, d.id
       limit 20
    ) s;

  return jsonb_build_object('success', true, 'communities', v_rows);
end
$function$;

revoke all on function public.find_communities_near(double precision, double precision) from public;
grant execute on function public.find_communities_near(double precision, double precision)
  to anon, authenticated, service_role;


-- ============================================================================================
-- BLOCK 3: public.overlapping_listed_communities(...)   (new; internal) and
-- public.check_community_area(double precision, double precision, integer, uuid)   (new; authenticated,
-- service_role)
-- ============================================================================================
create or replace function public.overlapping_listed_communities(
  p_center_lat double precision, p_center_lng double precision, p_radius_miles integer, p_exclude uuid)
returns table (id uuid, name text, description text, join_policy text, area_name text, area_radius_miles integer,
               member_count integer, distance_miles numeric)
language sql
stable
security definer
set search_path = ''
as $function$
  select d.id, d.name, d.description, d.join_policy, d.area_name, d.area_radius_miles,
         (select count(*) from public.community_members m
            join public.profiles p on p.id = m.user_id
           where m.community_id = d.id and m.status = 'active'
             and not coalesce(p.is_banned, false))::integer,
         round(d.miles::numeric, 1)
    from (
      select c.id, c.name, c.description, c.join_policy, c.area_name, c.area_radius_miles,
             public.great_circle_miles(c.area_center_lat, c.area_center_lng, p_center_lat, p_center_lng) as miles
        from public.communities c
       where c.is_public and c.archived_at is null and c.area_radius_miles is not null
         and c.id is distinct from p_exclude
    ) d
   where d.miles < d.area_radius_miles + p_radius_miles
     and public.can_discover_community(d.id)
   order by d.miles, d.name, d.id
   limit 20;
$function$;

revoke all on function public.overlapping_listed_communities(double precision, double precision, integer, uuid)
  from public, anon, authenticated;

create or replace function public.check_community_area(
  p_center_lat double precision, p_center_lng double precision, p_radius_miles integer,
  p_community_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_rows jsonb;
begin
  if p_center_lat is null or p_center_lng is null or p_radius_miles is null
     or not (p_center_lat between -90 and 90) or not (p_center_lng between -180 and 180)
     or p_radius_miles not in (1, 2, 5, 10) then
    return jsonb_build_object('success', false, 'error', 'Choose a service area', 'code', 'invalid_area');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o.id,
           'name', o.name,
           'description', o.description,
           'join_policy', o.join_policy,
           'area_name', o.area_name,
           'area_radius_miles', o.area_radius_miles,
           'member_count', o.member_count,
           'distance_miles', o.distance_miles)
         order by o.ord), '[]'::jsonb)
    into v_rows
    from public.overlapping_listed_communities(p_center_lat, p_center_lng, p_radius_miles, p_community_id)
         with ordinality as o(id, name, description, join_policy, area_name, area_radius_miles, member_count,
                              distance_miles, ord);

  return jsonb_build_object('success', true, 'communities', v_rows);
end
$function$;

revoke all on function public.check_community_area(double precision, double precision, integer, uuid)
  from public, anon;
grant execute on function public.check_community_area(double precision, double precision, integer, uuid)
  to authenticated, service_role;


-- ============================================================================================
-- BLOCK 4: public.create_community_with_area(...)   (new name; create_community(text, text, text, text) stays)
-- The live text of create_community (20261019_0001 Block 3, md5 b499c74a3371cc051f02a4bcd19b54f3) with the policy
-- code, the listed area checks, the overlap reason, is_public and the area on the insert, the created_listed event
-- and the longer admin body.
-- ============================================================================================
create or replace function public.create_community_with_area(
    p_name text,
    p_description text default null,
    p_join_policy text default 'approve',
    p_timezone text default null,
    p_listed boolean default false,
    p_area_name text default null,
    p_center_lat double precision default null,
    p_center_lng double precision default null,
    p_radius_miles integer default null,
    p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_profile record;
  v_name text := btrim(coalesce(p_name, ''));
  v_desc text := nullif(btrim(coalesce(p_description, '')), '');
  v_policy text := coalesce(p_join_policy, 'approve');
  v_tz text := nullif(btrim(coalesce(p_timezone, '')), '');
  v_listed boolean := coalesce(p_listed, false);
  v_area_name text := regexp_replace(coalesce(p_area_name, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_overlaps uuid[] := '{}'::uuid[];
  v_stored_reason text;
  v_body text;
  v_max integer;
  v_owned integer;
  v_id uuid;
  v_admin uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in to create a community');
  end if;

  select p.name, p.is_banned, p.max_owned_communities into v_profile
    from public.profiles p where p.id = v_uid;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Finish creating your profile first');
  end if;
  if coalesce(v_profile.is_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  if char_length(v_name) not between 2 and 60 then
    return jsonb_build_object('success', false, 'error', 'A community name needs 2 to 60 characters');
  end if;
  if v_desc is not null and char_length(v_desc) > 300 then
    return jsonb_build_object('success', false, 'error', 'The description can be at most 300 characters');
  end if;
  if v_policy not in ('invite', 'approve') then
    return jsonb_build_object('success', false, 'error', 'Unknown join policy', 'code', 'invalid');
  end if;
  -- A listed community needs a whole, valid service area; a hidden one ignores the area and the reason.
  if v_listed then
    if p_area_name is null and p_center_lat is null and p_center_lng is null and p_radius_miles is null then
      return jsonb_build_object('success', false, 'error', 'A listed community needs a service area',
                                'code', 'needs_area');
    end if;
    if p_area_name is null or p_center_lat is null or p_center_lng is null or p_radius_miles is null
       or not (p_center_lat between -90 and 90) or not (p_center_lng between -180 and 180)
       or p_radius_miles not in (1, 2, 5, 10)
       or char_length(v_area_name) not between 2 and 80
       or v_area_name ~ '(^|[[:space:]])[0-9]{1,6}[[:space:]]+[[:alpha:]]' then
      return jsonb_build_object('success', false, 'error', 'Choose a service area', 'code', 'invalid_area');
    end if;
  end if;
  -- A zone the server does not know falls back to the column default; it never refuses the creation.
  if v_tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names t where t.name = v_tz) then
    v_tz := null;
  end if;

  -- Serialize per account so the two limits cannot be raced (the submit_report idiom).
  perform pg_advisory_xact_lock(hashtextextended('create_community:' || v_uid::text, 0));

  if exists (select 1 from public.communities c
              where c.created_by = v_uid and c.created_at > now() - interval '1 day') then
    return jsonb_build_object('success', false,
      'error', 'You can create one community a day. Try again tomorrow.', 'code', 'daily_limit');
  end if;

  v_max := coalesce(v_profile.max_owned_communities, 3);
  select count(*) into v_owned
    from public.community_members m
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = v_uid and m.status = 'active' and m.role = 'owner';
  if v_owned >= v_max then
    return jsonb_build_object('success', false,
      'error', 'You already own ' || v_owned || ' communities, the most your account allows.',
      'code', 'owned_limit', 'max_owned', v_max, 'owned_count', v_owned);
  end if;

  -- A listed area that overlaps discoverable listed communities needs a reason; a reason is at most 300
  -- characters (ruling R12) and is kept only when there is an overlap.
  if v_listed then
    v_overlaps := array(select o.id
                          from public.overlapping_listed_communities(p_center_lat, p_center_lng, p_radius_miles, null)
                               with ordinality as o(id, name, description, join_policy, area_name, area_radius_miles,
                                                    member_count, distance_miles, ord)
                         order by o.ord);
  end if;
  if char_length(v_reason) > 300 or (cardinality(v_overlaps) > 0 and v_reason is null) then
    return jsonb_build_object('success', false,
      'error', 'Say why this community is needed beside the listed ones that cover this area (up to 300 characters)',
      'code', 'reason_required');
  end if;
  if cardinality(v_overlaps) > 0 then
    v_stored_reason := v_reason;
  end if;

  insert into public.communities (name, description, created_by, join_policy, is_public,
                                  area_name, area_center_lat, area_center_lng, area_radius_miles)
  values (v_name, v_desc, v_uid, v_policy, v_listed,
          case when v_listed then v_area_name end,
          case when v_listed then p_center_lat end,
          case when v_listed then p_center_lng end,
          case when v_listed then p_radius_miles end)
  returning id into v_id;

  if v_tz is not null then
    update public.communities set timezone = v_tz where id = v_id;
  end if;

  -- A creator is already looking at the app: no "you've been approved" notice.
  perform set_config('naars.suppress_approval_notice', '1', true);
  insert into public.community_members (community_id, user_id, role, status, activated_at)
  values (v_id, v_uid, 'owner', 'active', now());
  perform set_config('naars.suppress_approval_notice', '', true);

  insert into public.community_membership_events (community_id, user_id, actor_id, event, new_role, reason)
  values (v_id, v_uid, v_uid, 'approved', 'owner', 'created the community');

  if v_listed then
    insert into public.community_listing_events (community_id, actor_id, event, area_name, area_center_lat,
                                                 area_center_lng, area_radius_miles, overlapping_ids, reason)
    values (v_id, v_uid, 'created_listed', v_area_name, p_center_lat, p_center_lng, p_radius_miles, v_overlaps,
            v_stored_reason);
  end if;

  v_body := 'Created by ' || coalesce(nullif(btrim(v_profile.name), ''), 'a member') || '.';
  if v_listed then
    v_body := v_body || ' Listed · ' || v_area_name || ' (' || p_radius_miles || ' mi).';
    if v_stored_reason is not null then
      v_body := v_body || ' Reason: ' || v_stored_reason;
    end if;
  end if;

  for v_admin in
    select p.id from public.profiles p
     where p.is_admin and not coalesce(p.is_banned, false) and p.id <> v_uid
  loop
    perform public.notify_user_in_community(
      v_admin, 'announcement', 'New community: ' || v_name,
      v_body,
      v_id, false, '{}'::jsonb, v_uid
    );
  end loop;

  return jsonb_build_object('success', true, 'community_id', v_id);
end
$function$;

revoke all on function public.create_community_with_area(text, text, text, text, boolean, text, double precision,
  double precision, integer, text) from public, anon;
grant execute on function public.create_community_with_area(text, text, text, text, boolean, text, double precision,
  double precision, integer, text) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 5: public.update_community_access(...)   (new; the owner's listed switch, join policy and service area)
-- ============================================================================================
create or replace function public.update_community_access(
    p_community_id uuid,
    p_listed boolean,
    p_join_policy text,
    p_area_name text default null,
    p_center_lat double precision default null,
    p_center_lng double precision default null,
    p_radius_miles integer default null,
    p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_c public.communities%rowtype;
  v_area_sent boolean := p_area_name is not null or p_center_lat is not null or p_center_lng is not null
                         or p_radius_miles is not null;
  v_area_name text := regexp_replace(coalesce(p_area_name, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_new_name text;
  v_new_lat double precision;
  v_new_lng double precision;
  v_new_radius integer;
  v_public_changed boolean;
  v_policy_changed boolean;
  v_area_changed boolean := false;
  v_overlaps uuid[] := '{}'::uuid[];
  v_stored_reason text;
  v_user uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Only the owner can change how people join',
                              'code', 'not_owner');
  end if;
  if p_community_id is null
     or not exists (select 1 from public.communities c where c.id = p_community_id and c.archived_at is null) then
    return jsonb_build_object('success', false, 'error', 'Community not found', 'code', 'invalid');
  end if;
  -- is distinct from: a caller with no active membership gets null from my_community_role (ruling R8)
  if public.my_community_role(p_community_id) is distinct from 'owner' then
    return jsonb_build_object('success', false, 'error', 'Only the owner can change how people join',
                              'code', 'not_owner');
  end if;

  select c.* into v_c
    from public.communities c
   where c.id = p_community_id and c.archived_at is null
   for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Community not found', 'code', 'invalid');
  end if;

  if p_listed is null or p_join_policy is null or p_join_policy not in ('invite', 'approve') then
    return jsonb_build_object('success', false, 'error', 'Choose listed or hidden and how people join',
                              'code', 'invalid');
  end if;
  if v_c.is_default and not p_listed then
    return jsonb_build_object('success', false, 'error', 'The default community stays listed',
                              'code', 'default_stays_listed');
  end if;
  if v_area_sent and not coalesce(
       p_area_name is not null and p_center_lat is not null and p_center_lng is not null and p_radius_miles is not null
       and p_center_lat between -90 and 90 and p_center_lng between -180 and 180
       and p_radius_miles in (1, 2, 5, 10)
       and char_length(v_area_name) between 2 and 80
       and v_area_name !~ '(^|[[:space:]])[0-9]{1,6}[[:space:]]+[[:alpha:]]', false) then
    return jsonb_build_object('success', false, 'error', 'Choose a service area', 'code', 'invalid_area');
  end if;

  if v_area_sent then
    v_new_name := v_area_name;
    v_new_lat := p_center_lat;
    v_new_lng := p_center_lng;
    v_new_radius := p_radius_miles;
    v_area_changed := (v_new_name, v_new_lat, v_new_lng, v_new_radius)
                      is distinct from (v_c.area_name, v_c.area_center_lat, v_c.area_center_lng, v_c.area_radius_miles);
  else
    v_new_name := v_c.area_name;
    v_new_lat := v_c.area_center_lat;
    v_new_lng := v_c.area_center_lng;
    v_new_radius := v_c.area_radius_miles;
  end if;

  if p_listed and v_new_radius is null then
    return jsonb_build_object('success', false, 'error', 'A listed community needs a service area',
                              'code', 'needs_area');
  end if;

  v_public_changed := v_c.is_public is distinct from p_listed;
  v_policy_changed := v_c.join_policy is distinct from p_join_policy;

  -- Becoming listed, or moving a listed area: overlapping discoverable communities (itself excluded) need a
  -- reason; a reason is at most 300 characters (ruling R12) and is kept only when there is an overlap.
  if p_listed and (not v_c.is_public or v_area_changed) then
    v_overlaps := array(select o.id
                          from public.overlapping_listed_communities(v_new_lat, v_new_lng, v_new_radius, p_community_id)
                               with ordinality as o(id, name, description, join_policy, area_name, area_radius_miles,
                                                    member_count, distance_miles, ord)
                         order by o.ord);
  end if;
  if char_length(v_reason) > 300 or (cardinality(v_overlaps) > 0 and v_reason is null) then
    return jsonb_build_object('success', false,
      'error', 'Say why this community is needed beside the listed ones that cover this area (up to 300 characters)',
      'code', 'reason_required');
  end if;
  if cardinality(v_overlaps) > 0 then
    v_stored_reason := v_reason;
  end if;

  if not (v_public_changed or v_policy_changed or v_area_changed) then
    return jsonb_build_object('success', true, 'changed', false);
  end if;

  update public.communities
     set is_public = case when v_public_changed then p_listed else is_public end,
         join_policy = case when v_policy_changed then p_join_policy else join_policy end,
         area_name = case when v_area_changed then v_new_name else area_name end,
         area_center_lat = case when v_area_changed then v_new_lat else area_center_lat end,
         area_center_lng = case when v_area_changed then v_new_lng else area_center_lng end,
         area_radius_miles = case when v_area_changed then v_new_radius else area_radius_miles end,
         updated_at = now()
   where id = p_community_id;

  if p_listed and not v_c.is_public then
    insert into public.community_listing_events (community_id, actor_id, event, area_name, area_center_lat,
                                                 area_center_lng, area_radius_miles, overlapping_ids, reason)
    values (p_community_id, v_uid, 'listed', v_new_name, v_new_lat, v_new_lng, v_new_radius, v_overlaps,
            v_stored_reason);

    for v_user in
      select p.id from public.profiles p
       where p.is_admin and not coalesce(p.is_banned, false) and p.id <> v_uid
    loop
      perform public.notify_user_in_community(
        v_user, 'announcement', 'Now listed: ' || v_c.name,
        v_new_name || ' (' || v_new_radius || ' mi).' || coalesce(' Reason: ' || v_stored_reason, ''),
        p_community_id, false, '{}'::jsonb, v_uid
      );
    end loop;
  elsif p_listed and v_area_changed then
    insert into public.community_listing_events (community_id, actor_id, event, area_name, area_center_lat,
                                                 area_center_lng, area_radius_miles, overlapping_ids, reason)
    values (p_community_id, v_uid, 'area_moved', v_new_name, v_new_lat, v_new_lng, v_new_radius, v_overlaps,
            v_stored_reason);
  end if;

  if v_public_changed or v_policy_changed then
    for v_user in
      select m.user_id
        from public.community_members m
        join public.profiles p on p.id = m.user_id
       where m.community_id = p_community_id and m.status = 'active' and m.user_id <> v_uid
         and not coalesce(p.is_banned, false)
    loop
      perform public.notify_user_in_community(
        v_user, 'announcement', v_c.name || ' changed how people join',
        case when p_listed then 'Listed' else 'Hidden' end || ' · '
          || case when p_join_policy = 'invite' then 'Invite only' else 'Ask to join' end || '.',
        p_community_id, false, '{}'::jsonb, v_uid
      );
    end loop;
  end if;

  return jsonb_build_object('success', true, 'changed', true);
end
$function$;

revoke all on function public.update_community_access(uuid, boolean, text, text, double precision, double precision,
  integer, text) from public, anon;
grant execute on function public.update_community_access(uuid, boolean, text, text, double precision, double precision,
  integer, text) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 6: public.set_community_public(uuid, boolean)   live md5 be06eb7f873a1631bd743a572f9cee11
-- (20261017_0005 Block 12) with the select reading area_center_lat and the needs_area refusal before the update
-- ============================================================================================
create or replace function public.set_community_public(p_community_id uuid, p_is_public boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_default boolean;
  v_area_lat double precision;
begin
  if (select auth.uid()) is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;
  if p_is_public is null then
    return jsonb_build_object('success', false, 'error', 'Choose public or private');
  end if;

  select c.is_default, c.area_center_lat into v_default, v_area_lat
    from public.communities c where c.id = p_community_id and c.archived_at is null;
  if v_default is null then
    return jsonb_build_object('success', false, 'error', 'Community not found');
  end if;
  if v_default and not p_is_public then
    return jsonb_build_object('success', false, 'error', 'The default community stays public');
  end if;
  if p_is_public and v_area_lat is null then
    return jsonb_build_object('success', false, 'error', 'A listed community needs a service area',
                              'code', 'needs_area');
  end if;

  update public.communities set is_public = p_is_public, updated_at = now()
   where id = p_community_id and is_public is distinct from p_is_public;

  return jsonb_build_object('success', true);
end
$function$;

revoke all on function public.set_community_public(uuid, boolean) from public, anon;
grant execute on function public.set_community_public(uuid, boolean) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 7: public.get_community_preview(uuid)   live md5 6cf9b87e5ed8cb8214f1e1f4b8a5035c (20261021_0001 Block 4)
-- with archived rows read (merged -> code merged), the discoverable check, the area keys and is_example
-- ============================================================================================
create or replace function public.get_community_preview(p_community_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_c public.communities%rowtype;
  v_merged_into_name text;
  v_member_count bigint;
  v_requests jsonb;
  v_posts jsonb;
begin
  if p_community_id is not null then
    select c.* into v_c
      from public.communities c
     where c.id = p_community_id;
  end if;
  if v_c.id is null then
    return jsonb_build_object('success', false, 'error', 'Community not found', 'code', 'not_listed');
  end if;
  -- an archived community: say where a merged one went when the caller may discover that community
  if v_c.archived_at is not null then
    if v_c.merged_into_id is not null and public.can_discover_community(v_c.merged_into_id) then
      select c.name into v_merged_into_name from public.communities c where c.id = v_c.merged_into_id;
      return jsonb_build_object('success', false, 'error', 'Community merged', 'code', 'merged',
                                'merged_into_id', v_c.merged_into_id, 'merged_into_name', v_merged_into_name);
    end if;
    return jsonb_build_object('success', false, 'error', 'Community not found', 'code', 'not_listed');
  end if;
  -- hidden, or a test community the caller may not discover
  if not public.can_discover_community(v_c.id) then
    return jsonb_build_object('success', false, 'error', 'Community not found', 'code', 'not_listed');
  end if;

  select count(*) into v_member_count
    from public.community_members m
   where m.community_id = v_c.id and m.status = 'active';

  select coalesce(jsonb_agg(jsonb_build_object(
           'type', q.kind,
           'id', q.id,
           'title', q.title,
           'date', to_char(q.date, 'YYYY-MM-DD'),
           'time', q."time"::text,
           'timezone', q.timezone,
           'seats', q.seats,
           'poster_id', q.poster_id,
           'poster_name', q.poster_name,
           'poster_avatar_url', q.poster_avatar_url,
           'is_example', q.is_example)
         order by q.date, q."time" nulls last, q.id), '[]'::jsonb)
    into v_requests
    from (
      select x.kind, x.id, x.title, x.date, x."time", x.timezone, x.seats, x.poster_id, x.is_example,
             p.name as poster_name, p.avatar_url as poster_avatar_url
        from (
          select 'ride'::text as kind, r.id, null::text as title, r.date, r."time", r.timezone, r.seats,
                 r.user_id as poster_id, r.is_example
            from public.rides r
           where r.community_id = v_c.id and r.status = 'open' and r.claimed_by is null and r.hidden_at is null
             and r.date >= (now() at time zone coalesce(r.timezone, v_c.timezone))::date
          union all
          select 'favor'::text, f.id, f.title, f.date, f."time", f.timezone, null::integer,
                 f.user_id, f.is_example
            from public.favors f
           where f.community_id = v_c.id and f.status = 'open' and f.claimed_by is null and f.hidden_at is null
             and f.date >= (now() at time zone coalesce(f.timezone, v_c.timezone))::date
        ) x
        join public.profiles p on p.id = x.poster_id
       where not coalesce(p.is_banned, false)
         and (v_uid is null or not exists (
               select 1 from public.blocked_users b
                where (b.blocker_id = v_uid and b.blocked_id = x.poster_id)
                   or (b.blocker_id = x.poster_id and b.blocked_id = v_uid)))
       order by x.date, x."time" nulls last, x.id
       limit 10
    ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', q.id,
           'type', q.type,
           'title', q.title,
           'content', q.content,
           'created_at', q.created_at,
           'author_id', q.author_id,
           'author_name', q.author_name,
           'author_avatar_url', q.author_avatar_url,
           'comment_count', q.comment_count)
         order by q.created_at desc, q.id desc), '[]'::jsonb)
    into v_posts
    from (
      select t.id, t.type, t.title, left(t.content, 280) as content, t.created_at, t.user_id as author_id,
             p.name as author_name, p.avatar_url as author_avatar_url,
             (select count(*) from public.town_hall_comments k
               where k.post_id = t.id and k.hidden_at is null) as comment_count
        from public.town_hall_posts t
        join public.profiles p on p.id = t.user_id
       where t.community_id = v_c.id and t.hidden_at is null
         and not coalesce(p.is_banned, false)
         and (v_uid is null or not exists (
               select 1 from public.blocked_users b
                where (b.blocker_id = v_uid and b.blocked_id = t.user_id)
                   or (b.blocker_id = t.user_id and b.blocked_id = v_uid)))
       order by t.created_at desc, t.id desc
       limit 5
    ) q;

  return jsonb_build_object(
    'success', true,
    'community', jsonb_build_object(
      'id', v_c.id,
      'name', v_c.name,
      'description', v_c.description,
      'join_policy', v_c.join_policy,
      'is_public', v_c.is_public,
      'is_default', v_c.is_default,
      'member_count', v_member_count,
      'timezone', v_c.timezone,
      'area_name', v_c.area_name,
      'area_center_lat', v_c.area_center_lat,
      'area_center_lng', v_c.area_center_lng,
      'area_radius_miles', v_c.area_radius_miles),
    'requests', v_requests,
    'posts', v_posts);
end
$function$;

revoke all on function public.get_community_preview(uuid) from public;
grant execute on function public.get_community_preview(uuid) to anon, authenticated, service_role;


-- ============================================================================================
-- BLOCK 8: public.get_platform_communities()   live md5 7e6f81c814ef2affa0382b86d73e4d02 (20261017_0005 Block 32)
-- with the area, test, merge and listing keys per community and merge_proposals ('[]' until 20261021_0022)
-- ============================================================================================
create or replace function public.get_platform_communities()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_communities jsonb;
  v_requests jsonb;
begin
  if (select auth.uid()) is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.archived_at nulls first, s.created_at desc), '[]'::jsonb)
    into v_communities
    from (
      select c.id, c.name, c.description, c.created_by, cp.name as creator_name, c.created_at,
             c.is_public, c.is_default, c.join_policy, c.archived_at, c.archived_by,
             (select count(*) from public.community_members m
               where m.community_id = c.id and m.status = 'active') as member_count,
             (select count(*) from public.community_members m
               where m.community_id = c.id and m.status = 'pending') as pending_count,
             (select count(*) from public.community_members m
               where m.community_id = c.id and m.status = 'active' and m.role = 'owner') as owner_count,
             (select count(*) from public.reports r
               where r.reported_community_id = c.id and r.status = 'pending') as open_report_count,
             c.area_name, c.area_center_lat, c.area_center_lng, c.area_radius_miles, c.is_test,
             c.merged_into_id, mi.name as merged_into_name,
             le.event as listing_event,
             le.reason as listing_reason,
             case when le.event is null then null::text[]
                  else coalesce((select array_agg(o.name order by u.ord)
                                   from unnest(le.overlapping_ids) with ordinality as u(id, ord)
                                   join public.communities o on o.id = u.id), '{}'::text[])
             end as listing_overlaps,
             le.created_at as listing_event_at
        from public.communities c
        left join public.profiles cp on cp.id = c.created_by
        left join public.communities mi on mi.id = c.merged_into_id
        left join lateral (
          select e.event, e.reason, e.overlapping_ids, e.created_at
            from public.community_listing_events e
           where e.community_id = c.id
           order by e.created_at desc, e.id desc
           limit 1
        ) le on true
    ) s;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at), '[]'::jsonb)
    into v_requests
    from (
      select r.id as request_id, r.user_id, p.name as user_name, r.requested_max, r.reason, r.created_at,
             coalesce(p.max_owned_communities, 3) as current_max,
             (select count(*) from public.community_members m
                join public.communities c on c.id = m.community_id and c.archived_at is null
               where m.user_id = r.user_id and m.status = 'active' and m.role = 'owner') as owned_count
        from public.community_limit_requests r
        join public.profiles p on p.id = r.user_id
       where r.status = 'pending'
    ) s;

  return jsonb_build_object('success', true, 'communities', v_communities, 'limit_requests', v_requests,
                            'merge_proposals', '[]'::jsonb);
end
$function$;

revoke all on function public.get_platform_communities() from public, anon;
grant execute on function public.get_platform_communities() to authenticated, service_role;
