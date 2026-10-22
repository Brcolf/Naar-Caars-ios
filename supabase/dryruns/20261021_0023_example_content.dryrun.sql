-- DRY RUN of supabase/migrations/20261021_0023_example_content.sql. NEVER APPLIED. Ends in rollback; contains no commit. Paste verbatim.

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
-- BLOCK 1: public.notify_new_ride() and public.notify_new_favor()
--          live md5(prosrc) 412d6ec764b021bed454a34bf55cb993 and a4995495114a3936804b444de79df271
--          (20261017_0003 calls 1 and 2)
-- Derived from pg_get_functiondef: after the one BEGIN of each body (found once), an example request returns
-- before any bell row or push. Nothing else changes.
-- ============================================================================================
create or replace function public.notify_new_ride()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_destination TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    v_destination := COALESCE(NEW.destination, 'a destination');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_ride', 'New Ride Request',
            v_poster_name || ' needs a ride to ' || v_destination,
            NEW.id, NULL, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_ride', 'New Ride Request',
                v_poster_name || ' needs a ride to ' || v_destination,
                jsonb_build_object('ride_id', NEW.id::text, 'community_id', NEW.community_id::text),
                NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_new_ride() from public, anon, authenticated;

create or replace function public.notify_new_favor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_favor', 'New Favor Request',
            v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
            NULL, NEW.id, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_favor', 'New Favor Request',
                v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
                jsonb_build_object('favor_id', NEW.id::text, 'community_id', NEW.community_id::text),
                NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_new_favor() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 2: public.notify_town_hall_post()
--          live md5(prosrc) 8067912ecd96ed2a655a82c1a9d247f7 (20261019_0002 block 1)
-- Derived from pg_get_functiondef: the same guard first in the body (after its one BEGIN), so an example post
-- writes no "New in Town Hall" row or push. Nothing else changes.
-- ============================================================================================
create or replace function public.notify_town_hall_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_batch_key TEXT;
    v_notification_id UUID;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    -- send_community_broadcast sends this announcement's own push (20261019_0002 block 2); the Town Hall notice
    -- would be a second, batched one. The setting is transaction-local and set only around that one insert.
    IF NEW.type = 'announcement'
       AND coalesce(current_setting('naars.broadcast_post', true), '') = '1' THEN
        RETURN NEW;
    END IF;

    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    v_batch_key := 'town_hall_' || NEW.community_id::text || '_' || to_char(date_trunc('minute', NOW()) -
        (EXTRACT(MINUTE FROM NOW())::int % 5) * INTERVAL '1 minute', 'YYYY-MM-DD-HH24-MI');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND p.notify_town_hall = true
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'town_hall_post', 'New in Town Hall',
            v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
            NULL, NULL, NULL, NULL, NEW.id, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'town_hall_post', 'New in Town Hall',
                v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
                jsonb_build_object('town_hall_post_id', NEW.id::text, 'community_id', NEW.community_id::text),
                v_batch_key, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_town_hall_post() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 3: public.record_xp_on_request_created()
