-- 20261017_0004_communities_account_lifecycle.sql
--
-- APPLIED 2026-10-18 by the owner in the SQL editor, as ONE transaction (the file has its own
-- begin / commit). It deletes from auth.users and its functions delete from storage.objects,
-- which the Supabase MCP declines, and it must land atomically (see "Why one transaction").
-- Verified live the same day (read-only, then the probe below rolled back): the four functions are
-- SECURITY DEFINER with search_path '', EXECUTE is held by authenticated on delete_user_account and
-- admin_reject_pending_user only (anon none; unwind_member_requests and guard_last_owner none), the
-- guard_last_owner trigger is BEFORE DELETE OR UPDATE on community_members and enabled, and
-- community_membership_events held 0 rows afterwards (nothing from the owner's run leaked).
--   md5(prosrc): unwind_member_requests f275463d8d0c5e5f9043033677d6b01a,
--   delete_user_account 135aca113be1ebf5281c03c288ee32c6,
--   admin_reject_pending_user f5366ee20a4fa51908b3e8173cb1e400,
--   guard_last_owner aa26d64576260d3be2bf7213b3770e89.
-- Probe outcome (the probe below, re-expressed as 36 checks in one rolled-back transaction through
-- the MCP, every "expect error" case caught in a sub-transaction): all 36 passed. The guard raises
-- 42501 on deleting C3's sole owner row and on demoting C1's sole owner; O1's deletion makes A1
-- owner of C1 with 2 announcement rows and 1 queued push and revokes O1's code; O2's deletion
-- archives C2 with 2 "Probe C2 was closed" rows and 2 ride_unclaimed rows, M3 loses approved and
-- M1 keeps it; O3's deletion archives C3; CO1's deletion leaves C4 live with CO2 its one owner and
-- no announcement; M2's deletion leaves CO2 alone; the event row about O1 has null user_id and
-- reason; unwind_member_requests returns {reopened 1, removed 1, cancelled 1} as postgres and
-- 42501 to a client; admin_reject_pending_user answers the four cases as documented and refuses a
-- community owner who is not a platform admin; the default community's owner deleting their
-- account leaves Seattle live with exactly one other owner (STEP A, the A3 + INV-L1 reading, which
-- the owner accepted by applying this file; recorded in the decisions file under A3).
--
-- Phase 0, step 4 of Docs/superpowers/specs/2026-10-07-multi-community-design.md (section 3.5,
-- 3.6 INV-M3 / INV-M9 / INV-R6 / INV-I1, D20), as amended by decision A3 of
-- Docs/superpowers/specs/2026-10-17-multi-community-decisions.md (no ownerless state: a
-- community whose only owner deletes their account goes to the longest-standing admin, else
-- it is archived), with one exception for the default community: "A3 + INV-L1" (STEP A below).
-- A3 does not mention the default community; the INV-L1 exception is this file's reading and
-- awaits the owner's confirmation before the file is applied (record it in the decisions file
-- once confirmed). Requires steps 1-3 (20261017_0001..0003) to be live: the community tables,
-- default_community_id(), the membership mirror, recompute_flags_on_archive and
-- derive_notification_community.
--
-- What it does:
--
--   1. unwind_member_requests(p_community_id, p_user_id) -> {reopened, removed, cancelled}
--      (new, internal, service_role only; used by leave_community and remove_community_member
--      in step 5). Scoped to one community: the user's claims on confirmed requests are
--      reopened (the existing notify_*_status_change triggers send the poster the usual
--      "no longer available" bell row and push and delete the completion reminder); the
--      user's own unclaimed requests are deleted; the user's own claimed, not completed
--      requests are deleted after the helper gets the existing "cancelled because the poster
--      left" bell row; completed requests are kept; completion reminders of the deleted
--      requests go with them; the user's live invite codes for that community are revoked.
--
--   2. delete_user_account(p_user_id) (live body, md5(prosrc) e427a88440bbf72c1af040b786d54d45,
--      identical to 20261005_0008). STEP 1-7 are kept verbatim except that every name is now
--      schema-qualified and search_path is '' (it was 'public'). Three steps run first:
--        A. For each live community where the user is the only active owner: the
--           longest-standing other active, unbanned admin becomes owner (event
--           ownership_transferred; every active member gets an announcement bell row, the new
--           owner also a push). With no such admin the community is archived (event archived;
--           every active and pending member gets "<community> was closed because its owner's
--           account was deleted"; the poster and helper of every in-flight claim there get a
--           cancellation row and its completion reminder is dropped; recompute_flags_on_archive
--           re-routes anyone for whom it was the last community). A3 + INV-L1: the default
--           community is never archived while a member remains (to be confirmed by the owner,
--           see above): with no admin left, its longest-standing active member
--           (platform admins first) becomes owner; only with nobody left at all is it archived.
--           This runs before the profile delete, so guard_last_owner sees a second owner or an
--           archive when the cascade removes the user's owner row. The community rows are
--           locked first, so a co-owner deleting at the same moment cannot leave it ownerless.
--        B. The user's live community invites are revoked (a code must not outlive its
--           creator; the legacy invite_codes delete in STEP 7 stays).
--        C. reason is nulled on the user's community_membership_events rows (free text written
--           about them; the append-only trigger permits exactly that, and the FK then nulls
--           user_id).
--      Account deletion still has no precondition: the client's warning about archived
--      communities (A3) is a courtesy, the server applies these rules from every state.
--
--   3. admin_reject_pending_user(p_user_id) (live body, md5(prosrc)
--      5d3f8ec66b57078946e446dbbf2c01ab, identical to 20261005_0025). Caller check unchanged:
--      platform admins only, NULL-safe. It is now only the installed admin build's
--      compatibility path (D20): when the target has a pending row in the DEFAULT community,
--      that row is deleted (event rejected) and, only when the target then holds no
--      community_members row of any status anywhere, the profile and the auth.users row are
--      deleted as before ({success, deleted_user_id, rows_deleted: 1}); otherwise the account is
--      kept ({success: true, rows_deleted: 0}; the mirror has already recomputed the flags).
--      Without a pending default-community row nothing changes and it returns
--      {success: false, error} with "This person is already a member", "This person applied to
--      a different community" or "This account has not applied yet", which the installed build
--      shows as "Failed to reject user: ..." (AdminService.rejectUser decodes the same keys,
--      all optional). The old "Cannot reject an already approved user" refusal is replaced by
--      this per-row rule. A community owner who is not a platform admin is refused as before.
--
--   4. guard_last_owner() + trigger guard_last_owner (BEFORE UPDATE OR DELETE on
--      community_members, SECURITY DEFINER): raises 42501 when the row is the last active owner
--      of a community that is not archived and the new state is not an active owner (INV-M3).
--      It locks the community row before counting owners. Allowed: the community is archived
--      (leave_community archives first when the last owner is the only member), or is being
--      deleted by a cascade, or another active owner exists. Created here and never earlier:
--      with the live deletion RPC the cascade from profiles would hit this guard for the
--      default community's owner and their account could not be deleted.
--
-- Why one transaction: if guard_last_owner existed without the new delete_user_account, the
-- deletion of any sole owner would fail; if the new delete_user_account existed without the
-- guard nothing breaks, but the four belong to one reviewed state and one probe.
--
-- What old clients see: nothing different for members. Account deletion succeeds as before
-- and returns nothing. A platform admin on the installed build who rejects a default-community
-- applicant sees the same result; rejecting someone who applied elsewhere, has not applied, or
-- is already a member now shows an error banner and changes nothing (spec S6).
--
-- To undo (in one transaction): drop trigger guard_last_owner on public.community_members;
-- re-apply delete_user_account from 20261005_0008 and admin_reject_pending_user from
-- 20261005_0025; drop function public.guard_last_owner(), public.unwind_member_requests(uuid, uuid)
-- once no step-5 function calls it.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. unwind_member_requests
-- ---------------------------------------------------------------------------------------------
create or replace function public.unwind_member_requests(p_community_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_record record;
    v_name text;
    v_n integer;
    v_reopened integer := 0;
    v_removed integer := 0;
    v_cancelled integer := 0;
begin
    if p_community_id is null or p_user_id is null then
        raise exception 'unwind_member_requests: a community and a user are required';
    end if;

    select coalesce(c.name, 'the community') into v_name
      from public.communities c where c.id = p_community_id;
    v_name := coalesce(v_name, 'the community');

    -- (1) Claims the user made on confirmed requests are reopened. notify_ride_status_change /
    --     notify_favor_status_change send the poster (and co-requestors) the existing unclaimed
    --     bell row and push, and delete the completion reminder.
    update public.rides set status = 'open', claimed_by = null
     where community_id = p_community_id and claimed_by = p_user_id and status = 'confirmed';
    get diagnostics v_n = row_count;
    v_reopened := v_reopened + v_n;
    update public.favors set status = 'open', claimed_by = null
     where community_id = p_community_id and claimed_by = p_user_id and status = 'confirmed';
    get diagnostics v_n = row_count;
    v_reopened := v_reopened + v_n;

    -- (3, notice first) The user's own claimed requests that are not completed: the helper is
    --     told before the request is deleted (the existing "poster left" notice).
    for v_record in
        select r.id, r.claimed_by from public.rides r
         where r.community_id = p_community_id and r.user_id = p_user_id
           and r.claimed_by is not null and r.status <> 'completed'
    loop
        perform public.create_notification(
            v_record.claimed_by, 'ride_unclaimed', 'Ride Cancelled',
            'A ride you claimed has been cancelled because the poster left ' || v_name || '.',
            v_record.id, null, null, null, null, p_user_id
        );
        v_cancelled := v_cancelled + 1;
    end loop;
    for v_record in
        select f.id, f.claimed_by from public.favors f
         where f.community_id = p_community_id and f.user_id = p_user_id
           and f.claimed_by is not null and f.status <> 'completed'
    loop
        perform public.create_notification(
            v_record.claimed_by, 'favor_unclaimed', 'Favor Cancelled',
            'A favor you claimed has been cancelled because the poster left ' || v_name || '.',
            null, v_record.id, null, null, null, p_user_id
        );
        v_cancelled := v_cancelled + 1;
    end loop;

    -- (2) The user's own unclaimed requests (open; 'pending' is unused but treated the same).
    select count(*) into v_n from public.rides
     where community_id = p_community_id and user_id = p_user_id and claimed_by is null and status <> 'completed';
    v_removed := v_removed + v_n;
    select count(*) into v_n from public.favors
     where community_id = p_community_id and user_id = p_user_id and claimed_by is null and status <> 'completed';
    v_removed := v_removed + v_n;

    -- (4) Completion reminders of every request deleted below (the FK would cascade them too).
    delete from public.completion_reminders cr
     where cr.ride_id in (select r.id from public.rides r
                           where r.community_id = p_community_id and r.user_id = p_user_id and r.status <> 'completed')
        or cr.favor_id in (select f.id from public.favors f
                            where f.community_id = p_community_id and f.user_id = p_user_id and f.status <> 'completed');

    -- (2) + (3) Delete the user's requests in this community that are not completed.
    delete from public.rides
     where community_id = p_community_id and user_id = p_user_id and status <> 'completed';
    delete from public.favors
     where community_id = p_community_id and user_id = p_user_id and status <> 'completed';

    -- (5) The user's live invite codes for this community stop working.
    update public.community_invites set revoked_at = now()
     where community_id = p_community_id and created_by = p_user_id and revoked_at is null;

    return jsonb_build_object('reopened', v_reopened, 'removed', v_removed, 'cancelled', v_cancelled);
end $function$;

revoke all on function public.unwind_member_requests(uuid, uuid) from public, anon, authenticated;
grant execute on function public.unwind_member_requests(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 2. delete_user_account
-- ---------------------------------------------------------------------------------------------
create or replace function public.delete_user_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_record record;
    v_community record;
    v_successor uuid;
    v_successor_role text;
    v_successor_name text;
    v_title text;
    v_body text;
    v_nid uuid;
begin
    if auth.uid() is null or auth.uid() != p_user_id then
        raise exception 'Not authorized to delete this account';
    end if;

    -- STEP A: Communities the user owns alone (decision A3). Locked first, so a co-owner
    -- deleting at the same moment re-reads the owner set after this transaction commits.
    for v_community in
        select c.id, c.name, c.is_default
          from public.communities c
          join public.community_members m on m.community_id = c.id
         where m.user_id = p_user_id and m.role = 'owner' and m.status = 'active'
           and c.archived_at is null
         order by c.created_at, c.id
           for update of c
    loop
        -- a co-owner remains: nothing to hand over
        continue when exists (
            select 1 from public.community_members o
              join public.profiles op on op.id = o.user_id
             where o.community_id = v_community.id and o.user_id <> p_user_id
               and o.role = 'owner' and o.status = 'active' and op.is_banned = false
        );

        v_successor := null;
        v_successor_role := null;
        select m.user_id, m.role into v_successor, v_successor_role
          from public.community_members m
          join public.profiles p on p.id = m.user_id
         where m.community_id = v_community.id and m.user_id <> p_user_id
           and m.status = 'active' and m.role = 'admin' and p.is_banned = false
         order by m.activated_at nulls last, m.joined_at, m.user_id
         limit 1;

        -- INV-L1: the default community is never archived while a member remains
        if v_successor is null and v_community.is_default then
            select m.user_id, m.role into v_successor, v_successor_role
              from public.community_members m
              join public.profiles p on p.id = m.user_id
             where m.community_id = v_community.id and m.user_id <> p_user_id
               and m.status = 'active' and p.is_banned = false
             order by p.is_admin desc, m.activated_at nulls last, m.joined_at, m.user_id
             limit 1;
        end if;

        if v_successor is not null then
            update public.community_members
               set role = 'owner', updated_at = now()
             where community_id = v_community.id and user_id = v_successor;
            insert into public.community_membership_events
                (community_id, user_id, actor_id, event, old_role, new_role, reason)
            values
                (v_community.id, v_successor, p_user_id, 'ownership_transferred', v_successor_role, 'owner',
                 'The previous owner''s account was deleted');

            select coalesce(p.name, 'A member') into v_successor_name
              from public.profiles p where p.id = v_successor;
            v_title := v_community.name || ' has a new owner';
            v_body := coalesce(v_successor_name, 'A member')
                      || ' is now the owner because the previous owner''s account was closed.';

            for v_record in
                select m.user_id from public.community_members m
                 where m.community_id = v_community.id and m.status = 'active' and m.user_id <> p_user_id
            loop
                v_nid := public.create_notification(v_record.user_id, 'announcement', v_title, v_body);
                if v_nid is not null then
                    update public.notifications set community_id = v_community.id where id = v_nid;
                    if v_record.user_id = v_successor then
                        perform public.queue_push_notification(
                            v_successor, 'announcement', v_title, v_body,
                            jsonb_build_object('community_id', v_community.id::text), null, v_nid
                        );
                    end if;
                end if;
            end loop;
        else
            -- No admin: the community is archived with the deletion.
            v_title := v_community.name || ' was closed';
            v_body := v_community.name || ' was closed because its owner''s account was deleted.';

            for v_record in
                select m.user_id from public.community_members m
                 where m.community_id = v_community.id and m.status in ('active', 'pending')
                   and m.user_id <> p_user_id
            loop
                v_nid := public.create_notification(v_record.user_id, 'announcement', v_title, v_body);
                if v_nid is not null then
                    update public.notifications set community_id = v_community.id where id = v_nid;
                end if;
            end loop;

            -- In-flight claims there are cancelled with notice, as for any archive. The user's
            -- own requests and claims are left to STEP 1 / STEP 2 so nobody is told twice.
            for v_record in
                select r.id, r.user_id, r.claimed_by from public.rides r
                 where r.community_id = v_community.id and r.status = 'confirmed' and r.claimed_by is not null
                   and r.user_id <> p_user_id and r.claimed_by <> p_user_id
            loop
                perform public.create_notification(
                    v_record.user_id, 'ride_unclaimed', 'Ride Cancelled',
                    'Your ride was cancelled because ' || v_community.name || ' was closed.',
                    v_record.id, null, null, null, null, p_user_id
                );
                perform public.create_notification(
                    v_record.claimed_by, 'ride_unclaimed', 'Ride Cancelled',
                    'A ride you claimed was cancelled because ' || v_community.name || ' was closed.',
                    v_record.id, null, null, null, null, p_user_id
                );
                delete from public.completion_reminders where ride_id = v_record.id;
            end loop;
            for v_record in
                select f.id, f.user_id, f.claimed_by from public.favors f
                 where f.community_id = v_community.id and f.status = 'confirmed' and f.claimed_by is not null
                   and f.user_id <> p_user_id and f.claimed_by <> p_user_id
            loop
                perform public.create_notification(
                    v_record.user_id, 'favor_unclaimed', 'Favor Cancelled',
                    'Your favor was cancelled because ' || v_community.name || ' was closed.',
                    null, v_record.id, null, null, null, p_user_id
                );
                perform public.create_notification(
                    v_record.claimed_by, 'favor_unclaimed', 'Favor Cancelled',
                    'A favor you claimed was cancelled because ' || v_community.name || ' was closed.',
                    null, v_record.id, null, null, null, p_user_id
                );
                delete from public.completion_reminders where favor_id = v_record.id;
            end loop;

            -- fires recompute_flags_on_archive for every active and pending member
            update public.communities
               set archived_at = now(), archived_by = p_user_id, updated_at = now()
             where id = v_community.id;
            insert into public.community_membership_events (community_id, user_id, actor_id, event, reason)
            values (v_community.id, null, p_user_id, 'archived', 'The owner''s account was deleted');
        end if;
    end loop;

    -- STEP B: The user's live community invites stop working.
    update public.community_invites set revoked_at = now()
     where created_by = p_user_id and revoked_at is null;

    -- STEP C: Free text written about the user in the membership log (the FK nulls user_id).
    update public.community_membership_events set reason = null
     where user_id = p_user_id and reason is not null;

    -- STEP 1: Claimer leaves — reopen their claimed requests
    for v_record in
        select id, user_id from public.rides where claimed_by = p_user_id and status = 'confirmed'
    loop
        perform public.create_notification(
            v_record.user_id, 'ride_unclaimed', 'Ride Reopened',
            'The neighbor who claimed your ride has left. Your ride is open for others to claim.',
            v_record.id, null, null, null, null, p_user_id
        );
    end loop;
    update public.rides set status = 'open', claimed_by = null where claimed_by = p_user_id and status = 'confirmed';

    for v_record in
        select id, user_id from public.favors where claimed_by = p_user_id and status = 'confirmed'
    loop
        perform public.create_notification(
            v_record.user_id, 'favor_unclaimed', 'Favor Reopened',
            'The neighbor who claimed your favor has left. Your favor is open for others to claim.',
            null, v_record.id, null, null, null, p_user_id
        );
    end loop;
    update public.favors set status = 'open', claimed_by = null where claimed_by = p_user_id and status = 'confirmed';

    -- STEP 2: Poster leaves — notify claimers before deleting
    for v_record in
        select id, claimed_by from public.rides where user_id = p_user_id and claimed_by is not null and status = 'confirmed'
    loop
        perform public.create_notification(
            v_record.claimed_by, 'ride_unclaimed', 'Ride Cancelled',
            'A ride you claimed has been cancelled because the poster left.',
            v_record.id, null, null, null, null, p_user_id
        );
    end loop;
    for v_record in
        select id, claimed_by from public.favors where user_id = p_user_id and claimed_by is not null and status = 'confirmed'
    loop
        perform public.create_notification(
            v_record.claimed_by, 'favor_unclaimed', 'Favor Cancelled',
            'A favor you claimed has been cancelled because the poster left.',
            null, v_record.id, null, null, null, p_user_id
        );
    end loop;

    -- STEP 3: Orphaned review notifications
    update public.notifications set read = true
    where type in ('review_request', 'review_reminder') and read = false
      and (
        ride_id in (select id from public.rides where claimed_by = p_user_id and status = 'completed')
        or favor_id in (select id from public.favors where claimed_by = p_user_id and status = 'completed')
      );
    update public.rides set claimed_by = null where claimed_by = p_user_id and status = 'completed';
    update public.favors set claimed_by = null where claimed_by = p_user_id and status = 'completed';

    -- STEP 4: Reminders and storage objects
    delete from public.completion_reminders where claimer_user_id = p_user_id;
    -- Storage rows: best effort inside a sub-block. storage.protect_delete() blocks direct
    -- deletes unless the flag below is set (transaction-local; the sub-block's rollback also
    -- restores it). A failure here is logged and skipped so it can never abort deletion.
    begin
        perform set_config('storage.allow_delete_query', 'true', true);
        delete from storage.objects o
        where (
                o.owner = p_user_id
             or o.owner_id = p_user_id::text
             or (o.bucket_id = 'avatars' and lower(o.name) = p_user_id::text || '.jpg')
             or (o.bucket_id in ('message-images','audio-messages','town-hall-images','review-images','group-images')
                 and lower(o.name) like p_user_id::text || '/%')
              )
          -- keep the avatar of a group that outlives this user (see STEP 6)
          and not (
                o.bucket_id = 'group-images'
            and exists (
                select 1 from public.conversations c
                where c.id::text = lower(split_part(o.name, '/', 1))
                  and (
                        c.created_by <> p_user_id
                     or (select count(*) from public.conversation_participants cp
                         where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null) >= 2
                      )
            )
          );
        perform set_config('storage.allow_delete_query', 'false', true);
    exception when others then
        raise warning 'delete_user_account(%): storage cleanup skipped: % [%]', p_user_id, sqlerrm, sqlstate;
    end;

    -- STEP 5: NO ACTION foreign keys that would otherwise block the profile delete
    update public.conversation_participants set added_by = null where added_by = p_user_id;
    update public.profiles set banned_by = null where banned_by = p_user_id;

    -- STEP 6: Hand group conversations the user created to the longest-standing remaining
    -- member when at least two other active members remain; the user's own participant row
    -- and messages are removed below as before.
    update public.conversations c
    set created_by = (
        select cp.user_id from public.conversation_participants cp
        where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null
        order by cp.joined_at nulls last, cp.id
        limit 1
    )
    where c.created_by = p_user_id
      and (
        select count(*) from public.conversation_participants cp
        where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null
      ) >= 2;

    -- STEP 7: Rows that only concern this user (the remaining FKs cascade from profiles;
    -- community_members, community_invite_redemptions and community_invite_attempts among them)
    delete from public.push_tokens where user_id = p_user_id;
    delete from public.notifications where user_id = p_user_id;
    delete from public.reviews where fulfiller_id = p_user_id or reviewer_id = p_user_id;
    delete from public.town_hall_posts where user_id = p_user_id;
    delete from public.invite_codes where created_by = p_user_id;
    delete from public.messages where from_id = p_user_id;
    delete from public.conversation_participants where user_id = p_user_id;
    delete from public.conversations where created_by = p_user_id;
    delete from public.rides where user_id = p_user_id;
    delete from public.favors where user_id = p_user_id;
    delete from public.request_qa where user_id = p_user_id;
    delete from public.profiles where id = p_user_id;
    delete from auth.users where id = p_user_id;
end $function$;

revoke all on function public.delete_user_account(uuid) from public, anon;
grant execute on function public.delete_user_account(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 3. admin_reject_pending_user
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_reject_pending_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_caller_id uuid;
    v_default uuid;
    v_rows_deleted integer := 0;
begin
    v_caller_id := (select auth.uid());

    -- NULL-safe admin check (unchanged from 20261005_0025): platform admins only.
    if v_caller_id is null or not exists (
        select 1 from public.profiles where id = v_caller_id and is_admin = true
    ) then
        return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
    end if;

    v_default := public.default_community_id();

    -- Lock the pending default-community row so a concurrent approve cannot interleave.
    perform 1 from public.community_members m
     where m.user_id = p_user_id and m.community_id = v_default and m.status = 'pending'
       for update;

    if not found then
        if exists (
            select 1 from public.community_members m
              join public.communities c on c.id = m.community_id and c.archived_at is null
             where m.user_id = p_user_id and m.status = 'active'
        ) then
            return jsonb_build_object('success', false, 'error', 'This person is already a member');
        elsif exists (
            select 1 from public.community_members m
              join public.communities c on c.id = m.community_id and c.archived_at is null
             where m.user_id = p_user_id and m.status = 'pending'
        ) then
            return jsonb_build_object('success', false, 'error', 'This person applied to a different community');
        end if;
        return jsonb_build_object('success', false, 'error', 'This account has not applied yet');
    end if;

    insert into public.community_membership_events (community_id, user_id, actor_id, event)
    values (v_default, p_user_id, v_caller_id, 'rejected');

    -- the mirror recomputes approved / application_complete / primary_community_id
    delete from public.community_members
     where user_id = p_user_id and community_id = v_default and status = 'pending';

    -- The account goes only when nothing else ties it to any community (D20, INV-M9).
    if not exists (select 1 from public.community_members where user_id = p_user_id) then
        delete from public.profiles where id = p_user_id and approved = false;
        get diagnostics v_rows_deleted = row_count;
        if v_rows_deleted = 1 then
            delete from auth.users where id = p_user_id;
        end if;
        return jsonb_build_object(
            'success', true,
            'deleted_user_id', p_user_id,
            'rows_deleted', v_rows_deleted
        );
    end if;

    return jsonb_build_object('success', true, 'rows_deleted', 0);
end $function$;

revoke all on function public.admin_reject_pending_user(uuid) from public, anon;
grant execute on function public.admin_reject_pending_user(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 4. guard_last_owner + trigger (INV-M3)
-- ---------------------------------------------------------------------------------------------
create or replace function public.guard_last_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
    -- only the step-down of an active owner is interesting
    if old.role <> 'owner' or old.status <> 'active' then
        if tg_op = 'DELETE' then return old; end if;
        return new;
    end if;
    if tg_op = 'UPDATE' and new.role = 'owner' and new.status = 'active'
       and new.community_id = old.community_id and new.user_id = old.user_id then
        return new;
    end if;

    -- Lock the community, then count owners, so two owners stepping down at once cannot both
    -- pass. No live row: archived, or being deleted by a cascade.
    perform 1 from public.communities c
     where c.id = old.community_id and c.archived_at is null
       for update;
    if found and not exists (
        select 1 from public.community_members m
         where m.community_id = old.community_id and m.user_id <> old.user_id
           and m.role = 'owner' and m.status = 'active'
    ) then
        raise exception 'A community needs an owner. Transfer ownership or make an admin the owner first.'
            using errcode = '42501';
    end if;

    if tg_op = 'DELETE' then return old; end if;
    return new;
end $function$;

-- Trigger functions are not callable through the API, but keep the grants tidy like the rest.
revoke all on function public.guard_last_owner() from public, anon, authenticated;

create or replace trigger guard_last_owner
    before update or delete on public.community_members
    for each row execute function public.guard_last_owner();

commit;

-- =============================================================================================
-- Rolled-back probe for the owner (SQL editor, AFTER the file above is committed). Run it as
-- one script; it ends in rollback and leaves nothing behind. Expected results are on each
-- check; any "false" or an exception other than the two marked "expect error" is a failure.
-- Throwaway ids are 00000000-0000-4000-a000-0000000000NN; no real account is touched except
-- that the platform-admin subject (the oldest unbanned is_admin profile) makes two calls.
-- =============================================================================================
--
-- begin;
-- select set_config('naars.suppress_approval_notice', '1', true);   -- no welcome rows for probe joins
--
-- -- accounts: O1 sole owner with an admin (A1) and a member (M1); O2 sole owner with members
-- -- only (M1, M3); O3 alone; CO1 + CO2 co-owners with member M2; P1 default-community applicant;
-- -- P2 applicant to C1 only; P3 never applied; M1 also gets a pending default-community row.
-- insert into auth.users (id, email)
-- select ('00000000-0000-4000-a000-0000000000' || n)::uuid, 'probe' || n || '@example.invalid'
--   from unnest(array['01','02','03','04','05','06','07','08','09','10','11','12']) n;
-- insert into public.profiles (id, name, email)
-- select id, 'Probe ' || right(id::text, 2), email from auth.users where email like 'probe%@example.invalid';
-- -- 01 O1, 02 O2, 03 O3, 04 A1, 05 M1, 06 M2, 07 M3, 08 CO1, 09 CO2, 10 P1, 11 P2, 12 P3
-- insert into public.communities (id, name, join_policy) values
--   ('00000000-0000-4000-b000-000000000001', 'Probe C1', 'approve'),
--   ('00000000-0000-4000-b000-000000000002', 'Probe C2', 'approve'),
--   ('00000000-0000-4000-b000-000000000003', 'Probe C3', 'approve'),
--   ('00000000-0000-4000-b000-000000000004', 'Probe C4', 'approve');
-- insert into public.community_members (community_id, user_id, role, status, activated_at) values
--   ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000001', 'owner',  'active', now() - interval '3 days'),
--   ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000004', 'admin',  'active', now() - interval '2 days'),
--   ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000005', 'member', 'active', now() - interval '1 day'),
--   ('00000000-0000-4000-b000-000000000002', '00000000-0000-4000-a000-000000000002', 'owner',  'active', now()),
--   ('00000000-0000-4000-b000-000000000002', '00000000-0000-4000-a000-000000000005', 'member', 'active', now()),
--   ('00000000-0000-4000-b000-000000000002', '00000000-0000-4000-a000-000000000007', 'member', 'active', now()),
--   ('00000000-0000-4000-b000-000000000003', '00000000-0000-4000-a000-000000000003', 'owner',  'active', now()),
--   ('00000000-0000-4000-b000-000000000004', '00000000-0000-4000-a000-000000000008', 'owner',  'active', now()),
--   ('00000000-0000-4000-b000-000000000004', '00000000-0000-4000-a000-000000000009', 'owner',  'active', now()),
--   ('00000000-0000-4000-b000-000000000004', '00000000-0000-4000-a000-000000000006', 'member', 'active', now());
-- insert into public.community_members (community_id, user_id, status) values
--   ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000011', 'pending'),
--   (public.default_community_id(),          '00000000-0000-4000-a000-000000000010', 'pending'),
--   (public.default_community_id(),          '00000000-0000-4000-a000-000000000005', 'pending');
-- insert into public.community_invites (community_id, code, created_by, max_uses, expires_at) values
--   ('00000000-0000-4000-b000-000000000001', 'NCPRBAAAA2', '00000000-0000-4000-a000-000000000001', 1, now() + interval '7 days');
-- -- an in-flight claim in C2 between M1 and M3 (C2 gets archived)
-- insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id) values
--   ('00000000-0000-4000-c000-000000000001', '00000000-0000-4000-a000-000000000007', current_date + 1, '10:00',
--    'probe', 'probe', 'confirmed', '00000000-0000-4000-a000-000000000005', '00000000-0000-4000-b000-000000000002');
--
-- -- free text about O1 in the membership log, to check STEP C
-- insert into public.community_membership_events (community_id, user_id, event, reason) values
--   ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000001', 'role_changed', 'probe reason about O1');
--
-- -- guard (expect error 42501 on each; run each in its own savepoint)
-- savepoint g1;
-- delete from public.community_members where community_id = '00000000-0000-4000-b000-000000000003';   -- expect error
-- rollback to savepoint g1;
-- savepoint g2;
-- update public.community_members set role = 'member', status = 'left'
--  where community_id = '00000000-0000-4000-b000-000000000001' and user_id = '00000000-0000-4000-a000-000000000001';   -- expect error
-- rollback to savepoint g2;
--
-- -- a helper: delete one probe account as itself
-- -- (repeat this block for 01, 02, 03, 08 and 06, in that order)
-- select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-a000-000000000001', 'role', 'authenticated')::text, true);
-- set local role authenticated;
-- select public.delete_user_account('00000000-0000-4000-a000-000000000001');
-- reset role;
-- select set_config('request.jwt.claims', '', true);
--
-- -- after deleting 01 (sole owner with an admin):
-- select role = 'owner' from public.community_members
--  where community_id = '00000000-0000-4000-b000-000000000001' and user_id = '00000000-0000-4000-a000-000000000004';   -- true
-- select archived_at is null from public.communities where id = '00000000-0000-4000-b000-000000000001';             -- true
-- select count(*) = 2 from public.notifications where type = 'announcement'
--    and community_id = '00000000-0000-4000-b000-000000000001'
--    and user_id in ('00000000-0000-4000-a000-000000000004', '00000000-0000-4000-a000-000000000005');                -- true
-- select count(*) = 1 from public.notification_queue
--  where recipient_user_id = '00000000-0000-4000-a000-000000000004' and notification_type = 'announcement';         -- true
-- select revoked_at is not null from public.community_invites where code = 'NCPRBAAAA2';                             -- true
-- select not exists (select 1 from public.profiles where id = '00000000-0000-4000-a000-000000000001')
--    and not exists (select 1 from auth.users where id = '00000000-0000-4000-a000-000000000001');                   -- true
--
-- -- after deleting 02 (sole owner, members only):
-- select archived_at is not null from public.communities where id = '00000000-0000-4000-b000-000000000002';         -- true
-- select count(*) = 2 from public.notifications where type = 'announcement' and title = 'Probe C2 was closed';      -- true (M1, M3)
-- select count(*) = 2 from public.notifications
--  where ride_id = '00000000-0000-4000-c000-000000000001' and type = 'ride_unclaimed';                              -- true (poster M3, helper M1)
-- select approved = false and application_complete = false and primary_community_id is null
--   from public.profiles where id = '00000000-0000-4000-a000-000000000007';                                        -- true (C2 was M3's only community)
-- select approved from public.profiles where id = '00000000-0000-4000-a000-000000000005';                           -- true (M1 is still in C1)
--
-- -- after deleting 03 (alone):
-- select archived_at is not null from public.communities where id = '00000000-0000-4000-b000-000000000003';         -- true
--
-- -- after deleting 08 (a co-owner):
-- select archived_at is null from public.communities where id = '00000000-0000-4000-b000-000000000004';             -- true
-- select count(*) = 1 from public.community_members
--  where community_id = '00000000-0000-4000-b000-000000000004' and role = 'owner' and status = 'active';            -- true (CO2)
-- select count(*) = 0 from public.notifications where community_id = '00000000-0000-4000-b000-000000000004'
--    and type = 'announcement';                                                                                      -- true
--
-- -- after deleting 06 (a member):
-- select count(*) = 1 from public.community_members where community_id = '00000000-0000-4000-b000-000000000004';    -- true (CO2 only)
--
-- -- STEP C: the event row about O1 now has a null user_id and a null reason
-- select count(*) = 1 from public.community_membership_events
--  where community_id = '00000000-0000-4000-b000-000000000001' and event = 'role_changed'
--    and user_id is null and reason is null;                                                                         -- true
--
-- -- unwind_member_requests (as postgres): M1 in C1 posts an open ride, posts a ride A1 claimed,
-- -- and has claimed a ride A1 posted
-- insert into public.rides (id, user_id, date, "time", pickup, destination, status, claimed_by, community_id) values
--   ('00000000-0000-4000-c000-000000000002', '00000000-0000-4000-a000-000000000005', current_date + 1, '10:00', 'probe', 'probe', 'open', null, '00000000-0000-4000-b000-000000000001'),
--   ('00000000-0000-4000-c000-000000000003', '00000000-0000-4000-a000-000000000005', current_date + 1, '11:00', 'probe', 'probe', 'confirmed', '00000000-0000-4000-a000-000000000004', '00000000-0000-4000-b000-000000000001'),
--   ('00000000-0000-4000-c000-000000000004', '00000000-0000-4000-a000-000000000004', current_date + 1, '12:00', 'probe', 'probe', 'confirmed', '00000000-0000-4000-a000-000000000005', '00000000-0000-4000-b000-000000000001');
-- select public.unwind_member_requests('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000005');
--                                                                       -- {"reopened": 1, "removed": 1, "cancelled": 1}
-- select status = 'open' and claimed_by is null from public.rides where id = '00000000-0000-4000-c000-000000000004'; -- true
-- select count(*) = 0 from public.rides where id in ('00000000-0000-4000-c000-000000000002','00000000-0000-4000-c000-000000000003'); -- true
-- savepoint u1;
-- set local role authenticated;
-- select public.unwind_member_requests('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000005');   -- expect error: permission denied
-- rollback to savepoint u1;
--
-- -- admin_reject_pending_user as the platform admin
-- select set_config('request.jwt.claims', (select json_build_object('sub', id, 'role', 'authenticated')::text
--   from public.profiles where is_admin and not is_banned order by created_at limit 1), true);
-- set local role authenticated;
-- select public.admin_reject_pending_user('00000000-0000-4000-a000-000000000010');   -- success true, rows_deleted 1 (default applicant: account gone)
-- select public.admin_reject_pending_user('00000000-0000-4000-a000-000000000011');   -- success false, "applied to a different community"
-- select public.admin_reject_pending_user('00000000-0000-4000-a000-000000000012');   -- success false, "has not applied yet"
-- select public.admin_reject_pending_user('00000000-0000-4000-a000-000000000005');   -- success true, rows_deleted 0 (M1: default row gone, account kept)
-- reset role;
-- select not exists (select 1 from auth.users where id = '00000000-0000-4000-a000-000000000010');                  -- true
-- select exists (select 1 from public.community_members where user_id = '00000000-0000-4000-a000-000000000011'
--                and community_id = '00000000-0000-4000-b000-000000000001' and status = 'pending');                -- true
-- select exists (select 1 from public.profiles where id = '00000000-0000-4000-a000-000000000005' and approved)
--    and not exists (select 1 from public.community_members where user_id = '00000000-0000-4000-a000-000000000005'
--                    and community_id = public.default_community_id());                                           -- true
-- -- a community owner who is not a platform admin (A1 owns C1 now) is refused
-- select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-a000-000000000004', 'role', 'authenticated')::text, true);
-- set local role authenticated;
-- select public.admin_reject_pending_user('00000000-0000-4000-a000-000000000011');   -- success false, "Not authorized - admin access required"
-- reset role;
--
-- -- the short probe of the rollout also applies here: delete the account of the default
-- -- community's owner inside this transaction and check another admin became its owner.
-- rollback;
