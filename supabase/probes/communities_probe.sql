-- supabase/probes/communities_probe.sql
--
-- The committed probe for the multi-community build (Docs/superpowers/specs/2026-10-07-multi-community-design.md
-- §4 "The short probe" and "The full probe matrix", plus the cases added by decisions A1-A3 of
-- Docs/superpowers/specs/2026-10-17-multi-community-decisions.md). Migration headers cite a run of this file.
--
-- WHAT IT IS
--   A parameter section, a helper section (session-local functions in pg_temp, gone at disconnect), and one
--   block per probe. Every block is `begin; do $probe$ ... $probe$; rollback;` and leaves nothing behind:
--   probe accounts, communities, rides, notifications and push-queue rows all roll back (pg_net requests
--   queued by webhooks are rows in the same transaction and are never sent).
--   A block that passes raises NOTICE 'PROBE <name> OK' and the statement after its rollback returns the
--   row 'PROBE <name> OK'. A block that fails raises EXCEPTION 'PROBE <name> FAILED: <check>'; the run stops
--   there (the SQL editor and the MCP stop at the first error, and the transaction is aborted, so nothing is
--   kept). A runner greps for 'PROBE .* OK' and 'PROBE .* FAILED'. The last row of a full run is
--   'PROBE ALL OK'.
--
-- WHEN TO RUN WHAT
--   * Block `short` runs after EVERY Phase 0 step and sub-step, from before step 1 to after step 6. It adapts:
--     community checks run only once the community tables / fill triggers / guard_last_owner exist.
--   * Every other block is the full matrix and needs steps 1-5 live (each checks and fails with "steps 1-5
--     are not all live" otherwise). Run them after step 5 and again after step 6.
--   * The Phase 3 blocks (community_moderation, admin_community_reports, community_stats, broadcast_cap) need
--     20261018_0001 and 20261018_0002 live and fail with "Phase 3 is not live" otherwise (admin_community_reports
--     also needs File A blocks 6-8). posts_delete_policy holds DELETE statements: SQL editor (owner) only; the MCP
--     declines it.
--   * The Phase 4 blocks: phase4_registry needs 20261019_0001; broadcast_push needs 20261019_0002 and
--     membership_update_producers needs 20261019_0003. Both of those files are GATED (decision A5 point 2): until
--     they are applied, run their blocks only inside the dry run that creates them (they fail with "Phase 4 part
--     <x> is not live" otherwise). None of the three holds a DELETE; all run through the MCP.
--   * Phase 5. geocoding_lookup needs 20261019_0050 (5a). The 5b blocks need their file live and fail with
--     "File <X> is not live" otherwise: legacy_retired (20261019_0060), invite_codes_dropped (0061),
--     geocoding_revoked (0062), storage_private (0063; it inserts rows into storage.objects inside its rolled-back
--     transaction, so SQL editor (owner) if the MCP declines it). After 0060, legacy_bridges prints
--     'PROBE legacy_bridges SKIPPED' and legacy_retired covers the same ground; short gives its two probe
--     accounts their default membership directly instead of through the retired approve bridge; broadcast_cap
--     expects 42501 from send_broadcast_notifications once 0060 block 7 has revoked it. A 5b dry run never pastes
--     this file: it runs the committed script in supabase/dryruns/ (no commit; probes as savepoints).
--   * Release 1 (community discovery and trust, 20261021_0001). community_preview and listed_profiles need it
--     and fail with "Release 1 is not live" otherwise (pg_temp.probe_require_release1: get_community_preview
--     exists). reputation adapts: once Release 1 is live, u5 (active in public C2) is readable by every signed-in
--     account, so its "shares no community" check reads u3 (C1 only, private) and a new check reads u5. Neither
--     new block holds a DELETE; both run through the MCP.
--   * Release 2. test_flag_visibility and example_guard need 20261021_0020; discovery_search and listing_rules need
--     0021; community_merge needs 0022 (broadcast_cap and broadcast_push are its regression probes); example_content
--     needs 0023. None holds a DELETE; all run through the MCP. listed_reviews (ruling R9, 0020 Block 11) also needs
--     0020. Each fails with "Release 2 part <x> is not live" otherwise (pg_temp.probe_require_release2: part a =
--     0020, b = 0021, c = 0022, d = 0023, cumulative). noop_default adapts: once communities.is_test exists, its
--     guest expectations leave out test communities, as the guest views and policies of 0020 do.
--   * SQL editor: run the whole file. MCP execute_sql: pass the PARAMETERS and HELPERS sections plus the
--     block(s) in ONE call (the helpers live in the session). The `commit;` after HELPERS is deliberate:
--     in a multi-statement run it keeps the helpers from being rolled back by the first block's rollback.
--   * Never run it while a migration call is half applied in the same session.
--
-- SUBJECTS (placeholders; set any of them in PARAMETERS, or leave '' for the default shown)
--   member          an existing active member of the default community (real account; default: the oldest
--                   approved, unbanned, non-admin profile). Used read-mostly; it posts one ride and one favor
--                   and writes one review in `short`, all rolled back.
--   platform_admin  a platform admin, profiles.is_admin (default: the oldest unbanned is_admin profile).
--   default_owner   the default community's owner (default: its active owner row; before step 1 the oldest
--                   is_admin profile, which is not known to be the owner's account: before step 1 set it to
--                   the owner-confirmed profile id written into 20261017_0001 [call] 1b.1, D1). `short`
--                   deletes this account inside the transaction, as the spec asks.
--   Created inside each transaction (throwaway ids 00000000-0000-4000-a000-0000000005NN, emails
--   probe5NN@example.invalid; communities ...-b000-...5NN; rides ...-c000-...5NN), by pg_temp.probe_world():
--     u(1)  unapproved account (profile only, never applied)
--     u(2)  banned account (active in the default community, then banned)
--     u(3)  probe-community-only member (active in C1 only)
--     u(4)  community admin: owner of C1, not a platform admin
--     u(5)  admin of C1
--     u(6)  applicant with no membership (redeems codes)
--     u(7)  second C1-only member
--     u(8)  default-community applicant (pending)         u(15) second default-community applicant
--     u(9)  C1-only applicant (pending in C1)
--     u(10) never-applied account                          u(13) second never-applied account
--     u(11) active in C1 with a pending default-community row
--     u(12) owner of C2 (public probe community)           u(14) owner of C3 (private, invite policy), alone
--     u(16) spare (limit-decline case)
--     C1 private 'approve' (owner u4, admin u5, members u3 u7 u11, pending u9); C2 public 'approve' (owner
--     u12); C3 private 'invite' (owner u14). All created 30 days ago so the daily creation limit is not hit.
--     r(1): u7's completed ride in C1, helped by u3, reviewed 5 stars by u7. r(2): u3's open ride in C1.
--   anon            the anon role with request.jwt.claims {"role":"anon"}.
--   Identity switch: pg_temp.probe_run sets request.jwt.claims (set_config(..., true), the plpgsql form of
--   `set local request.jwt.claims`) and `set local role authenticated` / `anon`, runs the statement, and
--   resets both; an error inside comes back as {"success":false,"raised":true,"sqlstate","error"} with the
--   role restored (the sub-transaction rollback undoes the SET LOCAL).
--
-- XP BASELINE (optional, for noop_default)
--   Immediately before applying step 1, capture the leaderboard and paste it into probe.xp_baseline:
--     select jsonb_object_agg(user_id, xp) from public.get_xp_leaderboard();
--   Without it, noop_default compares the legacy leaderboard with get_community_leaderboard(default) only.
--   A user with new XP activity between the capture and the run is a legitimate mismatch: re-capture.
--
-- WHAT IS NOT A FAILURE
--   noop_default prints 'PROBE noop_default WARN' (a notice, not a failure) when the rides SELECT plan of a
--   member of three communities shows no index scan even with enable_seqscan off; the InitPlan is checked
--   hard. On ~110 rows the planner's choice is not a correctness property; read the plan in the notice.
--
-- RPC names and argument orders are those of spec §3.5 and decision A1 (create_community(p_name,
-- p_description, p_join_policy), create_community_invite(p_community_id, p_max_uses, p_expires_at),
-- validate_community_invite(p_code), redeem_community_invite(p_code, p_heard_about, p_join_reason),
-- request_to_join_community(p_community_id, p_heard_about, p_join_reason), approve_community_member /
-- reject_community_member(p_community_id, p_user_id), remove_community_member(p_community_id, p_user_id,
-- p_reason), leave_community(p_community_id), archive_community / unarchive_community(p_community_id),
-- get_community_members(p_community_id, p_status, p_limit, p_offset), search_community_members(p_query,
-- p_community_id, p_limit), get_community_leaderboard / get_community_spotlights(p_community_id, start_date,
-- end_date), get_profile_stats(p_user_id), report_community(p_community_id, p_code, p_report_type,
-- p_description), request_owned_community_limit(p_requested, p_reason), decide_owned_community_limit(
-- p_request_id, p_approve)). A refusal is accepted in either form the spec allows: an exception, or a jsonb
-- with success = false / a non-empty error.
--   Phase 3 adds: get_community_reports(p_community_id, p_status), moderate_community_content(p_report_id, p_action, p_reason), get_community_stats(p_community_id) and get_community_stats_fulfilled / _savings(p_community_id, p_period, p_count), get_community_stats_active_requests(p_community_id), send_community_broadcast(p_community_id, p_title, p_body, p_pinned[, p_type]).
--   Phase 4: create_community(p_name, p_description, p_join_policy, p_timezone); the membership_update producers approve_community_member, readmit_community_member, transfer_community_ownership, set_member_role; send_community_broadcast's push.
--   Phase 5 adds: get_geocoding_multiplier(p_location_key), put_geocoding_multiplier(p_location_key, p_latitude, p_longitude, p_multiplier).
--   Release 1 adds: get_community_preview(p_community_id) (refusal code 'not_listed'), is_listed_request(p_ride_id, p_favor_id).
--   Release 2 adds: 0020 great_circle_miles(lat1, lng1, lat2, lng2) and can_discover_community(p_community_id) (internal), the trigger guard_example_content (42501 'example_flag_reserved' / 'example_request'); 0021 search_communities_by_name(p_query), find_communities_near(p_lat, p_lng), check_community_area(p_center_lat, p_center_lng, p_radius_miles[, p_community_id]), overlapping_listed_communities(p_center_lat, p_center_lng, p_radius_miles, p_exclude) (internal), create_community_with_area(p_name[, p_description, p_join_policy, p_timezone, p_listed, p_area_name, p_center_lat, p_center_lng, p_radius_miles, p_reason]), update_community_access(p_community_id, p_listed, p_join_policy[, p_area_name, p_center_lat, p_center_lng, p_radius_miles, p_reason]) (refusal codes not_owner, invalid, default_stays_listed, invalid_area, needs_area, reason_required), and get_community_preview's refusal code 'merged' (with merged_into_id, merged_into_name); 0022 post_community_announcement(p_community_id, p_author, p_title, p_body, p_pinned, p_type, p_system_event, p_push_data), merge_communities(p_proposal_id, p_actor), search_merge_targets(p_community_id, p_query), propose_community_merge(p_community_id, p_other_id, p_survivor_id[, p_note]), get_community_merge_proposal(p_community_id), respond_to_community_merge(p_proposal_id, p_accept), withdraw_community_merge(p_proposal_id); 0023 set_example_content(p_type, p_id, p_is_example), refresh_example_requests() (internal).


-- =============================================================================================================
-- PARAMETERS (session settings; '' = use the default described above)
-- =============================================================================================================
select set_config('probe.member',         '', false);
select set_config('probe.platform_admin', '', false);
select set_config('probe.default_owner',  '', false);
select set_config('probe.xp_baseline',    '', false);


-- =============================================================================================================
-- HELPERS (pg_temp: visible to this session only, dropped at disconnect; all plpgsql so nothing is resolved
-- before it runs, which lets `short` work before step 1)
-- =============================================================================================================

create or replace function pg_temp.u(n int) returns uuid language plpgsql immutable as $f$
begin return ('00000000-0000-4000-a000-' || lpad((500 + n)::text, 12, '0'))::uuid; end $f$;

create or replace function pg_temp.c(n int) returns uuid language plpgsql immutable as $f$
begin return ('00000000-0000-4000-b000-' || lpad((500 + n)::text, 12, '0'))::uuid; end $f$;

create or replace function pg_temp.r(n int) returns uuid language plpgsql immutable as $f$
begin return ('00000000-0000-4000-c000-' || lpad((500 + n)::text, 12, '0'))::uuid; end $f$;

create or replace function pg_temp.probe_subject(p_name text) returns uuid language plpgsql as $f$
declare
  v text := nullif(current_setting('probe.' || p_name, true), '');
begin
  if v is not null then
    return v::uuid;
  end if;
  if p_name = 'member' then
    return (select p.id from public.profiles p
             where p.approved and not coalesce(p.is_banned, false) and not coalesce(p.is_admin, false)
               and p.email not like 'probe%@example.invalid'
             order by p.created_at, p.id limit 1);
  elsif p_name = 'platform_admin' then
    return (select p.id from public.profiles p
             where p.is_admin and not coalesce(p.is_banned, false)
             order by p.created_at, p.id limit 1);
  elsif p_name = 'default_owner' then
    if to_regclass('public.communities') is not null then
      v := (select m.user_id::text
              from public.community_members m
              join public.communities c on c.id = m.community_id
             where c.is_default and m.role = 'owner' and m.status = 'active'
             order by m.activated_at nulls last, m.user_id limit 1);
    end if;
    return coalesce(v::uuid, pg_temp.probe_subject('platform_admin'));
  end if;
  raise exception 'unknown probe subject %', p_name;
end $f$;

-- Run p_sql (one row, one jsonb-convertible column) as a subject. p_mode: 'user' (authenticated, sub =
-- p_subject), 'anon', or 'owner' (the table owner with no JWT: bypasses RLS as a definer function does;
-- triggers still run). Errors come back as a jsonb object instead of propagating.
create or replace function pg_temp.probe_run(p_subject uuid, p_sql text, p_mode text default 'user')
returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  begin
    if p_mode = 'user' then
      perform set_config('request.jwt.claims', json_build_object('sub', p_subject, 'role', 'authenticated')::text, true);
      set local role authenticated;
    elsif p_mode = 'anon' then
      perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
      set local role anon;
    else
      perform set_config('request.jwt.claims', '', true);
    end if;
    execute p_sql into v;
    reset role;
    perform set_config('request.jwt.claims', '', true);
    return coalesce(v, 'null'::jsonb);
  exception when others then
    return jsonb_build_object('success', false, 'raised', true, 'sqlstate', sqlstate, 'error', sqlerrm);
  end;
end $f$;

-- Call one function expression (any return type, void included) as a subject; returns its value as jsonb
-- (the first row for a set-returning function), or the error object of probe_run.
create or replace function pg_temp.probe_call(p_subject uuid, p_call text, p_mode text default 'user')
returns jsonb language plpgsql as $f$
declare
  j jsonb;
begin
  j := pg_temp.probe_run(p_subject, 'select to_jsonb(s) from (select ' || p_call || ' as r) s', p_mode);
  if j ? 'raised' then
    return j;
  end if;
  return coalesce(j -> 'r', 'null'::jsonb);
end $f$;

create or replace function pg_temp.probe_refused(j jsonb) returns boolean language plpgsql immutable as $f$
begin
  return j is not null and jsonb_typeof(j) = 'object'
     and (coalesce(j ->> 'raised', '') = 'true'
          or coalesce(j ->> 'success', '') = 'false'
          or nullif(j ->> 'error', '') is not null);
end $f$;

-- "Empty" as the spec's gated reads answer: null, a refusal, [], {}, or values that are all null / 0 /
-- false / '' (an empty stats row).
create or replace function pg_temp.probe_empty(j jsonb) returns boolean language plpgsql immutable as $f$
begin
  if j is null or j = 'null'::jsonb or pg_temp.probe_refused(j) then
    return true;
  end if;
  case jsonb_typeof(j)
    when 'array'   then return not exists (select 1 from jsonb_array_elements(j) e where not pg_temp.probe_empty(e));
    when 'object'  then return not exists (select 1 from jsonb_each(j) kv where not pg_temp.probe_empty(kv.value));
    when 'number'  then return j = '0'::jsonb;
    when 'boolean' then return j = 'false'::jsonb;
    when 'string'  then return (j #>> '{}') = '';
    else return false;
  end case;
end $f$;

create or replace function pg_temp.probe_count(p_subject uuid, p_sql text, p_mode text default 'user')
returns bigint language plpgsql as $f$
declare
  j jsonb;
begin
  j := pg_temp.probe_run(p_subject, 'select to_jsonb(count(*)) from (' || p_sql || ') s', p_mode);
  if pg_temp.probe_refused(j) then
    raise exception 'PROBE count query failed (%): %', p_sql, j ->> 'error';
  end if;
  return (j #>> '{}')::bigint;
end $f$;

create or replace function pg_temp.probe_ok(p_probe text, p_check text, p_cond boolean) returns void
language plpgsql as $f$
begin
  if p_cond is not true then
    raise exception 'PROBE % FAILED: %', p_probe, p_check;
  end if;
end $f$;

create or replace function pg_temp.probe_require(p_probe text) returns void language plpgsql as $f$
declare
  v_missing text[];
begin
  if to_regclass('public.communities') is null then
    raise exception 'PROBE % FAILED: steps 1-5 are not all live (no public.communities)', p_probe;
  end if;
  select array_agg(f) into v_missing
    from unnest(array['default_community_id', 'my_community_ids', 'recompute_profile_membership_flags',
                      'guard_request_claim_membership', 'get_community_leaderboard', 'get_community_spotlights',
                      'get_profile_stats', 'unwind_member_requests', 'guard_last_owner', 'create_community',
                      'create_community_invite', 'validate_community_invite', 'redeem_community_invite',
                      'request_to_join_community', 'approve_community_member', 'remove_community_member',
                      'leave_community', 'archive_community', 'unarchive_community', 'get_community_members',
                      'search_community_members', 'report_community', 'request_owned_community_limit',
                      'decide_owned_community_limit']) f
   where not exists (select 1 from pg_catalog.pg_proc p
                      where p.pronamespace = 'public'::regnamespace and p.proname = f);
  if v_missing is not null then
    raise exception 'PROBE % FAILED: steps 1-5 are not all live; missing %', p_probe, v_missing;
  end if;
end $f$;

-- the live communities in which a user is an active member (what my_community_ids() answers for them)
create or replace function pg_temp.probe_live_communities(p_user uuid) returns uuid[] language plpgsql as $f$
begin
  return coalesce((select array_agg(m.community_id)
                     from public.community_members m
                     join public.profiles p    on p.id = m.user_id and not p.is_banned
                     join public.communities c on c.id = m.community_id and c.archived_at is null
                    where m.user_id = p_user and m.status = 'active'), '{}'::uuid[]);
end $f$;

create or replace function pg_temp.probe_account(n int) returns uuid language plpgsql as $f$
declare
  v uuid := pg_temp.u(n);
  v_email text := 'probe' || (500 + n) || '@example.invalid';
begin
  insert into auth.users (id, email) values (v, v_email);
  insert into public.profiles (id, name, email) values (v, 'Probe ' || (500 + n), v_email);
  return v;
end $f$;

create or replace function pg_temp.probe_member(p_community uuid, p_user uuid, p_role text, p_status text, p_days int)
returns void language plpgsql as $f$
begin
  insert into public.community_members (community_id, user_id, role, status, joined_at, activated_at)
  values (p_community, p_user, p_role, p_status, now() - make_interval(days => p_days),
          case when p_status = 'active' then now() - make_interval(days => p_days) end);
end $f$;

create or replace function pg_temp.probe_community(n int, p_name text, p_owner uuid, p_public boolean, p_policy text)
returns uuid language plpgsql as $f$
begin
  insert into public.communities (id, name, description, created_by, is_public, join_policy, created_at)
  values (pg_temp.c(n), p_name, 'communities probe', p_owner, p_public, p_policy, now() - interval '30 days');
  perform pg_temp.probe_member(pg_temp.c(n), p_owner, 'owner', 'active', 30);
  return pg_temp.c(n);
end $f$;

-- the standard world (see SUBJECTS); run as the table owner with no JWT
create or replace function pg_temp.probe_world() returns void language plpgsql as $f$
declare
  d uuid := public.default_community_id();
  n int;
begin
  perform set_config('request.jwt.claims', '', true);
  if d is null then
    raise exception 'PROBE world FAILED: no default community';
  end if;
  for n in 1..16 loop
    perform pg_temp.probe_account(n);
  end loop;

  perform pg_temp.probe_community(1, 'Probe Community One',   pg_temp.u(4),  false, 'approve');
  perform pg_temp.probe_community(2, 'Probe Public Two',      pg_temp.u(12), true,  'approve');
  perform pg_temp.probe_community(3, 'Probe Community Three', pg_temp.u(14), false, 'invite');

  perform pg_temp.probe_member(pg_temp.c(1), pg_temp.u(5),  'admin',  'active', 20);
  perform pg_temp.probe_member(pg_temp.c(1), pg_temp.u(3),  'member', 'active', 10);
  perform pg_temp.probe_member(pg_temp.c(1), pg_temp.u(7),  'member', 'active', 9);
  perform pg_temp.probe_member(pg_temp.c(1), pg_temp.u(11), 'member', 'active', 8);
  perform pg_temp.probe_member(pg_temp.c(1), pg_temp.u(9),  'member', 'pending', 1);
  perform pg_temp.probe_member(d, pg_temp.u(2),  'member', 'active', 5);
  perform pg_temp.probe_member(d, pg_temp.u(8),  'member', 'pending', 1);
  perform pg_temp.probe_member(d, pg_temp.u(15), 'member', 'pending', 1);
  perform pg_temp.probe_member(d, pg_temp.u(11), 'member', 'pending', 1);

  update public.profiles set is_banned = true, banned_at = now(), ban_reason = 'communities probe'
   where id = pg_temp.u(2);
  update public.community_members set heard_about = 'Probe heard', join_reason = 'Probe reason'
   where community_id = pg_temp.c(1) and user_id = pg_temp.u(7);

  insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id)
  values (pg_temp.r(1), pg_temp.u(7), current_date - 2, '10:00', 'Probe pickup', 'Probe destination',
          'completed', pg_temp.u(3), pg_temp.c(1));
  insert into public.reviews (reviewer_id, fulfiller_id, ride_id, rating, comment)
  values (pg_temp.u(7), pg_temp.u(3), pg_temp.r(1), 5, 'Probe review');
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id)
  values (pg_temp.r(2), pg_temp.u(3), current_date + 3, '09:00', 'Probe pickup', 'Probe destination',
          'open', pg_temp.c(1));
end $f$;

-- Phase 3: fails unless steps 1-5 and both Phase 3 files (20261018_0001 / 0002) are live
create or replace function pg_temp.probe_require_phase3(p_probe text) returns void language plpgsql as $f$
declare
  v_missing text[];
begin
  perform pg_temp.probe_require(p_probe);
  select array_agg(f) into v_missing
    from unnest(array['is_community_staff', 'get_community_reports', 'moderate_community_content',
                      'can_read_community_stats', 'get_community_stats', 'get_community_stats_fulfilled',
                      'get_community_stats_savings', 'get_community_stats_active_requests']) f
   where not exists (select 1 from pg_catalog.pg_proc p
                      where p.pronamespace = 'public'::regnamespace and p.proname = f);
  if v_missing is not null then
    raise exception 'PROBE % FAILED: Phase 3 is not live; missing %', p_probe, v_missing;
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'reports' and column_name = 'community_status') then
    raise exception 'PROBE % FAILED: Phase 3 is not live; missing reports.community_status', p_probe;
  end if;
end $f$;

-- a Town Hall post written as the table owner (no JWT); ids 00000000-0000-4000-d000-0000000005NN
create or replace function pg_temp.probe_post(n int, p_author uuid, p_community uuid) returns uuid language plpgsql as $f$
declare
  v uuid := ('00000000-0000-4000-d000-' || lpad((500 + n)::text, 12, '0'))::uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into public.town_hall_posts (id, user_id, title, content, community_id)
  values (v, p_author, 'Probe post ' || n, 'communities probe post ' || n, p_community);
  return v;
end $f$;

-- Phase 4: fails unless Phase 3 and the named Phase 4 part are live (in the dry run: created earlier in the same
-- transaction). p_part: 'registry' (20261019_0001), 'broadcast' (20261019_0002), 'membership' (20261019_0003).
create or replace function pg_temp.probe_require_phase4(p_probe text, p_part text) returns void language plpgsql as $f$
declare
  v_ok boolean;
begin
  perform pg_temp.probe_require_phase3(p_probe);
  v_ok := case p_part
    when 'registry' then
          exists (select 1 from pg_catalog.pg_constraint
                   where conname = 'valid_notification_type'
                     and pg_catalog.pg_get_constraintdef(oid) like '%membership_update%')
      and exists (select 1 from pg_catalog.pg_proc
                   where pronamespace = 'public'::regnamespace and proname = 'should_notify_user'
                     and prosrc like '%membership_update%')
      and exists (select 1 from pg_catalog.pg_proc
                   where pronamespace = 'public'::regnamespace and proname = 'create_community'
                     and pg_catalog.pg_get_function_identity_arguments(oid) like '%p_timezone%')
    when 'broadcast' then
          exists (select 1 from pg_catalog.pg_proc
                   where pronamespace = 'public'::regnamespace and proname = 'send_community_broadcast'
                     and prosrc like '%queue_push_notification%')
      and exists (select 1 from pg_catalog.pg_proc
                   where pronamespace = 'public'::regnamespace and proname = 'notify_town_hall_post'
                     and prosrc like '%naars.broadcast_post%')
    when 'membership' then
          (select count(*) from pg_catalog.pg_proc
            where pronamespace = 'public'::regnamespace
              and proname in ('approve_community_member', 'readmit_community_member',
                              'transfer_community_ownership', 'set_member_role')
              and prosrc like '%membership_update%') = 4
    else false
  end;
  if not v_ok then
    raise exception 'PROBE % FAILED: Phase 4 part % is not live', p_probe, p_part;
  end if;
end $f$;

-- Phase 5: p_part 'a' = 20261019_0050 live; 'bridges' = 0060; 'invite_codes' = 0061; 'geocoding' = 0062;
-- 'storage' = 0063. Every part also needs steps 1-5 and 5a.
create or replace function pg_temp.probe_require_phase5(p_probe text, p_part text) returns void language plpgsql as $f$
begin
  perform pg_temp.probe_require(p_probe);
  if p_part not in ('a', 'bridges', 'invite_codes', 'geocoding', 'storage') then
    raise exception 'PROBE % FAILED: unknown Phase 5 part %', p_probe, p_part;
  end if;
  if not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'get_geocoding_multiplier')
     or not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'put_geocoding_multiplier') then
    raise exception 'PROBE % FAILED: Phase 5a is not live (no geocoding lookup functions)', p_probe;
  end if;
  if p_part = 'bridges' and exists (select 1 from pg_catalog.pg_trigger where not tgisinternal
                                     and tgname in ('legacy_application_to_membership', 'a_sync_legacy_approval_to_membership')) then
    raise exception 'PROBE % FAILED: File B (20261019_0060) is not live; the legacy bridges still exist', p_probe;
  elsif p_part = 'invite_codes' and to_regclass('public.invite_codes') is not null then
    raise exception 'PROBE % FAILED: File C (20261019_0061) is not live; public.invite_codes exists', p_probe;
  elsif p_part = 'geocoding' and (has_table_privilege('authenticated', 'public.geocoding_cache', 'select')
                                  or has_table_privilege('anon', 'public.geocoding_cache', 'select')) then
    raise exception 'PROBE % FAILED: File D (20261019_0062) is not live; geocoding_cache is still readable', p_probe;
  elsif p_part = 'storage' and exists (select 1 from storage.buckets
                                        where id in ('message-images', 'group-images', 'town-hall-images', 'review-images') and public) then
    raise exception 'PROBE % FAILED: File E (20261019_0063) is not live; a bucket is still public', p_probe;
  end if;
end $f$;

-- a storage object row written as the table owner (no JWT; no file is uploaded, the row is rolled back)
create or replace function pg_temp.probe_storage_object(p_bucket text, p_name text, p_owner uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', '', true);
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values (p_bucket, p_name, p_owner, p_owner::text, '{"mimetype": "image/jpeg", "size": 1}'::jsonb);
end $f$;

-- Release 1 (20261021_0001): fails unless steps 1-5 are live and get_community_preview exists (in the dry run:
-- created earlier in the same transaction)
create or replace function pg_temp.probe_require_release1(p_probe text) returns void language plpgsql as $f$
begin
  perform pg_temp.probe_require(p_probe);
  if to_regprocedure('public.get_community_preview(uuid)') is null then
    raise exception 'PROBE % FAILED: Release 1 is not live', p_probe;
  end if;
end $f$;

-- Release 2 (20261021_0020-0023): fails unless steps 1-5 and Release 1 are live and, cumulatively, every part up to
-- p_part: 'a' 0020 (communities.is_test and guard_example_content), 'b' 0021 (search_communities_by_name), 'c' 0022
-- (merge_communities), 'd' 0023 (refresh_example_requests). In a dry run: created earlier in the same transaction.
create or replace function pg_temp.probe_require_release2(p_probe text, p_part text) returns void language plpgsql as $f$
declare
  v_part text;
  v_fn text;
begin
  perform pg_temp.probe_require(p_probe);
  if p_part is null or p_part not in ('a', 'b', 'c', 'd') then
    raise exception 'PROBE % FAILED: unknown Release 2 part %', p_probe, p_part;
  end if;
  if to_regprocedure('public.get_community_preview(uuid)') is null then
    raise exception 'PROBE % FAILED: Release 2 part % is not live (Release 1 is not live)', p_probe, p_part;
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'communities' and column_name = 'is_test')
     or not exists (select 1 from pg_catalog.pg_proc
                     where pronamespace = 'public'::regnamespace and proname = 'guard_example_content') then
    raise exception 'PROBE % FAILED: Release 2 part a is not live', p_probe;
  end if;
  foreach v_part in array array['b', 'c', 'd'] loop
    exit when v_part > p_part;
    v_fn := case v_part when 'b' then 'search_communities_by_name'
                        when 'c' then 'merge_communities'
                        else 'refresh_example_requests' end;
    if not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = v_fn) then
      raise exception 'PROBE % FAILED: Release 2 part % is not live', p_probe, v_part;
    end if;
  end loop;
