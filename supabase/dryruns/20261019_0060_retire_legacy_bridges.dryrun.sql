-- DRY RUN of supabase/migrations/20261019_0060_retire_legacy_bridges.sql. NEVER APPLIED. Ends in rollback; contains no commit. Paste verbatim.

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
-- BLOCK 1: public.fill_request_community()   live md5(prosrc) 6241f67fc4e8618ac782b99a7b6d9295
-- (20261017_0001:834-871). Removed: the third branch (default_community_id() for an approved account with no
-- membership row). Deployed md5 must be 9d4cfb03912a7c4a874cffae239ee605.
-- ============================================================================================
create or replace function public.fill_request_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c uuid;
begin
  if new.community_id is not null then
    return new;
  end if;
  select m.community_id into v_c
    from public.profiles p
    join public.community_members m on m.user_id = p.id and m.community_id = p.primary_community_id and m.status = 'active'
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where p.id = new.user_id;
  if v_c is null then
    select m.community_id into v_c
      from public.community_members m
      join public.communities c on c.id = m.community_id and c.archived_at is null
     where m.user_id = new.user_id and m.status = 'active'
     order by m.activated_at nulls last, m.community_id
     limit 1;
  end if;
  if v_c is null then
    raise exception 'Choose a community' using errcode = '42501';
  end if;
  new.community_id := v_c;
  return new;
end
$function$;


-- ============================================================================================
-- BLOCK 2: public.redeem_community_invite(text, text, text)   live md5 f18e6af6f7ca7a53acd193db115b1f27
-- (20261017_0005:1076-1213). Derived from the live definition (D-S1). Removed, exactly once, these 8 lines
-- (the default-community copy into profiles):
--     select c.is_default into v_is_default from public.communities c where c.id = v_inv.community_id;
--     if v_status = 'pending' and v_is_default then
--       update public.profiles
--          set heard_about = coalesce(v_heard, heard_about),
--              join_reason = coalesce(v_reason, join_reason)
--        where id = v_uid;
--     end if;
--     <blank line>
-- The declared v_is_default stays (unused). Grants are kept by CREATE OR REPLACE.
-- Deployed md5 must be 2ec0702dc3a4d400ca2599d0ebb15693.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.redeem_community_invite(text, text, text)'::regprocedure;
  v_cut constant text := E'  select c.is_default into v_is_default from public.communities c where c.id = v_inv.community_id;\n  if v_status = ''pending'' and v_is_default then\n    update public.profiles\n       set heard_about = coalesce(v_heard, heard_about),\n           join_reason = coalesce(v_reason, join_reason)\n     where id = v_uid;\n  end if;\n\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'f18e6af6f7ca7a53acd193db115b1f27' then
    raise exception 'redeem_community_invite is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'redeem_community_invite: the answer copy was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> '2ec0702dc3a4d400ca2599d0ebb15693' then
    raise exception 'redeem_community_invite: unexpected body after the edit';
  end if;
end
$derive$;


-- ============================================================================================
-- BLOCK 3: public.request_to_join_community(uuid, text, text)   live md5 da89c2337d8102d4c284440c534c2b2a
-- (20261017_0005:1226-1327). Derived from the live definition (D-S1). Removed, exactly once, these 7 lines:
--     if v_c.is_default then
--       update public.profiles
--          set heard_about = coalesce(v_heard, heard_about),
--              join_reason = coalesce(v_reason, join_reason)
--        where id = v_uid;
--     end if;
--     <blank line>
-- Deployed md5 must be af9a2f5c560d2d74f35ab979e2f3856c.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.request_to_join_community(uuid, text, text)'::regprocedure;
  v_cut constant text := E'  if v_c.is_default then\n    update public.profiles\n       set heard_about = coalesce(v_heard, heard_about),\n           join_reason = coalesce(v_reason, join_reason)\n     where id = v_uid;\n  end if;\n\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'da89c2337d8102d4c284440c534c2b2a' then
    raise exception 'request_to_join_community is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'request_to_join_community: the answer copy was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'af9a2f5c560d2d74f35ab979e2f3856c' then
    raise exception 'request_to_join_community: unexpected body after the edit';
  end if;
end
$derive$;


