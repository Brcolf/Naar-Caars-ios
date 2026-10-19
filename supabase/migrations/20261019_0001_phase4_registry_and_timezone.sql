-- 20261019_0001_phase4_registry_and_timezone.sql
--
-- NOT APPLIED. Phase 4 of the multi-community design (Docs/superpowers/specs/2026-10-07-multi-community-design.md
-- §4 "Phase 4"), under the owner's decisions (Docs/superpowers/specs/2026-10-17-multi-community-decisions.md,
-- amendment A5, which wins where they differ).
--
-- What it does.
--   * notifications.valid_notification_type (block 1): the CHECK gains 'membership_update', the one new notification
--     type of Phase 4 (iOS plan Task 1 adds it to the Swift enum, NotificationTypeRegistry and
--     supabase/functions/_shared/notificationTypes.ts; 34 types on every layer). One ALTER TABLE statement, so the
--     table is never without the CHECK.
--   * should_notify_user (block 2, edited in place from the live body, md5(prosrc) a68446277de8720faa48d1d0384f371a,
--     which is 20261017_0001 call 1h.1): 'membership_update' joins the user_approved / user_rejected arm (always true,
--     like the account-status types; NotificationType.membershipUpdate.canBeDisabled == false on the client).
--   * create_community (block 3, dropped and created with one more argument from the live body, md5(prosrc)
--     573a3cfacd6f824e592d502575398df8, which is 20261017_0005 block 8): p_timezone text default null. A zone that
--     pg_timezone_names knows is stored on the new community; null, blank or unknown leaves the column default
--     ('America/Los_Angeles') and never refuses the creation (the client sends TimeZone.current.identifier, which a
--     server tz database might not know). The three-argument call of the Phase 2 and Phase 3 clients still resolves.
--     Grants restated as the live ones (authenticated, service_role).
--
-- Not in this file: no producer of membership_update (20261019_0003, GATED), the announcement push (20261019_0002,
-- GATED); get_badge_counts and update_community are unchanged (the plan's "What the server needs").
--
-- Apply. Supabase MCP apply_migration, one block per call, in order. Before block 2 and block 3 compare
-- md5(prosrc) with the value above; stop on a mismatch. Block 1 drops and re-adds a CHECK in one statement and
-- block 3 drops and creates a function in one call: if the MCP declines either, run that block in the SQL editor
-- (owner).
--
-- Verification. Dry run with 20261019_0002 and 20261019_0003 and the probe blocks phase4_registry, broadcast_push,
-- membership_update_producers, broadcast_cap, community_moderation and short (supabase/probes/communities_probe.sql;
-- each block's begin / rollback turned into a savepoint and a rollback to it). Then short after each block,
-- phase4_registry after block 3. Outcomes: not yet run.
--
-- What old clients see. Nothing. No function writes a membership_update row yet; should_notify_user's new arm has
-- no caller; the installed build never calls create_community, and the Phase 2 / Phase 3 builds' three-argument
-- call resolves to the new function with p_timezone null.
--
-- Rollback, in reverse order: create_community — drop function public.create_community(text, text, text, text),
-- then the three-argument body from 20261017_0005 block 8 with its grants (only while no client sends p_timezone:
-- after the Phase 4 client ships, a rollback breaks its Create); should_notify_user from 20261017_0001 call 1h.1;
-- the CHECK without 'membership_update' (only while no row has that type).


-- ============================================================================================
-- BLOCK 1: notifications.valid_notification_type gains 'membership_update'
-- The 33 values of 20260407202111_content_hidden_notification_type.sql, plus one. Existing rows all pass (P2, P3).
-- ============================================================================================
alter table public.notifications
  drop constraint valid_notification_type,
  add constraint valid_notification_type check (
    type = any (array[
      'message', 'added_to_conversation',
      'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
      'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
      'completion_reminder',
      'qa_activity', 'qa_question', 'qa_answer',
      'review', 'review_received', 'review_reminder', 'review_request',
      'town_hall_post', 'town_hall_comment', 'town_hall_reaction',
      'content_reported', 'content_hidden',
      'announcement', 'admin_announcement', 'broadcast',
      'pending_approval', 'user_approved', 'user_rejected',
      'account_restricted',
      'membership_update',
      'other'
    ]::text[])
  );


-- ============================================================================================
-- BLOCK 2: public.should_notify_user(uuid, text)   live md5(prosrc) a68446277de8720faa48d1d0384f371a
--          (20261017_0001 call 1h.1)
-- Change: 'membership_update' in the user_approved / user_rejected arm. Everything else is the live body.
-- ============================================================================================
create or replace function public.should_notify_user(p_user_id uuid, p_notification_type text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    CASE
        WHEN p_notification_type IN ('new_ride', 'new_favor') THEN
            RETURN true;
        WHEN p_notification_type IN ('announcement', 'admin_announcement', 'broadcast') THEN
            RETURN true;
        WHEN p_notification_type IN ('user_approved', 'user_rejected', 'membership_update') THEN
            RETURN true;
        WHEN p_notification_type = 'account_restricted' THEN
            RETURN true;
        WHEN p_notification_type IN ('pending_approval', 'content_reported') THEN
            RETURN v_profile.is_admin
                OR EXISTS (SELECT 1 FROM public.community_members m
                             JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
                            WHERE m.user_id = p_user_id AND m.status = 'active' AND m.role IN ('owner', 'admin'));
        WHEN p_notification_type IN ('message', 'added_to_conversation') THEN
            RETURN v_profile.notify_messages;
        WHEN p_notification_type IN (
            'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed'
        ) THEN
            RETURN v_profile.notify_ride_updates;
        WHEN p_notification_type IN ('qa_activity', 'qa_question', 'qa_answer') THEN
            RETURN v_profile.notify_qa_activity;
        WHEN p_notification_type IN (
            'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder'
        ) THEN
            RETURN v_profile.notify_review_reminders;
        WHEN p_notification_type IN ('town_hall_post', 'town_hall_comment', 'town_hall_reaction') THEN
            RETURN v_profile.notify_town_hall;
        WHEN p_notification_type = 'content_hidden' THEN
            RETURN true;
        ELSE
            RETURN false;
    END CASE;
END;
$function$;


-- ============================================================================================
-- BLOCK 3: public.create_community(text, text, text) → (text, text, text, text)
--          live md5(prosrc) 573a3cfacd6f824e592d502575398df8 (20261017_0005 block 8)
-- Changes: p_timezone text default null (last, so every existing call, named or positional, still resolves);
-- v_tz validated against pg_timezone_names; set on the new row after the insert, so the column default stays the
-- only place that names the fallback zone. Everything else is the live body.
-- One call: the drop and the create run together; create_community is never missing between two calls.
-- ============================================================================================
drop function public.create_community(text, text, text);

create function public.create_community(
    p_name text,
    p_description text default null,
    p_join_policy text default 'approve',
    p_timezone text default null
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

  insert into public.communities (name, description, created_by, join_policy)
  values (v_name, v_desc, v_uid, v_policy)
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
$function$;

revoke all on function public.create_community(text, text, text, text) from public, anon;
grant execute on function public.create_community(text, text, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
