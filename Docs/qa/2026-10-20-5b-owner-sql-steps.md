# Phase 5b: the owner's SQL-editor steps (2026-10-20)

## Outcome

The owner ran all four steps on 2026-10-20: File B block 5, the File C dry run, File C, and File E's nine `drop policy` lines. The orchestrator then verified the result through the MCP.

- **Check.** `20261019_phase5b_not_applied_check.sql`, sent verbatim, reads **false in every column** (`all_unchanged` false), which is the "After Step 4" column below. Phase 5b is fully applied: `20261019_0060`, `0061`, `0062` and `0063` all read APPLIED in their headers.
- **Account deletion.** `delete_user_account` is `bd886e739d25dbe7497ff6b21c5aa248`, the value File C requires. Its body is `20261017_0004`'s body with the one `invite_codes` line removed, and its grants are kept.
- **No leftovers.** No public function body contains the string `invite_codes`. (A plain `ilike '%invite_codes%'` matches `unwind_member_requests` only because `_` is a LIKE wildcard and its text contains the words "invite codes".) No `legacy_*` or invite-code function remains, and both bridge triggers are gone.
- **Storage.** The five buckets are private and avatars public. The only SELECT policies on `storage.objects` are "Avatar public read" and the five new ones.
- **Probes**, each rolled back, all through the MCP:
  - `account_deletion` OK. It ran first, because it is the App Store 5.1.1(v) check.
  - `legacy_retired` OK.
  - `legacy_bridges` SKIPPED (the bridges are gone).
  - `privileged_columns` OK.
  - `short` OK.
  - `invite_codes_dropped` OK.
  - `broadcast_cap` OK (its 42501 branch).
  - `geocoding_revoked` OK.
  - `geocoding_lookup` OK.
  - `storage_private` OK. The MCP accepted its inserts into `storage.objects`, so it did not need the SQL editor.
- **Still the owner's:**
  1. The full probe file in the SQL editor ("After all four steps", item 1). Its `posts_delete_policy` block holds DELETE statements the MCP declines, and the rest of the full matrix (`noop_default`, `isolation`, `community_moderation` and the others) was not run in this pass. The last row must be `PROBE ALL OK`.
  2. iOS plan Task 12 Step 4: the two-simulator check that photos and voice notes load, and that the public route answers 400.
  3. The release notes, App Store review notes and privacy-policy items under "Not SQL, but due now".

The sections below are the instructions as written before the owner's run. They are kept as the record.

The owner confirmed from App Store Connect on 2026-10-20 that no pre-community build remains in use (the A5 gate) and that every build in use contains the Phase 5a client (D-S9). Everything the Supabase MCP accepts has been applied from the orchestrator session. What is left are statements the MCP declines (`DROP TRIGGER`, `DROP FUNCTION`, `DROP TABLE`, `DROP POLICY`, and the `delete_user_account` body, which deletes from `auth.*` and `storage.*`). They run in the Supabase dashboard's SQL editor, in the order below.

## Where things stand

| File | State | What is left for you |
|---|---|---|
| `20261019_0002` Phase 4 File B (announcement push) | APPLIED | nothing in SQL (release notes, below) |
| `20261019_0003` Phase 4 File C (`membership_update` producers) | APPLIED | nothing |
| `20261019_0060` 5b File B (legacy bridges) | PARTIALLY APPLIED: blocks 1-4, 6, 7 | **Step 1**: block 5 |
| `20261019_0061` 5b File C (drop `invite_codes`) | NOT APPLIED | **Steps 2 and 3**: dry run, then the file |
| `20261019_0062` 5b File D (`geocoding_cache` direct access) | APPLIED | nothing |
| `20261019_0063` 5b File E (private buckets) | PARTIALLY APPLIED: blocks 1, 3, and 4 without its drops | **Step 4**: the nine `drop policy` statements |

What the partial states mean for people using the app now:

