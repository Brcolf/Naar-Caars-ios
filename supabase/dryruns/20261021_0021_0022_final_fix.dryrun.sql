-- DRY RUN of supabase/migrations/20261021_0021_discovery_rpcs.sql Block 9 and 20261021_0022_community_merge.sql Block 11 (final review I2, I1). NEVER APPLIED. Ends in rollback; contains no commit. Paste verbatim.

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
          (exists (select 1 from pg_catalog.pg_proc
                    where pronamespace = 'public'::regnamespace and proname = 'send_community_broadcast'
                      and prosrc like '%queue_push_notification%')
           -- 20261021_0022 Block 2 (ruling R2): the push moved into post_community_announcement
           or (exists (select 1 from pg_catalog.pg_proc
                        where pronamespace = 'public'::regnamespace and proname = 'send_community_broadcast'
                          and prosrc like '%post_community_announcement%')
               and exists (select 1 from pg_catalog.pg_proc
                            where pronamespace = 'public'::regnamespace and proname = 'post_community_announcement'
                              and prosrc like '%queue_push_notification%')))
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
-- BLOCK 9: public.overlapping_listed_communities(...)   live md5 6bba53d116095861adb7ff5e24541780 (Block 3)
-- Final review I2: the default community (Test Community, example content only, spec 4.11) is never an overlap, so
-- a real owner in its area is not asked for a reason and the nearby check does not point at it. One predicate,
-- `and not c.is_default`; find_communities_near and search still return it. Same signature, same ACL (internal).
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
         and not c.is_default
    ) d
   where d.miles < d.area_radius_miles + p_radius_miles
     and public.can_discover_community(d.id)
   order by d.miles, d.name, d.id
   limit 20;
$function$;

revoke all on function public.overlapping_listed_communities(double precision, double precision, integer, uuid)
  from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 11: public.propose_community_merge(uuid, uuid, uuid, text)   live md5 71a9052450623653c2f6ffc0bac5cd8a
