-- 20261005_0008_account_deletion_fk_fixes.sql
--
-- APPLIED. Verified live on 2026-10-06: the deployed body is byte-identical to this file
-- (md5 of prosrc), and a rolled-back probe deleted a throwaway account end to end: no error,
-- its storage object removed, profile and auth rows gone, a bystander's
-- conversation_participants.added_by set to null, the bystander untouched.
--
-- Before this, account deletion failed in production for every user (see 1).
-- ProfileService.deleteAccount still revokes the Apple token BEFORE calling this RPC; with
-- the RPC working that order no longer strands anyone, but it is still the wrong way round.
--
-- Account deletion hardening (App Store requirement: deletion must always succeed).
--
-- 1. storage.objects has a platform trigger (storage.protect_delete, BEFORE DELETE FOR EACH
--    STATEMENT) that raises 42501 "Direct deletion from storage tables is not allowed" unless
--    storage.allow_delete_query = 'true'. A statement trigger fires even when zero rows match,
--    so STEP 4 of the deployed function has always raised and the whole RPC rolled back
--    (pg_stat shows zero deletes on storage.objects ever). Verified on 2026-10-05:
--    `delete from storage.objects where false` raises 42501 as postgres. The function now sets
--    the flag (transaction-local) around its own delete, and runs the storage step in a
--    sub-block whose failure is logged and skipped: storage cleanup must never abort account
--    deletion again. Trade-off: if that step fails, the user's files stay until cleaned up by
--    hand (look for the warning in the Postgres log).
--    Object matching: every object row has owner / owner_id set (checked for all six buckets),
--    so ownership is the primary match. Object names use UPPERCASE uuids (Swift uuidString),
--    so the old name predicates (`name = p_user_id::text || '.jpg'`) never matched anything;
--    they now compare lower(name). A group avatar the user uploaded is kept when the group
--    survives (not created by the user, or handed over in STEP 6), otherwise the surviving
--    group would point at a missing image.
--    Deleting object rows makes the URLs unservable immediately; the stored bytes become
--    orphans. Follow-up: have the client call Storage remove() for its own objects before this
--    RPC (owner DELETE policies exist for avatars, message-images, audio-messages,
--    review-images and group-images, not for town-hall-images).
--
-- 2. Two foreign keys to profiles are NO ACTION and were never cleared, so the final
--    `delete from profiles` raised a foreign_key_violation for any user who had added someone
--    to a group they did not create (conversation_participants.added_by) or, as an admin, had
--    banned someone (profiles.banned_by). Reviewed against pg_constraint on 2026-10-05; every
--    other FK to profiles is ON DELETE CASCADE or SET NULL.
--
-- 3. Group conversations the user created are handed to the longest-standing remaining
--    member instead of cascading away (conversations.created_by is CASCADE NOT NULL). Only
--    groups with at least two other active members are kept; direct messages keep the previous
--    behaviour. The user's own messages still cascade with the profile (messages.from_id is
--    CASCADE NOT NULL and Swift's Message.fromId is non-optional).
--
-- 4. A third blocker was fixed separately and IS applied (20261005_0024): the append-only
--    trigger on content_moderation_events rejected the ON DELETE SET NULL updates from
--    reports / profiles, so deletion failed for any admin who had moderated and any user whose
--    report or reported content had been actioned.
--
-- Everything else is the previously deployed function body.
--
-- Still worth doing with real throwaway accounts on a device: a user who uploaded a message
-- image, one whose report an admin dismissed, and an admin who moderated something.