- **File B without block 5.** The two legacy bridge triggers are still on `profiles`, but they can no longer act: block 4 refuses (42501) any write of `approved` or `application_complete` that carries a user's session, before a bridge could run. The installed pre-community build is gone, and no community build makes those writes. This is the intermediate state the runbook planned for ("block 4 before block 5").
- **File E without the drops.** The five buckets (`message-images`, `group-images`, `town-hall-images`, `review-images`, `audio-messages`) are private, so their public URLs answer 400. The Phase 5a client signs its URLs and keeps working. The nine old read policies still exist. Permissive policies combine with OR, so anyone with the app's public key can still read every object in those buckets through the storage API. That is no worse than before today, but **the privacy goal of File E is reached only when Step 4 runs.**

## Rules for every step

1. Open a **new SQL-editor tab** for each script, and paste **only** that script. Never paste the probe file or any other migration file into the same tab.
2. Run the steps **in order**: 1, then 2, then 3, then 4. Step 3 depends on Step 2's dry run passing.
3. After each step, run the **check** (below) in a new tab and compare every column with the table for that step.
4. **Stop and tell the orchestrator** if any script ends in `ERROR`, or if any column of the check differs from the table. Do not run the next step. Each step's script is one transaction: an error means nothing from that step was kept.
5. After each step, ask the orchestrator to run that step's probes through the MCP. They contain nothing the MCP declines, except `storage_private` (see Step 4).

## The check (paste after every step)

This is `supabase/dryruns/20261019_phase5b_not_applied_check.sql` (file md5 `f616595d63d377b2aa1429ee76f62f6a`). It is read only. Paste the query below, or the whole file; the file's comment lines are harmless.

```sql
with c as (
  select
    (select count(*) = 6 and bool_and(b.public) from storage.buckets b
      where b.id in ('message-images', 'group-images', 'town-hall-images', 'review-images', 'audio-messages', 'avatars'))
      as buckets_all_public,
    to_regclass('public.invite_codes') is not null as invite_codes_exists,
    exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'validate_invite_code')
      as validate_invite_code_exists,
    coalesce((select md5(prosrc) = '135aca113be1ebf5281c03c288ee32c6' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.delete_user_account(uuid)')), false) as delete_user_account_unchanged,
    coalesce((select md5(prosrc) = '6241f67fc4e8618ac782b99a7b6d9295' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.fill_request_community()')), false) as fill_request_community_unchanged,
    coalesce((select md5(prosrc) = 'f18e6af6f7ca7a53acd193db115b1f27' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.redeem_community_invite(text, text, text)')), false) as redeem_community_invite_unchanged,
    coalesce((select md5(prosrc) = 'da89c2337d8102d4c284440c534c2b2a' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.request_to_join_community(uuid, text, text)')), false) as request_to_join_community_unchanged,
    coalesce((select md5(prosrc) = '48424e05ea801252b83ed8c893db5f4f' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.protect_admin_fields()')), false) as protect_admin_fields_unchanged,
    (select count(*) = 2 from pg_catalog.pg_trigger where not tgisinternal
      and tgname in ('legacy_application_to_membership', 'a_sync_legacy_approval_to_membership')) as bridges_present,
    coalesce(has_function_privilege('authenticated', to_regprocedure('public.admin_reject_pending_user(uuid)'), 'execute'), false)
      as admin_reject_pending_user_open,
    coalesce(has_function_privilege('authenticated', to_regprocedure('public.send_broadcast_notifications(text, text, text, boolean)'), 'execute'), false)
      as send_broadcast_notifications_open,
    has_table_privilege('authenticated', 'public.geocoding_cache', 'select') as geocoding_cache_readable,
    (select count(*) = 7 from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('Allow public read access on message-images', 'Message image read',
                         'Allow public read access on group-images', 'Anyone can view group images',
                         'Allow public read access on town-hall-images', 'Town hall public read',
                         'Allow public access to review images')) as old_storage_read_policies_present,
    not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('message_images_read_participants', 'group_images_read_participants',
                         'town_hall_images_read_visible', 'review_images_read_visible',
                         'audio_messages_read_participants')) as new_storage_read_policies_absent
)
select c.*,
       (buckets_all_public and invite_codes_exists and validate_invite_code_exists and delete_user_account_unchanged
        and fill_request_community_unchanged and redeem_community_invite_unchanged
        and request_to_join_community_unchanged and protect_admin_fields_unchanged and bridges_present
        and admin_reject_pending_user_open and send_broadcast_notifications_open and geocoding_cache_readable
        and old_storage_read_policies_present and new_storage_read_policies_absent) as all_unchanged
  from c;
```

