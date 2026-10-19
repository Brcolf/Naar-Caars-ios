# Multi-community Phase 5: server migrations and probes

> Companion of `2026-10-19-multi-community-phase5.md` (the iOS plan). This file holds the complete SQL of Phase 5 and its probe blocks. **File A (5a) is applied by the orchestrator now.** **Files B-E (5b) are written to disk, dry-run inside rolled-back transactions and committed with a NOT APPLIED header; none of them is applied until the gate of amendment A5 point 2** (iOS plan Task 12). The orchestrator copies each fenced block to the file named above it and records outcomes in the headers. Agents executing the iOS plan never write under `supabase/`.

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` §4 "Phase 5 - Deprecations" (lines 976-982), §3.2 `fill_request_community` (the "rollout safety only, removed in Phase 5" branch, lines 433-437), INV-L1 (line 763), D16 (line 1094), D19, D20, under `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` amendment **A5** (lines 54-62), which wins where they differ. Every live value below was read through the Supabase MCP on 2026-10-19 with read-only `select`s.

## What Phase 5 needs from the server, and where each piece is

| Item (A5 / spec) | Where | Applied | What the installed pre-community build sees |
|---|---|---|---|
| A definer lookup that returns only the multiplier | File A blocks 1-2 (`get_geocoding_multiplier`, `put_geocoding_multiplier`) | **now (5a)** | nothing: new names; it keeps reading and writing the table directly |
| Placemark data no longer kept | File A block 3 (optional, D-S8; a one-time clean-up) and File D block 2 (the same clear, repeated at the gate) | now, if kept; again at the gate | nothing: it reads only `multiplier` (`main:…/GeocodingCacheService.swift`, `select("multiplier")`). It also keeps **writing** placemarks with its direct upsert (`main:NaarsCars/Core/Utilities/GeocodingCacheService.swift:152`, `placemarkData: placemarkPayload(from:)`), as do Phase 1-4 builds, until File D closes the table, so block 3 cleans only the rows that exist when it runs |
| Stop maintaining `profiles.heard_about / join_reason` for new rows | client: iOS Task 4; server copy: File B blocks 2-3 | client now; server **gated** | after File B: its Pending Users screen shows "Not provided" for applicants who joined through a community build |
| Retire `legacy_application_to_membership`, `sync_legacy_approval_to_membership` | File B blocks 4-5 | **gated** | its application form can no longer submit, and its Approve no longer approves (both writes raise; block 4) |
| The rollout fallback in `fill_request_community` | File B block 1 | **gated** | an approved account with no membership row cannot post (0 such accounts on 2026-10-19) |
| The `is_default` dependence | File B blocks 1-3, 7 (and INV-L1 kept, D-S4) | **gated** | as the rows above; block 7: its admin "Send Broadcast" fails |
| `admin_reject_pending_user` revoked from `authenticated` | File B block 6 | **gated** | its Reject fails with an error alert |
| `invite_codes` and its policies / triggers dropped | File C (SQL editor) | **gated** | nothing reachable: no screen of the installed build uses the table (`git grep AdminInviteView main` finds no presenter); `validate_invite_code` (anon-callable today) goes |
| `geocoding_cache` direct access revoked | File D | **gated** (+ the 5a client in every build in use) | its availability probe (`select id limit 1`) fails with 42501, which it does **not** treat as a missing table (`main:NaarsCars/Core/Utilities/GeocodingCacheService.swift:173-198`; `isMissingGeocodingCacheTable`, `:200-207`, matches only 42P01 or a "does not exist" message), so caching never turns off: on every ride end that reaches the lookup it sends one failing probe before the read and another before the write, then reverse-geocodes on the device with the same rules (2 s timeout per end); the estimate is still produced and saved |
| Private buckets for `message-images`, `group-images`, `town-hall-images`, `review-images` | File E (SQL editor); `audio-messages` optional (D-1) | **gated** (+ the 5a client in every build in use) | **every message, group, Town Hall and review photo stops loading** (the public route answers 400); uploads still succeed; avatars unaffected |

## Statements the MCP declines

- **File A:** none. Block 3 is an `UPDATE … WHERE` (not a bare `DELETE`).
- **File B:** no `DELETE`, no `DROP POLICY`, nothing under `auth.*` / `storage.*`. Blocks 2-3 are `DO` blocks that `EXECUTE` a function definition derived from the live one (D-S1); block 5 is `DROP TRIGGER` / `DROP FUNCTION`. Neither is a known decline; **if the MCP declines a block, that block goes to the SQL editor (owner)**, verbatim.
- **Dry-run scripts** (`supabase/dryruns/`): the B and D scripts hold nothing the MCP declines; the C and E scripts hold their file's declined statements, so the owner runs them in the SQL editor.
- **File C: SQL editor (owner), one transaction.** Its `delete_user_account` body deletes from `auth.users` and `storage.objects` (declined), and it holds `DROP TABLE`.
- **File D:** a `REVOKE` (block 1) and an `UPDATE … WHERE` (block 2, not a bare `DELETE`); both accepted.
- **File E: SQL editor (owner), one transaction.** `DROP POLICY` (declined) and an `UPDATE` of `storage.buckets`.
- **Probe `storage_private`** inserts rows into `storage.objects` inside a rolled-back transaction; it runs inside File E's dry-run script (SQL editor, owner) and, at the gate, by itself in the SQL editor if the MCP declines it.

The orchestrator sends one block per call and never a file header (headers name declined statements in prose).

## Preconditions (read only, orchestrator; values observed on 2026-10-19)

- **P1. Live bodies.** `select proname, pg_get_function_identity_arguments(oid), md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname in (...)` must return exactly these before the block that changes each one; stop on any difference. Every "live" value equals the deployed value recorded in its source file's header, so the rollback source is that file.

  | Function | md5(prosrc) live | Rollback source (deployed md5 in its header) | md5 after Phase 5 |
  |---|---|---|---|
  | `fill_request_community()` | `6241f67fc4e8618ac782b99a7b6d9295` | `20261017_0001_communities_core.sql:834-871` (header `:84`) | `9d4cfb03912a7c4a874cffae239ee605` (B1) |
  | `redeem_community_invite(text, text, text)` | `f18e6af6f7ca7a53acd193db115b1f27` | `20261017_0005_communities_rpcs.sql:1076-1213` (header `:28`) | `2ec0702dc3a4d400ca2599d0ebb15693` (B2) |
  | `request_to_join_community(uuid, text, text)` | `da89c2337d8102d4c284440c534c2b2a` | `20261017_0005_communities_rpcs.sql:1226-1327` (header `:29`) | `af9a2f5c560d2d74f35ab979e2f3856c` (B3) |
  | `protect_admin_fields()` | `48424e05ea801252b83ed8c893db5f4f` | `20261017_0001_communities_core.sql:290-312` (header `:66`) | `d963a013278b5ace77565b8397683bf2` (B4) |
  | `legacy_application_to_membership()` | `387361399eda45649d08c1332c2df72c` | `20261017_0001:657-694`, trigger `:757-759` (header `:82`) | dropped (B5) |
  | `sync_legacy_approval_to_membership()` | `523906605a77307bb088f34d820e9093` | `20261017_0001:709-752`, trigger `:764-766`, revoke `:768-769` (header `:83`) | dropped (B5) |
  | `admin_reject_pending_user(uuid)` | `f5366ee20a4fa51908b3e8173cb1e400` | `20261017_0004_communities_account_lifecycle.sql:504-` (header `:13`) | unchanged; EXECUTE revoked (B6) |
  | `delete_user_account(uuid)` | `135aca113be1ebf5281c03c288ee32c6` | `20261017_0004:214-496`, grants `:498-499` (header `:12`) | `bd886e739d25dbe7497ff6b21c5aa248` (C1) |
  | `validate_invite_code(text)` | `0e330ecc03e2b00bedd3d0cc4785070f` | none in `supabase/migrations`; captured by C0 | dropped (C3) |
  | `mark_invite_code_used(text, text, text, text)` | `d129033694581c28234019c05cdcf78a` | `database/074_create_mark_invite_used_function.sql` (legacy, not verified identical); captured by C0 | dropped (C3) |
  | `guard_invite_code_client_update()` | `530255a0f0968765af6f922074cadbc9` | `20261006_0003_guard_invite_code_client_update.sql:26-49` | dropped (C3) |
  | `handle_invite_code_used()` | `255138a67eb745d065cbe9950dcf6bc8` | none; captured by C0 | dropped (C3) |
  | `get_leaderboard(text, integer)`, `get_leaderboard(date, date)` | `f97d8b82dbd14225a46f6e32558b0499`, `c52c79d1fd79c298fc40fdc320f62e23` | grants only (B7) | unchanged; EXECUTE revoked (B7, optional) |
  | `send_broadcast_notifications(text, text, text, boolean)` | `e238abe6ecffbf8cf4835e5703a74ee7` | `20261017_0003_communities_fanout.sql:981-` | unchanged; EXECUTE revoked (B7, optional) |
  | `create_signup_profile(...)` | `22686fb9af22c3c648ac77ab56c4a83c` | `20261017_0003:2062-` (header `:161`) | **not changed** (D-S5) |

  Each derived body (B2, B3, C1) removes one passage that occurs **exactly once** in the live `prosrc` (checked 2026-10-19: occurrence count 1 for all four cuts, B1's included); the "after" md5 values were computed in SQL from `md5(replace(prosrc, <passage>, ''))`. B1 and B4 are written out in full; B1's text was hashed and equals its computed "after" value.
- **P2. Grants, policies and data** (the rollback text of Files C-E is these rows):
  - `geocoding_cache`: 7 rows, newest `created_at` 2026-09-15; unique `location_key`; policies `geocoding_cache_select_authenticated` (SELECT), `_insert_authenticated` (INSERT, CHECK), `_update_authenticated` (UPDATE), all `authenticated` and all `(select is_active_user((select auth.uid())))`; no DELETE policy; table grants: `anon` and `authenticated` hold every privilege.
  - `invite_codes`: 62 rows (54 never used); columns `id, code, created_by, used_by, used_at, created_at, invite_statement, is_bulk, expires_at, bulk_code_id`; constraints `invite_codes_code_key UNIQUE (code)`, `invite_codes_created_by_fkey → profiles(id) ON DELETE CASCADE`, `invite_codes_used_by_fkey → profiles(id) ON DELETE SET NULL`, `invite_codes_bulk_code_id_fkey → invite_codes(id) ON DELETE SET NULL`; no other table references it; triggers `guard_invite_code_client_update` and `on_invite_code_used` (BEFORE UPDATE); policies "Approved users can create invite codes" (INSERT), "Users can view own created codes" (SELECT, `created_by = (select auth.uid())`), `invite_codes_insert_allowed` (INSERT), `invite_codes_update_mark_as_used` (UPDATE); grants: `anon` and `authenticated` every privilege. `validate_invite_code` is EXECUTE for PUBLIC, `anon`, `authenticated`; `mark_invite_code_used` for `service_role` only. The only function body naming the table is `delete_user_account` (live line 269: `    delete from public.invite_codes where created_by = p_user_id;`); no cron job names it.
  - `storage.buckets`: `message-images`, `group-images`, `town-hall-images`, `review-images`, `audio-messages`, `avatars`, all `public = true`. Objects: 17, 5, 2, 5, 5, 8. `storage.objects` SELECT policies: "Allow public read access on message-images" (public, `bucket_id = 'message-images'`), "Message image read" (public, `bucket_id = 'message-images' AND EXISTS (SELECT 1 FROM conversation_participants WHERE user_id = auth.uid())`), "Allow public read access on group-images", "Anyone can view group images", "Allow public read access on town-hall-images", "Town hall public read", "Allow public access to review images", "Allow public read access on audio-messages", "Anyone can view audio messages", "Avatar public read" (each `bucket_id = '<bucket>'` alone, role public). INSERT, UPDATE and DELETE policies are unchanged by this phase.
  - Stored URLs: every `messages.image_url` (13), `conversations.group_image_url` (4) and `town_hall_posts.image_url` (1) has the form `https://<project>.supabase.co/storage/v1/object/public/<bucket>/<path>`; review URLs add `?t=<timestamp>`. **No review carries an image** (`select count(*) from reviews where image_url is not null` = 0); the 5 objects in `review-images` are orphans (the app names uploads with a fresh `UUID()`, `ReviewService.swift:60, :196`, not the review id). No Town Hall post names a `review-images` URL (0).
  - Grants: `admin_reject_pending_user` EXECUTE `authenticated`, `service_role`; `get_leaderboard` (both) PUBLIC, `anon`, `authenticated`; `send_broadcast_notifications` `authenticated`.
