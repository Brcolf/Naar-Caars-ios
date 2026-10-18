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
-- shows a member every co-member and anon every active member of a public community; XP unchanged; the rides
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
             where r.hidden_at is null and c.is_public and c.archived_at is null);
  v_got := pg_temp.probe_count(null, 'select 1 from public.guest_rides', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon reads %s guest rides, expected %s', v_got, v_exp), v_got = v_exp);
  v_exp := (select count(*) from public.favors f join public.communities c on c.id = f.community_id
             where f.hidden_at is null and c.is_public and c.archived_at is null);
  v_got := pg_temp.probe_count(null, 'select 1 from public.guest_favors', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon reads %s guest favors, expected %s', v_got, v_exp), v_got = v_exp);
  perform pg_temp.probe_ok(v_probe, 'anon reads 0 rides and 0 favors from the tables',
    pg_temp.probe_count(null, 'select 1 from public.rides', 'anon') = 0
    and pg_temp.probe_count(null, 'select 1 from public.favors', 'anon') = 0);
  perform pg_temp.probe_ok(v_probe, 'anon reads no address text from the guest views',
    pg_temp.probe_count(null, $q$select 1 from public.guest_rides where pickup <> '' or destination <> ''$q$, 'anon') = 0
    and pg_temp.probe_count(null, $q$select 1 from public.guest_favors where location <> ''$q$, 'anon') = 0);
  v_exp := (select count(*) from public.town_hall_posts t join public.communities c on c.id = t.community_id
             where t.hidden_at is null and c.is_public and c.archived_at is null);
  v_got := pg_temp.probe_count(null, 'select 1 from public.town_hall_posts', 'anon');
  perform pg_temp.probe_ok(v_probe, format('anon reads %s posts, expected %s', v_got, v_exp), v_got = v_exp);

  v_ids := array(select m.user_id from public.community_members m join public.profiles p on p.id = m.user_id
                  where m.community_id = d and m.status = 'active' and not p.is_banned);
  v_got := pg_temp.probe_count(v_member, format('select 1 from public.public_profiles where id = any (%L::uuid[])', v_ids));
  perform pg_temp.probe_ok(v_probe, format('member reads %s of %s co-members in public_profiles', v_got, cardinality(v_ids)),
    v_got = cardinality(v_ids));
  v_exp := (select count(distinct m.user_id) from public.community_members m
              join public.communities c on c.id = m.community_id
             where m.status = 'active' and c.is_public and c.archived_at is null);
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
-- request there is dropped; restoring reverses both flags; the default community cannot be archived.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'archive';
  d uuid;
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);
  c1 uuid := pg_temp.c(1);
  v_rides_sql text;
  j jsonb;
begin
  perform pg_temp.probe_require(v_probe);
  perform pg_temp.probe_world();
  d := public.default_community_id();
  v_rides_sql := format('select 1 from public.rides where community_id = %L and user_id <> %L', c1, u3);

  perform pg_temp.probe_ok(v_probe, 'before archiving the member reads C1 rides (control)', pg_temp.probe_count(u3, v_rides_sql) >= 1);
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
-- community the caller is not in is refused.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'reputation';
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u5 uuid := pg_temp.u(5);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
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
  j := pg_temp.probe_call(v_member, format('public.get_profile_stats(%L::uuid)', u5));
  perform pg_temp.probe_ok(v_probe, 'a viewer who shares no community gets an empty result: ' || j::text, pg_temp.probe_empty(j));

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


select 'PROBE ALL OK' as probe;
