-- DRY RUN of supabase/migrations/20261021_0020_discovery_schema.sql. NEVER APPLIED. Ends in rollback; contains no commit. Paste verbatim.

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
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE test_flag_visibility OK' as probe;


-- =============================================================================================================
-- example_guard (Release 2, 20261021_0020 Block 10): a client cannot set is_example on a ride, a favor or a post,
-- nor system_event on a post, at insert, nor change is_example on a ride by update, its own included (42501
-- 'example_flag_reserved'); the table owner (as definer code, no JWT) can; a C1 member's claim of an example ride
-- or favor is refused with 42501 'example_request' and the same claim of an ordinary open ride succeeds; the poster
-- can still edit an example ride's notes. Clients have no UPDATE policy on town_hall_posts, so the guard's
-- post-update branch is a second line only.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE example_guard OK' as probe;


-- =============================================================================================================
-- listed_reviews (Release 2, 20261021_0020 Block 11, ruling R9): a signed-in account with no membership and
-- approved false (u10) reads the review of a completed request in a listed community (C2) and not one in a listed
-- test community (C4), nor the C2 request itself; the C4 review stays readable by its writer (control); an approved
-- account in neither (u3) reads the C2 review and not the C4 one; anon reads no review through the table beyond what
-- the guest views give it (reviews_select_anon_guest): the C2 review through them, not the C4 review.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE listed_reviews OK' as probe;


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
-- listed_profiles (Release 1, 20261021_0001): a signed-in account reads an active member of a listed community
-- (u12, public C2) in public_profiles and get_profile_stats, as a guest does, and not a member of a private one
-- (u14, C3); it reads the review of a completed request in a listed community and not one in a private community,
-- and still does not read the listed request's row itself; anon's read of reviews plans and runs (it needs
-- EXECUTE on is_listed_request).
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE listed_profiles OK' as probe;


-- =============================================================================================================
-- reputation: two viewers who each share a different community with the same person read identical
-- get_profile_stats; a viewer who shares none gets an empty result; get_community_leaderboard for a private
-- community the caller is not in is refused. Once Release 1 (20261021_0001) is live, an active member of a listed
-- community is readable by every signed-in account: the "shares none" check reads u3 (C1 only, private) instead of
-- u5 (active in public C2), and a default member now reads u5's stats.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE reputation OK' as probe;


-- =============================================================================================================
-- isolation: a probe community's ride and member are invisible to a default-community member (rides,
-- public_profiles, search_community_members, get_user_badges, get_user_stats, get_profile_stats); the probe
-- member cannot add a default member to a thread; notify_new_ride queues one push per probe-community member;
-- a claim across the boundary raises 42501 from the trigger even as the table owner; leaderboard and
-- spotlights of the probe community show only its people; a probe member reads only their own
-- community_members row and get_community_members gives them null answers and its admin the answers.
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE isolation OK' as probe;


-- =============================================================================================================
-- noop_default: no change for the default community. Each active member reads exactly the rides, favors and
-- posts they read before (visible rows of their live communities plus their own); an unapproved account
-- reads no foreign rows; anon reads the guest views and the posts of public communities; public_profiles
-- shows a member every co-member and anon every active member of a public community (once 20261021_0020 is live,
-- public and not a test community); XP unchanged; the rides
-- SELECT of a member of three communities shows the InitPlan (index scan reported).
-- =============================================================================================================
savepoint probe;
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
rollback to savepoint probe; release savepoint probe;
select 'PROBE noop_default OK' as probe;


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


select 'DRYRUN 20261021_0020 OK' as dryrun;
rollback;