end $f$;

-- a community's service area (20261021_0020 Block 1), written as the table owner (no JWT); the CHECKs apply
create or replace function pg_temp.probe_area(p_community uuid, p_name text, p_lat double precision,
                                              p_lng double precision, p_radius int)
returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', '', true);
  update public.communities
     set area_name = p_name, area_center_lat = p_lat, area_center_lng = p_lng, area_radius_miles = p_radius
   where id = p_community;
end $f$;

-- a listed 'approve' probe community pg_temp.c(n) flagged is_test (20261021_0020), owner p_owner, as the table owner
create or replace function pg_temp.probe_test_community(n int, p_owner uuid) returns uuid language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.probe_community(n, 'Probe Test ' || n, p_owner, true, 'approve');
  update public.communities set is_test = true where id = pg_temp.c(n);
  return pg_temp.c(n);
end $f$;
commit;


-- =============================================================================================================
-- short: the short probe (§4), after EVERY step. As an existing member: insert a ride and a favor without
-- community_id; a second member claims and completes the ride; the poster writes a 5-star review; the ride's
-- community and three xp_events rows with a community are read back; then the accounts of a probe member, a
-- probe admin and the default community's owner are deleted, each by itself.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'short';
  v_has_comm  boolean := to_regclass('public.communities') is not null;
  v_has_fill  boolean := exists (select 1 from pg_catalog.pg_trigger where tgname = 'fill_community_rides' and not tgisinternal);
  v_has_guard boolean := exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'guard_last_owner');
  v_member uuid := pg_temp.probe_subject('member');
  v_owner  uuid := pg_temp.probe_subject('default_owner');
  d uuid;
  v_claimer uuid;
  v_padmin uuid;
  v_ride uuid;
  v_favor uuid;
  v_review uuid;
  v_x uuid;
  j jsonb;
