-- 20261017_0005_communities_rpcs.sql
--
-- NOT APPLIED: waits for step 4 (20261017_0004, the owner's SQL-editor step). Steps 0-3 are live as
-- of 2026-10-18. Phase 0, step 5 of the multi-community design
-- (Docs/superpowers/specs/2026-10-07-multi-community-design.md §3.5 "New RPCs", §4 step 5) with the
-- owner's decisions of 2026-10-17 (Docs/superpowers/specs/2026-10-17-multi-community-decisions.md,
-- which wins where the two differ).
--
-- What it does: adds the membership, invite, directory, context, report, limit and platform RPCs.
-- From the moment create_community is applied a second community can exist; everything that
-- isolates one (steps 1-4: tables, helpers, mirror, fill triggers, RLS, fan-out, lifecycle) must
-- already be live. Every RPC is SECURITY DEFINER with search_path = '', checks its caller inside,
-- answers a refusal with jsonb {success: false, error[, code]} (the create_signup_profile shape;
-- `code` is a stable machine key for the client), and writes one community_membership_events row
-- per status or role transition. EXECUTE goes to `authenticated` only; the internal helpers and the
-- trigger function are revoked from every client role.
--
-- Decisions applied here:
--   A1  create_community: 1 per account per rolling day, and at most profiles.max_owned_communities
--       (default 3) live owned communities; request_owned_community_limit / decide_owned_community_limit
--       with announcement bell rows (no push); get_my_community_limits for the My communities screen;
--       get_platform_communities returns the open limit requests beside the communities.
--   A2  report_community accepts any community the caller can read under the communities SELECT
--       policy (public, member, admin, pending applicant) or a valid code; platform admins only
--       (reports.community_id stays null). set_community_public lets a platform admin flag a
--       community private (the A2 remedy; D7 keeps is_public platform-admin only).
--   A3  claim_community_ownership is not created (no ownerless state). leave_community: the last
--       owner must hand over first unless they are the only member, then leaving archives.
--   D21 notify_pending_membership (an application goes to the community's active owner and admins,
--       and to the platform admins only when the community has none) is NOT redefined here: its one
--       body is 20261017_0001 [call] 1h.2 (block 6 is left empty on purpose).
--
-- Not in this file, on purpose: unwind_member_requests (step 4, SQL editor; called here by
-- leave_community and remove_community_member), send_community_broadcast, get_community_leaderboard,
-- get_community_spotlights, get_profile_stats (step 3), and the Phase 3 get_community_reports,
-- moderate_community_content, get_community_stats.
--
-- Depends on (created by 20261017_0001..0004): communities, community_members, community_invites,
-- community_invite_redemptions, community_invite_attempts, community_membership_events,
-- community_limit_requests, profiles.max_owned_communities, profiles.primary_community_id,
-- notifications.community_id, reports.reported_community_id (+ report_target_check extension), the
-- helpers is_active_member / is_community_admin / is_platform_admin / my_community_ids /
-- my_admin_community_ids, the mirror (naars.membership_mirror escape in protect_admin_fields), the
-- naars.suppress_approval_notice guard in notify_user_approved, guard_last_owner, and the
-- notify_pending_membership function and trigger (step 1h), which this file does not touch.
--
-- Apply: one block per MCP call, in order (blocks 1-5 first: later bodies call them; block 6 is
-- empty). Function
-- bodies here delete only from public.community_members (reject); nothing touches auth.* or
-- storage.*, so every block is MCP-appliable. Record md5(prosrc) of each deployed body here.
--
-- Probes (to run in one rolled-back transaction before applying, and again after; see
-- supabase/probes/communities_probe.sql): create a community (second create the same day refused
-- with code daily_limit; fourth owned refused with code owned_limit; limit request -> announcement row
-- per platform admin; approve -> max raised and requester told); member invite is single-use and
-- expires within 7 days whatever the arguments; the 11th failed validation in an hour is refused;
-- validate_community_invite as anon -> permission denied; redeem into an approval community ->
-- pending row and exactly one pending_approval row + queue row for its owner, none for a Seattle
-- admin; approve -> active, mirror flips approved; reject deletes the row only; removed member
-- cannot redeem; banned caller gets error 'restricted' on redeem / request / approve; leave as last
-- owner with members refused, as the only member archives; get_community_members returns null
-- answers to a member and the answers to an admin, and leaves out blocked people for a member only;
-- report_community on a public community creates a report only platform admins read.
-- Outcomes: not yet run.
--
-- What old clients see: nothing. No installed build calls any of these functions. The one change an
-- installed admin build can observe is the pending_approval text from notify_pending_membership
-- ("New request to join <community>" / "<name> wants to join."), which arrives with step 1h.
--
-- Sequencing note: reject_community_member sends user_rejected and remove_community_member sends
-- account_restricted. The spec places both producers in Phase 3; they ship here, in Phase 0 step 5,
-- with the RPCs that need them (the decisions keep Phase 3 in scope, and the installed build already
-- knows both types). No installed build calls either RPC, so neither notice is sent before a new
-- build ships.


