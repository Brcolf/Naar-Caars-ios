-- DRY RUN of supabase/migrations/20261019_0061_drop_invite_codes.sql. NEVER APPLIED. Ends in rollback; contains no commit. Paste verbatim.

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

begin;

-- ============================================================================================
-- BLOCK 1: public.delete_user_account(uuid)   live md5 135aca113be1ebf5281c03c288ee32c6 (20261017_0004:214-496)
-- Removed, exactly once: "    delete from public.invite_codes where created_by = p_user_id;" (STEP 7).
-- Deployed md5 must be bd886e739d25dbe7497ff6b21c5aa248.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.delete_user_account(uuid)'::regprocedure;
  v_cut constant text := E'    delete from public.invite_codes where created_by = p_user_id;\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> '135aca113be1ebf5281c03c288ee32c6' then
    raise exception 'delete_user_account is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'delete_user_account: the invite_codes statement was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'bd886e739d25dbe7497ff6b21c5aa248' then
    raise exception 'delete_user_account: unexpected body after the edit';
  end if;
end
$derive$;

-- ============================================================================================
-- BLOCK 2: the table
-- ============================================================================================
drop table public.invite_codes;

-- ============================================================================================
-- BLOCK 3: the functions that existed only for it
-- ============================================================================================
drop function if exists public.validate_invite_code(text);
drop function if exists public.mark_invite_code_used(text, text, text, text);
drop function if exists public.guard_invite_code_client_update();
drop function if exists public.handle_invite_code_used();

-- the guard: no function body may still name the table
do $check$
begin
  if exists (select 1 from pg_catalog.pg_proc p
              where p.pronamespace = 'public'::regnamespace and position('invite_codes' in p.prosrc) > 0) then
    raise exception 'a public function still names invite_codes';
  end if;
end
$check$;

-- =============================================================================================================
-- invite_codes_dropped (Phase 5b, 20261019_0061): the table and its four functions are gone, delete_user_account is
-- the expected body and still deletes an account, and no public function names the table.
-- Run account_deletion and short after it as well.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE invite_codes_dropped OK' as probe;


-- =============================================================================================================
-- account_deletion (decision A3): a sole owner with an admin -> the admin is owner; a sole owner with members
-- but no admin -> the community is archived with the deletion and its members are told; a sole owner alone ->
-- archived. In every case the profile deletes cleanly, the user's invites are revoked and their event rows
-- have null user_id and reason.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE account_deletion OK' as probe;


-- =============================================================================================================
-- short: the short probe (§4), after EVERY step. As an existing member: insert a ride and a favor without
-- community_id; a second member claims and completes the ride; the poster writes a 5-star review; the ride's
-- community and three xp_events rows with a community are read back; then the accounts of a probe member, a
-- probe admin and the default community's owner are deleted, each by itself.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE short OK' as probe;


select 'DRYRUN 20261019_0061_drop_invite_codes.sql OK' as dryrun;
rollback;