begin
  perform pg_temp.probe_ok(v_probe, 'an existing member subject resolves', v_member is not null);
  perform pg_temp.probe_ok(v_probe, 'the default owner subject resolves', v_owner is not null);
  if v_has_comm then
    d := public.default_community_id();
  end if;

  -- a second member (the claimer) and a probe admin, made the way the installed admin build approves
  v_claimer := pg_temp.probe_account(901);
  v_padmin  := pg_temp.probe_account(902);
  update public.profiles set approved = true where id in (v_claimer, v_padmin);
  -- Phase 5b retires the approve bridge that turned this UPDATE into a default membership; give both accounts
  -- the membership directly when the bridge did not (a no-op before 20261019_0060)
  if v_has_comm then
    if not exists (select 1 from public.community_members where community_id = d and user_id = v_claimer) then
      perform pg_temp.probe_member(d, v_claimer, 'member', 'active', 1);
    end if;
    if not exists (select 1 from public.community_members where community_id = d and user_id = v_padmin) then
      perform pg_temp.probe_member(d, v_padmin, 'member', 'active', 1);
    end if;
  end if;
  update public.profiles set is_admin = true where id = v_padmin;
  if v_has_comm then
    update public.community_members set role = 'admin'
     where community_id = d and user_id = v_padmin and status = 'active';
  end if;

  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination, notes)
       values (%L, current_date + 1, '10:00', 'Probe pickup', 'Probe destination', 'communities probe')
       returning to_jsonb(id)$q$, v_member));
  perform pg_temp.probe_ok(v_probe, 'member inserts a ride without community_id: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  v_ride := (j #>> '{}')::uuid;

  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.favors (user_id, title, location, date)
       values (%L, 'Probe favor', 'Probe location', current_date + 1)
       returning to_jsonb(id)$q$, v_member));
  perform pg_temp.probe_ok(v_probe, 'member inserts a favor without community_id: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  v_favor := (j #>> '{}')::uuid;

  j := pg_temp.probe_run(v_claimer, format(
    $q$with x as (update public.rides set status = 'confirmed', claimed_by = %L where id = %L returning 1)
       select to_jsonb(count(*)) from x$q$, v_claimer, v_ride));
  perform pg_temp.probe_ok(v_probe, 'second member claims the ride: ' || j::text, j = '1'::jsonb);

  j := pg_temp.probe_call(v_claimer, format('public.complete_request(%L, %L::uuid)', 'ride', v_ride));
  perform pg_temp.probe_ok(v_probe, 'helper completes the ride: ' || j::text, coalesce(j ->> 'success', '') = 'true');

  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.reviews (reviewer_id, fulfiller_id, ride_id, rating, comment)
       values (%L, %L, %L, 5, 'Probe review') returning to_jsonb(id)$q$, v_member, v_claimer, v_ride));
  perform pg_temp.probe_ok(v_probe, 'poster inserts a 5-star review: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  v_review := (j #>> '{}')::uuid;

  perform pg_temp.probe_ok(v_probe, 'three xp_events rows for the ride and the review',
    (select count(*) from public.xp_events where source_id in (v_ride, v_review)) >= 3);
  if v_has_fill then
    perform pg_temp.probe_ok(v_probe, 'the ride belongs to the default community',
      (select community_id from public.rides where id = v_ride) = d);
    perform pg_temp.probe_ok(v_probe, 'the favor belongs to the default community',
      (select community_id from public.favors where id = v_favor) = d);
    perform pg_temp.probe_ok(v_probe, 'the xp_events rows carry the default community',
      not exists (select 1 from public.xp_events where source_id in (v_ride, v_review) and community_id is distinct from d));
  end if;

  -- deletions, each account by itself; the default owner last
  foreach v_x in array array[v_claimer, v_padmin, v_owner] loop
    j := pg_temp.probe_call(v_x, format('public.delete_user_account(%L::uuid)', v_x));
    perform pg_temp.probe_ok(v_probe, format('account %s deletes itself: %s', v_x, coalesce(j ->> 'error', '')), not pg_temp.probe_refused(j));
    perform pg_temp.probe_ok(v_probe, format('account %s is gone from profiles and auth.users', v_x),
      not exists (select 1 from public.profiles where id = v_x) and not exists (select 1 from auth.users where id = v_x));
  end loop;
  if v_has_guard then
    perform pg_temp.probe_ok(v_probe, 'the default community still has an active owner',
      exists (select 1 from public.community_members where community_id = d and role = 'owner' and status = 'active'));
  end if;

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE short OK' as probe;


-- =============================================================================================================
-- noop_default: no change for the default community. Each active member reads exactly the rides, favors and
-- posts they read before (visible rows of their live communities plus their own); an unapproved account
-- reads no foreign rows; anon reads the guest views and the posts of public communities; public_profiles
-- shows a member every co-member and anon every active member of a public community (once 20261021_0020 is live,
-- public and not a test community); XP unchanged; the rides
-- SELECT of a member of three communities shows the InitPlan (index scan reported).
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'noop_default';
  d uuid;
  v_member uuid := pg_temp.probe_subject('member');
  v_m uuid;
  v_un uuid;
  v_exp bigint;
  v_got bigint;
  v_ids uuid[];
  v_base jsonb := nullif(current_setting('probe.xp_baseline', true), '')::jsonb;
  j jsonb;
  k jsonb;
  kv record;
  v_plan text;
begin
  perform pg_temp.probe_require(v_probe);
  d := public.default_community_id();
  perform pg_temp.probe_ok(v_probe, 'the default community exists, is public and live',
    exists (select 1 from public.communities where id = d and is_public and archived_at is null));

  for v_m in
    select m.user_id from public.community_members m join public.profiles p on p.id = m.user_id
     where m.community_id = d and m.status = 'active' and not p.is_banned
  loop
    v_exp := (select count(*) from public.rides r
               where r.user_id = v_m or (r.hidden_at is null and r.community_id = any (pg_temp.probe_live_communities(v_m))));
    v_got := pg_temp.probe_count(v_m, 'select 1 from public.rides');
    perform pg_temp.probe_ok(v_probe, format('member %s reads %s rides, expected %s', v_m, v_got, v_exp), v_got = v_exp);
    v_exp := (select count(*) from public.favors f
               where f.user_id = v_m or (f.hidden_at is null and f.community_id = any (pg_temp.probe_live_communities(v_m))));
    v_got := pg_temp.probe_count(v_m, 'select 1 from public.favors');
    perform pg_temp.probe_ok(v_probe, format('member %s reads %s favors, expected %s', v_m, v_got, v_exp), v_got = v_exp);
    v_exp := (select count(*) from public.town_hall_posts t
               where t.user_id = v_m or (t.hidden_at is null and t.community_id = any (pg_temp.probe_live_communities(v_m))));
    v_got := pg_temp.probe_count(v_m, 'select 1 from public.town_hall_posts');
    perform pg_temp.probe_ok(v_probe, format('member %s reads %s posts, expected %s', v_m, v_got, v_exp), v_got = v_exp);
  end loop;

  v_un := pg_temp.probe_account(1);
  perform pg_temp.probe_ok(v_probe, 'an unapproved account reads 0 foreign rides',
    pg_temp.probe_count(v_un, format('select 1 from public.rides where user_id <> %L', v_un)) = 0);
  perform pg_temp.probe_ok(v_probe, 'an unapproved account reads 0 foreign favors',
    pg_temp.probe_count(v_un, format('select 1 from public.favors where user_id <> %L', v_un)) = 0);
  perform pg_temp.probe_ok(v_probe, 'an unapproved account reads 0 foreign posts',
    pg_temp.probe_count(v_un, format('select 1 from public.town_hall_posts where user_id <> %L', v_un)) = 0);

  v_exp := (select count(*) from public.rides r join public.communities c on c.id = r.community_id
             where r.hidden_at is null and c.is_public and c.archived_at is null
               and not coalesce((to_jsonb(c) ->> 'is_test')::boolean, false));
  v_got := pg_temp.probe_count(null, 'select 1 from public.guest_rides', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon reads %s guest rides, expected %s', v_got, v_exp), v_got = v_exp);
  v_exp := (select count(*) from public.favors f join public.communities c on c.id = f.community_id
             where f.hidden_at is null and c.is_public and c.archived_at is null
               and not coalesce((to_jsonb(c) ->> 'is_test')::boolean, false));
  v_got := pg_temp.probe_count(null, 'select 1 from public.guest_favors', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon reads %s guest favors, expected %s', v_got, v_exp), v_got = v_exp);
  perform pg_temp.probe_ok(v_probe, 'anon reads 0 rides and 0 favors from the tables',
    pg_temp.probe_count(null, 'select 1 from public.rides', 'anon') = 0
    and pg_temp.probe_count(null, 'select 1 from public.favors', 'anon') = 0);
  perform pg_temp.probe_ok(v_probe, 'anon reads no address text from the guest views',
    pg_temp.probe_count(null, $q$select 1 from public.guest_rides where pickup <> '' or destination <> ''$q$, 'anon') = 0
    and pg_temp.probe_count(null, $q$select 1 from public.guest_favors where location <> ''$q$, 'anon') = 0);
  v_exp := (select count(*) from public.town_hall_posts t join public.communities c on c.id = t.community_id
             where t.hidden_at is null and c.is_public and c.archived_at is null
               and not coalesce((to_jsonb(c) ->> 'is_test')::boolean, false));
  v_got := pg_temp.probe_count(null, 'select 1 from public.town_hall_posts', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon reads %s posts, expected %s', v_got, v_exp), v_got = v_exp);

  v_ids := array(select m.user_id from public.community_members m join public.profiles p on p.id = m.user_id
                  where m.community_id = d and m.status = 'active' and not p.is_banned);
  v_got := pg_temp.probe_count(v_member, format('select 1 from public.public_profiles where id = any (%L::uuid[])', v_ids));
  perform pg_temp.probe_ok(v_probe, format('member reads %s of %s co-members in public_profiles', v_got, cardinality(v_ids)),
    v_got = cardinality(v_ids));
  v_exp := (select count(distinct m.user_id) from public.community_members m
              join public.communities c on c.id = m.community_id
             where m.status = 'active' and c.is_public and c.archived_at is null
               and not coalesce((to_jsonb(c) ->> 'is_test')::boolean, false));
  v_got := pg_temp.probe_count(null, 'select 1 from public.public_profiles', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon reads %s public_profiles rows, expected %s', v_got, v_exp), v_got = v_exp);

  j := pg_temp.probe_run(v_member, $q$select coalesce(jsonb_object_agg(user_id, xp), '{}'::jsonb) from public.get_xp_leaderboard()$q$);
  k := pg_temp.probe_run(v_member, format(
    $q$select coalesce(jsonb_object_agg(user_id, xp), '{}'::jsonb)
         from public.get_community_leaderboard(%L::uuid, '1970-01-01'::date, current_date)$q$, d));
  perform pg_temp.probe_ok(v_probe, 'both leaderboards answer: ' || coalesce(j ->> 'error', '') || coalesce(k ->> 'error', ''),
    not pg_temp.probe_refused(j) and not pg_temp.probe_refused(k));
  perform pg_temp.probe_ok(v_probe, 'the legacy leaderboard equals the default community''s', j = k);
  if v_base is not null then
    for kv in select key, value from jsonb_each(v_base) loop
      perform pg_temp.probe_ok(v_probe, format('XP of %s is unchanged (%s before, %s now)', kv.key, kv.value, j -> kv.key),
        (j -> kv.key) = kv.value);
    end loop;
  else
    raise notice 'PROBE noop_default NOTE: probe.xp_baseline not set; XP compared between the legacy and community leaderboards only';
  end if;

  -- the member joins two more (probe) communities, then the rides SELECT plan
  perform pg_temp.probe_community(1, 'Probe Explain One', v_member, false, 'approve');
  perform pg_temp.probe_community(2, 'Probe Explain Two', v_member, false, 'approve');
  perform pg_temp.probe_ok(v_probe, 'the member is active in three communities', cardinality(pg_temp.probe_live_communities(v_member)) >= 3);
  perform set_config('enable_seqscan', 'off', true);
  j := pg_temp.probe_run(v_member, 'explain (analyze, format json) select id from public.rides');
  perform set_config('enable_seqscan', 'on', true);
  perform pg_temp.probe_ok(v_probe, 'explain ran: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  v_plan := j::text;
  perform pg_temp.probe_ok(v_probe, 'the rides SELECT evaluates the membership helper once (InitPlan)', v_plan ilike '%InitPlan%');
  if v_plan not ilike '%Index%' then
    raise notice 'PROBE noop_default WARN: rides SELECT plan shows no index scan: %', left(v_plan, 3000);
  end if;

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE noop_default OK' as probe;


-- =============================================================================================================
-- isolation: a probe community's ride and member are invisible to a default-community member (rides,
-- public_profiles, search_community_members, get_user_badges, get_user_stats, get_profile_stats); the probe
-- member cannot add a default member to a thread; notify_new_ride queues one push per probe-community member;
-- a claim across the boundary raises 42501 from the trigger even as the table owner; leaderboard and
-- spotlights of the probe community show only its people; a probe member reads only their own
-- community_members row and get_community_members gives them null answers and its admin the answers.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'isolation';
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u7 uuid := pg_temp.u(7);
  c1 uuid := pg_temp.c(1);
  v_conv uuid;
  v_ride uuid;
  v_ids uuid[];
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  perform pg_temp.probe_ok(v_probe, 'a C1 member sees the C1 ride (control)',
    pg_temp.probe_count(u7, format('select 1 from public.rides where id = %L', pg_temp.r(2))) = 1);
  perform pg_temp.probe_ok(v_probe, 'a default member does not see the C1 ride',
    pg_temp.probe_count(v_member, format('select 1 from public.rides where id = %L', pg_temp.r(2))) = 0);

  perform pg_temp.probe_ok(v_probe, 'a C1 admin sees the probe member in public_profiles (control)',
    pg_temp.probe_count(u4, format('select 1 from public.public_profiles where id = %L', u3)) = 1);
  perform pg_temp.probe_ok(v_probe, 'the probe member is absent from a default member''s public_profiles',
    pg_temp.probe_count(v_member, format('select 1 from public.public_profiles where id = %L', u3)) = 0);

  j := pg_temp.probe_run(u4, format($q$select coalesce(jsonb_agg(x.id), '[]'::jsonb) from public.search_community_members('Probe', %L::uuid, 50) x$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'a C1 admin finds the probe member in search (control): ' || j::text, j ? u3::text);
  j := pg_temp.probe_run(v_member, $q$select coalesce(jsonb_agg(x.id), '[]'::jsonb) from public.search_community_members('Probe', null, 50) x$q$);
  perform pg_temp.probe_ok(v_probe, 'search_community_members answers a default member: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the probe member is absent from a default member''s search', not (j ? u3::text));

  j := pg_temp.probe_call(v_member, format('public.get_user_badges(%L::uuid)', u3));
  perform pg_temp.probe_ok(v_probe, 'get_user_badges is empty for a default member: ' || j::text, pg_temp.probe_empty(j));
  j := pg_temp.probe_call(u4, format('public.get_user_stats(%L::uuid)', u3));
  perform pg_temp.probe_ok(v_probe, 'get_user_stats answers a C1 admin (control): ' || j::text, (j ->> 'review_count')::int = 1);
  j := pg_temp.probe_call(v_member, format('public.get_user_stats(%L::uuid)', u3));
  perform pg_temp.probe_ok(v_probe, 'get_user_stats is empty for a default member: ' || j::text, pg_temp.probe_empty(j));
  j := pg_temp.probe_call(v_member, format('public.get_profile_stats(%L::uuid)', u3));
  perform pg_temp.probe_ok(v_probe, 'get_profile_stats is empty for a default member: ' || j::text, pg_temp.probe_empty(j));

  j := pg_temp.probe_run(u3, format('insert into public.conversations (created_by) values (%L) returning to_jsonb(id)', u3));
  perform pg_temp.probe_ok(v_probe, 'the probe member creates a conversation: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  v_conv := (j #>> '{}')::uuid;
  j := pg_temp.probe_run(u3, format($q$with x as (insert into public.conversation_participants (conversation_id, user_id, added_by)
                                     values (%L, %L, %L) returning 1) select to_jsonb(count(*)) from x$q$, v_conv, u3, u3));
  perform pg_temp.probe_ok(v_probe, 'the creator adds themselves: ' || j::text, j = '1'::jsonb);
  j := pg_temp.probe_run(u3, format($q$with x as (insert into public.conversation_participants (conversation_id, user_id, added_by)
                                     values (%L, %L, %L) returning 1) select to_jsonb(count(*)) from x$q$, v_conv, u7, u3));
  perform pg_temp.probe_ok(v_probe, 'the creator adds a C1 co-member (control): ' || j::text, j = '1'::jsonb);
  j := pg_temp.probe_run(u3, format($q$with x as (insert into public.conversation_participants (conversation_id, user_id, added_by)
                                     values (%L, %L, %L) returning 1) select to_jsonb(count(*)) from x$q$, v_conv, v_member, u3));
  perform pg_temp.probe_ok(v_probe, 'the probe member cannot add a default member to a thread: ' || j::text,
    pg_temp.probe_refused(j) or j = '0'::jsonb);

  j := pg_temp.probe_run(u4, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination, community_id)
       values (%L, current_date + 2, '11:00', 'Probe pickup', 'Probe destination', %L) returning to_jsonb(id)$q$, u4, c1));
  perform pg_temp.probe_ok(v_probe, 'the C1 owner posts a C1 ride: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  v_ride := (j #>> '{}')::uuid;
  v_ids := array(select m.user_id from public.community_members m join public.profiles p on p.id = m.user_id
                  where m.community_id = c1 and m.status = 'active' and not p.is_banned and m.user_id <> u4
                    and not m.notifications_muted and (m.muted_until is null or m.muted_until < now()));
  perform pg_temp.probe_ok(v_probe, format('notify_new_ride queues %s pushes for %s C1 members',
      (select count(*) from public.notification_queue q where q.notification_type = 'new_ride' and q.payload -> 'data' ->> 'ride_id' = v_ride::text),
      cardinality(v_ids)),
    (select count(*) from public.notification_queue q
      where q.notification_type = 'new_ride' and q.payload -> 'data' ->> 'ride_id' = v_ride::text) = cardinality(v_ids)
    and (select count(distinct q.recipient_user_id) from public.notification_queue q
          where q.notification_type = 'new_ride' and q.payload -> 'data' ->> 'ride_id' = v_ride::text) = cardinality(v_ids));
  perform pg_temp.probe_ok(v_probe, 'no new_ride push leaves C1',
    not exists (select 1 from public.notification_queue q
                 where q.notification_type = 'new_ride' and q.payload -> 'data' ->> 'ride_id' = v_ride::text
                   and q.recipient_user_id <> all (v_ids)));
  perform pg_temp.probe_ok(v_probe, 'no new_ride bell row leaves C1',
    not exists (select 1 from public.notifications n where n.ride_id = v_ride and n.type = 'new_ride' and n.user_id <> all (v_ids)));

  j := pg_temp.probe_run(null, format($q$with x as (update public.rides set status = 'confirmed', claimed_by = %L where id = %L returning 1)
                                       select to_jsonb(count(*)) from x$q$, v_member, pg_temp.r(2)), 'owner');
  perform pg_temp.probe_ok(v_probe, 'a cross-community claim by the table owner raises 42501 from the trigger: ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_run(v_member, format($q$with x as (update public.rides set status = 'confirmed', claimed_by = %L where id = %L returning 1)
                                           select to_jsonb(count(*)) from x$q$, v_member, pg_temp.r(2)));
  perform pg_temp.probe_ok(v_probe, 'a cross-community claim by the client changes nothing: ' || j::text,
    pg_temp.probe_refused(j) or j = '0'::jsonb);
  j := pg_temp.probe_run(u7, format($q$with x as (update public.rides set status = 'confirmed', claimed_by = %L where id = %L returning 1)
                                     select to_jsonb(count(*)) from x$q$, u7, pg_temp.r(2)));
  perform pg_temp.probe_ok(v_probe, 'a C1 member can claim it (control): ' || j::text, j = '1'::jsonb);

  v_ids := array(select m.user_id from public.community_members m where m.community_id = c1 and m.status = 'active');
  j := pg_temp.probe_run(u4, format($q$select coalesce(jsonb_agg(x.user_id), '[]'::jsonb)
                                     from public.get_community_leaderboard(%L::uuid, '1970-01-01'::date, current_date) x$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the C1 leaderboard answers its admin and lists the probe member: ' || j::text,
    not pg_temp.probe_refused(j) and j ? u3::text);
  perform pg_temp.probe_ok(v_probe, 'the C1 leaderboard lists only C1 members',
    not exists (select 1 from jsonb_array_elements_text(j) e where e::uuid <> all (v_ids)));
  j := pg_temp.probe_run(u4, format($q$select to_jsonb(x) from public.get_community_leaderboard(%L::uuid, '1970-01-01'::date, current_date) x
                                     where x.user_id = %L$q$, c1, u7));
  perform pg_temp.probe_ok(v_probe, 'the C1 leaderboard counts only C1 requests: ' || j::text, (j ->> 'requests_made')::int = 1);
  j := pg_temp.probe_run(u4, format($q$select coalesce(jsonb_agg(x.user_id), '[]'::jsonb)
                                     from public.get_community_spotlights(%L::uuid, '1970-01-01'::date, current_date) x$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the C1 spotlights answer its admin: ' || coalesce(j ->> 'error', ''), not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the C1 spotlights name only C1 members',
    not exists (select 1 from jsonb_array_elements_text(j) e where e::uuid <> all (v_ids)));

  perform pg_temp.probe_ok(v_probe, 'a probe member reads only their own community_members rows',
    pg_temp.probe_count(u3, format('select 1 from public.community_members where user_id <> %L', u3)) = 0
    and pg_temp.probe_count(u3, 'select 1 from public.community_members') = 1);

  j := pg_temp.probe_run(u3, format($q$select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                                     from public.get_community_members(%L::uuid, 'active', 100, 0) x$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'get_community_members answers a member: ' || coalesce(j ->> 'error', ''),
    not pg_temp.probe_refused(j) and jsonb_array_length(j) >= 5);
  perform pg_temp.probe_ok(v_probe, 'a member gets null answers',
    not exists (select 1 from jsonb_array_elements(j) e
                 where nullif(e ->> 'heard_about', '') is not null or nullif(e ->> 'join_reason', '') is not null));
  perform pg_temp.probe_ok(v_probe, 'nobody gets email or phone',
    not exists (select 1 from jsonb_array_elements(j) e where e ? 'email' or e ? 'phone_number'));
  j := pg_temp.probe_run(u4, format($q$select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                                     from public.get_community_members(%L::uuid, 'active', 100, 0) x$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'its admin gets the answers',
    exists (select 1 from jsonb_array_elements(j) e where e ->> 'id' = u7::text and e ->> 'heard_about' = 'Probe heard'));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE isolation OK' as probe;


-- =============================================================================================================
-- legacy_bridges: the installed build's application UPDATE, approve and reject.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'legacy_bridges';
  d uuid;
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u4 uuid := pg_temp.u(4);   u8 uuid := pg_temp.u(8);   u9 uuid := pg_temp.u(9);
  u10 uuid := pg_temp.u(10); u11 uuid := pg_temp.u(11); u13 uuid := pg_temp.u(13); u15 uuid := pg_temp.u(15);
  c1 uuid := pg_temp.c(1);
  v_ids uuid[];
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  if not exists (select 1 from pg_catalog.pg_trigger where not tgisinternal and tgname = 'legacy_application_to_membership') then
    raise notice 'PROBE % SKIPPED: the legacy bridges are retired (20261019_0060); legacy_retired covers this', v_probe;
    return;
  end if;
  perform pg_temp.probe_world();
  d := public.default_community_id();

  -- old-client application UPDATE -> pending default membership, one pending_approval per default admin
  j := pg_temp.probe_run(u10, format($q$with x as (update public.profiles
        set heard_about = 'Probe heard', join_reason = 'Probe reason', application_complete = true, application_submitted_at = now()
        where id = %L returning 1) select to_jsonb(count(*)) from x$q$, u10));
  perform pg_temp.probe_ok(v_probe, 'the old application UPDATE succeeds: ' || j::text, j = '1'::jsonb);
  perform pg_temp.probe_ok(v_probe, 'it creates a pending default membership',
    exists (select 1 from public.community_members where community_id = d and user_id = u10 and status = 'pending'));
  v_ids := array(select m.user_id from public.community_members m join public.profiles p on p.id = m.user_id
                  where m.community_id = d and m.status = 'active' and m.role in ('owner', 'admin') and not p.is_banned);
  perform pg_temp.probe_ok(v_probe, format('exactly one pending_approval per default-community admin (%s)', cardinality(v_ids)),
    cardinality(v_ids) > 0
    and (select count(*) from public.notifications where type = 'pending_approval' and source_user_id = u10) = cardinality(v_ids)
    and (select count(distinct user_id) from public.notifications where type = 'pending_approval' and source_user_id = u10) = cardinality(v_ids)
    and not exists (select 1 from public.notifications where type = 'pending_approval' and source_user_id = u10 and user_id <> all (v_ids)));

  -- old-client approve -> active membership and approved
  j := pg_temp.probe_run(v_admin, format($q$with x as (update public.profiles set approved = true where id = %L returning 1)
                                          select to_jsonb(count(*)) from x$q$, u10));
  perform pg_temp.probe_ok(v_probe, 'the old approve UPDATE succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'old approve -> active default membership and approved = true',
    exists (select 1 from public.community_members where community_id = d and user_id = u10 and status = 'active')
    and (select approved from public.profiles where id = u10));

  -- old-client approve of a probe-community-only applicant -> approved stays false
  j := pg_temp.probe_run(v_admin, format($q$with x as (update public.profiles set approved = true where id = %L returning 1)
                                          select to_jsonb(count(*)) from x$q$, u9));
  perform pg_temp.probe_ok(v_probe, 'old approve of a C1 applicant raises nothing: ' || j::text, coalesce(j ->> 'raised', '') <> 'true');
  perform pg_temp.probe_ok(v_probe, 'old approve of a C1 applicant leaves approved false and the C1 row pending',
    not (select approved from public.profiles where id = u9)
    and exists (select 1 from public.community_members where community_id = c1 and user_id = u9 and status = 'pending'));

  -- approve through both paths in one transaction -> one state, no error, one welcome
  j := pg_temp.probe_call(v_admin, format('public.approve_community_member(%L::uuid, %L::uuid)', d, u8));
  perform pg_temp.probe_ok(v_probe, 'approve_community_member succeeds: ' || j::text, not pg_temp.probe_refused(j));
  j := pg_temp.probe_run(v_admin, format($q$with x as (update public.profiles set approved = true where id = %L returning 1)
                                          select to_jsonb(count(*)) from x$q$, u8));
  perform pg_temp.probe_ok(v_probe, 'the old approve after the new one raises nothing: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'both paths -> one active row, approved, one user_approved',
    (select count(*) from public.community_members where user_id = u8) = 1
    and exists (select 1 from public.community_members where community_id = d and user_id = u8 and status = 'active')
    and (select approved from public.profiles where id = u8)
    and (select count(*) from public.notifications where user_id = u8 and type = 'user_approved') = 1);

  -- old-client reject (admin_reject_pending_user)
  j := pg_temp.probe_call(v_admin, format('public.admin_reject_pending_user(%L::uuid)', u15));
  perform pg_temp.probe_ok(v_probe, 'reject of a default applicant succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'reject of a default applicant removes the row and the account',
    not exists (select 1 from public.community_members where user_id = u15)
    and not exists (select 1 from public.profiles where id = u15) and not exists (select 1 from auth.users where id = u15));

  j := pg_temp.probe_call(v_admin, format('public.admin_reject_pending_user(%L::uuid)', u9));
  perform pg_temp.probe_ok(v_probe, 'reject of a C1-only applicant -> success false: ' || j::text, coalesce(j ->> 'success', '') = 'false');
  perform pg_temp.probe_ok(v_probe, 'reject of a C1-only applicant changes nothing',
    exists (select 1 from public.profiles where id = u9)
    and exists (select 1 from public.community_members where community_id = c1 and user_id = u9 and status = 'pending'));

  j := pg_temp.probe_call(v_admin, format('public.admin_reject_pending_user(%L::uuid)', u13));
  perform pg_temp.probe_ok(v_probe, 'reject of a never-applied account -> success false: ' || j::text, coalesce(j ->> 'success', '') = 'false');
  perform pg_temp.probe_ok(v_probe, 'reject of a never-applied account changes nothing', exists (select 1 from public.profiles where id = u13));

  j := pg_temp.probe_call(v_admin, format('public.admin_reject_pending_user(%L::uuid)', u11));
  perform pg_temp.probe_ok(v_probe, 'reject of a C1 member with a pending default row succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'only the default row goes; the account stays approved',
    not exists (select 1 from public.community_members where community_id = d and user_id = u11)
    and exists (select 1 from public.community_members where community_id = c1 and user_id = u11 and status = 'active')
    and (select approved from public.profiles where id = u11));

  j := pg_temp.probe_call(u4, format('public.admin_reject_pending_user(%L::uuid)', u9));
  perform pg_temp.probe_ok(v_probe, 'a community owner who is not a platform admin is refused: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the refused reject changed nothing',
    exists (select 1 from public.profiles where id = u9)
    and exists (select 1 from public.community_members where community_id = c1 and user_id = u9));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE legacy_bridges OK' as probe;


-- =============================================================================================================
-- owner_notifications: an applicant redeems a code for an approval-gated probe community; its owner (not a
-- platform admin) holds exactly one pending_approval bell row and one queued push; a platform admin holds none.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'owner_notifications';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u4 uuid := pg_temp.u(4);  u6 uuid := pg_temp.u(6);
  c1 uuid := pg_temp.c(1);
  v_code text;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  j := pg_temp.probe_call(u4, format($q$public.create_community_invite(%L::uuid, 5, now() + interval '30 days')$q$, c1));
  v_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'the owner creates a code: ' || j::text, not pg_temp.probe_refused(j) and v_code is not null);
  j := pg_temp.probe_call(u6, format('public.redeem_community_invite(%L, %L, %L)', v_code, 'Probe heard', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'the applicant redeems it and is pending: ' || j::text, j ->> 'status' = 'pending');

  perform pg_temp.probe_ok(v_probe, 'the owner holds exactly one pending_approval bell row for the applicant, in C1',
    (select count(*) from public.notifications where user_id = u4 and type = 'pending_approval' and source_user_id = u6) = 1
    and (select community_id from public.notifications where user_id = u4 and type = 'pending_approval' and source_user_id = u6) = c1);
  perform pg_temp.probe_ok(v_probe, 'the owner holds exactly one queued pending_approval push for the applicant',
    (select count(*) from public.notification_queue
      where recipient_user_id = u4 and notification_type = 'pending_approval' and payload -> 'data' ->> 'user_id' = u6::text) = 1);
  perform pg_temp.probe_ok(v_probe, 'a platform admin holds none',
    not exists (select 1 from public.notifications where user_id = v_admin and type = 'pending_approval' and source_user_id = u6)
    and not exists (select 1 from public.notification_queue
                     where recipient_user_id = v_admin and notification_type = 'pending_approval' and payload -> 'data' ->> 'user_id' = u6::text));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE owner_notifications OK' as probe;


-- =============================================================================================================
-- privileged_columns: a non-admin's direct UPDATE of approved, is_admin, is_banned, primary_community_id or
-- max_owned_communities raises; the mirror's write (through an RPC called with a JWT) succeeds; a maintenance
-- write with no JWT succeeds; create_signup_profile re-run by a member leaves approved true.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'privileged_columns';
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u6 uuid := pg_temp.u(6);  u13 uuid := pg_temp.u(13);
  c1 uuid := pg_temp.c(1);
  v_sql text;
  v_new uuid;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  foreach v_sql in array array[
    format('update public.profiles set approved = false where id = %L', v_member),
    format('update public.profiles set is_admin = true where id = %L', v_member),
    format('update public.profiles set is_banned = true where id = %L', v_member),
    format('update public.profiles set primary_community_id = %L where id = %L', c1, v_member),
    format('update public.profiles set max_owned_communities = 10 where id = %L', v_member)]
  loop
    j := pg_temp.probe_run(v_member, 'with x as (' || v_sql || ' returning 1) select to_jsonb(count(*)) from x');
    perform pg_temp.probe_ok(v_probe, format('a member''s direct write raises (%s): %s', v_sql, j::text), coalesce(j ->> 'raised', '') = 'true');
  end loop;

  j := pg_temp.probe_call(u6, format('public.create_community(%L, %L, %L)', 'Probe Mirror Community', 'communities probe', 'invite'));
  v_new := nullif(j ->> 'community_id', '')::uuid;
  perform pg_temp.probe_ok(v_probe, 'an account without membership creates a community: ' || j::text, not pg_temp.probe_refused(j) and v_new is not null);
  perform pg_temp.probe_ok(v_probe, 'the mirror wrote approved, application_complete and the primary under a JWT',
    exists (select 1 from public.profiles where id = u6 and approved and application_complete and primary_community_id = v_new));

  j := pg_temp.probe_run(null, format($q$with x as (update public.profiles set is_banned = true, banned_at = now() where id = %L returning 1)
                                       select to_jsonb(count(*)) from x$q$, u13), 'owner');
  perform pg_temp.probe_ok(v_probe, 'a maintenance write with no JWT succeeds: ' || j::text, j = '1'::jsonb);

  j := pg_temp.probe_call(u3, format('public.create_signup_profile(%L::uuid, %L, %L)', u3,
                                     (select email from public.profiles where id = u3), (select name from public.profiles where id = u3)));
  perform pg_temp.probe_ok(v_probe, 'create_signup_profile re-run by a member raises nothing: ' || j::text, coalesce(j ->> 'raised', '') <> 'true');
  perform pg_temp.probe_ok(v_probe, 'and leaves approved and application_complete true',
    exists (select 1 from public.profiles where id = u3 and approved and application_complete));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE privileged_columns OK' as probe;


-- =============================================================================================================
-- membership_end: leaving the only community clears approved and application_complete; removal reports the
-- counts unwind_member_requests returned; a removed member reads no communities row for it and cannot redeem a
-- code to it; a banned account cannot redeem, request or be approved.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'membership_end';
  u2 uuid := pg_temp.u(2);  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u7 uuid := pg_temp.u(7);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  v_code text;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  j := pg_temp.probe_call(u7, format('public.leave_community(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'a member leaves their only community: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'leaving the only community -> approved = false, application_complete = false',
    exists (select 1 from public.profiles where id = u7 and not approved and not application_complete));
  perform pg_temp.probe_ok(v_probe, 'the membership is left with role member',
    exists (select 1 from public.community_members where community_id = c1 and user_id = u7 and status = 'left' and role = 'member'));

  j := pg_temp.probe_call(u4, format($q$public.create_community_invite(%L::uuid, 10, now() + interval '30 days')$q$, c1));
  v_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'the owner creates a multi-use code: ' || j::text, not pg_temp.probe_refused(j) and v_code is not null);
  j := pg_temp.probe_call(u4, format('public.remove_community_member(%L::uuid, %L::uuid, %L)', c1, u3, 'Probe removal'));
  perform pg_temp.probe_ok(v_probe, 'the owner removes a member: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the member is removed',
    exists (select 1 from public.community_members where community_id = c1 and user_id = u3 and status = 'removed'));
  perform pg_temp.probe_ok(v_probe, 'the counts are what unwind_member_requests did (r(2) deleted: removed 1, reopened 0, cancelled 0): ' || j::text,
    (j ->> 'removed')::int = 1 and (j ->> 'reopened')::int = 0 and (j ->> 'cancelled')::int = 0
    and not exists (select 1 from public.rides where id = pg_temp.r(2)));
  perform pg_temp.probe_ok(v_probe, 'a removed member reads no communities row for it',
    pg_temp.probe_count(u3, format('select 1 from public.communities where id = %L', c1)) = 0);
  j := pg_temp.probe_call(u3, format('public.redeem_community_invite(%L, null, null)', v_code));
  perform pg_temp.probe_ok(v_probe, 'a removed member cannot redeem a code to it: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and stays removed',
    exists (select 1 from public.community_members where community_id = c1 and user_id = u3 and status = 'removed'));

  perform pg_temp.probe_member(c1, u2, 'member', 'pending', 0);
  j := pg_temp.probe_call(u2, format('public.redeem_community_invite(%L, null, null)', v_code));
  perform pg_temp.probe_ok(v_probe, 'a banned account cannot redeem: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u2, format('public.request_to_join_community(%L::uuid, %L, %L)', c2, 'Probe heard', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'a banned account cannot request to join: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the refused request wrote no C2 row',
    not exists (select 1 from public.community_members where community_id = c2 and user_id = u2));
  j := pg_temp.probe_call(u4, format('public.approve_community_member(%L::uuid, %L::uuid)', c1, u2));
  perform pg_temp.probe_ok(v_probe, 'a banned account cannot be approved: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and stays pending',
    exists (select 1 from public.community_members where community_id = c1 and user_id = u2 and status = 'pending'));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE membership_end OK' as probe;


-- =============================================================================================================
-- archive: a member of an archived probe community reads none of its rides, cannot insert, and (it being their
-- only community) has approved = false and application_complete = false; the completion reminder of a confirmed
-- request there is dropped; restoring reverses both flags; the default community cannot be archived; a non-member,
-- a pending applicant and a plain member are refused (20261022_0001).
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'archive';
  d uuid;
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);
  u9 uuid := pg_temp.u(9);  u13 uuid := pg_temp.u(13);
  c1 uuid := pg_temp.c(1);
  v_rides_sql text;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();
  d := public.default_community_id();
  v_rides_sql := format('select 1 from public.rides where community_id = %L and user_id <> %L', c1, u3);

  perform pg_temp.probe_ok(v_probe, 'before archiving the member reads C1 rides (control)', pg_temp.probe_count(u3, v_rides_sql) >= 1);
  -- only the owner or a platform admin archives: no membership, a pending row or a plain member role is refused
  j := pg_temp.probe_call(u13, format('public.archive_community(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'a signed-in account with no membership cannot archive C1: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'C1 is still live', exists (select 1 from public.communities where id = c1 and archived_at is null));
  j := pg_temp.probe_call(u9, format('public.archive_community(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'a pending applicant cannot archive C1: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'C1 is still live', exists (select 1 from public.communities where id = c1 and archived_at is null));
  j := pg_temp.probe_call(u3, format('public.archive_community(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'a member who is not the owner cannot archive C1: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'C1 is still live', exists (select 1 from public.communities where id = c1 and archived_at is null));
  -- a confirmed request with a completion reminder, so the archive's reminder cleanup can be checked
  update public.rides set status = 'confirmed', claimed_by = pg_temp.u(7) where id = pg_temp.r(2);
  insert into public.completion_reminders (ride_id, claimer_user_id, scheduled_for)
  select pg_temp.r(2), pg_temp.u(7), now() + interval '1 day'
   where not exists (select 1 from public.completion_reminders where ride_id = pg_temp.r(2));
  j := pg_temp.probe_call(u4, format('public.archive_community(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner archives C1: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'archiving drops the completion reminder of a confirmed C1 request',
    not exists (select 1 from public.completion_reminders where ride_id = pg_temp.r(2)));
  perform pg_temp.probe_ok(v_probe, 'C1 is archived', exists (select 1 from public.communities where id = c1 and archived_at is not null));
  perform pg_temp.probe_ok(v_probe, 'a member of the archived community reads 0 of its rides', pg_temp.probe_count(u3, v_rides_sql) = 0);
  j := pg_temp.probe_run(u3, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination, community_id)
       values (%L, current_date + 1, '10:00', 'Probe pickup', 'Probe destination', %L) returning to_jsonb(id)$q$, u3, c1));
  perform pg_temp.probe_ok(v_probe, 'and cannot insert into it: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'archiving their only community -> approved = false, application_complete = false',
    exists (select 1 from public.profiles where id = u3 and not approved and not application_complete));

  j := pg_temp.probe_call(v_admin, format('public.unarchive_community(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'a platform admin restores C1: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'restoring -> approved = true, application_complete = true',
    exists (select 1 from public.profiles where id = u3 and approved and application_complete));
  perform pg_temp.probe_ok(v_probe, 'the member reads C1 rides again', pg_temp.probe_count(u3, v_rides_sql) >= 1);

  j := pg_temp.probe_call(v_admin, format('public.archive_community(%L::uuid)', d));
  perform pg_temp.probe_ok(v_probe, 'the default community cannot be archived: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and is still live', exists (select 1 from public.communities where id = d and archived_at is null));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE archive OK' as probe;


-- =============================================================================================================
-- invites: a member's code is single-use and expires within 7 days whatever the arguments; after 10 failed
-- validations in an hour the account is refused; validate_community_invite as anon -> permission denied.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'invites';
  u1 uuid := pg_temp.u(1);  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u6 uuid := pg_temp.u(6);
  c1 uuid := pg_temp.c(1);
  v_code text;
  v_admin_code text;
  i int;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  j := pg_temp.probe_call(u3, format($q$public.create_community_invite(%L::uuid, 50, now() + interval '60 days')$q$, c1));
  v_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'a member creates a code: ' || j::text, not pg_temp.probe_refused(j) and v_code is not null);
  perform pg_temp.probe_ok(v_probe, 'a member''s code is single-use and expires within 7 days',
    exists (select 1 from public.community_invites
             where code = v_code and created_by = u3 and max_uses = 1
               and expires_at is not null and expires_at <= now() + interval '7 days 1 minute'));

  j := pg_temp.probe_call(u4, format($q$public.create_community_invite(%L::uuid, 5, now() + interval '30 days')$q$, c1));
  v_admin_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'an admin creates a multi-use code: ' || j::text, not pg_temp.probe_refused(j) and v_admin_code is not null
    and exists (select 1 from public.community_invites where code = v_admin_code and max_uses = 5));
  j := pg_temp.probe_call(u1, format('public.validate_community_invite(%L)', v_admin_code));
  perform pg_temp.probe_ok(v_probe, 'the admin code validates (control): ' || j::text, j ->> 'valid' = 'true');
  perform pg_temp.probe_ok(v_probe, 'the preview carries no ids', not (j ? 'community_id') and not (j ? 'id'));

  for i in 1..10 loop
    j := pg_temp.probe_call(u6, $q$public.validate_community_invite('NCZZZZZZZZ')$q$);
    perform pg_temp.probe_ok(v_probe, format('failed validation %s is not valid: %s', i, j::text), coalesce(j ->> 'valid', '') <> 'true');
  end loop;
  j := pg_temp.probe_call(u6, format('public.validate_community_invite(%L)', v_admin_code));
  perform pg_temp.probe_ok(v_probe, 'the 11th validation in the hour is refused, even for a valid code: ' || j::text,
    pg_temp.probe_refused(j) or coalesce(j ->> 'valid', '') <> 'true');

  j := pg_temp.probe_call(null, format('public.validate_community_invite(%L)', v_admin_code), 'anon');
  perform pg_temp.probe_ok(v_probe, 'validate_community_invite as anon -> permission denied: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE invites OK' as probe;


-- =============================================================================================================
-- account_deletion (decision A3): a sole owner with an admin -> the admin is owner; a sole owner with members
-- but no admin -> the community is archived with the deletion and its members are told; a sole owner alone ->
-- archived. In every case the profile deletes cleanly, the user's invites are revoked and their event rows
-- have null user_id and reason.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'account_deletion';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);
  u12 uuid := pg_temp.u(12);  u14 uuid := pg_temp.u(14);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);  c3 uuid := pg_temp.c(3);
  v_code text;
  v_x uuid;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  j := pg_temp.probe_call(u4, format($q$public.create_community_invite(%L::uuid, 5, now() + interval '30 days')$q$, c1));
  v_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'the C1 owner creates a code: ' || j::text, not pg_temp.probe_refused(j) and v_code is not null);
  insert into public.community_membership_events (community_id, user_id, event, reason)
  values (c1, u4, 'role_changed', 'Probe reason about the owner');
  perform pg_temp.probe_member(c2, u3, 'member', 'active', 3);   -- C2: owner u12 with one member, no admin

  foreach v_x in array array[u4, u12, u14] loop
    j := pg_temp.probe_call(v_x, format('public.delete_user_account(%L::uuid)', v_x));
    perform pg_temp.probe_ok(v_probe, format('owner %s deletes their account: %s', v_x, coalesce(j ->> 'error', '')), not pg_temp.probe_refused(j));
    perform pg_temp.probe_ok(v_probe, format('owner %s is gone from profiles and auth.users', v_x),
      not exists (select 1 from public.profiles where id = v_x) and not exists (select 1 from auth.users where id = v_x));
    perform pg_temp.probe_ok(v_probe, format('no event row names %s any more', v_x),
      not exists (select 1 from public.community_membership_events where user_id = v_x));
  end loop;

  perform pg_temp.probe_ok(v_probe, 'sole owner with an admin -> the admin is owner and C1 stays live',
    exists (select 1 from public.community_members where community_id = c1 and user_id = u5 and role = 'owner' and status = 'active')
    and exists (select 1 from public.communities where id = c1 and archived_at is null));
  perform pg_temp.probe_ok(v_probe, 'the deleted owner''s invite is revoked',
    exists (select 1 from public.community_invites where code = v_code and revoked_at is not null));
  perform pg_temp.probe_ok(v_probe, 'the event row about the deleted owner has null user_id and reason',
    exists (select 1 from public.community_membership_events
             where community_id = c1 and event = 'role_changed' and user_id is null and reason is null));

  perform pg_temp.probe_ok(v_probe, 'sole owner with members only -> C2 archived with the deletion',
    exists (select 1 from public.communities where id = c2 and archived_at is not null));
  perform pg_temp.probe_ok(v_probe, 'the C2 member is told',
    exists (select 1 from public.notifications where user_id = u3 and type = 'announcement' and community_id = c2));
  perform pg_temp.probe_ok(v_probe, 'the C2 member keeps their other community',
    exists (select 1 from public.profiles where id = u3 and approved));
  perform pg_temp.probe_ok(v_probe, 'sole owner alone -> C3 archived',
    exists (select 1 from public.communities where id = c3 and archived_at is not null));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE account_deletion OK' as probe;


-- =============================================================================================================
-- reports: report_community creates a row only platform admins can read; a person report between two people
-- who share exactly one community gets that community; decision A2: a non-member can report a public
-- community, a private community needs membership or a valid code, a guest cannot report.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'reports';
  v_member uuid := pg_temp.probe_subject('member');
  v_admin  uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u10 uuid := pg_temp.u(10);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  v_report uuid;
  v_code text;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  j := pg_temp.probe_call(u3, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                         p_report_type => 'spam', p_description => 'Probe community report')$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'a member reports their community: ' || j::text, not pg_temp.probe_refused(j));
  v_report := (select id from public.reports where reporter_id = u3 and reported_community_id = c1 order by created_at desc limit 1);
  perform pg_temp.probe_ok(v_probe, 'the report row exists and routes to platform admins only (community_id null)',
    v_report is not null and (select community_id from public.reports where id = v_report) is null);
  perform pg_temp.probe_ok(v_probe, 'a platform admin reads it', pg_temp.probe_count(v_admin, format('select 1 from public.reports where id = %L', v_report)) = 1);
  perform pg_temp.probe_ok(v_probe, 'the community''s owner and admin do not',
    pg_temp.probe_count(u4, format('select 1 from public.reports where id = %L', v_report)) = 0
    and pg_temp.probe_count(u5, format('select 1 from public.reports where id = %L', v_report)) = 0);
  perform pg_temp.probe_ok(v_probe, 'another member does not', pg_temp.probe_count(v_member, format('select 1 from public.reports where id = %L', v_report)) = 0);

  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, null, null, null, null, 'harassment', 'Probe person report')$q$, u3, u7));
  perform pg_temp.probe_ok(v_probe, 'a person report is filed: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'a person report between two people sharing exactly one community gets it',
    (select community_id from public.reports where reporter_id = u3 and reported_user_id = u7 order by created_at desc limit 1) = c1);

  -- A2: a public community, reported by a signed-in non-member
  j := pg_temp.probe_call(u10, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                          p_report_type => 'inappropriate_content', p_description => 'Probe public report')$q$, c2));
  perform pg_temp.probe_ok(v_probe, 'a non-member reports a public community: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the public-community report routes to platform admins only',
    exists (select 1 from public.reports where reporter_id = u10 and reported_community_id = c2 and community_id is null));

  j := pg_temp.probe_call(v_member, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                              p_report_type => 'spam', p_description => 'Probe private report')$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'a non-member cannot report a private community it cannot see: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the refused report wrote nothing',
    not exists (select 1 from public.reports where reporter_id = v_member and reported_community_id = c1));

  j := pg_temp.probe_call(u4, format($q$public.create_community_invite(%L::uuid, 5, now() + interval '30 days')$q$, c1));
  v_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'the owner creates a code: ' || j::text, not pg_temp.probe_refused(j) and v_code is not null);
  j := pg_temp.probe_call(v_member, format($q$public.report_community(p_community_id => null, p_code => %L,
                                              p_report_type => 'spam', p_description => 'Probe code report')$q$, v_code));
  perform pg_temp.probe_ok(v_probe, 'a holder of a valid code can report the private community: ' || j::text,
    not pg_temp.probe_refused(j)
    and exists (select 1 from public.reports where reporter_id = v_member and reported_community_id = c1));

  j := pg_temp.probe_call(null, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                          p_report_type => 'spam', p_description => 'Probe guest report')$q$, c2), 'anon');
  perform pg_temp.probe_ok(v_probe, 'a guest cannot report: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE reports OK' as probe;


-- =============================================================================================================
-- reputation: two viewers who each share a different community with the same person read identical
-- get_profile_stats; a viewer who shares none gets an empty result; get_community_leaderboard for a private
-- community the caller is not in is refused. Once Release 1 (20261021_0001) is live, an active member of a listed
-- community is readable by every signed-in account: the "shares none" check reads u3 (C1 only, private) instead of
-- u5 (active in public C2), and a default member now reads u5's stats.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'reputation';
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  v_release1 boolean := to_regprocedure('public.get_community_preview(uuid)') is not null;
  j jsonb;
  k jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();

  -- u5 is in C1 (with u3) and C2 (with u12); u3 and u12 share nothing. u5 helped u12 in C2.
  perform pg_temp.probe_member(c2, u5, 'member', 'active', 5);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id)
  values (pg_temp.r(5), u12, current_date - 3, '09:00', 'Probe pickup', 'Probe destination', 'completed', u5, c2);
  insert into public.reviews (reviewer_id, fulfiller_id, ride_id, rating, comment)
  values (u12, u5, pg_temp.r(5), 4, 'Probe review');

  j := pg_temp.probe_call(u3,  format('public.get_profile_stats(%L::uuid)', u5));
  k := pg_temp.probe_call(u12, format('public.get_profile_stats(%L::uuid)', u5));
  perform pg_temp.probe_ok(v_probe, 'a C1 viewer reads the stats: ' || j::text, not pg_temp.probe_empty(j) and (j ->> 'review_count')::int = 1);
  perform pg_temp.probe_ok(v_probe, format('viewers through different communities read identical stats: %s vs %s', j, k), j = k);
  if v_release1 then
    -- u3 has u7's review of r(1): a C1 co-member reads it (control), a default member does not
    j := pg_temp.probe_call(u7, format('public.get_profile_stats(%L::uuid)', u3));
    perform pg_temp.probe_ok(v_probe, 'a C1 viewer reads u3''s stats (control): ' || j::text, not pg_temp.probe_empty(j) and (j ->> 'review_count')::int = 1);
    j := pg_temp.probe_call(v_member, format('public.get_profile_stats(%L::uuid)', u3));
    perform pg_temp.probe_ok(v_probe, 'a viewer who shares no community gets an empty result: ' || j::text, pg_temp.probe_empty(j));
    k := pg_temp.probe_call(v_member, format('public.get_profile_stats(%L::uuid)', u5));
    perform pg_temp.probe_ok(v_probe, 'a default member reads the stats of an active member of a listed community: ' || k::text,
      not pg_temp.probe_empty(k) and (k ->> 'review_count')::int = 1);
  else
    j := pg_temp.probe_call(v_member, format('public.get_profile_stats(%L::uuid)', u5));
    perform pg_temp.probe_ok(v_probe, 'a viewer who shares no community gets an empty result: ' || j::text, pg_temp.probe_empty(j));
  end if;

  j := pg_temp.probe_run(v_member, format($q$select coalesce(jsonb_agg(x.user_id), '[]'::jsonb)
                                           from public.get_community_leaderboard(%L::uuid, '1970-01-01'::date, current_date) x$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the leaderboard of a private community the caller is not in is refused: ' || j::text,
    pg_temp.probe_refused(j) or j = '[]'::jsonb);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE reputation OK' as probe;


-- =============================================================================================================
-- blocks: with a block in either direction, get_community_members (as a non-admin) and
-- search_community_members leave the other person out; an admin's pending list does not.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'blocks';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u7 uuid := pg_temp.u(7);  u9 uuid := pg_temp.u(9);
  c1 uuid := pg_temp.c(1);
  v_members text;
  v_search text;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();
  v_members := format($q$select coalesce(jsonb_agg(x.id), '[]'::jsonb) from public.get_community_members(%L::uuid, 'active', 100, 0) x$q$, c1);
  v_search  := format($q$select coalesce(jsonb_agg(x.id), '[]'::jsonb) from public.search_community_members('Probe', %L::uuid, 50) x$q$, c1);

  perform pg_temp.probe_ok(v_probe, 'before the block u3 sees u7 in the directory and in search (control)',
    pg_temp.probe_run(u3, v_members) ? u7::text and pg_temp.probe_run(u3, v_search) ? u7::text);

  insert into public.blocked_users (blocker_id, blocked_id, reason) values (u3, u7, 'communities probe');
  j := pg_temp.probe_run(u3, v_members);
  perform pg_temp.probe_ok(v_probe, 'the blocker''s directory leaves the blocked person out: ' || j::text, not pg_temp.probe_refused(j) and not (j ? u7::text));
  j := pg_temp.probe_run(u3, v_search);
  perform pg_temp.probe_ok(v_probe, 'the blocker''s search leaves the blocked person out: ' || j::text, not pg_temp.probe_refused(j) and not (j ? u7::text));
  j := pg_temp.probe_run(u7, v_members);
  perform pg_temp.probe_ok(v_probe, 'the blocked person''s directory leaves the blocker out: ' || j::text, not pg_temp.probe_refused(j) and not (j ? u3::text));
  j := pg_temp.probe_run(u7, v_search);
  perform pg_temp.probe_ok(v_probe, 'the blocked person''s search leaves the blocker out: ' || j::text, not pg_temp.probe_refused(j) and not (j ? u3::text));

  insert into public.blocked_users (blocker_id, blocked_id, reason) values (u4, u9, 'communities probe');
  j := pg_temp.probe_run(u4, format($q$select coalesce(jsonb_agg(x.id), '[]'::jsonb) from public.get_community_members(%L::uuid, 'pending', 100, 0) x$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the admin''s pending list is not block-filtered: ' || j::text, j ? u9::text);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE blocks OK' as probe;


-- =============================================================================================================
-- creation_limits (decision A1): 1 community per account per day; 3 owned by default; the limit-raise request
-- (validation, one open request, platform admins told) and its decision (non-admin refused, approval raises
-- profiles.max_owned_communities and tells the requester, a decided request cannot be decided again, a
-- decline leaves the limit and tells the requester).
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'creation_limits';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u10 uuid := pg_temp.u(10);  u16 uuid := pg_temp.u(16);
  v_req uuid;
  v_req2 uuid;
  v_admins bigint;
  v_before bigint;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();
  v_admins := (select count(*) from public.profiles where is_admin and not is_banned);

  -- daily limit
  j := pg_temp.probe_call(u10, format('public.create_community(%L, %L, %L)', 'Probe Daily One', 'communities probe', 'approve'));
  perform pg_temp.probe_ok(v_probe, 'the first community of the day is created: ' || j::text,
    not pg_temp.probe_refused(j) and nullif(j ->> 'community_id', '') is not null);
  j := pg_temp.probe_call(u10, format('public.create_community(%L, %L, %L)', 'Probe Daily Two', 'communities probe', 'approve'));
  perform pg_temp.probe_ok(v_probe, 'the second community the same day is refused: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and was not created', not exists (select 1 from public.communities where name = 'Probe Daily Two'));

  -- owned limit: u4 owns C1 plus two more (all created 30 days ago)
  perform pg_temp.probe_community(4, 'Probe Owned Two',   u4, false, 'approve');
  perform pg_temp.probe_community(5, 'Probe Owned Three', u4, false, 'approve');
  j := pg_temp.probe_call(u4, format('public.create_community(%L, %L, %L)', 'Probe Owned Four', 'communities probe', 'approve'));
  perform pg_temp.probe_ok(v_probe, 'a fourth owned community is refused at the default limit of 3: ' || j::text, pg_temp.probe_refused(j));

  -- the limit request
  j := pg_temp.probe_call(u4, $q$public.request_owned_community_limit(3, 'Probe reason')$q$);
  perform pg_temp.probe_ok(v_probe, 'a requested limit below 4 is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u4, $q$public.request_owned_community_limit(21, 'Probe reason')$q$);
  perform pg_temp.probe_ok(v_probe, 'a requested limit above 20 is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u4, $q$public.request_owned_community_limit(5, '   ')$q$);
  perform pg_temp.probe_ok(v_probe, 'a request without a reason is refused: ' || j::text, pg_temp.probe_refused(j));

  v_before := (select count(*) from public.notifications n join public.profiles p on p.id = n.user_id
                where n.type = 'announcement' and p.is_admin and not p.is_banned);
  j := pg_temp.probe_call(u4, $q$public.request_owned_community_limit(5, 'Probe reason')$q$);
  v_req := nullif(j ->> 'request_id', '')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a valid request is accepted: ' || j::text, not pg_temp.probe_refused(j) and v_req is not null);
  perform pg_temp.probe_ok(v_probe, 'the request row is pending with the requested number',
    exists (select 1 from public.community_limit_requests where id = v_req and user_id = u4 and requested_max = 5 and status = 'pending'));
  perform pg_temp.probe_ok(v_probe, 'every platform admin gets one announcement row',
    (select count(*) from public.notifications n join public.profiles p on p.id = n.user_id
      where n.type = 'announcement' and p.is_admin and not p.is_banned) = v_before + v_admins);
  perform pg_temp.probe_ok(v_probe, 'the requester can read their request',
    pg_temp.probe_count(u4, format('select 1 from public.community_limit_requests where id = %L', v_req)) = 1);
  perform pg_temp.probe_ok(v_probe, 'another member cannot',
    pg_temp.probe_count(u5, format('select 1 from public.community_limit_requests where id = %L', v_req)) = 0);
  j := pg_temp.probe_call(u4, $q$public.request_owned_community_limit(6, 'Probe reason again')$q$);
  perform pg_temp.probe_ok(v_probe, 'a second open request is refused: ' || j::text, pg_temp.probe_refused(j));

  -- the decision
  j := pg_temp.probe_call(u5, format('public.decide_owned_community_limit(%L::uuid, true)', v_req));
  perform pg_temp.probe_ok(v_probe, 'a non-platform-admin cannot decide: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the request is still pending', exists (select 1 from public.community_limit_requests where id = v_req and status = 'pending'));

  v_before := (select count(*) from public.notifications where user_id = u4 and type = 'announcement');
  j := pg_temp.probe_call(v_admin, format('public.decide_owned_community_limit(%L::uuid, true)', v_req));
  perform pg_temp.probe_ok(v_probe, 'a platform admin approves: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'approval raises max_owned_communities to the requested number',
    (select max_owned_communities from public.profiles where id = u4) = 5);
  perform pg_temp.probe_ok(v_probe, 'the request is approved, with decider and time',
    exists (select 1 from public.community_limit_requests
             where id = v_req and status = 'approved' and decided_by = v_admin and decided_at is not null));
  perform pg_temp.probe_ok(v_probe, 'the requester is told',
    (select count(*) from public.notifications where user_id = u4 and type = 'announcement') = v_before + 1);
  j := pg_temp.probe_call(v_admin, format('public.decide_owned_community_limit(%L::uuid, false)', v_req));
  perform pg_temp.probe_ok(v_probe, 'a decided request cannot be decided again: ' || j::text, pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and keeps its decision',
    exists (select 1 from public.community_limit_requests where id = v_req and status = 'approved')
    and (select max_owned_communities from public.profiles where id = u4) = 5);
  j := pg_temp.probe_call(u4, format('public.create_community(%L, %L, %L)', 'Probe Owned Four', 'communities probe', 'approve'));
  perform pg_temp.probe_ok(v_probe, 'with the raised limit the fourth community is created: ' || j::text,
    not pg_temp.probe_refused(j) and nullif(j ->> 'community_id', '') is not null);

  -- the decline path: u16 at the default limit
  perform pg_temp.probe_community(6, 'Probe Sixteen One',   u16, false, 'approve');
  perform pg_temp.probe_community(7, 'Probe Sixteen Two',   u16, false, 'approve');
  perform pg_temp.probe_community(8, 'Probe Sixteen Three', u16, false, 'approve');
  j := pg_temp.probe_call(u16, $q$public.request_owned_community_limit(4, 'Probe reason')$q$);
  v_req2 := nullif(j ->> 'request_id', '')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a second account requests a higher limit: ' || j::text, v_req2 is not null);
  v_before := (select count(*) from public.notifications where user_id = u16 and type = 'announcement');
  j := pg_temp.probe_call(v_admin, format('public.decide_owned_community_limit(%L::uuid, false)', v_req2));
  perform pg_temp.probe_ok(v_probe, 'a platform admin declines: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'a decline leaves the limit at 3 and marks the request declined',
    (select max_owned_communities from public.profiles where id = u16) = 3
    and exists (select 1 from public.community_limit_requests where id = v_req2 and status = 'declined' and decided_by = v_admin));
  perform pg_temp.probe_ok(v_probe, 'the declined requester is told',
    (select count(*) from public.notifications where user_id = u16 and type = 'announcement') = v_before + 1);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE creation_limits OK' as probe;


-- =============================================================================================================
-- community_moderation (Phase 3, INV-P2, D27): a report on a probe-community post reaches its owner and admin
-- with no source user and a push carrying community_id, never the author or the reporter, and the platform
-- admins' rows are unchanged; get_community_reports has no reporter field and refuses non-admins; a report on an
-- admin's post reaches no admin of the community, is not in their lists and cannot be moderated by them (nor by
-- its author); a person report between two people sharing one community reaches that community's admins but not
-- the reported person, and one about an admin reaches none; hide / restore / dismiss write the content, the events
-- and the community's own decision, and leave the report pending in the platform admins' queue; platform moderation
-- wins (no restore of a platform admin's hide or of the auto-hide, no hide or dismiss on a report a platform admin
-- reviewed, no hide of hidden content); a community report is out of reach; an archived community's reports are
-- refused.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'community_moderation';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u12 uuid := pg_temp.u(12);
  u11 uuid := pg_temp.u(11);
  c1 uuid := pg_temp.c(1);
  v_post3 uuid;  v_post5 uuid;  v_post11 uuid;  v_post7b uuid;  v_r_post11 uuid;  v_r_auto uuid;
  v_comment uuid := '00000000-0000-4000-d000-000000000601'::uuid;
  v_r_post3 uuid;  v_r_post5 uuid;  v_r_comment uuid;  v_r_person uuid;  v_r_person_admin uuid;  v_r_community uuid;
  v_padmins bigint;
  v_list jsonb;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  v_padmins := (select count(*) from public.profiles where is_admin);

  v_post3 := pg_temp.probe_post(1, u3, c1);    -- a plain member's post
  v_post5 := pg_temp.probe_post(2, u5, c1);    -- an admin's post
  insert into public.town_hall_comments (id, post_id, user_id, content)
  values (v_comment, v_post3, u7, 'communities probe comment');

  -- (a) a member reports a member's post
  j := pg_temp.probe_call(u7, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'harassment', 'Probe post report')$q$, u7, u3, v_post3));
  perform pg_temp.probe_ok(v_probe, 'a member reports a post: ' || j::text, not pg_temp.probe_refused(j));
  v_r_post3 := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the report carries C1', (select community_id from public.reports where id = v_r_post3) = c1);
  perform pg_temp.probe_ok(v_probe, 'the owner and the admin each hold one content_reported row with no source user, in C1',
    (select count(*) from public.notifications n
      where n.user_id in (u4, u5) and n.type = 'content_reported' and n.town_hall_post_id = v_post3
        and n.source_user_id is null and n.community_id = c1) = 2);
  perform pg_temp.probe_ok(v_probe, 'each holds one queued push carrying community_id',
    (select count(*) from public.notification_queue q
      where q.recipient_user_id in (u4, u5) and q.notification_type = 'content_reported'
        and q.payload -> 'data' ->> 'town_hall_post_id' = v_post3::text
        and q.payload -> 'data' ->> 'community_id' = c1::text) = 2);
  perform pg_temp.probe_ok(v_probe, 'the author and the reporter hold none',
    not exists (select 1 from public.notifications n
                 where n.user_id in (u3, u7) and n.type = 'content_reported' and n.town_hall_post_id = v_post3));
  perform pg_temp.probe_ok(v_probe, 'the platform admins'' rows are unchanged: one each, with the reporter',
    (select count(*) from public.notifications n join public.profiles p on p.id = n.user_id
      where p.is_admin and n.type = 'content_reported' and n.town_hall_post_id = v_post3
        and n.source_user_id = u7) = v_padmins);

  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner lists the report: ' || v_list::text,
    coalesce(v_list ->> 'success', '') = 'true'
    and exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
                 where (e ->> 'report_id')::uuid = v_r_post3 and (e ->> 'author_id')::uuid = u3));
  perform pg_temp.probe_ok(v_probe, 'no row has a reporter field, and the reporter''s id appears nowhere in the list',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where e ? 'reporter_id' or e ? 'reporter_name')
    and position(u7::text in (v_list -> 'reports')::text) = 0);
  j := pg_temp.probe_call(u3, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'a plain member is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u12, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'another community''s owner is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(null, format('public.get_community_reports(%L::uuid, null)', c1), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call it: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  -- (b) a report on an admin's post: platform admins only (INV-P2 rule 3)
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe admin post report')$q$, u3, u5, v_post5));
  v_r_post5 := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the report on the admin''s post is filed: ' || j::text, v_r_post5 is not null);
  perform pg_temp.probe_ok(v_probe, 'it reaches no owner or admin of C1',
    not exists (select 1 from public.notifications n
                  join public.community_members m on m.user_id = n.user_id and m.community_id = c1
                                                 and m.status = 'active' and m.role in ('owner', 'admin')
                 where n.type = 'content_reported' and n.town_hall_post_id = v_post5));
  perform pg_temp.probe_ok(v_probe, 'it reaches every platform admin',
    (select count(*) from public.notifications n join public.profiles p on p.id = n.user_id
      where p.is_admin and n.type = 'content_reported' and n.town_hall_post_id = v_post5) = v_padmins);
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'it is not in the owner''s list',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_post5));
  v_list := pg_temp.probe_call(u5, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'nor in its author''s list',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_post5));
  v_list := pg_temp.probe_call(v_admin, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'a platform admin reads C1''s list, without it: ' || v_list::text,
    coalesce(v_list ->> 'success', '') = 'true'
    and not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_post5));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post5, 'hide', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot moderate a report about an admin''s post: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post5, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the author cannot moderate a report about their own content: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(v_admin, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post5, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'nor can a platform admin through this function (admin_moderate_content is theirs): ' || j::text,
    pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the admin''s post is untouched and its report pending',
    (select hidden_at from public.town_hall_posts where id = v_post5) is null
    and (select status from public.reports where id = v_r_post5) = 'pending');

  -- (c) an admin reports a member's comment: the reporting admin is not told, the owner is
  j := pg_temp.probe_call(u5, format($q$public.submit_report(%L::uuid, %L::uuid, null, null, %L::uuid, null, null,
                                         'inappropriate_content', 'Probe comment report')$q$, u5, u7, v_comment));
  v_r_comment := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the comment report is filed: ' || j::text, v_r_comment is not null);
  perform pg_temp.probe_ok(v_probe, 'the reporting admin holds no new row; the owner holds one more',
    (select count(*) from public.notifications n
      where n.user_id = u5 and n.type = 'content_reported' and n.town_hall_post_id = v_post3) = 1
    and (select count(*) from public.notifications n
      where n.user_id = u4 and n.type = 'content_reported' and n.town_hall_post_id = v_post3) = 2);
  perform pg_temp.probe_ok(v_probe, 'the comment''s author is not told',
    not exists (select 1 from public.notifications n where n.user_id = u7 and n.type = 'content_reported'));

  -- (d) person reports (D27)
  j := pg_temp.probe_call(u7, format($q$public.submit_report(%L::uuid, %L::uuid, null, null, null, null, null,
                                         'harassment', 'Probe person report')$q$, u7, u3));
  v_r_person := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a person report between two C1-only members carries C1',
    (select community_id from public.reports where id = v_r_person) = c1);
  perform pg_temp.probe_ok(v_probe, 'the owner and the admin each hold one entity-less row for it, tagged C1, no source user',
    (select count(*) from public.notifications n
      where n.user_id in (u4, u5) and n.type = 'content_reported' and n.ride_id is null and n.favor_id is null
        and n.town_hall_post_id is null and n.source_user_id is null and n.community_id = c1) = 2);
  perform pg_temp.probe_ok(v_probe, 'the reported person holds none',
    not exists (select 1 from public.notifications n where n.user_id = u3 and n.type = 'content_reported'));
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, null, null, null, null,
                                         'harassment', 'Probe admin person report')$q$, u3, u5));
  v_r_person_admin := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a person report about an admin reaches no admin of C1 (the owner still has one entity-less row)',
    v_r_person_admin is not null
    and (select count(*) from public.notifications n
          where n.user_id = u4 and n.type = 'content_reported' and n.ride_id is null and n.favor_id is null
            and n.town_hall_post_id is null) = 1);

  -- (e) moderation by the owner on the member's post; the platform admins' queue is not changed
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', '   '));
  perform pg_temp.probe_ok(v_probe, 'hide without a reason is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u3, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', 'Probe'));
  perform pg_temp.probe_ok(v_probe, 'a plain member cannot moderate: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', 'Probe hide reason'));
  perform pg_temp.probe_ok(v_probe, 'the owner hides the post: ' || j::text, coalesce(j ->> 'success', '') = 'true');
  perform pg_temp.probe_ok(v_probe, 'the post is hidden by the owner with the reason',
    exists (select 1 from public.town_hall_posts
             where id = v_post3 and hidden_at is not null and hidden_by = u4 and hidden_reason = 'Probe hide reason'));
  perform pg_temp.probe_ok(v_probe, 'the report is action_taken for the community and still pending for the platform admins',
    exists (select 1 from public.reports
             where id = v_r_post3 and community_status = 'action_taken' and community_reviewed_at is not null
               and content_hidden and status = 'pending' and reviewed_by is null and reviewed_at is null));
  perform pg_temp.probe_ok(v_probe, 'one hide event acted by the owner',
    (select count(*) from public.content_moderation_events
      where target_type = 'town_hall_post' and target_id = v_post3 and action = 'hide' and acted_by = u4) = 1);
  perform pg_temp.probe_ok(v_probe, 'the author is told (content_hidden)',
    exists (select 1 from public.notifications where user_id = u3 and type = 'content_hidden' and town_hall_post_id = v_post3));
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s list reads action_taken, restorable, not platform-handled: ' || v_list::text,
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
             where (e ->> 'report_id')::uuid = v_r_post3 and e ->> 'status' = 'action_taken'
               and (e ->> 'can_restore')::boolean and not (e ->> 'platform_handled')::boolean));
  j := pg_temp.probe_run(v_admin, format($q$select coalesce(jsonb_agg(x.report_id), '[]'::jsonb)
                                            from public.admin_get_reports(%L::uuid, 'pending') x$q$, v_admin));
  perform pg_temp.probe_ok(v_probe, 'it is still in the platform admins'' pending queue', j @> to_jsonb(array[v_r_post3]));
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', 'Probe again'));
  perform pg_temp.probe_ok(v_probe, 'hiding hidden content is refused (no hidden_by overwrite): ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'already_hidden'
    and (select hidden_by from public.town_hall_posts where id = v_post3) = u4);
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'C1''s admin restores the owner''s hide: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select hidden_at from public.town_hall_posts where id = v_post3) is null
    and exists (select 1 from public.content_moderation_events
                 where target_id = v_post3 and action = 'restore' and acted_by = u5));

  -- (f) a person report: dismiss only, recorded for the community, still pending for the platform admins
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_person, 'hide', 'Probe'));
  perform pg_temp.probe_ok(v_probe, 'a person report cannot be hidden: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_person, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the admin dismisses it for the community: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and exists (select 1 from public.reports
                 where id = v_r_person and community_status = 'dismissed' and status = 'pending' and reviewed_by is null)
    and exists (select 1 from public.content_moderation_events
                 where report_id = v_r_person and action = 'dismiss' and acted_by = u5));
  v_list := pg_temp.probe_call(u4, format($q$public.get_community_reports(%L::uuid, 'dismissed')$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s Dismissed list holds it: ' || v_list::text,
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_person));
  v_list := pg_temp.probe_call(u4, format($q$public.get_community_reports(%L::uuid, 'pending')$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s Pending list does not',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_person));
  j := pg_temp.probe_run(v_admin, format($q$select coalesce(jsonb_agg(x.report_id), '[]'::jsonb)
                                            from public.admin_get_reports(%L::uuid, 'pending') x$q$, v_admin));
  perform pg_temp.probe_ok(v_probe, 'the platform admins'' pending queue still holds it', j @> to_jsonb(array[v_r_person]));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_person, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'a second dismissal is refused: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'already_closed');

  -- (g) a community report never reaches community admins
  j := pg_temp.probe_call(u3, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                         p_report_type => 'spam', p_description => 'Probe community report')$q$, c1));
  v_r_community := (select id from public.reports where reporter_id = u3 and reported_community_id = c1 order by created_at desc limit 1);
  perform pg_temp.probe_ok(v_probe, 'the community report exists', v_r_community is not null);
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_community, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot act on a report about the community: ' || j::text, pg_temp.probe_refused(j));
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'nor list it',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_community));

  -- (h) platform moderation wins: a platform admin's hide and review close the report to the community
  v_post11 := pg_temp.probe_post(3, u11, c1);
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe platform-handled report')$q$, u3, u11, v_post11));
  v_r_post11 := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the report on the member''s post is filed: ' || j::text, v_r_post11 is not null);
  j := pg_temp.probe_call(v_admin, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                          v_admin, v_r_post11, 'hide', 'Probe platform hide'));
  perform pg_temp.probe_ok(v_probe, 'a platform admin hides it through admin_moderate_content: ' || j::text,
    not pg_temp.probe_refused(j)
    and (select hidden_by from public.town_hall_posts where id = v_post11) = v_admin
    and (select status from public.reports where id = v_r_post11) = 'action_taken');
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s list reads it platform-handled and not restorable: ' || v_list::text,
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
             where (e ->> 'report_id')::uuid = v_r_post11 and e ->> 'status' = 'action_taken'
               and (e ->> 'platform_handled')::boolean and not (e ->> 'can_restore')::boolean));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post11, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot restore a platform admin''s hide: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_hidden'
    and (select hidden_by from public.town_hall_posts where id = v_post11) = v_admin);
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post11, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'nor dismiss the report a platform admin reviewed: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_handled');
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post11, 'hide', 'Probe'));
  perform pg_temp.probe_ok(v_probe, 'nor hide on it: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_handled');
  perform pg_temp.probe_ok(v_probe, 'the platform admin''s decision is intact',
    exists (select 1 from public.reports
             where id = v_r_post11 and status = 'action_taken' and reviewed_by = v_admin and community_status is null));

  -- (i) the 3-reporter auto-hide (hidden_by null) is restored only by platform admins
  v_post7b := pg_temp.probe_post(4, u7, c1);
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe auto-hide 1')$q$, u3, u7, v_post7b));
  j := pg_temp.probe_call(u11, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                          'spam', 'Probe auto-hide 2')$q$, u11, u7, v_post7b));
  j := pg_temp.probe_call(u5, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe auto-hide 3')$q$, u5, u7, v_post7b));
  v_r_auto := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'three distinct reporters auto-hide the post, hidden_by null: ' || j::text,
    v_r_auto is not null
    and exists (select 1 from public.town_hall_posts where id = v_post7b and hidden_at is not null and hidden_by is null)
    and exists (select 1 from public.content_moderation_events
                 where target_id = v_post7b and action = 'auto_hide' and acted_by is null));
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s list offers no restore for it',
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
             where (e ->> 'report_id')::uuid = v_r_auto and (e ->> 'content_hidden')::boolean
               and not (e ->> 'can_restore')::boolean));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_auto, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot undo the auto-hide: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_hidden'
    and (select hidden_at from public.town_hall_posts where id = v_post7b) is not null);
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_auto, 'hide', 'Probe takeover'));
  perform pg_temp.probe_ok(v_probe, 'nor take it over by hiding it again: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'already_hidden'
    and (select hidden_by from public.town_hall_posts where id = v_post7b) is null);
  j := pg_temp.probe_call(v_admin, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_auto, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'a platform admin may restore it here (admin_moderate_content gives them that already): ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select hidden_at from public.town_hall_posts where id = v_post7b) is null);

  -- (j) an archived community's reports are out of reach
  perform set_config('request.jwt.claims', '', true);
  update public.communities set archived_at = now() where id = c1;
  j := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'after archiving, the owner is refused: ' || j::text, pg_temp.probe_refused(j));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE community_moderation OK' as probe;


