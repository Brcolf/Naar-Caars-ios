-- 20261018_0002_community_stats_and_broadcast_cap.sql
--
-- NOT APPLIED. Phase 3 of the multi-community design (spec §3.5 rows "admin_dashboard_stats() ..." and
-- "get_community_stats(p_community_id) and the three breakdowns", §4 Phase 3, D14), with the owner decision of
-- 2026-10-17 that platform admins are exempt from the broadcast cap until Phase 3 (20261017_0003:193-198).
--
-- What it does.
--   * can_read_community_stats (new, internal): the caller may read one community's statistics (its admins and the
--     platform admins: is_community_admin), or, for a null community, every community's (platform admins only).
--   * get_community_stats(p_community_id default null) and the breakdowns get_community_stats_fulfilled,
--     get_community_stats_savings, get_community_stats_active_requests (new): the live admin_* bodies with
--     `community_id = p_community_id` on every rides / favors scan, or no filter for a null community. jsonb
--     envelopes: {success:true, fulfilled_count, total_savings, active_rides_count} and {success:true, rows:[...]}
--     with exactly the legacy row keys; {success:false, error} for anyone else.
--   * admin_dashboard_stats(), admin_stats_fulfilled(text, int), admin_stats_savings(text, int),
--     admin_stats_active_rides() (edited in place; live md5 in each block): thin wrappers that keep their signatures,
--     return types and the legacy platform-admin check and message, and return the null-community (every community)
--     result of the new functions. For the installed admin build nothing changes: the numbers already covered every
--     community. (Spec "resolving as above" is read as "platform admins see every community", the platform admins'
--     answer today; see the plan's D-S3.)
--   * send_community_broadcast (edited in place, live md5 df908ac4cf41a160e4f5285af8580c5d): the 3-per-day cap
--     (D14) now applies to platform admins too, and counts only announcements by platform admins and by the
--     community's owners and admins (a member's directly inserted 'announcement' row no longer counts, for anyone).
--     Nothing else changes; the send_broadcast_notifications wrapper is untouched and inherits the cap. Needs
--     is_community_staff (20261018_0001 block 1).
--
-- Apply. After 20261018_0001. Supabase MCP apply_migration, one block per call, in order (blocks 1-5 before the
-- wrappers that call them). No block removes rows, drops a policy, or writes to auth.* / storage.*.
--
-- Verification. Before applying, snapshot as a platform admin: admin_dashboard_stats(), admin_stats_fulfilled('month',
-- 12), admin_stats_fulfilled('week', 12), admin_stats_savings('year', 12), admin_stats_active_rides(). Dry run all
-- ten blocks in one begin; ... rollback; with the probe blocks community_stats, broadcast_cap and short (each block's
-- begin / rollback turned into a savepoint and a rollback to it), and the same
-- five calls after the blocks: equal (active rides compared as a set). Then short after each block, community_stats
-- and broadcast_cap at the end. Outcomes: not yet run.
--
-- What old clients see. Admin dashboard figures and breakdowns: identical. Broadcasts: a platform admin's fourth
-- announcement within 24 hours in the default community is refused; the installed build shows the server's text
-- ("This community has already sent 3 announcements today"). Rows a member typed 'announcement' no longer use up
-- anyone's cap.
--
-- Rollback: send_community_broadcast from 20261017_0003 call 11 (:893-972); the four admin_* bodies from
-- 20260302173326_admin_stats_include_favors.sql:6-47 (admin_dashboard_stats), 20260302171609_admin_stats_fulfilled.sql
-- :8-68, 20260302171619_admin_stats_savings.sql:8-47, 20260302173734_fix_active_rides_status_cast.sql:6-58 (each
-- compared with the live body on 2026-10-18: identical); then drop the five new functions.