-- (Block 5). Final review I1: a proposal pushes the other community's owners, so it now has limits. Refused with
-- code invalid when the caller and an active owner of the other community have blocked each other (either way);
-- with code recently_declined when a proposal between the two was withdrawn in the last 24 hours (either
-- direction); with code rate_limited when the caller has made 3 proposals in the last 24 hours (a per-caller
-- advisory lock keeps two calls from passing the count together). Same signature, same ACL.
-- ============================================================================================
create or replace function public.propose_community_merge(
  p_community_id uuid,
  p_other_id uuid,
  p_survivor_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_from record;
  v_other record;
  v_survivor_name text;
  v_body text;
  v_id uuid;
  v_owner uuid;
begin
  if v_uid is null or not coalesce(public.my_community_role(p_community_id) = 'owner', false) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;
  if p_other_id is null or p_other_id = p_community_id then
    return jsonb_build_object('success', false, 'error', 'Choose another community to merge with', 'code', 'invalid');
  end if;

  -- One proposal at a time per caller (the daily cap below), then per community, smaller id first.
  perform pg_advisory_xact_lock(hashtextextended('community_merge_proposer:' || v_uid::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('community_merge:' || least(p_community_id, p_other_id)::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('community_merge:' || greatest(p_community_id, p_other_id)::text, 0));

  update public.community_merge_proposals
     set status = 'expired'
   where status = 'pending' and expires_at <= now()
     and (from_community_id in (p_community_id, p_other_id) or to_community_id in (p_community_id, p_other_id));

  if p_survivor_id is null or p_survivor_id not in (p_community_id, p_other_id)
     or char_length(coalesce(v_note, '')) > 300 then
    return jsonb_build_object('success', false, 'error', 'Choose another community to merge with', 'code', 'invalid');
  end if;

  select c.name, c.is_default into v_from from public.communities c where c.id = p_community_id;
  select c.name, c.is_default, c.archived_at, c.merged_into_id into v_other
    from public.communities c where c.id = p_other_id;
  if not found or v_other.archived_at is not null or v_other.merged_into_id is not null then
    return jsonb_build_object('success', false, 'error', 'Choose another community to merge with', 'code', 'invalid');
  end if;
  -- A block between the caller and an owner of the other community, either way: no proposal, no notice (the
  -- answer does not say why).
  if exists (select 1
               from public.community_members m
               join public.blocked_users b
                 on (b.blocker_id = v_uid and b.blocked_id = m.user_id)
                 or (b.blocker_id = m.user_id and b.blocked_id = v_uid)
              where m.community_id = p_other_id and m.status = 'active' and m.role = 'owner') then
    return jsonb_build_object('success', false, 'error', 'Choose another community to merge with', 'code', 'invalid');
  end if;
  if v_from.is_default or v_other.is_default then
    return jsonb_build_object('success', false, 'error', 'The default community cannot be merged',
                              'code', 'default_community');
  end if;
  if exists (select 1 from public.community_merge_proposals p
              where p.status = 'pending'
                and (p.from_community_id in (p_community_id, p_other_id)
                     or p.to_community_id in (p_community_id, p_other_id))) then
    return jsonb_build_object('success', false,
                              'error', 'A merge proposal is already open for one of these communities',
                              'code', 'merge_pending');
  end if;
  if exists (select 1 from public.community_merge_proposals p
              where p.status = 'declined' and p.decided_at > now() - interval '7 days'
                and ((p.from_community_id = p_community_id and p.to_community_id = p_other_id)
                     or (p.from_community_id = p_other_id and p.to_community_id = p_community_id))) then
    return jsonb_build_object('success', false, 'error', 'This merge was declined in the last 7 days',
                              'code', 'recently_declined');
  end if;
  if exists (select 1 from public.community_merge_proposals p
              where p.status = 'withdrawn' and p.decided_at > now() - interval '24 hours'
                and ((p.from_community_id = p_community_id and p.to_community_id = p_other_id)
                     or (p.from_community_id = p_other_id and p.to_community_id = p_community_id))) then
    return jsonb_build_object('success', false, 'error', 'This merge was withdrawn in the last 24 hours',
                              'code', 'recently_declined');
  end if;
  if (select count(*) from public.community_merge_proposals p
       where p.proposed_by = v_uid and p.created_at > now() - interval '24 hours') >= 3 then
    return jsonb_build_object('success', false, 'error', 'Too many merge proposals today. Try again tomorrow',
                              'code', 'rate_limited');
  end if;

  insert into public.community_merge_proposals (from_community_id, to_community_id, survivor_community_id,
                                                proposed_by, note)
  values (p_community_id, p_other_id, p_survivor_id, v_uid, v_note)
  returning id into v_id;

  v_survivor_name := case when p_survivor_id = p_community_id then v_from.name else v_other.name end;
  v_body := v_from.name || ' proposes making ' || v_from.name || ' and ' || v_other.name || ' one community: '
            || v_survivor_name || '. Open Manage in ' || v_other.name || ' to accept or decline.';
  for v_owner in
    select m.user_id
      from public.community_members m
      join public.profiles p on p.id = m.user_id
     where m.community_id = p_other_id and m.status = 'active' and m.role = 'owner'
       and not coalesce(p.is_banned, false) and m.user_id <> v_uid
  loop
    perform public.notify_user_in_community(
      v_owner, 'announcement', 'Merge proposal from ' || v_from.name, v_body, p_other_id, true, '{}'::jsonb, v_uid
    );
  end loop;

  return jsonb_build_object('success', true, 'proposal_id', v_id);
end
$function$;

revoke all on function public.propose_community_merge(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.propose_community_merge(uuid, uuid, uuid, text) to authenticated, service_role;


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
-- non-admin. Block 9 (final review I2): the default community, given a probe area for the transaction, is never an
-- overlap (check_community_area, and a listed creation inside its area needs no reason) while find_communities_near
-- still finds it there.
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

  -- the default community is never an overlap (I2): a 10-mile probe area for it, away from every live area
  perform pg_temp.probe_area(d, 'Probe Default Area', 0.5, -160.0, 10);
  perform pg_temp.probe_ok(v_probe, 'the default community is listed and unarchived (the case is not vacuous)',
    exists (select 1 from public.communities c where c.id = d and c.is_public and c.archived_at is null
              and c.area_radius_miles = 10));
  j := pg_temp.probe_call(u13, 'public.find_communities_near(0.52, -160.0)');
  perform pg_temp.probe_ok(v_probe, 'control: find_communities_near finds the default community in its area: '
                                    || left(j::text, 300),
    jsonb_path_exists(j, '$.communities[*].id ? (@ == $d)', jsonb_build_object('d', d)));
  j := pg_temp.probe_call(u13, 'public.check_community_area(0.52, -160.0, 2)');
  perform pg_temp.probe_ok(v_probe, 'check_community_area inside the default community''s area returns nothing: '
                                    || left(j::text, 300),
    j ->> 'success' = 'true' and j -> 'communities' = '[]'::jsonb);
  j := pg_temp.probe_call(u16, format(
    'public.create_community_with_area(p_name => %L, p_listed => true, p_area_name => %L, p_center_lat => 0.52, p_center_lng => -160.0, p_radius_miles => 2)',
    'Probe Beside Default', 'Probe Default Town'));
  perform pg_temp.probe_ok(v_probe, 'a listed creation inside the default community''s area needs no reason: ' || j::text,
    j ->> 'success' = 'true'
    and exists (select 1 from public.community_listing_events e
                 where e.community_id = (j ->> 'community_id')::uuid and e.event = 'created_listed'
                   and e.overlapping_ids = '{}'::uuid[] and e.reason is null));

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
  perform pg_temp.probe_ok(v_probe, 'the platform list answers with a merge_proposals list and no probe proposal: '
                                    || left(j::text, 300),
    j ->> 'success' = 'true' and jsonb_typeof(j -> 'merge_proposals') = 'array' and j ? 'limit_requests'
    and not exists (select 1 from jsonb_array_elements(j -> 'merge_proposals') e
                     where e ->> 'from_id' like '00000000-0000-4000-b000-%'
                        or e ->> 'to_id' like '00000000-0000-4000-b000-%'));
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
-- community_merge (Release 2, 20261021_0022 Blocks 1-10; rulings R-G1, R1, R2, R13-R17, R23). EXECUTE, definer and
-- volatility of every File C function; search_merge_targets (owner only, fewer than 2 characters, a hidden community
-- by its exact name only and without its area, a listed one by part of its name with its area, exact matches first,
-- no default, no self, a test community only for its member); proposals (not_owner, merge_pending, the bell row and
-- push for the other owner, incoming / outgoing, decline with its notice, recently_declined in both directions and
-- after 8 days, withdraw with its notice, expiry, closed answers); the merge of C3 (owner u14; u3 admin, u7 active
-- with an open ride, u5 pending, u11 active and muted with C3 as primary, u12 a member) into C2 (owner u12; u3 a
-- member, u7 removed): roles, pending, mute, removed stays removed with the ride unwound, content and history in C2
-- with the completed ride's updated_at kept, xp, notifications and reports moved, the community report kept on C3,
-- the invite revoked, C3 archived and merged with its events, primary community (R1), the applicant notice (R14),
-- the archive notice for u7 (R15), the system announcement and its pushes (not the accepter, not the muted), the
-- D14 cap not counting it, get_my_community_merges, the preview, the platform list, no restore (R16); the default
-- community refused; one owner of both (C6 into C2); an archived side (C1 into C5) withdrawn; a stale pending
-- proposal reads 'expired' in the platform list; merge_communities closed to clients. Block 11 (final review I1):
-- re-proposing within 24 hours of a withdrawal answers recently_declined in both directions, a caller's fourth
-- proposal within 24 hours answers rate_limited and writes nothing, and a block between the caller and an owner of
-- the other community (either way) answers invalid with no proposal and no notice (an admin's block does not).
-- =============================================================================================================
savepoint probe;
do $probe$
declare
  v_probe constant text := 'community_merge';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  d uuid := public.default_community_id();
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);
  u11 uuid := pg_temp.u(11);  u12 uuid := pg_temp.u(12);  u13 uuid := pg_temp.u(13);  u14 uuid := pg_temp.u(14);
  u16 uuid := pg_temp.u(16);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);  c3 uuid := pg_temp.c(3);
  c4 uuid;  c5 uuid;  c6 uuid;  c7 uuid;  c8 uuid;  c9 uuid;  c10 uuid;
  v_ids constant jsonpath := '$.communities[*].id ? (@ starts with "00000000-0000-4000-b000-")';
  v_open_ride uuid := pg_temp.r(61);
  v_done_ride uuid := pg_temp.r(62);
  v_done_at constant timestamptz := now() - interval '10 days';
  v_c3_joined timestamptz;
  v_c3_activated timestamptz;
  v_favor uuid;
  v_post uuid;
  v_sys_post uuid;
  v_comment uuid;
  v_post_report uuid;
  v_community_report uuid;
  v_first uuid;
  v_prop uuid;
  v_nid uuid;
  v_c1_members bigint;
  v_names text;
  v_fn text;
  n int;
  j jsonb;
  k jsonb;
begin
  perform pg_temp.probe_require_release2(v_probe, 'c');
  perform pg_temp.probe_world();
  perform set_config('request.jwt.claims', '', true);

  -- EXECUTE (ruling R-G1), definer, search_path, volatility
  foreach v_fn in array array['public.search_merge_targets(uuid, text)',
      'public.propose_community_merge(uuid, uuid, uuid, text)', 'public.get_community_merge_proposal(uuid)',
      'public.respond_to_community_merge(uuid, boolean)', 'public.withdraw_community_merge(uuid)',
      'public.get_my_community_merges()', 'public.send_community_broadcast(uuid, text, text, boolean, text)',
      'public.get_platform_communities()', 'public.unarchive_community(uuid)'] loop
    perform pg_temp.probe_ok(v_probe, v_fn || ': EXECUTE for authenticated and service_role, none for anon or public',
      not has_function_privilege('anon', v_fn, 'execute')
      and has_function_privilege('authenticated', v_fn, 'execute')
      and has_function_privilege('service_role', v_fn, 'execute')
      and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                       where p.oid = v_fn::regprocedure and a.grantee = 0));
  end loop;
  foreach v_fn in array array['public.post_community_announcement(uuid, uuid, text, text, boolean, text, text, jsonb)',
      'public.merge_communities(uuid, uuid)'] loop
    perform pg_temp.probe_ok(v_probe, v_fn || ': EXECUTE for service_role only (no anon, authenticated or public)',
      not has_function_privilege('anon', v_fn, 'execute')
      and not has_function_privilege('authenticated', v_fn, 'execute')
      and has_function_privilege('service_role', v_fn, 'execute')
      and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                       where p.oid = v_fn::regprocedure and a.grantee = 0));
  end loop;
  perform pg_temp.probe_ok(v_probe, 'the eleven File C functions are security definer with search_path ""',
    (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in ('post_community_announcement', 'send_community_broadcast', 'merge_communities',
                          'search_merge_targets', 'propose_community_merge', 'get_community_merge_proposal',
                          'respond_to_community_merge', 'withdraw_community_merge', 'get_my_community_merges',
                          'get_platform_communities', 'unarchive_community')
        and p.prosecdef and p.proconfig = array['search_path=""']) = 11);
  perform pg_temp.probe_ok(v_probe, 'the three read functions are stable',
    (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in ('search_merge_targets', 'get_community_merge_proposal', 'get_my_community_merges')
        and p.provolatile = 's') = 3);

  -- The world: C2 listed with an area, C1 hidden with an area, C4 a listed test community (owner u16, u12 a
  -- member), C8 listed 'A Probe Public Two' (sorts before C2). C3's members: u14 owner, u3 admin, u7, u11 (muted,
  -- C3 primary, activated after C1 so the archive's own recompute would choose C1), u12, and u5 pending. C2: u12
  -- owner, u3 member, u7 removed.
  perform pg_temp.probe_area(c2, 'Probe Town', 0.5, -150.0, 2);
  perform pg_temp.probe_area(c1, 'Probe Hidden Area', 0.5, -149.0, 1);
  c4 := pg_temp.probe_test_community(4, u16);
  perform pg_temp.probe_member(c4, u12, 'member', 'active', 3);
  c8 := pg_temp.probe_community(8, 'A Probe Public Two', u16, true, 'approve');
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.probe_member(c2, u3, 'member', 'active', 6);
  insert into public.community_members (community_id, user_id, role, status, joined_at, activated_at, ended_at,
                                        removal_reason)
  values (c2, u7, 'member', 'removed', now() - interval '20 days', now() - interval '20 days',
          now() - interval '5 days', 'communities probe');
  perform pg_temp.probe_member(c3, u3, 'admin', 'active', 7);
  perform pg_temp.probe_member(c3, u7, 'member', 'active', 6);
  perform pg_temp.probe_member(c3, u12, 'member', 'active', 4);
  perform pg_temp.probe_member(c3, u11, 'member', 'active', 2);
  perform pg_temp.probe_member(c3, u5, 'member', 'pending', 1);
  update public.community_members set notifications_muted = true where community_id = c3 and user_id = u11;
  update public.community_members set heard_about = 'Probe merge heard', join_reason = 'Probe merge reason'
   where community_id = c3 and user_id = u5;
  update public.profiles set primary_community_id = c3 where id = u11;
  select m.joined_at, m.activated_at into v_c3_joined, v_c3_activated
    from public.community_members m where m.community_id = c3 and m.user_id = u11;
  perform pg_temp.probe_ok(v_probe, 'u11''s primary community is C3 and C1 is activated first (R1 setup)',
    (select primary_community_id from public.profiles where id = u11) = c3
    and (select activated_at from public.community_members where community_id = c1 and user_id = u11) < v_c3_activated);

  -- C3's content: u7's open ride, a completed ride (updated 10 days ago) with its xp, a favor claimed by u11
  -- (confirmed, R17), a post with a comment, a report on the post, a report on C3 itself, a live invite
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id)
  values (v_open_ride, u7, current_date + 4, '09:00', 'Probe pickup', 'Probe destination', 'open', c3);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id,
                            updated_at)
  values (v_done_ride, u14, current_date - 11, '10:00', 'Probe pickup', 'Probe destination', 'completed', u3, c3,
          v_done_at);
  insert into public.xp_events (user_id, amount, source_type, source_id, description, community_id)
  values (u3, 5, 'ride_fulfilled', v_done_ride, 'communities probe', c3)
  on conflict (source_type, source_id) do nothing;
  insert into public.favors (user_id, title, description, location, date, status, claimed_by, community_id)
  values (u14, 'Probe favor', 'communities probe', 'Probe location', current_date + 2, 'confirmed', u11, c3)
  returning id into v_favor;
  v_post := pg_temp.probe_post(61, u14, c3);
  insert into public.town_hall_comments (post_id, user_id, content)
  values (v_post, u3, 'communities probe comment') returning id into v_comment;
  insert into public.reports (reporter_id, reported_post_id, report_type, description)
  values (u12, v_post, 'other', 'communities probe') returning id into v_post_report;
  insert into public.reports (reporter_id, reported_community_id, report_type, description)
  values (u13, c3, 'other', 'communities probe') returning id into v_community_report;
  j := pg_temp.probe_call(u14, format($q$public.create_community_invite(%L::uuid, 5, now() + interval '7 days')$q$, c3));
  perform pg_temp.probe_ok(v_probe, 'C3''s owner creates an invite: ' || (j - 'code')::text,
    not pg_temp.probe_refused(j)
    and (select count(*) from public.community_invites where community_id = c3 and revoked_at is null) = 1);
  perform pg_temp.probe_ok(v_probe, 'the post report belongs to C3; the community report has no community',
    (select community_id from public.reports where id = v_post_report) = c3
    and (select community_id from public.reports where id = v_community_report) is null);

  -- search_merge_targets
  j := pg_temp.probe_call(u3, format('public.search_merge_targets(%L::uuid, %L)', c2, 'Probe'));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: a member of C2 is not its owner: ' || j::text,
    j ->> 'code' = 'not_owner');
  j := pg_temp.probe_call(u12, format('public.search_merge_targets(%L::uuid, %L)', c2, ' P '));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: one character answers an empty list: ' || j::text,
    j ->> 'success' = 'true' and j -> 'communities' = '[]'::jsonb);
  j := pg_temp.probe_call(u12, format('public.search_merge_targets(%L::uuid, %L)', c2, 'Community Thr'));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: part of a hidden name finds nothing hidden: ' || j::text,
    j ->> 'success' = 'true' and not jsonb_path_exists(j, '$.communities[*].id ? (@ == $a || @ == $b)',
                                                   jsonb_build_object('a', c3, 'b', c1)));
  j := pg_temp.probe_call(u12, format('public.search_merge_targets(%L::uuid, %L)', c2, '  probe community THREE '));
  k := j #> '{communities,0}';
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: a hidden community by its exact name, any case: ' || j::text,
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c3)
    and (select array_agg(x order by x) from jsonb_object_keys(k) x)
        = array['area_name', 'id', 'is_public', 'join_policy', 'member_count', 'name']
    and k -> 'is_public' = 'false'::jsonb and k ->> 'join_policy' = 'invite' and (k ->> 'member_count')::int = 5
    and k -> 'area_name' = 'null'::jsonb);
  j := pg_temp.probe_call(u14, format('public.search_merge_targets(%L::uuid, %L)', c3, 'Probe Community One'));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: hidden C1 by its exact name, without its area (R23): ' || j::text,
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c1) and j #> '{communities,0,area_name}' = 'null'::jsonb);
  j := pg_temp.probe_call(u14, format('public.search_merge_targets(%L::uuid, %L)', c3, 'probe public two'));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: listed C2 (exact) before C8 (part), C2 with its area: ' || j::text,
    jsonb_path_query_array(j, v_ids) = jsonb_build_array(c2, c8)
    and j #>> '{communities,0,area_name}' = 'Probe Town' and (j #>> '{communities,0,member_count}')::int = 2
    and j #> '{communities,0,is_public}' = 'true'::jsonb);
  j := pg_temp.probe_call(u14, format('public.search_merge_targets(%L::uuid, %L)', c3, 'Probe Test'));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: test C4 is not offered to a non-member: ' || j::text,
    j ->> 'success' = 'true' and not (jsonb_path_query_array(j, v_ids) @> jsonb_build_array(c4)));
  j := pg_temp.probe_call(u12, format('public.search_merge_targets(%L::uuid, %L)', c2, 'Probe Test'));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: test C4 is offered to its member: ' || j::text,
    jsonb_path_query_array(j, v_ids) @> jsonb_build_array(c4));
  j := pg_temp.probe_call(u14, format('public.search_merge_targets(%L::uuid, %L)', c3,
                                      (select name from public.communities where id = d)));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: never the default community: ' || left(j::text, 300),
    j ->> 'success' = 'true'
    and not jsonb_path_exists(j, '$.communities[*].id ? (@ == $d)', jsonb_build_object('d', d)));
  j := pg_temp.probe_call(u14, format('public.search_merge_targets(%L::uuid, %L)', c3, 'Probe Community Three'));
  perform pg_temp.probe_ok(v_probe, 'search_merge_targets: never the caller''s own community: ' || j::text,
    j ->> 'success' = 'true' and not (jsonb_path_query_array(j, v_ids) @> jsonb_build_array(c3)));

  -- proposals: refusals, the first proposal and its notice
  j := pg_temp.probe_call(u3, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid, %L)',
                                     c2, c3, c2, 'Probe note'));
  perform pg_temp.probe_ok(v_probe, 'u3 (a member of C2) cannot propose for C2: ' || j::text, j ->> 'code' = 'not_owner');
  foreach v_fn in array array[format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c2, c2),
      format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c1),
      format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid, %L)', c2, c3, c2, repeat('n', 301)),
      format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, gen_random_uuid(), c2)] loop
    j := pg_temp.probe_call(u12, v_fn);
    perform pg_temp.probe_ok(v_probe, 'invalid proposal refused: ' || j::text, j ->> 'code' = 'invalid');
  end loop;
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid, %L)',
                                      c2, c3, c2, 'Probe note'));
  v_first := (j ->> 'proposal_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'u12 proposes C2 and C3 as C2: ' || j::text,
    j ->> 'success' = 'true' and v_first is not null
    and exists (select 1 from public.community_merge_proposals
                 where id = v_first and from_community_id = c2 and to_community_id = c3 and survivor_community_id = c2
                   and proposed_by = u12 and note = 'Probe note' and status = 'pending'
                   and expires_at = now() + interval '7 days'));
  j := pg_temp.probe_call(u14, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c3, c1, c3));
  perform pg_temp.probe_ok(v_probe, 'a second proposal involving C3 is refused: ' || j::text,
    j ->> 'code' = 'merge_pending');
  v_nid := (select id from public.notifications
             where user_id = u14 and type = 'announcement' and title = 'Merge proposal from Probe Public Two');
  perform pg_temp.probe_ok(v_probe, 'u14 has one announcement bell row and one push for the proposal',
    (select count(*) from public.notifications
      where user_id = u14 and type = 'announcement' and title = 'Merge proposal from Probe Public Two') = 1
    and exists (select 1 from public.notifications
                 where id = v_nid and community_id = c3 and source_user_id = u12
                   and body = 'Probe Public Two proposes making Probe Public Two and Probe Community Three one '
                              || 'community: Probe Public Two. Open Manage in Probe Community Three to accept or decline.')
    and (select count(*) from public.notification_queue q
          where q.recipient_user_id = u14 and q.notification_type = 'announcement'
            and q.payload ->> 'title' = 'Merge proposal from Probe Public Two') = 1
    and exists (select 1 from public.notification_queue q
                 where q.recipient_user_id = u14 and q.payload -> 'data' ->> 'notification_id' = v_nid::text
                   and q.payload -> 'data' ->> 'community_id' = c3::text));
  perform pg_temp.probe_ok(v_probe, 'nobody else is told of the proposal',
    (select count(*) from public.notifications where title = 'Merge proposal from Probe Public Two') = 1);

  j := pg_temp.probe_call(u14, format('public.get_community_merge_proposal(%L::uuid)', c3));
  k := j -> 'proposal';
  perform pg_temp.probe_ok(v_probe, 'C3''s owner sees the proposal as incoming: ' || j::text,
    j ->> 'success' = 'true' and k ->> 'id' = v_first::text and k ->> 'direction' = 'incoming'
    and k #>> '{from,id}' = c2::text and k #>> '{from,name}' = 'Probe Public Two'
    and k #>> '{from,join_policy}' = 'approve' and (k #>> '{from,member_count}')::int = 2
    and k #>> '{to,id}' = c3::text and (k #>> '{to,member_count}')::int = 5
    and k ->> 'survivor_id' = c2::text and k ->> 'note' = 'Probe note' and k ->> 'proposed_by_name' = 'Probe 512'
    and k ->> 'created_at' is not null and k ->> 'expires_at' is not null
    and (select count(*) from jsonb_object_keys(k)) = 9);
  j := pg_temp.probe_call(u12, format('public.get_community_merge_proposal(%L::uuid)', c2));
  perform pg_temp.probe_ok(v_probe, 'C2''s owner sees it as outgoing: ' || j::text,
    j #>> '{proposal,id}' = v_first::text and j #>> '{proposal,direction}' = 'outgoing');
  j := pg_temp.probe_call(v_admin, format('public.get_community_merge_proposal(%L::uuid)', c3));
  perform pg_temp.probe_ok(v_probe, 'a platform admin sees it: ' || j::text, j #>> '{proposal,id}' = v_first::text);
  j := pg_temp.probe_call(u3, format('public.get_community_merge_proposal(%L::uuid)', c2));
  k := pg_temp.probe_call(u3, format('public.get_community_merge_proposal(%L::uuid)', c3));
  perform pg_temp.probe_ok(v_probe, 'u3 (member of C2, admin of C3) reads neither: ' || j::text || ' / ' || k::text,
    j ->> 'code' = 'not_owner' and k ->> 'code' = 'not_owner');
  j := pg_temp.probe_call(u3, format('public.respond_to_community_merge(%L::uuid, true)', v_first));
  k := pg_temp.probe_call(u12, format('public.respond_to_community_merge(%L::uuid, true)', v_first));
  perform pg_temp.probe_ok(v_probe, 'only an owner of C3 answers (u3 admin, u12 member of C3): ' || j::text || ' / ' || k::text,
    j ->> 'code' = 'not_owner' and k ->> 'code' = 'not_owner'
    and (select status from public.community_merge_proposals where id = v_first) = 'pending');

  -- decline, recently_declined, 8 days later
  j := pg_temp.probe_call(u14, format('public.respond_to_community_merge(%L::uuid, false)', v_first));
  perform pg_temp.probe_ok(v_probe, 'u14 declines: ' || j::text,
    j ->> 'success' = 'true'
    and exists (select 1 from public.community_merge_proposals
                 where id = v_first and status = 'declined' and decided_by = u14 and decided_at is not null));
  perform pg_temp.probe_ok(v_probe, 'u12 gets one bell row for the decline, no push',
    (select count(*) from public.notifications
      where user_id = u12 and type = 'announcement' and title = 'Merge declined' and community_id = c2
        and body = 'Probe Community Three declined merging with Probe Public Two.') = 1
    and not exists (select 1 from public.notification_queue where payload ->> 'title' = 'Merge declined'));
  j := pg_temp.probe_call(u14, format('public.respond_to_community_merge(%L::uuid, true)', v_first));
  perform pg_temp.probe_ok(v_probe, 'a declined proposal cannot be accepted: ' || j::text,
    j ->> 'code' = 'proposal_closed');
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c2));
  k := pg_temp.probe_call(u14, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c3, c2, c2));
  perform pg_temp.probe_ok(v_probe, 'declined within 7 days, either direction: ' || j::text || ' / ' || k::text,
    j ->> 'code' = 'recently_declined' and k ->> 'code' = 'recently_declined');
  update public.community_merge_proposals set decided_at = now() - interval '8 days' where id = v_first;
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c2));
  v_prop := (j ->> 'proposal_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'eight days after the decline the proposal is accepted: ' || j::text,
    j ->> 'success' = 'true' and v_prop is not null);

  -- withdraw
  j := pg_temp.probe_call(u3, format('public.withdraw_community_merge(%L::uuid)', v_prop));
  perform pg_temp.probe_ok(v_probe, 'u3 cannot withdraw: ' || j::text, j ->> 'code' = 'not_owner');
  j := pg_temp.probe_call(u14, format('public.withdraw_community_merge(%L::uuid)', v_prop));
  perform pg_temp.probe_ok(v_probe, 'C3''s owner withdraws: ' || j::text,
    j ->> 'success' = 'true'
    and exists (select 1 from public.community_merge_proposals
                 where id = v_prop and status = 'withdrawn' and decided_by = u14 and decided_at is not null));
  perform pg_temp.probe_ok(v_probe, 'u12 gets one bell row for the withdrawal, no push',
    (select count(*) from public.notifications
      where user_id = u12 and type = 'announcement' and title = 'Merge proposal withdrawn' and community_id = c2
        and body = 'Probe Community Three withdrew the merge proposal.') = 1
    and not exists (select 1 from public.notification_queue where payload ->> 'title' = 'Merge proposal withdrawn'));
  j := pg_temp.probe_call(u14, format('public.withdraw_community_merge(%L::uuid)', v_prop));
  perform pg_temp.probe_ok(v_probe, 'a withdrawn proposal cannot be withdrawn again: ' || j::text,
    j ->> 'code' = 'proposal_closed');
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c2));
  k := pg_temp.probe_call(u14, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c3, c2, c2));
  perform pg_temp.probe_ok(v_probe, 'withdrawn within 24 hours, either direction (I1): ' || j::text || ' / ' || k::text,
    j ->> 'code' = 'recently_declined' and k ->> 'code' = 'recently_declined'
    and (select count(*) from public.community_merge_proposals
          where from_community_id in (c2, c3) and to_community_id in (c2, c3)) = 2);
  update public.community_merge_proposals set decided_at = now() - interval '25 hours' where id = v_prop;

  -- expiry
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c2));
  v_prop := (j ->> 'proposal_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a third proposal: ' || j::text, v_prop is not null);
  update public.community_merge_proposals set expires_at = now() - interval '1 minute' where id = v_prop;
  j := pg_temp.probe_call(u14, format('public.get_community_merge_proposal(%L::uuid)', c3));
  perform pg_temp.probe_ok(v_probe, 'an expired proposal is not shown: ' || j::text,
    j ->> 'success' = 'true' and j -> 'proposal' = 'null'::jsonb);
  j := pg_temp.probe_call(u14, format('public.respond_to_community_merge(%L::uuid, true)', v_prop));
  perform pg_temp.probe_ok(v_probe, 'an expired proposal answers proposal_closed and reads expired: ' || j::text,
    j ->> 'code' = 'proposal_closed'
    and (select status from public.community_merge_proposals where id = v_prop) = 'expired'
    and exists (select 1 from public.communities where id = c3 and archived_at is null));

  -- the daily cap (I1): u12 has made three proposals today; the fourth writes nothing
  n := (select count(*) from public.notifications where user_id = u14 and title = 'Merge proposal from Probe Public Two');
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c2));
  perform pg_temp.probe_ok(v_probe, 'u12''s fourth proposal within 24 hours answers rate_limited: ' || j::text,
    j ->> 'code' = 'rate_limited'
    and (select count(*) from public.community_merge_proposals where proposed_by = u12) = 3
    and (select count(*) from public.notifications
          where user_id = u14 and title = 'Merge proposal from Probe Public Two') = n);
  update public.community_merge_proposals set created_at = created_at - interval '25 hours' where proposed_by = u12;

  -- the merge
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c2));
  v_prop := (j ->> 'proposal_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a fourth proposal, a day later: ' || j::text, v_prop is not null);
  j := pg_temp.probe_call(u14, format('public.respond_to_community_merge(%L::uuid, true)', v_prop));
  perform pg_temp.probe_ok(v_probe, 'u14 accepts: C2 survives, C3 is merged: ' || j::text,
    j ->> 'success' = 'true' and j ->> 'survivor_id' = c2::text and j ->> 'merged_id' = c3::text);
  perform pg_temp.probe_ok(v_probe, 'the settings are reset after the merge',
    coalesce(current_setting('naars.suppress_approval_notice', true), '') = ''
    and coalesce(current_setting('naars.membership_mirror', true), '') = ''
    and coalesce(current_setting('naars.broadcast_post', true), '') = '');

  -- members in C2
  perform pg_temp.probe_ok(v_probe, 'C2: u14 admin, u3 admin (the higher role), u12 still the only owner',
    exists (select 1 from public.community_members where community_id = c2 and user_id = u14
             and role = 'admin' and status = 'active')
    and exists (select 1 from public.community_members where community_id = c2 and user_id = u3
                 and role = 'admin' and status = 'active')
    and (select array_agg(user_id) from public.community_members
          where community_id = c2 and role = 'owner' and status = 'active') = array[u12]);
  perform pg_temp.probe_ok(v_probe, 'C2: u5 pending with C3''s answers',
    exists (select 1 from public.community_members where community_id = c2 and user_id = u5 and status = 'pending'
             and role = 'member' and heard_about = 'Probe merge heard' and join_reason = 'Probe merge reason'));
  perform pg_temp.probe_ok(v_probe, 'C2: u11 active member, muted, with C3''s dates',
    exists (select 1 from public.community_members where community_id = c2 and user_id = u11 and status = 'active'
             and role = 'member' and notifications_muted and joined_at = v_c3_joined
             and activated_at = v_c3_activated));
  perform pg_temp.probe_ok(v_probe, 'C2: u7 is still removed and their unclaimed C3 ride is deleted',
    exists (select 1 from public.community_members where community_id = c2 and user_id = u7 and status = 'removed')
    and not exists (select 1 from public.rides where id = v_open_ride));
  perform pg_temp.probe_ok(v_probe, 'C3''s rows are kept as they were (history)',
    (select count(*) from public.community_members where community_id = c3) = 6
    and exists (select 1 from public.community_members where community_id = c3 and user_id = u14
                 and role = 'owner' and status = 'active'));
  perform pg_temp.probe_ok(v_probe, 'R1: u11''s primary community moved from C3 to C2 (not to C1)',
    (select primary_community_id from public.profiles where id = u11) = c2);

  -- content
  perform pg_temp.probe_ok(v_probe, 'the completed ride, the favor and the post are in C2; the ride kept its updated_at',
    exists (select 1 from public.rides where id = v_done_ride and community_id = c2 and status = 'completed'
             and updated_at = v_done_at)
    and exists (select 1 from public.favors where id = v_favor and community_id = c2 and status = 'confirmed'
                 and claimed_by = u11)
    and exists (select 1 from public.town_hall_posts where id = v_post and community_id = c2)
    and exists (select 1 from public.town_hall_comments where id = v_comment and post_id = v_post));
  perform pg_temp.probe_ok(v_probe, 'nothing of C3 is left in rides, favors, posts, xp_events or reports',
    not exists (select 1 from public.rides where community_id = c3)
    and not exists (select 1 from public.favors where community_id = c3)
    and not exists (select 1 from public.town_hall_posts where community_id = c3)
    and not exists (select 1 from public.xp_events where community_id = c3)
    and not exists (select 1 from public.reports where community_id = c3)
    and exists (select 1 from public.xp_events where source_id = v_done_ride and community_id = c2));
  perform pg_temp.probe_ok(v_probe, 'the post report moved to C2; the community report still names C3',
    (select community_id from public.reports where id = v_post_report) = c2
    and exists (select 1 from public.reports
                 where id = v_community_report and reported_community_id = c3 and community_id is null));
  perform pg_temp.probe_ok(v_probe, 'notifications of C3 moved to C2: only u7''s archive notice still names C3',
    not exists (select 1 from public.notifications
                 where community_id = c3 and not (user_id = u7 and title = 'Probe Community Three was archived'))
    and exists (select 1 from public.notifications where id = v_nid and community_id = c2));
  perform pg_temp.probe_ok(v_probe, 'C3''s invite is revoked',
    not exists (select 1 from public.community_invites where community_id = c3 and revoked_at is null));

  -- C3, the events, the proposal
  perform pg_temp.probe_ok(v_probe, 'C3 is archived by u14 and merged into C2',
    exists (select 1 from public.communities where id = c3 and archived_at is not null and archived_by = u14
             and merged_into_id = c2 and merged_at is not null));
  perform pg_temp.probe_ok(v_probe, 'one merged event on C2 and one archived event on C3',
    (select count(*) from public.community_membership_events
      where community_id = c2 and event = 'merged' and actor_id = u14
        and reason = 'merged Probe Community Three (' || c3::text || ')') = 1
    and (select count(*) from public.community_membership_events where community_id = c2 and event = 'merged') = 1
    and (select count(*) from public.community_membership_events
          where community_id = c3 and event = 'archived' and reason = 'merged into ' || c2::text) = 1);
  perform pg_temp.probe_ok(v_probe, 'the proposal is accepted by u14',
    exists (select 1 from public.community_merge_proposals
             where id = v_prop and status = 'accepted' and decided_by = u14 and decided_at is not null));

  -- notices
  perform pg_temp.probe_ok(v_probe, 'R14: u12 has one pending_approval row for u5 in C2',
    (select count(*) from public.notifications
      where user_id = u12 and type = 'pending_approval' and source_user_id = u5 and community_id = c2) = 1);
  perform pg_temp.probe_ok(v_probe, 'R15: u7 has the archive notice for C3, without a push',
    (select count(*) from public.notifications
      where user_id = u7 and type = 'announcement' and title = 'Probe Community Three was archived'
        and community_id = c3) = 1
    and not exists (select 1 from public.notification_queue
                     where recipient_user_id = u7 and payload ->> 'title' = 'Probe Community Three was archived'));
  v_sys_post := (select id from public.town_hall_posts where community_id = c2 and system_event = 'community_merged');
  perform pg_temp.probe_ok(v_probe, 'one system announcement in C2 by u14',
    (select count(*) from public.town_hall_posts where system_event = 'community_merged' and community_id = c2) = 1
    and exists (select 1 from public.town_hall_posts
                 where id = v_sys_post and type = 'announcement' and user_id = u14 and not pinned
                   and title = 'Communities merged'
                   and content = 'Probe Public Two and Probe Community Three are now one community: Probe Public Two.'));
  perform pg_temp.probe_ok(v_probe, 'one announcement bell row each for u3 and u12; none for u14 (accepter) or u11 (muted)',
    (select array_agg(n.user_id order by n.user_id) from public.notifications n
      where n.town_hall_post_id = v_sys_post and n.type = 'announcement' and n.title = 'Communities merged'
        and n.body like '%Probe Public Two%' and n.body like '%Probe Community Three%')
    = (select array_agg(x order by x) from unnest(array[u3, u12]) x));
  perform pg_temp.probe_ok(v_probe, 'one push each for u3 and u12 with community_event merged, its community and bell row',
    (select array_agg(q.recipient_user_id order by q.recipient_user_id) from public.notification_queue q
      where q.payload -> 'data' ->> 'town_hall_post_id' = v_sys_post::text)
    = (select array_agg(x order by x) from unnest(array[u3, u12]) x)
    and not exists (select 1 from public.notification_queue q
                     where q.payload -> 'data' ->> 'town_hall_post_id' = v_sys_post::text
                       and (q.notification_type <> 'announcement' or q.batch_key is not null
                            or q.payload -> 'data' ->> 'community_event' is distinct from 'merged'
                            or q.payload -> 'data' ->> 'community_id' is distinct from c2::text
                            or not exists (select 1 from public.notifications n
                                            where n.id::text = q.payload -> 'data' ->> 'notification_id'
                                              and n.user_id = q.recipient_user_id))));
  perform pg_temp.probe_ok(v_probe, 'the system announcement makes no Town Hall notice',
    not exists (select 1 from public.notifications where type = 'town_hall_post' and town_hall_post_id = v_sys_post));

  -- the D14 cap does not count the system announcement
  for n in 1..3 loop
    j := pg_temp.probe_call(u12, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                        c2, 'Probe after merge ' || n, 'communities probe'));
    perform pg_temp.probe_ok(v_probe, format('announcement %s in C2 after the merge is sent: %s', n, j),
      not pg_temp.probe_refused(j));
  end loop;
  j := pg_temp.probe_call(u12, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                      c2, 'Probe after merge 4', 'communities probe'));
  perform pg_temp.probe_ok(v_probe, 'the fourth is refused (P0001): ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = 'P0001');

  -- reads after the merge
  j := pg_temp.probe_call(u11, 'public.get_my_community_merges()');
  k := (select jsonb_agg(e) from jsonb_array_elements(j -> 'merges') e
         where e ->> 'merged_id' like '00000000-0000-4000-b000-%');
  perform pg_temp.probe_ok(v_probe, 'get_my_community_merges maps C3 to C2 for u11: ' || j::text,
    j ->> 'success' = 'true' and jsonb_array_length(k) = 1
    and k #>> '{0,merged_id}' = c3::text and k #>> '{0,merged_name}' = 'Probe Community Three'
    and k #>> '{0,survivor_id}' = c2::text and k #>> '{0,survivor_name}' = 'Probe Public Two'
    and k #>> '{0,merged_at}' is not null and (select count(*) from jsonb_object_keys(k -> 0)) = 5);
  j := pg_temp.probe_call(u13, 'public.get_my_community_merges()');
  perform pg_temp.probe_ok(v_probe, 'get_my_community_merges is empty for an account that was not in C3: ' || j::text,
    j ->> 'success' = 'true'
    and not exists (select 1 from jsonb_array_elements(j -> 'merges') e
                     where e ->> 'merged_id' like '00000000-0000-4000-b000-%'));
  j := pg_temp.probe_call(u13, format('public.get_community_preview(%L::uuid)', c3));
  perform pg_temp.probe_ok(v_probe, 'the preview of C3 answers merged into C2: ' || j::text,
    j ->> 'code' = 'merged' and j ->> 'merged_into_id' = c2::text);
  j := pg_temp.probe_call(v_admin, 'public.get_platform_communities()');
  k := (select e from jsonb_array_elements(j -> 'merge_proposals') e where e ->> 'id' = v_prop::text);
  perform pg_temp.probe_ok(v_probe, 'the platform list shows the merge as accepted: ' || coalesce(k::text, 'null'),
    j ->> 'success' = 'true'
    and k ->> 'status' = 'accepted' and k ->> 'from_id' = c2::text and k ->> 'from_name' = 'Probe Public Two'
    and k ->> 'to_id' = c3::text and k ->> 'to_name' = 'Probe Community Three' and k ->> 'survivor_id' = c2::text
    and k ->> 'survivor_name' = 'Probe Public Two' and k ->> 'decided_at' is not null
    and (select count(*) from jsonb_object_keys(k)) = 12);
  select string_agg(e ->> 'status', ',' order by e ->> 'status') into v_names
    from jsonb_array_elements(j -> 'merge_proposals') e
   where e ->> 'from_id' = c2::text and e ->> 'to_id' = c3::text;
  perform pg_temp.probe_ok(v_probe, 'the platform list holds the four C2-C3 proposals: ' || coalesce(v_names, 'none'),
    v_names = 'accepted,declined,expired,withdrawn');
  j := pg_temp.probe_call(v_admin, format('public.unarchive_community(%L::uuid)', c3));
  perform pg_temp.probe_ok(v_probe, 'R16: a platform admin cannot restore merged C3: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'error' = 'This community was merged and cannot be restored'
    and exists (select 1 from public.communities where id = c3 and archived_at is not null));
  j := pg_temp.probe_call(u12, format('public.respond_to_community_merge(%L::uuid, true)', v_prop));
  k := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, c3, c2));
  perform pg_temp.probe_ok(v_probe,
    'the accepted proposal is closed; merged C3 cannot be proposed: ' || j::text || ' / ' || k::text,
    j ->> 'code' = 'proposal_closed' and k ->> 'code' = 'invalid');

  -- the default community
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c2, d, c2));
  perform pg_temp.probe_ok(v_probe, 'the default community is refused: ' || j::text, j ->> 'code' = 'default_community');

  -- one owner of both: C6 into C2
  c6 := pg_temp.probe_community(6, 'Probe Six', u12, false, 'invite');
  j := pg_temp.probe_call(u12, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c6, c2, c2));
  v_prop := (j ->> 'proposal_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'u12 proposes C6 into C2 and is not told of their own proposal: ' || j::text,
    v_prop is not null
    and not exists (select 1 from public.notifications where title = 'Merge proposal from Probe Six'));
  j := pg_temp.probe_call(u12, format('public.respond_to_community_merge(%L::uuid, true)', v_prop));
  perform pg_temp.probe_ok(v_probe, 'u12 accepts as C2''s owner: ' || j::text,
    j ->> 'success' = 'true' and j ->> 'survivor_id' = c2::text and j ->> 'merged_id' = c6::text);
  perform pg_temp.probe_ok(v_probe, 'u12 has one C2 row, owner; C6 is merged into C2',
    (select count(*) from public.community_members where community_id = c2 and user_id = u12) = 1
    and exists (select 1 from public.community_members where community_id = c2 and user_id = u12
                 and role = 'owner' and status = 'active')
    and exists (select 1 from public.communities where id = c6 and archived_at is not null and merged_into_id = c2));

  -- an archived side: C1 into C5, C5 archived before the answer
  c5 := pg_temp.probe_community(5, 'Probe Five', u13, true, 'approve');
  v_c1_members := (select count(*) from public.community_members where community_id = c1);
  j := pg_temp.probe_call(u4, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c1, c5, c5));
  v_prop := (j ->> 'proposal_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'u4 proposes C1 into C5: ' || j::text, v_prop is not null);
  perform set_config('request.jwt.claims', '', true);
  update public.communities set archived_at = now() where id = c5;
  j := pg_temp.probe_call(u13, format('public.respond_to_community_merge(%L::uuid, true)', v_prop));
  perform pg_temp.probe_ok(v_probe, 'an archived side closes the proposal as withdrawn; C1 is unchanged: ' || j::text,
    j ->> 'code' = 'proposal_closed'
    and (select status from public.community_merge_proposals where id = v_prop) = 'withdrawn'
    and exists (select 1 from public.communities where id = c1 and archived_at is null and merged_into_id is null)
    and (select count(*) from public.community_members where community_id = c1) = v_c1_members);
  j := pg_temp.probe_call(v_admin, format('public.unarchive_community(%L::uuid)', c5));
  perform pg_temp.probe_ok(v_probe, 'R16 control: an archive that is not a merge can still be restored: ' || j::text,
    j ->> 'success' = 'true' and exists (select 1 from public.communities where id = c5 and archived_at is null));

  -- blocks (I1): u11 (owner of C9) blocked u16; u16 blocked u5 (owner of C10, admin of C1)
  c7 := pg_temp.probe_community(7, 'Probe Seven', u16, false, 'approve');
  c9 := pg_temp.probe_community(9, 'Probe Nine', u11, false, 'approve');
  c10 := pg_temp.probe_community(10, 'Probe Ten', u5, false, 'approve');
  insert into public.blocked_users (blocker_id, blocked_id, reason) values (u11, u16, 'communities probe');
  insert into public.blocked_users (blocker_id, blocked_id, reason) values (u16, u5, 'communities probe');
  j := pg_temp.probe_call(u16, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c7, c9, c7));
  k := pg_temp.probe_call(u16, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c7, c10, c7));
  perform pg_temp.probe_ok(v_probe, 'a block either way between the caller and the other owner: invalid, nothing '
                                    || 'written, nobody told: ' || j::text || ' / ' || k::text,
    j ->> 'code' = 'invalid' and k ->> 'code' = 'invalid'
    and not exists (select 1 from public.community_merge_proposals where c7 in (from_community_id, to_community_id))
    and not exists (select 1 from public.notifications where title = 'Merge proposal from Probe Seven'));

  -- a stale pending proposal (also the block control: u16 blocked C1's admin u5, not its owner u4)
  j := pg_temp.probe_call(u16, format('public.propose_community_merge(%L::uuid, %L::uuid, %L::uuid)', c7, c1, c1));
  v_prop := (j ->> 'proposal_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'u16 proposes C7 into C1: ' || j::text,
    v_prop is not null
    and (select count(*) from public.notifications where user_id = u4 and title = 'Merge proposal from Probe Seven') = 1);
  perform set_config('request.jwt.claims', '', true);
  update public.community_merge_proposals set expires_at = now() - interval '1 minute' where id = v_prop;
  j := pg_temp.probe_call(v_admin, 'public.get_platform_communities()');
  k := (select e from jsonb_array_elements(j -> 'merge_proposals') e where e ->> 'id' = v_prop::text);
  perform pg_temp.probe_ok(v_probe, 'a pending proposal past its expiry reads expired: ' || coalesce(k::text, 'null'),
    k ->> 'status' = 'expired'
    and (select status from public.community_merge_proposals where id = v_prop) = 'pending');

  -- merge_communities is internal
  j := pg_temp.probe_call(u16, format('public.merge_communities(%L::uuid, %L::uuid)', v_prop, u16));
  perform pg_temp.probe_ok(v_probe, 'a client cannot call merge_communities (42501): ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');
  j := pg_temp.probe_call(u16, format($q$public.post_community_announcement(%L::uuid, %L::uuid, 't', 'b', false,
                                        'announcement', null, '{}'::jsonb)$q$, c7, u16));
  perform pg_temp.probe_ok(v_probe, 'a client cannot call post_community_announcement (42501): ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback to savepoint probe; release savepoint probe;
select 'PROBE community_merge OK' as probe;


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


select 'DRYRUN 20261021_0021_0022_final_fix OK' as dryrun;
rollback;