-- =============================================================================================================
-- admin_community_reports (Phase 3 carry-over, File A blocks 6-8, D-S1): admin_get_reports lists a community
-- report as target 'community' with the community's name; a platform admin dismisses it through
-- admin_moderate_content, which logs one content_moderation_events row with target_type 'community'; Hide on it
-- raises; a caller who is not a platform admin (here the community's own owner) is refused.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'admin_community_reports';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);
  c1 uuid := pg_temp.c(1);
  v_r uuid;
  v_rows jsonb;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  if not exists (select 1 from pg_catalog.pg_constraint
                  where conname = 'content_moderation_events_target_type_check'
                    and pg_catalog.pg_get_constraintdef(oid) like '%community%') then
    raise exception 'PROBE % FAILED: File A blocks 6-8 are not live (D-S1)', v_probe;
  end if;
  perform pg_temp.probe_world();

  j := pg_temp.probe_call(u3, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                         p_report_type => 'spam', p_description => 'Probe community report')$q$, c1));
  v_r := (select id from public.reports where reporter_id = u3 and reported_community_id = c1 order by created_at desc limit 1);
  perform pg_temp.probe_ok(v_probe, 'the community report exists: ' || j::text, v_r is not null);

  v_rows := pg_temp.probe_run(v_admin, format($q$select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                                                 from public.admin_get_reports(%L::uuid, 'pending') x
                                                where x.report_id = %L::uuid$q$, v_admin, v_r));
  perform pg_temp.probe_ok(v_probe, 'admin_get_reports lists it as a community target with the name as preview: ' || v_rows::text,
    jsonb_typeof(v_rows) = 'array' and jsonb_array_length(v_rows) = 1
    and v_rows -> 0 ->> 'target_type' = 'community'
    and v_rows -> 0 ->> 'content_preview' = 'Probe Community One'
    and (v_rows -> 0 ->> 'reporter_id')::uuid = u3);

  j := pg_temp.probe_call(v_admin, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                          v_admin, v_r, 'hide', 'Probe hide'));
  perform pg_temp.probe_ok(v_probe, 'Hide on a community report raises: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and (select status from public.reports where id = v_r) = 'pending');

  j := pg_temp.probe_call(u4, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                     u4, v_r, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the community''s owner, not a platform admin, is refused: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and (select status from public.reports where id = v_r) = 'pending');
  j := pg_temp.probe_run(u4, format($q$select coalesce(jsonb_agg(x.report_id), '[]'::jsonb)
                                       from public.admin_get_reports(%L::uuid, null) x$q$, u4));
  perform pg_temp.probe_ok(v_probe, 'and cannot list platform reports: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  j := pg_temp.probe_call(v_admin, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                          v_admin, v_r, 'dismiss', 'Probe dismissal'));
  perform pg_temp.probe_ok(v_probe, 'the platform admin dismisses it: ' || j::text,
    not pg_temp.probe_refused(j)
    and exists (select 1 from public.reports
                 where id = v_r and status = 'dismissed' and reviewed_by = v_admin and admin_notes = 'Probe dismissal'));
  perform pg_temp.probe_ok(v_probe, 'one dismiss event with target_type community and the community as target',
    (select count(*) from public.content_moderation_events
      where report_id = v_r and target_type = 'community' and target_id = c1
        and action = 'dismiss' and acted_by = v_admin) = 1);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE admin_community_reports OK' as probe;


-- =============================================================================================================
-- community_stats (Phase 3): get_community_stats and the three breakdowns read only the community's requests;
-- members, other communities and anon are refused; the null scope is platform admins only; the legacy admin_*
-- functions return the null scope's answer to a platform admin and refuse a community owner.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'community_stats';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);
  j jsonb;
  k jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  -- r(1): completed in C1; r(2): open in C1
  update public.rides set estimated_cost = 12.50 where id = pg_temp.r(1);

  j := pg_temp.probe_call(u4, format('public.get_community_stats(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner reads C1''s figures: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (j ->> 'fulfilled_count')::int = 1 and (j ->> 'active_rides_count')::int = 1
    and (j ->> 'total_savings')::numeric = 12.50);
  j := pg_temp.probe_call(u3, format('public.get_community_stats(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'a plain member is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u12, format('public.get_community_stats(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'another community''s owner is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u4, 'public.get_community_stats(null)');
  perform pg_temp.probe_ok(v_probe, 'the null (every community) scope is refused to a community owner: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(null, format('public.get_community_stats(%L::uuid)', c1), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call it: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  j := pg_temp.probe_call(u4, format('public.get_community_stats_active_requests(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'active requests: C1''s open ride, and nothing from another community: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and exists (select 1 from jsonb_array_elements(j -> 'rows') e where (e ->> 'id')::uuid = pg_temp.r(2))
    and not exists (select 1 from jsonb_array_elements(j -> 'rows') e
                     where (e ->> 'id')::uuid not in (select id from public.rides where community_id = c1
                                                      union all select id from public.favors where community_id = c1)));
  j := pg_temp.probe_call(u4, format($q$public.get_community_stats_fulfilled(%L::uuid, 'month', 12)$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'fulfilled breakdown counts C1''s one completed request: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select coalesce(sum((e ->> 'total_count')::int), 0) from jsonb_array_elements(j -> 'rows') e) = 1);
  j := pg_temp.probe_call(u4, format($q$public.get_community_stats_savings(%L::uuid, 'month', 12)$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'savings breakdown sums C1''s estimate: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select coalesce(sum((e ->> 'total_savings')::numeric), 0) from jsonb_array_elements(j -> 'rows') e) = 12.50);

  -- the legacy wrappers
  j := pg_temp.probe_call(v_admin, 'public.get_community_stats(null)');
  k := pg_temp.probe_call(v_admin, 'public.admin_dashboard_stats()');
  perform pg_temp.probe_ok(v_probe, format('admin_dashboard_stats equals the every-community scope: %s vs %s', k, j), k = (j - 'success'));
  j := pg_temp.probe_call(v_admin, $q$public.get_community_stats_fulfilled(null, 'week', 12)$q$);
  k := pg_temp.probe_call(v_admin, $q$public.admin_stats_fulfilled('week', 12)$q$);
  perform pg_temp.probe_ok(v_probe, 'admin_stats_fulfilled equals the every-community rows', k = j -> 'rows');
  j := pg_temp.probe_call(v_admin, $q$public.get_community_stats_savings(null, 'year', 12)$q$);
  k := pg_temp.probe_call(v_admin, $q$public.admin_stats_savings('year', 12)$q$);
  perform pg_temp.probe_ok(v_probe, 'admin_stats_savings equals the every-community rows', k = j -> 'rows');
  j := pg_temp.probe_run(v_admin, $q$select coalesce(jsonb_agg(e order by e ->> 'id'), '[]'::jsonb)
                                     from jsonb_array_elements(public.get_community_stats_active_requests(null) -> 'rows') e$q$);
  k := pg_temp.probe_run(v_admin, $q$select coalesce(jsonb_agg(e order by e ->> 'id'), '[]'::jsonb)
                                     from jsonb_array_elements(public.admin_stats_active_rides()::jsonb) e$q$);
  perform pg_temp.probe_ok(v_probe, 'admin_stats_active_rides equals the every-community rows (as a set)', k = j);
  j := pg_temp.probe_call(u4, 'public.admin_dashboard_stats()');
  perform pg_temp.probe_ok(v_probe, 'a community owner who is not a platform admin is refused by the legacy function: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE community_stats OK' as probe;


-- =============================================================================================================
-- broadcast_cap (Phase 3, D14): announcement-typed rows a plain member writes do not count; a platform admin's
-- fourth announcement within 24 hours in one community is refused with P0001, as a community admin's already was;
-- the installed admin build's wrapper (default community) is capped the same way.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'broadcast_cap';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);
  c1 uuid := pg_temp.c(1);
  d uuid;
  v_existing int;
  n int;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  d := public.default_community_id();

  -- (a) three rows typed 'announcement' by a plain member of C1: what town_hall_posts_insert_active_user lets an
  --     active member write (it does not restrict type). Written as the table owner so the case does not depend on
  --     the probe account's approval flags; the cap must not count them.
  perform set_config('request.jwt.claims', '', true);
  insert into public.town_hall_posts (user_id, title, content, type, community_id)
  select u3, 'Probe member announcement ' || g, 'communities probe', 'announcement', c1
    from generate_series(1, 3) g;

  for n in 1..3 loop
    j := pg_temp.probe_call(v_admin, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                            c1, 'Probe announcement ' || n, 'communities probe'));
    perform pg_temp.probe_ok(v_probe, format('the platform admin''s announcement %s in C1 is sent: %s', n, j), not pg_temp.probe_refused(j));
  end loop;
  j := pg_temp.probe_call(v_admin, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                          c1, 'Probe announcement 4', 'communities probe'));
  perform pg_temp.probe_ok(v_probe, 'the platform admin''s fourth in 24 hours is refused with P0001: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = 'P0001');
  j := pg_temp.probe_call(u4, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                     c1, 'Probe owner announcement', 'communities probe'));
  perform pg_temp.probe_ok(v_probe, 'the owner is refused too (the cap is per community): ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = 'P0001');
  perform pg_temp.probe_ok(v_probe, 'C1 holds six announcement rows, three of them by the platform admin',
    (select count(*) from public.town_hall_posts where community_id = c1 and type = 'announcement') = 6
    and (select count(*) from public.town_hall_posts
          where community_id = c1 and type = 'announcement' and user_id = v_admin) = 3);

  if has_function_privilege('authenticated', 'public.send_broadcast_notifications(text, text, text, boolean)', 'execute') then
  -- the installed admin build's wrapper posts into the default community
  -- the same counting rule as the function: announcements by platform admins and by the community's staff
  v_existing := (select count(*)::int from public.town_hall_posts t
                   left join public.profiles a on a.id = t.user_id
                  where t.community_id = d and t.type = 'announcement' and t.created_at > now() - interval '24 hours'
                    and (coalesce(a.is_admin, false) or public.is_community_staff(d, t.user_id)));
  for n in 1..greatest(3 - v_existing, 0) loop
    j := pg_temp.probe_call(v_admin, format($q$public.send_broadcast_notifications(%L, %L, 'broadcast', false)$q$,
                                            'Probe wrapper ' || n, 'communities probe'));
    perform pg_temp.probe_ok(v_probe, format('wrapper announcement %s is sent: %s', n, j), not pg_temp.probe_refused(j));
  end loop;
  j := pg_temp.probe_call(v_admin, $q$public.send_broadcast_notifications('Probe wrapper over', 'communities probe', 'broadcast', false)$q$);
  perform pg_temp.probe_ok(v_probe, 'the wrapper refuses the platform admin once the default community has three today: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = 'P0001');
  else
    -- File B block 7 (20261019_0060, D-S3) closed the installed admin build's wrapper to clients
    j := pg_temp.probe_call(v_admin, $q$public.send_broadcast_notifications('Probe wrapper closed', 'communities probe', 'broadcast', false)$q$);
    perform pg_temp.probe_ok(v_probe, 'the wrapper is closed to clients after File B block 7: ' || j::text,
      coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');
  end if;

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE broadcast_cap OK' as probe;


-- =============================================================================================================
-- posts_delete_policy (Phase 3, spec §3.4)   ** SQL editor (owner): this block holds DELETE statements, which
-- the MCP's permission layer declines. Paste PARAMETERS, HELPERS and this block. **
-- A community admin may remove a member's post in their community, not an owner's post; a plain member may not
-- remove another member's post; the owner of another community may not; an author may remove their own.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'posts_delete_policy';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);
  v_p3 uuid;  v_p4 uuid;  v_p7 uuid;  v_p7b uuid;
  v_sql constant text := $q$with x as (delete from public.town_hall_posts where id = %L returning 1)
                            select to_jsonb(count(*)) from x$q$;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  v_p3  := pg_temp.probe_post(11, u3, c1);
  v_p4  := pg_temp.probe_post(12, u4, c1);   -- the owner's
  v_p7  := pg_temp.probe_post(13, u7, c1);
  v_p7b := pg_temp.probe_post(14, u7, c1);

  j := pg_temp.probe_run(u3, format(v_sql, v_p7));
  perform pg_temp.probe_ok(v_probe, 'a plain member cannot remove another member''s post: ' || j::text, j = '0'::jsonb);
  j := pg_temp.probe_run(u12, format(v_sql, v_p7b));
  perform pg_temp.probe_ok(v_probe, 'another community''s owner cannot: ' || j::text, j = '0'::jsonb);
  j := pg_temp.probe_run(u5, format(v_sql, v_p7));
  perform pg_temp.probe_ok(v_probe, 'C1''s admin removes a member''s post: ' || j::text, j = '1'::jsonb);
  j := pg_temp.probe_run(u5, format(v_sql, v_p4));
  perform pg_temp.probe_ok(v_probe, 'C1''s admin cannot remove the owner''s post: ' || j::text, j = '0'::jsonb);
  j := pg_temp.probe_run(u3, format(v_sql, v_p3));
  perform pg_temp.probe_ok(v_probe, 'an author removes their own post: ' || j::text, j = '1'::jsonb);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE posts_delete_policy OK' as probe;

-- =============================================================================================================
-- phase4_registry (Phase 4, 20261019_0001): the CHECK accepts membership_update and still refuses an unknown
-- type; should_notify_user answers true for it; create_community stores a known p_timezone, falls back to the
-- column default for an unknown or missing one, and the Phase 2 / 3 three-argument call still resolves; the
-- renamed old overload (create_community_pre_p4, which existed between block 3 and the owner's block 4 on
-- 2026-10-19; the check is skipped once it is gone) is callable by nobody; anon is refused.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'phase4_registry';
  u3 uuid := pg_temp.u(3);  u6 uuid := pg_temp.u(6);  u13 uuid := pg_temp.u(13);  u16 uuid := pg_temp.u(16);
  v_default text;
  v_id uuid;
  j jsonb;
begin
  perform pg_temp.probe_require_phase4(v_probe, 'registry');
  perform pg_temp.probe_world();
  v_default := (select replace(replace(column_default, '''', ''), '::text', '')
                  from information_schema.columns
                 where table_schema = 'public' and table_name = 'communities' and column_name = 'timezone');

  -- (a) the CHECK
  perform set_config('request.jwt.claims', '', true);
  insert into public.notifications (user_id, type, title) values (u3, 'membership_update', 'Probe membership update');
  perform pg_temp.probe_ok(v_probe, 'a membership_update row is accepted',
    exists (select 1 from public.notifications where user_id = u3 and type = 'membership_update'));
  begin
    insert into public.notifications (user_id, type, title) values (u3, 'probe_unknown_type', 'Probe');
    raise exception 'PROBE % FAILED: an unknown notification type was accepted', v_probe;
  exception when check_violation then
    null;
  end;

  -- (b) should_notify_user
  perform pg_temp.probe_ok(v_probe, 'should_notify_user(member, membership_update) is true',
    public.should_notify_user(u3, 'membership_update'));
  perform pg_temp.probe_ok(v_probe, 'an unknown type is still false',
    not public.should_notify_user(u3, 'probe_unknown_type'));

  -- (c) a known zone is stored
  j := pg_temp.probe_call(u6, format('public.create_community(%L, %L, %L, %L)',
                                     'Probe Zone One', 'communities probe', 'approve', 'America/New_York'));
  perform pg_temp.probe_ok(v_probe, 'create_community with a zone succeeds: ' || j::text, not pg_temp.probe_refused(j));
  v_id := (j ->> 'community_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the zone is stored',
    (select timezone from public.communities where id = v_id) = 'America/New_York');

  -- (d) an unknown zone falls back, by name (the PostgREST form, description omitted)
  j := pg_temp.probe_call(u13, format('public.create_community(p_name => %L, p_timezone => %L)',
                                      'Probe Zone Two', 'Not/AZone'));
  perform pg_temp.probe_ok(v_probe, 'an unknown zone is not a refusal: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'an unknown zone leaves the column default ' || coalesce(v_default, '?'),
    (select timezone from public.communities where id = (j ->> 'community_id')::uuid) = v_default);

  -- (e) the Phase 2 / 3 call: three arguments, no zone
  j := pg_temp.probe_call(u16, format('public.create_community(%L, %L, %L)', 'Probe Zone Three', 'communities probe', 'invite'));
  perform pg_temp.probe_ok(v_probe, 'the three-argument call resolves: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and keeps the column default',
    (select timezone from public.communities where id = (j ->> 'community_id')::uuid) = v_default);

  -- (f) one overload
  perform pg_temp.probe_ok(v_probe, 'exactly one create_community',
    (select count(*) from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'create_community') = 1);

  if to_regprocedure('public.create_community_pre_p4(text, text, text)') is not null then
    j := pg_temp.probe_call(u16, format('public.create_community_pre_p4(%L, %L, %L)', 'Probe Old Overload', 'communities probe', 'invite'));
    perform pg_temp.probe_ok(v_probe, 'the renamed three-argument overload is not callable by authenticated: ' || j::text,
      coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');
  end if;
  j := pg_temp.probe_call(null, format('public.create_community(%L, %L, %L)', 'Probe Anon', 'communities probe', 'invite'), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call create_community: ' || j::text, coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');
  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE phase4_registry OK' as probe;


-- =============================================================================================================
-- broadcast_push (Phase 4, 20261019_0002, GATED: dry run only until the A5 gate): every unmuted active member but
-- the sender gets one immediate push of the announcement's type with community_id, town_hall_post_id and
-- notification_id, also with Town Hall notifications off; a muted member gets nothing; the announcement produces
-- no town_hall_post row or push; a member's own 'announcement'-typed post is still notified as a Town Hall post.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'broadcast_push';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u11 uuid := pg_temp.u(11);
  c1 uuid := pg_temp.c(1);
  v_post uuid;
  v_member_post uuid;
  j jsonb;
begin
  perform pg_temp.probe_require_phase4(v_probe, 'broadcast');
  perform pg_temp.probe_world();
  perform set_config('request.jwt.claims', '', true);
  update public.profiles set notify_town_hall = true  where id in (u3, u5);
  update public.profiles set notify_town_hall = false where id = u7;      -- Town Hall off: still gets the push
  update public.community_members set notifications_muted = true
   where community_id = c1 and user_id = u11;                             -- muted: nothing

  -- C1's active members: owner u4 (sender), admin u5, members u3 u7 u11 (muted); u9 is pending.
  j := pg_temp.probe_call(u4, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                     c1, 'Probe broadcast', 'communities probe broadcast'));
  perform pg_temp.probe_ok(v_probe, 'the owner''s announcement reaches three members: ' || j::text, j = '3'::jsonb);
  v_post := (select id from public.town_hall_posts
              where community_id = c1 and type = 'announcement' and title = 'Probe broadcast');

  perform pg_temp.probe_ok(v_probe, 'one broadcast push each for u3, u5 and u7, none for the sender or the muted member',
    (select array_agg(q.recipient_user_id order by q.recipient_user_id)
       from public.notification_queue q
      where q.notification_type = 'broadcast'
        and q.payload -> 'data' ->> 'town_hall_post_id' = v_post::text)
    = (select array_agg(x order by x) from unnest(array[u3, u5, u7]) x));
  perform pg_temp.probe_ok(v_probe, 'each push carries the community and its own bell row, and is not batched',
    not exists (select 1 from public.notification_queue q
                 where q.notification_type = 'broadcast'
                   and q.payload -> 'data' ->> 'town_hall_post_id' = v_post::text
                   and (q.batch_key is not null
                        or q.payload -> 'data' ->> 'community_id' is distinct from c1::text
                        or not exists (select 1 from public.notifications n
                                        where n.id::text = q.payload -> 'data' ->> 'notification_id'
                                          and n.user_id = q.recipient_user_id and n.type = 'broadcast'))));
  perform pg_temp.probe_ok(v_probe, 'the push title and body are the announcement''s',
    not exists (select 1 from public.notification_queue q
                 where q.notification_type = 'broadcast'
                   and q.payload -> 'data' ->> 'town_hall_post_id' = v_post::text
                   and (q.payload ->> 'title' <> 'Probe broadcast' or q.payload ->> 'body' <> 'communities probe broadcast')));
  perform pg_temp.probe_ok(v_probe, 'the announcement makes no Town Hall row or push (the side door is closed)',
    not exists (select 1 from public.notifications where type = 'town_hall_post' and town_hall_post_id = v_post)
    and not exists (select 1 from public.notification_queue
                     where notification_type = 'town_hall_post'
                       and payload -> 'data' ->> 'town_hall_post_id' = v_post::text));
  perform pg_temp.probe_ok(v_probe, 'the setting is reset after the call',
    coalesce(current_setting('naars.broadcast_post', true), '') = '');

  -- a member's own 'announcement'-typed post (20261018_0002 D-S8) is still a Town Hall post
  insert into public.town_hall_posts (user_id, title, content, type, community_id)
  values (u3, 'Probe member announcement', 'communities probe', 'announcement', c1)
  returning id into v_member_post;
  perform pg_temp.probe_ok(v_probe, 'a member''s announcement-typed post still notifies Town Hall subscribers',
    exists (select 1 from public.notifications where type = 'town_hall_post' and town_hall_post_id = v_member_post and user_id = u5));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE broadcast_push OK' as probe;


-- =============================================================================================================
-- membership_update_producers (Phase 4, 20261019_0003, GATED: dry run only until the A5 gate): approval into a
-- further community writes membership_update (approved) and no user_approved; a first approval writes no
-- membership_update; a hand-over tells the new owner (owner) and not the old one; being made a co-owner tells the
-- person; a demotion is silent; a readmit into a further community writes membership_update (approved) and no
-- user_approved.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'membership_update_producers';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);
  u9 uuid := pg_temp.u(9);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  j jsonb;
begin
  perform pg_temp.probe_require_phase4(v_probe, 'membership');
  perform pg_temp.probe_world();

  -- (a) approval into a further community: u3 is active in C1 and asks C2 (owner u12)
  perform pg_temp.probe_member(c2, u3, 'member', 'pending', 1);
  j := pg_temp.probe_call(u12, format('public.approve_community_member(%L::uuid, %L::uuid)', c2, u3));
  perform pg_temp.probe_ok(v_probe, 'approve into C2 succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'u3 gets one membership_update for C2 and no user_approved for C2',
    (select count(*) from public.notifications where user_id = u3 and type = 'membership_update' and community_id = c2) = 1
    and not exists (select 1 from public.notifications where user_id = u3 and type = 'user_approved' and community_id = c2));
  perform pg_temp.probe_ok(v_probe, 'its push says approved and names C2',
    exists (select 1 from public.notification_queue
             where recipient_user_id = u3 and notification_type = 'membership_update'
               and payload -> 'data' ->> 'membership_event' = 'approved'
               and payload -> 'data' ->> 'community_id' = c2::text));

  -- (b) a first approval: u9 has no other active membership
  j := pg_temp.probe_call(u4, format('public.approve_community_member(%L::uuid, %L::uuid)', c1, u9));
  perform pg_temp.probe_ok(v_probe, 'approve u9 into C1 succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'a first approval writes no membership_update',
    not exists (select 1 from public.notifications where user_id = u9 and type = 'membership_update'));

  -- (c) hand-over: owner u4 → admin u5
  j := pg_temp.probe_call(u4, format('public.transfer_community_ownership(%L::uuid, %L::uuid)', c1, u5));
  perform pg_temp.probe_ok(v_probe, 'the hand-over succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the new owner is told (owner), the old owner is not',
    exists (select 1 from public.notification_queue
             where recipient_user_id = u5 and notification_type = 'membership_update'
               and payload -> 'data' ->> 'membership_event' = 'owner'
               and payload -> 'data' ->> 'community_id' = c1::text)
    and (select count(*) from public.notifications where user_id = u5 and type = 'membership_update' and community_id = c1) = 1
    and not exists (select 1 from public.notifications where user_id = u4 and type = 'membership_update'));

  -- (d) co-owner: the new owner u5 makes u7 an owner, then a member again
  j := pg_temp.probe_call(u5, format('public.set_member_role(%L::uuid, %L::uuid, %L)', c1, u7, 'owner'));
  perform pg_temp.probe_ok(v_probe, 'u7 made an owner: ' || j::text, not pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u5, format('public.set_member_role(%L::uuid, %L::uuid, %L)', c1, u7, 'member'));
  perform pg_temp.probe_ok(v_probe, 'u7 made a member again: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'u7 got exactly one membership_update (the promotion, not the demotion)',
    (select count(*) from public.notifications where user_id = u7 and type = 'membership_update' and community_id = c1) = 1);

  -- (e) readmit into a further community: u7 (active in C1) was removed from C2; C2's owner u12 lets them back in
  perform pg_temp.probe_member(c2, u7, 'member', 'removed', 2);
  j := pg_temp.probe_call(u12, format('public.readmit_community_member(%L::uuid, %L::uuid)', c2, u7));
  perform pg_temp.probe_ok(v_probe, 'readmit u7 into C2 succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'u7 gets one membership_update (approved) for C2 and no user_approved for C2',
    (select count(*) from public.notifications where user_id = u7 and type = 'membership_update' and community_id = c2) = 1
    and not exists (select 1 from public.notifications where user_id = u7 and type = 'user_approved' and community_id = c2)
    and exists (select 1 from public.notification_queue
                 where recipient_user_id = u7 and notification_type = 'membership_update'
                   and payload -> 'data' ->> 'membership_event' = 'approved'
                   and payload -> 'data' ->> 'community_id' = c2::text));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE membership_update_producers OK' as probe;


-- =============================================================================================================
-- geocoding_lookup (Phase 5a, 20261019_0050): an active member writes and reads one multiplier through the two
-- definer functions and gets back only a number; an unapproved or banned account gets null and cannot write;
-- anon cannot call either; malformed keys, keys that do not match the coordinates and out-of-range multipliers
-- are refused; a row older than 24 hours is a miss and a new write refreshes it; no placemark is stored.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'geocoding_lookup';
  v_member uuid := pg_temp.probe_subject('member');
  u1 uuid := pg_temp.u(1);  u2 uuid := pg_temp.u(2);
  v_key constant text := '89.987_-179.987';     -- no real place: the edge of the map
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'a');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'the probe key is unused', not exists (select 1 from public.geocoding_cache where location_key = v_key));

  j := pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.2)', v_key));
  perform pg_temp.probe_ok(v_probe, 'an active member writes a multiplier: ' || j::text, j = 'true'::jsonb);
  perform pg_temp.probe_ok(v_probe, 'the row holds the multiplier, no placemark, a fresh updated_at',
    exists (select 1 from public.geocoding_cache where location_key = v_key and multiplier = 1.2
              and placemark_data is null and updated_at > now() - interval '1 minute'));

  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'the member reads back only a number: ' || j::text,
    jsonb_typeof(j) = 'number' and (j #>> '{}')::numeric = 1.2);

  j := pg_temp.probe_call(u1, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'an unapproved account reads null: ' || j::text, j = 'null'::jsonb);
  j := pg_temp.probe_call(u2, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'a banned account reads null: ' || j::text, j = 'null'::jsonb);
  j := pg_temp.probe_call(u1, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.5)', v_key));
  perform pg_temp.probe_ok(v_probe, 'an unapproved account cannot write: ' || j::text,
    j = 'false'::jsonb and (select multiplier from public.geocoding_cache where location_key = v_key) = 1.2);

  j := pg_temp.probe_call(null, format('public.get_geocoding_multiplier(%L)', v_key), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call the lookup: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_call(null, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.1)', v_key), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call the write: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');

  foreach j in array array[
    pg_temp.probe_call(v_member, $q$public.put_geocoding_multiplier('1.2_3.4', 1.2, 3.4, 1.1)$q$),               -- malformed key
    pg_temp.probe_call(v_member, $q$public.put_geocoding_multiplier('x; drop', 1.2, 3.4, 1.1)$q$),               -- malformed key
    pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 10.0, 10.0, 1.1)', v_key)),     -- key does not match
    pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 3.0)', v_key)),  -- out of range
    pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 0.5)', v_key))]  -- out of range
  loop
    perform pg_temp.probe_ok(v_probe, 'a malformed or out-of-range write is refused: ' || j::text, j = 'false'::jsonb);
  end loop;
  perform pg_temp.probe_ok(v_probe, 'and the row is unchanged',
    (select multiplier from public.geocoding_cache where location_key = v_key) = 1.2);
  j := pg_temp.probe_call(v_member, $q$public.get_geocoding_multiplier('not a key')$q$);
  perform pg_temp.probe_ok(v_probe, 'a malformed lookup answers null: ' || j::text, j = 'null'::jsonb);

  perform set_config('request.jwt.claims', '', true);
  update public.geocoding_cache set created_at = now() - interval '25 hours', updated_at = now() - interval '25 hours'
   where location_key = v_key;
  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'a row older than 24 hours is a miss: ' || j::text, j = 'null'::jsonb);
  j := pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.1)', v_key));
  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'a new write refreshes it: ' || j::text, (j #>> '{}')::numeric = 1.1);

  perform pg_temp.probe_ok(v_probe, 'both functions are SECURITY DEFINER with an empty search_path and not callable by anon',
    (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
       from pg_catalog.pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('get_geocoding_multiplier', 'put_geocoding_multiplier'))
    and not has_function_privilege('anon', 'public.get_geocoding_multiplier(text)', 'execute')
    and not has_function_privilege('anon', 'public.put_geocoding_multiplier(text, numeric, numeric, numeric)', 'execute'));

  if has_table_privilege('authenticated', 'public.geocoding_cache', 'select') then
    -- before 20261019_0062 the installed build's direct read still works
    perform pg_temp.probe_ok(v_probe, 'before File D the direct table read still works for a member',
      pg_temp.probe_count(v_member, format('select 1 from public.geocoding_cache where location_key = %L', v_key)) = 1);
  end if;

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE geocoding_lookup OK' as probe;


-- =============================================================================================================
-- legacy_retired (Phase 5b, 20261019_0060): the bridges are gone; the installed build's application UPDATE and
-- approve raise and change nothing, for platform admins too; a member's own flag write raises; the RPC approve
-- still works; admin_reject_pending_user is closed to clients; an approved account with no membership row cannot
-- post while a member still posts without naming a community; answers given to the default community stay on
-- the membership row and are not copied into profiles.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'legacy_retired';
  d uuid;
  v_admin  uuid := pg_temp.probe_subject('platform_admin');
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u6 uuid := pg_temp.u(6);  u8 uuid := pg_temp.u(8);
  u10 uuid := pg_temp.u(10);  u13 uuid := pg_temp.u(13);  u15 uuid := pg_temp.u(15);
  v_code text;
  v_ride uuid;
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'bridges');
  perform pg_temp.probe_world();
  d := public.default_community_id();

  perform pg_temp.probe_ok(v_probe, 'the bridge functions are gone',
    not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace
                 and proname in ('legacy_application_to_membership', 'sync_legacy_approval_to_membership')));
  perform pg_temp.probe_ok(v_probe, 'the four edited bodies are the expected ones',
    (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.fill_request_community()'::regprocedure) = '9d4cfb03912a7c4a874cffae239ee605'
    and (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.redeem_community_invite(text, text, text)'::regprocedure) = '2ec0702dc3a4d400ca2599d0ebb15693'
    and (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.request_to_join_community(uuid, text, text)'::regprocedure) = 'af9a2f5c560d2d74f35ab979e2f3856c'
    and (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.protect_admin_fields()'::regprocedure) = 'd963a013278b5ace77565b8397683bf2');

  -- the installed build's application form
  j := pg_temp.probe_run(u10, format($q$with x as (update public.profiles
        set heard_about = 'Probe heard', join_reason = 'Probe reason', application_complete = true, application_submitted_at = now()
        where id = %L returning 1) select to_jsonb(count(*)) from x$q$, u10));
  perform pg_temp.probe_ok(v_probe, 'the old application UPDATE raises 42501: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  perform pg_temp.probe_ok(v_probe, 'and creates no membership; the flag stays false',
    not exists (select 1 from public.community_members where user_id = u10)
    and not (select application_complete from public.profiles where id = u10));

  j := pg_temp.probe_run(u3, format($q$with x as (update public.profiles set application_complete = false where id = %L returning 1)
                                     select to_jsonb(count(*)) from x$q$, u3));
  perform pg_temp.probe_ok(v_probe, 'a member''s own application_complete write raises: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  -- the installed admin build's approve
  j := pg_temp.probe_run(v_admin, format($q$with x as (update public.profiles set approved = true where id = %L returning 1)
                                          select to_jsonb(count(*)) from x$q$, u8));
  perform pg_temp.probe_ok(v_probe, 'a platform admin''s direct approve raises 42501: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  perform pg_temp.probe_ok(v_probe, 'and the applicant is still pending and not approved',
    exists (select 1 from public.community_members where community_id = d and user_id = u8 and status = 'pending')
    and not (select approved from public.profiles where id = u8));

  j := pg_temp.probe_call(v_admin, format('public.approve_community_member(%L::uuid, %L::uuid)', d, u8));
  perform pg_temp.probe_ok(v_probe, 'approve_community_member still works: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the mirror approves and one welcome is sent',
    exists (select 1 from public.community_members where community_id = d and user_id = u8 and status = 'active')
    and (select approved from public.profiles where id = u8)
    and (select count(*) from public.notifications where user_id = u8 and type = 'user_approved') = 1);

  j := pg_temp.probe_call(v_admin, format('public.admin_reject_pending_user(%L::uuid)', u15));
  perform pg_temp.probe_ok(v_probe, 'admin_reject_pending_user is closed to clients: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  perform pg_temp.probe_ok(v_probe, 'and the applicant and their account remain',
    exists (select 1 from public.profiles where id = u15)
    and exists (select 1 from public.community_members where community_id = d and user_id = u15 and status = 'pending'));

  -- no default fallback: an approved account with no membership row (a maintenance write, no JWT). The insert
  -- runs as the table owner so RLS cannot refuse it first: only the fill trigger decides (before File B it
  -- would have filled the default community).
  perform set_config('request.jwt.claims', '', true);
  update public.profiles set approved = true where id = u13;
  j := pg_temp.probe_run(null, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination)
       values (%L, current_date + 1, '10:00', 'Probe pickup', 'Probe destination') returning to_jsonb(community_id)$q$, u13), 'owner');
  perform pg_temp.probe_ok(v_probe, 'the fill trigger no longer places such an account in the default community: ' || j::text,
    pg_temp.probe_refused(j) and coalesce(j ->> 'error', '') like '%Choose a community%');
  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination)
       values (%L, current_date + 1, '10:00', 'Probe pickup', 'Probe destination') returning to_jsonb(id)$q$, v_member));
  perform pg_temp.probe_ok(v_probe, 'a member still posts without naming a community: ' || j::text, not pg_temp.probe_refused(j));
  v_ride := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'into one of their live communities',
    (select community_id from public.rides where id = v_ride) = any (pg_temp.probe_live_communities(v_member)));

  -- answers stay on the membership row
  j := pg_temp.probe_call(u10, format('public.request_to_join_community(%L::uuid, %L, %L)', d, 'Probe heard', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'asking to join the default community works: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the answers are on the membership row and not on the profile',
    exists (select 1 from public.community_members where community_id = d and user_id = u10 and heard_about = 'Probe heard')
    and (select heard_about is null and join_reason is null from public.profiles where id = u10));

  j := pg_temp.probe_call(v_admin, format($q$public.create_community_invite(%L::uuid, 5, now() + interval '1 day')$q$, d));
  v_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'a platform admin makes a default-community code: ' || j::text, v_code is not null);
  j := pg_temp.probe_call(u6, format('public.redeem_community_invite(%L, %L, %L)', v_code, 'Probe heard 6', 'Probe reason 6'));
  perform pg_temp.probe_ok(v_probe, 'redeeming it works: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and copies nothing into the profile',
    exists (select 1 from public.community_members where community_id = d and user_id = u6 and heard_about = 'Probe heard 6')
    and (select heard_about is null and join_reason is null from public.profiles where id = u6));

  if not has_function_privilege('authenticated', 'public.send_broadcast_notifications(text, text, text, boolean)', 'execute') then
    perform pg_temp.probe_ok(v_probe, 'block 7 applied: the legacy leaderboards are closed too',
      not has_function_privilege('authenticated', 'public.get_leaderboard(text, integer)', 'execute')
      and not has_function_privilege('authenticated', 'public.get_leaderboard(date, date)', 'execute'));
  end if;

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE legacy_retired OK' as probe;


-- =============================================================================================================
-- invite_codes_dropped (Phase 5b, 20261019_0061): the table and its four functions are gone, delete_user_account is
-- the expected body and still deletes an account, and no public function names the table.
-- Run account_deletion and short after it as well.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'invite_codes_dropped';
  u1 uuid := pg_temp.u(1);
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'invite_codes');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'the four invite-code functions are gone',
    not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace
                 and proname in ('validate_invite_code', 'mark_invite_code_used', 'guard_invite_code_client_update', 'handle_invite_code_used')));
  perform pg_temp.probe_ok(v_probe, 'no public function names invite_codes',
    not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and position('invite_codes' in prosrc) > 0));
  perform pg_temp.probe_ok(v_probe, 'delete_user_account is the expected body',
    (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.delete_user_account(uuid)'::regprocedure) = 'bd886e739d25dbe7497ff6b21c5aa248');
  j := pg_temp.probe_call(u1, format('public.delete_user_account(%L::uuid)', u1));
  perform pg_temp.probe_ok(v_probe, 'an account still deletes itself: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and is gone from profiles and auth.users',
    not exists (select 1 from public.profiles where id = u1) and not exists (select 1 from auth.users where id = u1));
  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE invite_codes_dropped OK' as probe;


-- =============================================================================================================
-- geocoding_revoked (Phase 5b, 20261019_0062): no client role can read or write geocoding_cache directly; the two
-- definer functions still work for an active member.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'geocoding_revoked';
  v_member uuid := pg_temp.probe_subject('member');
  v_key constant text := '89.986_-179.986';
  v_priv text;
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'geocoding');
  foreach v_priv in array array['select', 'insert', 'update', 'delete'] loop
    perform pg_temp.probe_ok(v_probe, format('no %s privilege for anon or authenticated', v_priv),
      not has_table_privilege('anon', 'public.geocoding_cache', v_priv)
      and not has_table_privilege('authenticated', 'public.geocoding_cache', v_priv));
  end loop;
  j := pg_temp.probe_run(v_member, 'select to_jsonb(count(*)) from public.geocoding_cache');
  perform pg_temp.probe_ok(v_probe, 'a member''s direct read raises 42501: ' || j::text, coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_run(null, 'select to_jsonb(count(*)) from public.geocoding_cache', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon''s direct read raises 42501: ' || j::text, coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.geocoding_cache (latitude, longitude, location_key, multiplier) values (89.986, -179.986, %L, 1.5)
       returning to_jsonb(id)$q$, v_key));
  perform pg_temp.probe_ok(v_probe, 'a member''s direct write raises: ' || j::text, coalesce(j ->> 'raised', '') = 'true');
  j := pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.986, -179.986, 1.2)', v_key));
  perform pg_temp.probe_ok(v_probe, 'the definer write still works: ' || j::text, j = 'true'::jsonb);
  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'the definer lookup still works: ' || j::text, (j #>> '{}')::numeric = 1.2);
  perform pg_temp.probe_ok(v_probe, 'block 2: no placemark data is left',
    not exists (select 1 from public.geocoding_cache where placemark_data is not null));
  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE geocoding_revoked OK' as probe;


-- =============================================================================================================
-- storage_private (Phase 5b, 20261019_0063): the four buckets are private and avatars public; a message or group
-- photo is readable by the thread's participants and its uploader only; a Town Hall photo by whoever can read a
-- post that shows it (guests only for public communities); a review photo by whoever can read the review.
-- Object rows are inserted as the table owner and rolled back (no file is uploaded).
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'storage_private';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u7 uuid := pg_temp.u(7);
  u11 uuid := pg_temp.u(11);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  v_conv constant uuid := '00000000-0000-4000-e000-000000000501'::uuid;
  v_base constant text := 'https://probe.invalid/storage/v1/object/public/';
  v_msg text;  v_grp text;  v_th_public constant text := 'probe-th-public.jpg';  v_th_private constant text := 'probe-th-private.jpg';
  v_rev text;
  v_post uuid;
  v_sql text;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'storage');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'the four buckets are private and avatars public',
    not exists (select 1 from storage.buckets where id in ('message-images', 'group-images', 'town-hall-images', 'review-images') and public)
    and exists (select 1 from storage.buckets where id = 'avatars' and public));
  perform pg_temp.probe_ok(v_probe, 'no SELECT policy on those buckets is a bare bucket test any more',
    not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and cmd = 'SELECT'
                 and qual in ('(bucket_id = ''message-images''::text)', '(bucket_id = ''group-images''::text)',
                              '(bucket_id = ''town-hall-images''::text)', '(bucket_id = ''review-images''::text)')));

  -- a thread between u3 and u7 (C1 members), photos uploaded by u3 and by u11 (not a participant)
  perform set_config('request.jwt.claims', '', true);
  insert into public.conversations (id, created_by) values (v_conv, u3);
  insert into public.conversation_participants (conversation_id, user_id) values (v_conv, u3), (v_conv, u7)
    on conflict do nothing;   -- in case a trigger already added the creator
  v_msg := upper(v_conv::text) || '/probe-msg.jpg';
  v_grp := upper(v_conv::text) || '/avatar_probe.jpg';
  perform pg_temp.probe_storage_object('message-images', v_msg, u3);
  perform pg_temp.probe_storage_object('group-images', v_grp, u3);
  perform pg_temp.probe_storage_object('message-images', upper(v_conv::text) || '/probe-other.jpg', u11);

  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'message-images', v_msg);
  perform pg_temp.probe_ok(v_probe, 'a participant reads the message photo', pg_temp.probe_count(u7, v_sql) = 1);
  perform pg_temp.probe_ok(v_probe, 'a non-participant does not', pg_temp.probe_count(u4, v_sql) = 0);
  perform pg_temp.probe_ok(v_probe, 'anon does not', pg_temp.probe_count(null, v_sql, 'anon') = 0);
  perform pg_temp.probe_ok(v_probe, 'an uploader who is not a participant reads only their own object',
    pg_temp.probe_count(u11, format('select 1 from storage.objects where bucket_id = %L and name like %L', 'message-images', upper(v_conv::text) || '/%')) = 1);
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'group-images', v_grp);
  perform pg_temp.probe_ok(v_probe, 'a participant reads the group photo; a non-participant and anon do not',
    pg_temp.probe_count(u7, v_sql) = 1 and pg_temp.probe_count(u4, v_sql) = 0 and pg_temp.probe_count(null, v_sql, 'anon') = 0);

  -- Town Hall: one photo on a post in C2 (public), one on a post in C1 (private)
  perform pg_temp.probe_storage_object('town-hall-images', v_th_public, u12);
  perform pg_temp.probe_storage_object('town-hall-images', v_th_private, u3);
  v_post := pg_temp.probe_post(1, u12, c2);
  update public.town_hall_posts set image_url = v_base || 'town-hall-images/' || v_th_public where id = v_post;
  v_post := pg_temp.probe_post(2, u3, c1);
  update public.town_hall_posts set image_url = v_base || 'town-hall-images/' || v_th_private where id = v_post;
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'town-hall-images', v_th_public);
  perform pg_temp.probe_ok(v_probe, 'anon reads a public community''s Town Hall photo', pg_temp.probe_count(null, v_sql, 'anon') = 1);
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'town-hall-images', v_th_private);
  perform pg_temp.probe_ok(v_probe, 'a private community''s Town Hall photo: its member yes, anon and a non-member no',
    pg_temp.probe_count(u7, v_sql) = 1 and pg_temp.probe_count(null, v_sql, 'anon') = 0 and pg_temp.probe_count(u12, v_sql) = 0);

  -- review photo on r(1) (u7's C1 ride, reviewed by u7, helped by u3)
  -- named like ReviewService's uploads: "<UUID>.jpg" (an uppercase uuid; the app uses a fresh UUID, not the review id,
  -- ReviewService.swift:60, :196; the policy matches by image_url, so the name's origin does not matter), URL with ?t=
  v_rev := upper((select v.id from public.reviews v where v.ride_id = pg_temp.r(1) limit 1)::text) || '.jpg';
  perform pg_temp.probe_storage_object('review-images', v_rev, u7);
  update public.reviews set image_url = v_base || 'review-images/' || v_rev || '?t=1' where ride_id = pg_temp.r(1);
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'review-images', v_rev);
  perform pg_temp.probe_ok(v_probe, 'a review photo: the reviewer and a C1 member yes, a non-member and anon no',
    pg_temp.probe_count(u7, v_sql) = 1 and pg_temp.probe_count(u3, v_sql) = 1
    and pg_temp.probe_count(u12, v_sql) = 0 and pg_temp.probe_count(null, v_sql, 'anon') = 0);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE storage_private OK' as probe;


-- =============================================================================================================
-- community_preview (Release 1, 20261021_0001): a visitor of a listed community (u3, not in C2; anon) reads its
-- id, member count, live open requests and newest post, and no address, note, description or gift key; hidden and
-- past requests are left out; a private community (C1), a null id and an unknown id are refused with 'not_listed',
-- to a C1 member too, without an exception; a block in either direction hides the other person's requests and
-- posts (checked before the archive, on a preview that answers success); an archived community is refused.
-- Rows are inserted as the table owner, as in reputation.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'community_preview';
  u3 uuid := pg_temp.u(3);  u7 uuid := pg_temp.u(7);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  v_ride   uuid := pg_temp.r(21);   -- open, in two days
  v_hidden uuid := pg_temp.r(22);   -- open, in two days, hidden
  v_past   uuid := pg_temp.r(23);   -- open, three days ago
  v_favor uuid;
  v_post uuid;
  v_call text;
  v_ids jsonb;
  j jsonb;
  k jsonb;
begin
  perform pg_temp.probe_require_release1(v_probe);
  perform pg_temp.probe_world();

  -- u12 (owner of public C2, its only member) posts a live ride and favor, a hidden ride, a past ride and a post
  insert into public.rides (id, user_id, date, "time", pickup, destination, notes, status, community_id, hidden_at, hidden_reason)
  values (v_ride,   u12, current_date + 2, '09:00', 'Probe pickup', 'Probe destination', 'Probe notes', 'open', c2, null, null),
         (v_hidden, u12, current_date + 2, '10:00', 'Probe pickup', 'Probe destination', null, 'open', c2, now(), 'communities probe'),
         (v_past,   u12, current_date - 3, '09:00', 'Probe pickup', 'Probe destination', null, 'open', c2, null, null);
  insert into public.favors (user_id, title, description, location, date, gift, status, community_id)
  values (u12, 'Probe favor', 'Probe description', 'Probe location', current_date + 2, 'Probe gift', 'open', c2)
  returning id into v_favor;
  v_post := pg_temp.probe_post(21, u12, c2);
  v_call := format('public.get_community_preview(%L::uuid)', c2);

  -- u3 is active in C1 only (private), not in C2
  j := pg_temp.probe_call(u3, v_call);
  perform pg_temp.probe_ok(v_probe, 'a non-member reads the preview of a listed community: ' || left(j::text, 500),
    j ->> 'success' = 'true');
  perform pg_temp.probe_ok(v_probe, 'the community is C2 with 1 active member: ' || (j -> 'community')::text,
    j #>> '{community,id}' = c2::text and (j #>> '{community,member_count}')::int = 1);
  v_ids := jsonb_path_query_array(j, '$.requests[*].id');
  perform pg_temp.probe_ok(v_probe, 'both live requests are listed: ' || v_ids::text,
    v_ids ? v_ride::text and v_ids ? v_favor::text);
  perform pg_temp.probe_ok(v_probe, 'the hidden and the past ride are not: ' || v_ids::text,
    not (v_ids ? v_hidden::text) and not (v_ids ? v_past::text));
  perform pg_temp.probe_ok(v_probe, 'the ride and the favor carry their type and title: ' || (j -> 'requests')::text,
    exists (select 1 from jsonb_array_elements(j -> 'requests') e
             where e ->> 'id' = v_ride::text and e ->> 'type' = 'ride' and e -> 'title' = 'null'::jsonb)
    and exists (select 1 from jsonb_array_elements(j -> 'requests') e
                 where e ->> 'id' = v_favor::text and e ->> 'type' = 'favor' and e ->> 'title' = 'Probe favor'));
  perform pg_temp.probe_ok(v_probe, 'no request has a pickup, destination, location, notes, description or gift key',
    not exists (select 1 from jsonb_array_elements(j -> 'requests') e, jsonb_object_keys(e) kk
                 where kk in ('pickup', 'destination', 'location', 'notes', 'description', 'gift')));
  perform pg_temp.probe_ok(v_probe, 'the post is listed: ' || (j -> 'posts')::text,
    jsonb_path_query_array(j, '$.posts[*].id') ? v_post::text);

  k := pg_temp.probe_call(null, v_call, 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon reads the same requests and post: ' || left(k::text, 500),
    k ->> 'success' = 'true'
    and jsonb_path_query_array(k, '$.requests[*].id') = v_ids
    and jsonb_path_query_array(k, '$.posts[*].id') = jsonb_path_query_array(j, '$.posts[*].id'));

  -- refusals: a private community (u12 is not in C1, u3 is), a null id, an unknown id
  j := pg_temp.probe_call(u12, format('public.get_community_preview(%L::uuid)', c1));
  k := pg_temp.probe_call(u3,  format('public.get_community_preview(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, format('a private community is refused to a non-member and to its member: %s / %s', j, k),
    j ->> 'success' = 'false' and j ->> 'code' = 'not_listed' and k ->> 'success' = 'false' and k ->> 'code' = 'not_listed');
  foreach v_call in array array['public.get_community_preview(null::uuid)', 'public.get_community_preview(gen_random_uuid())'] loop
    j := pg_temp.probe_call(null, v_call, 'anon');
    k := pg_temp.probe_call(u3, v_call);
    perform pg_temp.probe_ok(v_probe, format('%s answers not_listed to anon and to u3 without an exception: %s / %s', v_call, j, k),
      not (j ? 'raised') and j ->> 'code' = 'not_listed' and not (k ? 'raised') and k ->> 'code' = 'not_listed');
  end loop;

  -- blocks, before the archive: u12 blocks u7 (the blocked person reads), then u3 blocks u12 (the blocker reads)
  v_call := format('public.get_community_preview(%L::uuid)', c2);
  j := pg_temp.probe_run(u12, format($q$insert into public.blocked_users (blocker_id, blocked_id, reason)
                                      values (%L, %L, 'communities probe') returning to_jsonb(id)$q$, u12, u7));
  perform pg_temp.probe_ok(v_probe, 'u12 blocks u7: ' || j::text, not pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u7, v_call);
  perform pg_temp.probe_ok(v_probe, 'the person u12 blocked reads a preview without u12''s requests and post: ' || left(j::text, 500),
    j ->> 'success' = 'true'
    and not exists (select 1 from jsonb_array_elements(j -> 'requests') e where e ->> 'poster_id' = u12::text)
    and not exists (select 1 from jsonb_array_elements(j -> 'posts') e where e ->> 'author_id' = u12::text));
  j := pg_temp.probe_run(u3, format($q$insert into public.blocked_users (blocker_id, blocked_id, reason)
                                     values (%L, %L, 'communities probe') returning to_jsonb(id)$q$, u3, u12));
  perform pg_temp.probe_ok(v_probe, 'u3 blocks u12: ' || j::text, not pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u3, v_call);
  perform pg_temp.probe_ok(v_probe, 'the blocker reads a preview without u12''s requests and post: ' || left(j::text, 500),
    j ->> 'success' = 'true'
    and not exists (select 1 from jsonb_array_elements(j -> 'requests') e where e ->> 'poster_id' = u12::text)
    and not exists (select 1 from jsonb_array_elements(j -> 'posts') e where e ->> 'author_id' = u12::text));
  k := pg_temp.probe_call(null, v_call, 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon still reads them (control): ' || left(k::text, 500),
    jsonb_path_query_array(k, '$.requests[*].id') ? v_ride::text and jsonb_path_query_array(k, '$.posts[*].id') ? v_post::text);

  -- archive
  update public.communities set archived_at = now() where id = c2;
  j := pg_temp.probe_call(u3, v_call);
  perform pg_temp.probe_ok(v_probe, 'an archived community is refused: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'code' = 'not_listed');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE community_preview OK' as probe;


-- =============================================================================================================
-- listed_profiles (Release 1, 20261021_0001): a signed-in account reads an active member of a listed community
-- (u12, public C2) in public_profiles and get_profile_stats, as a guest does, and not a member of a private one
-- (u14, C3); it reads the review of a completed request in a listed community and not one in a private community,
-- and still does not read the listed request's row itself; anon's read of reviews plans and runs (it needs
-- EXECUTE on is_listed_request).
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'listed_profiles';
  u3 uuid := pg_temp.u(3);  u5 uuid := pg_temp.u(5);  u12 uuid := pg_temp.u(12);  u14 uuid := pg_temp.u(14);
  u16 uuid := pg_temp.u(16);
  c2 uuid := pg_temp.c(2);  c3 uuid := pg_temp.c(3);
  v_rev2 uuid;
  v_rev3 uuid;
  j jsonb;
begin
  perform pg_temp.probe_require_release1(v_probe);
  perform pg_temp.probe_world();

  perform pg_temp.probe_ok(v_probe, 'u3 reads u12 (public C2 only) in public_profiles',
    pg_temp.probe_count(u3, format('select 1 from public.public_profiles where id = %L', u12)) = 1);
  perform pg_temp.probe_ok(v_probe, 'u3 does not read u14 (private C3 only) in public_profiles',
    pg_temp.probe_count(u3, format('select 1 from public.public_profiles where id = %L', u14)) = 0);
  -- the gate answers {} for a hidden profile; a visible one has the three keys even when they are 0 / null
  j := pg_temp.probe_call(u3, format('public.get_profile_stats(%L::uuid)', u12));
  perform pg_temp.probe_ok(v_probe, 'get_profile_stats(u12) is not empty for u3: ' || j::text,
    jsonb_typeof(j) = 'object' and j ? 'review_count');
  j := pg_temp.probe_call(u3, format('public.get_profile_stats(%L::uuid)', u14));
  perform pg_temp.probe_ok(v_probe, 'get_profile_stats(u14) is empty for u3: ' || j::text, j = '{}'::jsonb);

  -- a completed C2 ride (u12 posted, u5 made a C2 member and helped) and a completed C3 ride (u14 posted, u16 made a
  -- C3 member and helped), each reviewed by its poster, as in reputation
  perform pg_temp.probe_member(c2, u5, 'member', 'active', 5);
  perform pg_temp.probe_member(c3, u16, 'member', 'active', 5);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id)
  values (pg_temp.r(31), u12, current_date - 3, '09:00', 'Probe pickup', 'Probe destination', 'completed', u5, c2),
         (pg_temp.r(32), u14, current_date - 3, '09:00', 'Probe pickup', 'Probe destination', 'completed', u16, c3);
  insert into public.reviews (reviewer_id, fulfiller_id, ride_id, rating, comment)
  values (u12, u5, pg_temp.r(31), 4, 'Probe review') returning id into v_rev2;
  insert into public.reviews (reviewer_id, fulfiller_id, ride_id, rating, comment)
  values (u14, u16, pg_temp.r(32), 5, 'Probe review') returning id into v_rev3;

  perform pg_temp.probe_ok(v_probe, 'u3 is approved (the reviews policy''s gate)',
    (select p.approved from public.profiles p where p.id = u3));
  perform pg_temp.probe_ok(v_probe, 'u3 reads the review of the completed C2 ride',
    pg_temp.probe_count(u3, format('select 1 from public.reviews where id = %L', v_rev2)) = 1);
  perform pg_temp.probe_ok(v_probe, 'u3 still does not read the C2 ride itself',
    pg_temp.probe_count(u3, format('select 1 from public.rides where id = %L', pg_temp.r(31))) = 0);
  perform pg_temp.probe_ok(v_probe, 'the C3 review is readable by its writer (control)',
    pg_temp.probe_count(u14, format('select 1 from public.reviews where id = %L', v_rev3)) = 1);
  perform pg_temp.probe_ok(v_probe, 'u3 does not read the review of the completed C3 ride',
    pg_temp.probe_count(u3, format('select 1 from public.reviews where id = %L', v_rev3)) = 0);
  j := pg_temp.probe_run(null, 'select to_jsonb(count(*)) from (select 1 from public.reviews) s', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon reads public.reviews without an error: ' || j::text, not pg_temp.probe_refused(j));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE listed_profiles OK' as probe;


-- =============================================================================================================
-- test_flag_visibility (Release 2, 20261021_0020): File A's schema (Blocks 1-6: the area columns and their CHECKs,
-- is_test, the merge columns, the two definer-only tables and the one-pending rule, the 'merged' event, the example
-- columns, the distance helper, the helpers' EXECUTE) and the is_test filter (Blocks 6-9). A listed test community
-- C4 (owner u16, its only member) beside listed C2 (owner u12), each with an area, an open ride, an open favor and a
-- post: anon reads no row of C4 from communities, guest_rides, guest_favors and town_hall_posts and one of each for
-- C2; u3 (in neither) reads C2 and not C4 from communities; C4's owner and a platform admin read C4; anon's and u3's
-- public_profiles and u3's my_visible_profile_ids() leave out u16 and keep u12; is_listed_request is false for C4's
-- requests and true for C2's; can_discover_community answers per caller and refuses a direct client call;
-- guest_rides and guest_favors end with is_example.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'test_flag_visibility';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u12 uuid := pg_temp.u(12);  u16 uuid := pg_temp.u(16);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);  c3 uuid := pg_temp.c(3);  c4 uuid;
  v_ride2 uuid := pg_temp.r(41);
  v_ride4 uuid := pg_temp.r(42);
  v_favor2 uuid;
  v_favor4 uuid;
  v_post2 uuid;
  v_post4 uuid;
  v_def text;
  v_sql text;
  v_state text;
  v_t text;
  v_d double precision;
  j jsonb;
begin
  perform pg_temp.probe_require_release2(v_probe, 'a');
  perform pg_temp.probe_world();

  -- Block 1: columns and CHECKs
  perform pg_temp.probe_ok(v_probe, 'communities has the seven new columns with their types',
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'communities'
        and (column_name, data_type) in (('area_name', 'text'), ('area_center_lat', 'double precision'),
              ('area_center_lng', 'double precision'), ('area_radius_miles', 'integer'), ('is_test', 'boolean'),
              ('merged_into_id', 'uuid'), ('merged_at', 'timestamp with time zone'))) = 7);
  perform pg_temp.probe_ok(v_probe, 'communities.is_test is not null with default false',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'communities' and column_name = 'is_test'
               and is_nullable = 'NO' and column_default = 'false'));
  perform pg_temp.probe_ok(v_probe, 'the five communities CHECKs exist',
    (select count(*) from pg_catalog.pg_constraint
      where conrelid = 'public.communities'::regclass and contype = 'c'
        and conname in ('communities_area_all_or_none', 'communities_area_radius', 'communities_area_center',
                        'communities_area_name', 'communities_hidden_not_open')) = 5);
  perform pg_temp.probe_ok(v_probe, 'communities_hidden_not_open reads is_public or join_policy <> open',
    (select pg_catalog.pg_get_constraintdef(oid) from pg_catalog.pg_constraint
      where conrelid = 'public.communities'::regclass and conname = 'communities_hidden_not_open')
      like '%is_public OR (join_policy <> ''open''::text)%');
  foreach v_sql in array array[
      format('select pg_temp.probe_area(%L::uuid, %L, 0.5, -150.0, 3)', c2, 'Probe Area'),
      format('select pg_temp.probe_area(%L::uuid, %L, 91, -150.0, 2)', c2, 'Probe Area'),
      format('select pg_temp.probe_area(%L::uuid, %L, 0.5, -181, 2)', c2, 'Probe Area'),
      format('select pg_temp.probe_area(%L::uuid, %L, %L::double precision, -150.0, 2)', c2, 'Probe Area', 'NaN'),
      format('select pg_temp.probe_area(%L::uuid, %L, 0.5, -150.0, 2)', c2, '  P  '),
      format('select pg_temp.probe_area(%L::uuid, %L, 0.5, -150.0, 2)', c2, repeat('x', 81)),
      format('select pg_temp.probe_area(%L::uuid, null, 0.5, -150.0, 2)', c2),
      format('select pg_temp.probe_area(%L::uuid, %L, 0.5, null, 2)', c2, 'Probe Area')]
  loop
    begin
      execute v_sql;
      v_state := 'none';
    exception when others then
      v_state := sqlstate;
    end;
    perform pg_temp.probe_ok(v_probe, format('a bad area is refused by a CHECK (23514, got %s): %s', v_state, v_sql),
      v_state = '23514');
  end loop;
  c4 := pg_temp.probe_test_community(4, u16);
  perform pg_temp.probe_area(c2, 'Probe Area Two', 0.5, -150.0, 2);
  perform pg_temp.probe_area(c4, 'Probe Area Four', 0.52, -150.0, 1);
  perform pg_temp.probe_area(c3, 'Probe Area Three', -0.5, 180, 10);
  perform pg_temp.probe_ok(v_probe, 'C2, C3 and C4 carry their areas; C4 is a listed test community',
    (select count(*) from public.communities where id in (c2, c3, c4) and area_radius_miles is not null) = 3
    and (select is_public and is_test from public.communities where id = c4));

  -- Blocks 2-5: the two tables, the one-pending rule, the 'merged' event, the example columns
  foreach v_t in array array['public.community_listing_events', 'public.community_merge_proposals'] loop
    perform pg_temp.probe_ok(v_probe, v_t || ' has RLS on and no policy',
      (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass)
      and not exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass));
    perform pg_temp.probe_ok(v_probe, v_t || ' grants nothing to anon or authenticated',
      not has_table_privilege('anon', v_t, 'select,insert,update,delete,truncate,references,trigger')
      and not has_table_privilege('authenticated', v_t, 'select,insert,update,delete,truncate,references,trigger'));
  end loop;
  j := pg_temp.probe_run(u3, 'select to_jsonb(count(*)) from public.community_listing_events');
  perform pg_temp.probe_ok(v_probe, 'a member''s direct read of community_listing_events raises 42501: ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501');
  insert into public.community_merge_proposals (from_community_id, to_community_id, survivor_community_id, proposed_by)
  values (c2, c1, c2, u12);
  foreach v_sql in array array[
      format('insert into public.community_merge_proposals (from_community_id, to_community_id, survivor_community_id) values (%L, %L, %L)', c2, c3, c2),
      format('insert into public.community_merge_proposals (from_community_id, to_community_id, survivor_community_id) values (%L, %L, %L)', c3, c1, c1)]
  loop
    begin
      execute v_sql;
      v_state := 'none';
    exception when others then
      v_state := sqlstate;
    end;
    perform pg_temp.probe_ok(v_probe, format('a second pending proposal from or to one community is refused (23505, got %s)', v_state),
      v_state = '23505');
  end loop;
  foreach v_sql in array array[
      format('insert into public.community_merge_proposals (from_community_id, to_community_id, survivor_community_id) values (%L, %L, %L)', c3, c3, c3),
      format('insert into public.community_merge_proposals (from_community_id, to_community_id, survivor_community_id) values (%L, %L, %L)', c3, c4, c1)]
  loop
    begin
      execute v_sql;
      v_state := 'none';
    exception when others then
      v_state := sqlstate;
    end;
    perform pg_temp.probe_ok(v_probe, format('a proposal to itself or with a third survivor is refused (23514, got %s)', v_state),
      v_state = '23514');
  end loop;
  perform pg_temp.probe_ok(v_probe, 'a new proposal is pending and expires in 7 days',
    exists (select 1 from public.community_merge_proposals
             where from_community_id = c2 and status = 'pending' and expires_at = created_at + interval '7 days'));
  v_def := (select pg_catalog.pg_get_constraintdef(oid) from pg_catalog.pg_constraint
             where conrelid = 'public.community_membership_events'::regclass
               and conname = 'community_membership_events_event_check');
  perform pg_temp.probe_ok(v_probe, 'the membership event CHECK allows the 11 live events and merged: ' || coalesce(v_def, 'null'),
    (select count(*) from unnest(array['applied', 'invited', 'approved', 'rejected', 'removed', 'readmitted', 'left',
                                       'role_changed', 'ownership_transferred', 'archived', 'unarchived', 'merged']) e
      where v_def like '%''' || e || '''%') = 12);
  perform pg_temp.probe_ok(v_probe, 'rides, favors and town_hall_posts have is_example boolean not null default false',
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name in ('rides', 'favors', 'town_hall_posts')
        and column_name = 'is_example' and data_type = 'boolean' and is_nullable = 'NO'
        and column_default = 'false') = 3);
  perform pg_temp.probe_ok(v_probe, 'town_hall_posts.system_event is text',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'town_hall_posts' and column_name = 'system_event'
               and data_type = 'text'));
  perform pg_temp.probe_ok(v_probe, 'the eight File A indexes exist',
    (select count(*) from pg_catalog.pg_indexes
      where schemaname = 'public'
        and indexname in ('communities_listed_live', 'community_listing_events_community_created',
                          'community_merge_one_pending_from', 'community_merge_one_pending_to',
                          'community_merge_proposals_to_status', 'rides_examples', 'favors_examples',
                          'town_hall_posts_examples')) = 8);

  -- Block 6: the distance and the EXECUTE of every function File A creates or re-creates
  v_d := public.great_circle_miles(0, 0, 0, 1);
  perform pg_temp.probe_ok(v_probe, format('one degree of longitude at the equator is about 69.09 miles (%s)', v_d),
    v_d between 69.0 and 69.2);
  v_d := public.great_circle_miles(0, 179.9, 0, -179.9);
  perform pg_temp.probe_ok(v_probe, format('0.2 degrees across the antimeridian is about 13.8 miles (%s)', v_d),
    v_d between 13.7 and 13.9);
  perform pg_temp.probe_ok(v_probe, 'a point is 0 miles from itself',
    public.great_circle_miles(47.6062, -122.3321, 47.6062, -122.3321) = 0);
  foreach v_t in array array[
      'public.great_circle_miles(double precision, double precision, double precision, double precision)',
      'public.can_discover_community(uuid)', 'public.guard_example_content()'] loop
    perform pg_temp.probe_ok(v_probe, v_t || ': EXECUTE for service_role only (no anon, authenticated or public)',
      not has_function_privilege('anon', v_t, 'execute')
      and not has_function_privilege('authenticated', v_t, 'execute')
      and has_function_privilege('service_role', v_t, 'execute')
      and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                       where p.oid = v_t::regprocedure and a.grantee = 0));
  end loop;
  foreach v_t in array array['public.my_visible_profile_ids()', 'public.is_listed_request(uuid, uuid)'] loop
    perform pg_temp.probe_ok(v_probe, v_t || ': EXECUTE kept for anon, authenticated and service_role, none for public',
      has_function_privilege('anon', v_t, 'execute')
      and has_function_privilege('authenticated', v_t, 'execute')
      and has_function_privilege('service_role', v_t, 'execute')
      and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                       where p.oid = v_t::regprocedure and a.grantee = 0));
  end loop;
  j := pg_temp.probe_call(u3, format('public.can_discover_community(%L::uuid)', c2));
  perform pg_temp.probe_ok(v_probe, 'a client''s direct call of can_discover_community raises 42501: ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501');

  -- Blocks 7-9: C2 and C4 each get an open ride, an open favor and a post (as the table owner)
  perform set_config('request.jwt.claims', '', true);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id)
  values (v_ride2, u12, current_date + 2, '09:00', 'Probe pickup', 'Probe destination', 'open', c2),
         (v_ride4, u16, current_date + 2, '09:00', 'Probe pickup', 'Probe destination', 'open', c4);
  insert into public.favors (user_id, title, location, date, status, community_id)
  values (u12, 'Probe favor', 'Probe location', current_date + 2, 'open', c2) returning id into v_favor2;
  insert into public.favors (user_id, title, location, date, status, community_id)
  values (u16, 'Probe favor', 'Probe location', current_date + 2, 'open', c4) returning id into v_favor4;
  v_post2 := pg_temp.probe_post(41, u12, c2);
  v_post4 := pg_temp.probe_post(42, u16, c4);

  foreach v_t in array array['public.communities|id', 'public.guest_rides|community_id',
                             'public.guest_favors|community_id', 'public.town_hall_posts|community_id'] loop
    v_sql := format('select 1 from %s where %I = ', split_part(v_t, '|', 1), split_part(v_t, '|', 2));
    perform pg_temp.probe_ok(v_probe, 'anon reads one C2 row from ' || split_part(v_t, '|', 1) || ' (control)',
      pg_temp.probe_count(null, v_sql || quote_literal(c2), 'anon') = 1);
    perform pg_temp.probe_ok(v_probe, 'anon reads no C4 row from ' || split_part(v_t, '|', 1),
      pg_temp.probe_count(null, v_sql || quote_literal(c4), 'anon') = 0);
  end loop;

  perform pg_temp.probe_ok(v_probe, 'u3 reads C2 from communities (control)',
    pg_temp.probe_count(u3, format('select 1 from public.communities where id = %L', c2)) = 1);
  perform pg_temp.probe_ok(v_probe, 'u3 (not in C4) reads no C4 row from communities',
    pg_temp.probe_count(u3, format('select 1 from public.communities where id = %L', c4)) = 0);
  perform pg_temp.probe_ok(v_probe, 'u16 (C4''s owner) reads C4',
    pg_temp.probe_count(u16, format('select 1 from public.communities where id = %L', c4)) = 1);
  perform pg_temp.probe_ok(v_probe, 'the platform admin subject resolves', v_admin is not null);
  perform pg_temp.probe_ok(v_probe, 'the platform admin reads C4',
    pg_temp.probe_count(v_admin, format('select 1 from public.communities where id = %L', c4)) = 1);

  perform pg_temp.probe_ok(v_probe, 'u16 is active in no listed community but C4',
    not exists (select 1 from public.community_members m
                  join public.communities c on c.id = m.community_id
                 where m.user_id = u16 and m.status = 'active' and c.id <> c4
                   and c.is_public and c.archived_at is null));
  perform pg_temp.probe_ok(v_probe, 'anon reads u12 in public_profiles (control)',
    pg_temp.probe_count(null, format('select 1 from public.public_profiles where id = %L', u12), 'anon') = 1);
  perform pg_temp.probe_ok(v_probe, 'anon does not read u16 in public_profiles',
    pg_temp.probe_count(null, format('select 1 from public.public_profiles where id = %L', u16), 'anon') = 0);
  perform pg_temp.probe_ok(v_probe, 'u3 reads u12 in public_profiles (control)',
    pg_temp.probe_count(u3, format('select 1 from public.public_profiles where id = %L', u12)) = 1);
  perform pg_temp.probe_ok(v_probe, 'u3 does not read u16 in public_profiles',
    pg_temp.probe_count(u3, format('select 1 from public.public_profiles where id = %L', u16)) = 0);
  j := pg_temp.probe_call(u3, 'public.my_visible_profile_ids()');
  perform pg_temp.probe_ok(v_probe, 'my_visible_profile_ids() for u3 keeps u12 and leaves out u16: ' || j::text,
    jsonb_typeof(j) = 'array' and j ? u12::text and not (j ? u16::text));

  perform pg_temp.probe_ok(v_probe, 'is_listed_request is true for the C2 ride and favor (control)',
    public.is_listed_request(v_ride2, null) and public.is_listed_request(null, v_favor2));
  perform pg_temp.probe_ok(v_probe, 'is_listed_request is false for the C4 ride and favor',
    not public.is_listed_request(v_ride4, null) and not public.is_listed_request(null, v_favor4));

  -- can_discover_community as definer code calls it: the table owner, with the caller's JWT claims
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  perform pg_temp.probe_ok(v_probe, 'u3 discovers C2, and neither C4 nor its own private C1',
    public.can_discover_community(c2) and not public.can_discover_community(c4) and not public.can_discover_community(c1));
  perform set_config('request.jwt.claims', json_build_object('sub', u16, 'role', 'authenticated')::text, true);
  perform pg_temp.probe_ok(v_probe, 'C4''s owner discovers C4', public.can_discover_community(c4));
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform pg_temp.probe_ok(v_probe, 'a platform admin discovers C4', public.can_discover_community(c4));
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform pg_temp.probe_ok(v_probe, 'a guest discovers C2 and not C4, an unknown id or null',
    public.can_discover_community(c2) and not public.can_discover_community(c4)
    and not public.can_discover_community(gen_random_uuid()) and not public.can_discover_community(null));
  perform set_config('request.jwt.claims', '', true);

  foreach v_t in array array['guest_rides', 'guest_favors'] loop
    perform pg_temp.probe_ok(v_probe, v_t || ' ends with is_example',
      (select c.column_name::text from information_schema.columns c
        where c.table_schema = 'public' and c.table_name = v_t
        order by c.ordinal_position desc limit 1) = 'is_example');
  end loop;
  j := pg_temp.probe_run(null, format('select to_jsonb(is_example) from public.guest_rides where id = %L', v_ride2), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon reads is_example = false on the C2 ride: ' || j::text, j = 'false'::jsonb);

  -- an archived listed community is not discoverable
  update public.communities set archived_at = now() where id = c2;
  perform set_config('request.jwt.claims', json_build_object('sub', u12, 'role', 'authenticated')::text, true);
  perform pg_temp.probe_ok(v_probe, 'an archived C2 is not discoverable, even by its owner', not public.can_discover_community(c2));
  perform set_config('request.jwt.claims', '', true);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE test_flag_visibility OK' as probe;


-- =============================================================================================================
-- example_guard (Release 2, 20261021_0020 Block 10): a client cannot set is_example on a ride, a favor or a post,
-- nor system_event on a post, at insert, nor change is_example on a ride by update, its own included (42501
-- 'example_flag_reserved'); the table owner (as definer code, no JWT) can; a C1 member's claim of an example ride
-- or favor is refused with 42501 'example_request' and the same claim of an ordinary open ride succeeds; the poster
-- can still edit an example ride's notes. Clients have no UPDATE policy on town_hall_posts, so the guard's
-- post-update branch is a second line only.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'example_guard';
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u7 uuid := pg_temp.u(7);  u11 uuid := pg_temp.u(11);
  c1 uuid := pg_temp.c(1);
  v_example uuid := pg_temp.r(2);    -- u3's open C1 ride (probe_world)
  v_control uuid := pg_temp.r(52);   -- u11's open C1 ride
  v_own uuid;
  v_favor uuid;
  v_post uuid;
  v_sql text;
  v_state text;
  j jsonb;
begin
  perform pg_temp.probe_require_release2(v_probe, 'a');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'an existing member subject resolves', v_member is not null);

  -- the member subject's own ordinary ride (the guard lets it through: control)
  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination, notes)
       values (%L, current_date + 2, '10:00', 'Probe pickup', 'Probe destination', 'communities probe')
       returning to_jsonb(id)$q$, v_member));
  perform pg_temp.probe_ok(v_probe, 'the member inserts an ordinary ride (control): ' || coalesce(j ->> 'error', ''),
    not pg_temp.probe_refused(j));
  v_own := (j #>> '{}')::uuid;

  foreach v_sql in array array[
      format($q$insert into public.rides (user_id, date, "time", pickup, destination, is_example)
                values (%L, current_date + 2, '10:00', 'Probe pickup', 'Probe destination', true) returning to_jsonb(id)$q$, v_member),
      format($q$insert into public.favors (user_id, title, location, date, is_example)
                values (%L, 'Probe favor', 'Probe location', current_date + 2, true) returning to_jsonb(id)$q$, v_member),
      format($q$insert into public.town_hall_posts (user_id, title, content, is_example)
                values (%L, 'Probe post', 'communities probe post', true) returning to_jsonb(id)$q$, v_member),
      format($q$insert into public.town_hall_posts (user_id, title, content, system_event)
                values (%L, 'Probe post', 'communities probe post', 'community_merged') returning to_jsonb(id)$q$, v_member),
      format($q$with x as (update public.rides set is_example = true where id = %L returning 1)
                select to_jsonb(count(*)) from x$q$, v_own)]
  loop
    j := pg_temp.probe_run(v_member, v_sql);
    perform pg_temp.probe_ok(v_probe, format('refused with 42501 example_flag_reserved: %s -> %s', left(v_sql, 60), j),
      coalesce(j ->> 'sqlstate', '') = '42501' and coalesce(j ->> 'error', '') = 'example_flag_reserved');
  end loop;
  perform pg_temp.probe_ok(v_probe, 'the member''s ride is still not an example',
    not (select r.is_example from public.rides r where r.id = v_own));

  -- the table owner (definer code) marks u3's open C1 ride r(2) as an example
  j := pg_temp.probe_run(null, format(
    $q$with x as (update public.rides set is_example = true where id = %L returning 1) select to_jsonb(count(*)) from x$q$,
    v_example), 'owner');
  perform pg_temp.probe_ok(v_probe, 'the table owner marks r(2) as an example: ' || j::text, j = '1'::jsonb);

  j := pg_temp.probe_run(u7, format(
    $q$with x as (update public.rides set status = 'confirmed', claimed_by = %L where id = %L returning 1)
       select to_jsonb(count(*)) from x$q$, u7, v_example));
  perform pg_temp.probe_ok(v_probe, 'a C1 member''s claim of the example ride is refused with 42501 example_request: ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501' and coalesce(j ->> 'error', '') = 'example_request');
  perform pg_temp.probe_ok(v_probe, 'the example ride is still open and unclaimed',
    exists (select 1 from public.rides r where r.id = v_example and r.status::text = 'open' and r.claimed_by is null));

  j := pg_temp.probe_run(u3, format(
    $q$with x as (update public.rides set notes = 'Probe notes edited' where id = %L returning 1)
       select to_jsonb(count(*)) from x$q$, v_example));
  perform pg_temp.probe_ok(v_probe, 'the poster still edits the example ride''s notes: ' || j::text, j = '1'::jsonb);
  j := pg_temp.probe_run(u3, format(
    $q$with x as (update public.rides set is_example = false where id = %L returning 1)
       select to_jsonb(count(*)) from x$q$, v_example));
  perform pg_temp.probe_ok(v_probe, 'the poster cannot clear is_example (42501 example_flag_reserved): ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501' and coalesce(j ->> 'error', '') = 'example_flag_reserved');

  -- an example favor, written by the table owner, cannot be claimed either
  perform set_config('request.jwt.claims', '', true);
  insert into public.favors (user_id, title, location, date, status, community_id, is_example)
  values (u3, 'Probe example favor', 'Probe location', current_date + 3, 'open', c1, true)
  returning id into v_favor;
  j := pg_temp.probe_run(u7, format(
    $q$with x as (update public.favors set status = 'confirmed', claimed_by = %L where id = %L returning 1)
       select to_jsonb(count(*)) from x$q$, u7, v_favor));
  perform pg_temp.probe_ok(v_probe, 'a C1 member''s claim of the example favor is refused with 42501 example_request: ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501' and coalesce(j ->> 'error', '') = 'example_request');

  -- control: a second, ordinary open C1 ride, claimed the same way
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id)
  values (v_control, u11, current_date + 3, '11:00', 'Probe pickup', 'Probe destination', 'open', c1);
  j := pg_temp.probe_run(u7, format(
    $q$with x as (update public.rides set status = 'confirmed', claimed_by = %L where id = %L returning 1)
       select to_jsonb(count(*)) from x$q$, u7, v_control));
  perform pg_temp.probe_ok(v_probe, 'the same claim of an ordinary open ride succeeds (control): ' || j::text, j = '1'::jsonb);

  -- the definer path for posts: the table owner writes a post with system_event and is_example
  perform set_config('request.jwt.claims', '', true);
  insert into public.town_hall_posts (user_id, title, content, community_id, system_event, is_example)
  values (u3, 'Probe system post', 'communities probe post', c1, 'community_merged', true)
  returning id into v_post;
  perform pg_temp.probe_ok(v_probe, 'the table owner writes a post with system_event and is_example', v_post is not null);
  begin
    insert into public.town_hall_posts (user_id, title, content, community_id, system_event)
    values (u3, 'Probe system post', 'communities probe post', c1, 'other_event');
    v_state := 'none';
  exception when others then
    v_state := sqlstate;
  end;
  perform pg_temp.probe_ok(v_probe, 'system_event accepts only community_merged (23514, got ' || v_state || ')',
    v_state = '23514');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE example_guard OK' as probe;


-- =============================================================================================================
-- listed_reviews (Release 2, 20261021_0020 Block 11, ruling R9): a signed-in account with no membership and
-- approved false (u10) reads the review of a completed request in a listed community (C2) and not one in a listed
-- test community (C4), nor the C2 request itself; the C4 review stays readable by its writer (control); an approved
-- account in neither (u3) reads the C2 review and not the C4 one; anon reads no review through the table beyond what
-- the guest views give it (reviews_select_anon_guest): the C2 review through them, not the C4 review.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'listed_reviews';
  u3 uuid := pg_temp.u(3);  u5 uuid := pg_temp.u(5);  u10 uuid := pg_temp.u(10);  u12 uuid := pg_temp.u(12);
  u13 uuid := pg_temp.u(13);  u16 uuid := pg_temp.u(16);
  c2 uuid := pg_temp.c(2);  c4 uuid;
  v_rev2 uuid;
  v_rev4 uuid;
begin
  perform pg_temp.probe_require_release2(v_probe, 'a');
  perform pg_temp.probe_world();
  c4 := pg_temp.probe_test_community(4, u16);

  -- a completed C2 ride (u12 posted, u5 made a C2 member and helped) and a completed C4 ride (u16 posted, u13 made a
  -- C4 member and helped), each reviewed by its poster, as in listed_profiles
  perform pg_temp.probe_member(c2, u5, 'member', 'active', 5);
  perform pg_temp.probe_member(c4, u13, 'member', 'active', 5);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id)
  values (pg_temp.r(61), u12, current_date - 3, '09:00', 'Probe pickup', 'Probe destination', 'completed', u5, c2),
         (pg_temp.r(62), u16, current_date - 3, '09:00', 'Probe pickup', 'Probe destination', 'completed', u13, c4);
  insert into public.reviews (reviewer_id, fulfiller_id, ride_id, rating, comment)
  values (u12, u5, pg_temp.r(61), 4, 'Probe review') returning id into v_rev2;
  insert into public.reviews (reviewer_id, fulfiller_id, ride_id, rating, comment)
  values (u16, u13, pg_temp.r(62), 5, 'Probe review') returning id into v_rev4;

  perform pg_temp.probe_ok(v_probe, 'u10 has no membership and is not approved (the old gate is false for it)',
    not exists (select 1 from public.community_members m where m.user_id = u10)
    and not coalesce((select p.approved from public.profiles p where p.id = u10), false));
  perform pg_temp.probe_ok(v_probe, 'u10 reads the review of the completed C2 ride',
    pg_temp.probe_count(u10, format('select 1 from public.reviews where id = %L', v_rev2)) = 1);
  perform pg_temp.probe_ok(v_probe, 'u10 does not read the C2 ride itself',
    pg_temp.probe_count(u10, format('select 1 from public.rides where id = %L', pg_temp.r(61))) = 0);
  perform pg_temp.probe_ok(v_probe, 'the C4 review is readable by its writer (control)',
    pg_temp.probe_count(u16, format('select 1 from public.reviews where id = %L', v_rev4)) = 1);
  perform pg_temp.probe_ok(v_probe, 'u10 does not read the review of the completed C4 ride',
    pg_temp.probe_count(u10, format('select 1 from public.reviews where id = %L', v_rev4)) = 0);
  perform pg_temp.probe_ok(v_probe, 'u3 (approved, in neither) reads the C2 review and not the C4 one',
    pg_temp.probe_count(u3, format('select 1 from public.reviews where id = %L', v_rev2)) = 1
    and pg_temp.probe_count(u3, format('select 1 from public.reviews where id = %L', v_rev4)) = 0);
  perform pg_temp.probe_ok(v_probe, 'anon reads the C2 review through the guest views (control)',
    pg_temp.probe_count(null, format('select 1 from public.reviews where id = %L', v_rev2), 'anon') = 1);
  perform pg_temp.probe_ok(v_probe, 'anon does not read the C4 review',
    pg_temp.probe_count(null, format('select 1 from public.reviews where id = %L', v_rev4), 'anon') = 0);
  perform pg_temp.probe_ok(v_probe, 'anon reads no review through the table beyond the guest views',
    pg_temp.probe_count(null, $q$select 1 from public.reviews v
                                  where not exists (select 1 from public.guest_rides g where g.id = v.ride_id)
                                    and not exists (select 1 from public.guest_favors g where g.id = v.favor_id)$q$,
                        'anon') = 0);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE listed_reviews OK' as probe;


-- =============================================================================================================
-- discovery_search (Release 2, 20261021_0021 Blocks 1-3 and 7; rulings R-G1 and R-G4): the EXECUTE, definer,
-- search_path and volatility of every File B function; search by name (case, the wildcards % and _ and the
-- backslash taken literally, trimming, fewer than 2 characters, the 60-character cut, names that start with the
-- text first); search near a point (the distance, the edge of a circle, 3 miles north, the antimeridian, invalid
-- points); hidden C1 (an area its owner set) in neither search for anyone, its owner included; listed test
-- community C4 (owner u16) in both and in get_community_preview for its owner and a platform admin only; a banned
-- member not counted; the row shape; nothing written by any search, preview or area check (pg_stat_xact_user_tables
-- of this transaction, so concurrent live writes cannot disturb it; communities, notifications and
-- community_listing_events included); 20 rows at most with 25 matching communities; get_community_preview of
-- merged communities ('merged' when the survivor is discoverable to the caller, not_listed otherwise); an archived
-- C2 gone from both searches. Probe areas sit where no live area is (C2 at (0.5, -150.0), radius 2); every
-- "returns nothing" check reads probe ids only (00000000-0000-4000-b000-...).
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'discovery_search';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u2 uuid := pg_temp.u(2);  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u12 uuid := pg_temp.u(12);
  u16 uuid := pg_temp.u(16);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);  c3 uuid := pg_temp.c(3);  c4 uuid;
  c6 uuid := pg_temp.c(6);  c7 uuid := pg_temp.c(7);  c8 uuid := pg_temp.c(8);  c9 uuid := pg_temp.c(9);
  v_ids constant jsonpath := '$.communities[*].id ? (@ starts with "00000000-0000-4000-b000-")';
  v_keys constant text[] := array['id', 'name', 'description', 'join_policy', 'area_name', 'area_radius_miles',
                                  'member_count', 'distance_miles'];
  v_sixty constant text := rpad('Probe Sixty Nine ', 60, 'x');
  v_writes bigint;
  v_fn text;
  v_q text;
  v_subs uuid[];
  v_modes text[];
  i int;
  n int;
  j jsonb;
  k jsonb;
begin
  perform pg_temp.probe_require_release2(v_probe, 'b');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'the platform admin subject resolves', v_admin is not null);

  -- EXECUTE (ruling R-G1), definer, search_path, volatility
  foreach v_fn in array array['public.search_communities_by_name(text)',
                              'public.find_communities_near(double precision, double precision)',
                              'public.get_community_preview(uuid)'] loop
    perform pg_temp.probe_ok(v_probe, v_fn || ': EXECUTE for anon, authenticated and service_role, none for public',
      has_function_privilege('anon', v_fn, 'execute')
      and has_function_privilege('authenticated', v_fn, 'execute')
      and has_function_privilege('service_role', v_fn, 'execute')
      and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                       where p.oid = v_fn::regprocedure and a.grantee = 0));
  end loop;
  foreach v_fn in array array['public.check_community_area(double precision, double precision, integer, uuid)',
      'public.create_community_with_area(text, text, text, text, boolean, text, double precision, double precision, integer, text)',
      'public.update_community_access(uuid, boolean, text, text, double precision, double precision, integer, text)',
      'public.set_community_public(uuid, boolean)', 'public.get_platform_communities()'] loop
    perform pg_temp.probe_ok(v_probe, v_fn || ': EXECUTE for authenticated and service_role, none for anon or public',
      not has_function_privilege('anon', v_fn, 'execute')
      and has_function_privilege('authenticated', v_fn, 'execute')
      and has_function_privilege('service_role', v_fn, 'execute')
      and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                       where p.oid = v_fn::regprocedure and a.grantee = 0));
  end loop;
  v_fn := 'public.overlapping_listed_communities(double precision, double precision, integer, uuid)';
  perform pg_temp.probe_ok(v_probe, v_fn || ': EXECUTE for service_role only (no anon, authenticated or public)',
    not has_function_privilege('anon', v_fn, 'execute')
    and not has_function_privilege('authenticated', v_fn, 'execute')
    and has_function_privilege('service_role', v_fn, 'execute')
    and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                     where p.oid = v_fn::regprocedure and a.grantee = 0));
  perform pg_temp.probe_ok(v_probe, 'the nine File B functions are security definer with search_path ""',
    (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in ('search_communities_by_name', 'find_communities_near', 'overlapping_listed_communities',
                          'check_community_area', 'create_community_with_area', 'update_community_access',
                          'set_community_public', 'get_community_preview', 'get_platform_communities')
        and p.prosecdef and p.proconfig = array['search_path=""']) = 9);
  perform pg_temp.probe_ok(v_probe, 'search_communities_by_name and find_communities_near are stable',
    (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in ('search_communities_by_name', 'find_communities_near') and p.provolatile = 's') = 2);
  j := pg_temp.probe_call(null, 'public.check_community_area(0.5, -150.0, 1)', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call check_community_area (42501): ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_call(u3, 'public.overlapping_listed_communities(0.5, -150.0, 1, null)');
  perform pg_temp.probe_ok(v_probe, 'a member cannot call overlapping_listed_communities (42501): ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501');

  -- the world: C2 'Probe Town' (0.5, -150.0) radius 2 with banned u2 active in it; listed test community C4 (owner
  -- u16) at the same point, radius 1; hidden C1, whose owner sets an area at the same point through
  -- update_community_access; listed C6 at (0, 179.99), radius 10; listed C7 'Test Probe Seven', C8
  -- 'Probe 100% Eight' and C9 (a 60-character name), no area
  perform pg_temp.probe_area(c2, 'Probe Town', 0.5, -150.0, 2);
  perform pg_temp.probe_member(c2, u2, 'member', 'active', 3);
  c4 := pg_temp.probe_test_community(4, u16);
  perform pg_temp.probe_area(c4, 'Probe Town Test', 0.5, -150.0, 1);
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, false, %L, %L, 0.5, -150.0, 2)',
                                      c1, 'approve', 'Probe One Area'));
  perform pg_temp.probe_ok(v_probe, 'C1''s owner sets an area on hidden C1: ' || j::text,
    j ->> 'success' = 'true' and j ->> 'changed' = 'true');
  perform pg_temp.probe_ok(v_probe, 'C1 stays hidden with its area and no listing event',
    (select not c.is_public and c.area_name = 'Probe One Area' and c.area_radius_miles = 2
       from public.communities c where c.id = c1)
    and not exists (select 1 from public.community_listing_events e where e.community_id = c1));
  perform pg_temp.probe_community(6, 'Probe Dateline Six', u12, true, 'approve');
  perform pg_temp.probe_area(c6, 'Probe Dateline', 0, 179.99, 10);
  perform pg_temp.probe_community(7, 'Test Probe Seven', u12, true, 'approve');
  perform pg_temp.probe_community(8, 'Probe 100% Eight', u12, true, 'approve');
  perform pg_temp.probe_community(9, v_sixty, u12, true, 'approve');

  v_writes := (select coalesce(sum(t.n_tup_ins + t.n_tup_upd + t.n_tup_del), 0)
                 from pg_catalog.pg_stat_xact_user_tables t);

  -- search by name
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', 'two'), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: ''two'' finds C2 only: ' || left(j::text, 500),
    j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = jsonb_build_array(c2));
  k := (select e from jsonb_array_elements(j -> 'communities') e where e ->> 'id' = c2::text);
  perform pg_temp.probe_ok(v_probe, 'the row has exactly the eight keys: ' || coalesce(k::text, 'null'),
    k ?& v_keys and (select count(*) from jsonb_object_keys(k)) = 8);
  perform pg_temp.probe_ok(v_probe, 'C2''s row: name, policy, area, 1 member (banned u2 not counted), no distance: ' || k::text,
    k ->> 'name' = 'Probe Public Two' and k ->> 'join_policy' = 'approve' and k ->> 'area_name' = 'Probe Town'
    and (k ->> 'area_radius_miles')::int = 2 and (k ->> 'member_count')::int = 1
    and k -> 'distance_miles' = 'null'::jsonb and k ->> 'description' = 'communities probe');
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', 'PROBE PUBLIC'), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: ''PROBE PUBLIC'' matches case-insensitively: ' || left(j::text, 500),
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c2));
  foreach v_q in array array['o', '%', '_', '\', ' ', ''] loop
    j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', v_q), 'anon');
    perform pg_temp.probe_ok(v_probe, format('anon: %L (fewer than 2 characters) answers success with no row: %s', v_q, j),
      j = '{"success": true, "communities": []}'::jsonb);
  end loop;
  j := pg_temp.probe_call(null, 'public.search_communities_by_name(null)', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: null answers success with no row: ' || j::text,
    j = '{"success": true, "communities": []}'::jsonb);
  foreach v_q in array array['%%', '__', 'o%', '_o', 'e\', '\\', '\%'] loop
    j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', v_q), 'anon');
    perform pg_temp.probe_ok(v_probe, format('anon: %L is literal (no probe name holds it), success, no error: %s', v_q, left(j::text, 300)),
      not (j ? 'raised') and j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = '[]'::jsonb);
  end loop;
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', '0%'), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: ''0%'' finds only the name that holds it literally: ' || left(j::text, 500),
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c8));
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', '  probe  '), 'anon');
  k := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', 'probe'), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: ''  probe  '' answers what ''probe'' answers, with rows: ' || left(j::text, 300),
    j = k and jsonb_array_length(j -> 'communities') > 0);
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', repeat('x', 200)), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: a 200-character query answers success with no probe row: ' || left(j::text, 300),
    not (j ? 'raised') and j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = '[]'::jsonb);
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', v_sixty || 'yyyy'), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: only the first 60 characters are used (a 64-character query finds C9): ' || left(j::text, 300),
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c9));
  j := pg_temp.probe_call(u16, format('public.search_communities_by_name(%L)', 'test'));
  perform pg_temp.probe_ok(v_probe, 'u16: ''test'' lists the name that starts with it (C7) before the one that holds it (C4): ' || left(j::text, 500),
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c7, c4));

  -- hidden C1 is never listed, for its owner, a member, anon or a platform admin
  v_subs := array[u4, u3, null, v_admin];
  v_modes := array['user', 'user', 'anon', 'user'];
  for i in 1 .. 4 loop
    j := pg_temp.probe_call(v_subs[i], format('public.search_communities_by_name(%L)', 'community one'), v_modes[i]);
    k := pg_temp.probe_call(v_subs[i], 'public.find_communities_near(0.5038, -150.0)', v_modes[i]);
    perform pg_temp.probe_ok(v_probe, format('hidden C1 is in neither search for subject %s: %s / %s', i, left(j::text, 300), left(k::text, 300)),
      j ->> 'success' = 'true' and k ->> 'success' = 'true'
      and not (jsonb_path_query_array(j, v_ids) ? c1::text) and not (jsonb_path_query_array(k, v_ids) ? c1::text));
  end loop;

  -- test community C4: its owner and a platform admin find it; u3 and anon do not
  v_subs := array[u16, v_admin, u3, null];
  v_modes := array['user', 'user', 'user', 'anon'];
  for i in 1 .. 4 loop
    j := pg_temp.probe_call(v_subs[i], format('public.search_communities_by_name(%L)', 'probe test'), v_modes[i]);
    k := pg_temp.probe_call(v_subs[i], 'public.find_communities_near(0.5, -150.0)', v_modes[i]);
    perform pg_temp.probe_ok(v_probe, format('C4 is in both searches for subject %s exactly when it is u16 or the platform admin: %s / %s',
                                             i, left(j::text, 300), left(k::text, 300)),
      (jsonb_path_query_array(j, v_ids) ? c4::text) = (i <= 2) and (jsonb_path_query_array(k, v_ids) ? c4::text) = (i <= 2));
    j := pg_temp.probe_call(v_subs[i], format('public.get_community_preview(%L::uuid)', c4), v_modes[i]);
    perform pg_temp.probe_ok(v_probe, format('get_community_preview(C4) for subject %s: %s', i, left(j::text, 300)),
      case when i <= 2 then j ->> 'success' = 'true' and j #>> '{community,id}' = c4::text
           else j ->> 'success' = 'false' and j ->> 'code' = 'not_listed' and not (j ? 'raised') end);
  end loop;

  -- search near a point
  j := pg_temp.probe_call(null, 'public.find_communities_near(0.5038, -150.0)', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: a point 0.26 miles from C2''s centre finds C2 only: ' || left(j::text, 500),
    j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = jsonb_build_array(c2));
  k := (select e from jsonb_array_elements(j -> 'communities') e where e ->> 'id' = c2::text);
  perform pg_temp.probe_ok(v_probe, 'C2''s row has the eight keys and distance_miles 0.3: ' || k::text,
    k ?& v_keys and (select count(*) from jsonb_object_keys(k)) = 8
    and (k ->> 'distance_miles')::numeric = 0.3 and (k ->> 'member_count')::int = 1);
  j := pg_temp.probe_call(null, 'public.find_communities_near(0.5275, -150.0)', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: a point 1.9 miles away is inside C2''s 2-mile circle: ' || left(j::text, 300),
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c2));
  j := pg_temp.probe_call(null, 'public.find_communities_near(0.5304, -150.0)', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: a point 2.1 miles away is outside it: ' || left(j::text, 300),
    j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = '[]'::jsonb);
  foreach v_q in array array['anon', 'user'] loop
    j := pg_temp.probe_call(case when v_q = 'user' then u16 end, 'public.find_communities_near(0.5434, -150.0)', v_q);
    perform pg_temp.probe_ok(v_probe, format('%s: a point 3 miles north finds no probe community: %s', v_q, left(j::text, 300)),
      j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = '[]'::jsonb);
  end loop;
  j := pg_temp.probe_call(null, 'public.find_communities_near(0, -179.99)', 'anon');
  k := (select e from jsonb_array_elements(j -> 'communities') e where e ->> 'id' = c6::text);
  perform pg_temp.probe_ok(v_probe, 'anon: C6 (centre (0, 179.99), radius 10) is found from (0, -179.99), 1.4 miles away: ' || left(j::text, 300),
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c6) and (k ->> 'distance_miles')::numeric = 1.4);
  foreach v_q in array array['91, 0', '-90.0001, 0', '0, -181', '0, 180.0001', 'null, 0', '0, null', 'null, null',
                             '''NaN''::double precision, 0', '0, ''Infinity''::double precision'] loop
    j := pg_temp.probe_call(null, format('public.find_communities_near(%s)', v_q), 'anon');
    perform pg_temp.probe_ok(v_probe, format('anon: (%s) answers invalid_area without an exception: %s', v_q, j),
      not (j ? 'raised') and j ->> 'success' = 'false' and j ->> 'code' = 'invalid_area'
      and j ->> 'error' = 'Choose a town or ZIP code');
  end loop;
  j := pg_temp.probe_call(null, 'public.find_communities_near(-90, 180)', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon: the corner (-90, 180) is a valid point: ' || left(j::text, 300),
    j ->> 'success' = 'true');

  perform pg_temp.probe_ok(v_probe, 'no search, preview or refusal above wrote a row (communities, notifications and community_listing_events included)',
    (select coalesce(sum(t.n_tup_ins + t.n_tup_upd + t.n_tup_del), 0) from pg_catalog.pg_stat_xact_user_tables t) = v_writes);

  -- 20 rows at most: 25 more listed communities named 'Probe Many NN' at C2's centre, radius 1
  for n in 1 .. 25 loop
    perform pg_temp.probe_community(110 + n, 'Probe Many ' || lpad(n::text, 2, '0'), u12, true, 'approve');
    perform pg_temp.probe_area(pg_temp.c(110 + n), 'Probe Many Area', 0.5, -150.0, 1);
  end loop;
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', 'probe many'), 'anon');
  k := pg_temp.probe_call(null, 'public.find_communities_near(0.5, -150.0)', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon: 25 matches give 20 rows by name (%s) and near (%s)',
                                           jsonb_array_length(j -> 'communities'), jsonb_array_length(k -> 'communities')),
    jsonb_array_length(j -> 'communities') = 20 and jsonb_array_length(k -> 'communities') = 20);
  perform pg_temp.probe_ok(v_probe, 'by name they come in name order: ' || left(j::text, 300),
    j #>> '{communities,0,name}' = 'Probe Many 01' and j #>> '{communities,19,name}' = 'Probe Many 20');

  -- get_community_preview of merged communities: C3 (private) merged into listed C2 answers 'merged';
  -- C6 merged into hidden C1 and C8 merged into test C4 answer not_listed, except C8 to C4's owner
  perform set_config('request.jwt.claims', '', true);
  update public.communities set archived_at = now(), merged_into_id = c2, merged_at = now() where id = c3;
  update public.communities set archived_at = now(), merged_into_id = c1, merged_at = now() where id = c6;
  update public.communities set archived_at = now(), merged_into_id = c4, merged_at = now() where id = c8;
  foreach v_q in array array['anon', 'user'] loop
    j := pg_temp.probe_call(case when v_q = 'user' then u3 end, format('public.get_community_preview(%L::uuid)', c3), v_q);
    perform pg_temp.probe_ok(v_probe, format('%s: C3 merged into C2 answers merged with C2''s id and name: %s', v_q, j),
      not (j ? 'raised') and j ->> 'success' = 'false' and j ->> 'code' = 'merged'
      and j ->> 'merged_into_id' = c2::text and j ->> 'merged_into_name' = 'Probe Public Two');
  end loop;
  j := pg_temp.probe_call(u4, format('public.get_community_preview(%L::uuid)', c6));
  k := pg_temp.probe_call(null, format('public.get_community_preview(%L::uuid)', c6), 'anon');
  perform pg_temp.probe_ok(v_probe, format('C6 merged into hidden C1 answers not_listed to C1''s owner and anon: %s / %s', j, k),
    j ->> 'code' = 'not_listed' and k ->> 'code' = 'not_listed' and not (j ? 'merged_into_id') and not (k ? 'merged_into_id'));
  j := pg_temp.probe_call(u16, format('public.get_community_preview(%L::uuid)', c8));
  k := pg_temp.probe_call(u3, format('public.get_community_preview(%L::uuid)', c8));
  perform pg_temp.probe_ok(v_probe, format('C8 merged into test C4: merged for C4''s owner, not_listed for u3: %s / %s', j, k),
    j ->> 'code' = 'merged' and j ->> 'merged_into_id' = c4::text and k ->> 'code' = 'not_listed'
    and not (k ? 'merged_into_id'));

  -- an archived C2 is gone from both searches, and C3 merged into it is now not_listed
  update public.communities set archived_at = now() where id = c2;
  j := pg_temp.probe_call(null, format('public.search_communities_by_name(%L)', 'two'), 'anon');
  k := pg_temp.probe_call(null, 'public.find_communities_near(0.5038, -150.0)', 'anon');
  perform pg_temp.probe_ok(v_probe, format('an archived C2 is in neither search: %s / %s', left(j::text, 300), left(k::text, 300)),
    j ->> 'success' = 'true' and k ->> 'success' = 'true'
    and not (jsonb_path_query_array(j, v_ids) ? c2::text) and not (jsonb_path_query_array(k, v_ids) ? c2::text));
  j := pg_temp.probe_call(null, format('public.get_community_preview(%L::uuid)', c3), 'anon');
  perform pg_temp.probe_ok(v_probe, 'C3 merged into the archived C2 answers not_listed: ' || j::text,
    j ->> 'code' = 'not_listed' and not (j ? 'merged_into_id'));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE discovery_search OK' as probe;


-- =============================================================================================================
-- listing_rules (Release 2, 20261021_0021 Blocks 3-8; rulings R-G4, R8, R12 and R21; C2 'Probe Town' at (0.5,
-- -150.0), radius 2). check_community_area: the overlap with distance, itself excluded, nothing far away, invalid
-- areas. create_community_with_area: a hidden creation (no area, no event) that ignores area arguments; needs_area,
-- invalid_area (radius 3, a house number, a missing or out-of-range or NaN centre, a short or long name),
-- reason_required (none, blank, over 300 characters); with a reason, the created_listed event names C2 and the
-- reason, every platform admin gets one announcement bell row with it and no push; a listed 'Seattle 98101' with no
-- overlap and no reason (an empty overlap list); 'open' refused. update_community_access: anon has no EXECUTE; the
-- refusal order (an admin of C1, a non-member, an unknown id; null switches, 'open', a partial or invalid area);
-- set_community_public needs an area to list; needs_area; reason_required; listed with its event, the members'
-- notices (not the owner's, not a pending applicant's), the admins' notices, no push; a repeat changes nothing; a
-- policy change; an area move (area_moved, no member notice); a reason over 300 characters; unlisting; the default
-- community stays listed. get_community_preview: the area keys and is_example on every request.
-- get_platform_communities: the new keys, the newest listing event, the merge keys, merge_proposals, refused to a
-- non-admin.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'listing_rules';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  v_downer uuid := pg_temp.probe_subject('default_owner');
  d uuid := public.default_community_id();
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u6 uuid := pg_temp.u(6);
  u7 uuid := pg_temp.u(7);  u9 uuid := pg_temp.u(9);  u10 uuid := pg_temp.u(10);  u11 uuid := pg_temp.u(11);
  u12 uuid := pg_temp.u(12);  u13 uuid := pg_temp.u(13);  u15 uuid := pg_temp.u(15);  u16 uuid := pg_temp.u(16);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);  c3 uuid := pg_temp.c(3);
  v_ids constant jsonpath := '$.communities[*].id ? (@ starts with "00000000-0000-4000-b000-")';
  v_keys constant text[] := array['area_name', 'area_center_lat', 'area_center_lng', 'area_radius_miles', 'is_test',
                                  'merged_into_id', 'merged_into_name', 'listing_event', 'listing_reason',
                                  'listing_overlaps', 'listing_event_at'];
  v_title constant text := 'Probe Community One changed how people join';
  v_admins uuid[];
  v_members uuid[] := array[pg_temp.u(3), pg_temp.u(5), pg_temp.u(7), pg_temp.u(11)];
  v_new uuid;
  v_far uuid;
  v_ride uuid := pg_temp.r(51);
  v_calls text[];
  v_codes text[];
  v_n bigint;
  v_e bigint;
  i int;
  j jsonb;
  k jsonb;
begin
  perform pg_temp.probe_require_release2(v_probe, 'b');
  perform pg_temp.probe_world();
  perform pg_temp.probe_area(c2, 'Probe Town', 0.5, -150.0, 2);
  v_admins := array(select p.id from public.profiles p where p.is_admin and not coalesce(p.is_banned, false));
  perform pg_temp.probe_ok(v_probe, 'the platform admin and default owner subjects resolve; a platform admin exists',
    v_admin is not null and v_downer is not null and cardinality(v_admins) > 0);

  -- check_community_area
  j := pg_temp.probe_call(u13, 'public.check_community_area(0.52, -150.0, 1)');
  k := (select e from jsonb_array_elements(j -> 'communities') e where e ->> 'id' = c2::text);
  perform pg_temp.probe_ok(v_probe, 'a 1-mile area 1.4 miles from C2''s centre overlaps C2 only: ' || left(j::text, 500),
    j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = jsonb_build_array(c2)
    and (k ->> 'distance_miles')::numeric = 1.4 and (select count(*) from jsonb_object_keys(k)) = 8
    and (k ->> 'member_count')::int = 1);
  j := pg_temp.probe_call(u12, format('public.check_community_area(0.52, -150.0, 1, %L::uuid)', c2));
  perform pg_temp.probe_ok(v_probe, 'C2 is excluded when the check is for C2 itself: ' || left(j::text, 300),
    j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = '[]'::jsonb);
  j := pg_temp.probe_call(u13, 'public.check_community_area(0.5, -140.0, 1)');
  perform pg_temp.probe_ok(v_probe, 'an area far from every probe area overlaps none: ' || left(j::text, 300),
    j ->> 'success' = 'true' and jsonb_path_query_array(j, v_ids) = '[]'::jsonb);
  for i in 1 .. 6 loop
    j := pg_temp.probe_call(u13, 'public.check_community_area(' ||
           (array['0.5, -150.0, 3', 'null, -150.0, 1', '91, 0, 1', '0, -181, 1', '0.5, -150.0, null',
                  '''NaN''::double precision, 0, 1'])[i] || ')');
    perform pg_temp.probe_ok(v_probe, format('check_community_area case %s answers invalid_area: %s', i, j),
      not (j ? 'raised') and j ->> 'success' = 'false' and j ->> 'code' = 'invalid_area');
  end loop;

  -- create_community_with_area: hidden, no area, no listing event
  j := pg_temp.probe_call(u6, format('public.create_community_with_area(%L, null, %L)', 'Probe Hidden Six', 'invite'));
  perform pg_temp.probe_ok(v_probe, 'u6 creates a hidden invite community: ' || j::text, j ->> 'success' = 'true');
  v_new := (j ->> 'community_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'it is hidden, invite, without an area, owned by u6, with no listing event',
    (select not c.is_public and c.join_policy = 'invite' and c.area_name is null and c.area_center_lat is null
            and c.area_center_lng is null and c.area_radius_miles is null
       from public.communities c where c.id = v_new)
    and exists (select 1 from public.community_members m
                 where m.community_id = v_new and m.user_id = u6 and m.role = 'owner' and m.status = 'active')
    and not exists (select 1 from public.community_listing_events e where e.community_id = v_new));
  j := pg_temp.probe_call(u15, format(
    'public.create_community_with_area(p_name => %L, p_listed => false, p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1, p_reason => %L)',
    'Probe Hidden Fifteen', 'Probe Ignored', 'Probe ignored reason'));
  perform pg_temp.probe_ok(v_probe, 'a hidden creation with area arguments succeeds: ' || j::text, j ->> 'success' = 'true');
  perform pg_temp.probe_ok(v_probe, 'and ignores the area and the reason',
    (select not c.is_public and c.area_name is null and c.area_radius_miles is null
       from public.communities c where c.id = (j ->> 'community_id')::uuid)
    and not exists (select 1 from public.community_listing_events e where e.community_id = (j ->> 'community_id')::uuid));

  -- create_community_with_area refusals (u13), none of which creates anything
  v_calls := array[
    '',
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 3', 'Probe Overlap'),
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1', '5412 Probe Ln NW'),
    format(', p_area_name => %L, p_center_lng => -150.0, p_radius_miles => 1', 'Probe Overlap'),
    format(', p_area_name => %L, p_center_lat => 91, p_center_lng => -150.0, p_radius_miles => 1', 'Probe Overlap'),
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -181, p_radius_miles => 1', 'Probe Overlap'),
    format(', p_area_name => %L, p_center_lat => %L::double precision, p_center_lng => -150.0, p_radius_miles => 1', 'Probe Overlap', 'NaN'),
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1', ' P '),
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1', repeat('x', 81)),
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1', 'Probe Overlap'),
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1, p_reason => %L', 'Probe Overlap', '   '),
    format(', p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1, p_reason => %L', 'Probe Overlap', repeat('x', 301))];
  v_codes := array['needs_area', 'invalid_area', 'invalid_area', 'invalid_area', 'invalid_area', 'invalid_area',
                   'invalid_area', 'invalid_area', 'invalid_area', 'reason_required', 'reason_required', 'reason_required'];
  for i in 1 .. cardinality(v_calls) loop
    j := pg_temp.probe_call(u13, format('public.create_community_with_area(p_name => %L, p_join_policy => %L, p_listed => true%s)',
                                        'Probe Listed Thirteen', 'approve', v_calls[i]));
    perform pg_temp.probe_ok(v_probe, format('listed creation case %s answers %s: %s', i, v_codes[i], j),
      not (j ? 'raised') and j ->> 'success' = 'false' and j ->> 'code' = v_codes[i]);
  end loop;
  perform pg_temp.probe_ok(v_probe, 'no refusal created a community',
    not exists (select 1 from public.communities c where c.created_by = u13));
  j := pg_temp.probe_call(u16, format('public.create_community_with_area(p_name => %L, p_reason => %L)',
                                      'Probe Long Reason', repeat('x', 301)));
  perform pg_temp.probe_ok(v_probe, 'a reason over 300 characters is refused even for a hidden creation (R12): ' || j::text,
    j ->> 'code' = 'reason_required' and not exists (select 1 from public.communities c where c.created_by = u16));

  -- listed, overlapping C2, with a reason: the event, the admins' bell rows, no push
  j := pg_temp.probe_call(u13, format(
    'public.create_community_with_area(p_name => %L, p_join_policy => %L, p_listed => true, p_area_name => %L, p_center_lat => 0.52, p_center_lng => -150.0, p_radius_miles => 1, p_reason => %L)',
    'Probe Listed Thirteen', 'approve', '  Probe Overlap  ', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'u13 creates a listed community over C2 with a reason: ' || j::text, j ->> 'success' = 'true');
  v_new := (j ->> 'community_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'it is listed with the trimmed area',
    (select c.is_public and c.join_policy = 'approve' and c.area_name = 'Probe Overlap' and c.area_center_lat = 0.52
            and c.area_center_lng = -150.0 and c.area_radius_miles = 1
       from public.communities c where c.id = v_new));
  perform pg_temp.probe_ok(v_probe, 'one created_listed event with the area, C2 and the reason',
    (select count(*) from public.community_listing_events e where e.community_id = v_new) = 1
    and exists (select 1 from public.community_listing_events e
                 where e.community_id = v_new and e.event = 'created_listed' and e.actor_id = u13
                   and e.area_name = 'Probe Overlap' and e.area_center_lat = 0.52 and e.area_center_lng = -150.0
                   and e.area_radius_miles = 1 and e.overlapping_ids = array[c2] and e.reason = 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'every platform admin got exactly one announcement bell row with the area and the reason, and nobody else',
    (select count(*) from public.notifications n where n.community_id = v_new) = cardinality(v_admins)
    and (select count(distinct n.user_id) from public.notifications n
          where n.community_id = v_new and n.type = 'announcement' and n.user_id = any (v_admins)
            and n.title = 'New community: Probe Listed Thirteen'
            and n.body = 'Created by Probe 513. Listed · Probe Overlap (1 mi). Reason: Probe reason') = cardinality(v_admins));
  perform pg_temp.probe_ok(v_probe, 'no push was queued for those rows',
    not exists (select 1 from public.notification_queue q
                 where q.payload -> 'data' ->> 'notification_id' in
                       (select n.id::text from public.notifications n where n.community_id = v_new)));

  -- listed, no overlap, no reason, a label with a ZIP code after the town (R-G4, R21)
  j := pg_temp.probe_call(u10, format(
    'public.create_community_with_area(p_name => %L, p_listed => true, p_area_name => %L, p_center_lat => 0.5, p_center_lng => -140.0, p_radius_miles => 1)',
    'Probe Far Ten', 'Seattle 98101'));
  perform pg_temp.probe_ok(v_probe, 'u10 creates a listed community with no overlap and no reason: ' || j::text, j ->> 'success' = 'true');
  v_far := (j ->> 'community_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'one created_listed event with an empty overlap list and no reason',
    (select count(*) from public.community_listing_events e where e.community_id = v_far) = 1
    and exists (select 1 from public.community_listing_events e
                 where e.community_id = v_far and e.event = 'created_listed' and e.overlapping_ids = '{}'::uuid[]
                   and e.reason is null and e.area_name = 'Seattle 98101'));
  perform pg_temp.probe_ok(v_probe, 'the admins'' rows say listed without a reason',
    (select count(distinct n.user_id) from public.notifications n
      where n.community_id = v_far and n.user_id = any (v_admins)
        and n.body = 'Created by Probe 510. Listed · Seattle 98101 (1 mi).') = cardinality(v_admins));
  j := pg_temp.probe_call(u13, format('public.create_community_with_area(%L, null, %L)', 'Probe Open', 'open'));
  perform pg_temp.probe_ok(v_probe, 'the open policy is refused with code invalid: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'code' = 'invalid');

  -- update_community_access: refusals in order (ruling R8)
  j := pg_temp.probe_call(null, format('public.update_community_access(%L::uuid, true, %L)', c1, 'approve'), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call update_community_access (42501): ' || j::text,
    coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_call(u5, format('public.update_community_access(%L::uuid, true, %L)', c1, 'approve'));
  k := pg_temp.probe_call(u13, format('public.update_community_access(%L::uuid, true, %L)', c1, 'approve'));
  perform pg_temp.probe_ok(v_probe, format('an admin of C1 and a non-member get not_owner: %s / %s', j, k),
    j ->> 'code' = 'not_owner' and k ->> 'code' = 'not_owner');
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L)', gen_random_uuid(), 'approve'));
  k := pg_temp.probe_call(u4, format('public.update_community_access(null, true, %L)', 'approve'));
  perform pg_temp.probe_ok(v_probe, format('an unknown or null id gets invalid: %s / %s', j, k),
    j ->> 'code' = 'invalid' and k ->> 'code' = 'invalid');
  v_calls := array[format('null, %L', 'approve'), 'true, null', format('true, %L', 'open'),
                   format('true, %L, %L', 'approve', 'Probe One Area'),
                   format('true, %L, %L, 0.48, -150.0, 3', 'approve', 'Probe One Area'),
                   format('true, %L, %L, 0.48, -150.0, 1', 'approve', '12 Probe Street')];
  v_codes := array['invalid', 'invalid', 'invalid', 'invalid_area', 'invalid_area', 'invalid_area'];
  for i in 1 .. cardinality(v_calls) loop
    j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, %s)', c1, v_calls[i]));
    perform pg_temp.probe_ok(v_probe, format('C1''s owner, case %s (%s), gets %s: %s', i, v_calls[i], v_codes[i], j),
      not (j ? 'raised') and j ->> 'success' = 'false' and j ->> 'code' = v_codes[i]);
  end loop;

  -- set_community_public needs an area to list (unlisting does not)
  j := pg_temp.probe_call(v_admin, format('public.set_community_public(%L::uuid, true)', c1));
  perform pg_temp.probe_ok(v_probe, 'set_community_public lists no community without an area: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'code' = 'needs_area'
    and not (select c.is_public from public.communities c where c.id = c1));
  j := pg_temp.probe_call(v_admin, format('public.set_community_public(%L::uuid, false)', c2));
  perform pg_temp.probe_ok(v_probe, 'set_community_public unlists C2 (control): ' || j::text,
    j ->> 'success' = 'true' and not (select c.is_public from public.communities c where c.id = c2));
  j := pg_temp.probe_call(v_admin, format('public.set_community_public(%L::uuid, true)', c2));
  perform pg_temp.probe_ok(v_probe, 'and lists C2 again, which has an area: ' || j::text,
    j ->> 'success' = 'true' and (select c.is_public from public.communities c where c.id = c2));

  -- hidden -> listed
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L)', c1, 'approve'));
  perform pg_temp.probe_ok(v_probe, 'listing C1 without an area gets needs_area: ' || j::text, j ->> 'code' = 'needs_area');
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L, %L, 0.48, -150.0, 1)',
                                     c1, 'approve', 'Probe One Area'));
  perform pg_temp.probe_ok(v_probe, 'listing C1 over C2 without a reason gets reason_required: ' || j::text,
    j ->> 'code' = 'reason_required'
    and (select not c.is_public and c.area_name is null from public.communities c where c.id = c1));
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L, %L, 0.48, -150.0, 1, %L)',
                                     c1, 'approve', 'Probe One Area', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'with a reason C1 is listed: ' || j::text,
    j ->> 'success' = 'true' and j ->> 'changed' = 'true'
    and (select c.is_public and c.join_policy = 'approve' and c.area_name = 'Probe One Area' and c.area_center_lat = 0.48
                and c.area_radius_miles = 1 from public.communities c where c.id = c1));
  perform pg_temp.probe_ok(v_probe, 'one listed event naming C2 and the reason',
    (select count(*) from public.community_listing_events e where e.community_id = c1) = 1
    and exists (select 1 from public.community_listing_events e
                 where e.community_id = c1 and e.event = 'listed' and e.actor_id = u4 and e.overlapping_ids = array[c2]
                   and e.reason = 'Probe reason' and e.area_name = 'Probe One Area' and e.area_radius_miles = 1));
  perform pg_temp.probe_ok(v_probe, 'u3, u5, u7 and u11 each got one "changed how people join" row; u4 and pending u9 none',
    (select count(*) from public.notifications n
      where n.community_id = c1 and n.title = v_title and n.type = 'announcement'
        and n.body = 'Listed · Ask to join.' and n.user_id = any (v_members)) = 4
    and (select count(distinct n.user_id) from public.notifications n
          where n.community_id = c1 and n.title = v_title and n.user_id = any (v_members)) = 4
    and not exists (select 1 from public.notifications n
                     where n.community_id = c1 and n.title = v_title and n.user_id in (u4, u9)));
  perform pg_temp.probe_ok(v_probe, 'every platform admin got one "Now listed" row with the area and the reason',
    (select count(distinct n.user_id) from public.notifications n
      where n.community_id = c1 and n.type = 'announcement' and n.user_id = any (v_admins)
        and n.title = 'Now listed: Probe Community One'
        and n.body = 'Probe One Area (1 mi). Reason: Probe reason') = cardinality(v_admins)
    and (select count(*) from public.notifications n
          where n.community_id = c1 and n.title = 'Now listed: Probe Community One') = cardinality(v_admins));
  perform pg_temp.probe_ok(v_probe, 'no push was queued for those rows (probe_world''s new_ride rows for C1 are not counted)',
    not exists (select 1 from public.notification_queue q
                 where q.payload -> 'data' ->> 'notification_id' in
                       (select n.id::text from public.notifications n
                         where n.community_id = c1
                           and n.title in (v_title, 'Now listed: Probe Community One'))));

  -- the same values again change nothing
  v_n := (select count(*) from public.notifications n where n.community_id = c1);
  v_e := (select count(*) from public.community_listing_events e where e.community_id = c1);
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L, %L, 0.48, -150.0, 1, %L)',
                                     c1, 'approve', 'Probe One Area', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'a repeat answers changed = false and writes no row: ' || j::text,
    j ->> 'success' = 'true' and j ->> 'changed' = 'false'
    and (select count(*) from public.notifications n where n.community_id = c1) = v_n
    and (select count(*) from public.community_listing_events e where e.community_id = c1) = v_e);

  -- a policy change (no area sent): members told, no listing event
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L)', c1, 'invite'));
  perform pg_temp.probe_ok(v_probe, 'C1 becomes invite only: ' || j::text,
    j ->> 'changed' = 'true'
    and (select c.join_policy = 'invite' and c.area_name = 'Probe One Area' from public.communities c where c.id = c1)
    and (select count(*) from public.community_listing_events e where e.community_id = c1) = v_e
    and (select count(*) from public.notifications n
          where n.community_id = c1 and n.title = v_title and n.body = 'Listed · Invite only.'
            and n.user_id = any (v_members)) = 4);

  -- an area move while listed, away from every area: area_moved, no member notice, no reason needed
  v_n := (select count(*) from public.notifications n where n.community_id = c1);
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L, %L, 0.5, -145.0, 2)',
                                     c1, 'invite', 'Probe One Far'));
  perform pg_temp.probe_ok(v_probe, 'C1 moves its area: ' || j::text,
    j ->> 'changed' = 'true'
    and (select c.area_name = 'Probe One Far' and c.area_center_lng = -145.0 and c.area_radius_miles = 2
           from public.communities c where c.id = c1)
    and exists (select 1 from public.community_listing_events e
                 where e.community_id = c1 and e.event = 'area_moved' and e.overlapping_ids = '{}'::uuid[]
                   and e.reason is null and e.area_name = 'Probe One Far')
    and (select count(*) from public.notifications n where n.community_id = c1) = v_n);
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L, %L, 0.48, -150.0, 1)',
                                     c1, 'invite', 'Probe One Area'));
  perform pg_temp.probe_ok(v_probe, 'moving it back over C2 without a reason gets reason_required: ' || j::text,
    j ->> 'code' = 'reason_required');
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, true, %L, null, null, null, null, %L)',
                                     c1, 'approve', repeat('x', 301)));
  perform pg_temp.probe_ok(v_probe, 'a reason over 300 characters gets reason_required with no overlap (R12): ' || j::text,
    j ->> 'code' = 'reason_required'
    and (select c.join_policy from public.communities c where c.id = c1) = 'invite');

  -- unlisting: members told, no listing event; the default community stays listed
  v_e := (select count(*) from public.community_listing_events e where e.community_id = c1);
  j := pg_temp.probe_call(u4, format('public.update_community_access(%L::uuid, false, %L)', c1, 'invite'));
  perform pg_temp.probe_ok(v_probe, 'C1 is hidden again, members told, no listing event: ' || j::text,
    j ->> 'changed' = 'true' and not (select c.is_public from public.communities c where c.id = c1)
    and (select count(*) from public.community_listing_events e where e.community_id = c1) = v_e
    and (select count(*) from public.notifications n
          where n.community_id = c1 and n.title = v_title and n.body = 'Hidden · Invite only.'
            and n.user_id = any (v_members)) = 4);
  j := pg_temp.probe_call(v_downer, format('public.update_community_access(%L::uuid, false, %L)', d,
                                           (select c.join_policy from public.communities c where c.id = d)));
  perform pg_temp.probe_ok(v_probe, 'the default community''s owner cannot unlist it: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'code' = 'default_stays_listed');

  -- get_community_preview: the area keys, and is_example on every request
  perform set_config('request.jwt.claims', '', true);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id)
  values (v_ride, u12, current_date + 2, '09:00', 'Probe pickup', 'Probe destination', 'open', c2);
  j := pg_temp.probe_call(u3, format('public.get_community_preview(%L::uuid)', c2));
  perform pg_temp.probe_ok(v_probe, 'C2''s preview carries its area: ' || left(j::text, 500),
    j ->> 'success' = 'true' and j #>> '{community,area_name}' = 'Probe Town'
    and (j #>> '{community,area_center_lat}')::double precision = 0.5
    and (j #>> '{community,area_center_lng}')::double precision = -150.0
    and (j #>> '{community,area_radius_miles}')::int = 2);
  perform pg_temp.probe_ok(v_probe, 'every request carries is_example; the ride''s is false: ' || (j -> 'requests')::text,
    jsonb_array_length(j -> 'requests') > 0
    and not exists (select 1 from jsonb_array_elements(j -> 'requests') e where jsonb_typeof(e -> 'is_example') <> 'boolean'
                       or not (e ? 'is_example'))
    and exists (select 1 from jsonb_array_elements(j -> 'requests') e
                 where e ->> 'id' = v_ride::text and e -> 'is_example' = 'false'::jsonb));

  -- get_platform_communities: the new keys and the newest listing event
  update public.communities set archived_at = now(), merged_into_id = c2, merged_at = now() where id = c3;
  j := pg_temp.probe_call(v_admin, 'public.get_platform_communities()');
  perform pg_temp.probe_ok(v_probe, 'the platform list answers with an empty merge_proposals list: ' || left(j::text, 300),
    j ->> 'success' = 'true' and j -> 'merge_proposals' = '[]'::jsonb and j ? 'limit_requests');
  perform pg_temp.probe_ok(v_probe, 'every community row has the eleven new keys',
    not exists (select 1 from jsonb_array_elements(j -> 'communities') e where not (e ?& v_keys)));
  k := (select e from jsonb_array_elements(j -> 'communities') e where e ->> 'id' = v_new::text);
  perform pg_temp.probe_ok(v_probe, 'u13''s community: created_listed, the reason, C2 by name, the area: ' || coalesce(k::text, 'null'),
    k ->> 'listing_event' = 'created_listed' and k ->> 'listing_reason' = 'Probe reason'
    and k -> 'listing_overlaps' = '["Probe Public Two"]'::jsonb and k ->> 'listing_event_at' is not null
    and k ->> 'area_name' = 'Probe Overlap' and (k ->> 'area_center_lat')::double precision = 0.52
    and (k ->> 'area_center_lng')::double precision = -150.0 and (k ->> 'area_radius_miles')::int = 1
    and k -> 'is_test' = 'false'::jsonb and k -> 'merged_into_id' = 'null'::jsonb
    and k -> 'merged_into_name' = 'null'::jsonb);
  k := (select e from jsonb_array_elements(j -> 'communities') e where e ->> 'id' = v_far::text);
  perform pg_temp.probe_ok(v_probe, 'u10''s community: an empty overlap list and no reason: ' || coalesce(k::text, 'null'),
    k ->> 'listing_event' = 'created_listed' and k -> 'listing_overlaps' = '[]'::jsonb
    and k -> 'listing_reason' = 'null'::jsonb);
  k := (select e from jsonb_array_elements(j -> 'communities') e where e ->> 'id' = c3::text);
  perform pg_temp.probe_ok(v_probe, 'C3: no listing event, merged into C2 by id and name: ' || coalesce(k::text, 'null'),
    k -> 'listing_event' = 'null'::jsonb and k -> 'listing_overlaps' = 'null'::jsonb
    and k -> 'listing_event_at' = 'null'::jsonb
    and k ->> 'merged_into_id' = c2::text and k ->> 'merged_into_name' = 'Probe Public Two');
  j := pg_temp.probe_call(u4, 'public.get_platform_communities()');
  perform pg_temp.probe_ok(v_probe, 'the platform list is refused to a community owner: ' || j::text,
    j ->> 'success' = 'false');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE listing_rules OK' as probe;

select 'PROBE ALL OK' as probe;