- **P3. Counts that must hold before File B** (2026-10-19): approved accounts with no membership row **0**; `approved` mirror drift **0**; `application_complete` mirror drift **0**; pending default-community applicants **0**; `applied` events in the last 30 days 2; profiles with `heard_about` or `join_reason` set 5; live communities 1; profiles 19. If the first count is not 0 at the gate, give those accounts a membership (Requests to join) before block 1, or they cannot post.
- **P4. None of the new names exists:** `get_geocoding_multiplier`, `put_geocoding_multiplier`.
- **P5. Migration numbers.** `ls supabase/migrations/20261019_*` before writing; Phase 4 uses `20261019_0001`-`0003` (its SQL plan); if anything else took `0050`-`0063`, renumber upward and keep the order A, B, C, D, E.

## Runbook (orchestrator)

**5a, now:**

1. P1 (the File A rows: none), P4, P5.
2. **Dry run** (one `execute_sql`): `begin;` File A blocks 1-3 (block 3 only if the owner keeps D-S8), the probe PARAMETERS and HELPERS (with the additions below, without the HELPERS `commit;`), the blocks `geocoding_lookup` and `short` with each `begin;` / `rollback;` turned into `savepoint probe;` / `rollback to savepoint probe;`, `rollback;`. Pass when both print OK.
3. **Apply File A**, one `apply_migration` per block (names `20261019_0050_block_<n>`), `short` after each.
4. **Probe** `geocoding_lookup` through the MCP.
5. **Record** in File A's header: APPLIED with the date, the migration-history versions, `md5(prosrc)` of both functions, the probe outcomes. Commit the migration file and the probe file together (iOS plan Task 6 may land before or after; the client tolerates either order).

