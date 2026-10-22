-- DRY RUN of supabase/migrations/20261021_0021_discovery_rpcs.sql. NEVER APPLIED. Ends in rollback; contains no commit. Paste verbatim.

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

begin;

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
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
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
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE listing_rules OK' as probe;


-- =============================================================================================================
-- community_preview (Release 1, 20261021_0001): a visitor of a listed community (u3, not in C2; anon) reads its
-- id, member count, live open requests and newest post, and no address, note, description or gift key; hidden and
-- past requests are left out; a private community (C1), a null id and an unknown id are refused with 'not_listed',
-- to a C1 member too, without an exception; a block in either direction hides the other person's requests and
-- posts (checked before the archive, on a preview that answers success); an archived community is refused.
-- Rows are inserted as the table owner, as in reputation.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE community_preview OK' as probe;


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


select 'DRYRUN 20261021_0021 OK' as dryrun;
rollback;
