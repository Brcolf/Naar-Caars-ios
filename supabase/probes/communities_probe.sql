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

select 'PROBE ALL OK' as probe;