--          live md5(prosrc) a2f1a07e89f884da817302e9d13667a9 (20261017_0003 call 7)
-- Derived from pg_get_functiondef: the same guard first in the body (after its one BEGIN). An example request
-- earns no XP, so the account that posts the examples never leads a leaderboard. Nothing else changes.
-- ============================================================================================
create or replace function public.record_xp_on_request_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_is_first BOOLEAN;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME = 'rides' THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
        VALUES (
            NEW.user_id, 5, 'ride_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
            NEW.created_at, NEW.community_id
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.rides WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (NEW.user_id, 10, 'first_ride', NEW.id, 'First ride milestone', NEW.created_at, NEW.community_id)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    ELSE
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
        VALUES (
            NEW.user_id, 5, 'favor_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.title, 'Favor'),
            NEW.created_at, NEW.community_id
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.favors WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (NEW.user_id, 10, 'first_favor', NEW.id, 'First favor milestone', NEW.created_at, NEW.community_id)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

revoke all on function public.record_xp_on_request_created() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 4: public.expire_past_open_requests()
--          live md5(prosrc) e798c760a31ed69697a23895238d52d7 (20261006_0004; ruling R11)
-- Derived from pg_get_functiondef: "and not r.is_example" and "and not f.is_example" after each
-- "status = 'open'" condition (each found once). An example never expires; refresh_example_requests (Block 6)
-- moves it forward instead. Nothing else changes.
-- ============================================================================================
create or replace function public.expire_past_open_requests()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_count integer := 0;
    v_rides integer;
    v_favors integer;
begin
    -- The status-change triggers would message ride/favor participants ("marked as
    -- completed") and queue pushes for every stale row; expiry is housekeeping, so they are
    -- disabled for the duration of this function. The XP trigger is a no-op (claimed_by is
    -- null) and set_updated_at still runs.
    alter table public.rides disable trigger on_ride_status_change_notify;
    alter table public.favors disable trigger on_favor_status_change_notify;

    update public.rides r
    set status = 'completed'
    where r.status = 'open'
      and not r.is_example
      and r.claimed_by is null
      and ((r.date::date + r.time::time) at time zone coalesce(r.timezone, 'America/Los_Angeles'))
            < now() - interval '12 hours';
    get diagnostics v_rides = row_count;

    update public.favors f
    set status = 'completed'
    where f.status = 'open'
      and not f.is_example
      and f.claimed_by is null
      and (case
             when f.time is null
               then ((f.date::date + 1)::timestamp at time zone coalesce(f.timezone, 'America/Los_Angeles'))
             else ((f.date::date + f.time::time) at time zone coalesce(f.timezone, 'America/Los_Angeles'))
           end) < now() - interval '12 hours';
    get diagnostics v_favors = row_count;

    alter table public.rides enable trigger on_ride_status_change_notify;
    alter table public.favors enable trigger on_favor_status_change_notify;

    v_count := coalesce(v_rides, 0) + coalesce(v_favors, 0);
    return v_count;
exception when others then
    alter table public.rides enable trigger on_ride_status_change_notify;
    alter table public.favors enable trigger on_favor_status_change_notify;
    raise;
end;
$function$;

revoke all on function public.expire_past_open_requests() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 5: public.set_example_content(text, uuid, boolean)   (new; authenticated, service_role; platform admins)
-- ============================================================================================
create or replace function public.set_example_content(p_type text, p_id uuid, p_is_example boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer := 0;
begin
  if (select auth.uid()) is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;

  if p_type is null or p_type not in ('ride', 'favor', 'town_hall_post') or p_id is null or p_is_example is null then
    return jsonb_build_object('success', false, 'error', 'Choose a ride, a favor or a post, and true or false',
                              'code', 'invalid');
  end if;

  -- a definer write: guard_example_content (20261021_0020 Block 10) lets it through
  if p_type = 'ride' then
    update public.rides set is_example = p_is_example
     where id = p_id and is_example is distinct from p_is_example;
  elsif p_type = 'favor' then
    update public.favors set is_example = p_is_example
     where id = p_id and is_example is distinct from p_is_example;
  else
    update public.town_hall_posts set is_example = p_is_example
     where id = p_id and is_example is distinct from p_is_example;
  end if;
  get diagnostics v_count = row_count;

  return jsonb_build_object('success', true, 'changed', v_count > 0);
end
$function$;

revoke all on function public.set_example_content(text, uuid, boolean) from public, anon;
grant execute on function public.set_example_content(text, uuid, boolean) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 6: public.refresh_example_requests()   (new; internal: the daily job, Block 7)
-- Every example ride and favor that is not hidden: tomorrow is the day after today in the row's own time zone; a
-- date before tomorrow moves forward by whole weeks (same weekday) to the first such day on or after tomorrow, so
-- it lands in [tomorrow, tomorrow + 6]; a row that is not open or has a helper becomes open with no helper.
-- Only rows that need a change are written, so a second run the same day changes nothing. Returns the number of
-- rows changed. No trigger is disabled: examples cannot be claimed (guard_example_content), so the reopen branch is
-- a safety net, and if it fires the status trigger may tell the poster.
-- ============================================================================================
create or replace function public.refresh_example_requests()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_rides integer := 0;
  v_favors integer := 0;
begin
  with t as (
    select r.id, (now() at time zone coalesce(r.timezone, 'America/Los_Angeles'))::date + 1 as tomorrow
      from public.rides r
     where r.is_example and r.hidden_at is null
  )
  update public.rides r
     set date = case when r.date < t.tomorrow
                     then r.date + 7 * ceil((t.tomorrow - r.date) / 7.0)::int
                     else r.date end,
         status = 'open',
         claimed_by = null
    from t
   where r.id = t.id
     and (r.date < t.tomorrow or r.status::text <> 'open' or r.claimed_by is not null);
  get diagnostics v_rides = row_count;

  with t as (
    select f.id, (now() at time zone coalesce(f.timezone, 'America/Los_Angeles'))::date + 1 as tomorrow
      from public.favors f
     where f.is_example and f.hidden_at is null
  )
  update public.favors f
     set date = case when f.date < t.tomorrow
                     then f.date + 7 * ceil((t.tomorrow - f.date) / 7.0)::int
                     else f.date end,
         status = 'open',
         claimed_by = null
    from t
   where f.id = t.id
     and (f.date < t.tomorrow or f.status::text <> 'open' or f.claimed_by is not null);
  get diagnostics v_favors = row_count;

  return v_rides + v_favors;
end
$function$;

revoke all on function public.refresh_example_requests() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 7: the daily job refresh-example-requests at 11:10 UTC (about 3-4 AM Pacific, away from the 03:15 UTC
-- expiry job), then one run now
-- ============================================================================================
select cron.schedule('refresh-example-requests', '10 11 * * *', $$select public.refresh_example_requests()$$);

select public.refresh_example_requests();


-- =============================================================================================================
-- example_content (Release 2, 20261021_0023 Blocks 1-7; rulings R-G1, R3). EXECUTE, definer and volatility of the
-- File D functions; in C1 (active members u3, u5, u7, u11; the notifiers skip the poster u4) an example ride, favor
-- and post by u4 write no notifications row and no xp_events row, and the same three without the flag write the
-- bell rows and XP as before (control); expire_past_open_requests completes a 20-day-old ordinary open ride and
-- leaves the example open; refresh_example_requests moves a 20-day-old example ride to [tomorrow, tomorrow + 6]
-- (Los Angeles) and a 9-day-old example favor to the same window in Pacific/Auckland, each on its own weekday,
-- reopens a completed example with no helper, leaves a hidden example and a future one alone, and a second run
-- returns 0; set_example_content by the platform admin subject (changed true, then false; a definer write the S1
-- guard allows), refused for the member subject and for an unknown type, closed to anon; the cron job.
-- =============================================================================================================
savepoint probe;
do $probe$
declare
  v_probe constant text := 'example_content';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);
  u11 uuid := pg_temp.u(11);
  c1 uuid := pg_temp.c(1);
  v_others constant uuid[] := array[pg_temp.u(3), pg_temp.u(5), pg_temp.u(7), pg_temp.u(11)];
  v_ex_ride uuid := pg_temp.r(71);      -- example, in three days
  v_ctl_ride uuid := pg_temp.r(72);     -- ordinary, in three days
  v_old_ex uuid := pg_temp.r(73);       -- example, open, 20 days ago
  v_old_ctl uuid := pg_temp.r(74);      -- ordinary, open, 20 days ago
  v_done_ex uuid := pg_temp.r(75);      -- example, completed, helped by u3
  v_hidden_ex uuid := pg_temp.r(76);    -- example, hidden, 20 days ago
  v_old_date constant date := current_date - 20;
  v_nz_date constant date := current_date - 9;
  v_tomorrow constant date := (now() at time zone 'America/Los_Angeles')::date + 1;
  v_nz_tomorrow constant date := (now() at time zone 'Pacific/Auckland')::date + 1;
  v_ex_favor uuid;
  v_ctl_favor uuid;
  v_nz_favor uuid;
  v_ex_post uuid;
  v_ctl_post uuid;
  v_date date;
  v_fn text;
  n int;
  j jsonb;
begin
  perform pg_temp.probe_require_release2(v_probe, 'd');
  perform pg_temp.probe_world();
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.probe_ok(v_probe, 'the platform admin and member subjects resolve',
    v_admin is not null and v_member is not null);

  -- EXECUTE (ruling R-G1), definer, search_path, volatility
  v_fn := 'public.set_example_content(text, uuid, boolean)';
  perform pg_temp.probe_ok(v_probe, v_fn || ': EXECUTE for authenticated and service_role, none for anon or public',
    not has_function_privilege('anon', v_fn, 'execute')
    and has_function_privilege('authenticated', v_fn, 'execute')
    and has_function_privilege('service_role', v_fn, 'execute')
    and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                     where p.oid = v_fn::regprocedure and a.grantee = 0));
  foreach v_fn in array array['public.refresh_example_requests()', 'public.notify_new_ride()',
      'public.notify_new_favor()', 'public.notify_town_hall_post()', 'public.record_xp_on_request_created()',
      'public.expire_past_open_requests()'] loop
    perform pg_temp.probe_ok(v_probe, v_fn || ': EXECUTE for service_role only (no anon, authenticated or public)',
      not has_function_privilege('anon', v_fn, 'execute')
      and not has_function_privilege('authenticated', v_fn, 'execute')
      and has_function_privilege('service_role', v_fn, 'execute')
      and not exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
                       where p.oid = v_fn::regprocedure and a.grantee = 0));
  end loop;
  foreach v_fn in array array['public.set_example_content(text, uuid, boolean)', 'public.refresh_example_requests()',
      'public.notify_new_ride()', 'public.notify_new_favor()', 'public.notify_town_hall_post()',
      'public.record_xp_on_request_created()', 'public.expire_past_open_requests()'] loop
    perform pg_temp.probe_ok(v_probe, v_fn || ': security definer, search_path "", volatile',
      exists (select 1 from pg_catalog.pg_proc p
               where p.oid = v_fn::regprocedure and p.prosecdef and p.provolatile = 'v'
                 and p.proconfig @> array['search_path=""']));
  end loop;

  -- R3: an example ride, favor and post by u4 in C1 notify nobody and earn no XP; the same without the flag do
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id, is_example)
  values (v_ex_ride, u4, current_date + 3, '09:00', 'Probe pickup', 'Probe destination', 'open', c1, true);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id)
  values (v_ctl_ride, u4, current_date + 3, '10:00', 'Probe pickup', 'Probe destination', 'open', c1);
  insert into public.favors (user_id, title, location, date, status, community_id, is_example)
  values (u4, 'Probe example favor', 'Probe location', current_date + 3, 'open', c1, true)
  returning id into v_ex_favor;
  insert into public.favors (user_id, title, location, date, status, community_id)
  values (u4, 'Probe favor', 'Probe location', current_date + 3, 'open', c1)
  returning id into v_ctl_favor;
  insert into public.town_hall_posts (user_id, title, content, community_id, is_example)
  values (u4, 'Probe example post', 'communities probe example post', c1, true)
  returning id into v_ex_post;
  v_ctl_post := pg_temp.probe_post(71, u4, c1);

  perform pg_temp.probe_ok(v_probe, 'the example ride writes no notifications row',
    not exists (select 1 from public.notifications where ride_id = v_ex_ride));
  perform pg_temp.probe_ok(v_probe, 'the example favor writes no notifications row',
    not exists (select 1 from public.notifications where favor_id = v_ex_favor));
  perform pg_temp.probe_ok(v_probe, 'the example post writes no notifications row (no New in Town Hall)',
    not exists (select 1 from public.notifications where town_hall_post_id = v_ex_post));
  perform pg_temp.probe_ok(v_probe, 'the example ride and favor earn no XP',
    not exists (select 1 from public.xp_events where source_id in (v_ex_ride, v_ex_favor)));
  perform pg_temp.probe_ok(v_probe, 'the example ride, favor and post queue no push',
    not exists (select 1 from public.notification_queue q
                 where q.payload::text like '%' || v_ex_ride::text || '%'
                    or q.payload::text like '%' || v_ex_favor::text || '%'
                    or q.payload::text like '%' || v_ex_post::text || '%'));

  perform pg_temp.probe_ok(v_probe, 'control: the ordinary ride tells u3, u5, u7 and u11 (one new_ride row each)',
    (select array_agg(user_id order by user_id) from public.notifications
      where ride_id = v_ctl_ride and type = 'new_ride')
    = (select array_agg(x order by x) from unnest(v_others) x));
  perform pg_temp.probe_ok(v_probe, 'control: the ordinary favor tells u3, u5, u7 and u11 (one new_favor row each)',
    (select array_agg(user_id order by user_id) from public.notifications
      where favor_id = v_ctl_favor and type = 'new_favor')
    = (select array_agg(x order by x) from unnest(v_others) x));
  perform pg_temp.probe_ok(v_probe, 'control: the ordinary post tells u3, u5, u7 and u11 (New in Town Hall)',
    (select array_agg(user_id order by user_id) from public.notifications
      where town_hall_post_id = v_ctl_post and type = 'town_hall_post')
    = (select array_agg(x order by x) from unnest(v_others) x));
  perform pg_temp.probe_ok(v_probe, 'control: the ordinary ride and favor earn u4 their request XP',
    exists (select 1 from public.xp_events where source_id = v_ctl_ride and source_type = 'ride_requested'
                                              and user_id = u4)
    and exists (select 1 from public.xp_events where source_id = v_ctl_favor and source_type = 'favor_requested'
                                                  and user_id = u4));

  -- expiry skips examples
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id, is_example)
  values (v_old_ex, u4, v_old_date, '09:00', 'Probe pickup', 'Probe destination', 'open', c1, true);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id)
  values (v_old_ctl, u4, v_old_date, '09:00', 'Probe pickup', 'Probe destination', 'open', c1);
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, community_id, is_example,
                            hidden_at, hidden_reason)
  values (v_hidden_ex, u4, v_old_date, '09:00', 'Probe pickup', 'Probe destination', 'open', c1, true,
          now(), 'communities probe');
  insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id,
                            is_example)
  values (v_done_ex, u4, v_tomorrow + 2, '09:00', 'Probe pickup', 'Probe destination', 'completed', u3, c1, true);
  insert into public.favors (user_id, title, location, date, status, community_id, is_example, timezone)
  values (u4, 'Probe example favor NZ', 'Probe location', v_nz_date, 'open', c1, true, 'Pacific/Auckland')
  returning id into v_nz_favor;

  perform public.expire_past_open_requests();
  perform pg_temp.probe_ok(v_probe, 'expiry completes the 20-day-old ordinary open ride',
    (select status::text from public.rides where id = v_old_ctl) = 'completed');
  perform pg_temp.probe_ok(v_probe, 'expiry leaves the 20-day-old example open, its date unchanged',
    exists (select 1 from public.rides where id = v_old_ex and status::text = 'open' and date = v_old_date));
  perform pg_temp.probe_ok(v_probe, 'expiry leaves the 9-day-old example favor open',
    (select status::text from public.favors where id = v_nz_favor) = 'open');
  perform pg_temp.probe_ok(v_probe, 'the status-change triggers are enabled again after expiry',
    (select count(*) from pg_catalog.pg_trigger
      where tgname in ('on_ride_status_change_notify', 'on_favor_status_change_notify') and tgenabled = 'O') = 2);

  -- the daily refresh
  n := public.refresh_example_requests();
  perform pg_temp.probe_ok(v_probe, 'the first refresh changes at least the three probe rows (' || n || ')', n >= 3);
  v_date := (select date from public.rides where id = v_old_ex);
  perform pg_temp.probe_ok(v_probe, format('the 20-day-old example moves to [%s, %s] on its weekday (got %s)',
      v_tomorrow, v_tomorrow + 6, v_date),
    v_date between v_tomorrow and v_tomorrow + 6
    and extract(dow from v_date) = extract(dow from v_old_date)
    and (select status::text from public.rides where id = v_old_ex) = 'open');
  v_date := (select date from public.favors where id = v_nz_favor);
  perform pg_temp.probe_ok(v_probe, format('the Auckland example favor moves to [%s, %s] on its weekday (got %s)',
      v_nz_tomorrow, v_nz_tomorrow + 6, v_date),
    v_date between v_nz_tomorrow and v_nz_tomorrow + 6
    and extract(dow from v_date) = extract(dow from v_nz_date));
  perform pg_temp.probe_ok(v_probe, 'the completed example is open again with no helper, its future date kept',
    exists (select 1 from public.rides where id = v_done_ex and status::text = 'open' and claimed_by is null
                                         and date = v_tomorrow + 2));
  perform pg_temp.probe_ok(v_probe, 'the hidden example is left alone',
    exists (select 1 from public.rides where id = v_hidden_ex and date = v_old_date));
  perform pg_temp.probe_ok(v_probe, 'a future example and an ordinary ride are left alone',
    (select date from public.rides where id = v_ex_ride) = current_date + 3
    and (select date from public.rides where id = v_old_ctl) = v_old_date
    and (select status::text from public.rides where id = v_old_ctl) = 'completed');
  n := public.refresh_example_requests();
  perform pg_temp.probe_ok(v_probe, 'a second refresh changes nothing (' || n || ')', n = 0);

  -- set_example_content
  j := pg_temp.probe_call(v_admin, format('public.set_example_content(%L, %L::uuid, false)', 'ride', v_ex_ride));
  perform pg_temp.probe_ok(v_probe, 'the platform admin clears the example ride (changed true): ' || j::text,
    j ->> 'success' = 'true' and j ->> 'changed' = 'true'
    and not (select is_example from public.rides where id = v_ex_ride));
  j := pg_temp.probe_call(v_admin, format('public.set_example_content(%L, %L::uuid, false)', 'ride', v_ex_ride));
  perform pg_temp.probe_ok(v_probe, 'the same call again changes nothing: ' || j::text,
    j ->> 'success' = 'true' and j ->> 'changed' = 'false');
  j := pg_temp.probe_call(v_admin, format('public.set_example_content(%L, %L::uuid, true)', 'ride', v_ctl_ride));
  perform pg_temp.probe_ok(v_probe, 'the platform admin marks the ordinary ride as an example: ' || j::text,
    j ->> 'changed' = 'true' and (select is_example from public.rides where id = v_ctl_ride));
  j := pg_temp.probe_call(v_admin, format('public.set_example_content(%L, %L::uuid, false)', 'favor', v_ex_favor));
  perform pg_temp.probe_ok(v_probe, 'the platform admin clears the example favor: ' || j::text,
    j ->> 'changed' = 'true' and not (select is_example from public.favors where id = v_ex_favor));
  j := pg_temp.probe_call(v_admin, format('public.set_example_content(%L, %L::uuid, false)', 'town_hall_post',
                                          v_ex_post));
  perform pg_temp.probe_ok(v_probe, 'the platform admin clears the example post: ' || j::text,
    j ->> 'changed' = 'true' and not (select is_example from public.town_hall_posts where id = v_ex_post));
  j := pg_temp.probe_call(v_admin, format('public.set_example_content(%L, %L::uuid, true)', 'comment', v_ex_post));
  perform pg_temp.probe_ok(v_probe, 'an unknown type is refused with code invalid: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'code' = 'invalid');
  j := pg_temp.probe_call(v_admin, format('public.set_example_content(%L, %L::uuid, null)', 'ride', v_ex_ride));
  perform pg_temp.probe_ok(v_probe, 'a null flag is refused with code invalid: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'code' = 'invalid');
  j := pg_temp.probe_call(v_member, format('public.set_example_content(%L, %L::uuid, false)', 'ride', v_old_ex));
  perform pg_temp.probe_ok(v_probe, 'the member subject is refused: ' || j::text,
    j ->> 'success' = 'false' and j ->> 'error' = 'Not authorized - admin access required'
    and (select is_example from public.rides where id = v_old_ex));
  j := pg_temp.probe_call(null, format('public.set_example_content(%L, %L::uuid, false)', 'ride', v_old_ex), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call set_example_content (42501): ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');
  j := pg_temp.probe_call(u3, 'public.refresh_example_requests()');
  perform pg_temp.probe_ok(v_probe, 'a client cannot call refresh_example_requests (42501): ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');

  -- the daily job (read only)
  perform pg_temp.probe_ok(v_probe, 'cron.job has refresh-example-requests at 10 11 * * *, active',
    exists (select 1 from cron.job
             where jobname = 'refresh-example-requests' and schedule = '10 11 * * *'
               and command = 'select public.refresh_example_requests()' and active));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback to savepoint probe; release savepoint probe;
select 'PROBE example_content OK' as probe;


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


select 'DRYRUN 20261021_0023 OK' as dryrun;
rollback;
