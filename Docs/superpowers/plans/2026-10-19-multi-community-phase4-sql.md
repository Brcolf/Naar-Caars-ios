# Multi-community Phase 4: server migrations and probes

> Companion of `2026-10-19-multi-community-phase4.md` (the iOS plan). This file holds the complete SQL of Phase 4 and the probe blocks. **Nothing here is applied.** The orchestrator copies each fenced block to the file named above it, applies File A, dry-runs Files B and C, records the outcomes in the file headers, and commits the migration files and the probe file in the same change (CLAUDE.md, migration rules). Agents executing the iOS plan never write under `supabase/` except `supabase/functions/_shared/notificationTypes.ts` (iOS plan Task 1).

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` §4 "Phase 4 — Multi-membership polish" (lines 972-976), §5 (notification and badge rows), D13, D22, under `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` amendment **A5** (wins where they differ). A5 point 2: "registry entries ship now, producers are gated", and the real `broadcast` push is gated the same way. The **gate condition** used below, word for word in each gated header: *apply only after the owner confirms from App Store Connect that no pre-community build remains in use.*

## What Phase 4 needs from the server, and where each piece is

| Spec / A5 item | Where | Applied |
|---|---|---|
| `membership_update` passes the `notifications.type` CHECK | File A block 1 | now |
| `should_notify_user` answers for `membership_update` (today it falls to `ELSE false`, so a producer's `create_notification` would return null) | File A block 2 | now |
| `get_badge_counts` lists | **no change.** The type lists in the live body (`md5 683075d80bd7126b4d515e210b561a0a`, read 2026-10-19) name only request, message, Town Hall and announcement types; every other bell row, `membership_update` included, is counted by `else 'notification:' || id::text` in `bell_groups`. It joins no request or community total, which is right for a one-off notice. | — |
| community time zone at creation (`TimeZone.current` → `create_community(p_timezone)`) | File A block 3 (`create_community` today takes `p_name, p_description, p_join_policy` only, `md5 573a3cfacd6f824e592d502575398df8`) | now |
| Settings edits the time zone | **no change.** Live `update_community(p_community_id, p_name, p_description, p_join_policy, p_members_can_invite, p_timezone)` already validates `p_timezone` against `pg_timezone_names` and lets the owner or a platform admin set it (`md5 7bf86ba02a90e5b996177ea86455a704`). | — |
| the real `broadcast` push honouring `canBeDisabled == false` and the community mute, routed to Announcements, replacing the Town Hall side door (D13) | File B blocks 1-2 | **GATED** |
| `membership_update` producers: an approval into a further community (replacing D22's `user_approved`), being let back into a further community (the same `user_approved` reuse in `readmit_community_member`), an ownership hand-over, being made an owner | File C blocks 1-4 | **GATED** |
| the edge functions | **no change and no redeploy in Phase 4** (D-S4). `send-notification` (deployed v21, source read 2026-10-19 and identical to the repo) and `send-message-push` import `_shared/notificationTypes.ts` but use only named members that already exist; the new `MEMBERSHIP_UPDATE` constant is unused by both. A `broadcast` or `membership_update` row in `notification_queue` is sent by the generic path (`sendPushToUser`: `type` plus the flattened `data`, the banned-recipient skip, the badge from `get_badge_counts`) with no type-specific code. | — |
| probe additions | `phase4_registry` (File A), `broadcast_push` (File B), `membership_update_producers` (File C) | with each file |

**How the announcement reaches people today** (live, read 2026-10-19). `send_community_broadcast` (`md5 b49920cb7b9aacbb0a5b0bc9cf85f864`, `20261018_0002` block 10) inserts one `town_hall_posts` row typed `announcement` and, for every active, unbanned, unmuted member except the sender, one bell row of the announcement type (`broadcast` by default) through `create_notification`, **with no push**. The post's insert fires the trigger `on_town_hall_post_notify` → `notify_town_hall_post()` (`md5 5c5d85a295dd292f6a92f73f2bfa2ce0`), which gives every active, unbanned, unmuted member **whose `profiles.notify_town_hall` is true** a second bell row typed `town_hall_post` ("New in Town Hall") and a push batched per 5 minutes (`batch_key 'town_hall_<community>_…'`, `process_batched_notifications` rewrites a batch's body to "N new posts in Town Hall"). That is the "Town Hall side door": a member who turned Town Hall off gets no push for an announcement, although `NotificationType.broadcast.canBeDisabled == false` (`NaarsCars/Core/Models/AppNotification.swift:111-127`) and Settings says announcements are "Always enabled" (`Features/Profile/Views/NotificationSettingsSection.swift:102-111`); everyone else gets the generic Town Hall text, possibly merged with other posts, and the tap opens the post, not Announcements.

**What File B changes for the installed pre-community build** (why it is GATED): its members stop receiving the "New in Town Hall" bell row and batched push for an announcement and receive instead one immediate push of type `broadcast` with the announcement's own title and body, also when Town Hall notifications are off. The installed build routes a `broadcast` push to its Announcements list already (`main:NaarsCars/Core/Utilities/DeepLinkParser.swift:134-137`), so nothing breaks, but what it receives changes, which A5 point 2 reserves for the gate.

**What File C changes for the installed build** (why it is GATED): the pre-community build decodes `NotificationType` with the synthesized `Decodable`, which throws on an unknown raw value, so one `membership_update` row would fail that device's whole bell list decode. Phase 1 and later builds decode it as `.other` (`AppNotification.swift:149-161`) and the Phase 4 build routes it.

## Statements the MCP declines

No block contains a `DELETE` statement, `DROP POLICY`, or a delete from `auth.*` / `storage.*`. Two are flagged:

- **File A block 1** (`alter table … drop constraint …, add constraint …`): the same single-statement form the MCP applied for `20261018_0001` block 6 on 2026-10-18. Not expected to be declined. **If it is: SQL editor (owner)**, the exact block.
- **File A block 3** (`drop function public.create_community(text, text, text); create function …`): `DROP FUNCTION` is not one of the statements the MCP is known to decline, but it has not been sent through it on this project. **If it is declined: SQL editor (owner)**, the exact block; both statements run in that one call, so `create_community` is never missing for longer than the call.

None of the probe blocks contains a `DELETE`. The orchestrator sends one block per call and never a file header.

## Preconditions (read only, orchestrator; values observed on 2026-10-19)

- **P1. Live bodies.** `select proname, pg_get_function_identity_arguments(oid), md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname in (...)` must return exactly these before the block that replaces each one; stop on any difference. Before relying on a rollback source, confirm it: the md5 of the text between that file's `$function$` delimiters equals the live value (`python3 -I` over the file; the Phase 3 method).

  | Function | Identity arguments | md5(prosrc) on 2026-10-19 | Replaced by | Rollback source |
  |---|---|---|---|---|
  | `should_notify_user` | `p_user_id uuid, p_notification_type text` | `a68446277de8720faa48d1d0384f371a` | File A block 2 | `20261017_0001_communities_core.sql:1191-1240` (call 1h.1) |
  | `create_community` | `p_name text, p_description text, p_join_policy text` | `573a3cfacd6f824e592d502575398df8` | File A block 3 (drop + create) | `20261017_0005_communities_rpcs.sql:362-` (block 8) |
  | `notify_town_hall_post` | (trigger) | `5c5d85a295dd292f6a92f73f2bfa2ce0` | File B block 1 (GATED) | `20261017_0003_communities_fanout.sql:314-` |
  | `send_community_broadcast` | `p_community_id uuid, p_title text, p_body text, p_pinned boolean, p_type text` | `b49920cb7b9aacbb0a5b0bc9cf85f864` | File B block 2 (GATED) | `20261018_0002_community_stats_and_broadcast_cap.sql:437-520` (block 10) |
  | `approve_community_member` | `p_community_id uuid, p_user_id uuid` | `d46e6536ada7419c1f63b8e988f1f670` | File C block 1 (GATED) | `20261017_0005_communities_rpcs.sql:1340-` |
  | `transfer_community_ownership` | `p_community_id uuid, p_user_id uuid` | `8fc784bfc93916789137a8328d4929d8` | File C block 2 (GATED) | `20261017_0005_communities_rpcs.sql:1653-` |
  | `set_member_role` | `p_community_id uuid, p_user_id uuid, p_role text` | `4e00bbdc2abcf3d993e8377324655689` | File C block 3 (GATED) | `20261017_0005_communities_rpcs.sql:1591-` |
  | `readmit_community_member` | `p_community_id uuid, p_user_id uuid` | `3045087b5df74f503cb1986da444160e` | File C block 4 (GATED) | `20261017_0005_communities_rpcs.sql:1523-1580` (its `as $$ … $$` body hashes to the live value, checked 2026-10-19) |

  Read and **not** replaced (recorded so a later change is noticed): `create_notification` `cf30b6278b9603f23b8feab4383cca49`, `queue_push_notification` `98f8e0726ae1670c0d7eb69090329a4c`, `notify_user_in_community` `fb4722eeda9389814118aa6ae7db8302`, `get_badge_counts` `683075d80bd7126b4d515e210b561a0a`, `update_community` `7bf86ba02a90e5b996177ea86455a704`, `send_broadcast_notifications` `e238abe6ecffbf8cf4835e5703a74ee7` (the installed admin build's wrapper; it calls `send_community_broadcast` and inherits File B), `delete_user_account` `135aca113be1ebf5281c03c288ee32c6`, `derive_notification_community` `55c06fd052dc3e6f48b259da89719dd8`, `process_batched_notifications` `52b43f1079fc1b3c899dd3a4e8c2d9ba`.

  Grants (from `proacl`): `create_community`, `send_community_broadcast`, `approve_community_member`, `transfer_community_ownership`, `set_member_role`, `readmit_community_member`: `postgres`, `authenticated`, `service_role`. `should_notify_user`, `notify_town_hall_post`, `notify_user_in_community`, `queue_push_notification`: `postgres`, `service_role` only. `CREATE OR REPLACE` keeps grants; File A block 3's `CREATE` restates them.
- **P2. The CHECK.** `select pg_get_constraintdef(oid) from pg_constraint where conname = 'valid_notification_type'` returns the 33 values of `20260407202111_content_hidden_notification_type.sql:9-` (message … account_restricted, other) and not `membership_update`.
- **P3. No row of the new type and no producer.** `select count(*) from notifications where type = 'membership_update'` = 0; `select count(*) from notification_queue where notification_type = 'membership_update'` = 0; `select proname from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%membership_update%'` returns no row before File A, and only `should_notify_user` after it (while Files B and C are not applied).
- **P4. Registry.** `scripts/validate-notification-types.sh` exits 0 on the branch after iOS plan Task 1 (34 types; it reads the CHECK from File A's migration file once that file is committed).
- **P5. One `create_community`.** `select count(*) from pg_proc where proname = 'create_community' and pronamespace = 'public'::regnamespace` = 1 (before and after File A block 3; PostgREST resolves by argument names, and two overloads that both accept the Phase 2/3 call's three names would make it ambiguous).

## Runbook (orchestrator)

1. **Preconditions** P1, P2, P3, P5.
2. **Dry run, all three files** (one `execute_sql` call), **off-peak** (the owner's quiet hours; the Phase 3 dry run ran at night): `begin;` File A blocks 1-3, File B blocks 1-2, File C blocks 1-4, the probe PARAMETERS and HELPERS (with the additions below, and without the HELPERS section's `commit;`), the blocks `phase4_registry`, `broadcast_push`, `membership_update_producers`, `broadcast_cap`, `community_moderation`, `short`, `rollback;`. Each probe block's own `begin;` / `rollback;` becomes `savepoint probe;` / `rollback to savepoint probe;` (the method recorded in `20261017_0005`'s header), so a block's rollback does not undo the migration blocks under test. Pass when every probe prints OK. Record the outcome in all three headers. **Locks.** File A block 1 is an `ALTER TABLE public.notifications` and takes an `ACCESS EXCLUSIVE` lock on `notifications` that the transaction holds until its `rollback;`, so every live read and insert of `notifications` (the bell, `create_notification` from any trigger or RPC) waits for the whole dry run, probes included. Keep the dry run to the blocks named here (no extra probe blocks), run it off-peak, and, if it takes more than a few seconds or the owner prefers, split it: (2a) File A block 1 alone with the `short` probe, `begin; … rollback;` (seconds); (2b) the rest, where `probe_require_phase4('registry')` then needs the CHECK, so 2b starts with block 1 too — in that case run 2b only off-peak. `set local lock_timeout = '5s'` as the transaction's first statement makes the ALTER give up rather than queue behind a long reader (and so make every later `notifications` query queue behind it); a timeout means: retry later, nothing was changed. **This dry run is the only time Files B and C run before the gate**; it leaves nothing behind (the `notification_queue` rows and their `pg_net` requests are in the rolled-back transaction, as the probe header says).
3. **Apply File A**, blocks 1 → 3, one `apply_migration` per block (names `20261019_0001_block_<n>`). Before each block: P1's md5 check for the function it replaces. After each block: the `short` probe. After block 3: P5, and `phase4_registry`.
4. **Record** in File A's header: APPLIED with the date, the migration-history versions, `md5(prosrc)` of the two deployed bodies (`select proname, md5(prosrc) …`), the probe outcomes. Files B and C keep **NOT APPLIED** and gain the dry-run outcome and the date of the P1 values they were written against. Commit the three migration files and the probe file together.
   **Outcome, 2026-10-19.** Steps 2-4 done. The dry run ran as three short rolled-back calls (the lock rule above); `execute_sql` and `apply_migration` both decline `drop function`, so File A block 3 was applied as a rename of the old overload to `create_community_pre_p4` with every EXECUTE grant revoked, plus the new function, in one call; File A's header records the versions, the deployed md5s and a block 4 (NOT APPLIED, owner, SQL editor: `drop function public.create_community_pre_p4(text, text, text);`). Files B and C keep NOT APPLIED with their dry-run outcomes.
5. **Nothing else is applied in Phase 4.** No edge-function deploy (D-S4).
6. **When the A5 gate opens** (owner, from App Store Connect): repeat P1 for the six gated functions (a body changed since 2026-10-19 means the gated block must be rebuilt from the new live body first), repeat the dry run of B and C with their probes, then apply File B blocks 1 → 2 and File C blocks 1 → 4 one call each with `short` after each, `broadcast_push` and `membership_update_producers` at the end, and flip their headers to APPLIED. File B and File C are independent of each other and can open separately. Then the release notes say that announcements now arrive as a push for every member who has not muted the community, and the App Store review notes say the same.

**Sequencing.** File A changes nothing any build can see: no producer writes `membership_update`, `should_notify_user` gains an arm no caller uses yet, and `create_community` keeps its three-argument call (the new argument has a default). The Phase 4 client needs File A block 3 before its Create sends `p_timezone` (iOS plan Prerequisite 2).

---

## File A — `supabase/migrations/20261019_0001_phase4_registry_and_timezone.sql`

````sql
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
````

---

## File B — `supabase/migrations/20261019_0002_broadcast_push.sql` (GATED)

````sql
-- 20261019_0002_broadcast_push.sql
--
-- NOT APPLIED. GATED (decision A5 point 2): apply only after the owner confirms from App Store Connect that no
-- pre-community build remains in use. Phase 4 of the multi-community design (spec §4 "Phase 4", D13: "a real
-- broadcast push honouring canBeDisabled = false and the community mute, routed to Announcements, replacing the
-- Town Hall side door").
--
-- What it does.
--   * send_community_broadcast (block 2, edited in place from the live body, md5(prosrc)
--     b49920cb7b9aacbb0a5b0bc9cf85f864, which is 20261018_0002 block 10): every recipient of the bell row (active,
--     unbanned, not muted, not the sender: the loop is unchanged) also gets one immediate push of the announcement's
--     type (broadcast by default) through queue_push_notification, with community_id, town_hall_post_id and (added by
--     queue_push_notification) notification_id; the title and body are cut to 100 and 180 characters for APNs.
--     should_notify_user answers true for the three announcement types whatever the person's preferences, so
--     canBeDisabled == false holds; the community mute holds because the loop already skips muted members. The
--     announcement's Town Hall post is inserted with the transaction-local setting naars.broadcast_post = '1', reset
--     right after.
--   * notify_town_hall_post (block 1, edited in place from the live body, md5(prosrc)
--     5c5d85a295dd292f6a92f73f2bfa2ce0, which is 20261017_0003): returns at once for a post typed 'announcement'
--     inserted while naars.broadcast_post = '1', so the announcement no longer also produces a "New in Town Hall"
--     bell row and batched push (the side door). Every other post, including an 'announcement'-typed row a member
--     inserts directly (20261018_0002 D-S8), is notified exactly as before.
--   * The cap, the rate of announcements and the bell rows are unchanged. send_broadcast_notifications (the
--     installed admin build's wrapper) calls send_community_broadcast and therefore pushes too.
--
-- Apply. After 20261019_0001. Supabase MCP apply_migration, one block per call, block 1 before block 2 (block 2's
-- setting is harmless without block 1, but then both pushes would go out). Before each block compare md5(prosrc)
-- with the value above; stop on a mismatch. No block removes rows, drops a policy, or writes to auth.* / storage.*.
--
-- Verification. Dry run (with 20261019_0001 and 20261019_0003) and probe broadcast_push and broadcast_cap
-- (supabase/probes/communities_probe.sql). Outcomes: not yet run.
--
-- What old clients see (why it is gated). The installed pre-community build's members stop receiving the "New in
-- Town Hall" bell row and batched push for an announcement; instead each receives one push of type broadcast with
-- the announcement's own title and body, also when Town Hall notifications are off. The installed build routes a
-- broadcast push to its Announcements list (DeepLinkParser on main), so nothing breaks, but what it receives
-- changes. Phase 1-4 builds route it to Announcements (NaarsCars/Core/Utilities/DeepLinkParser.swift:162-165).
--
-- Rollback, in reverse order: send_community_broadcast from 20261018_0002 block 10; notify_town_hall_post from
-- 20261017_0003.


-- ============================================================================================
-- BLOCK 1: public.notify_town_hall_post()   live md5(prosrc) 5c5d85a295dd292f6a92f73f2bfa2ce0 (20261017_0003)
-- Change: the early return for an announcement written by send_community_broadcast. Everything else is the live body.
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


-- ============================================================================================
-- BLOCK 2: public.send_community_broadcast(uuid, text, text, boolean, text)
--          live md5(prosrc) b49920cb7b9aacbb0a5b0bc9cf85f864 (20261018_0002 block 10)
-- Changes: naars.broadcast_post around the post insert; one queue_push_notification per bell row. Everything else
-- (the 42501 / 22023 / P0001 refusals, the advisory lock, the D14 cap, the recipients) is the live body.
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

    -- The announcement has its own push below: notify_town_hall_post skips this one post (20261019_0002 block 1).
    perform set_config('naars.broadcast_post', '1', true);
    insert into public.town_hall_posts (
        user_id, title, content, pinned, type, community_id, created_at, updated_at
    ) values (
        v_uid, p_title, p_body, coalesce(p_pinned, false), 'announcement', p_community_id, now(), now()
    )
    returning id into v_post_id;
    perform set_config('naars.broadcast_post', '', true);

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
            -- D13: one immediate push per bell row (no batch key). should_notify_user is true for the three
            -- announcement types whatever the preferences (canBeDisabled == false); the mute is the loop's.
            perform public.queue_push_notification(
                v_member.user_id, v_type, left(p_title, 100), left(p_body, 180),
                jsonb_build_object('community_id', p_community_id::text, 'town_hall_post_id', v_post_id::text),
                null, v_notification_id
            );
        end if;
    end loop;

    return v_inserted_count;
end;
$function$;
````

---

## File C — `supabase/migrations/20261019_0003_membership_update_producers.sql` (GATED)

````sql
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
-- Outcomes: not yet run.
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
````

---

## Probe additions — `supabase/probes/communities_probe.sql`

Three edits to the file.

**(1) Header, "WHEN TO RUN WHAT" (`:18-30`):** add one bullet after the Phase 3 bullet:

```text
--   * The Phase 4 blocks: phase4_registry needs 20261019_0001; broadcast_push needs 20261019_0002 and
--     membership_update_producers needs 20261019_0003. Both of those files are GATED (decision A5 point 2): until
--     they are applied, run their blocks only inside the dry run that creates them (they fail with "Phase 4 part
--     <x> is not live" otherwise). None of the three holds a DELETE; all run through the MCP.
```

and extend the RPC list (`:76-87`) with: `Phase 4: create_community(p_name, p_description, p_join_policy, p_timezone); the membership_update producers approve_community_member, readmit_community_member, transfer_community_ownership, set_member_role; send_community_broadcast's push`.

**(2) HELPERS:** insert before the `commit;` at `:363`:

```sql
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
```

**(3) Blocks:** insert before the final `select 'PROBE ALL OK' as probe;` (`:1958`).

```sql
-- =============================================================================================================
-- phase4_registry (Phase 4, 20261019_0001): the CHECK accepts membership_update and still refuses an unknown
-- type; should_notify_user answers true for it; create_community stores a known p_timezone, falls back to the
-- column default for an unknown or missing one, and the Phase 2 / 3 three-argument call still resolves.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'phase4_registry';
  u3 uuid := pg_temp.u(3);  u6 uuid := pg_temp.u(6);  u13 uuid := pg_temp.u(13);  u16 uuid := pg_temp.u(16);
  v_default text;
  v_id uuid;
  j jsonb;
begin
  perform pg_temp.probe_require_phase4(v_probe, 'registry');
  perform pg_temp.probe_world();
  v_default := (select replace(replace(column_default, '''', ''), '::text', '')
                  from information_schema.columns
                 where table_schema = 'public' and table_name = 'communities' and column_name = 'timezone');

  -- (a) the CHECK
  perform set_config('request.jwt.claims', '', true);
  insert into public.notifications (user_id, type, title) values (u3, 'membership_update', 'Probe membership update');
  perform pg_temp.probe_ok(v_probe, 'a membership_update row is accepted',
    exists (select 1 from public.notifications where user_id = u3 and type = 'membership_update'));
  begin
    insert into public.notifications (user_id, type, title) values (u3, 'probe_unknown_type', 'Probe');
    raise exception 'PROBE % FAILED: an unknown notification type was accepted', v_probe;
  exception when check_violation then
    null;
  end;

  -- (b) should_notify_user
  perform pg_temp.probe_ok(v_probe, 'should_notify_user(member, membership_update) is true',
    public.should_notify_user(u3, 'membership_update'));
  perform pg_temp.probe_ok(v_probe, 'an unknown type is still false',
    not public.should_notify_user(u3, 'probe_unknown_type'));

  -- (c) a known zone is stored
  j := pg_temp.probe_call(u6, format('public.create_community(%L, %L, %L, %L)',
                                     'Probe Zone One', 'communities probe', 'approve', 'America/New_York'));
  perform pg_temp.probe_ok(v_probe, 'create_community with a zone succeeds: ' || j::text, not pg_temp.probe_refused(j));
  v_id := (j ->> 'community_id')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the zone is stored',
    (select timezone from public.communities where id = v_id) = 'America/New_York');

  -- (d) an unknown zone falls back, by name (the PostgREST form, description omitted)
  j := pg_temp.probe_call(u13, format('public.create_community(p_name => %L, p_timezone => %L)',
                                      'Probe Zone Two', 'Not/AZone'));
  perform pg_temp.probe_ok(v_probe, 'an unknown zone is not a refusal: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'an unknown zone leaves the column default ' || coalesce(v_default, '?'),
    (select timezone from public.communities where id = (j ->> 'community_id')::uuid) = v_default);

  -- (e) the Phase 2 / 3 call: three arguments, no zone
  j := pg_temp.probe_call(u16, format('public.create_community(%L, %L, %L)', 'Probe Zone Three', 'communities probe', 'invite'));
  perform pg_temp.probe_ok(v_probe, 'the three-argument call resolves: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and keeps the column default',
    (select timezone from public.communities where id = (j ->> 'community_id')::uuid) = v_default);

  -- (f) one overload
  perform pg_temp.probe_ok(v_probe, 'exactly one create_community',
    (select count(*) from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'create_community') = 1);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE phase4_registry OK' as probe;


-- =============================================================================================================
-- broadcast_push (Phase 4, 20261019_0002, GATED: dry run only until the A5 gate): every unmuted active member but
-- the sender gets one immediate push of the announcement's type with community_id, town_hall_post_id and
-- notification_id, also with Town Hall notifications off; a muted member gets nothing; the announcement produces
-- no town_hall_post row or push; a member's own 'announcement'-typed post is still notified as a Town Hall post.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'broadcast_push';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u11 uuid := pg_temp.u(11);
  c1 uuid := pg_temp.c(1);
  v_post uuid;
  v_member_post uuid;
  j jsonb;
begin
  perform pg_temp.probe_require_phase4(v_probe, 'broadcast');
  perform pg_temp.probe_world();
  perform set_config('request.jwt.claims', '', true);
  update public.profiles set notify_town_hall = true  where id in (u3, u5);
  update public.profiles set notify_town_hall = false where id = u7;      -- Town Hall off: still gets the push
  update public.community_members set notifications_muted = true
   where community_id = c1 and user_id = u11;                             -- muted: nothing

  -- C1's active members: owner u4 (sender), admin u5, members u3 u7 u11 (muted); u9 is pending.
  j := pg_temp.probe_call(u4, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                     c1, 'Probe broadcast', 'communities probe broadcast'));
  perform pg_temp.probe_ok(v_probe, 'the owner''s announcement reaches three members: ' || j::text, j = '3'::jsonb);
  v_post := (select id from public.town_hall_posts
              where community_id = c1 and type = 'announcement' and title = 'Probe broadcast');

  perform pg_temp.probe_ok(v_probe, 'one broadcast push each for u3, u5 and u7, none for the sender or the muted member',
    (select array_agg(q.recipient_user_id order by q.recipient_user_id)
       from public.notification_queue q
      where q.notification_type = 'broadcast'
        and q.payload -> 'data' ->> 'town_hall_post_id' = v_post::text)
    = (select array_agg(x order by x) from unnest(array[u3, u5, u7]) x));
  perform pg_temp.probe_ok(v_probe, 'each push carries the community and its own bell row, and is not batched',
    not exists (select 1 from public.notification_queue q
                 where q.notification_type = 'broadcast'
                   and q.payload -> 'data' ->> 'town_hall_post_id' = v_post::text
                   and (q.batch_key is not null
                        or q.payload -> 'data' ->> 'community_id' is distinct from c1::text
                        or not exists (select 1 from public.notifications n
                                        where n.id::text = q.payload -> 'data' ->> 'notification_id'
                                          and n.user_id = q.recipient_user_id and n.type = 'broadcast'))));
  perform pg_temp.probe_ok(v_probe, 'the push title and body are the announcement''s',
    not exists (select 1 from public.notification_queue q
                 where q.notification_type = 'broadcast'
                   and q.payload -> 'data' ->> 'town_hall_post_id' = v_post::text
                   and (q.payload ->> 'title' <> 'Probe broadcast' or q.payload ->> 'body' <> 'communities probe broadcast')));
  perform pg_temp.probe_ok(v_probe, 'the announcement makes no Town Hall row or push (the side door is closed)',
    not exists (select 1 from public.notifications where type = 'town_hall_post' and town_hall_post_id = v_post)
    and not exists (select 1 from public.notification_queue
                     where notification_type = 'town_hall_post'
                       and payload -> 'data' ->> 'town_hall_post_id' = v_post::text));
  perform pg_temp.probe_ok(v_probe, 'the setting is reset after the call',
    coalesce(current_setting('naars.broadcast_post', true), '') = '');

  -- a member's own 'announcement'-typed post (20261018_0002 D-S8) is still a Town Hall post
  insert into public.town_hall_posts (user_id, title, content, type, community_id)
  values (u3, 'Probe member announcement', 'communities probe', 'announcement', c1)
  returning id into v_member_post;
  perform pg_temp.probe_ok(v_probe, 'a member''s announcement-typed post still notifies Town Hall subscribers',
    exists (select 1 from public.notifications where type = 'town_hall_post' and town_hall_post_id = v_member_post and user_id = u5));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE broadcast_push OK' as probe;


-- =============================================================================================================
-- membership_update_producers (Phase 4, 20261019_0003, GATED: dry run only until the A5 gate): approval into a
-- further community writes membership_update (approved) and no user_approved; a first approval writes no
-- membership_update; a hand-over tells the new owner (owner) and not the old one; being made a co-owner tells the
-- person; a demotion is silent; a readmit into a further community writes membership_update (approved) and no
-- user_approved.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'membership_update_producers';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);
  u9 uuid := pg_temp.u(9);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  j jsonb;
begin
  perform pg_temp.probe_require_phase4(v_probe, 'membership');
  perform pg_temp.probe_world();

  -- (a) approval into a further community: u3 is active in C1 and asks C2 (owner u12)
  perform pg_temp.probe_member(c2, u3, 'member', 'pending', 1);
  j := pg_temp.probe_call(u12, format('public.approve_community_member(%L::uuid, %L::uuid)', c2, u3));
  perform pg_temp.probe_ok(v_probe, 'approve into C2 succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'u3 gets one membership_update for C2 and no user_approved for C2',
    (select count(*) from public.notifications where user_id = u3 and type = 'membership_update' and community_id = c2) = 1
    and not exists (select 1 from public.notifications where user_id = u3 and type = 'user_approved' and community_id = c2));
  perform pg_temp.probe_ok(v_probe, 'its push says approved and names C2',
    exists (select 1 from public.notification_queue
             where recipient_user_id = u3 and notification_type = 'membership_update'
               and payload -> 'data' ->> 'membership_event' = 'approved'
               and payload -> 'data' ->> 'community_id' = c2::text));

  -- (b) a first approval: u9 has no other active membership
  j := pg_temp.probe_call(u4, format('public.approve_community_member(%L::uuid, %L::uuid)', c1, u9));
  perform pg_temp.probe_ok(v_probe, 'approve u9 into C1 succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'a first approval writes no membership_update',
    not exists (select 1 from public.notifications where user_id = u9 and type = 'membership_update'));

  -- (c) hand-over: owner u4 → admin u5
  j := pg_temp.probe_call(u4, format('public.transfer_community_ownership(%L::uuid, %L::uuid)', c1, u5));
  perform pg_temp.probe_ok(v_probe, 'the hand-over succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the new owner is told (owner), the old owner is not',
    exists (select 1 from public.notification_queue
             where recipient_user_id = u5 and notification_type = 'membership_update'
               and payload -> 'data' ->> 'membership_event' = 'owner'
               and payload -> 'data' ->> 'community_id' = c1::text)
    and (select count(*) from public.notifications where user_id = u5 and type = 'membership_update' and community_id = c1) = 1
    and not exists (select 1 from public.notifications where user_id = u4 and type = 'membership_update'));

  -- (d) co-owner: the new owner u5 makes u7 an owner, then a member again
  j := pg_temp.probe_call(u5, format('public.set_member_role(%L::uuid, %L::uuid, %L)', c1, u7, 'owner'));
  perform pg_temp.probe_ok(v_probe, 'u7 made an owner: ' || j::text, not pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u5, format('public.set_member_role(%L::uuid, %L::uuid, %L)', c1, u7, 'member'));
  perform pg_temp.probe_ok(v_probe, 'u7 made a member again: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'u7 got exactly one membership_update (the promotion, not the demotion)',
    (select count(*) from public.notifications where user_id = u7 and type = 'membership_update' and community_id = c1) = 1);

  -- (e) readmit into a further community: u7 (active in C1) was removed from C2; C2's owner u12 lets them back in
  perform pg_temp.probe_member(c2, u7, 'member', 'removed', 2);
  j := pg_temp.probe_call(u12, format('public.readmit_community_member(%L::uuid, %L::uuid)', c2, u7));
  perform pg_temp.probe_ok(v_probe, 'readmit u7 into C2 succeeds: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'u7 gets one membership_update (approved) for C2 and no user_approved for C2',
    (select count(*) from public.notifications where user_id = u7 and type = 'membership_update' and community_id = c2) = 1
    and not exists (select 1 from public.notifications where user_id = u7 and type = 'user_approved' and community_id = c2)
    and exists (select 1 from public.notification_queue
                 where recipient_user_id = u7 and notification_type = 'membership_update'
                   and payload -> 'data' ->> 'membership_event' = 'approved'
                   and payload -> 'data' ->> 'community_id' = c2::text));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE membership_update_producers OK' as probe;
```

## Deviations and choices the owner can veto

- **D-S1. The real announcement push is GATED, not shipped with the Phase 4 client** (A5 point 2 names it). Until the gate opens, the app keeps today's behaviour: the bell row plus, for Town Hall subscribers only, the batched "New in Town Hall" push; Settings' "Always enabled" stays only partly true. Applying File B earlier would change what the installed build receives (the plan's "What Phase 4 needs", File B header).
- **D-S2. The side door is closed with a transaction-local setting, not by skipping every `announcement`-typed post** in `notify_town_hall_post`. Skipping by type alone would silence the Town Hall notice of a member's directly inserted `announcement` row (20261018_0002 D-S8), and nothing would replace it, because only `send_community_broadcast` sends the push. The setting is set and reset around one insert inside a `SECURITY DEFINER` function; a client cannot set it in the same transaction as a PostgREST insert.
- **D-S3. `delete_user_account`'s handover notice keeps the type `announcement`.** It is the account-deletion function (App Store 5.1.1(v)) and an SQL-editor file (it deletes from `auth.*`); a type change there is not worth re-running the owner's step. Its push already carries `community_id` and its tap opens Announcements. Revisit with Phase 5b.
- **D-S4. No edge-function deploy in Phase 4.** The deployed `send-notification` (v21) equals the repo; the TS registry constant `MEMBERSHIP_UPDATE` is unused by both functions, so a deploy changes no behaviour and adds a production step. The repo registry is in sync on every layer (`validate-notification-types.sh`); the next functional deploy carries it. To deploy anyway: `get_edge_function` both, diff against the repo, `deploy_edge_function` with the repo files, then watch one real push in `query_logs`.
- **D-S5. `create_community` is dropped and re-created** rather than overloaded. Two overloads that both accept the Phase 2/3 call's three argument names make PostgREST's resolution ambiguous; the only callers are this branch's clients (the installed build never calls it). Rolling it back after the Phase 4 client ships would break that client's Create.
- **D-S6. An unknown time zone falls back to the column default instead of refusing** the creation (unlike `update_community`, which refuses one). A person creating a community should not fail because their device reports a zone the server's tz database does not list; the owner can fix it in Settings, where a refusal is shown.
- **D-S7. Push text is cut to 100 / 180 characters** for the announcement push (APNs payloads are limited to 4 KB, and an announcement body has no server length limit); the bell row keeps the full text.
- **D-S8. No notice on promotion to admin or on any demotion**, and none for the old owner after a hand-over (they acted). The spec names ownership changes and further-community approvals only.
- **D-S9. "All communities" for platform admins (D13) is not built:** the cap is per community and the Phase 3 announcement screen targets one community; an "All" choice would be one call per community against each community's cap. Deferred.
- **D-S10. Being let back into a further community also moves to `membership_update`** (File C block 4). The spec names "second-community approvals"; `readmit_community_member` sends the same "You're in" notice with D22's `user_approved` reuse (live body read 2026-10-19), and leaving it would keep that one path on the old route. The owner can veto by dropping block 4 together with its probe step (e), its P1 row, `readmit_community_member` in `probe_require_phase4`'s `'membership'` list (and the count back to 3) and the iOS plan's Task 13 Step 1 md5; nothing else depends on it.