**5b, now (iOS plan Task 11):** write Files B-E with NOT APPLIED headers; assemble the five files of "Dry-run scripts (5b)" below and pass their structural check; run C0 (File C's rollback capture) and export the `invite_codes` rows to a CSV off the repository **before** any File C dry run; dry-run B and D through the MCP (each script verbatim, one `execute_sql` call); hand the C and E scripts to the owner for the SQL editor (the committed script verbatim, alone in the editor tab; **never** a migration file or the probe file); after each of the four runs, the not-applied check, which must answer `all_unchanged = true`; record each outcome in the header; re-run P1-P3 to show nothing changed; commit locally; **ask the owner before pushing** (CLAUDE.md, public repository).

**5b, at the gate only (iOS plan Task 12):** P1-P3 again; File B blocks 1 → 6 (7 if kept) one per call with `short` after each, then `legacy_retired`, `legacy_bridges` (SKIPPED), `broadcast_cap` (its 42501 branch when block 7 is applied), `privileged_columns`, `account_deletion`; File D (blocks 1-2), then `geocoding_revoked`; **owner:** File C (then `invite_codes_dropped`, `short`, `account_deletion`), File E (then `storage_private`); the full probe file last. Headers become APPLIED with deployed md5 values.

**Sequencing inside File B.** Block 4 (the mirror-only flags) goes before block 5 (dropping the bridges): with block 4 live, the installed build's two direct writes raise before the bridges could fire, so there is never a moment when an application leaves `application_complete = true` with no membership.

---

## Dry-run scripts (5b)

**Why a script, not the files.** A migration file or the probe file pasted into a transaction does not stay inside it. The probe file's HELPERS section ends with a deliberate `commit;` (`supabase/probes/communities_probe.sql:363`; the header at `:27-30` explains it), and every probe block opens and closes its own transaction (`begin;` `:372` … `rollback;` `:460`, and so on for each block). Pasted after a file's blocks, the HELPERS `commit;` applies the gated migration for real (for File C: `invite_codes` dropped and `delete_user_account` replaced; for File E: four private buckets, and every message, group, Town Hall and review photo stops loading on the installed build), and even without it the first probe's `rollback;` ends the outer transaction, so the later probes test the unchanged database. So each gated file gets one committed script, outside `supabase/migrations` and never applied, that the MCP or the owner runs verbatim.

| File | Script (`supabase/dryruns/`) | Run by | Probe blocks, in this order |
|---|---|---|---|
| B | `20261019_0060_retire_legacy_bridges.dryrun.sql` | orchestrator, MCP `execute_sql` (one call) | `legacy_retired`, `legacy_bridges` (prints SKIPPED), `broadcast_cap` (its block-7 branch), `privileged_columns`, `account_deletion`, `short` |
| C | `20261019_0061_drop_invite_codes.dryrun.sql` | **owner, SQL editor** | `invite_codes_dropped`, `account_deletion`, `short` |
| D | `20261019_0062_geocoding_cache_direct_access_revoked.dryrun.sql` | orchestrator, MCP `execute_sql` (one call) | `geocoding_revoked`, `geocoding_lookup`, `short` |
| E | `20261019_0063_private_image_buckets.dryrun.sql` | **owner, SQL editor** | `storage_private`, `short` |

**Assembly** (the orchestrator, by copying text; every piece is taken from the committed files after the probe additions below are in place, so the HELPERS include `probe_require_phase5` and `probe_storage_object`):

1. A header comment: `-- DRY RUN of supabase/migrations/<file>. NEVER APPLIED. Ends in rollback; contains no commit. Paste verbatim.`
2. PARAMETERS: the four `select set_config('probe.…', '', false);` lines (`communities_probe.sql:94-97` at `4956682`).
3. HELPERS: every line from the HELPERS banner (`:100`) through the last statement before its `commit;` (`:362`), **without** the `commit;` line.
4. `begin;`
5. The migration's blocks: File B blocks 1-7 (block 7 only while D-S3 is kept); File C blocks 1-3 and its guard `DO` block, **without** the file's own `begin;` and `commit;`; File D blocks 1-2; File E blocks 1-3 (block 4 only with D-1), **without** its `begin;` and `commit;`. The file headers are not copied (they name declined statements in prose).
6. Each probe block of the table's row, from its banner through its `select 'PROBE <name> OK' as probe;` line, with its one `begin;` line replaced by `savepoint probe;` and its one `rollback;` line replaced by `rollback to savepoint probe; release savepoint probe;`. Nothing inside the `DO` bodies changes.
7. `select 'DRYRUN <file> OK' as dryrun;`
8. `rollback;`

PARAMETERS and HELPERS stand before the `begin;`. Sent as one multi-statement request (the SQL editor, `execute_sql`), PostgreSQL folds them into the transaction the `begin;` opens and the final `rollback;` removes them too; sent statement by statement they commit on their own, which is harmless, because they create only `pg_temp` functions and session settings. A statement that raises anywhere aborts the transaction and the rest of the script does not run; the migration's blocks are committed in neither case.

**Structural check** (run on each script before it is committed or run; any mismatch: fix the script, never run it):

```bash
S=supabase/dryruns/<script>; N=<number of probe blocks in the table row>
grep -niE '^[[:space:]]*commit[[:space:]]*;' "$S"                       # expected: no output
grep -cE '^begin;$' "$S"                                                 # expected: 1
grep -cE '^rollback;$' "$S"                                              # expected: 1
grep -cE '^savepoint probe;$' "$S"                                       # expected: N
grep -cE '^rollback to savepoint probe; release savepoint probe;$' "$S"  # expected: N
grep -vE '^[[:space:]]*(--.*)?$' "$S" | tail -2                          # expected: the DRYRUN select, then rollback;
awk '/^create or replace function pg_temp\./{h=NR} /^begin;$/{b=NR} END{exit !(h<b)}' "$S" && echo helpers-before-begin   # expected: helpers-before-begin
```

**Not-applied check** (`supabase/dryruns/20261019_phase5b_not_applied_check.sql`, read only, run through the MCP after every dry run, and by the owner in a new SQL-editor tab after theirs). On 2026-10-19 it answered `all_unchanged = true` with every column true:

```sql
-- supabase/dryruns/20261019_phase5b_not_applied_check.sql
--
-- READ ONLY. Never applied. Proves that no Phase 5b file (20261019_0060-0063) is applied: run it after every
-- 5b dry run (iOS plan Task 11) and before the 5b gate. Every column must be true; all_unchanged sums them up.
-- false in any column (or an error such as "function ... does not exist") means something was applied: stop
-- and follow the dry-run section of the Phase 5 SQL plan ("If the check is not all true").
-- Expected values read through the Supabase MCP on 2026-10-19.
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

**If the check is not all true** (a dry run committed something): stop, tell the owner at once, and do not run another script. Restore from the file's own rollback text: File B and File D from their headers; File C from the C0 capture (`20261019_0061a`) and the CSV taken before its dry run, then `delete_user_account` from `20261017_0004:214-499`; File E with its header's rollback (`update storage.buckets set public = true …`, recreate the seven policies from P2, drop the new ones). For File E the installed build shows no message, group, Town Hall or review photo until the rollback runs, so it is the first thing done.

---

## File A — `supabase/migrations/20261019_0050_geocoding_multiplier_lookup.sql` (5a, apply now)

````sql
-- 20261019_0050_geocoding_multiplier_lookup.sql
--
-- NOT APPLIED. Phase 5a of the multi-community design (Docs/superpowers/specs/2026-10-07-multi-community-design.md
-- §4 "Phase 5", D16), under amendment A5 of Docs/superpowers/specs/2026-10-17-multi-community-decisions.md
-- ("add a definer geocoding lookup and move the client to it"; the SELECT revoke is 5b, 20261019_0062).
--
-- What it does.
--   * get_geocoding_multiplier(p_location_key) -> numeric: the multiplier of a cached place, only for an
--     active account (is_active_user, caller-bound), only for a well-formed key (the client's 3-decimal
--     "lat_lon", RideCostEstimator.cacheKey), only when the row was written in the last 24 hours (updated_at,
--     falling back to created_at). Null otherwise. No other column is ever returned.
--   * put_geocoding_multiplier(p_location_key, p_latitude, p_longitude, p_multiplier) -> boolean: the client's
--     write after an on-device reverse geocode. Active accounts only; the key must be well formed and match
--     the coordinates to 3 decimals; the multiplier must lie in the range the client computes (0.9-1.5,
--     GeocodingCacheService.placemarkMultiplier). Upsert on location_key, placemark_data always null,
--     updated_at = now(). Answers false on any refusal (the client treats the cache as best effort).
--   * Block 3 (optional, D-S8): clears the placemark data written so far. No reader exists. A ONE-TIME
--     clean-up: the installed build and Phase 1-4 builds keep upserting placemark_data directly
--     (main:NaarsCars/Core/Utilities/GeocodingCacheService.swift:152) until 20261019_0062 closes the table,
--     which repeats the clear (its block 2).
--
-- What old clients see. Nothing. The installed build and the Phase 1-4 builds keep reading
-- select("multiplier") and upserting the table directly; this file changes no policy and no grant on it.
-- A row such a build refreshes keeps its old updated_at (PostgREST updates only the columns sent), so the
-- 5a client treats it as expired until it writes the key itself. Harmless: the multiplier is recomputed.
--
-- Apply. Supabase MCP apply_migration, one block per call, in order. Nothing here is declined.
-- Verification. Dry run: blocks 1-3 in one begin; ... rollback; with the probe PARAMETERS, the HELPERS without
-- their commit;, and the probe blocks geocoding_lookup and short with begin;/rollback; turned into savepoints
-- (the plan's runbook step 2; the same assembly as the 5b dry-run scripts). Then short after each block and
-- geocoding_lookup at the end.
-- Outcomes: not yet run.
--
-- Rollback. drop function public.put_geocoding_multiplier(text, numeric, numeric, numeric);
-- drop function public.get_geocoding_multiplier(text); (the 5a client then finds no function, turns its
-- lookup off for the session and still estimates every ride). Block 3 cannot be undone; the multipliers are
-- untouched by it.


-- ============================================================================================
-- BLOCK 1: public.get_geocoding_multiplier(text)   (new)
-- ============================================================================================
create or replace function public.get_geocoding_multiplier(p_location_key text)
returns numeric
language sql
stable
security definer
set search_path = ''
as $function$
  select g.multiplier
    from public.geocoding_cache g
   where public.is_active_user((select auth.uid()))
     and p_location_key ~ '^-?[0-9]{1,3}\.[0-9]{3}_-?[0-9]{1,3}\.[0-9]{3}$'
     and g.location_key = p_location_key
     and coalesce(g.updated_at, g.created_at) >= now() - interval '24 hours'
   limit 1;
$function$;

revoke all on function public.get_geocoding_multiplier(text) from public, anon;
grant execute on function public.get_geocoding_multiplier(text) to authenticated;


-- ============================================================================================
-- BLOCK 2: public.put_geocoding_multiplier(text, numeric, numeric, numeric)   (new)
-- The checks are split so a malformed key never reaches the numeric casts (OR has no evaluation order).
-- ============================================================================================
create or replace function public.put_geocoding_multiplier(
    p_location_key text,
    p_latitude numeric,
    p_longitude numeric,
    p_multiplier numeric
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if not public.is_active_user((select auth.uid())) then
    return false;
  end if;
  if p_location_key is null
     or p_location_key !~ '^-?[0-9]{1,3}\.[0-9]{3}_-?[0-9]{1,3}\.[0-9]{3}$'
     or p_latitude is null or p_longitude is null or p_multiplier is null then
    return false;
  end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180
     or abs(split_part(p_location_key, '_', 1)::numeric - p_latitude) > 0.0005
     or abs(split_part(p_location_key, '_', 2)::numeric - p_longitude) > 0.0005
     or p_multiplier < 0.9 or p_multiplier > 1.5 then
    return false;
  end if;

  insert into public.geocoding_cache (latitude, longitude, location_key, multiplier, placemark_data, created_at, updated_at)
  values (p_latitude, p_longitude, p_location_key, p_multiplier, null, now(), now())
  on conflict (location_key) do update
     set latitude = excluded.latitude,
         longitude = excluded.longitude,
         multiplier = excluded.multiplier,
         placemark_data = null,
         updated_at = now();
  return true;
end
$function$;

revoke all on function public.put_geocoding_multiplier(text, numeric, numeric, numeric) from public, anon;
grant execute on function public.put_geocoding_multiplier(text, numeric, numeric, numeric) to authenticated;


-- ============================================================================================
-- BLOCK 3 (optional, D-S8): the placemarks written so far. Seven rows on 2026-10-19; no client or function
-- reads placemark_data. One-time: builds without the 5a client keep writing placemarks until 20261019_0062,
-- whose block 2 clears them again.
-- ============================================================================================
update public.geocoding_cache set placemark_data = null where placemark_data is not null;
````

---

## File B — `supabase/migrations/20261019_0060_retire_legacy_bridges.sql` (5b, NOT APPLIED)

````sql
-- 20261019_0060_retire_legacy_bridges.sql
--
-- NOT APPLIED. GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (Docs/superpowers/specs/2026-10-17-multi-community-decisions.md, A5 point 2). Phase 5b of the
-- multi-community design (§4 "Phase 5": retire the legacy bridges, the rollout fallback in
-- fill_request_community and the is_default dependence; admin_reject_pending_user revoked from authenticated;
-- stop maintaining profiles.heard_about / join_reason for new rows).
--
-- What it does.
--   1. fill_request_community: the "rollout safety only, removed in Phase 5" branch goes (spec lines 433-437):
--      an account with no membership row is no longer placed in the default community because profiles.approved
--      is true. Primary, then oldest active membership, else 'Choose a community' (42501), as before.
--   2-3. redeem_community_invite / request_to_join_community: the copy of a default-community applicant's
--      answers into profiles.heard_about / join_reason goes (it existed only for the installed build's Pending
--      Users screen, D19). Answers stay on the community_members row. Derived from the live body (D-S1).
--   4. protect_admin_fields: approved and application_complete become mirror-only. With the bridges gone a
--      direct write would leave the mirror wrong, so any UPDATE that carries an end-user JWT and changes either
--      column raises 42501, platform admins included; recompute_profile_membership_flags (the flag
--      naars.membership_mirror) and writes with no JWT (migrations, SQL editor, service role) pass. The other
--      guarded columns keep today's rule (admins may change them).
--   5. The two bridge triggers on profiles and their functions are dropped.
--   6. admin_reject_pending_user: EXECUTE revoked from authenticated (service_role keeps it). No community
--      build calls it after iOS Task 2.
--   7. (optional, D-S3) The installed build's remaining default-community wrappers: EXECUTE revoked on
--      get_leaderboard (both overloads; no build calls them) and send_broadcast_notifications (only the
--      installed admin build calls it; community builds call send_community_broadcast).
--
-- What old clients see (the installed pre-community build; the gate says none is left).
--   1: an approved account with no membership row cannot post (0 such accounts on 2026-10-19). 2-3: its Pending
--   Users screen shows "Not provided" for answers of applicants who joined through a community build. 4: its
--   application form's submit and its admin Approve both fail with their error alerts
--   (application_error_submit_failed, admin_approve_failed). 5: nothing beyond 4. 6: its Reject fails
--   (admin_reject_failed). 7: its Send Broadcast fails. Community builds (Phase 2 and later) see nothing: they
--   never write approved / application_complete, never call these functions, and read answers from
--   community_members.
--
-- Apply. Supabase MCP apply_migration, one block per call, in order 1 → 6 (7 if kept); block 4 before block 5
-- (see the plan's runbook). Before blocks 1-4 compare md5(prosrc) with the value above each; blocks 2-3 check
-- it themselves and raise on a mismatch. If the MCP declines a block, SQL editor (owner), verbatim.
-- Verification. Dry run (now): supabase/dryruns/20261019_0060_retire_legacy_bridges.dryrun.sql through the MCP
-- (every block inside one begin; ... rollback;, with legacy_retired, legacy_bridges, broadcast_cap,
-- privileged_columns, account_deletion and short as savepoints), then the not-applied check. Outcomes: not yet run. At the gate: short after every block; legacy_retired,
-- privileged_columns, account_deletion at the end.
--
-- Rollback, in reverse order. 7: grant execute on the three functions back to the roles in the plan's P2.
-- 6: grant execute on function public.admin_reject_pending_user(uuid) to authenticated. 5: re-run
-- 20261017_0001_communities_core.sql:657-694, 709-752, 757-769 (functions, triggers, revoke). 4: re-run
-- 20261017_0001:290-312. 3: 20261017_0005_communities_rpcs.sql:1226-1327. 2: 20261017_0005:1076-1213.
-- 1: 20261017_0001:834-871. Answers not copied while the file was live are still on community_members.


-- ============================================================================================
-- BLOCK 1: public.fill_request_community()   live md5(prosrc) 6241f67fc4e8618ac782b99a7b6d9295
-- (20261017_0001:834-871). Removed: the third branch (default_community_id() for an approved account with no
-- membership row). Deployed md5 must be 9d4cfb03912a7c4a874cffae239ee605.
-- ============================================================================================
create or replace function public.fill_request_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c uuid;
begin
  if new.community_id is not null then
    return new;
  end if;
  select m.community_id into v_c
    from public.profiles p
    join public.community_members m on m.user_id = p.id and m.community_id = p.primary_community_id and m.status = 'active'
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where p.id = new.user_id;
  if v_c is null then
    select m.community_id into v_c
      from public.community_members m
      join public.communities c on c.id = m.community_id and c.archived_at is null
     where m.user_id = new.user_id and m.status = 'active'
     order by m.activated_at nulls last, m.community_id
     limit 1;
  end if;
  if v_c is null then
    raise exception 'Choose a community' using errcode = '42501';
  end if;
  new.community_id := v_c;
  return new;
end
$function$;


-- ============================================================================================
-- BLOCK 2: public.redeem_community_invite(text, text, text)   live md5 f18e6af6f7ca7a53acd193db115b1f27
-- (20261017_0005:1076-1213). Derived from the live definition (D-S1). Removed, exactly once, these 8 lines
-- (the default-community copy into profiles):
--     select c.is_default into v_is_default from public.communities c where c.id = v_inv.community_id;
--     if v_status = 'pending' and v_is_default then
--       update public.profiles
--          set heard_about = coalesce(v_heard, heard_about),
--              join_reason = coalesce(v_reason, join_reason)
--        where id = v_uid;
--     end if;
--     <blank line>
-- The declared v_is_default stays (unused). Grants are kept by CREATE OR REPLACE.
-- Deployed md5 must be 2ec0702dc3a4d400ca2599d0ebb15693.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.redeem_community_invite(text, text, text)'::regprocedure;
  v_cut constant text := E'  select c.is_default into v_is_default from public.communities c where c.id = v_inv.community_id;\n  if v_status = ''pending'' and v_is_default then\n    update public.profiles\n       set heard_about = coalesce(v_heard, heard_about),\n           join_reason = coalesce(v_reason, join_reason)\n     where id = v_uid;\n  end if;\n\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'f18e6af6f7ca7a53acd193db115b1f27' then
    raise exception 'redeem_community_invite is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'redeem_community_invite: the answer copy was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> '2ec0702dc3a4d400ca2599d0ebb15693' then
    raise exception 'redeem_community_invite: unexpected body after the edit';
  end if;
end
$derive$;


-- ============================================================================================
-- BLOCK 3: public.request_to_join_community(uuid, text, text)   live md5 da89c2337d8102d4c284440c534c2b2a
-- (20261017_0005:1226-1327). Derived from the live definition (D-S1). Removed, exactly once, these 7 lines:
--     if v_c.is_default then
--       update public.profiles
--          set heard_about = coalesce(v_heard, heard_about),
--              join_reason = coalesce(v_reason, join_reason)
--        where id = v_uid;
--     end if;
--     <blank line>
-- Deployed md5 must be af9a2f5c560d2d74f35ab979e2f3856c.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.request_to_join_community(uuid, text, text)'::regprocedure;
  v_cut constant text := E'  if v_c.is_default then\n    update public.profiles\n       set heard_about = coalesce(v_heard, heard_about),\n           join_reason = coalesce(v_reason, join_reason)\n     where id = v_uid;\n  end if;\n\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'da89c2337d8102d4c284440c534c2b2a' then
    raise exception 'request_to_join_community is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'request_to_join_community: the answer copy was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'af9a2f5c560d2d74f35ab979e2f3856c' then
    raise exception 'request_to_join_community: unexpected body after the edit';
  end if;
end
$derive$;


-- ============================================================================================
-- BLOCK 4: public.protect_admin_fields()   live md5 48424e05ea801252b83ed8c893db5f4f (20261017_0001:290-312)
-- Changes: approved and application_complete are mirror-only for every end-user JWT (D-S2); approved leaves the
-- admin-guarded list, whose message changes accordingly. Deployed md5 must be d963a013278b5ace77565b8397683bf2.
-- Before this block: confirm no function other than recompute_profile_membership_flags and
-- sync_legacy_approval_to_membership writes either column (both set naars.membership_mirror; read 2026-10-19).
-- ============================================================================================
create or replace function public.protect_admin_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if current_setting('naars.membership_mirror', true) = '1' then
        return new;
    end if;

    -- Phase 5b: approved and application_complete follow memberships only. With the legacy bridges
    -- retired a direct write would leave the mirror wrong, so a write that carries an end-user JWT
    -- (platform admins included) is refused; writes with no JWT (migrations, SQL editor, service role) pass.
    if (old.approved is distinct from new.approved
        or old.application_complete is distinct from new.application_complete)
       and (select auth.uid()) is not null then
        raise exception 'approved and application_complete follow community memberships'
            using errcode = '42501';
    end if;

    if (old.is_admin is distinct from new.is_admin
        or old.is_banned is distinct from new.is_banned
        or old.primary_community_id is distinct from new.primary_community_id
        or old.max_owned_communities is distinct from new.max_owned_communities) then
        if (select auth.uid()) is not null
           and not coalesce((select p.is_admin from public.profiles p where p.id = (select auth.uid())), false) then
            raise exception 'Only admins can modify is_admin, is_banned, primary_community_id or max_owned_communities fields';
        end if;
    end if;
    return new;
end;
$function$;


-- ============================================================================================
-- BLOCK 5: the two legacy bridges (20261017_0001 [call] 1d.4-1d.6)
-- ============================================================================================
drop trigger if exists legacy_application_to_membership on public.profiles;
drop trigger if exists a_sync_legacy_approval_to_membership on public.profiles;
drop function if exists public.legacy_application_to_membership();
drop function if exists public.sync_legacy_approval_to_membership();


-- ============================================================================================
-- BLOCK 6: public.admin_reject_pending_user(uuid)   body unchanged (md5 f5366ee20a4fa51908b3e8173cb1e400)
-- ============================================================================================
revoke execute on function public.admin_reject_pending_user(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 7 (optional, D-S3): the installed build's default-community wrappers that no community build calls
-- ============================================================================================
revoke execute on function public.get_leaderboard(text, integer) from public, anon, authenticated;
revoke execute on function public.get_leaderboard(date, date) from public, anon, authenticated;
revoke execute on function public.send_broadcast_notifications(text, text, text, boolean) from public, anon, authenticated;
````

---

## File C — `supabase/migrations/20261019_0061_drop_invite_codes.sql` (5b, NOT APPLIED, SQL editor)

````sql
-- 20261019_0061_drop_invite_codes.sql
--
-- NOT APPLIED. GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (A5 point 2). SQL EDITOR (owner), as ONE transaction: delete_user_account's body deletes
-- from auth.users and storage.objects and the file drops a table, which the Supabase MCP declines.
-- Phase 5b of the multi-community design (§4 "Phase 5": invite_codes and its policies / triggers dropped in a
-- SQL-editor file).
--
-- What it does.
--   0. (before the transaction, read only) the rollback capture: pg_get_functiondef of the four functions,
--      the table's columns, constraints, indexes, policies and triggers, saved to
--      supabase/migrations/20261019_0061a_invite_codes_rollback_capture.sql (DDL only, committed, never
--      applied); the 62 rows exported to a CSV kept OFF the repository (they hold user ids; the repo is public).
--   1. delete_user_account: its one statement on invite_codes (STEP 7, live line 269) goes, so account deletion
--      keeps working once the table is gone (App Store 5.1.1(v)). Derived from the live definition (D-S1).
--   2. drop table public.invite_codes (its four policies, two triggers, three foreign keys, the unique index
--      and the self reference go with it; no other table references it).
--   3. the four functions that existed only for it: validate_invite_code (EXECUTE for anon today: it tells
--      anyone whether a code exists), mark_invite_code_used, guard_invite_code_client_update,
--      handle_invite_code_used.
--
-- What old clients see. Nothing reachable: the installed build has no screen that reads or writes the table
-- (its AdminInviteView, InvitationWorkflowView and SignupInviteCodeView are never presented), and no
-- community build references it after iOS Tasks 1-3. Sign-up never used it (public sign-up,
-- create_signup_profile). Community invites (community_invites) are unaffected.
--
-- Verification. Dry run (now, owner, SQL editor): NOT this file. Paste only
-- supabase/dryruns/20261019_0061_drop_invite_codes.dryrun.sql, verbatim (it holds blocks 1-3 inside one
-- begin; ... rollback;, the probe helpers without their commit;, and invite_codes_dropped, account_deletion and
-- short as savepoints), after C0 and the CSV export; then the not-applied check in a new tab. Outcomes: not yet
-- run. At the gate: this file as one transaction, then invite_codes_dropped, short and account_deletion.
--
-- Rollback. Recreate the table, its constraints, policies and triggers and the four functions from
-- 20261019_0061a; load the CSV; re-run delete_user_account from 20261017_0004:214-499.

begin;

-- ============================================================================================
-- BLOCK 1: public.delete_user_account(uuid)   live md5 135aca113be1ebf5281c03c288ee32c6 (20261017_0004:214-496)
-- Removed, exactly once: "    delete from public.invite_codes where created_by = p_user_id;" (STEP 7).
-- Deployed md5 must be bd886e739d25dbe7497ff6b21c5aa248.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.delete_user_account(uuid)'::regprocedure;
  v_cut constant text := E'    delete from public.invite_codes where created_by = p_user_id;\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> '135aca113be1ebf5281c03c288ee32c6' then
    raise exception 'delete_user_account is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'delete_user_account: the invite_codes statement was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'bd886e739d25dbe7497ff6b21c5aa248' then
    raise exception 'delete_user_account: unexpected body after the edit';
  end if;
end
$derive$;

-- ============================================================================================
-- BLOCK 2: the table
-- ============================================================================================
drop table public.invite_codes;

-- ============================================================================================
-- BLOCK 3: the functions that existed only for it
-- ============================================================================================
drop function if exists public.validate_invite_code(text);
drop function if exists public.mark_invite_code_used(text, text, text, text);
drop function if exists public.guard_invite_code_client_update();
drop function if exists public.handle_invite_code_used();

-- the guard: no function body may still name the table
do $check$
begin
  if exists (select 1 from pg_catalog.pg_proc p
              where p.pronamespace = 'public'::regnamespace and position('invite_codes' in p.prosrc) > 0) then
    raise exception 'a public function still names invite_codes';
  end if;
end
$check$;

commit;
````

**C0, the capture** (read only, run by the orchestrator through the MCP just before the owner's run; output written to `20261019_0061a_invite_codes_rollback_capture.sql`, header "ROLLBACK CAPTURE, never applied"):

```sql
select pg_get_functiondef(p.oid) from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('validate_invite_code', 'mark_invite_code_used', 'guard_invite_code_client_update', 'handle_invite_code_used');
select column_name, data_type, is_nullable, column_default from information_schema.columns
 where table_schema = 'public' and table_name = 'invite_codes' order by ordinal_position;
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.invite_codes'::regclass;
select indexdef from pg_indexes where schemaname = 'public' and tablename = 'invite_codes';
select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.invite_codes'::regclass and not tgisinternal;
select policyname, cmd, roles, qual, with_check from pg_policies where schemaname = 'public' and tablename = 'invite_codes';
select grantee, string_agg(privilege_type, ',') from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'invite_codes' group by grantee;
```

---

## File D — `supabase/migrations/20261019_0062_geocoding_cache_direct_access_revoked.sql` (5b, NOT APPLIED)

````sql
-- 20261019_0062_geocoding_cache_direct_access_revoked.sql
--
-- NOT APPLIED. GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (A5 point 2) AND that every build in use contains the Phase 5a client (its ride-cost lookup
-- calls get_geocoding_multiplier / put_geocoding_multiplier, 20261019_0050). Phase 5b (§4 "Phase 5":
-- geocoding_cache read through a definer lookup, direct SELECT revoked; D16).
--
-- What it does. Block 1 revokes every table privilege on public.geocoding_cache from anon and authenticated (SELECT,
-- and also INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER: the 5a client writes through
-- put_geocoding_multiplier, and an upsert without SELECT fails anyway; D-S6). The three policies stay and are
-- inert without the grants (removing them is a DROP POLICY, SQL-editor work for a later cleanup). The two
-- definer functions keep working (they run as the table owner). Block 2 clears the placemark data that builds
-- without the 5a client wrote after 20261019_0050 block 3 (they upsert it directly until block 1 closes the table).
--
-- What old clients see. A build without the 5a client (the installed build, Phase 1-4 builds): its
-- availability probe (select id limit 1) fails with 42501. It does not treat 42501 as a missing table
-- (main:NaarsCars/Core/Utilities/GeocodingCacheService.swift:173-198, :200-207 match only 42P01 or a
-- "does not exist" message), so it never turns caching off: every ride end that reaches the lookup sends one
-- failing probe before the read and another before the write, then reverse-geocodes on the device (2 s timeout
-- per end, the same multiplier rules); the estimate is still computed and saved. Nothing else changes for it.
--
-- Apply. Supabase MCP apply_migration, one call per block. Verification: dry run (now) through
-- supabase/dryruns/20261019_0062_geocoding_cache_direct_access_revoked.dryrun.sql (geocoding_revoked,
-- geocoding_lookup and short as savepoints), then the not-applied check; at the gate, the three probes after
-- the calls. Outcomes: not yet run. Block 2 cannot be undone (the multipliers are untouched).
-- Rollback. grant select, insert, update, delete, truncate, references, trigger on table public.geocoding_cache
-- to anon, authenticated; (the grants read in the plan's P2).

-- BLOCK 1
revoke all privileges on table public.geocoding_cache from anon, authenticated;

-- BLOCK 2: placemarks written by builds without the 5a client since 20261019_0050 block 3
update public.geocoding_cache set placemark_data = null where placemark_data is not null;
````

---

## File E — `supabase/migrations/20261019_0063_private_image_buckets.sql` (5b, NOT APPLIED, SQL editor)

````sql
-- 20261019_0063_private_image_buckets.sql
--
-- NOT APPLIED. GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (A5 point 2) AND that every build in use contains the Phase 5a client (it downloads these
-- buckets through signed URLs). SQL EDITOR (owner), as ONE transaction: DROP POLICY and the write to
-- storage.buckets are declined by the Supabase MCP. Phase 5b (§4 "Phase 5": private storage buckets with
-- signed URLs for message-images, group-images, town-hall-images, review-images; D16).
--
-- What it does.
--   1. storage.buckets.public = false for the four buckets: the public route
--      /storage/v1/object/public/<bucket>/... stops serving them (400). Avatars stay public.
--   2. Their public SELECT policies on storage.objects are dropped (seven, listed in the plan's P2), and four
--      SELECT policies take their place. They decide who may create a signed URL and download an object:
--        message-images, group-images (path <conversation id>/<file>): the uploader, or a participant of that
--        conversation (any conversation_participants row of the caller, including one who left: they still
--        read the thread within their window);
--        town-hall-images (path <file>): the uploader, or anyone (guests included) who can read a Town Hall post
--        or a review whose image_url names the object (the posts' and reviews' own policies decide, so a guest
--        sees only public communities' photos);
--        review-images (path <UUID>.jpg, a fresh UUID per upload, not the review id: ReviewService.swift:60,
--        :196): the uploader, or anyone who can read a review, or a Town Hall post, whose image_url names the
--        object (no live review carries an image on 2026-10-19; the 5 objects in the bucket are orphans, readable
--        after this file by their uploader only). The post clause covers the shape
--        ReviewService.createTownHallPostForReview builds (:237-257; no caller today, 0 such posts live).
--      The uploader clause also keeps the group and review uploads working: they use upsert, which needs
--      SELECT on the object.
--   3. (optional, D-1, only with iOS Task 8 shipped) audio-messages: private, the participant policy.
--   INSERT, UPDATE and DELETE policies are unchanged.
--
-- What old clients see. A build without the 5a client (the installed build, Phase 1-4 builds): every
-- message photo, group photo, Town Hall photo and review photo fails to load (its image placeholder or
-- error view); uploads still succeed, and the photos it sends are readable by the 5a client. With block 3,
-- its voice notes fail to play. Avatars are unaffected.
--
-- Verification. Dry run (now, owner, SQL editor): NOT this file. Paste only
-- supabase/dryruns/20261019_0063_private_image_buckets.dryrun.sql, verbatim (blocks 1-3 inside one begin; ...
-- rollback;, the probe helpers without their commit;, storage_private and short as savepoints); then the
-- not-applied check in a new tab, which must show buckets_all_public = true. At the gate: this file as one
-- transaction, storage_private after the commit, then iOS plan Task 12 Step 4 (the two-simulator check and the
-- 400 from the public route). Outcomes: not yet run.
--
-- Rollback. update storage.buckets set public = true where id in (...); drop the four new policies; recreate
-- the seven dropped ones from the plan's P2 (each "for select to public using (bucket_id = '<bucket>')", and
-- "Message image read" with its EXISTS clause).

begin;

-- BLOCK 1: the buckets
update storage.buckets set public = false
 where id in ('message-images', 'group-images', 'town-hall-images', 'review-images');

-- BLOCK 2: the public SELECT policies
drop policy if exists "Allow public read access on message-images" on storage.objects;
drop policy if exists "Message image read" on storage.objects;
drop policy if exists "Allow public read access on group-images" on storage.objects;
drop policy if exists "Anyone can view group images" on storage.objects;
drop policy if exists "Allow public read access on town-hall-images" on storage.objects;
drop policy if exists "Town hall public read" on storage.objects;
drop policy if exists "Allow public access to review images" on storage.objects;

-- BLOCK 3: who may read each object
create policy message_images_read_participants on storage.objects
  for select to authenticated
  using (
    bucket_id = 'message-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.conversation_participants cp
                  where cp.user_id = (select auth.uid())
                    and cp.conversation_id::text = lower((storage.foldername(storage.objects.name))[1]))
    )
  );

create policy group_images_read_participants on storage.objects
  for select to authenticated
  using (
    bucket_id = 'group-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.conversation_participants cp
                  where cp.user_id = (select auth.uid())
                    and cp.conversation_id::text = lower((storage.foldername(storage.objects.name))[1]))
    )
  );

create policy town_hall_images_read_visible on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'town-hall-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.town_hall_posts p
                  where p.image_url is not null
                    and position(('/town-hall-images/' || storage.objects.name) in p.image_url) > 0)
      or exists (select 1 from public.reviews r
                  where r.image_url is not null
                    and position(('/town-hall-images/' || storage.objects.name) in r.image_url) > 0)
    )
  );

create policy review_images_read_visible on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'review-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.reviews r
                  where r.image_url is not null
                    and position(('/review-images/' || storage.objects.name) in r.image_url) > 0)
      or exists (select 1 from public.town_hall_posts p
                  where p.image_url is not null
                    and position(('/review-images/' || storage.objects.name) in p.image_url) > 0)
    )
  );

-- BLOCK 4 (optional, D-1; only with iOS Task 8 in every build in use)
-- update storage.buckets set public = false where id = 'audio-messages';
-- drop policy if exists "Allow public read access on audio-messages" on storage.objects;
-- drop policy if exists "Anyone can view audio messages" on storage.objects;
-- create policy audio_messages_read_participants on storage.objects
--   for select to authenticated
--   using (
--     bucket_id = 'audio-messages'
--     and (
--       owner_id = (select auth.uid())::text
--       or exists (select 1 from public.conversation_participants cp
--                   where cp.user_id = (select auth.uid())
--                     and cp.conversation_id::text = lower((storage.foldername(storage.objects.name))[1]))
--     )
--   );

commit;
````

---

## Probe additions — `supabase/probes/communities_probe.sql`

Five edits to the file. **Line anchors** (`:18-30`, `:72-85`, `:94-97`, `:100-363`, `:366-461`, `:399`, `:723-819`, `:1848-1914`, `:1958`) were read at `4956682`; Phase 4's SQL plan adds blocks to the same file before this phase runs, so the orchestrator re-finds each anchor by its text (the banner, the quoted statement, the block's `v_probe` name) and does not edit by line number.

**(1) Header, "WHEN TO RUN WHAT" (`:18-30`):** add after the Phase 3 bullet:

```text
--   * Phase 5. geocoding_lookup needs 20261019_0050 (5a). The 5b blocks need their file live and fail with
--     "File <X> is not live" otherwise: legacy_retired (20261019_0060), invite_codes_dropped (0061),
--     geocoding_revoked (0062), storage_private (0063; it inserts rows into storage.objects inside its rolled-back
--     transaction, so SQL editor (owner) if the MCP declines it). After 0060, legacy_bridges prints
--     'PROBE legacy_bridges SKIPPED' and legacy_retired covers the same ground; short gives its two probe
--     accounts their default membership directly instead of through the retired approve bridge; broadcast_cap
--     expects 42501 from send_broadcast_notifications once 0060 block 7 has revoked it. A 5b dry run never pastes
--     this file: it runs the committed script in supabase/dryruns/ (no commit; probes as savepoints).
```

and extend the RPC list (`:72-85`) with: `Phase 5 adds: get_geocoding_multiplier(p_location_key), put_geocoding_multiplier(p_location_key, p_latitude, p_longitude, p_multiplier).`

**(2) HELPERS:** insert before the `commit;` at `:363`:

```sql
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
```

**(3) Edits to three existing blocks** (`short`, `legacy_bridges`, `broadcast_cap`).

`short` (`:366-461`), after `update public.profiles set approved = true where id in (v_claimer, v_padmin);` (`:399`) and before the role update:

```sql
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
```

`legacy_bridges` (`:723-819`), right after `perform pg_temp.probe_require(v_probe);`:

```sql
  if not exists (select 1 from pg_catalog.pg_trigger where not tgisinternal and tgname = 'legacy_application_to_membership') then
    raise notice 'PROBE % SKIPPED: the legacy bridges are retired (20261019_0060); legacy_retired covers this', v_probe;
    return;
  end if;
```

`broadcast_cap` (`:1848-1914`): File B block 7 (D-S3) revokes EXECUTE on `send_broadcast_notifications` from `authenticated`, so the block's wrapper section (`:1895-1909`, from the comment `-- the installed admin build's wrapper posts into the default community` through the P0001 check) would get 42501 where it expects success and then P0001, and the full probe run at the gate would fail. Wrap that section, unchanged, in a privilege test:

```sql
  if has_function_privilege('authenticated', 'public.send_broadcast_notifications(text, text, text, boolean)', 'execute') then
    -- <the existing wrapper section, unchanged: the v_existing count, the loop and the P0001 check>
  else
    -- File B block 7 (20261019_0060, D-S3) closed the installed admin build's wrapper to clients
    j := pg_temp.probe_call(v_admin, $q$public.send_broadcast_notifications('Probe wrapper closed', 'communities probe', 'broadcast', false)$q$);
    perform pg_temp.probe_ok(v_probe, 'the wrapper is closed to clients after File B block 7: ' || j::text,
      coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = '42501');
  end if;
```

**(4) Blocks:** insert before the final `select 'PROBE ALL OK' as probe;` (`:1958`).

```sql
-- =============================================================================================================
-- geocoding_lookup (Phase 5a, 20261019_0050): an active member writes and reads one multiplier through the two
-- definer functions and gets back only a number; an unapproved or banned account gets null and cannot write;
-- anon cannot call either; malformed keys, keys that do not match the coordinates and out-of-range multipliers
-- are refused; a row older than 24 hours is a miss and a new write refreshes it; no placemark is stored.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'geocoding_lookup';
  v_member uuid := pg_temp.probe_subject('member');
  u1 uuid := pg_temp.u(1);  u2 uuid := pg_temp.u(2);
  v_key constant text := '89.987_-179.987';     -- no real place: the edge of the map
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'a');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'the probe key is unused', not exists (select 1 from public.geocoding_cache where location_key = v_key));

  j := pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.2)', v_key));
  perform pg_temp.probe_ok(v_probe, 'an active member writes a multiplier: ' || j::text, j = 'true'::jsonb);
  perform pg_temp.probe_ok(v_probe, 'the row holds the multiplier, no placemark, a fresh updated_at',
    exists (select 1 from public.geocoding_cache where location_key = v_key and multiplier = 1.2
              and placemark_data is null and updated_at > now() - interval '1 minute'));

  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'the member reads back only a number: ' || j::text,
    jsonb_typeof(j) = 'number' and (j #>> '{}')::numeric = 1.2);

  j := pg_temp.probe_call(u1, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'an unapproved account reads null: ' || j::text, j = 'null'::jsonb);
  j := pg_temp.probe_call(u2, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'a banned account reads null: ' || j::text, j = 'null'::jsonb);
  j := pg_temp.probe_call(u1, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.5)', v_key));
  perform pg_temp.probe_ok(v_probe, 'an unapproved account cannot write: ' || j::text,
    j = 'false'::jsonb and (select multiplier from public.geocoding_cache where location_key = v_key) = 1.2);

  j := pg_temp.probe_call(null, format('public.get_geocoding_multiplier(%L)', v_key), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call the lookup: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_call(null, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.1)', v_key), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call the write: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');

  foreach j in array array[
    pg_temp.probe_call(v_member, $q$public.put_geocoding_multiplier('1.2_3.4', 1.2, 3.4, 1.1)$q$),               -- malformed key
    pg_temp.probe_call(v_member, $q$public.put_geocoding_multiplier('x; drop', 1.2, 3.4, 1.1)$q$),               -- malformed key
    pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 10.0, 10.0, 1.1)', v_key)),     -- key does not match
    pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 3.0)', v_key)),  -- out of range
    pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 0.5)', v_key))]  -- out of range
  loop
    perform pg_temp.probe_ok(v_probe, 'a malformed or out-of-range write is refused: ' || j::text, j = 'false'::jsonb);
  end loop;
  perform pg_temp.probe_ok(v_probe, 'and the row is unchanged',
    (select multiplier from public.geocoding_cache where location_key = v_key) = 1.2);
  j := pg_temp.probe_call(v_member, $q$public.get_geocoding_multiplier('not a key')$q$);
  perform pg_temp.probe_ok(v_probe, 'a malformed lookup answers null: ' || j::text, j = 'null'::jsonb);

  perform set_config('request.jwt.claims', '', true);
  update public.geocoding_cache set created_at = now() - interval '25 hours', updated_at = now() - interval '25 hours'
   where location_key = v_key;
  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'a row older than 24 hours is a miss: ' || j::text, j = 'null'::jsonb);
  j := pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.987, -179.987, 1.1)', v_key));
  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'a new write refreshes it: ' || j::text, (j #>> '{}')::numeric = 1.1);

  perform pg_temp.probe_ok(v_probe, 'both functions are SECURITY DEFINER with an empty search_path and not callable by anon',
    (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
       from pg_catalog.pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('get_geocoding_multiplier', 'put_geocoding_multiplier'))
    and not has_function_privilege('anon', 'public.get_geocoding_multiplier(text)', 'execute')
    and not has_function_privilege('anon', 'public.put_geocoding_multiplier(text, numeric, numeric, numeric)', 'execute'));

  if has_table_privilege('authenticated', 'public.geocoding_cache', 'select') then
    -- before 20261019_0062 the installed build's direct read still works
    perform pg_temp.probe_ok(v_probe, 'before File D the direct table read still works for a member',
      pg_temp.probe_count(v_member, format('select 1 from public.geocoding_cache where location_key = %L', v_key)) = 1);
  end if;

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE geocoding_lookup OK' as probe;


-- =============================================================================================================
-- legacy_retired (Phase 5b, 20261019_0060): the bridges are gone; the installed build's application UPDATE and
-- approve raise and change nothing, for platform admins too; a member's own flag write raises; the RPC approve
-- still works; admin_reject_pending_user is closed to clients; an approved account with no membership row cannot
-- post while a member still posts without naming a community; answers given to the default community stay on
-- the membership row and are not copied into profiles.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'legacy_retired';
  d uuid;
  v_admin  uuid := pg_temp.probe_subject('platform_admin');
  v_member uuid := pg_temp.probe_subject('member');
  u3 uuid := pg_temp.u(3);  u6 uuid := pg_temp.u(6);  u8 uuid := pg_temp.u(8);
  u10 uuid := pg_temp.u(10);  u13 uuid := pg_temp.u(13);  u15 uuid := pg_temp.u(15);
  v_code text;
  v_ride uuid;
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'bridges');
  perform pg_temp.probe_world();
  d := public.default_community_id();

  perform pg_temp.probe_ok(v_probe, 'the bridge functions are gone',
    not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace
                 and proname in ('legacy_application_to_membership', 'sync_legacy_approval_to_membership')));
  perform pg_temp.probe_ok(v_probe, 'the four edited bodies are the expected ones',
    (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.fill_request_community()'::regprocedure) = '9d4cfb03912a7c4a874cffae239ee605'
    and (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.redeem_community_invite(text, text, text)'::regprocedure) = '2ec0702dc3a4d400ca2599d0ebb15693'
    and (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.request_to_join_community(uuid, text, text)'::regprocedure) = 'af9a2f5c560d2d74f35ab979e2f3856c'
    and (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.protect_admin_fields()'::regprocedure) = 'd963a013278b5ace77565b8397683bf2');

  -- the installed build's application form
  j := pg_temp.probe_run(u10, format($q$with x as (update public.profiles
        set heard_about = 'Probe heard', join_reason = 'Probe reason', application_complete = true, application_submitted_at = now()
        where id = %L returning 1) select to_jsonb(count(*)) from x$q$, u10));
  perform pg_temp.probe_ok(v_probe, 'the old application UPDATE raises 42501: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  perform pg_temp.probe_ok(v_probe, 'and creates no membership; the flag stays false',
    not exists (select 1 from public.community_members where user_id = u10)
    and not (select application_complete from public.profiles where id = u10));

  j := pg_temp.probe_run(u3, format($q$with x as (update public.profiles set application_complete = false where id = %L returning 1)
                                     select to_jsonb(count(*)) from x$q$, u3));
  perform pg_temp.probe_ok(v_probe, 'a member''s own application_complete write raises: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  -- the installed admin build's approve
  j := pg_temp.probe_run(v_admin, format($q$with x as (update public.profiles set approved = true where id = %L returning 1)
                                          select to_jsonb(count(*)) from x$q$, u8));
  perform pg_temp.probe_ok(v_probe, 'a platform admin''s direct approve raises 42501: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  perform pg_temp.probe_ok(v_probe, 'and the applicant is still pending and not approved',
    exists (select 1 from public.community_members where community_id = d and user_id = u8 and status = 'pending')
    and not (select approved from public.profiles where id = u8));

  j := pg_temp.probe_call(v_admin, format('public.approve_community_member(%L::uuid, %L::uuid)', d, u8));
  perform pg_temp.probe_ok(v_probe, 'approve_community_member still works: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the mirror approves and one welcome is sent',
    exists (select 1 from public.community_members where community_id = d and user_id = u8 and status = 'active')
    and (select approved from public.profiles where id = u8)
    and (select count(*) from public.notifications where user_id = u8 and type = 'user_approved') = 1);

  j := pg_temp.probe_call(v_admin, format('public.admin_reject_pending_user(%L::uuid)', u15));
  perform pg_temp.probe_ok(v_probe, 'admin_reject_pending_user is closed to clients: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and coalesce(j ->> 'sqlstate', '') = '42501');
  perform pg_temp.probe_ok(v_probe, 'and the applicant and their account remain',
    exists (select 1 from public.profiles where id = u15)
    and exists (select 1 from public.community_members where community_id = d and user_id = u15 and status = 'pending'));

  -- no default fallback: an approved account with no membership row (a maintenance write, no JWT). The insert
  -- runs as the table owner so RLS cannot refuse it first: only the fill trigger decides (before File B it
  -- would have filled the default community).
  perform set_config('request.jwt.claims', '', true);
  update public.profiles set approved = true where id = u13;
  j := pg_temp.probe_run(null, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination)
       values (%L, current_date + 1, '10:00', 'Probe pickup', 'Probe destination') returning to_jsonb(community_id)$q$, u13), 'owner');
  perform pg_temp.probe_ok(v_probe, 'the fill trigger no longer places such an account in the default community: ' || j::text,
    pg_temp.probe_refused(j) and coalesce(j ->> 'error', '') like '%Choose a community%');
  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.rides (user_id, date, "time", pickup, destination)
       values (%L, current_date + 1, '10:00', 'Probe pickup', 'Probe destination') returning to_jsonb(id)$q$, v_member));
  perform pg_temp.probe_ok(v_probe, 'a member still posts without naming a community: ' || j::text, not pg_temp.probe_refused(j));
  v_ride := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'into one of their live communities',
    (select community_id from public.rides where id = v_ride) = any (pg_temp.probe_live_communities(v_member)));

  -- answers stay on the membership row
  j := pg_temp.probe_call(u10, format('public.request_to_join_community(%L::uuid, %L, %L)', d, 'Probe heard', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'asking to join the default community works: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the answers are on the membership row and not on the profile',
    exists (select 1 from public.community_members where community_id = d and user_id = u10 and heard_about = 'Probe heard')
    and (select heard_about is null and join_reason is null from public.profiles where id = u10));

  j := pg_temp.probe_call(v_admin, format($q$public.create_community_invite(%L::uuid, 5, now() + interval '1 day')$q$, d));
  v_code := j ->> 'code';
  perform pg_temp.probe_ok(v_probe, 'a platform admin makes a default-community code: ' || j::text, v_code is not null);
  j := pg_temp.probe_call(u6, format('public.redeem_community_invite(%L, %L, %L)', v_code, 'Probe heard 6', 'Probe reason 6'));
  perform pg_temp.probe_ok(v_probe, 'redeeming it works: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and copies nothing into the profile',
    exists (select 1 from public.community_members where community_id = d and user_id = u6 and heard_about = 'Probe heard 6')
    and (select heard_about is null and join_reason is null from public.profiles where id = u6));

  if not has_function_privilege('authenticated', 'public.send_broadcast_notifications(text, text, text, boolean)', 'execute') then
    perform pg_temp.probe_ok(v_probe, 'block 7 applied: the legacy leaderboards are closed too',
      not has_function_privilege('authenticated', 'public.get_leaderboard(text, integer)', 'execute')
      and not has_function_privilege('authenticated', 'public.get_leaderboard(date, date)', 'execute'));
  end if;

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE legacy_retired OK' as probe;


-- =============================================================================================================
-- invite_codes_dropped (Phase 5b, 20261019_0061): the table and its four functions are gone, delete_user_account is
-- the expected body and still deletes an account, and no public function names the table.
-- Run account_deletion and short after it as well.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'invite_codes_dropped';
  u1 uuid := pg_temp.u(1);
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'invite_codes');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'the four invite-code functions are gone',
    not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace
                 and proname in ('validate_invite_code', 'mark_invite_code_used', 'guard_invite_code_client_update', 'handle_invite_code_used')));
  perform pg_temp.probe_ok(v_probe, 'no public function names invite_codes',
    not exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and position('invite_codes' in prosrc) > 0));
  perform pg_temp.probe_ok(v_probe, 'delete_user_account is the expected body',
    (select md5(prosrc) from pg_catalog.pg_proc where oid = 'public.delete_user_account(uuid)'::regprocedure) = 'bd886e739d25dbe7497ff6b21c5aa248');
  j := pg_temp.probe_call(u1, format('public.delete_user_account(%L::uuid)', u1));
  perform pg_temp.probe_ok(v_probe, 'an account still deletes itself: ' || j::text, not pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'and is gone from profiles and auth.users',
    not exists (select 1 from public.profiles where id = u1) and not exists (select 1 from auth.users where id = u1));
  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE invite_codes_dropped OK' as probe;


-- =============================================================================================================
-- geocoding_revoked (Phase 5b, 20261019_0062): no client role can read or write geocoding_cache directly; the two
-- definer functions still work for an active member.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'geocoding_revoked';
  v_member uuid := pg_temp.probe_subject('member');
  v_key constant text := '89.986_-179.986';
  v_priv text;
  j jsonb;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'geocoding');
  foreach v_priv in array array['select', 'insert', 'update', 'delete'] loop
    perform pg_temp.probe_ok(v_probe, format('no %s privilege for anon or authenticated', v_priv),
      not has_table_privilege('anon', 'public.geocoding_cache', v_priv)
      and not has_table_privilege('authenticated', 'public.geocoding_cache', v_priv));
  end loop;
  j := pg_temp.probe_run(v_member, 'select to_jsonb(count(*)) from public.geocoding_cache');
  perform pg_temp.probe_ok(v_probe, 'a member''s direct read raises 42501: ' || j::text, coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_run(null, 'select to_jsonb(count(*)) from public.geocoding_cache', 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon''s direct read raises 42501: ' || j::text, coalesce(j ->> 'sqlstate', '') = '42501');
  j := pg_temp.probe_run(v_member, format(
    $q$insert into public.geocoding_cache (latitude, longitude, location_key, multiplier) values (89.986, -179.986, %L, 1.5)
       returning to_jsonb(id)$q$, v_key));
  perform pg_temp.probe_ok(v_probe, 'a member''s direct write raises: ' || j::text, coalesce(j ->> 'raised', '') = 'true');
  j := pg_temp.probe_call(v_member, format('public.put_geocoding_multiplier(%L, 89.986, -179.986, 1.2)', v_key));
  perform pg_temp.probe_ok(v_probe, 'the definer write still works: ' || j::text, j = 'true'::jsonb);
  j := pg_temp.probe_call(v_member, format('public.get_geocoding_multiplier(%L)', v_key));
  perform pg_temp.probe_ok(v_probe, 'the definer lookup still works: ' || j::text, (j #>> '{}')::numeric = 1.2);
  perform pg_temp.probe_ok(v_probe, 'block 2: no placemark data is left',
    not exists (select 1 from public.geocoding_cache where placemark_data is not null));
  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE geocoding_revoked OK' as probe;


-- =============================================================================================================
-- storage_private (Phase 5b, 20261019_0063): the four buckets are private and avatars public; a message or group
-- photo is readable by the thread's participants and its uploader only; a Town Hall photo by whoever can read a
-- post that shows it (guests only for public communities); a review photo by whoever can read the review.
-- Object rows are inserted as the table owner and rolled back (no file is uploaded).
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'storage_private';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u7 uuid := pg_temp.u(7);
  u11 uuid := pg_temp.u(11);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);  c2 uuid := pg_temp.c(2);
  v_conv constant uuid := '00000000-0000-4000-e000-000000000501'::uuid;
  v_base constant text := 'https://probe.invalid/storage/v1/object/public/';
  v_msg text;  v_grp text;  v_th_public constant text := 'probe-th-public.jpg';  v_th_private constant text := 'probe-th-private.jpg';
  v_rev text;
  v_post uuid;
  v_sql text;
begin
  perform pg_temp.probe_require_phase5(v_probe, 'storage');
  perform pg_temp.probe_world();
  perform pg_temp.probe_ok(v_probe, 'the four buckets are private and avatars public',
    not exists (select 1 from storage.buckets where id in ('message-images', 'group-images', 'town-hall-images', 'review-images') and public)
    and exists (select 1 from storage.buckets where id = 'avatars' and public));
  perform pg_temp.probe_ok(v_probe, 'no SELECT policy on those buckets is a bare bucket test any more',
    not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and cmd = 'SELECT'
                 and qual in ('(bucket_id = ''message-images''::text)', '(bucket_id = ''group-images''::text)',
                              '(bucket_id = ''town-hall-images''::text)', '(bucket_id = ''review-images''::text)')));

  -- a thread between u3 and u7 (C1 members), photos uploaded by u3 and by u11 (not a participant)
  perform set_config('request.jwt.claims', '', true);
  insert into public.conversations (id, created_by) values (v_conv, u3);
  insert into public.conversation_participants (conversation_id, user_id) values (v_conv, u3), (v_conv, u7)
    on conflict do nothing;   -- in case a trigger already added the creator
  v_msg := upper(v_conv::text) || '/probe-msg.jpg';
  v_grp := upper(v_conv::text) || '/avatar_probe.jpg';
  perform pg_temp.probe_storage_object('message-images', v_msg, u3);
  perform pg_temp.probe_storage_object('group-images', v_grp, u3);
  perform pg_temp.probe_storage_object('message-images', upper(v_conv::text) || '/probe-other.jpg', u11);

  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'message-images', v_msg);
  perform pg_temp.probe_ok(v_probe, 'a participant reads the message photo', pg_temp.probe_count(u7, v_sql) = 1);
  perform pg_temp.probe_ok(v_probe, 'a non-participant does not', pg_temp.probe_count(u4, v_sql) = 0);
  perform pg_temp.probe_ok(v_probe, 'anon does not', pg_temp.probe_count(null, v_sql, 'anon') = 0);
  perform pg_temp.probe_ok(v_probe, 'an uploader who is not a participant reads only their own object',
    pg_temp.probe_count(u11, format('select 1 from storage.objects where bucket_id = %L and name like %L', 'message-images', upper(v_conv::text) || '/%')) = 1);
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'group-images', v_grp);
  perform pg_temp.probe_ok(v_probe, 'a participant reads the group photo; a non-participant and anon do not',
    pg_temp.probe_count(u7, v_sql) = 1 and pg_temp.probe_count(u4, v_sql) = 0 and pg_temp.probe_count(null, v_sql, 'anon') = 0);

  -- Town Hall: one photo on a post in C2 (public), one on a post in C1 (private)
  perform pg_temp.probe_storage_object('town-hall-images', v_th_public, u12);
  perform pg_temp.probe_storage_object('town-hall-images', v_th_private, u3);
  v_post := pg_temp.probe_post(1, u12, c2);
  update public.town_hall_posts set image_url = v_base || 'town-hall-images/' || v_th_public where id = v_post;
  v_post := pg_temp.probe_post(2, u3, c1);
  update public.town_hall_posts set image_url = v_base || 'town-hall-images/' || v_th_private where id = v_post;
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'town-hall-images', v_th_public);
  perform pg_temp.probe_ok(v_probe, 'anon reads a public community''s Town Hall photo', pg_temp.probe_count(null, v_sql, 'anon') = 1);
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'town-hall-images', v_th_private);
  perform pg_temp.probe_ok(v_probe, 'a private community''s Town Hall photo: its member yes, anon and a non-member no',
    pg_temp.probe_count(u7, v_sql) = 1 and pg_temp.probe_count(null, v_sql, 'anon') = 0 and pg_temp.probe_count(u12, v_sql) = 0);

  -- review photo on r(1) (u7's C1 ride, reviewed by u7, helped by u3)
  -- named like ReviewService's uploads: "<UUID>.jpg" (an uppercase uuid; the app uses a fresh UUID, not the review id,
  -- ReviewService.swift:60, :196; the policy matches by image_url, so the name's origin does not matter), URL with ?t=
  v_rev := upper((select v.id from public.reviews v where v.ride_id = pg_temp.r(1) limit 1)::text) || '.jpg';
  perform pg_temp.probe_storage_object('review-images', v_rev, u7);
  update public.reviews set image_url = v_base || 'review-images/' || v_rev || '?t=1' where ride_id = pg_temp.r(1);
  v_sql := format('select 1 from storage.objects where bucket_id = %L and name = %L', 'review-images', v_rev);
  perform pg_temp.probe_ok(v_probe, 'a review photo: the reviewer and a C1 member yes, a non-member and anon no',
    pg_temp.probe_count(u7, v_sql) = 1 and pg_temp.probe_count(u3, v_sql) = 1
    and pg_temp.probe_count(u12, v_sql) = 0 and pg_temp.probe_count(null, v_sql, 'anon') = 0);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE storage_private OK' as probe;
```

---

## Deviations and choices the owner can veto

- **D-S1. Three bodies are derived from the live definition** (File B blocks 2-3, File C block 1). `redeem_community_invite` (5,204 characters), `request_to_join_community` (3,523) and `delete_user_account` (14,406) each lose one passage. Instead of a hand transcription, each block checks the live md5, takes `pg_get_functiondef`, removes the passage after checking it occurs exactly once, executes the result and checks the md5 of the new body against a value computed on 2026-10-19. A body that drifted before the gate makes the block raise rather than apply. The committed file therefore holds the edit, not the full body; the full pre-edit body is in the cited source file, and `pg_get_functiondef` after the apply gives the new one. To have full bodies in the files instead, the orchestrator pastes `pg_get_functiondef` output after the dry run and replaces each `DO` block with it, keeping the md5 checks as a separate `DO`.
- **D-S2. `approved` and `application_complete` become mirror-only (File B block 4).** Not in the spec's list. Without it, retiring the bridges leaves two direct writes that succeed and corrupt the mirror: the installed form's `application_complete = true` with no membership (the waiting screen with nothing pending), and an admin's `approved = true` with no membership (an approved account that cannot post). With it, both fail loudly. Platform admins lose a direct write no community build uses (Requests to join and `approve_community_member` are the approval path). Without the block, the bridges are dropped all the same and the nightly consistency query of spec §5 has to catch the drift.
- **D-S3. Block 7 is optional.** `get_leaderboard` (both overloads) has no caller in the current client or in `main`; `send_broadcast_notifications` is called only by the installed admin build (`main:Core/Services/AdminService.swift:478`). Both resolve to the default community. Keeping them costs nothing; closing them removes two anon-callable functions.
- **D-S4. INV-L1 is kept.** The spec's INV-L1 ("exactly one default community … never archived", while any pre-community build is supported) could lapse at the gate, making Seattle archivable like any other community. This plan does not change `archive_community`, `archive_community_with_notices`, `leave_community` or `delete_user_account`'s STEP A (the A3 + INV-L1 succession the owner accepted on 2026-10-18): that is a product decision, not a deprecation. `is_default` stays as the "Default" label and as the platform admins' view in `get_badge_counts` and Requests to join. `default_community_id()` also stays: `get_xp_leaderboard` and `get_leaderboard_spotlights`, which the current client still calls when no community is selected (`Core/Services/LeaderboardService.swift:143-144, 185-186`), and `fill_xp_event_community` use it as the last resort.
- **D-S5. `create_signup_profile` is not changed.** It accepts `p_heard_about` / `p_join_reason` but no build has ever sent them (`git log -S p_heard_about` over the Swift sources finds only `[P2-T1]`, in `CommunityService`), so every new row already gets null. Changing a sign-up function for no observable effect is risk without benefit; dropping the two parameters would also change its signature, which CLAUDE.md treats as an RPC seam.
- **D-S6. File D revokes every table privilege, not only SELECT.** The 5a client writes through `put_geocoding_multiplier`, and the installed build's upsert needs SELECT anyway. The three policies stay (inert); dropping them is SQL-editor work for a later cleanup.
- **D-S7. Who may read a stored object (File E).** Message and group photos: any participant row of the caller for the folder's conversation (a person who left still reads the thread within their window, as the `messages` policy allows), plus the uploader. Town Hall and review photos: visibility by reference, through the posts' and reviews' own policies (a `position()` scan of `image_url`; 34 posts and a few dozen reviews today; a stored object path column is the follow-up if this grows). The uploader may always read their own objects, which also keeps the two `upsert: true` uploads (`ConversationService.swift:668-672`, `ReviewService.swift:202-206`) working. A review photo stored in `town-hall-images` by `ReviewService`'s fallback (`:208-218`) is covered by the Town Hall policy's review clause, and a Town Hall post that carries a `review-images` URL (the shape the uncalled `ReviewService.createTownHallPostForReview` builds, `:237-257`; 0 such posts) by the review policy's post clause. Review images are matched by `image_url`, so the upload's file name (a fresh UUID, `:60`, `:196`) does not matter; no live review has one, so the gate writes one (iOS plan Task 10 O5).
- **D-S8. Placemark data is cleared now (File A block 3) and again at the gate (File D block 2).** Seven rows hold street-level placemarks written by the old client; nothing reads them. Block 3 is a one-time clean-up: the installed build and Phase 1-4 builds keep writing placemarks with their direct upsert (`main:NaarsCars/Core/Utilities/GeocodingCacheService.swift:152`) until File D closes the table, so File D repeats the clear. Both are irreversible (the multipliers are untouched). Drop block 3 to keep the rows until File D.
- **D-S9. The gate for Files D and E is stricter than A5's.** A5 point 2 names "no pre-community build remains in use". Files D and E also break any community build that lacks the 5a client (Phase 1-4 builds use direct table access and public image URLs). If the first community build to reach the App Store contains 5a, the two conditions coincide; otherwise those files wait for that build to age out too. Files B and C need only A5's condition: no community build writes the mirrored flags, calls `admin_reject_pending_user`, or touches `invite_codes`.
- **D-S10. `invite_codes` is dropped, not renamed.** A rename plus a revoke would be reversible in one statement; the spec and A5 say drop. File C keeps a DDL capture in the repository and the rows off it (they hold user ids and the repository is public).
- **Follow-ups, not in this phase:** `profiles` keeps table-level UPDATE grants on `heard_about` / `join_reason` (a column-level revoke needs the whole grant list rebuilt); the inert `geocoding_cache` policies and the duplicate storage INSERT policies on `message-images` ("Message image uploads" and `message_images_insert_authenticated`) can be dropped in the SQL editor; the 54 unused legacy codes go with the table.