What it must print (`t` = true, `f` = false). The column names say "unchanged", "present" or "open", so **false means applied**.

| Column | Now (2026-10-20, before Step 1) | After Step 1 | After Step 2 | After Step 3 | After Step 4 |
|---|---|---|---|---|---|
| `buckets_all_public` | f | f | f | f | f |
| `invite_codes_exists` | t | t | t | **f** | f |
| `validate_invite_code_exists` | t | t | t | **f** | f |
| `delete_user_account_unchanged` | t | t | t | **f** | f |
| `fill_request_community_unchanged` | f | f | f | f | f |
| `redeem_community_invite_unchanged` | f | f | f | f | f |
| `request_to_join_community_unchanged` | f | f | f | f | f |
| `protect_admin_fields_unchanged` | f | f | f | f | f |
| `bridges_present` | t | **f** | f | f | f |
| `admin_reject_pending_user_open` | f | f | f | f | f |
| `send_broadcast_notifications_open` | f | f | f | f | f |
| `geocoding_cache_readable` | f | f | f | f | f |
| `old_storage_read_policies_present` | t | t | t | t | **f** |
| `new_storage_read_policies_absent` | f | f | f | f | f |
| `all_unchanged` | f | f | f | f | f |

After Step 2 (a dry run) the check must read exactly as after Step 1. If it does not, the dry run kept something. Stop, and tell the orchestrator at once (the Phase 5 SQL plan's "If the check is not all true" section has the rollback).

## Step 1: File B block 5 (the two legacy bridges)

Paste exactly this, alone in a new tab:

```sql
drop trigger if exists legacy_application_to_membership on public.profiles;
drop trigger if exists a_sync_legacy_approval_to_membership on public.profiles;
drop function if exists public.legacy_application_to_membership();
drop function if exists public.sync_legacy_approval_to_membership();
```

- **Must print:** "Success. No rows returned" (no error).
- **Then:** run the check; `bridges_present` is now false, and everything else is as in the "Now" column.
- **Then (orchestrator, MCP):** `legacy_retired` must print OK. `legacy_bridges` must print SKIPPED. `privileged_columns`, `account_deletion` and `short` must print OK. Then File B's header becomes APPLIED.
- **Stop on:** any error, or `bridges_present` still true.

## Step 2: File C dry run (nothing is kept)

Already done, nothing to redo: the rollback capture C0 (`supabase/migrations/20261019_0061a_invite_codes_rollback_capture.sql`) and the CSV export of the 62 rows, kept off the repository, both from 2026-10-19. Read just now through the MCP: the table still has 62 rows (54 with no `used_by`), and the four invite-code functions and `delete_user_account` still have the P1 md5 values. So the capture and the CSV are current.

Paste the **whole file** `supabase/dryruns/20261019_0061_drop_invite_codes.dryrun.sql`, alone in a new tab. Paste nothing else: not the migration file, not the probe file. The file is 596 lines, md5 `275f6321aea91bec804c9a4d9d8d6fe4`. It has passed the plan's structural check: no `commit;`, one `begin;`, one `rollback;`, three savepoint pairs, and the helpers before `begin;`.

- **Must print:** the row `DRYRUN 20261019_0061_drop_invite_codes.sql OK` (or, if the editor shows only the last statement, "Success" with no error). Its three probes, `invite_codes_dropped`, `account_deletion` and `short`, run inside it, and any of them failing ends it in `ERROR: PROBE … FAILED: …`.
- **Then:** run the check. It must read exactly as after Step 1: `invite_codes_exists`, `validate_invite_code_exists` and `delete_user_account_unchanged` all **true**.
- **Stop on:** any `ERROR`, or any of those three reading false. If one of them reads false, the dry run committed: tell the orchestrator immediately; the rollback is C0 plus the CSV, then `delete_user_account` from `20261017_0004:214-499`.

## Step 3: File C (drop `invite_codes`)

Paste the **whole file** `supabase/migrations/20261019_0061_drop_invite_codes.sql`, alone in a new tab. It is 93 lines, md5 `38429203c3d2e3f7081d977f7d1c3abb`. It is one transaction: `begin;`, block 1 (`delete_user_account` without its `invite_codes` line, derived from the live body with md5 checks before and after), block 2 (`drop table public.invite_codes`), block 3 (the four functions), a guard that no public function still names the table, then `commit;`.

- **Must print:** "Success. No rows returned" (no error). If block 1's md5 check finds a different live body, it raises `delete_user_account is not the expected live body`, and nothing is changed.
- **Then:** run the check. `invite_codes_exists`, `validate_invite_code_exists` and `delete_user_account_unchanged` are now false.
- **Then (orchestrator, MCP):** `invite_codes_dropped`, `short` and `account_deletion` must print OK. Account deletion has to keep working (App Store 5.1.1(v)). Then File C's header becomes APPLIED, with the deployed `delete_user_account` md5, which must be `bd886e739d25dbe7497ff6b21c5aa248`.
- **Stop on:** any error. If `account_deletion` or `short` fails afterwards, tell the orchestrator before anything else. The rollback is C0, the CSV, and `delete_user_account` from `20261017_0004:214-499`.

## Step 4: File E, the nine old read policies

Paste exactly this, alone in a new tab. These are block 2 of `20261019_0063` and the two `drop policy` lines of its block 4, in file order. Do **not** paste the whole File E: its `create policy` statements already ran, so the file would fail and roll back.

```sql
drop policy if exists "Allow public read access on message-images" on storage.objects;
drop policy if exists "Message image read" on storage.objects;
drop policy if exists "Allow public read access on group-images" on storage.objects;
drop policy if exists "Anyone can view group images" on storage.objects;
drop policy if exists "Allow public read access on town-hall-images" on storage.objects;
drop policy if exists "Town hall public read" on storage.objects;
drop policy if exists "Allow public access to review images" on storage.objects;
drop policy if exists "Allow public read access on audio-messages" on storage.objects;
drop policy if exists "Anyone can view audio messages" on storage.objects;
```

- **Must print:** "Success. No rows returned" (no error).
- **Then:** run the check. `old_storage_read_policies_present` is now false, and every column reads false.
- **Then:** the probe `storage_private` must print OK. It inserts probe rows into `storage.objects` inside a rolled-back transaction. The orchestrator tries it through the MCP first. If the MCP declines it, paste into a new tab the probe file's PARAMETERS and HELPERS sections plus the `storage_private` block (`supabase/probes/communities_probe.sql`), and nothing else. Then do iOS plan Task 12 Step 4: the two-simulator check that message, group, Town Hall and review photos and voice notes still load, and that the public route answers 400.
- **Stop on:** any error. If photos stop loading for a signed-in member, the rollback is to recreate the dropped policies from the Phase 5 SQL plan's P2 (each `for select to public using (bucket_id = '<bucket>')`, and "Message image read" with its EXISTS clause).

## After all four steps

1. Run the full probe file `supabase/probes/communities_probe.sql` (md5 `5e56723831ef43fb1b5231a6fa9ed5df`) in the SQL editor, the whole file in one tab. Its last row must be `PROBE ALL OK`. It holds `posts_delete_policy`, which only the SQL editor can run. `legacy_bridges` prints SKIPPED, and `broadcast_cap` takes its 42501 branch.
2. The orchestrator flips the headers of `20261019_0060`, `0061` and `0063` to APPLIED.

## Not SQL, but due now

- **Release notes and App Store review notes** (Phase 4 runbook step 6): announcements now arrive as a push for every member who has not muted the community, also when Town Hall notifications are off.
- **Legal follow-up** (Phase 5a note): once Step 4 is done, tighten `Legal/PRIVACY_POLICY.md`'s sentence that images may be reachable by URL.