-- ============================================================================================
-- BLOCK 1: public.my_community_role(uuid)  (internal)
-- The caller's role in a live community they are an active, unbanned member of; else null.
-- ============================================================================================
create or replace function public.my_community_role(p_community_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
    from public.community_members m
    join public.profiles p    on p.id = m.user_id and not coalesce(p.is_banned, false)
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.community_id = p_community_id
     and m.user_id = (select auth.uid())
     and m.status = 'active';
$$;

revoke all on function public.my_community_role(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 2: public.notify_user_in_community(...)  (internal)
-- One entity-less bell row (through create_notification, so should_notify_user still gates it),
-- tagged with the community by a direct UPDATE on the returned id (spec §3.3), plus an optional push
-- that carries community_id in its data.
-- ============================================================================================
create or replace function public.notify_user_in_community(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_community_id uuid,
  p_push boolean default false,
  p_data jsonb default '{}'::jsonb,
  p_source_user_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  v_id := public.create_notification(
    p_user_id, p_type, p_title, p_body,
    null::uuid, null::uuid, null::uuid, null::uuid, null::uuid, p_source_user_id, false
  );
  if v_id is null then
    return null;
  end if;

  if p_community_id is not null then
    update public.notifications set community_id = p_community_id
     where id = v_id and community_id is null;
  end if;

  if p_push then
    perform public.queue_push_notification(
      p_user_id, p_type, p_title, p_body,
      coalesce(p_data, '{}'::jsonb)
        || case when p_community_id is null then '{}'::jsonb
                else jsonb_build_object('community_id', p_community_id::text) end,
      null::text,
      v_id
    );
  end if;

  return v_id;
end
$$;

revoke all on function public.notify_user_in_community(uuid, text, text, text, uuid, boolean, jsonb, uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 3: public.lookup_community_invite(text)  (internal)
-- Resolves a typed code (case, spaces and dashes ignored) to its invite and a state:
-- valid | expired | exhausted | revoked. A code made by a plain member stops working when the
-- owner turns member invites off; a code in an archived community reads as revoked.
-- ============================================================================================
create or replace function public.lookup_community_invite(p_code text)
returns table (
  invite_id uuid,
  community_id uuid,
  created_by uuid,
  state text,
  community_name text,
  join_policy text,
  is_public boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, i.community_id, i.created_by,
         case
           when i.revoked_at is not null or c.archived_at is not null then 'revoked'
           when i.expires_at is not null and i.expires_at <= now() then 'expired'
           when i.max_uses is not null and i.use_count >= i.max_uses then 'exhausted'
           when not c.members_can_invite
                and not exists (select 1 from public.community_members m
                                 where m.community_id = i.community_id and m.user_id = i.created_by
                                   and m.status = 'active' and m.role in ('owner', 'admin'))
                and not exists (select 1 from public.profiles p where p.id = i.created_by and p.is_admin)
             then 'revoked'
           else 'valid'
         end,
         c.name, c.join_policy, c.is_public
    from public.community_invites i
    join public.communities c on c.id = i.community_id
   where i.code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

revoke all on function public.lookup_community_invite(text) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 4: public.invite_attempts_exceeded(uuid)  (internal)
-- The brute-force bound shared by validate, redeem and report-by-code: 10 failed attempts in an
-- hour. Refused calls are not recorded, so the lock ends an hour after the tenth failure.
-- ============================================================================================
create or replace function public.invite_attempts_exceeded(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select count(*) >= 10
    from public.community_invite_attempts a
   where a.user_id = p_user_id
     and not a.succeeded
     and a.attempted_at > now() - interval '1 hour';
$$;

revoke all on function public.invite_attempts_exceeded(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 5: public.archive_community_with_notices(uuid, uuid)  (internal)
-- Shared by archive_community and leave_community (the only member leaving). Tells every other
-- active member, tells the poster and the helper of each confirmed request that it was cancelled
-- and drops its completion reminder (as 20261017_0004 STEP A does for the same archive case, so
-- process_completion_reminders sends nothing for a request in an archived community), then sets
-- archived_at (which fires recompute_flags_on_archive) and writes the 'archived' event.
-- Content is kept unchanged so unarchive_community restores it. The caller has already checked
-- permission and that the community is not the default one.
-- ============================================================================================
create or replace function public.archive_community_with_notices(p_community_id uuid, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  r record;
begin
  select c.name into v_name
    from public.communities c
   where c.id = p_community_id and c.archived_at is null and not c.is_default
   for update;
  if not found then
    return;
  end if;

  for r in
    select m.user_id from public.community_members m
     where m.community_id = p_community_id and m.status = 'active'
       and m.user_id is distinct from p_actor
  loop
    perform public.notify_user_in_community(
      r.user_id, 'announcement', v_name || ' was archived',
      'Its requests and posts are no longer visible.', p_community_id, false, '{}'::jsonb, null
    );
  end loop;

  for r in
    select x.id, x.user_id, x.claimed_by from public.rides x
     where x.community_id = p_community_id and x.status = 'confirmed' and x.claimed_by is not null
  loop
    perform public.create_notification(r.user_id, 'ride_unclaimed', 'Ride Cancelled',
      'Your ride was cancelled because ' || v_name || ' was archived.',
      r.id, null::uuid, null::uuid, null::uuid, null::uuid, null::uuid, false);
    perform public.create_notification(r.claimed_by, 'ride_unclaimed', 'Ride Cancelled',
      'A ride you claimed was cancelled because ' || v_name || ' was archived.',
      r.id, null::uuid, null::uuid, null::uuid, null::uuid, null::uuid, false);
    delete from public.completion_reminders where ride_id = r.id;   -- as 0004 STEP A: no reminder push for an archived request
  end loop;

  for r in
    select x.id, x.user_id, x.claimed_by from public.favors x
     where x.community_id = p_community_id and x.status = 'confirmed' and x.claimed_by is not null
  loop
    perform public.create_notification(r.user_id, 'favor_unclaimed', 'Favor Cancelled',
      'Your favor was cancelled because ' || v_name || ' was archived.',
      null::uuid, r.id, null::uuid, null::uuid, null::uuid, null::uuid, false);
    perform public.create_notification(r.claimed_by, 'favor_unclaimed', 'Favor Cancelled',
      'A favor you claimed was cancelled because ' || v_name || ' was archived.',
      null::uuid, r.id, null::uuid, null::uuid, null::uuid, null::uuid, false);
    delete from public.completion_reminders where favor_id = r.id;
  end loop;

  update public.communities
     set archived_at = now(), archived_by = p_actor, updated_at = now()
   where id = p_community_id;

  insert into public.community_membership_events (community_id, user_id, actor_id, event)
  values (p_community_id, null, p_actor, 'archived');
end
$$;

revoke all on function public.archive_community_with_notices(uuid, uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 6: removed. notify_pending_membership() is defined once, in 20261017_0001 [call] 1h.2
-- (D21 recipients, the same text and push data). The block number is kept so references to the
-- later blocks stay valid.
-- ============================================================================================


-- ============================================================================================
-- BLOCK 7: public.create_community(text, text, text)
-- Any signed-in, unbanned account (approval not required). A1 limits: one per rolling day, and at
-- most profiles.max_owned_communities live owned communities. The creator becomes the active owner
-- with the approval notice suppressed; the mirror sets the primary if it was null. Each platform
-- admin gets an announcement bell row (no push).
-- ============================================================================================
create or replace function public.create_community(
  p_name text,
  p_description text default null,
  p_join_policy text default 'approve'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile record;
  v_name text := btrim(coalesce(p_name, ''));
  v_desc text := nullif(btrim(coalesce(p_description, '')), '');
  v_policy text := coalesce(p_join_policy, 'approve');
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
    return jsonb_build_object('success', false, 'error', 'Unknown join policy');
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

  insert into public.communities (name, description, created_by, join_policy)
  values (v_name, v_desc, v_uid, v_policy)
  returning id into v_id;

  -- A creator is already looking at the app: no "you've been approved" notice.
  perform set_config('naars.suppress_approval_notice', '1', true);
  insert into public.community_members (community_id, user_id, role, status, activated_at)
  values (v_id, v_uid, 'owner', 'active', now());
  perform set_config('naars.suppress_approval_notice', '', true);

  insert into public.community_membership_events (community_id, user_id, actor_id, event, new_role, reason)
  values (v_id, v_uid, v_uid, 'approved', 'owner', 'created the community');

  for v_admin in
    select p.id from public.profiles p
     where p.is_admin and not coalesce(p.is_banned, false) and p.id <> v_uid
  loop
    perform public.notify_user_in_community(
      v_admin, 'announcement', 'New community: ' || v_name,
      'Created by ' || coalesce(nullif(btrim(v_profile.name), ''), 'a member') || '.',
      v_id, false, '{}'::jsonb, v_uid
    );
  end loop;

  return jsonb_build_object('success', true, 'community_id', v_id);
end
$$;

revoke all on function public.create_community(text, text, text) from public, anon;
grant execute on function public.create_community(text, text, text) to authenticated;


-- ============================================================================================
-- BLOCK 8: public.get_my_community_limits()
-- For My communities (A1): the owned limit, how many are owned, whether Create is available today,
-- and the caller's latest limit request (its status shows until decided).
-- ============================================================================================
create or replace function public.get_my_community_limits()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_max integer;
  v_owned integer;
  v_last timestamptz;
  v_request jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  select coalesce(p.max_owned_communities, 3) into v_max from public.profiles p where p.id = v_uid;
  if v_max is null then
    return jsonb_build_object('success', false, 'error', 'Finish creating your profile first');
  end if;

  select count(*) into v_owned
    from public.community_members m
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = v_uid and m.status = 'active' and m.role = 'owner';

  select max(c.created_at) into v_last from public.communities c where c.created_by = v_uid;

  select jsonb_build_object('request_id', r.id, 'requested_max', r.requested_max, 'reason', r.reason,
                            'status', r.status, 'created_at', r.created_at, 'decided_at', r.decided_at)
    into v_request
    from public.community_limit_requests r
   where r.user_id = v_uid
   order by r.created_at desc
   limit 1;

  return jsonb_build_object(
    'success', true,
    'max_owned', v_max,
    'owned_count', v_owned,
    'next_create_at', case when v_last > now() - interval '1 day' then v_last + interval '1 day' end,
    'can_create', v_owned < v_max and (v_last is null or v_last <= now() - interval '1 day'),
    'latest_request', v_request
  );
end
$$;

revoke all on function public.get_my_community_limits() from public, anon;
grant execute on function public.get_my_community_limits() to authenticated;


-- ============================================================================================
-- BLOCK 9: public.request_owned_community_limit(integer, text)
-- A1: a member at their owned limit asks for 4..20; reason required; one open request per account.
-- Each platform admin gets an announcement bell row (no push, no community).
-- ============================================================================================
create or replace function public.request_owned_community_limit(p_requested integer, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile record;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_owned integer;
  v_id uuid;
  v_admin uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  select p.name, p.is_banned, coalesce(p.max_owned_communities, 3) as max_owned into v_profile
    from public.profiles p where p.id = v_uid;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Finish creating your profile first');
  end if;
  if coalesce(v_profile.is_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  if p_requested is null or p_requested not between 4 and 20 then
    return jsonb_build_object('success', false, 'error', 'Ask for a limit between 4 and 20');
  end if;
  if v_reason is null then
    return jsonb_build_object('success', false, 'error', 'Say why you need more communities');
  end if;
  if char_length(v_reason) > 500 then
    return jsonb_build_object('success', false, 'error', 'The reason can be at most 500 characters');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('community_limit_request:' || v_uid::text, 0));

  if p_requested <= v_profile.max_owned then
    return jsonb_build_object('success', false,
      'error', 'Ask for more than your current limit of ' || v_profile.max_owned);
  end if;

  select count(*) into v_owned
    from public.community_members m
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = v_uid and m.status = 'active' and m.role = 'owner';
  if v_owned < v_profile.max_owned then
    return jsonb_build_object('success', false,
      'error', 'You can still create communities under your current limit', 'code', 'under_limit');
  end if;

  if exists (select 1 from public.community_limit_requests r
              where r.user_id = v_uid and r.status = 'pending') then
    return jsonb_build_object('success', false,
      'error', 'You already have a request waiting for a decision', 'code', 'request_open');
  end if;

  insert into public.community_limit_requests (user_id, requested_max, reason, status)
  values (v_uid, p_requested, v_reason, 'pending')
  returning id into v_id;

  for v_admin in
    select p.id from public.profiles p
     where p.is_admin and not coalesce(p.is_banned, false) and p.id <> v_uid
  loop
    perform public.notify_user_in_community(
      v_admin, 'announcement',
      coalesce(nullif(btrim(v_profile.name), ''), 'A member') || ' asks to own up to ' || p_requested || ' communities',
      v_reason, null, false, '{}'::jsonb, v_uid
    );
  end loop;

  return jsonb_build_object('success', true, 'request_id', v_id);
end
$$;

revoke all on function public.request_owned_community_limit(integer, text) from public, anon;
grant execute on function public.request_owned_community_limit(integer, text) to authenticated;


-- ============================================================================================
-- BLOCK 10: public.decide_owned_community_limit(uuid, boolean)
-- A1: a platform admin approves (max_owned_communities raised to the requested value, never
-- lowered) or declines; the requester gets an announcement row either way. The profiles write
-- passes protect_admin_fields because the caller is a platform admin.
-- ============================================================================================
create or replace function public.decide_owned_community_limit(p_request_id uuid, p_approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_req record;
  v_max integer;
begin
  if v_uid is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;
  if p_approve is null then
    return jsonb_build_object('success', false, 'error', 'Choose approve or decline');
  end if;

  select r.id, r.user_id, r.requested_max, r.status into v_req
    from public.community_limit_requests r
   where r.id = p_request_id
   for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Request not found');
  end if;
  if v_req.status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'This request was already decided');
  end if;

  update public.community_limit_requests
     set status = case when p_approve then 'approved' else 'declined' end,
         decided_by = v_uid,
         decided_at = now()
   where id = v_req.id;

  if p_approve then
    update public.profiles
       set max_owned_communities = greatest(coalesce(max_owned_communities, 3), v_req.requested_max)
     where id = v_req.user_id;
  end if;

  select coalesce(p.max_owned_communities, 3) into v_max from public.profiles p where p.id = v_req.user_id;

  if p_approve then
    perform public.notify_user_in_community(
      v_req.user_id, 'announcement', 'You can now own up to ' || v_max || ' communities',
      'A platform admin approved your request.', null, false, '{}'::jsonb, null);
  else
    perform public.notify_user_in_community(
      v_req.user_id, 'announcement', 'Request for more communities declined',
      'You can still own up to ' || coalesce(v_max, 3) || ' communities.', null, false, '{}'::jsonb, null);
  end if;

  return jsonb_build_object('success', true, 'status', case when p_approve then 'approved' else 'declined' end,
                            'max_owned', v_max);
end
$$;

revoke all on function public.decide_owned_community_limit(uuid, boolean) from public, anon;
grant execute on function public.decide_owned_community_limit(uuid, boolean) to authenticated;


-- ============================================================================================
-- BLOCK 11: public.update_community(uuid, text, text, text, boolean, text)
-- Owner (or platform admin) of a live community. A null argument leaves that field unchanged; an
-- empty description clears it. is_public and is_default are not editable here (D7).
-- ============================================================================================
create or replace function public.update_community(
  p_community_id uuid,
  p_name text default null,
  p_description text default null,
  p_join_policy text default null,
  p_members_can_invite boolean default null,
  p_timezone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_name text := btrim(p_name);
  v_desc text := btrim(p_description);
begin
  if v_uid is null or not (public.is_community_admin(p_community_id)
                           and (public.my_community_role(p_community_id) = 'owner' or public.is_platform_admin())) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can change this community');
  end if;

  if v_name is not null and char_length(v_name) not between 2 and 60 then
    return jsonb_build_object('success', false, 'error', 'A community name needs 2 to 60 characters');
  end if;
  if v_desc is not null and char_length(v_desc) > 300 then
    return jsonb_build_object('success', false, 'error', 'The description can be at most 300 characters');
  end if;
  if p_join_policy is not null and p_join_policy not in ('invite', 'approve') then
    return jsonb_build_object('success', false, 'error', 'Unknown join policy');
  end if;
  if p_timezone is not null and not exists (select 1 from pg_catalog.pg_timezone_names t where t.name = p_timezone) then
    return jsonb_build_object('success', false, 'error', 'Unknown time zone');
  end if;

  update public.communities c
     set name = coalesce(v_name, c.name),
         description = case when p_description is null then c.description else nullif(v_desc, '') end,
         join_policy = coalesce(p_join_policy, c.join_policy),
         members_can_invite = coalesce(p_members_can_invite, c.members_can_invite),
         timezone = coalesce(p_timezone, c.timezone),
         updated_at = now()
   where c.id = p_community_id and c.archived_at is null;

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.update_community(uuid, text, text, text, boolean, text) from public, anon;
grant execute on function public.update_community(uuid, text, text, text, boolean, text) to authenticated;


-- ============================================================================================
-- BLOCK 12: public.set_community_public(uuid, boolean)
-- Platform admins only (D7; A2's remedy for a reported public community). The default community
-- stays public, because the guest path Apple reviewed reads it.
-- ============================================================================================
create or replace function public.set_community_public(p_community_id uuid, p_is_public boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_default boolean;
begin
  if (select auth.uid()) is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;
  if p_is_public is null then
    return jsonb_build_object('success', false, 'error', 'Choose public or private');
  end if;

  select c.is_default into v_default
    from public.communities c where c.id = p_community_id and c.archived_at is null;
  if v_default is null then
    return jsonb_build_object('success', false, 'error', 'Community not found');
  end if;
  if v_default and not p_is_public then
    return jsonb_build_object('success', false, 'error', 'The default community stays public');
  end if;

  update public.communities set is_public = p_is_public, updated_at = now()
   where id = p_community_id and is_public is distinct from p_is_public;

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.set_community_public(uuid, boolean) from public, anon;
grant execute on function public.set_community_public(uuid, boolean) to authenticated;


-- ============================================================================================
-- BLOCK 13: public.archive_community(uuid)
-- The owner or a platform admin. The default community cannot be archived (INV-L1).
-- ============================================================================================
create or replace function public.archive_community(p_community_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_c record;
begin
  if v_uid is null or not (public.my_community_role(p_community_id) = 'owner' or public.is_platform_admin()) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can archive this community');
  end if;

  select c.is_default, c.archived_at into v_c from public.communities c where c.id = p_community_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Community not found');
  end if;
  if v_c.is_default then
    return jsonb_build_object('success', false, 'error', 'The default community cannot be archived');
  end if;
  if v_c.archived_at is not null then
    return jsonb_build_object('success', false, 'error', 'This community is already archived');
  end if;

  perform public.archive_community_with_notices(p_community_id, v_uid);

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.archive_community(uuid) from public, anon;
grant execute on function public.archive_community(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 14: public.unarchive_community(uuid)
-- Platform admins only. Clearing archived_at fires recompute_flags_on_archive, which restores each
-- member's flags.
-- ============================================================================================
create or replace function public.unarchive_community(p_community_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;

  update public.communities
     set archived_at = null, archived_by = null, updated_at = now()
   where id = p_community_id and archived_at is not null;
  if not found then
    return jsonb_build_object('success', false, 'error', 'This community is not archived');
  end if;

  insert into public.community_membership_events (community_id, user_id, actor_id, event)
  values (p_community_id, null, v_uid, 'unarchived');

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.unarchive_community(uuid) from public, anon;
grant execute on function public.unarchive_community(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 15: public.create_community_invite(uuid, integer, timestamptz)
-- Limits are enforced here, not in the client (INV-I1). A plain member (when members_can_invite)
-- always gets a single-use code that expires within 7 days, at most 10 live codes per community.
-- An admin (owner, admin, or platform admin) sets 1..1000 uses and must set an expiry within 90
-- days, at most 25 live codes per community. Code: 'NC' + 8 symbols from the 31-symbol alphabet,
-- drawn from extensions.gen_random_bytes with rejection sampling, retried on a unique violation.
-- ============================================================================================
create or replace function public.create_community_invite(
  p_community_id uuid,
  p_max_uses integer default null,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_role text;
  v_is_admin boolean;
  v_can_member boolean;
  v_max integer;
  v_exp timestamptz;
  v_cap integer;
  v_live integer;
  v_code text;
  v_bytes bytea;
  v_b integer;
  v_id uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  v_role := public.my_community_role(p_community_id);
  v_is_admin := public.is_community_admin(p_community_id);
  if not v_is_admin then
    if v_role is null then
      return jsonb_build_object('success', false, 'error', 'Only members can invite people');
    end if;
    select c.members_can_invite into v_can_member from public.communities c where c.id = p_community_id;
    if not coalesce(v_can_member, false) then
      return jsonb_build_object('success', false, 'error', 'Only admins can invite people to this community');
    end if;
  end if;

  if v_is_admin then
    v_max := coalesce(p_max_uses, 1);
    if v_max not between 1 and 1000 then
      return jsonb_build_object('success', false, 'error', 'A code can be used 1 to 1,000 times');
    end if;
    if p_expires_at is null or p_expires_at <= now() or p_expires_at > now() + interval '90 days' then
      return jsonb_build_object('success', false, 'error', 'Choose an expiry within the next 90 days');
    end if;
    v_exp := p_expires_at;
    v_cap := 25;
  else
    v_max := 1;
    v_exp := least(coalesce(p_expires_at, now() + interval '7 days'), now() + interval '7 days');
    if v_exp <= now() then
      v_exp := now() + interval '7 days';
    end if;
    v_cap := 10;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('community_invite_create:' || p_community_id::text || ':' || v_uid::text, 0));

  select count(*) into v_live
    from public.community_invites i
   where i.community_id = p_community_id and i.created_by = v_uid
     and i.revoked_at is null
     and (i.expires_at is null or i.expires_at > now())
     and (i.max_uses is null or i.use_count < i.max_uses);
  if v_live >= v_cap then
    return jsonb_build_object('success', false,
      'error', 'You have ' || v_live || ' codes that still work. Revoke one first.', 'code', 'too_many_codes');
  end if;

  for v_attempt in 1..8 loop
    v_code := 'NC';
    while char_length(v_code) < 10 loop
      v_bytes := extensions.gen_random_bytes(16);
      for i in 0..15 loop
        v_b := get_byte(v_bytes, i);
        -- 248 = 8 * 31: values at or above it would bias the modulo, so they are skipped.
        if v_b < 248 then
          v_code := v_code || substr(v_alphabet, (v_b % 31) + 1, 1);
          exit when char_length(v_code) = 10;
        end if;
      end loop;
    end loop;

    begin
      insert into public.community_invites (community_id, code, created_by, max_uses, expires_at)
      values (p_community_id, v_code, v_uid, v_max, v_exp)
      returning id into v_id;
      exit;
    exception when unique_violation then
      v_id := null;
    end;
  end loop;

  if v_id is null then
    return jsonb_build_object('success', false, 'error', 'Could not create a code. Try again.');
  end if;

  return jsonb_build_object('success', true, 'code', v_code, 'invite_id', v_id,
                            'max_uses', v_max, 'expires_at', v_exp);
end
$$;

revoke all on function public.create_community_invite(uuid, integer, timestamptz) from public, anon;
grant execute on function public.create_community_invite(uuid, integer, timestamptz) to authenticated;


-- ============================================================================================
-- BLOCK 16: public.revoke_community_invite(uuid)
-- The code's creator or an admin of its community.
-- ============================================================================================
create or replace function public.revoke_community_invite(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_inv record;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  select i.community_id, i.created_by into v_inv
    from public.community_invites i where i.id = p_invite_id;
  if not found or not (v_inv.created_by = v_uid or public.is_community_admin(v_inv.community_id)) then
    return jsonb_build_object('success', false, 'error', 'Code not found');
  end if;

  update public.community_invites set revoked_at = now()
   where id = p_invite_id and revoked_at is null;

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.revoke_community_invite(uuid) from public, anon;
grant execute on function public.revoke_community_invite(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 17: public.validate_community_invite(text)
-- Authenticated only (a signed-out code waits in PendingInviteStore). Read-only preview with no ids;
-- member_count only for a public community. Every call is recorded; after 10 failed attempts in an
-- hour the account is refused until the hour has passed.
-- ============================================================================================
create or replace function public.validate_community_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_inv record;
  v_found boolean;
  v_member_count integer;
  v_already boolean;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('community_invite:' || v_uid::text, 0));

  if public.invite_attempts_exceeded(v_uid) then
    return jsonb_build_object('success', false,
      'error', 'Too many codes tried. Try again in an hour.', 'code', 'rate_limited');
  end if;

  select * into v_inv from public.lookup_community_invite(p_code) limit 1;
  v_found := found;

  insert into public.community_invite_attempts (user_id, succeeded)
  values (v_uid, v_found and v_inv.state = 'valid');

  if not v_found or v_inv.state = 'revoked' then
    return jsonb_build_object('success', true, 'valid', false, 'expired', false);
  end if;
  if v_inv.state in ('expired', 'exhausted') then
    return jsonb_build_object('success', true, 'valid', false, 'expired', true,
                              'community_name', v_inv.community_name);
  end if;

  if v_inv.is_public then
    select count(*) into v_member_count
      from public.community_members m
      join public.profiles p on p.id = m.user_id and not coalesce(p.is_banned, false)
     where m.community_id = v_inv.community_id and m.status = 'active';
  end if;

  select exists (select 1 from public.community_members m
                  where m.community_id = v_inv.community_id and m.user_id = v_uid
                    and m.status in ('active', 'pending'))
    into v_already;

  return jsonb_build_object('success', true, 'valid', true, 'expired', false,
                            'requires_approval', v_inv.join_policy = 'approve',
                            'community_name', v_inv.community_name,
                            'already_member', v_already)
         || case when v_member_count is null then '{}'::jsonb
                 else jsonb_build_object('member_count', v_member_count) end;
end
$$;

revoke all on function public.validate_community_invite(text) from public, anon;
grant execute on function public.validate_community_invite(text) to authenticated;


-- ============================================================================================
-- BLOCK 18: public.redeem_community_invite(text, text, text)
-- Self. Shares the attempt limit. A platform-banned caller gets error 'restricted'; a 'removed' row
-- is refused (only an admin re-admits, D4); a 'left' row is reopened. 'invite' communities admit at
-- once (approval notice suppressed), 'approve' communities make the row pending (the
-- notify_pending_membership trigger tells that community's admins). use_count is bumped and a
-- redemption row written. For the default community the answers are also copied to profiles,
-- where the installed admin build reads them.
-- ============================================================================================
create or replace function public.redeem_community_invite(
  p_code text,
  p_heard_about text default null,
  p_join_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_banned boolean;
  v_inv record;
  v_found boolean;
  v_row record;
  v_has_row boolean;
  v_status text;
  v_is_default boolean;
  v_heard text := left(nullif(btrim(coalesce(p_heard_about, '')), ''), 500);
  v_reason text := left(nullif(btrim(coalesce(p_join_reason, '')), ''), 500);
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  select p.is_banned into v_banned from public.profiles p where p.id = v_uid;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Finish creating your profile first');
  end if;
  if coalesce(v_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('community_invite:' || v_uid::text, 0));

  if public.invite_attempts_exceeded(v_uid) then
    return jsonb_build_object('success', false,
      'error', 'Too many codes tried. Try again in an hour.', 'code', 'rate_limited');
  end if;

  select * into v_inv from public.lookup_community_invite(p_code) limit 1;
  if found then
    -- serialize redemptions of one code, then read its state again
    perform 1 from public.community_invites i where i.id = v_inv.invite_id for update;
    select * into v_inv from public.lookup_community_invite(p_code) limit 1;
  end if;
  v_found := found;

  insert into public.community_invite_attempts (user_id, succeeded)
  values (v_uid, v_found and v_inv.state = 'valid');

  if not v_found or v_inv.state = 'revoked' then
    return jsonb_build_object('success', false, 'error', 'This code is not valid', 'code', 'invalid');
  end if;
  if v_inv.state = 'expired' then
    return jsonb_build_object('success', false, 'error', 'This code has expired', 'code', 'expired');
  end if;
  if v_inv.state = 'exhausted' then
    return jsonb_build_object('success', false, 'error', 'This code has been used up', 'code', 'exhausted');
  end if;

  select m.status into v_row
    from public.community_members m
   where m.community_id = v_inv.community_id and m.user_id = v_uid
   for update;
  v_has_row := found;

  if v_has_row then
    if v_row.status = 'removed' then
      return jsonb_build_object('success', false,
        'error', 'A community admin has to re-admit you', 'code', 'removed');
    elsif v_row.status = 'active' then
      return jsonb_build_object('success', false,
        'error', 'You are already a member of this community', 'code', 'already_member');
    elsif v_row.status = 'pending' then
      return jsonb_build_object('success', false,
        'error', 'Your request to join is already waiting for an admin', 'code', 'already_pending');
    end if;
  end if;

  v_status := case when v_inv.join_policy = 'invite' then 'active' else 'pending' end;

  if v_status = 'active' and (select count(*) from public.community_members m
                               where m.community_id = v_inv.community_id and m.status = 'active') >= 500 then
    return jsonb_build_object('success', false, 'error', 'This community is full', 'code', 'full');
  end if;

  if v_status = 'active' then
    perform set_config('naars.suppress_approval_notice', '1', true);
  end if;

  if v_has_row then
    update public.community_members
       set status = v_status,
           role = 'member',
           invited_by = v_inv.created_by,
           invite_id = v_inv.invite_id,
           approved_by = null,
           heard_about = v_heard,
           join_reason = v_reason,
           removal_reason = null,
           joined_at = now(),
           activated_at = case when v_status = 'active' then now() end,
           ended_at = null,
           updated_at = now()
     where community_id = v_inv.community_id and user_id = v_uid;
  else
    insert into public.community_members
      (community_id, user_id, role, status, invited_by, invite_id, heard_about, join_reason, activated_at)
    values
      (v_inv.community_id, v_uid, 'member', v_status, v_inv.created_by, v_inv.invite_id, v_heard, v_reason,
       case when v_status = 'active' then now() end);
  end if;

  perform set_config('naars.suppress_approval_notice', '', true);

  update public.community_invites set use_count = use_count + 1 where id = v_inv.invite_id;
  insert into public.community_invite_redemptions (invite_id, user_id)
  values (v_inv.invite_id, v_uid)
  on conflict (invite_id, user_id) do update set redeemed_at = now();

  insert into public.community_membership_events (community_id, user_id, actor_id, event, new_role)
  values (v_inv.community_id, v_uid, v_uid,
          case when v_status = 'active' then 'invited' else 'applied' end,
          case when v_status = 'active' then 'member' end);

  select c.is_default into v_is_default from public.communities c where c.id = v_inv.community_id;
  if v_status = 'pending' and v_is_default then
    update public.profiles
       set heard_about = coalesce(v_heard, heard_about),
           join_reason = coalesce(v_reason, join_reason)
     where id = v_uid;
  end if;

  return jsonb_build_object('success', true, 'community_id', v_inv.community_id, 'status', v_status);
end
$$;

revoke all on function public.redeem_community_invite(text, text, text) from public, anon;
grant execute on function public.redeem_community_invite(text, text, text) to authenticated;


-- ============================================================================================
-- BLOCK 19: public.request_to_join_community(uuid, text, text)
-- Self; the community must be public and live. Banned callers get 'restricted'; removed rows are
-- refused; a request within 7 days of a rejection is refused. Creates or reopens a pending row
-- (notify_pending_membership tells the admins). Answers are copied to profiles for the default
-- community only.
-- ============================================================================================
create or replace function public.request_to_join_community(
  p_community_id uuid,
  p_heard_about text default null,
  p_join_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_banned boolean;
  v_c record;
  v_row record;
  v_has_row boolean;
  v_last_reject timestamptz;
  v_heard text := left(nullif(btrim(coalesce(p_heard_about, '')), ''), 500);
  v_reason text := left(nullif(btrim(coalesce(p_join_reason, '')), ''), 500);
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  select p.is_banned into v_banned from public.profiles p where p.id = v_uid;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Finish creating your profile first');
  end if;
  if coalesce(v_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('community_join:' || v_uid::text, 0));

  select c.id, c.is_default into v_c
    from public.communities c
   where c.id = p_community_id and c.archived_at is null and c.is_public;
  if not found then
    return jsonb_build_object('success', false, 'error', 'This community is not open to requests');
  end if;

  select m.status into v_row
    from public.community_members m
   where m.community_id = p_community_id and m.user_id = v_uid
   for update;
  v_has_row := found;

  if v_has_row then
    if v_row.status = 'removed' then
      return jsonb_build_object('success', false,
        'error', 'A community admin has to re-admit you', 'code', 'removed');
    elsif v_row.status = 'active' then
      return jsonb_build_object('success', false,
        'error', 'You are already a member of this community', 'code', 'already_member');
    elsif v_row.status = 'pending' then
      return jsonb_build_object('success', false,
        'error', 'Your request to join is already waiting for an admin', 'code', 'already_pending');
    end if;
  end if;

  select max(e.created_at) into v_last_reject
    from public.community_membership_events e
   where e.community_id = p_community_id and e.user_id = v_uid and e.event = 'rejected';
  if v_last_reject is not null and v_last_reject > now() - interval '7 days' then
    return jsonb_build_object('success', false,
      'error', 'You can ask to join again after ' || to_char(v_last_reject + interval '7 days', 'FMMonth FMDD'),
      'code', 'recently_rejected', 'retry_after', v_last_reject + interval '7 days');
  end if;

  if v_has_row then
    update public.community_members
       set status = 'pending',
           role = 'member',
           invited_by = null,
           invite_id = null,
           approved_by = null,
           heard_about = v_heard,
           join_reason = v_reason,
           removal_reason = null,
           joined_at = now(),
           activated_at = null,
           ended_at = null,
           updated_at = now()
     where community_id = p_community_id and user_id = v_uid;
  else
    insert into public.community_members (community_id, user_id, role, status, heard_about, join_reason)
    values (p_community_id, v_uid, 'member', 'pending', v_heard, v_reason);
  end if;

  insert into public.community_membership_events (community_id, user_id, actor_id, event)
  values (p_community_id, v_uid, v_uid, 'applied');

  if v_c.is_default then
    update public.profiles
       set heard_about = coalesce(v_heard, heard_about),
           join_reason = coalesce(v_reason, join_reason)
     where id = v_uid;
  end if;

  return jsonb_build_object('success', true, 'community_id', p_community_id, 'status', 'pending');
end
$$;

revoke all on function public.request_to_join_community(uuid, text, text) from public, anon;
grant execute on function public.request_to_join_community(uuid, text, text) to authenticated;


-- ============================================================================================
-- BLOCK 20: public.approve_community_member(uuid, uuid)
-- Community admin. pending -> active. A banned target is refused with 'restricted' (no detail). If
-- the person already had an active membership elsewhere, this RPC sends the community-named
-- user_approved row and push (D22); otherwise the mirror flips profiles.approved and
-- notify_user_approved sends the welcome.
-- ============================================================================================
create or replace function public.approve_community_member(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_status text;
  v_banned boolean;
  v_name text;
  v_other boolean;
begin
  if v_uid is null or not public.is_community_admin(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only community admins can approve requests');
  end if;

  select m.status into v_status
    from public.community_members m
   where m.community_id = p_community_id and m.user_id = p_user_id
   for update;
  if not found or v_status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'There is no request to approve', 'code', 'not_pending');
  end if;

  select p.is_banned into v_banned from public.profiles p where p.id = p_user_id;
  if coalesce(v_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  if (select count(*) from public.community_members m
       where m.community_id = p_community_id and m.status = 'active') >= 500 then
    return jsonb_build_object('success', false, 'error', 'This community is full', 'code', 'full');
  end if;

  select exists (select 1 from public.community_members m
                   join public.communities c on c.id = m.community_id and c.archived_at is null
                  where m.user_id = p_user_id and m.status = 'active' and m.community_id <> p_community_id)
    into v_other;

  update public.community_members
     set status = 'active', activated_at = now(), approved_by = v_uid, ended_at = null, updated_at = now()
   where community_id = p_community_id and user_id = p_user_id;

  insert into public.community_membership_events (community_id, user_id, actor_id, event, new_role)
  values (p_community_id, p_user_id, v_uid, 'approved', 'member');

  if v_other then
    select c.name into v_name from public.communities c where c.id = p_community_id;
    perform public.notify_user_in_community(
      p_user_id, 'user_approved', 'You''re in: ' || v_name, 'Your request to join was approved.',
      p_community_id, true, '{}'::jsonb, v_uid);
  end if;

  return jsonb_build_object('success', true, 'community_id', p_community_id, 'user_id', p_user_id);
end
$$;

revoke all on function public.approve_community_member(uuid, uuid) from public, anon;
grant execute on function public.approve_community_member(uuid, uuid) to authenticated;


-- ============================================================================================
-- BLOCK 21: public.reject_community_member(uuid, uuid)
-- Community admin. Deletes the pending row, never the account; the mirror then routes a person
-- with nothing left to onboarding. Sends the Phase 3 user_rejected notice (spec §2.4).
-- ============================================================================================
create or replace function public.reject_community_member(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_name text;
begin
  if v_uid is null or not public.is_community_admin(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only community admins can decline requests');
  end if;

  delete from public.community_members
   where community_id = p_community_id and user_id = p_user_id and status = 'pending';
  if not found then
    return jsonb_build_object('success', false, 'error', 'There is no request to decline', 'code', 'not_pending');
  end if;

  insert into public.community_membership_events (community_id, user_id, actor_id, event)
  values (p_community_id, p_user_id, v_uid, 'rejected');

  select c.name into v_name from public.communities c where c.id = p_community_id;
  perform public.notify_user_in_community(
    p_user_id, 'user_rejected', 'Request not approved',
    'Your request to join ' || v_name || ' was not approved.', p_community_id, true, '{}'::jsonb, null);

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.reject_community_member(uuid, uuid) from public, anon;
grant execute on function public.reject_community_member(uuid, uuid) to authenticated;


-- ============================================================================================
-- BLOCK 22: public.remove_community_member(uuid, uuid, text)
-- Community admin; an admin or owner target only by an owner (or a platform admin). Unwinds the
-- member's requests in that community (unwind_member_requests, step 4), resets the role, sets
-- 'removed'. The member gets the account_restricted notice without the remover's name.
-- ============================================================================================
create or replace function public.remove_community_member(
  p_community_id uuid,
  p_user_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row record;
  v_name text;
  v_reason text := left(nullif(btrim(coalesce(p_reason, '')), ''), 500);
  v_res jsonb;
begin
  if v_uid is null or not public.is_community_admin(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only community admins can remove members');
  end if;
  if p_user_id = v_uid then
    return jsonb_build_object('success', false, 'error', 'Use Leave to leave a community');
  end if;

  select m.status, m.role into v_row
    from public.community_members m
   where m.community_id = p_community_id and m.user_id = p_user_id
   for update;
  if not found or v_row.status <> 'active' then
    return jsonb_build_object('success', false, 'error', 'This person is not an active member', 'code', 'not_active');
  end if;
  if v_row.role in ('owner', 'admin')
     and not (public.my_community_role(p_community_id) = 'owner' or public.is_platform_admin()) then
    return jsonb_build_object('success', false, 'error', 'Only an owner can remove an admin');
  end if;
  if v_row.role = 'owner' and not exists (
       select 1 from public.community_members m
        where m.community_id = p_community_id and m.status = 'active' and m.role = 'owner'
          and m.user_id <> p_user_id) then
    return jsonb_build_object('success', false,
      'error', 'Make someone else owner before removing the owner', 'code', 'last_owner');
  end if;

  -- the counts are what unwind_member_requests actually did (reopened claims, deleted unclaimed
  -- requests, cancelled claimed ones), not a separate estimate
  v_res := public.unwind_member_requests(p_community_id, p_user_id);

  update public.community_members
     set role = 'member', status = 'removed', removal_reason = v_reason, ended_at = now(), updated_at = now()
   where community_id = p_community_id and user_id = p_user_id;

  insert into public.community_membership_events (community_id, user_id, actor_id, event, old_role, new_role, reason)
  values (p_community_id, p_user_id, v_uid, 'removed', v_row.role, 'member', v_reason);

  select c.name into v_name from public.communities c where c.id = p_community_id;
  perform public.notify_user_in_community(
    p_user_id, 'account_restricted', 'Removed from ' || v_name, 'A community admin removed you.',
    p_community_id, true, '{}'::jsonb, null);

  return jsonb_build_object('success', true,
                            'reopened',  coalesce((v_res->>'reopened')::integer, 0),
                            'removed',   coalesce((v_res->>'removed')::integer, 0),
                            'cancelled', coalesce((v_res->>'cancelled')::integer, 0));
end
$$;

revoke all on function public.remove_community_member(uuid, uuid, text) from public, anon;
grant execute on function public.remove_community_member(uuid, uuid, text) to authenticated;


-- ============================================================================================
-- BLOCK 23: public.readmit_community_member(uuid, uuid)
-- Community admin; the only way back for a removed member (D4). Notices as for approval.
-- ============================================================================================
create or replace function public.readmit_community_member(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_status text;
  v_banned boolean;
  v_name text;
  v_other boolean;
begin
  if v_uid is null or not public.is_community_admin(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only community admins can re-admit members');
  end if;

  select m.status into v_status
    from public.community_members m
   where m.community_id = p_community_id and m.user_id = p_user_id
   for update;
  if not found or v_status <> 'removed' then
    return jsonb_build_object('success', false, 'error', 'This person was not removed', 'code', 'not_removed');
  end if;

  select p.is_banned into v_banned from public.profiles p where p.id = p_user_id;
  if coalesce(v_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  if (select count(*) from public.community_members m
       where m.community_id = p_community_id and m.status = 'active') >= 500 then
    return jsonb_build_object('success', false, 'error', 'This community is full', 'code', 'full');
  end if;

  select exists (select 1 from public.community_members m
                   join public.communities c on c.id = m.community_id and c.archived_at is null
                  where m.user_id = p_user_id and m.status = 'active' and m.community_id <> p_community_id)
    into v_other;

  update public.community_members
     set status = 'active', role = 'member', activated_at = now(), approved_by = v_uid,
         removal_reason = null, ended_at = null, updated_at = now()
   where community_id = p_community_id and user_id = p_user_id;

  insert into public.community_membership_events (community_id, user_id, actor_id, event, new_role)
  values (p_community_id, p_user_id, v_uid, 'readmitted', 'member');

  if v_other then
    select c.name into v_name from public.communities c where c.id = p_community_id;
    perform public.notify_user_in_community(
      p_user_id, 'user_approved', 'You''re in: ' || v_name, 'A community admin let you back in.',
      p_community_id, true, '{}'::jsonb, v_uid);
  end if;

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.readmit_community_member(uuid, uuid) from public, anon;
grant execute on function public.readmit_community_member(uuid, uuid) to authenticated;


-- ============================================================================================
-- BLOCK 24: public.set_member_role(uuid, uuid, text)
-- Owner (or platform admin) of a live community. 'owner' makes a co-owner; demoting the last owner
-- is refused (guard_last_owner would also refuse it).
-- ============================================================================================
create or replace function public.set_member_role(p_community_id uuid, p_user_id uuid, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row record;
  v_banned boolean;
begin
  if v_uid is null or not (public.is_community_admin(p_community_id)
                           and (public.my_community_role(p_community_id) = 'owner' or public.is_platform_admin())) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can change roles');
  end if;
  if p_role is null or p_role not in ('owner', 'admin', 'member') then
    return jsonb_build_object('success', false, 'error', 'Unknown role');
  end if;

  select m.status, m.role into v_row
    from public.community_members m
   where m.community_id = p_community_id and m.user_id = p_user_id
   for update;
  if not found or v_row.status <> 'active' then
    return jsonb_build_object('success', false, 'error', 'This person is not an active member', 'code', 'not_active');
  end if;
  if v_row.role = p_role then
    return jsonb_build_object('success', true);
  end if;

  select p.is_banned into v_banned from public.profiles p where p.id = p_user_id;
  if p_role <> 'member' and coalesce(v_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  if v_row.role = 'owner' and not exists (
       select 1 from public.community_members m
        where m.community_id = p_community_id and m.status = 'active' and m.role = 'owner'
          and m.user_id <> p_user_id) then
    return jsonb_build_object('success', false,
      'error', 'A community needs an owner. Make someone else owner first.', 'code', 'last_owner');
  end if;

  update public.community_members set role = p_role, updated_at = now()
   where community_id = p_community_id and user_id = p_user_id;

  insert into public.community_membership_events (community_id, user_id, actor_id, event, old_role, new_role)
  values (p_community_id, p_user_id, v_uid, 'role_changed', v_row.role, p_role);

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.set_member_role(uuid, uuid, text) from public, anon;
grant execute on function public.set_member_role(uuid, uuid, text) to authenticated;


-- ============================================================================================
-- BLOCK 25: public.transfer_community_ownership(uuid, uuid)
-- An active owner hands ownership to another active, unbanned member and becomes an admin. The new
-- owner is written first, so guard_last_owner always sees an owner.
-- ============================================================================================
create or replace function public.transfer_community_ownership(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_target record;
  v_banned boolean;
begin
  if v_uid is null or public.my_community_role(p_community_id) is distinct from 'owner' then
    return jsonb_build_object('success', false, 'error', 'Only the owner can hand over ownership');
  end if;
  if p_user_id is null or p_user_id = v_uid then
    return jsonb_build_object('success', false, 'error', 'Choose another member');
  end if;

  perform 1 from public.community_members m
   where m.community_id = p_community_id and m.user_id = v_uid
   for update;

  select m.status, m.role into v_target
    from public.community_members m
   where m.community_id = p_community_id and m.user_id = p_user_id
   for update;
  if not found or v_target.status <> 'active' then
    return jsonb_build_object('success', false, 'error', 'This person is not an active member', 'code', 'not_active');
  end if;

  select p.is_banned into v_banned from public.profiles p where p.id = p_user_id;
  if coalesce(v_banned, false) then
    return jsonb_build_object('success', false, 'error', 'restricted', 'code', 'restricted');
  end if;

  if v_target.role <> 'owner' then
    update public.community_members set role = 'owner', updated_at = now()
     where community_id = p_community_id and user_id = p_user_id;
    insert into public.community_membership_events (community_id, user_id, actor_id, event, old_role, new_role)
    values (p_community_id, p_user_id, v_uid, 'ownership_transferred', v_target.role, 'owner');
  end if;

  update public.community_members set role = 'admin', updated_at = now()
   where community_id = p_community_id and user_id = v_uid;
  insert into public.community_membership_events (community_id, user_id, actor_id, event, old_role, new_role)
  values (p_community_id, v_uid, v_uid, 'role_changed', 'owner', 'admin');

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.transfer_community_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_community_ownership(uuid, uuid) to authenticated;


-- ============================================================================================
-- BLOCK 26: public.leave_community(uuid)
-- Self. A pending applicant withdraws. An active member: the last owner is refused while other
-- members remain (A3: transfer or promote first); as the only member, leaving archives the
-- community (never the default one). Then unwind_member_requests (rule 13), role back to member,
-- status 'left'. Returns the three counts unwind_member_requests reports (what was actually done).
-- ============================================================================================
create or replace function public.leave_community(p_community_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row record;
  v_c record;
  v_archived boolean := false;
  v_res jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;

  select m.status, m.role into v_row
    from public.community_members m
   where m.community_id = p_community_id and m.user_id = v_uid
   for update;
  if not found or v_row.status not in ('active', 'pending') then
    return jsonb_build_object('success', false, 'error', 'You are not a member of this community', 'code', 'not_member');
  end if;

  select c.is_default, c.archived_at into v_c
    from public.communities c where c.id = p_community_id
   for update;

  if v_row.status = 'pending' then
    update public.community_members
       set status = 'left', ended_at = now(), updated_at = now()
     where community_id = p_community_id and user_id = v_uid;
    insert into public.community_membership_events (community_id, user_id, actor_id, event)
    values (p_community_id, v_uid, v_uid, 'left');
    return jsonb_build_object('success', true, 'reopened', 0, 'removed', 0, 'cancelled', 0, 'archived', false);
  end if;

  if v_row.role = 'owner' and v_c.archived_at is null and not exists (
       select 1 from public.community_members m
        where m.community_id = p_community_id and m.status = 'active' and m.role = 'owner'
          and m.user_id <> v_uid) then
    if exists (select 1 from public.community_members m
                where m.community_id = p_community_id and m.status = 'active' and m.user_id <> v_uid) then
      return jsonb_build_object('success', false,
        'error', 'Make another member owner before you leave', 'code', 'last_owner');
    end if;
    if v_c.is_default then
      return jsonb_build_object('success', false, 'error', 'The default community cannot be closed');
    end if;
    -- archived first, so guard_last_owner lets the owner row go
    perform public.archive_community_with_notices(p_community_id, v_uid);
    v_archived := true;
  end if;

  -- the counts are what unwind_member_requests actually did, not a separate estimate
  v_res := public.unwind_member_requests(p_community_id, v_uid);

  update public.community_members
     set role = 'member', status = 'left', ended_at = now(), updated_at = now()
   where community_id = p_community_id and user_id = v_uid;

  insert into public.community_membership_events (community_id, user_id, actor_id, event, old_role, new_role)
  values (p_community_id, v_uid, v_uid, 'left', v_row.role, 'member');

  return jsonb_build_object('success', true,
                            'reopened',  coalesce((v_res->>'reopened')::integer, 0),
                            'removed',   coalesce((v_res->>'removed')::integer, 0),
                            'cancelled', coalesce((v_res->>'cancelled')::integer, 0),
                            'archived',  v_archived);
end
$$;

revoke all on function public.leave_community(uuid) from public, anon;
grant execute on function public.leave_community(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 27: public.set_primary_community(uuid)
-- Self; must be a live active membership. The only client route to profiles.primary_community_id
-- (protect_admin_fields lets this one statement through via the transaction-local escape).
-- ============================================================================================
create or replace function public.set_primary_community(p_community_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not public.is_active_member(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'You are not a member of this community');
  end if;

  perform set_config('naars.membership_mirror', '1', true);
  update public.profiles set primary_community_id = p_community_id
   where id = v_uid and primary_community_id is distinct from p_community_id;
  perform set_config('naars.membership_mirror', '', true);

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.set_primary_community(uuid) from public, anon;
grant execute on function public.set_primary_community(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 28: public.get_my_memberships()
-- Self; works while approved = false (the waiting screen calls it). Active and pending memberships
-- in live communities, primary first. pending_count only for the community's admins. Nothing for a
-- platform-banned account (INV-M6). There is no owner_vacant column (A3).
-- ============================================================================================
create or replace function public.get_my_memberships()
returns table (
  community_id uuid,
  name text,
  description text,
  role text,
  status text,
  is_primary boolean,
  join_policy text,
  is_public boolean,
  is_default boolean,
  members_can_invite boolean,
  timezone text,
  can_invite boolean,
  member_count integer,
  pending_count integer,
  notifications_muted boolean,
  muted_until timestamptz,
  joined_at timestamptz,
  activated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.name, c.description, m.role, m.status,
         coalesce(p.primary_community_id = c.id, false),
         c.join_policy, c.is_public, c.is_default, c.members_can_invite, c.timezone,
         (m.status = 'active' and (m.role in ('owner', 'admin') or c.members_can_invite)),
         (select count(*)::integer
            from public.community_members x
            join public.profiles xp on xp.id = x.user_id and not coalesce(xp.is_banned, false)
           where x.community_id = c.id and x.status = 'active'),
         case when m.status = 'active' and m.role in ('owner', 'admin') then
           (select count(*)::integer from public.community_members x
             where x.community_id = c.id and x.status = 'pending')
         end,
         m.notifications_muted, m.muted_until, m.joined_at, m.activated_at
    from public.community_members m
    join public.communities c on c.id = m.community_id and c.archived_at is null
    join public.profiles p    on p.id = m.user_id and not coalesce(p.is_banned, false)
   where m.user_id = (select auth.uid())
     and m.status in ('active', 'pending')
   order by coalesce(p.primary_community_id = c.id, false) desc, m.activated_at nulls last, c.name, c.id;
$$;

revoke all on function public.get_my_memberships() from public, anon;
grant execute on function public.get_my_memberships() to authenticated;


-- ============================================================================================
-- BLOCK 29: public.get_community_members(uuid, text, integer, integer)
-- Members read the active directory; pending / removed / left lists only for admins of that
-- community. heard_about, join_reason, invited_by_name and removal_reason are null unless the caller
-- is an admin of it. No email, phone or ban fields for anyone (D12). For a non-admin, banned people
-- and people blocked in either direction are left out; admin lists are not block-filtered. An
-- unauthorized call returns no rows (no oracle).
-- ============================================================================================
create or replace function public.get_community_members(
  p_community_id uuid,
  p_status text default 'active',
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  id uuid,
  name text,
  avatar_url text,
  car text,
  role text,
  status text,
  joined_at timestamptz,
  activated_at timestamptz,
  heard_about text,
  join_reason text,
  invited_by_name text,
  removal_reason text
)
language sql
stable
security definer
set search_path = ''
as $$
  with k as (
    select (select auth.uid()) as uid,
           public.is_community_admin(p_community_id) as is_admin,
           public.is_active_member(p_community_id) as is_member,
           coalesce(p_status, 'active') as st
  )
  select p.id, p.name, p.avatar_url, p.car, m.role, m.status, m.joined_at, m.activated_at,
         case when k.is_admin then m.heard_about end,
         case when k.is_admin then m.join_reason end,
         case when k.is_admin then inv.name end,
         case when k.is_admin then m.removal_reason end
    from k
    join public.community_members m on m.community_id = p_community_id and m.status = k.st
    join public.profiles p on p.id = m.user_id
    left join public.profiles inv on inv.id = m.invited_by
   where k.uid is not null
     and k.st in ('active', 'pending', 'removed', 'left')
     and (k.is_admin or (k.is_member and k.st = 'active'))
     and (k.is_admin or (
           not coalesce(p.is_banned, false)
           and not exists (select 1 from public.blocked_users b
                            where (b.blocker_id = k.uid and b.blocked_id = p.id)
                               or (b.blocker_id = p.id and b.blocked_id = k.uid))))
   order by case when m.status = 'active'
                 then case m.role when 'owner' then 0 when 'admin' then 1 else 2 end
                 else 0 end,
            case when m.status = 'pending' then m.joined_at end,
            lower(p.name), p.id
   limit least(greatest(coalesce(p_limit, 100), 1), 500)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.get_community_members(uuid, text, integer, integer) from public, anon;
grant execute on function public.get_community_members(uuid, text, integer, integer) to authenticated;


-- ============================================================================================
-- BLOCK 30: public.search_community_members(text, uuid, integer)
-- Member pickers. Active, unbanned members of the caller's communities (or of one of them), the
-- caller excluded, blocked either way excluded on the server. The columns are public_profiles'
-- columns in its order; declared as a table rather than `setof public.public_profiles` so the view
-- can be replaced without touching this function.
-- ============================================================================================
create or replace function public.search_community_members(
  p_query text,
  p_community_id uuid default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  name text,
  avatar_url text,
  car text,
  approved boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name, p.avatar_url, p.car, p.approved, p.created_at, p.updated_at
    from public.profiles p
   where p.id <> (select auth.uid())
     and not coalesce(p.is_banned, false)
     and exists (select 1 from public.community_members m
                  where m.user_id = p.id and m.status = 'active'
                    and m.community_id = any ((select public.my_community_ids())::uuid[])
                    and (p_community_id is null or m.community_id = p_community_id))
     and not exists (select 1 from public.blocked_users b
                      where (b.blocker_id = (select auth.uid()) and b.blocked_id = p.id)
                         or (b.blocker_id = p.id and b.blocked_id = (select auth.uid())))
     and (coalesce(btrim(p_query), '') = ''
          or p.name ilike '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%')
   order by lower(p.name), p.id
   limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke all on function public.search_community_members(text, uuid, integer) from public, anon;
grant execute on function public.search_community_members(text, uuid, integer) to authenticated;


-- ============================================================================================
-- BLOCK 31: public.report_community(uuid, text, text, text)
-- A2: any signed-in account reports a community it can read under the communities SELECT policy
-- (public, member, admin, pending applicant) or one it holds a valid code for (the code path shares
-- the invite attempt limit). The report carries reported_community_id with community_id left null,
-- so only platform admins see it (handle_new_report). submit_report's limits apply and share its
-- lock: one pending report per reporter per community (a repeat answers success with
-- duplicate = true), 20 reports an hour.
-- ============================================================================================
create or replace function public.report_community(
  p_community_id uuid default null,
  p_code text default null,
  p_report_type text default 'other',
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_cid uuid;
  v_inv record;
  v_found boolean;
  v_id uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in to report');
  end if;
  if p_report_type is null or p_report_type not in ('spam', 'harassment', 'inappropriate_content', 'scam', 'other') then
    return jsonb_build_object('success', false, 'error', 'Unknown report type');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('submit_report:' || v_uid::text, 0));

  if nullif(btrim(coalesce(p_code, '')), '') is not null then
    if public.invite_attempts_exceeded(v_uid) then
      return jsonb_build_object('success', false,
        'error', 'Too many codes tried. Try again in an hour.', 'code', 'rate_limited');
    end if;
    select * into v_inv from public.lookup_community_invite(p_code) limit 1;
    v_found := found;
    insert into public.community_invite_attempts (user_id, succeeded)
    values (v_uid, v_found and v_inv.state = 'valid');
    if not v_found or v_inv.state <> 'valid'
       or (p_community_id is not null and p_community_id <> v_inv.community_id) then
      return jsonb_build_object('success', false, 'error', 'Community not found');
    end if;
    v_cid := v_inv.community_id;
  elsif p_community_id is not null then
    if not exists (
         select 1 from public.communities c
          where c.id = p_community_id
            and c.archived_at is null
            and (c.is_public
                 or c.id = any ((select public.my_community_ids())::uuid[])
                 or c.id = any ((select public.my_admin_community_ids())::uuid[])
                 or exists (select 1 from public.community_members m
                             where m.community_id = c.id and m.user_id = v_uid and m.status = 'pending'))) then
      return jsonb_build_object('success', false, 'error', 'Community not found');
    end if;
    v_cid := p_community_id;
  else
    return jsonb_build_object('success', false, 'error', 'Choose a community to report');
  end if;

  if exists (select 1 from public.reports r
              where r.reporter_id = v_uid and r.reported_community_id = v_cid and r.status = 'pending') then
    return jsonb_build_object('success', true, 'duplicate', true);
  end if;

  if (select count(*) from public.reports r
       where r.reporter_id = v_uid and r.created_at > now() - interval '1 hour') >= 20 then
    return jsonb_build_object('success', false, 'error', 'Too many reports, try again later', 'code', 'rate_limited');
  end if;

  insert into public.reports (reporter_id, reported_community_id, report_type, description)
  values (v_uid, v_cid, p_report_type, left(p_description, 2000))
  returning id into v_id;

  return jsonb_build_object('success', true, 'report_id', v_id);
end
$$;

revoke all on function public.report_community(uuid, text, text, text) from public, anon;
grant execute on function public.report_community(uuid, text, text, text) to authenticated;


-- ============================================================================================
-- BLOCK 32: public.get_platform_communities()
-- Platform admins only. Every community including archived ones (name, description, creator,
-- created, member / pending / owner counts, archived, open report count), plus the open owned-limit
-- requests (A1) with the requester's current limit and owned count.
-- ============================================================================================
create or replace function public.get_platform_communities()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
               where r.reported_community_id = c.id and r.status = 'pending') as open_report_count
        from public.communities c
        left join public.profiles cp on cp.id = c.created_by
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

  return jsonb_build_object('success', true, 'communities', v_communities, 'limit_requests', v_requests);
end
$$;

revoke all on function public.get_platform_communities() from public, anon;
grant execute on function public.get_platform_communities() to authenticated;