create or replace function public.delete_user_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_record record;
begin
    if auth.uid() is null or auth.uid() != p_user_id then
        raise exception 'Not authorized to delete this account';
    end if;

    -- STEP 1: Claimer leaves — reopen their claimed requests
    for v_record in
        select id, user_id from rides where claimed_by = p_user_id and status = 'confirmed'
    loop
        perform create_notification(
            v_record.user_id, 'ride_unclaimed', 'Ride Reopened',
            'The neighbor who claimed your ride has left. Your ride is open for others to claim.',
            v_record.id, null, null, null, null, p_user_id
        );
    end loop;
    update rides set status = 'open', claimed_by = null where claimed_by = p_user_id and status = 'confirmed';

    for v_record in
        select id, user_id from favors where claimed_by = p_user_id and status = 'confirmed'
    loop
        perform create_notification(
            v_record.user_id, 'favor_unclaimed', 'Favor Reopened',
            'The neighbor who claimed your favor has left. Your favor is open for others to claim.',
            null, v_record.id, null, null, null, p_user_id
        );
    end loop;
    update favors set status = 'open', claimed_by = null where claimed_by = p_user_id and status = 'confirmed';

    -- STEP 2: Poster leaves — notify claimers before deleting
    for v_record in
        select id, claimed_by from rides where user_id = p_user_id and claimed_by is not null and status = 'confirmed'
    loop
        perform create_notification(
            v_record.claimed_by, 'ride_unclaimed', 'Ride Cancelled',
            'A ride you claimed has been cancelled because the poster left.',
            v_record.id, null, null, null, null, p_user_id
        );
    end loop;
    for v_record in
        select id, claimed_by from favors where user_id = p_user_id and claimed_by is not null and status = 'confirmed'
    loop
        perform create_notification(
            v_record.claimed_by, 'favor_unclaimed', 'Favor Cancelled',
            'A favor you claimed has been cancelled because the poster left.',
            null, v_record.id, null, null, null, p_user_id
        );
    end loop;

    -- STEP 3: Orphaned review notifications
    update notifications set read = true
    where type in ('review_request', 'review_reminder') and read = false
      and (
        ride_id in (select id from rides where claimed_by = p_user_id and status = 'completed')
        or favor_id in (select id from favors where claimed_by = p_user_id and status = 'completed')
      );
    update rides set claimed_by = null where claimed_by = p_user_id and status = 'completed';
    update favors set claimed_by = null where claimed_by = p_user_id and status = 'completed';

    -- STEP 4: Reminders and storage objects
    delete from completion_reminders where claimer_user_id = p_user_id;
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
                select 1 from conversations c
                where c.id::text = lower(split_part(o.name, '/', 1))
                  and (
                        c.created_by <> p_user_id
                     or (select count(*) from conversation_participants cp
                         where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null) >= 2
                      )
            )
          );
        perform set_config('storage.allow_delete_query', 'false', true);
    exception when others then
        raise warning 'delete_user_account(%): storage cleanup skipped: % [%]', p_user_id, sqlerrm, sqlstate;
    end;

    -- STEP 5: NO ACTION foreign keys that would otherwise block the profile delete
    update conversation_participants set added_by = null where added_by = p_user_id;
    update profiles set banned_by = null where banned_by = p_user_id;

    -- STEP 6: Hand group conversations the user created to the longest-standing remaining
    -- member when at least two other active members remain; the user's own participant row
    -- and messages are removed below as before.
    update conversations c
    set created_by = (
        select cp.user_id from conversation_participants cp
        where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null
        order by cp.joined_at nulls last, cp.id
        limit 1
    )
    where c.created_by = p_user_id
      and (
        select count(*) from conversation_participants cp
        where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null
      ) >= 2;

    -- STEP 7: Rows that only concern this user (the remaining FKs cascade from profiles)
    delete from push_tokens where user_id = p_user_id;
    delete from notifications where user_id = p_user_id;
    delete from reviews where fulfiller_id = p_user_id or reviewer_id = p_user_id;
    delete from town_hall_posts where user_id = p_user_id;
    delete from invite_codes where created_by = p_user_id;
    delete from messages where from_id = p_user_id;
    delete from conversation_participants where user_id = p_user_id;
    delete from conversations where created_by = p_user_id;
    delete from rides where user_id = p_user_id;
    delete from favors where user_id = p_user_id;
    delete from request_qa where user_id = p_user_id;
    delete from profiles where id = p_user_id;
    delete from auth.users where id = p_user_id;
end $function$;
