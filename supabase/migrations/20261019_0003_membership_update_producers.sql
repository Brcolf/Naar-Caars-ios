-- 20261019_0003_membership_update_producers.sql
--
-- NOT APPLIED. GATED (decision A5 point 2): apply only after the owner confirms from App Store Connect that no
-- pre-community build remains in use. Phase 4 of the multi-community design (spec §4 "Phase 4": "one new
-- notification type, membership_update, … to give ownership changes and second-community approvals their own tap
-- route"; it replaces D22's reuse of user_approved for a further community). Needs 20261019_0001 (the CHECK and the
-- should_notify_user arm; without them create_notification returns null or the insert fails the whole RPC).
--
-- What it does. Each producer writes one bell row with community_id and one push through notify_user_in_community
-- (unchanged, md5 fb4722eeda9389814118aa6ae7db8302); the push data carries membership_event, which the client's
-- DeepLinkParser reads (iOS plan Task 2): 'approved' → My communities, 'owner' with community_id → that community's
-- Members.
--   * approve_community_member (block 1, live md5 d46e6536ada7419c1f63b8e988f1f670, 20261017_0005): the notice to a
--     person approved into a further community (v_other) is typed membership_update with membership_event 'approved'
--     instead of user_approved. The first approval is unchanged (its notice comes from the membership-flags path).
--   * transfer_community_ownership (block 2, live md5 8fc784bfc93916789137a8328d4929d8, 20261017_0005): the new owner
--     is told (today nobody is), membership_event 'owner'. Nothing is sent when the target was already an owner.
--   * set_member_role (block 3, live md5 4e00bbdc2abcf3d993e8377324655689, 20261017_0005): a person made an owner
--     (a co-owner) is told, membership_event 'owner'. Promotion to admin and every demotion stay silent (the spec
--     names only ownership changes and further-community approvals).
--   * readmit_community_member (block 4, live md5 3045087b5df74f503cb1986da444160e, 20261017_0005): a removed member
--     let back into a community while active in another (v_other) gets membership_update with membership_event
--     'approved' instead of user_approved, so the tap opens My communities like a further-community approval. A
--     readmit with no other active membership keeps sending nothing, as today.
--   * Not changed: delete_user_account's handover notice ('announcement' with a push to the successor) is an
--     SQL-editor function (it deletes from auth.*) and keeps its type (the plan's D-S3).
--
-- Apply. After 20261019_0001. Supabase MCP apply_migration, one block per call (blocks 1-4), any order. Before each block compare
-- md5(prosrc) with the value above; stop on a mismatch. No block removes rows, drops a policy, or writes to auth.* /
-- storage.*.
--
-- Verification. Dry run (with 20261019_0001 and 20261019_0002) and probe membership_update_producers and short.
-- Outcomes, 2026-10-19 (dry run only, rolled back; the P1 values above are the live ones of that day):
-- membership_update_producers OK (all five steps) and short OK; the three calls are listed in 20261019_0001's
-- header. 20261019_0001 is live since 2026-10-19, so the CHECK and the should_notify_user arm this file needs are
-- in place. Repeat P1 and the dry run before applying (runbook step 6).
--
-- What old clients see (why it is gated). A membership_update row on the installed pre-community build fails its
-- bell list decode (no tolerant decoder in that build). Phase 1-3 builds show the row as a generic notification
-- (.other) whose tap opens the dashboard, and their push tap opens nothing in particular; the Phase 4 build routes
-- both. An installed-build second device of someone approved into a further community no longer gets the
-- user_approved "loading flash" D22 accepted (an approval or a readmit into a further community).
--
-- Rollback: each function from its 20261017_0005 body. Rows already written stay (they are valid under the CHECK).


-- ============================================================================================
-- BLOCK 1: public.approve_community_member(uuid, uuid)   live md5(prosrc) d46e6536ada7419c1f63b8e988f1f670
-- Change: the further-community notice's type and data. Everything else is the live body.
-- ============================================================================================
create or replace function public.approve_community_member(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
    -- Phase 4: its own type, so the tap opens My communities (was user_approved, D22).
    perform public.notify_user_in_community(
      p_user_id, 'membership_update', 'You''re in: ' || v_name, 'Your request to join was approved.',
      p_community_id, true, jsonb_build_object('membership_event', 'approved'), v_uid);
  end if;

  return jsonb_build_object('success', true, 'community_id', p_community_id, 'user_id', p_user_id);
end
$function$;


-- ============================================================================================
-- BLOCK 2: public.transfer_community_ownership(uuid, uuid)   live md5(prosrc) 8fc784bfc93916789137a8328d4929d8
-- Change: the new owner's notice. Everything else is the live body.
-- ============================================================================================
create or replace function public.transfer_community_ownership(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_target record;
  v_banned boolean;
  v_name text;
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

    -- Phase 4: the new owner is told; the tap opens the community's Members.
    select c.name into v_name from public.communities c where c.id = p_community_id;
    perform public.notify_user_in_community(
      p_user_id, 'membership_update', 'You''re the owner of ' || v_name,
      'Ownership of the community was handed to you.',
      p_community_id, true, jsonb_build_object('membership_event', 'owner'), v_uid);
  end if;

  update public.community_members set role = 'admin', updated_at = now()
   where community_id = p_community_id and user_id = v_uid;
  insert into public.community_membership_events (community_id, user_id, actor_id, event, old_role, new_role)
  values (p_community_id, v_uid, v_uid, 'role_changed', 'owner', 'admin');

  return jsonb_build_object('success', true);
end
$function$;


-- ============================================================================================
-- BLOCK 3: public.set_member_role(uuid, uuid, text)   live md5(prosrc) 4e00bbdc2abcf3d993e8377324655689
-- Change: a person made an owner is told. Everything else is the live body.
-- ============================================================================================
create or replace function public.set_member_role(p_community_id uuid, p_user_id uuid, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_row record;
  v_banned boolean;
  v_name text;
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

  if p_role = 'owner' then
    -- Phase 4: a new co-owner is told; the tap opens the community's Members.
    select c.name into v_name from public.communities c where c.id = p_community_id;
    perform public.notify_user_in_community(
      p_user_id, 'membership_update', 'You''re an owner of ' || v_name,
      'A community owner made you an owner.',
      p_community_id, true, jsonb_build_object('membership_event', 'owner'), v_uid);
  end if;

  return jsonb_build_object('success', true);
end
$function$;


-- ============================================================================================
-- BLOCK 4: public.readmit_community_member(uuid, uuid)   live md5(prosrc) 3045087b5df74f503cb1986da444160e
--          (20261017_0005 :1523-1580)
-- Change: the further-community notice's type and data (was user_approved with '{}'). Everything else is the live
-- body.
-- ============================================================================================
create or replace function public.readmit_community_member(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
    -- Phase 4: its own type, so the tap opens My communities (was user_approved, D22).
    perform public.notify_user_in_community(
      p_user_id, 'membership_update', 'You''re in: ' || v_name, 'A community admin let you back in.',
      p_community_id, true, jsonb_build_object('membership_event', 'approved'), v_uid);
  end if;

  return jsonb_build_object('success', true);
end
$function$;