-- ============================================================================================
-- BLOCK 1: public.can_read_community_stats(uuid)  (internal)
-- ============================================================================================
create or replace function public.can_read_community_stats(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and case when p_community_id is null then public.is_platform_admin()
              else public.is_community_admin(p_community_id) end;
$$;

revoke all on function public.can_read_community_stats(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 2: public.get_community_stats(uuid)
-- The admin_dashboard_stats body (20260302173326), scoped.
-- ============================================================================================
create or replace function public.get_community_stats(p_community_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fulfilled bigint;
  v_savings numeric(12,2);
  v_active bigint;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce((select count(*) from public.rides r
                    where r.status = 'completed'
                      and (p_community_id is null or r.community_id = p_community_id)), 0)
       + coalesce((select count(*) from public.favors f
                    where f.status = 'completed'
                      and (p_community_id is null or f.community_id = p_community_id)), 0)
    into v_fulfilled;

  select coalesce(sum(r.estimated_cost), 0)
    into v_savings
    from public.rides r
   where r.estimated_cost is not null
     and (p_community_id is null or r.community_id = p_community_id);

  select (select count(*) from public.rides r
           where r.status in ('open', 'pending', 'confirmed')
             and (p_community_id is null or r.community_id = p_community_id))
       + (select count(*) from public.favors f
           where f.status in ('open', 'pending', 'confirmed')
             and (p_community_id is null or f.community_id = p_community_id))
    into v_active;

  return jsonb_build_object(
    'success', true,
    'fulfilled_count', v_fulfilled,
    'total_savings', v_savings,
    'active_rides_count', v_active
  );
end
$$;

revoke all on function public.get_community_stats(uuid) from public, anon;
grant execute on function public.get_community_stats(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 3: public.get_community_stats_fulfilled(uuid, text, integer)
-- The admin_stats_fulfilled body (20260302171609), scoped. p_count is bounded 1..520 (ten years of weeks); the
-- installed build always sends 12.
-- ============================================================================================
create or replace function public.get_community_stats_fulfilled(
  p_community_id uuid default null,
  p_period text default 'month',
  p_count integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trunc text := case p_period when 'week' then 'week' when 'year' then 'year' else 'month' end;
  v_count integer := least(greatest(coalesce(p_count, 12), 1), 520);
  v_rows jsonb;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.period_start desc), '[]'::jsonb)
    into v_rows
    from (
      select combined.period_start,
             sum(combined.ride_count)::bigint as ride_count,
             sum(combined.favor_count)::bigint as favor_count,
             sum(combined.ride_count + combined.favor_count)::bigint as total_count
        from (
          select date_trunc(v_trunc, r.updated_at)::date as period_start,
                 count(*) as ride_count,
                 0 as favor_count
            from public.rides r
           where r.status = 'completed'
             and (p_community_id is null or r.community_id = p_community_id)
           group by date_trunc(v_trunc, r.updated_at)
          union all
          select date_trunc(v_trunc, f.updated_at)::date,
                 0,
                 count(*)
            from public.favors f
           where f.status = 'completed'
             and (p_community_id is null or f.community_id = p_community_id)
           group by date_trunc(v_trunc, f.updated_at)
        ) combined
       group by combined.period_start
       order by combined.period_start desc
       limit v_count
    ) t;

  return jsonb_build_object('success', true, 'rows', v_rows);
end
$$;

revoke all on function public.get_community_stats_fulfilled(uuid, text, integer) from public, anon;
grant execute on function public.get_community_stats_fulfilled(uuid, text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 4: public.get_community_stats_savings(uuid, text, integer)
-- The admin_stats_savings body (20260302171619), scoped.
-- ============================================================================================
create or replace function public.get_community_stats_savings(
  p_community_id uuid default null,
  p_period text default 'month',
  p_count integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trunc text := case p_period when 'week' then 'week' when 'year' then 'year' else 'month' end;
  v_count integer := least(greatest(coalesce(p_count, 12), 1), 520);
  v_rows jsonb;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.period_start desc), '[]'::jsonb)
    into v_rows
    from (
      select date_trunc(v_trunc, r.created_at)::date as period_start,
             coalesce(sum(r.estimated_cost), 0)::numeric(12,2) as total_savings,
             count(*)::bigint as ride_count
        from public.rides r
       where r.estimated_cost is not null
         and (p_community_id is null or r.community_id = p_community_id)
       group by date_trunc(v_trunc, r.created_at)
       order by period_start desc
       limit v_count
    ) t;

  return jsonb_build_object('success', true, 'rows', v_rows);
end
$$;

revoke all on function public.get_community_stats_savings(uuid, text, integer) from public, anon;
grant execute on function public.get_community_stats_savings(uuid, text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 5: public.get_community_stats_active_requests(uuid)
-- The admin_stats_active_rides body (20260302173734), scoped. A community admin is a member of it and already reads
-- its addresses.
-- ============================================================================================
create or replace function public.get_community_stats_active_requests(p_community_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.date asc, t."time" asc), '[]'::jsonb)
    into v_rows
    from (
      select r.id,
             'ride' as type,
             r.pickup as title,
             r.destination as subtitle,
             r.date,
             r."time",
             r.status::text as status,
             r.claimed_by,
             poster.name as poster_name,
             claimer.name as claimer_name
        from public.rides r
        left join public.profiles poster  on poster.id  = r.user_id
        left join public.profiles claimer on claimer.id = r.claimed_by
       where r.status in ('open', 'pending', 'confirmed')
         and (p_community_id is null or r.community_id = p_community_id)
      union all
      select f.id,
             'favor' as type,
             f.title as title,
             f.location as subtitle,
             f.date,
             f."time",
             f.status::text as status,
             f.claimed_by,
             poster.name as poster_name,
             claimer.name as claimer_name
        from public.favors f
        left join public.profiles poster  on poster.id  = f.user_id
        left join public.profiles claimer on claimer.id = f.claimed_by
       where f.status in ('open', 'pending', 'confirmed')
         and (p_community_id is null or f.community_id = p_community_id)
    ) t;

  return jsonb_build_object('success', true, 'rows', v_rows);
end
$$;

revoke all on function public.get_community_stats_active_requests(uuid) from public, anon;
grant execute on function public.get_community_stats_active_requests(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 6: public.admin_dashboard_stats()   live md5(prosrc) 5e27ad2aa06507f20a3ada5efd78646b
-- Wrapper. The legacy check and message are kept (a banned platform admin, whom the legacy body let through, is now
-- refused by is_platform_admin with the same message; such an account cannot use the app).
-- ============================================================================================
create or replace function public.admin_dashboard_stats()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats(null);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return (v - 'success')::json;
end
$$;

revoke all on function public.admin_dashboard_stats() from public, anon;
grant execute on function public.admin_dashboard_stats() to authenticated;


-- ============================================================================================
-- BLOCK 7: public.admin_stats_fulfilled(text, integer)   live md5(prosrc) 687d59d37ad68aad9c736a4224f2bbea
-- ============================================================================================
create or replace function public.admin_stats_fulfilled(
    p_period text default 'month',
    p_count integer default 12
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats_fulfilled(null, p_period, p_count);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return coalesce(v -> 'rows', '[]'::jsonb)::json;
end
$$;

revoke all on function public.admin_stats_fulfilled(text, integer) from public, anon;
grant execute on function public.admin_stats_fulfilled(text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 8: public.admin_stats_savings(text, integer)   live md5(prosrc) 81653c495a17d65d350fbac3c7eb0214
-- ============================================================================================
create or replace function public.admin_stats_savings(
    p_period text default 'month',
    p_count integer default 12
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats_savings(null, p_period, p_count);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return coalesce(v -> 'rows', '[]'::jsonb)::json;
end
$$;

revoke all on function public.admin_stats_savings(text, integer) from public, anon;
grant execute on function public.admin_stats_savings(text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 9: public.admin_stats_active_rides()   live md5(prosrc) 50a14b5c0e97e06f30f424898f90f84a
-- ============================================================================================
create or replace function public.admin_stats_active_rides()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats_active_requests(null);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return coalesce(v -> 'rows', '[]'::jsonb)::json;
end
$$;

revoke all on function public.admin_stats_active_rides() from public, anon;
grant execute on function public.admin_stats_active_rides() to authenticated;


-- ============================================================================================
-- BLOCK 10: public.send_community_broadcast(uuid, text, text, boolean, text)
--   live md5(prosrc) df908ac4cf41a160e4f5285af8580c5d (20261017_0003 call 11)
-- Two changes. (1) The D14 cap (3 announcements per community in any 24 hours) applies to platform admins too
-- (owner decision 2026-10-17: "exempt until Phase 3"). (2) The cap counts only announcements written by a platform
-- admin or by an active owner or admin of the community, read when the new one is sent. town_hall_posts_insert_active_user
-- (20261017_0002 [A09]) does not restrict `type`, so any active member can insert rows typed 'announcement' directly;
-- counted, three of them would lock the community, platform admins included, out of announcements for a day. A
-- demoted admin's earlier announcements stop counting (no role history is kept); that can only loosen the cap.
-- The refusal keeps SQLSTATE P0001, which the Phase 3 client maps to its daily-limit message.
-- ============================================================================================
create or replace function public.send_community_broadcast(
    p_community_id uuid,
    p_title text,
    p_body text,
    p_pinned boolean,
    p_type text default 'broadcast'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_uid uuid := (select auth.uid());
    v_post_id uuid;
    v_member record;
    v_notification_id uuid;
    v_inserted_count integer := 0;
    v_type text;
begin
    if v_uid is null then
        raise exception 'Only admins can send broadcast notifications' using errcode = '42501';
    end if;

    -- Deviation 4 of 20261017_0003 (owner decision 2026-10-17): the type is passed through, limited to the three
    -- announcement types should_notify_user already accepts.
    v_type := coalesce(nullif(btrim(p_type), ''), 'broadcast');
    if v_type not in ('broadcast', 'admin_announcement', 'announcement') then
        raise exception 'Unsupported announcement type' using errcode = '22023';
    end if;

    if p_community_id is null or not public.is_community_admin(p_community_id) then
        raise exception 'Only admins of this community can send announcements' using errcode = '42501';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('community_broadcast:' || p_community_id::text, 0));

    -- D14: at most 3 announcements per community in any 24 hours, for every sender (Phase 3). Only announcements
    -- by a platform admin or by this community's owners and admins count: a member can write a row typed
    -- 'announcement' through the insert policy, and must not be able to use up the community's cap.
    if (select count(*)
          from public.town_hall_posts t
          left join public.profiles a on a.id = t.user_id
         where t.community_id = p_community_id
           and t.type = 'announcement'
           and t.created_at > now() - interval '24 hours'
           and (coalesce(a.is_admin, false) or public.is_community_staff(p_community_id, t.user_id))) >= 3 then
        raise exception 'This community has already sent 3 announcements today' using errcode = 'P0001';
    end if;

    insert into public.town_hall_posts (
        user_id, title, content, pinned, type, community_id, created_at, updated_at
    ) values (
        v_uid, p_title, p_body, coalesce(p_pinned, false), 'announcement', p_community_id, now(), now()
    )
    returning id into v_post_id;

    for v_member in
        select m.user_id
          from public.community_members m
          join public.profiles p on p.id = m.user_id
          join public.communities c on c.id = m.community_id and c.archived_at is null
         where m.community_id = p_community_id
           and m.status = 'active'
           and not p.is_banned
           and m.user_id <> v_uid
           and not m.notifications_muted
           and (m.muted_until is null or m.muted_until < now())
    loop
        v_notification_id := public.create_notification(
            v_member.user_id, v_type, p_title, p_body,
            null, null, null, null, v_post_id, v_uid, coalesce(p_pinned, false)
        );
        if v_notification_id is not null then
            v_inserted_count := v_inserted_count + 1;
        end if;
    end loop;

    return v_inserted_count;
end;
$function$;

revoke all on function public.send_community_broadcast(uuid, text, text, boolean, text) from public, anon;
grant execute on function public.send_community_broadcast(uuid, text, text, boolean, text) to authenticated, service_role;