-- ============================================================================================
-- BLOCK 4: public.protect_admin_fields()   live md5 48424e05ea801252b83ed8c893db5f4f (20261017_0001:290-312)
-- Changes: approved and application_complete are mirror-only for every end-user JWT (D-S2); approved leaves the
-- admin-guarded list, whose message changes accordingly. Deployed md5 must be d963a013278b5ace77565b8397683bf2.
-- Before this block: confirm no function other than recompute_profile_membership_flags and
-- sync_legacy_approval_to_membership writes either column (both set naars.membership_mirror; read 2026-10-19).
-- ============================================================================================
create or replace function public.protect_admin_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if current_setting('naars.membership_mirror', true) = '1' then
        return new;
    end if;

    -- Phase 5b: approved and application_complete follow memberships only. With the legacy bridges
    -- retired a direct write would leave the mirror wrong, so a write that carries an end-user JWT
    -- (platform admins included) is refused; writes with no JWT (migrations, SQL editor, service role) pass.
    if (old.approved is distinct from new.approved
        or old.application_complete is distinct from new.application_complete)
       and (select auth.uid()) is not null then
        raise exception 'approved and application_complete follow community memberships'
            using errcode = '42501';
    end if;

    if (old.is_admin is distinct from new.is_admin
        or old.is_banned is distinct from new.is_banned
        or old.primary_community_id is distinct from new.primary_community_id
        or old.max_owned_communities is distinct from new.max_owned_communities) then
        if (select auth.uid()) is not null
           and not coalesce((select p.is_admin from public.profiles p where p.id = (select auth.uid())), false) then
            raise exception 'Only admins can modify is_admin, is_banned, primary_community_id or max_owned_communities fields';
        end if;
    end if;
    return new;
end;
$function$;


-- ============================================================================================
-- BLOCK 5: the two legacy bridges (20261017_0001 [call] 1d.4-1d.6)
-- ============================================================================================
drop trigger if exists legacy_application_to_membership on public.profiles;
drop trigger if exists a_sync_legacy_approval_to_membership on public.profiles;
drop function if exists public.legacy_application_to_membership();
drop function if exists public.sync_legacy_approval_to_membership();


-- ============================================================================================
-- BLOCK 6: public.admin_reject_pending_user(uuid)   body unchanged (md5 f5366ee20a4fa51908b3e8173cb1e400)
-- ============================================================================================
revoke execute on function public.admin_reject_pending_user(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 7 (optional, D-S3): the installed build's default-community wrappers that no community build calls
-- ============================================================================================
revoke execute on function public.get_leaderboard(text, integer) from public, anon, authenticated;
revoke execute on function public.get_leaderboard(date, date) from public, anon, authenticated;
revoke execute on function public.send_broadcast_notifications(text, text, text, boolean) from public, anon, authenticated;

-- =============================================================================================================
-- legacy_retired (Phase 5b, 20261019_0060): the bridges are gone; the installed build's application UPDATE and
-- approve raise and change nothing, for platform admins too; a member's own flag write raises; the RPC approve
-- still works; admin_reject_pending_user is closed to clients; an approved account with no membership row cannot
-- post while a member still posts without naming a community; answers given to the default community stay on
-- the membership row and are not copied into profiles.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE legacy_retired OK' as probe;


-- =============================================================================================================
-- legacy_bridges: the installed build's application UPDATE, approve and reject.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE legacy_bridges OK' as probe;


-- =============================================================================================================
-- broadcast_cap (Phase 3, D14): announcement-typed rows a plain member writes do not count; a platform admin's
-- fourth announcement within 24 hours in one community is refused with P0001, as a community admin's already was;
-- the installed admin build's wrapper (default community) is capped the same way.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE broadcast_cap OK' as probe;


-- =============================================================================================================
-- privileged_columns: a non-admin's direct UPDATE of approved, is_admin, is_banned, primary_community_id or
-- max_owned_communities raises; the mirror's write (through an RPC called with a JWT) succeeds; a maintenance
-- write with no JWT succeeds; create_signup_profile re-run by a member leaves approved true.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE privileged_columns OK' as probe;


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


select 'DRYRUN 20261019_0060_retire_legacy_bridges.sql OK' as dryrun;
rollback;
