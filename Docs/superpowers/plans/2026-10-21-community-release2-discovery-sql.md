# Community Release 2 (discovery): server migrations, test data and probes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the server everything discovery needs: service areas, the owner's listed switch, search by name and by place, the nearby check, a create RPC with area and reason, the merge proposal flow with its single-transaction merge, the `is_test` flag, and example content in Test Community that stays current and never notifies anyone.

**Architecture:** Four additive migration files (A schema and visibility, B discovery RPCs, C merge, D example content) and one data script, each applied block by block through the Supabase MCP after a rolled-back dry run, each proven by new blocks of `supabase/probes/communities_probe.sql`. Existing functions change only by an edit of their live body (the D-S1 derive pattern or a full rewrite with the same signature); every new capability has a new name, so Release 1 and Phase 5a builds keep working. Distances are great-circle miles in plain SQL (no PostGIS); nothing a person types or their device location is stored or logged.

**Tech Stack:** PostgreSQL 15 on Supabase (plpgsql, RLS, SECURITY DEFINER, `pg_cron`), the Supabase MCP (`execute_sql`, `apply_migration`), the committed probe file.

**Spec:** `Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md` (4.1, 4.2, 4.10, 4.11, 4.12 and the "Release 2, discovery" paragraph of 4.10). Companion: `Docs/superpowers/plans/2026-10-21-community-release2-discovery.md` (the iOS plan; its gate runs this plan's probes again). Builds on `Docs/superpowers/plans/2026-10-21-community-release1-navigation.md` Task 1 (`20261021_0001`), which must be APPLIED first.

## Global Constraints

- **Executor:** the orchestrator only. Agents executing the iOS plan never write under `supabase/`.
- **The live schema is extended, not replaced** (spec 3). Every edited function starts from its live body, checked by `md5(prosrc)` before the edit (P1); a mismatch stops the task.
- **A signature change gets a new name** (spec 3, CLAUDE.md). No existing function in this plan changes its signature or return type; `create_community` stays for Release 1 builds beside the new `create_community_with_area`.
- **MCP refusals:** `apply_migration` / `execute_sql` decline `DELETE`, `DROP POLICY`, `DROP FUNCTION`, `DROP TABLE` and function bodies that delete from `auth.*` / `storage.*`. Such a statement goes, verbatim, to a file or header marked NOT APPLIED for the owner's SQL editor; it is never rephrased to get past the MCP. In this plan only the rollbacks are declined statements.
- **One `apply_migration` per block**, named `<file>_block_<n>`, its text byte for byte from the committed file; probe `short` after each block.
- **Every function** is `security definer` (or invoker where stated), `set search_path = ''`, with `revoke all … from public` and explicit grants; internal helpers are revoked from `anon` and `authenticated`.
- **RLS is the boundary** (spec 3): visitors read communities only through definer RPCs or the existing guest views and policies; the two new tables have RLS on and no client policy or grant.
- **Privacy** (spec 4.2): `search_communities_by_name` and `find_communities_near` write nothing, raise no notice carrying their arguments, and are `stable`; the device coordinate reaches only `find_communities_near`.
- **Hidden is never open** (spec 4.1): `communities` gains `check (is_public or join_policy <> 'open')`; `join_policy` still allows only `invite` and `approve` until Release 3b. No data migration: hidden approval communities keep their policy.
- **Only the owner** changes listed, join policy and service area (`update_community_access`); platform admins keep `set_community_public` for unlisting (A2).
- **`is_test`** hides a community from search, the join list and guest views for everyone except its members and platform admins (spec 4.10); it is set only in SQL by the orchestrator. Test Community is not flagged.
- **Example content** (spec 4.11): `is_example` on `rides`, `favors`, `town_hall_posts`; only platform admins (and definer code) set it; example rows never notify, never earn XP, never expire, and cannot be claimed.
- **Notification registry unchanged at 34 types:** every new notice is an `announcement` bell row (`scripts/validate-notification-types.sh` still prints "34 types in sync").
- **Public repository:** no personal data in any committed file. Test accounts are found by display name plus the first 8 characters of their id recorded in `Docs/qa/test-data.md`; Test Community's full id is already public in `supabase/scripts/2026-10-21_test_community_cleanup.sql`.
- **Commits:** subject `[R2-S<n>] …`, body ending `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (the orchestrator's line; an executing session whose harness gives another attribution line uses that one). **Staging:** `git add` exactly the task's **Files** paths, which each commit step names; never `git add -A` or a directory; never push (CLAUDE.md, public repository: ask the owner).

## Review Focus

1. **Search text with wildcards, case and spaces** (`%`, `_`, `\`, `"  te "`, one character, 200 characters): literal, case-insensitive substring of the name, trimmed, at most 60 characters used, at most 20 rows, nothing for fewer than 2 characters. Pinned: S2 probe `discovery_search` (wildcard, backslash, padding and length checks).
2. **A point or an area at the edges** (null, latitude 91, longitude -181, the antimeridian, a radius of 3 miles, an area name "5412 Probe Ln NW"): a typed refusal (`invalid_area`), never an exception and never a stored row. Pinned: S2 probes `discovery_search` and `listing_rules`.
3. **A merge where one person has different standing in the two communities** (removed from the survivor but active in the merged one; pending in one and active in the other; owner of both): removed stays removed and their requests in the merged community are unwound; the higher role wins; pending stays pending. Pinned: S3 probe `community_merge` (the roles table and the one-owner-of-both case).
4. **Two owners proposing to each other at the same moment, or a proposal answered after it expired, was withdrawn, or one side was archived:** one pending proposal per community, `proposal_closed` for a stale answer, no merge. Pinned: S3 probe `community_merge` (one-pending, expiry, archived side).
5. **The daily refresh running twice, late, or after a missed week:** every example ends in `[tomorrow, tomorrow + 6]` in its own time zone, keeps its weekday, a second run changes nothing. Pinned: S4 probe `example_content` (idempotence and a 20-day-old example).

---

## What Release 2 needs from the server, and where each piece is

| Spec item | Where | What a Release 1 or Phase 5a build sees |
|---|---|---|
| Service-area columns, `is_test`, the merge columns | A1 | nothing (new columns) |
| Listing reason and overlaps for platform admins | A2 table `community_listing_events`, B8 | nothing |
| Merge proposals | A3 table `community_merge_proposals`, C | nothing |
| `is_example`, `system_event` | A5 | guest views return one more column (ignored by the decoders) |
| `is_test` out of the join list, guest views, profiles and reviews of listed communities | A7-A9 | Test Public A and B leave Explore's flat list for non-members (Release 1 Prerequisite 3 is settled by this) |
| Claims of examples refused, flag reserved | A10 | an example claim fails with the generic claim error |
| Search by name and by place, the nearby check | B1-B3 | nothing (new names) |
| Create with area and reason | B4 | nothing; Release 1 keeps creating hidden communities through `create_community` |
| Owner's listed switch, policy and area | B5 | nothing |
| Listing needs an area | B6 (`set_community_public`) | a platform admin's "allow guests" on Create fails with `community_create_public_failed` for a community without an area |
| Preview: area keys, `is_example`, `is_test` and `merged` refusals | B7 | a merged community's page shows "Couldn't load" (unknown code) |
| Platform list: area, test flag, reason, merges | B8 | nothing (keys added) |
| Merge (propose, respond, withdraw, the transaction, the announcement, the survivor map) | C1-C9 | members of a merged community see it leave their lists after the next membership load and get the announcement push (type `announcement`, routed to Announcements) |
| Example rules and the daily refresh | D1-D7 | examples never notify or expire |
| Test Community area, test flags, example content | data script (S5) | Test Community shows example requests and posts |

## Statements the MCP declines

None in Files A-D or the data script. Declined statements appear only in the rollback text of each header (`drop function`, `drop table`, `drop trigger`, deleting seeded rows); those are the owner's SQL-editor steps. The data script disables two notify triggers inside its own transaction (`alter table … disable trigger`); if the MCP declines that, the owner runs the script verbatim in the SQL editor.

## Preconditions (read only, orchestrator, through `execute_sql`)

- **P0. Release 1 is live.** `to_regprocedure('public.get_community_preview(uuid)')` and `to_regprocedure('public.is_listed_request(uuid, uuid)')` are not null and `20261021_0001`'s header reads APPLIED. Otherwise stop.
- **P1. Live bodies.** For each function this plan edits, `md5(prosrc)` live equals the deployed value in the header of its source file; record both in the new file's header as the rollback source:

  | Function | Source of the live body (deployed md5 in that header) |
  |---|---|
  | `my_visible_profile_ids()`, `is_listed_request(uuid, uuid)`, `get_community_preview(uuid)` | `20261021_0001` blocks 1, 2, 4 |
  | `get_platform_communities()`, `set_community_public(uuid, boolean)` | `20261017_0005` blocks 32, 12 |
  | `send_community_broadcast(uuid, text, text, boolean, text)`, `notify_town_hall_post()` | `20261019_0002` blocks 2, 1 (`1f4f2dfbe34141fa821967370d33a309`, `8067912ecd96ed2a655a82c1a9d247f7`) |
  | `notify_new_ride()`, `notify_new_favor()`, `record_xp_on_request_created()` | `20261017_0003` calls 1, 2, 7 |
  | `expire_past_open_requests()` | `20261006_0004` |

  The views `guest_rides`, `guest_favors`, `public_profiles` and the policies `communities_select_anon`, `communities_select_authenticated`, "Guests can view visible town hall posts" equal `20261017_0002` [V1]-[V3], [N1], [N2], [A08] (`pg_get_viewdef`, `pg_policies.qual`); the `community_membership_events_event_check` definition lists the 11 events of `20261017_0001:217`.
- **P2. Names are free.** `to_regclass` of `public.community_listing_events`, `public.community_merge_proposals` is null; `to_regprocedure` of every new function in this plan is null; `information_schema.columns` has none of the new columns; `select jobname from cron.job` has no `refresh-example-requests`.
- **P3. Triggers exist** with these names: `on_qa_created_notify` (request_qa), `on_town_hall_comment_notify` (town_hall_comments), `set_updated_at_rides`, `set_updated_at_favors`, `set_updated_at_town_hall_posts`, `on_ride_status_change_notify`, `on_favor_status_change_notify`.
- **P4. Migration numbers.** `ls supabase/migrations/20261021_*` and `list_migrations`: nothing numbered `20261021_0020`-`0023`. On a collision renumber upward, keeping A < B < C < D.
- **P5. Test data** (S5 only): exactly one profile named `NC Test Owner` whose id starts `eebf5514`; exactly one named `NC Test Neighbor` whose id prefix the owner recorded in `Docs/qa/test-data.md` (Prerequisite 2 of the iOS plan); Test Community `7a8ed131-cb05-462b-a491-b433d70a3fe5` is named "Test Community", default, listed, `approve`; the four test communities match the prefixes and names in `Docs/qa/test-data.md`.

## Runbook

S1 → S2 → S3 → S4 in order, each: P1/P2 rows for that file, write the file (NOT APPLIED header), write its dry-run script, structural check, dry run (one `execute_sql` of the script), not-applied check (P2 names still null), apply block by block with `short` after each, the file's probe blocks, header to APPLIED, commit. S5 (data) after S4, with the owner's go-ahead (it writes to Test Community, which has real members). S6 runs the full probe file and closes the headers. The iOS plan's Tasks use stubs; S1-S5 must be live before its gate.

## Dry-run scripts (assembly)

One script per file in `supabase/dryruns/`, assembled exactly as the Phase 5 SQL plan's "Dry-run scripts (5b)" section (header comment, PARAMETERS, HELPERS without their `commit;`, `begin;`, the file's blocks without header, each listed probe block with its `begin;` → `savepoint probe;` and `rollback;` → `rollback to savepoint probe; release savepoint probe;`, `select 'DRYRUN <file> OK' as dryrun;`, `rollback;`) and passing its structural check with N = the probe count below. The HELPERS include this plan's additions (S1 Step 2).

| Script | Probe blocks (N) |
|---|---|
| `20261021_0020_discovery_schema.dryrun.sql` | `test_flag_visibility`, `example_guard`, `community_preview`, `listed_profiles`, `isolation`, `short` (6) |
| `20261021_0021_discovery_rpcs.dryrun.sql` | `discovery_search`, `listing_rules`, `community_preview`, `short` (4) |
| `20261021_0022_community_merge.dryrun.sql` | `community_merge`, `broadcast_cap`, `broadcast_push`, `short` (4) |
| `20261021_0023_example_content.dryrun.sql` | `example_content`, `short` (2) |

---

### Task S1: File A — columns, tables, visibility and the example guard

**Files:**
- Create: `supabase/migrations/20261021_0020_discovery_schema.sql` (blocks 1-10), `supabase/dryruns/20261021_0020_discovery_schema.dryrun.sql`
- Modify: `supabase/probes/communities_probe.sql` (header "WHEN TO RUN WHAT" and RPC list; HELPERS before the `commit;`; blocks `test_flag_visibility`, `example_guard` before `select 'PROBE ALL OK'`)

**Interfaces:**
- Consumes: Release 1's `my_visible_profile_ids()` listed arm and `is_listed_request(uuid, uuid)`.
- Produces: `communities` columns `area_name text`, `area_center_lat double precision`, `area_center_lng double precision`, `area_radius_miles integer`, `is_test boolean not null default false`, `merged_into_id uuid references communities(id) on delete set null`, `merged_at timestamptz`; `rides.is_example`, `favors.is_example`, `town_hall_posts.is_example` (`boolean not null default false`); `town_hall_posts.system_event text`; tables `community_listing_events`, `community_merge_proposals`; `public.great_circle_miles(double precision, double precision, double precision, double precision) returns double precision`; `public.can_discover_community(uuid) returns boolean`; trigger function `public.guard_example_content()`; the event `'merged'` in `community_membership_events`.

- [ ] **Step 1: Write File A** with a header in the `20261019_0002` form (NOT APPLIED; what it does; what old clients see, from the table above; apply order; the P1 values; rollback per block). Blocks:
  - **Block 1** `alter table public.communities add column …` the seven columns, plus constraints in the same statement: `communities_area_all_or_none` (the four area columns all null or all not null), `communities_area_radius` (`area_radius_miles in (1, 2, 5, 10)`), `communities_area_center` (lat between -90 and 90, lng between -180 and 180), `communities_area_name` (`char_length(btrim(area_name)) between 2 and 80`), `communities_hidden_not_open` (`is_public or join_policy <> 'open'`). Index `communities_listed_live (id) where is_public and archived_at is null`.
  - **Block 2** `community_listing_events (id uuid pk default gen_random_uuid(), community_id uuid not null references communities on delete cascade, actor_id uuid references profiles on delete set null, event text not null check (event in ('created_listed', 'listed', 'area_moved')), area_name text, area_center_lat double precision, area_center_lng double precision, area_radius_miles integer, overlapping_ids uuid[] not null default '{}', reason text check (reason is null or char_length(reason) between 1 and 300), created_at timestamptz not null default now())`; index `(community_id, created_at desc)`; RLS on; `revoke all … from public, anon, authenticated`.
  - **Block 3** `community_merge_proposals (id uuid pk default gen_random_uuid(), from_community_id uuid not null, to_community_id uuid not null, survivor_community_id uuid not null` (all three `references communities on delete cascade`), `proposed_by uuid references profiles on delete set null, note text check (note is null or char_length(note) <= 300), status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'withdrawn', 'expired')), created_at timestamptz not null default now(), expires_at timestamptz not null default now() + interval '7 days', decided_at timestamptz, decided_by uuid references profiles on delete set null`, `check (from_community_id <> to_community_id)`, `check (survivor_community_id in (from_community_id, to_community_id))`); partial unique indexes `community_merge_one_pending_from (from_community_id) where status = 'pending'` and `community_merge_one_pending_to (to_community_id) where status = 'pending'`; index `(to_community_id, status)`; RLS on; revoke as Block 2.
  - **Block 4** one `alter table public.community_membership_events drop constraint community_membership_events_event_check, add constraint … check (event in (<the 11 live values>, 'merged'))`.
  - **Block 5** `rides`, `favors`, `town_hall_posts` gain `is_example boolean not null default false`; `town_hall_posts` gains `system_event text check (system_event is null or system_event = 'community_merged')`; partial indexes `<table>_examples (id) where is_example`.
  - **Block 6** the two helpers. `great_circle_miles` is `language sql immutable parallel safe`, no grants beyond the owner (definer code calls it):
    ```sql
    select 2 * 3958.8 * asin(least(1, sqrt(
             power(sin(radians(lat2 - lat1) / 2), 2)
           + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))));
    ```
    `can_discover_community(p_community_id)` (`language sql stable security definer`, revoked from `anon`, `authenticated`): a row with that id, `is_public`, `archived_at is null`, and `(not is_test or public.is_platform_admin() or id = any((select public.my_community_ids())::uuid[]))`. This predicate is "discoverable" everywhere below.
  - **Block 7** `create or replace view` `guest_rides` and `guest_favors`: the [V1]/[V2] text with `and not c.is_test` in the `where` and `r.is_example` / `f.is_example` appended after `community_id` (columns are only appended); `public_profiles`: [V3] with `and not c.is_test` inside the anon arm's `exists`. Comments restated.
  - **Block 8** three `alter policy`: `communities_select_anon using (is_public and not is_test and archived_at is null)`; `communities_select_authenticated`: [N2] with `is_public` replaced by `(is_public and not is_test)`; "Guests can view visible town hall posts": [A08] with `and not c.is_test`.
  - **Block 9** `my_visible_profile_ids()`: its live body with `and not c.is_test` after `c.is_public and c.archived_at is null` in the listed-member arm (derive pattern of `20261019_0060` block 2: that exact passage must occur once; md5 checked before and after). `is_listed_request(uuid, uuid)`: a full rewrite of its live body (two `exists` arms) with `and not c.is_test` in both arms; signature and grants unchanged.
  - **Block 10** `guard_example_content()` (invoker, `language plpgsql`, the `current_user not in ('authenticated', 'anon')` early return of `guard_request_client_update`) and `create or replace trigger guard_example_content before insert or update on` each of `rides`, `favors`, `town_hall_posts`. Rules for a client role: INSERT with `new.is_example` → raise `42501` `'example_flag_reserved'`; INSERT on `town_hall_posts` with `new.system_event is not null` → the same; UPDATE changing `is_example` (or `system_event` on posts) → the same; UPDATE of `rides` / `favors` where `old.is_example` and `new.claimed_by is distinct from old.claimed_by` → raise `42501` with the message exactly `'example_request'` (the iOS client matches this text). Branch on `TG_TABLE_NAME` before touching `system_event`. The trigger name sorts before `guard_request_claim_membership` and `guard_request_client_update`, so it fires first.
- [ ] **Step 2: Probe additions.** HELPERS (before the `commit;`): `pg_temp.probe_require_release2(p_probe text, p_part text)` — raises `PROBE <p> FAILED: Release 2 part <x> is not live` unless Release 1 is live (`get_community_preview` exists) and, cumulatively, part `'a'`: column `communities.is_test` and function `guard_example_content` exist; `'b'`: `search_communities_by_name`; `'c'`: `merge_communities`; `'d'`: `refresh_example_requests`. `pg_temp.probe_area(p_community uuid, p_name text, p_lat double precision, p_lng double precision, p_radius int)` updates the four area columns as the table owner. `pg_temp.probe_test_community(n int, p_owner uuid)`: `probe_community(n, 'Probe Test ' || n, p_owner, true, 'approve')` then `is_test = true`. Header bullet: "Release 2. test_flag_visibility and example_guard need 20261021_0020; discovery_search and listing_rules need 0021; community_merge needs 0022 (broadcast_cap and broadcast_push are its regression probes); example_content needs 0023. None holds a DELETE; all run through the MCP." RPC list: the Release 2 names with their arguments.
  - **`test_flag_visibility`** (probe_world; C4 = `probe_test_community(4, u(16))`, area on C2 and C4; u(12)'s open future ride in C4 and a post): anon reads 0 rows of `communities`, `guest_rides`, posts for C4 and 1 row for C2; u(3) (not in C4) reads 0 rows of C4 from `communities`; u(16) (C4's owner) reads its row; the platform admin subject reads it; anon's `public_profiles` excludes u(16) when u(16) is in no other listed community; `my_visible_profile_ids()` for u(3) excludes u(16); `is_listed_request(<the C4 ride>, null)` is false; `guest_rides` has the column `is_example`.
  - **`example_guard`**: as the member subject, an insert of a ride with `is_example = true` → `42501`; an update of the member's own ride setting `is_example` → `42501`; a post insert with `system_event` → `42501`; the owner (no JWT) marks u(3)'s open C1 ride `r(2)` as an example; u(7) (C1 member) claiming it with the claim UPDATE → `42501` with error text `example_request`; the same claim on a non-example open ride succeeds.
- [ ] **Step 3: Dry-run script and structural check** (`20261021_0020_discovery_schema.dryrun.sql`, N = 6). Expected: no `commit;`, one `begin;`, one `rollback;`, 6 savepoints.
- [ ] **Step 4: Dry run** (one `execute_sql`, the script verbatim). Expected: six `PROBE … OK` rows and `DRYRUN 20261021_0020 OK`; afterwards P2's names for File A are still null.
- [ ] **Step 5: Apply** blocks 1-10 (`20261021_0020_block_<n>`), `short` after each. Expected: `PROBE short OK` ten times.
- [ ] **Step 6: Probes** `test_flag_visibility`, `example_guard`, `community_preview`, `listed_profiles`, `reputation`, `isolation`, `noop_default` (one `execute_sql` each with PARAMETERS and HELPERS). Expected: all OK.
- [ ] **Step 7: Header** → `APPLIED 2026-10-2x`: migration-history versions, `md5(prosrc)` of every created or edited function (each equal to the file's text between delimiters), `md5(qual)` of the three policies, the dry-run and probe outcomes, rollback (Blocks 7-9: the P1 text through the MCP; Block 10 `drop trigger … ; drop function public.guard_example_content()`, Blocks 1-6 `drop` of the columns, tables, functions: SQL editor, owner, and only while no Release 2 client is installed).
- [ ] **Step 8: Commit** (`supabase/migrations/20261021_0020_discovery_schema.sql`, `supabase/dryruns/20261021_0020_discovery_schema.dryrun.sql`, `supabase/probes/communities_probe.sql`) `[R2-S1] Service-area, test and example columns; is_test visibility; example guard`.

---

### Task S2: File B — search, the nearby check, create, access, preview and the platform list

**Files:**
- Create: `supabase/migrations/20261021_0021_discovery_rpcs.sql` (blocks 1-8), `supabase/dryruns/20261021_0021_discovery_rpcs.dryrun.sql`
- Modify: `supabase/probes/communities_probe.sql` (blocks `discovery_search`, `listing_rules`)

**Interfaces:**
- Consumes: S1's columns, `can_discover_community`, `great_circle_miles`, `community_listing_events`.
- Produces (row shape shared by Blocks 1-3, key `communities`, at most 20 rows): `{"success": true, "communities": [{id, name, description, join_policy, area_name, area_radius_miles, member_count, distance_miles}]}`; `member_count` counts active, unbanned members; `distance_miles` is `round(<miles>::numeric, 1)` or null. Refusals are `{"success": false, "error", "code"}`.
  - `search_communities_by_name(p_query text) returns jsonb` (anon, authenticated, service_role)
  - `find_communities_near(p_lat double precision, p_lng double precision) returns jsonb` (anon, authenticated, service_role)
  - `check_community_area(p_center_lat double precision, p_center_lng double precision, p_radius_miles integer, p_community_id uuid default null) returns jsonb` (authenticated, service_role)
  - internal `overlapping_listed_communities(p_center_lat double precision, p_center_lng double precision, p_radius_miles integer, p_exclude uuid) returns table (id uuid, name text, description text, join_policy text, area_name text, area_radius_miles integer, member_count integer, distance_miles numeric)`
  - `create_community_with_area(p_name text, p_description text default null, p_join_policy text default 'approve', p_timezone text default null, p_listed boolean default false, p_area_name text default null, p_center_lat double precision default null, p_center_lng double precision default null, p_radius_miles integer default null, p_reason text default null) returns jsonb` → `{success, community_id}` (authenticated, service_role)
  - `update_community_access(p_community_id uuid, p_listed boolean, p_join_policy text, p_area_name text default null, p_center_lat double precision default null, p_center_lng double precision default null, p_radius_miles integer default null, p_reason text default null) returns jsonb` → `{success, changed}` (authenticated, service_role)
  - `get_community_preview(uuid)`: Release 1 shape plus `community.area_name / area_center_lat / area_center_lng / area_radius_miles` and `requests[].is_example`; refusal codes `not_listed` and `merged` (with `merged_into_id`, `merged_into_name`).
  - `get_platform_communities()`: every community row gains `area_name, area_center_lat, area_center_lng, area_radius_miles, is_test, merged_into_id, merged_into_name, listing_event, listing_reason, listing_overlaps (text[] of names), listing_event_at`; top level gains `merge_proposals` (filled by S3; `[]` until then).
  - New refusal codes: `not_owner`, `needs_area`, `invalid_area`, `reason_required`, `default_stays_listed` (S3 adds `merge_pending`, `recently_declined`, `proposal_closed`, `default_community`).

- [ ] **Step 1: Write File B** (header as S1). Blocks:
  - **Block 1 `search_communities_by_name`** (`stable`, plpgsql): `q := left(btrim(coalesce(p_query, '')), 60)`; fewer than 2 characters → `{success: true, communities: []}`; rows: discoverable communities with `strpos(lower(name), lower(q)) > 0` (no LIKE, so `%` and `_` are literal), order `strpos(lower(name), lower(q)) = 1 desc, name, id`, limit 20, `distance_miles` null.
  - **Block 2 `find_communities_near`**: null, latitude outside [-90, 90] or longitude outside [-180, 180] → `{success: false, error: 'Choose a town or ZIP code', code: 'invalid_area'}`; rows: discoverable communities with an area and `great_circle_miles(center, point) <= area_radius_miles`, ordered by that distance, then name; limit 20; `distance_miles` from the point.
  - **Block 3** `overlapping_listed_communities` (definer, revoked from client roles): discoverable communities with an area, `id is distinct from p_exclude`, `great_circle_miles(centers) < their radius + p_radius_miles`, ordered by distance, limit 20, `distance_miles` between centers. `check_community_area` (no EXECUTE for `anon`): invalid point or `p_radius_miles not in (1, 2, 5, 10)` → `invalid_area`; else the rows of the helper under `communities`.
  - **Block 4 `create_community_with_area`**: the live text of `create_community(text, text, text, text)` (`20261019_0001` block 3, md5 `b499c74a3371cc051f02a4bcd19b54f3`) with these additions in order: `p_join_policy` other than `invite` / `approve` → the existing "Unknown join policy" refusal with `code: 'invalid'`; when `p_listed`: all four area arguments null → `needs_area`; any one null, out of range, radius not in the set, or `p_area_name` failing `char_length(btrim(…)) between 2 and 80` or matching `'(^|[[:space:]])[0-9]{1,6}[[:space:]]+[[:alpha:]]'` (a house number) → `invalid_area`; when not listed the area arguments and the reason are ignored. After the two limits and before the insert: when listed, `v_overlaps := array(select id from overlapping_listed_communities(…, null))`; non-empty with `nullif(btrim(p_reason), '')` null or longer than 300 → `reason_required`. The insert sets `is_public = p_listed` and the area; when listed, a `community_listing_events` row (`created_listed`, the area, `v_overlaps`, the trimmed reason). Platform admins' bell rows (unchanged loop) get the body `'Created by <name>.'` followed, when listed, by `' Listed · <area_name> (<r> mi).'` and, with a reason, `' Reason: <reason>'`; no push.
  - **Block 5 `update_community_access`**: refusals in this order: no `auth.uid()` or `my_community_role(p_community_id) <> 'owner'` → `not_owner` (platform admins are not owners here); community archived or missing → `invalid`; `p_listed` or `p_join_policy` null, or policy not `invite` / `approve` → `invalid`; default community with `p_listed = false` → `default_stays_listed`; area arguments not all null and not all valid (Block 4's rules) → `invalid_area`; resulting area null while listed → `needs_area`; becoming listed, or listed with a new area different from the stored one, and overlaps (excluding itself) with no reason → `reason_required`. Then one `update communities` (only changed columns, `updated_at = now()`; area columns only when new ones were sent; `select … for update` first). `community_listing_events`: `listed` when hidden → listed, `area_moved` when it stays listed and the area changed. When hidden → listed: platform admins' bell rows (no push) `'Now listed: <name>'` / `'<area_name> (<r> mi).'` plus `' Reason: <reason>'`. When `is_public` or `join_policy` changed: every other active member gets `notify_user_in_community(…, 'announcement', '<name> changed how people join', '<Listed|Hidden> · <Ask to join|Invite only>.', p_community_id, false, …)`. Returns `{success: true, changed}`.
  - **Block 6 `set_community_public`**: the live text (`20261017_0005` block 12) with the select reading `c.is_default, c.area_center_lat` and, before the update, `p_is_public` and no area → `{success: false, error: 'A listed community needs a service area', code: 'needs_area'}`.
  - **Block 7 `get_community_preview`**: the live text (`20261021_0001` block 4) with: the community lookup reads archived rows too; archived with `merged_into_id` whose survivor is discoverable → `{success: false, error: 'Community merged', code: 'merged', merged_into_id, merged_into_name}`; any other archived, hidden, or `is_test` community the caller may not discover → `not_listed` (members of a test community and platform admins pass); the community object gains the four area keys; each request object gains `is_example`.
  - **Block 8 `get_platform_communities`**: the live text (`20261017_0005` block 32) with the added row keys (listing values from the newest `community_listing_events` row of the community; `listing_overlaps` the names of `overlapping_ids` in order) and `merge_proposals` (S3 Block 9 fills it; here `'[]'::jsonb`).
- [ ] **Step 2: Probe blocks.**
  - **`discovery_search`** (probe_world; areas: C2 at 47.6062, -122.3321 radius 2 named 'Probe Town'; C4 test community at the same point radius 1; C1 hidden with an area set by the owner): anon `search_communities_by_name('two')` returns C2 only; `('PROBE PUBLIC')` matches case-insensitively; `('o')` is empty; `('%')` and `('_')` return no row (no community name holds them); `('\')` returns `success` with no row and no error (a backslash is literal); `('  probe  ')` returns the same rows as `('probe')` (trimmed); a 200-character query returns `success` with no error; hidden C1 never appears for anyone, its members included; C4 appears for its owner u(16) and the platform admin subject and not for u(3) or anon, and `get_community_preview(c(4))` answers `not_listed` to u(3) and anon and succeeds for u(16) and the platform admin; `find_communities_near(47.6100, -122.3321)` returns C2 with `distance_miles` 0.3 (rounded) for anon; a point 3 miles north returns nothing; a probe community centred at `(0, 179.99)` with radius 10 is found from `(0, -179.99)` (across the antimeridian); `(91, 0)`, `(0, -181)` and `(null, 0)` → `invalid_area`; an archived C2 disappears from both; at most 20 rows when 25 matching probe communities exist (created in the block); nothing was inserted into any table by the searches (row counts of `communities`, `notifications`, `community_listing_events` unchanged around the calls).
  - **`listing_rules`** (probe_world; C2's area as in `discovery_search`): u(6) `create_community_with_area('Probe Hidden Six', null, 'invite')` → success, `is_public` false, no area, no listing event; u(13) listed with no area → `needs_area`; radius 3 → `invalid_area`; area name `'5412 Probe Ln NW'` → `invalid_area`; area overlapping C2 with no reason → `reason_required`; with reason 'Probe reason' → success, one `created_listed` event naming C2 and the reason, and every platform admin got one `announcement` bell row containing 'Reason: Probe reason' and no `notification_queue` row; `'open'` → `invalid`. `update_community_access`: u(5) (admin of C1) → `not_owner`; u(4) (owner of C1) hidden → listed without area → `needs_area`; with an area overlapping C2 and no reason → `reason_required`; with a reason → `changed = true`, a `listed` event, u(3), u(5), u(7), u(11) each got one bell row "… changed how people join" and u(4) none; repeat with the same values → `changed = false` and no new rows; default community unlisted by its owner → `default_stays_listed`; `set_community_public(c(1), true)` by the platform admin on a community without an area → `needs_area`; `get_community_preview` of C2 has `area_radius_miles = 2` and every request carries `is_example`.
- [ ] **Step 3: Dry-run script, structural check (N = 4), dry run.** Expected: four OK rows and `DRYRUN 20261021_0021 OK`; File B names still null afterwards.
- [ ] **Step 4: Apply** blocks 1-8 with `short` after each; then `discovery_search`, `listing_rules`, `community_preview`, `test_flag_visibility`. Expected: all OK.
- [ ] **Step 5: Header** APPLIED (versions, md5s, outcomes; rollback: Blocks 6-8 the P1 text through the MCP; Blocks 1-5 `drop function` in the SQL editor).
- [ ] **Step 6: Commit** (`supabase/migrations/20261021_0021_discovery_rpcs.sql`, `supabase/dryruns/20261021_0021_discovery_rpcs.dryrun.sql`, `supabase/probes/communities_probe.sql`) `[R2-S2] Search by name and place, the nearby check, create with area, owner access switch`.

---

### Task S3: File C — merging two communities

**Files:**
- Create: `supabase/migrations/20261021_0022_community_merge.sql` (blocks 1-9), `supabase/dryruns/20261021_0022_community_merge.dryrun.sql`
- Modify: `supabase/probes/communities_probe.sql` (block `community_merge`)

**Interfaces:**
- Consumes: S1 tables and columns, S2's discoverable rule and `get_platform_communities`.
- Produces:
  - internal `post_community_announcement(p_community_id uuid, p_author uuid, p_title text, p_body text, p_pinned boolean, p_type text, p_system_event text, p_push_data jsonb) returns integer`
  - internal `merge_communities(p_proposal_id uuid, p_actor uuid) returns jsonb`
  - `search_merge_targets(p_community_id uuid, p_query text) returns jsonb` → `{success, communities: [{id, name, join_policy, is_public, member_count, area_name}]}`
  - `propose_community_merge(p_community_id uuid, p_other_id uuid, p_survivor_id uuid, p_note text default null) returns jsonb` → `{success, proposal_id}`
  - `get_community_merge_proposal(p_community_id uuid) returns jsonb` → `{success, proposal: null | {id, direction ('incoming'|'outgoing'), from: {id, name, join_policy, member_count}, to: {…}, survivor_id, note, proposed_by_name, created_at, expires_at}}`
  - `respond_to_community_merge(p_proposal_id uuid, p_accept boolean) returns jsonb` → accept `{success, survivor_id, merged_id}`, decline `{success}`
  - `withdraw_community_merge(p_proposal_id uuid) returns jsonb` → `{success}`
  - `get_my_community_merges() returns jsonb` → `{success, merges: [{merged_id, merged_name, survivor_id, survivor_name, merged_at}]}`
  - All client RPCs: EXECUTE for `authenticated`, `service_role`. Push data of the merge announcement: `{community_id, town_hall_post_id, community_event: 'merged'}` (plus `notification_id`, added by `queue_push_notification`).

- [ ] **Step 1: Write File C.** Blocks:
  - **Block 1 `post_community_announcement`**: the post insert (with `naars.broadcast_post = '1'` around it, `system_event = p_system_event`) and the recipient loop of the live `send_community_broadcast`, moved verbatim, the push data being `jsonb_build_object('community_id', …, 'town_hall_post_id', …) || coalesce(p_push_data, '{}')`; returns the bell-row count. No permission check, no cap.
  - **Block 2 `send_community_broadcast`** (same signature): the live checks and the D14 cap with one added condition `and t.system_event is null`, then `return public.post_community_announcement(p_community_id, v_uid, p_title, p_body, coalesce(p_pinned, false), v_type, null, '{}'::jsonb);`. Behaviour is otherwise unchanged (probes `broadcast_cap`, `broadcast_push` prove it).
  - **Block 3 `merge_communities`** (definer, revoked from client roles), one plpgsql body inside `begin … exception when lock_not_available then return {success: false, error: 'Busy, try again', code: 'rate_limited'} end`, with `set_config('lock_timeout', '5s', true)`. Let S = survivor, M = merged. Steps, in this order:
    1. Lock both community rows `for update` in id order; both unarchived, else `proposal_closed`.
    2. Members of M, by M status (`ROLE` maps owner and admin → `admin`, member → `member`; rank owner > admin > member):

       | M row | S row | Result in S |
       |---|---|---|
       | active | none | insert active, `ROLE(m)`, M's `joined_at`, `activated_at`, `notifications_muted`, `muted_until` |
       | active | active | role = the higher of S's role and `ROLE(m)` |
       | active | pending or left | update to active, `ROLE(m)`, `activated_at = M's` |
       | active | removed | unchanged; `perform public.unwind_member_requests(M, user)` before content moves |
       | pending | none | insert pending with M's `heard_about`, `join_reason`, `invited_by` |
       | pending | any | unchanged |
       | left or removed | any | unchanged |

       Inserts and updates run with `naars.suppress_approval_notice = '1'` (the `create_community` idiom), reset after. M's rows are left as they are (history; `get_my_community_merges` reads them). `profiles.primary_community_id = S` where it was M for every person moved.
    3. Content, with `set_updated_at_rides`, `set_updated_at_favors`, `set_updated_at_town_hall_posts` disabled around these three updates and re-enabled in the same body (the `20261017_0001:1030-1038` idiom, so completed history keeps its dates): `rides`, `favors`, `town_hall_posts` `set community_id = S where community_id = M`; then `xp_events`, `notifications`, `reports` (`community_id` only; `reported_community_id` stays M) the same.
    4. `community_invites set revoked_at = now() where community_id = M and revoked_at is null`.
    5. `communities` M: `archived_at = now(), archived_by = p_actor, merged_into_id = S, merged_at = now(), updated_at = now()` (this fires `recompute_flags_on_archive`, after step 2). Events: M `'archived'` with reason `'merged into ' || S`; S `'merged'` with reason `'merged ' || M name || ' (' || M || ')'`.
    6. Proposal `status = 'accepted', decided_at = now(), decided_by = p_actor`.
    7. `perform public.post_community_announcement(S, p_actor, 'Communities merged', <from name> || ' and ' || <to name> || ' are now one community: ' || <S name> || '.', false, 'announcement', 'community_merged', '{"community_event": "merged"}')`.
    8. Return `{success: true, survivor_id, merged_id}`.
  - **Block 4 `search_merge_targets`**: caller an active owner of `p_community_id` else `not_owner`; query trimmed, fewer than 2 characters → `[]`; rows: unarchived, not default, not `p_community_id`, not merged, and either discoverable with a name containing the query, or hidden (`not is_public`) with `lower(btrim(name)) = lower(q)` exactly; test communities only for their members and platform admins; exact matches first, then name; limit 20.
  - **Block 5 `propose_community_merge`**: `pg_advisory_xact_lock` on both ids (smaller first); `update … set status = 'expired'` for pending rows of either community past `expires_at`; refusals: caller not an active owner of `p_community_id` → `not_owner`; same id, survivor not one of the two, note over 300, other missing, archived or merged → `invalid`; either is the default community → `default_community`; a pending proposal involving either → `merge_pending`; a proposal between the two, either direction, declined within 7 days → `recently_declined`. Insert; every active owner of the other community gets `notify_user_in_community(owner, 'announcement', 'Merge proposal from ' || <from name>, <from name> || ' proposes making ' || <from name> || ' and ' || <to name> || ' one community: ' || <survivor name> || '. Open Manage in ' || <to name> || ' to accept or decline.', p_other_id, true, '{}', v_uid)` (bell row and push).
  - **Block 6 `get_community_merge_proposal`**: active owner of `p_community_id` or platform admin, else `not_owner`; the pending, unexpired proposal with that community as `from` (`direction 'outgoing'`) or `to` (`'incoming'`), or `null`.
  - **Block 7 `respond_to_community_merge`**, refusals in this order: lock the proposal `for update`; not pending, or past `expires_at` (then set `expired`) → `proposal_closed`; either community archived → set `withdrawn` and `proposal_closed` (checked before the role, because an archived community answers no role); caller not an active owner of `to_community_id` → `not_owner`; decline → `declined`, `decided_*`, and the proposer community's owners get a bell row without push `'Merge declined'` / `<to name> || ' declined merging with ' || <from name> || '.'`; accept → `return public.merge_communities(p_proposal_id, v_uid)`.
  - **Block 8 `withdraw_community_merge`**: active owner of either community; not pending → `proposal_closed`; `withdrawn`, `decided_*`; the other community's owners get a bell row without push `'Merge proposal withdrawn'` / `<caller community name> || ' withdrew the merge proposal.'`.
  - **Block 9** `get_my_community_merges`: communities with `merged_into_id` not null, `merged_at > now() - interval '90 days'`, where the caller has a `community_members` row with `status = 'active'`, joined to the survivor's name; and `get_platform_communities` re-created with `merge_proposals` = every proposal pending or decided within 30 days: `{id, from_id, from_name, to_id, to_name, survivor_id, survivor_name, status (pending past expires_at reads 'expired'), note, created_at, expires_at, decided_at}`, newest first.
- [ ] **Step 2: Probe block `community_merge`** (probe_world; C2 owner u(12) and C3 owner u(14); members built in the block: u(3) active in both C2 and C3 as member in C2 and admin in C3; u(7) removed from C2 and active in C3 with an open ride; u(5) pending in C3; u(11) active in C3 with mute on; u(12) also a plain member of C3; u(14) owner of C3; a completed C3 ride with an `updated_at` 10 days ago; an open C3 favor claimed by u(11); a C3 post and comment; a live C3 invite):
  - u(3) proposing with `p_community_id = c(2)` → `not_owner`; u(12) proposes (`c(2)`, other `c(3)`, survivor `c(2)`, note 'Probe note') → success; a second proposal by u(14) for C3 with C1 → `merge_pending`; u(14) got one `announcement` bell row and one `notification_queue` row; `get_community_merge_proposal(c(3))` for u(14) is `incoming`, `get_community_merge_proposal(c(2))` for u(12) is `outgoing`; u(3) reading either gets `not_owner`.
  - u(14) declines; u(12) proposes again → `recently_declined`; the decline's `decided_at` moved back 8 days (owner update) → propose succeeds; withdraw by u(14) → `withdrawn`; propose again; expire it (owner sets `expires_at` in the past) → respond → `proposal_closed` and status `expired`; propose again; u(14) accepts → `{success, survivor_id: c(2), merged_id: c(3)}`.
  - Afterwards in C2: u(14) admin, u(3) admin (higher of member and admin), u(5) pending, u(11) active with mute on, u(7) still removed and their unclaimed C3 ride deleted (what `unwind_member_requests` does to an unclaimed request), u(12) still the only owner; the C3 ride, favor and post now in C2; the completed ride's `updated_at` unchanged; the favor still claimed by u(11); the C3 invite revoked; C3 archived with `merged_into_id = c(2)`; one `merged` event on C2; every active member of C2 except u(14) (the accepter) and u(11) (muted, as the broadcast loop skips) has exactly one new `announcement` bell row naming both communities and a queue row whose data has `community_event = merged`; `send_community_broadcast(c(2), …)` by u(12) succeeds three times afterwards (the system post did not count); `get_my_community_merges()` for u(11) maps C3 → C2; `get_community_preview(c(3))` for u(13) answers `merged` with `merged_into_id = c(2)`; `get_platform_communities()` lists the proposal with status `accepted`.
  - `default_community`: u(12) proposing C2 with the default community → refused.
  - **One owner of both:** C6 = `probe_community(6, 'Probe Six', u(12), false, 'invite')` (u(12) owns C2 and C6); u(12) proposes (`c(6)`, other `c(2)`, survivor `c(2)`) → success; u(12) accepts as owner of C2 → `{success, survivor_id: c(2), merged_id: c(6)}`; u(12) still has exactly one C2 row, role `owner`; C6 archived with `merged_into_id = c(2)`.
  - An archived side: C5 = `probe_community(5, 'Probe Five', u(13), true, 'approve')`; u(4) proposes C1 into C5; the owner archives C5 (`archived_at = now()`); u(13) accepting → `proposal_closed`, the proposal reads `withdrawn`, C1 unchanged.
- [ ] **Step 3: Dry-run script, structural check (N = 4), dry run.** Expected: four OK rows and `DRYRUN 20261021_0022 OK`.
- [ ] **Step 4: Apply** blocks 1-9 with `short` after each (Block 2 is followed by `broadcast_cap` and `broadcast_push` too); then `community_merge`. Expected: all OK.
- [ ] **Step 5: Header** APPLIED (rollback: Blocks 2 and 9's `get_platform_communities` from P1 through the MCP; the others `drop function` in the SQL editor; no merge can be undone by rollback, say so).
- [ ] **Step 6: Commit** (`supabase/migrations/20261021_0022_community_merge.sql`, `supabase/dryruns/20261021_0022_community_merge.dryrun.sql`, `supabase/probes/communities_probe.sql`) `[R2-S3] Merge proposals and the single-transaction merge`.

---

### Task S4: File D — example content rules and the daily refresh

**Files:**
- Create: `supabase/migrations/20261021_0023_example_content.sql` (blocks 1-7), `supabase/dryruns/20261021_0023_example_content.dryrun.sql`
- Modify: `supabase/probes/communities_probe.sql` (block `example_content`)

**Interfaces:**
- Produces: `set_example_content(p_type text, p_id uuid, p_is_example boolean) returns jsonb` (authenticated, service_role; platform admins only) → `{success, changed}`; `refresh_example_requests() returns integer` (no client grant); cron job `refresh-example-requests` at `10 11 * * *` (11:10 UTC daily, about 3-4 AM Pacific, away from the 03:15 UTC expiry job).

- [ ] **Step 1: Write File D.** Blocks 1-4 are derive edits (exact passage found once, md5 before and after):
  - **Block 1** `notify_new_ride()` and `notify_new_favor()`: after their `BEGIN`, `IF NEW.is_example THEN RETURN NEW; END IF;`.
  - **Block 2** `notify_town_hall_post()`: the same guard first in its body.
  - **Block 3** `record_xp_on_request_created()`: the same guard first (an example earns no XP, so the test account never leads a leaderboard).
  - **Block 4** `expire_past_open_requests()`: `and not r.is_example` and `and not f.is_example` after each `status = 'open'` condition.
  - **Block 5** `set_example_content`: not a platform admin → `{success: false, error: 'Not authorized - admin access required'}`; `p_type` in `ride`, `favor`, `town_hall_post` else `code 'invalid'`; updates `is_example` (a definer write, so the S1 guard allows it); `changed` true when a row changed.
  - **Block 6** `refresh_example_requests()` (definer, `volatile`): for every ride and favor with `is_example` and `hidden_at is null`, with `v_tomorrow := (now() at time zone coalesce(<row>.timezone, 'America/Los_Angeles'))::date + 1`, set `date = date + 7 * ceil((v_tomorrow - date) / 7.0)::int` when `date < v_tomorrow` (same weekday, lands in `[v_tomorrow, v_tomorrow + 6]`), and `status = 'open', claimed_by = null` where status is not open or `claimed_by` is set; returns the number of rows changed. No trigger is disabled (examples cannot be claimed, so the reopen branch is a safety net; if it fires, the status trigger may tell the test account).
  - **Block 7** `select cron.schedule('refresh-example-requests', '10 11 * * *', $$select public.refresh_example_requests()$$);` then `select public.refresh_example_requests();` once.
- [ ] **Step 2: Probe block `example_content`**: as the owner, an example ride by u(12) in C2 inserted with `is_example` → no `notifications` row for C2's members and no `xp_events` row; the same insert without the flag → bell rows as today (control); an example post → no "New in Town Hall" row; an open example ride dated 20 days ago and a non-example one → `expire_past_open_requests()` completes only the non-example; `refresh_example_requests()` moves the example to a date in `[tomorrow, tomorrow + 6]` (Los Angeles) with the same `extract(dow)`; a second call returns 0; a completed example becomes open with no helper; the platform admin subject's `set_example_content('ride', <id>, false)` → `changed = true`; the member subject → refused; `cron.job` has `refresh-example-requests` with schedule `10 11 * * *` (checked outside the savepoint, read only).
- [ ] **Step 3: Dry-run script, structural check (N = 2), dry run** (Block 7's `cron.schedule` inside the rolled-back transaction leaves no job; verify `cron.job` afterwards).
- [ ] **Step 4: Apply** blocks 1-7 with `short` after each; then `example_content`, `owner_notifications`, `reputation`. Expected: all OK.
- [ ] **Step 5: Header** APPLIED (rollback: Blocks 1-4 the P1 text through the MCP; Block 5-6 `drop function` and Block 7 `select cron.unschedule('refresh-example-requests')`, SQL editor).
- [ ] **Step 6: Commit** (`supabase/migrations/20261021_0023_example_content.sql`, `supabase/dryruns/20261021_0023_example_content.dryrun.sql`, `supabase/probes/communities_probe.sql`) `[R2-S4] Example content never notifies, earns XP or expires; daily refresh`.

---

### Task S5: Test data — Test Community's area, the test flags, and the example content

**Files:**
- Create: `supabase/scripts/2026-10-21_release2_test_data.sql` (a one-off data script, not a migration; header NOT APPLIED → APPLIED with outcomes)
- Modify: `Docs/qa/test-data.md` (areas, `is_test`, NC Test Neighbor, the example content and how to hide it)

**Interfaces:**
- Consumes: S1-S4 live; P5.
- Produces: Test Community `area_name 'Seattle'`, center `47.6062, -122.3321`, radius 10; Test Public A `'Capitol Hill, Seattle'`, `47.6253, -122.3222`, 1; Test Public B `'Bellevue'`, `47.6101, -122.2015`, 2; `is_test = true` on the four test communities; NC Test Owner and NC Test Neighbor active members of Test Community; 8 example requests, 3 example posts, 1 comment and 2 answered questions.

- [ ] **Step 1: Write the script**, one transaction. Part A (read only, raises and stops on any mismatch): resolve the two accounts and five communities by name and id prefix (P5); assert Test Community has no `is_example` row yet; assert the columns the inserts name exist (`request_qa`: `ride_id, favor_id, user_id, question, answer`; `town_hall_comments`: `post_id, user_id, content`). Part B: the area and flag updates above (`update … where id = <resolved>`). Part C: for each test account without an active Test Community row, `naars.suppress_approval_notice = '1'`, insert `community_members (…, 'member', 'active', activated_at = now())`, reset, and an `'approved'` event with reason `'example content account'`. Part D, rows with `community_id` = Test Community, `is_example = true`, timezone `America/Los_Angeles`, status `open`, poster NC Test Owner, dates `current_date (Los Angeles) + <day>`:

  | # | Kind | Day | Time | From / title | To / location | Seats or duration | Notes, description or gift |
  |---|---|---|---|---|---|---|---|
  | 1 | ride | 2 | 10:00 | Ballard Branch Library | Pike Place Market | 1 | "Meeting a friend for lunch. Happy to chip in for parking." |
  | 2 | ride | 3 | 06:30 | Westlake Station | Seattle-Tacoma International Airport | 1 | "Early flight, one carry-on." |
  | 3 | ride | 5 | 18:30 | Capitol Hill Station | Seattle Center | 2 | "Two of us going to a show." |
  | 4 | ride | 6 | 09:00 | Green Lake Park | University of Washington Station | 1 | gift "Coffee on me" |
  | 5 | favor | 1 | — | Pick up a box of apples at the farmers market | Ballard Farmers Market | `under_hour` | "Any stall with Honeycrisp apples is fine." |
  | 6 | favor | 4 | 14:00 | Return two library books | Seattle Central Library | `under_hour` | "They're due Friday." |
  | 7 | favor | 5 | — | Help carry folding chairs for a picnic | Gas Works Park | `couple_hours` | "About twenty chairs from the parking lot to the lawn." |
  | 8 | favor | 7 | 11:00 | Walk with me to the plant sale | Volunteer Park | `couple_hours` | gift "A tomato start for your garden" |

  Posts (NC Test Owner, `is_example`): a pinned `announcement` "Welcome to Test Community" / "This is the example community for exploring Naar's Cars. The rides, favors and posts here are examples: open them to see how a request, its questions and its answers look. Real neighborhoods have their own communities; search for yours in Explore."; a `user_post` "Is the Ballard Farmers Market open on holidays?" with one comment by NC Test Neighbor "It's open every Sunday, holidays included."; a `user_post` "Thank you to whoever helped carry the chairs at Gas Works Park last weekend!". Q&A (asker NC Test Neighbor, answered in the same insert): on ride 2 "How much luggage will you have?" / "One carry-on and a backpack."; on favor 5 "Which stall do you usually buy from?" / "Any stall with Honeycrisp apples is fine.". Around the comment and Q&A inserts, `alter table public.town_hall_comments disable trigger on_town_hall_comment_notify; alter table public.request_qa disable trigger on_qa_created_notify;` and the matching `enable` right after (inside the transaction, so no other session ever sees them disabled). Part E (read only): counts of example rows (8, 3), Q&A (2), comments (1); `notifications` rows created in this transaction (0); `xp_events` rows for the new ids (0); both triggers `tgenabled = 'O'`.
- [ ] **Step 2: Ask the owner for the go-ahead** (it writes to Test Community, where 19 real members are; they receive nothing). Record the answer in the script header.
- [ ] **Step 3: Run** the script through one `execute_sql` (owner's SQL editor if the MCP declines the trigger statements). Expected: Part E prints 8, 3, 2, 1, 0, 0 and both triggers enabled.
- [ ] **Step 4: Verify as visitors:** `get_community_preview(Test Community)` as anon lists the open examples with `is_example = true` and the welcome post; `search_communities_by_name('test')` as anon returns Test Community and none of the four test communities; `find_communities_near(47.6062, -122.3321)` as anon returns Test Community with `distance_miles` 0.0.
- [ ] **Step 5: Update** `Docs/qa/test-data.md` (Test Community's area and example content and how platform admins hide it; the four flags; NC Test Neighbor's display name and id prefix only) and the script header (APPLIED, outcomes). **Commit** (`supabase/scripts/2026-10-21_release2_test_data.sql`, `Docs/qa/test-data.md`) `[R2-S5] Test Community area and example content; test communities flagged`.

---

### Task S6: Full probe run and closing the headers

**Files:** the four migration headers; `supabase/probes/communities_probe.sql` (none if unchanged).

- [ ] **Step 1:** Run the whole probe file through the MCP, PARAMETERS and HELPERS with each group of blocks (the R1 G1 split; `posts_delete_policy` and `storage_private` are the owner's SQL-editor blocks). Expected: every `PROBE … OK`, last row `PROBE ALL OK` from the owner's run.
- [ ] **Step 2:** `has_function_privilege('anon', …, 'execute')` is true for `search_communities_by_name(text)`, `find_communities_near(double precision, double precision)`, `get_community_preview(uuid)` and false for every other new function; `select count(*) from public.community_listing_events` and `…merge_proposals` as `authenticated` raises 42501.
- [ ] **Step 3:** Record the outcomes in each header and commit (the four `supabase/migrations/20261021_002*.sql` files, and `supabase/probes/communities_probe.sql` if it changed) `[R2-S6] Release 2 server: full probe run`.

---

## New files

| Path | Task |
|---|---|
| `supabase/migrations/20261021_0020_discovery_schema.sql` | S1 |
| `supabase/migrations/20261021_0021_discovery_rpcs.sql` | S2 |
| `supabase/migrations/20261021_0022_community_merge.sql` | S3 |
| `supabase/migrations/20261021_0023_example_content.sql` | S4 |
| `supabase/dryruns/20261021_0020_discovery_schema.dryrun.sql` … `0023_example_content.dryrun.sql` (four) | S1-S4 |
| `supabase/scripts/2026-10-21_release2_test_data.sql` | S5 |

## Interfaces Release 3 relies on

- Columns: `communities.area_name / area_center_lat / area_center_lng / area_radius_miles` (the fallback circle of the area trigger, spec 4.4 step 2), `is_test`, `merged_into_id`, `merged_at`; `rides / favors / town_hall_posts.is_example` (Release 3's `member_rides` / `member_favors` views and the guest views carry it; Release 3's `help_with_request` refuses an example with `{success: false, code: 'example'}`, so the text `example_request` stays only in `guard_example_content`'s refusal of a direct claim UPDATE, and the iOS `ClaimService.isExampleRefusal(_:)` is removed by Release 3 iOS Task 4); `town_hall_posts.system_event`.
- `great_circle_miles(…)` and `can_discover_community(uuid)` for any later distance or visibility rule.
- `join_policy` still `invite | approve`; Release 3b widens the CHECK to `'open'`, which `communities_hidden_not_open` then binds; `update_community_access` and `create_community_with_area` accept `'open'` only after 3b (the policy list is one line in each).
- `merge_communities` moves `rides`, `favors`, `town_hall_posts`, `xp_events`, `notifications`, `reports`; Release 3 must add `request_offers` to it in the same change that creates them (Release 3 SQL D10); request threads link to their request by id and follow it.
- Row shapes as listed in S2 and S3 Interfaces; keys are only ever added.

## Self-review notes

- **Spec coverage.** 4.1 (two switches, CHECK, owner-only RPC, bell row to members, hidden keeps approval): S1 Block 1, S2 Blocks 5-6. 4.2 (area columns, search by name and place, guest-callable, great-circle, not stored or logged, nearby check with server re-check and required reason, re-run on listing and area move, platform list and bell row): S1 Blocks 1-2, 6; S2 Blocks 1-5, 8. 4.10 (Test Community area 10 mi, `is_test`): S1 Blocks 7-9, S5. 4.11 (columns, platform-admin-only flag, refresh on pg_cron, expiry and notification exemptions, content list, refused claim, guests see them): S1 Blocks 5, 10; S4; S5. 4.12 (proposal table, propose / respond / withdraw / 7-day expiry / one pending, the transaction, roles, content, mutes, archive with notice, invites stop, announcement outside the cap, Admin → Communities): S3.
- **Decisions the owner can veto.** (1) The listing reason lives in `community_listing_events`, not a `communities` column, so it is never readable through the table guests read, and each listing or area move keeps its own reason. (2) A merged community's invite codes are revoked, not moved (the spec says both; codes stopping is the safer reading). (3) A person removed from the survivor stays removed and their requests in the merged community are unwound. (4) The default community cannot be merged in either role. (5) A declined pair cannot be proposed again for 7 days; withdraw has no cool-down. (6) Example rows earn no XP and example posts never notify (the spec names only the request trigger). (7) The search distance is rounded to 0.1 mile. (8) `set_community_public` refuses to list a community without an area (spec "Hidden → listed needs a service area"); a platform admin on a Release 1 build sees the Create "allow guests" step fail. (9) The id-gated guest reads (`get_community_leaderboard`, `get_community_spotlights`, `get_profile_stats`, `get_user_badges`, `get_user_stats`, `is_user_approved`) still answer for a test community whose id a guest already has; no listing exposes those ids. (10) NC Test Neighbor, a second test account, asks the seeded questions and writes the comment, so no example is a conversation with oneself. (11) The seed runs as the table owner with NC Test Owner as the author of every row, not under the test account's own session: the S1 guard refuses `is_example` from any non-admin client, so the rows cannot be written through the test account's JWT; notices are suppressed as `create_community` does (`naars.suppress_approval_notice` for the memberships) and by the example rules of File D plus the two in-transaction trigger disables for the comment and the questions. (12) `update_community`, which Release 1 and Phase 5a builds call from Settings, still changes `join_policy` without the members' announcement; only `update_community_access` (Release 2 builds) tells members. Adding the announcement to the live RPC would change what old builds' owners trigger; the gap closes as old builds age out.
- **Not in this plan:** the iOS client (companion plan); area columns on requests, offers, request threads, the cool-off, `'open'` (Release 3).
