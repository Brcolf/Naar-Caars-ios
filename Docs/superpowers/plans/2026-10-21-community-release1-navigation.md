# Community Release 1 (navigation shell, today's behaviour) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the four-tab shell plus the iOS 26 Explore search tab, a page for every community, Town Hall without the leaderboard switch, a slimmer Profile, the "Look around first" Welcome, the merged Requests feed with include/exclude chips and a policy chip on every card, the Helping tile and the two push behaviours, with no change to claims, addresses or messaging.

**Architecture:** `MainTabView` moves from `.tabItem` to the `Tab` API with `NavigationCoordinator.Tab` as the selection (`.townHall` renamed from `.community`, `.explore` added; Explore has no refresh domain). Explore is a thin root (`ExploreView`) around today's `MyCommunitiesView`, which becomes the before-search content and takes over the community-admin intents from Profile; every community opens `CommunityPageView`, which reads a member's row from `CommunityContext` and everyone else's view through one new definer RPC, `get_community_preview`. The only server work is one additive migration (the RPC, signed-in visitors reading members and reviews of listed communities as guests already do); no SwiftData model, sync engine, notification type, `RefreshCoordinator` trigger or messaging file changes.

**Tech Stack:** Swift 6.3 toolchain in Swift 5 mode, SwiftUI (`Tab`, `TabRole.search`, `tabBarMinimizeBehavior`), XCTest, Xcode 26.6 / iOS 26.5 SDK, Supabase (PostgreSQL definer functions, RLS), the Supabase MCP.

**Spec:** `Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md` (4.3, 4.6, 4.9, 4.10 "Release 1"; where it differs from the mockups `build/design/mockups/navigation-mockups.html` S1-S8, the spec wins). Read both, and CLAUDE.md, before a task.

## Global Constraints

- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `SWIFT_VERSION = 5.0`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. No build-setting, permission, entitlement, Info.plist key or SDK change in this release (the location permission is Release 2).
- **Today's behaviour.** Claims, unclaims, addresses, the request detail screens, Q&A, messaging (UIKit and SwiftUI), the bell sheet, push delivery and the badge RPC are unchanged. `git diff --stat <R1 base>..HEAD -- NaarsCars/Features/Messaging NaarsCars/UI/Components/Messaging NaarsCars/Core/Storage NaarsCars/Core/Services/RefreshCoordinator.swift NaarsCars/Core/Services/RealtimeManager.swift NaarsCars/Core/Services/ClaimService.swift` is empty at the gate.
- **A Phase 5a build sees no difference.** The server change is additive (new names; two read widenings for screens such a build cannot reach). No RPC it calls changes signature or answer.
- **RefreshCoordinator.** No new trigger and no new coordinator call. `MainTabView.onChange(of: selectedTab)` stays the single caller of `setVisibleDomain`; Requests → `.dashboard`, Messages → `.conversations`, Town Hall → `.townHall`, Profile and Explore → `nil`. Joins and leaves reuse the sanctioned `forceFullRefreshAndWait(.dashboard, trigger: "joinedCommunity" / "leftCommunity")` inside `MyCommunitiesViewModel`. A tab appearance shows what is stored; Explore's own reads (`get_my_memberships`, limits, the listed list) run at most once per `Constants.Timing.refreshStalenessWindow` (30 s) except on pull-to-refresh.
- **WebSockets.** The teardown stays keyed to leaving the Messages tab (`old == .messages && new != .messages` → `MessagingSyncEngine.shared.cancelGracePeriodAndUnsubscribe()`).
- **Push routing** only through `pendingIntent` / `deferNotificationIntent()`; the bell stays a sheet and applies its deferred intent on dismiss. Every view that consumes `pendingIntent` replays an intent set before it existed (`.onChange(of:initial: true)`, once per view lifetime, one main-actor turn later), as `RequestsDashboardView.swift:125-146` does. Never a value-based `NavigationLink` inside a pushed screen; item-driven destinations only (CLAUDE.md, Phase 3).
- **Guest gating.** Every new auth-required control (invite code, Start a community, Ask to join, Report, saved code Use) shows `GuestSignInPromptView` for a guest and never calls a community RPC; the server already refuses anon on every such RPC. The two new functions are anon-callable: `get_community_preview` (read-only, listed communities only) and `is_listed_request` (a boolean a guest can already derive from the guest views).
- **Notification registry:** unchanged at 34 types; `scripts/validate-notification-types.sh` still prints "34 types in sync". No new `NotificationType`, no SQL CHECK change.
- **SwiftData trio:** untouched (no model, mapper or sync-engine change).
- **RLS is the boundary.** Visitors read a community only through `get_community_preview` (SECURITY DEFINER, `search_path = ''`, listed and unarchived only, no address, note or description column). Screens only explain.
- **ViewModels:** new ones are `final class … : ObservableObject` + `@MainActor` (`CommunityPageViewModel`); none subscribes or touches a repository in `init`; no migration between `ObservableObject` and `@Observable`.
- **Design system** (`Docs/design-system/README.md`): `ColorTheme` tokens only; tags through `NaarsChip` (the policy chip is a `NaarsChip`), counts through `NotificationBadge`, cards through `.cardStyle()`, failures through `.errorBanner(message:)` or a `.warning` toast, notices through an `.info` toast; `.glassEffect` only on the community page's floating join bar (the sixth glass surface); every scrolling screen on `Color.naarsBackground`; no root-level `.tint`. Every interactive element has an `accessibilityLabel`; new identifiers are listed per task.
- **Strings** are keys in `NaarsCars/Resources/Localizable.xcstrings` with `en`, `es`, `ko`, `vi`, `zh-Hans`, `zh-Hant`, added **only** with `python3 -I scripts/add-localization-keys.py build/R1-T<n>-keys.json` (the implementer writes the five machine translations in the tone of neighbouring keys and keeps `%@`, `%lld`, `%1$@`). A changed sentence is a new key; existing keys are never edited or removed. Counts use `<key>_one` / `<key>_other`. **Never commit Xcode's auto-extraction noise:** if a build leaves the catalog changed beyond the task's keys, `git checkout -- NaarsCars/Resources/Localizable.xcstrings` and re-run the script.
- **Public repository.** No personal data (names, emails, ids beyond the first 8 characters already in `Docs/qa/test-data.md`) in any committed file, capture or fixture.
- **New Swift files** go through the Xcode MCP: open this worktree's `NaarsCars/NaarsCars.xcodeproj`, `XcodeListWindows`, confirm the workspace path, `XcodeLS` the group, `XcodeWrite`. When the MCP is unavailable, the type goes into the fallback file named in the New files table (same target) and the task says so. Never hand-edit `project.pbxproj`; let Xcode go idle before a Lane B build.
- **SQL:** all new SQL is in `supabase/migrations/20261021_0001_community_preview.sql`, applied by the orchestrator one `apply_migration` per block through the Supabase MCP, after a rolled-back dry run. The MCP declines `DELETE`, `DROP POLICY`, `DROP FUNCTION`, `DROP TABLE` and auth/storage deletes: such statements (only the rollback here) go to the owner's SQL editor, never rephrased. Agents executing iOS tasks never write under `supabase/`.
- **One simulator at a time on the 8 GB Mac.** Unit tests run on the never-signed-in `iPhone 16 Tests` device (the owner's `iPhone 16` and the `iPhone 17 (26.5)` hold signed-in sessions); never run `RideServiceTests`, `FavorServiceTests`, `TownHallServiceTests` on a signed-in device. Shut a device down by UDID, never `shutdown all`.
- Every task ends with a green Lane B build, its tests passing and one commit whose subject starts `[R1-T<n>]` and whose body ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (the orchestrator's line; an executing session whose harness gives another attribution line uses that one). **Staging:** `git add` exactly the task's **Files** paths, plus `NaarsCars/Resources/Localizable.xcstrings` when the task added keys and `NaarsCars/NaarsCars.xcodeproj/project.pbxproj` when it created or removed a file (each commit step names which of the two it adds); never `git add -A` or a directory; tasks never push.

### Commands (`<n>` is the task number)

```bash
# BUILD. Expected: exit=0, no "error:" line, and no "warning:" naming a touched file that build/R1-baseline-build.log lacks.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build > build/R1-T<n>-build.log 2>&1; echo "exit=$?"; grep -n "error:" build/R1-T<n>-build.log | head -20

# RED (compile-level failing test). Expected: exit≠0 and the named compile error.
xcodebuild build-for-testing -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Tests' -derivedDataPath build/DerivedData -quiet > build/R1-T<n>-red.log 2>&1; echo "exit=$?"; grep -n "error:" build/R1-T<n>-red.log | head

# TEST <ONLY> (-only-testing:NaarsCarsTests/<Class>[/<method>] …). Expected: exit=0, 0 failures.
rm -rf build/R1-T<n>.xcresult; xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Tests' <ONLY> -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/R1-T<n>.xcresult -quiet > build/R1-T<n>-test.log 2>&1; echo "exit=$?"; xcrun xcresulttool get test-results summary --path build/R1-T<n>.xcresult

# FULL = the same without <ONLY>, result bundle build/R1-T<n>-full.xcresult. Expected: 0 failures, skips only in the session-gated classes.
# RELEASE = Release build for the simulator into build/DerivedData. Expected: exit=0, no "error:" (catches DEBUG-only names outside #if DEBUG).
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Release -derivedDataPath build/DerivedData -quiet build > build/R1-T<n>-release.log 2>&1; echo "exit=$?"
# PREVIEWGUARD <files>. Expected: no output.
awk 'FNR==1{d=0} /^#if DEBUG/{d=1} /^#endif/{d=0} /^#Preview/{if(!d) print FILENAME":"FNR": #Preview outside #if DEBUG"}' <files>
# CAPTURE <view file> = RenderPreview (Lane A) of each #Preview in the file three times: no override,
# {"Color Scheme": "Dark Appearance"}, {"Dynamic Type": "AX 5"}; copy the PNGs to build/R1-T<n>-captures/ and inspect each
# (clipped or truncated text, overlapping chips or badges, dark contrast). Fallback when Xcode cannot render: Lane B
# screenshots on "iPhone 16 Tests" with `simctl ui <udid> appearance dark` and `content_size accessibility-extra-extra-extra-large`, reset after.
```

`FULL` runs at the end of Tasks 4, 8 and in the gate; `RELEASE` at the end of Tasks 5, 6 and in the gate. Each task report records executed / passed / skipped.

### Task index

| Task | Deliverable | Risk |
|---|---|---|
| 1 | Server: `get_community_preview`, listed members' profiles and reviews readable by signed-in visitors; probes (orchestrator) | medium |
| 2 | Join policy display (`.open`, chip, subtitle, rule sentence), `CommunityPolicyChip`, `CommunityMonogram`, `CommunityContext` listed communities and `joinPolicy(for:)` | low |
| 3 | `CommunityPreview` model, `fetchCommunityPreview`, the `not_listed` refusal, stubs | low |
| 4 | Tab API migration, Explore tab and routing: community-admin intents open on Explore, Profile loses My communities, Explore badge | high |
| 5 | Community page (member, pending, visitor, unavailable) with the leaderboard pinned to the community | medium |
| 6 | Explore content: rows open the page, listed communities, Have an invite code?, Start a community, guest prompts, 30 s re-entry rule | medium |
| 7 | Town Hall tab: rename, leaderboard switch gone, title menu with About and Find, "Now in <community>" | medium |
| 8 | Requests filter model: `RequestsScope.excluding`, toggle and normalisation, open counts, header rules | medium |
| 9 | Requests screen: chips row, title menu with counts, About and Find, policy chip on cards, Open / Mine / Helping, request-push rule | medium |
| 10 | Profile admin row for platform admins only; Welcome: "Look around first", no "I have an invite code" | low |
| 11 | Drafts: design system, privacy policy, FAQ, App Store review notes | low |
| 12 | Gate, then CLAUDE.md, AGENTS.md and SECURITY.md from its evidence | high |

### Prerequisites outside this plan

1. **Working tree.** At plan time `git status` shows two changes this plan did not make: `project.pbxproj` (`CURRENT_PROJECT_VERSION` 11 → 12, the owner's build bump) and an Xcode re-sort of `Localizable.xcstrings` (6,516 / 6,478 lines). The catalog script refuses a re-sorted file. Before Task 2 the orchestrator asks the owner to commit the bump and to allow `git checkout -- NaarsCars/Resources/Localizable.xcstrings`; nothing is discarded without that answer.
2. **SQL apply.** Task 1 is applied under the owner's standing instruction for the multi-community build; if the orchestrator is not sure it covers this design, it asks before Task 1 Step 4. Task 1 must be live before the gate (Tasks 3-9 use stubs).
3. **Owner decision before release, not before the build: Test Public A and B.** The `is_test` flag is Release 2 (spec 4.10), so in Release 1 Explore's flat list shows "Test Public A" and "Test Public B" to every person (they already appear today in Join a community's public list). Options: set both to hidden (`set_community_public`) until Release 2, or pull `is_test` forward. The gate records the choice.
4. Xcode open on this worktree's project for Tasks 2, 4, 5, 8 (new files); idle during builds.
5. **Gate devices:** the owner's `iPhone 16` (their platform-admin account, member of Test Community), the `iPhone 17 (26.5)` signed in as NC Test Owner (owner of the four test communities, `Docs/qa/test-data.md`), and `iPhone 16 Tests` (never signed in) for unit tests and the guest pass. Writes happen only in Test Public A with the owner's go-ahead; nothing is posted in Test Community.

## Review Focus

1. **A community-admin push or bell tap (`pending_approval` with a community, `content_reported` for a community admin, `membership_update` owner) while the app is closed or before Explore was ever shown.** Expected: Explore selected, exactly one push of Requests to join / Reports / Members, intent cleared once, never routed to Profile. Pinned: Task 4 (`testCommunityAdminIntents_TargetExploreTab`, `testDeferredCommunityAdminIntents_SelectExploreTab`, `testExploreRoute_CommunityAdminIntentsMapToTheirScreens`) and Task 12 O6 (cold start).
2. **A stored Requests filter that no longer fits** (a community left or archived, every community excluded, a malformed value). Expected: the feed falls back to All communities, never an empty feed or a crash. Pinned: Task 8 (`testRequestsScope_ExcludingStorageRoundTripAndMalformedValues`, `testRefresh_ExcludingScopeDropsCommunitiesNoLongerActive`, `testRefresh_ExcludingEveryActiveCommunityFallsBackToAll`, `testToggleRequestsInclusion_NeverExcludesTheLastCommunity`).
3. **A hidden, archived or unknown community, a hidden request, a blocked person, or an address reaching a visitor** through the preview or the widened profile and review reads. Expected: never. Pinned: Task 1 probes `community_preview` and `listed_profiles`.
4. **The community page while its load fails, is cancelled, or the membership changes under it** (leave, archive, approval). Expected: a retry state on failure, nothing on cancel, the mode re-resolves. Pinned: Task 5 (`testVisitor_NetworkFailureShowsFailedAndRetryLoads`, `testVisitor_CancelledLoadIsNotAFailure`, `testLeavingAListedCommunity_ReloadsAsVisitor`, `testLeavingAHiddenCommunity_ShowsUnavailable`).
5. **A guest acting on Explore or a community page.** Expected: the sign-in prompt, no membership, limits or join RPC. Pinned: Task 5 (`testGuest_VisitorActionIsSignUp`), Task 6 (`testLoad_GuestLoadsListedOnlyWithoutMembershipOrLimitCalls`) and Task 12 O2.

---

### Task 1: Server — `get_community_preview` and listed members for signed-in visitors

**Executor:** the orchestrator (writes under `supabase/`). **Files:**
- Create: `supabase/migrations/20261021_0001_community_preview.sql` (four blocks)
- Modify: `supabase/probes/communities_probe.sql` (helper `probe_require_release1`, blocks `community_preview` and `listed_profiles`, the `reputation` block)

**Interfaces:**
- Produces: `public.get_community_preview(p_community_id uuid) returns jsonb` (SECURITY DEFINER, `stable`, `search_path = ''`, EXECUTE for `anon`, `authenticated`, `service_role`). Refusal `{"success": false, "error": "Community not found", "code": "not_listed"}`. Success:
  `{"success": true, "community": {id, name, description, join_policy, is_public, is_default, member_count, timezone}, "requests": [{type ("ride"|"favor"), id, title (favor title, null for a ride), date (yyyy-mm-dd), time (text or null), timezone, seats (ride, else null), poster_id, poster_name, poster_avatar_url}], "posts": [{id, type, title, content, created_at, author_id, author_name, author_avatar_url, comment_count}]}`. Keys may be added later (Release 3 adds area keys); none is removed or renamed.
- Produces: `public.is_listed_request(p_ride_id uuid, p_favor_id uuid) returns boolean` (definer, EXECUTE for `anon`, `authenticated`, `service_role`).
- Changes: `public.my_visible_profile_ids()` also returns active members of listed (public, unarchived) communities, so `public_profiles`, `get_profile_stats`, `get_user_badges`, `get_user_stats` and `is_user_approved` answer a signed-in visitor as they answer a guest; the reviews policy "Approved users can view reviews" also admits a review of a visible request in a listed community.

- [ ] **Step 0: Preconditions (read only, MCP `execute_sql`).** P1: `md5(prosrc)` of `my_visible_profile_ids()` is `534c017b224ddef0399887151b4e99ad` (deployed value, `20261017_0001_communities_core.sql:75`; rollback text `:487-504`). P2: `select qual from pg_policies where tablename = 'reviews' and policyname = 'Approved users can view reviews'` equals the `[A23]` expression of `20261017_0002_communities_rls.sql:583-592` (record it in the header as the rollback text). P3: `to_regprocedure('public.get_community_preview(uuid)')` and `to_regprocedure('public.is_listed_request(uuid, uuid)')` are null. P4: `ls supabase/migrations/20261021_*` and `list_migrations` show nothing numbered `20261021_0001`. Any difference: stop and report.
- [ ] **Step 1: Write the migration** with a header in the `20261019_0050` form (NOT APPLIED until Step 6; what it does; what old clients see: nothing, new names and widenings for screens a Phase 5a build cannot reach; that `review-images` objects of such reviews become readable to signed-in visitors through `20261019_0063`'s policy, as they are to guests; rollback per block). Blocks:
  - **Block 1** `my_visible_profile_ids()`: the live body (`20261017_0001:494-503`) with one more arm before `) s where u is not null`:
    ```sql
    union all select m.user_id from public.community_members m
                join public.communities c on c.id = m.community_id
               where m.status = 'active' and c.is_public and c.archived_at is null
    ```
    Same `language sql stable security definer set search_path = ''`; grants unchanged.
  - **Block 2** `is_listed_request(p_ride_id, p_favor_id)`: `exists` a ride with `id = p_ride_id`, `hidden_at is null`, whose community `is_public and archived_at is null`, or the same for a favor with `id = p_favor_id`. `revoke all … from public; grant execute … to anon, authenticated, service_role` (anon too: the policy in Block 3 applies to every role, and Postgres checks EXECUTE when it builds the plan even where the `approved` test is false).
  - **Block 3** `alter policy "Approved users can view reviews" on public.reviews using (…)`: the `[A23]` expression with `or public.is_listed_request(reviews.ride_id, reviews.favor_id)` added inside the parenthesised `or` list.
  - **Block 4** `get_community_preview(p_community_id uuid)`, plpgsql. Refuse (`not_listed`) when the id is null or no community has that id with `is_public and archived_at is null` (a hidden community is refused to its own members too; members use their membership row). `member_count`: active members. `requests`: at most 10, rides and favors of the community with `status = 'open'`, `claimed_by is null`, `hidden_at is null`, `date >= (now() at time zone coalesce(<row>.timezone, c.timezone))::date`, poster not banned, and, when `auth.uid()` is not null, no `blocked_users` row either way between the caller and the poster; ordered by date, time (nulls last), id. No pickup, destination, location, notes, description, gift, flight or cost key. `posts`: at most 5 newest `town_hall_posts` of the community with `hidden_at is null`, author not banned and not blocked either way, `content` cut to 280 characters (`left`), `comment_count` = its comments with `hidden_at is null`. `revoke all … from public; grant execute … to anon, authenticated, service_role`.
- [ ] **Step 2: Probe additions** (`communities_probe.sql`, file conventions of `:1-115`): helper `pg_temp.probe_require_release1(p_probe text)` raising `PROBE <p> FAILED: Release 1 is not live` when `to_regprocedure('public.get_community_preview(uuid)')` is null; header line under "WHEN TO RUN WHAT". Block **`community_preview`** (after `probe_world`; C2 is public, owner u12; C1 private): u12 posts an open future ride and a future favor in C2, a hidden ride, a ride dated three days ago and a post (inserts as `reputation` does at `:1336-1338`). Checks: u3 (not in C2) gets `success = true`, `community.member_count = 1`, both live requests and the post, neither the hidden nor the past ride; no request object has any of the keys `pickup`, `destination`, `location`, `notes`, `description`, `gift` (`jsonb_object_keys`); anon gets the same ids; u12 (not in C1) and u3 (a C1 member) get `code = 'not_listed'` for c(1); `get_community_preview(null)` and `get_community_preview(gen_random_uuid())` answer `code = 'not_listed'` to anon and to u3 without an exception; after `update communities set archived_at = now() where id = c(2)` u3 gets `not_listed`; after u3 blocks u12 (insert into `blocked_users` as u3), u3's preview of c(2) has no request or post by u12. Block **`listed_profiles`**: u3 reads 1 row of `public_profiles` for u12 (public C2 only) and 0 for u14 (private C3 only); `get_profile_stats(u12)` is not empty for u3 and `get_profile_stats(u14)` is; a review of a completed C2 ride (u12 posted, u5 made a C2 member and helped, as in `reputation`) is readable by u3, a review of a completed C3 ride is not; anon reads `select 1 from public.reviews` without an error. **`reputation`** (`:1316-1358`): when Release 1 is live, the "viewer who shares no community" check uses u3 (C1 only, private) instead of u5, and a new check asserts the default member now reads u5's stats (u5 is active in public C2); before Release 1 the block keeps its current checks.
- [ ] **Step 3: Dry run** (one `execute_sql`): `begin;` the four blocks, PARAMETERS, HELPERS without their `commit;`, the blocks `community_preview`, `listed_profiles`, `reputation`, `isolation`, `noop_default`, `short` with each `begin;` / `rollback;` turned into `savepoint probe;` / `rollback to savepoint probe; release savepoint probe;`, `select 'DRYRUN 20261021_0001 OK';`, `rollback;` (the Phase 5 SQL plan's assembly). Expected: every `PROBE … OK` and the DRYRUN row; afterwards P3 still answers null for both names.
- [ ] **Step 4: Apply** with four `apply_migration` calls named `20261021_0001_block_<n>`, each block's text byte for byte; after each, block `short` (PARAMETERS + HELPERS + `short` in one `execute_sql`). Expected: `PROBE short OK` four times.
- [ ] **Step 5: Probes after apply:** `community_preview`, `listed_profiles`, `reputation`, `isolation`, `noop_default`, `short`, one `execute_sql` each with PARAMETERS and HELPERS. Expected: all OK.
- [ ] **Step 6: Header** → `APPLIED 2026-10-2x` with the migration-history versions, `md5(prosrc)` of the three functions (each equal to the text between its delimiters), `md5(qual)` of the reviews policy, the dry-run and probe outcomes, and the rollback: Block 1 the `0001` body, Block 3 the recorded `[A23]` text (both through the MCP), Blocks 2 and 4 `drop function …` (SQL editor, owner).
- [ ] **Step 7: Commit** `[R1-T1] Community preview RPC and listed members readable by signed-in visitors` with the migration and `supabase/probes/communities_probe.sql`.

---

### Task 2: Join policy display, the two badges, and listed communities in `CommunityContext`

**Files:**
- Modify: `NaarsCars/Core/Models/CommunityPayloads.swift:157-160` (`CommunityJoinPolicy`)
- Create: `NaarsCars/UI/Components/Common/CommunityBadges.swift` (fallback: `NotificationBadge.swift`)
- Modify: `NaarsCars/App/CommunityContext.swift` (new state after `:110`, lookups after `:140`, `resetForSignOut` `:268-287`)
- Test: `NaarsCars/NaarsCarsTests/Core/Decoding/CommunityPayloadDecodingTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift` (CommunityContext section `:94-270`)

**Interfaces:**
- Produces: `enum CommunityJoinPolicy: String { case invite, approve, open }` with `var chipText: String`, `var systemImage: String` ("key.fill", "lock.fill", "globe"), `var subtitleText: String`, `var ruleSentence: String`.
- Produces: `struct CommunityPolicyChip: View { let policy: CommunityJoinPolicy; var size: NaarsChip.Size = .regular }` (a neutral `NaarsChip` with the icon; accessibility label `community_policy_accessibility`); `struct CommunityMonogram: View { let name: String; var size: CGFloat = 40 }` with `static func initials(for name: String) -> String`.
- Produces on `CommunityContext`: `private(set) var listedCommunities: [PublicCommunity]`, `func loadListedCommunities() async -> Bool` (true on success; on failure keeps the previous list; never throws), `func joinPolicy(for communityId: UUID?) -> CommunityJoinPolicy?` (the membership's policy, else the listed community's, else nil). `resetForSignOut` empties the list.

Keys (English): `community_policy_open` "Open"; `community_policy_ask_to_join` "Ask to join"; `community_policy_invite_only` "Invite only"; `community_policy_subtitle_open` "Open community"; `community_policy_accessibility` "Join rule: %@"; `community_rule_open` "Anyone nearby can join. Helpers see only the area until a poster accepts them. No phone numbers are shown. Messaging opens when a poster accepts a helper."; `community_rule_ask_to_join` "An admin approves every member. A helper's claim confirms at once."; `community_rule_invite_only` "Members join with an invite code or link. A helper's claim confirms at once."

- [ ] **Step 0:** Prerequisite 1 is settled; `git status --porcelain` is empty. Build `HEAD` into `build/R1-baseline-build.log` (BUILD command) and run FULL once into `build/R1-baseline-full.xcresult`; record executed / passed / skipped (the gate compares against it).
- [ ] **Step 1: Failing tests.**

```swift
// CommunityPayloadDecodingTests
func testJoinPolicy_ParsesServerValuesAndRejectsUnknown() {
    XCTAssertEqual(CommunityJoinPolicy(rawValue: "open"), .open)
    XCTAssertEqual(CommunityJoinPolicy(rawValue: "approve"), .approve)
    XCTAssertEqual(CommunityJoinPolicy(rawValue: "invite"), .invite)
    XCTAssertNil(CommunityJoinPolicy(rawValue: "public"))
}
func testJoinPolicy_ChipSubtitleRuleAndIcon() {   // English literals: the test locale is en
    XCTAssertEqual(CommunityJoinPolicy.approve.chipText, "Ask to join")
    XCTAssertEqual(CommunityJoinPolicy.invite.subtitleText, "Invite only")
    XCTAssertEqual(CommunityJoinPolicy.open.subtitleText, "Open community")
    XCTAssertEqual(CommunityJoinPolicy.approve.ruleSentence, "An admin approves every member. A helper's claim confirms at once.")
    XCTAssertEqual(CommunityJoinPolicy.open.ruleSentence,
                   "Anyone nearby can join. Helpers see only the area until a poster accepts them. No phone numbers are shown. Messaging opens when a poster accepts a helper.")
    XCTAssertEqual([CommunityJoinPolicy.open, .approve, .invite].map(\.systemImage), ["globe", "lock.fill", "key.fill"])
}
func testMonogramInitials() {
    XCTAssertEqual(CommunityMonogram.initials(for: "Ballard Neighbors"), "BN")
    XCTAssertEqual(CommunityMonogram.initials(for: "test community seattle"), "TC")
    XCTAssertEqual(CommunityMonogram.initials(for: "Solo"), "S")
    XCTAssertEqual(CommunityMonogram.initials(for: "   "), "?")
}
// AppLaunchManagerTests (CommunityContext)
func testJoinPolicy_ReadsTheMembershipThenTheListedCommunity()   // A active "approve"; listed [B "invite"] → .approve, .invite; unknown id and nil → nil
func testLoadListedCommunities_KeepsThePreviousListOnFailure()    // stub fetchPublicCommunitiesResult success [B] → true, [B]; then failure → false, still [B]
func testResetForSignOut_EmptiesListedCommunities()
```
- [ ] **Step 2: RED.** Expected: "type 'CommunityJoinPolicy' has no member 'open'".
- [ ] **Step 3: Implement** the policy members (text through the keys above), the two views (`CommunityMonogram`: initials of the first two words, uppercased, in `Font.naarsHeadline` on a circle of `Color.naarsPrimary.opacity(0.12)`, text `.naarsPrimary`, `accessibilityHidden(true)`), and the context members; `loadListedCommunities` calls `service.fetchPublicCommunities()` and treats `CancellationError` / `URLError.cancelled` as a quiet failure. Add the keys with the script. `#Preview`s for both views (three policies; three names).
- [ ] **Step 4: GREEN.** BUILD; TEST `CommunityPayloadDecodingTests`, `AppLaunchManagerTests`, `CommunityServiceTests`. Expected: 6 new tests pass. CAPTURE `CommunityBadges.swift`.
- [ ] **Step 5: Commit** (the Files paths, the catalog, `project.pbxproj`) `[R1-T2] Join policy display, policy chip and monogram, listed communities in CommunityContext`.

---

### Task 3: `CommunityPreview` and `fetchCommunityPreview`

**Files:**
- Modify: `NaarsCars/Core/Models/CommunityPayloads.swift` (`CommunityRefusalCode` `:14-35`, a new `CommunityPreview` after `PublicCommunity` `:340-354`)
- Modify: `NaarsCars/Core/Protocols/CommunityServiceProtocol.swift:28`, `NaarsCars/Core/Services/CommunityService.swift` (after `:362`), `NaarsCars/Core/Services/PreviewCommunityService.swift`
- Modify (tests): `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift` (`StubCommunityService` `:425-`), `NaarsCars/NaarsCarsTests/Core/Services/CommunityServiceTests.swift` (`:173-181` and new tests)

**Interfaces:**
- Consumes: Task 1's row shape.
- Produces: `CommunityRefusalCode.notListed = "not_listed"`; `struct CommunityPreview: Decodable, Equatable, Sendable { let community: Community; let requests: [Request]; let posts: [Post] }` with `Community { id: UUID, name: String, description: String?, joinPolicy: String, isPublic: Bool, isDefault: Bool, memberCount: Int, timezone: String }`, `Request: Identifiable { type: String, id: UUID, title: String?, date: Date, time: String?, timezone: String?, seats: Int?, posterId: UUID, posterName: String, posterAvatarUrl: String?; var isRide: Bool }`, `Post: Identifiable { id: UUID, type: String?, title: String?, content: String, createdAt: Date, authorId: UUID, authorName: String, authorAvatarUrl: String?, commentCount: Int }` (explicit snake_case `CodingKeys`, decoded by `DateDecoderFactory.makeSupabaseDecoder()`); `CommunityServiceProtocol.fetchCommunityPreview(communityId: UUID) async throws -> CommunityPreview` (`rpc("get_community_preview", params: CommunityIdParams(...))`, `CommunityRPC.decode`). `StubCommunityService.fetchCommunityPreviewResult: Result<CommunityPreview, Error>` and `fetchCommunityPreviewCalls: [UUID]`; `CommunityFixtures.communityPreviewJSON` (Test-Public-style names, no personal data; a ride, then a favor, then one post with `comment_count` 3) and `static func preview(_ id: UUID, name: String, policy: String = "approve") -> CommunityPreview` (description nil, `isDefault` false, `memberCount` 1, the same two requests and one post); `PreviewCommunityService.preview: CommunityPreview?` and `failPreview: Bool`.

Key: `community_error_not_listed` "This community isn't listed. You can join it with an invite code or link."

- [ ] **Step 1: Failing tests** in `CommunityServiceTests`:

```swift
func testFetchCommunityPreview_SendsCommunityIdAndDecodes() async throws {
    respond(with: CommunityFixtures.communityPreviewJSON)
    let preview = try await service.fetchCommunityPreview(communityId: CommunityFixtures.communityA)
    let request = try onlyRequest()
    XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_preview")
    XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_community_id"])
    XCTAssertEqual(preview.community.joinPolicy, "approve")
    XCTAssertEqual(preview.requests.map(\.isRide), [true, false])
    XCTAssertEqual(preview.posts.first?.commentCount, 3)
}
func testFetchCommunityPreview_NotListedThrowsTypedRefusal() async {
    respond(with: #"{"success": false, "error": "Community not found", "code": "not_listed"}"#)
    do { _ = try await service.fetchCommunityPreview(communityId: CommunityFixtures.communityA); XCTFail("expected a refusal") }
    catch let error as CommunityRPCError { XCTAssertEqual(error.code, .notListed) }
    catch { XCTFail("unexpected \(error)") }
}
```
and `testLocalizedMessage_EveryCodeHasAKey` expects `21` codes.
- [ ] **Step 2: RED.** Expected: "value of type 'CommunityService' has no member 'fetchCommunityPreview'".
- [ ] **Step 3: Implement** the model, the service method, the stub and the preview service; add the key.
- [ ] **Step 4: GREEN.** BUILD; TEST `CommunityServiceTests`, `CommunityPayloadDecodingTests`. Expected: 2 new tests pass.
- [ ] **Step 5: Commit** (the Files paths, the catalog) `[R1-T3] Community preview model and service call`.

---

### Task 4: Tab API migration, the Explore tab, and community routes on Explore

**Files:**
- Modify: `NaarsCars/App/NavigationCoordinator.swift` (`Tab` `:89-94`; `.townHall` deep link `:197-199`; `isSameDeepLink` `:288-289`; `applyNotificationIntent` `:378-407`; guest gating `:420-449`)
- Modify: `NaarsCars/App/NavigationIntent.swift:11-58`
- Modify: `NaarsCars/App/MainTabView.swift:52-185` (and a `Tab.refreshDomain` extension at the end)
- Modify: `NaarsCars/Core/Services/BadgeCountManager.swift:39-60, 353-357`
- Create: `NaarsCars/Features/Community/Views/ExploreView.swift` (fallback: `MyCommunitiesView.swift`)
- Modify: `NaarsCars/Features/Community/Views/MyCommunitiesView.swift` (header comment `:11`; title `:125`; intents and destinations)
- Modify: `NaarsCars/Features/Community/Views/CommunityTabView.swift:86` (`.townHall`)
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift` (remove `:35-43` states other than `pendingMembersTarget`, the My communities row `:94` and `:692-724`, the Explore intents from `:169-170` and `:750-776`, destinations `:212-229`)
- Test: `NavigationCoordinatorRoutingTests.swift` (`:47, 98, 108, 127, 230, 260-330, 393-409, 459, 475` and new), `PendingInviteStoreTests.swift:158`, `BadgeCountManagerTests.swift:40, 172, 184`, `MyCommunitiesViewModelTests.swift` (existing; one new test)

**Interfaces:**
- Produces: `enum NavigationCoordinator.Tab: Int { case requests = 0, messages = 1, townHall = 2, profile = 3, explore = 4 }`; `extension NavigationCoordinator.Tab { var refreshDomain: RefreshCoordinator.Domain? }`; `NavigationIntent.explore` (guest-safe, not admin-only; `MainTabView` selects Explore and clears it).
- Produces: `targetTab` → `.explore` for `.myCommunities`, `.joinCommunity`, `.pendingMembers`, `.communityReports`, `.communityMembers`, `.explore`; `.profile` for `.profile`, `.adminPanel`, `.pendingUsers`, `.adminReports`; `.townHall` for `.townHallPost`, `.announcements`. `applyNotificationIntent` selects the same tabs.
- Produces: `BadgeCountManager.BadgeCounts.explore` (was `profile`; `pending_members_total`), `clearExploreBadge()` (was `clearProfileBadge()`).
- Produces: `struct ExploreView: View` (NavigationStack root: `MyCommunitiesView()`, bell, `.trackScreen("Explore")`); `enum MyCommunitiesView.ExploreRoute: Equatable { case root, pendingMembers(PendingMembersTarget), communityReports(UUID), communityMembers(UUID) }` and `static func exploreRoute(for intent: NavigationIntent) -> ExploreRoute?`.

Keys: `explore_title` "Explore"; `explore_tab_hint` "Find and manage communities"; `nav_tab_town_hall` "Town Hall"; `nav_tab_town_hall_hint` "View your community's Town Hall". Identifier: `tab.explore`.

- [ ] **Step 1: Failing tests.** Update the existing expectations (`.community` → `.townHall`; the community-admin intents' `.profile` → `.explore`; rename those tests `…SelectsExploreTab` / `…ForExploreTab`; `PendingInviteStoreTests:158` → `.explore`; `BadgeCountManagerTests` `counts.profile` → `counts.explore`), and add:

```swift
// NavigationCoordinatorRoutingTests
func testCommunityAdminIntents_TargetExploreTab() {
    let a = CommunityFixtures.communityA
    for intent: NavigationIntent in [.myCommunities, .joinCommunity, .pendingMembers(a), .communityReports(a), .communityMembers(a), .explore] {
        XCTAssertEqual(intent.targetTab, .explore, "\(intent)")
    }
    for intent: NavigationIntent in [.pendingUsers, .adminPanel, .adminReports, .profile(UUID())] {
        XCTAssertEqual(intent.targetTab, .profile, "\(intent)")
    }
    XCTAssertEqual(NavigationIntent.townHallPost(UUID()).targetTab, .townHall)
}
func testDeferredCommunityAdminIntents_SelectExploreTab() {
    let a = CommunityFixtures.communityA
    for intent: NotificationIntent in [.openPendingMembers(communityId: a), .openCommunityReports(communityId: a), .openCommunityMembers(communityId: a), .openMyCommunities] {
        coordinator.selectedTab = .requests
        coordinator.deferNotificationIntent(intent)
        coordinator.applyDeferredNotificationIntentIfNeeded()
        XCTAssertEqual(coordinator.selectedTab, .explore, "\(intent)")
    }
    coordinator.deferNotificationIntent(.openPendingUsers); coordinator.applyDeferredNotificationIntentIfNeeded()
    XCTAssertEqual(coordinator.selectedTab, .profile)
}
func testExploreIntent_IsGuestSafe() {
    XCTAssertFalse(coordinator.intentRequiresAuth(.explore)); XCTAssertFalse(coordinator.intentIsAdminOnly(.explore))
}
func testTabRefreshDomains_ExploreAndProfileHaveNone() {
    XCTAssertEqual(NavigationCoordinator.Tab.requests.refreshDomain, .dashboard)
    XCTAssertEqual(NavigationCoordinator.Tab.messages.refreshDomain, .conversations)
    XCTAssertEqual(NavigationCoordinator.Tab.townHall.refreshDomain, .townHall)
    XCTAssertNil(NavigationCoordinator.Tab.profile.refreshDomain); XCTAssertNil(NavigationCoordinator.Tab.explore.refreshDomain)
}
// MyCommunitiesViewModelTests
func testExploreRoute_CommunityAdminIntentsMapToTheirScreens() {
    let a = CommunityFixtures.communityA
    XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .pendingMembers(a)), .pendingMembers(.community(a, name: nil)))
    XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .communityReports(a)), .communityReports(a))
    XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .communityMembers(a)), .communityMembers(a))
    XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .myCommunities), .root)
    XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .joinCommunity), .root)
    XCTAssertNil(MyCommunitiesView.exploreRoute(for: .pendingUsers)); XCTAssertNil(MyCommunitiesView.exploreRoute(for: .ride(UUID())))
}
```
- [ ] **Step 2: RED.** Expected: "type 'NavigationCoordinator.Tab' has no member 'explore'".
- [ ] **Step 3: Routing model.** Enum, intent, `targetTab`, `applyNotificationIntent`, guest gating, `.townHall` uses; `BadgeCounts.explore` and `clearExploreBadge()`.
- [ ] **Step 4: `MainTabView`.** `@State private var selectedTab: NavigationCoordinator.Tab = .requests`; the body is a `TabView(selection:)` of five `Tab(_:systemImage:value:)` items in this order, each keeping its content, `.badge(Int)` (0 hides it) and `accessibilityHint`: Requests (`car.fill`, `counts.requests`), Messages (`message.fill`, `counts.messages`), Town Hall (`nav_tab_town_hall`, `person.3.fill`, `counts.community`), Profile (`person.fill`, no badge), and `Tab("explore_title".localized, systemImage: "magnifyingglass", value: .explore, role: .search) { ExploreView() }` with `.badge(appState.isGuest ? 0 : badgeManager.counts.explore)`, `.accessibilityIdentifier("tab.explore")`; `.tabBarMinimizeBehavior(.onScrollDown)` on the `TabView`. `onChange(of: selectedTab)`: write the coordinator, `setVisibleDomain(newTab.refreshDomain)`, the Messages teardown, then per tab `clearRequestsBadge` / `clearMessagesBadge` / `clearCommunityBadge(visibleCommunityId:)` / `clearExploreBadge` (Profile none). The initial pass syncs `navigationCoordinator.selectedTab = selectedTab`; `.explore` selects the tab and sets `pendingIntent = nil`; every other intent keeps today's handling with `intent.targetTab`.
- [ ] **Step 5: `ExploreView` and the routes.** `ExploreView` as in Interfaces (bell for everyone; a guest's tap reaches the existing prompt). In `MyCommunitiesView`: title `explore_title`; `.onChange(of: navigationCoordinator.pendingIntent, initial: true)` with the replay rule of `RequestsDashboardView.swift:125-146`, mapping through `exploreRoute(for:)` to `pendingTarget`, a new `reportsTarget: UUID?` (`CommunityReportsView(communityId:communityName:)`), `membersTarget` (`CommunityMembersTarget(communityId:communityName:refreshesRoleFirst: true)` with `.id(communityId)`, copied from `MyProfileView.swift:218-229`), and clearing the intent; each destination sets `screenPushedOnTop` on appear. In `MyProfileView`: the My communities row and every Explore intent and destination go; `.pendingUsers`, `.adminPanel`, `.adminReports`, `.profile` stay.
- [ ] **Step 6: GREEN.** BUILD; TEST `NavigationCoordinatorRoutingTests`, `NavigationCoordinatorTests`, `PendingInviteStoreTests`, `BadgeCountManagerTests`, `MyCommunitiesViewModelTests`, `AppDelegateNotificationHandlingTests`; then FULL. Expected: 5 new tests pass, the renamed ones pass. Lane B: install on `iPhone 16 Tests`, enter guest mode, screenshot the tab bar in light, dark and AX 5 (`build/R1-T4-captures/`): five items, Explore trailing, no label wraps.
- [ ] **Step 7: Commit** (the Files paths, the catalog, `project.pbxproj`) `[R1-T4] Tab API with the Explore search tab; community routes open on Explore`.

---

### Task 5: The community page

**Files:**
- Create: `NaarsCars/Features/Community/ViewModels/CommunityPageViewModel.swift` (fallback: `MyCommunitiesViewModel.swift`)
- Create: `NaarsCars/Features/Community/Views/CommunityPageView.swift` (fallback: `MyCommunitiesView.swift`)
- Modify: `NaarsCars/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift:44-56`; `NaarsCars/Features/Leaderboards/Views/LeaderboardView.swift:11-15` (comment: hosted by the community page)
- Test: create `NaarsCars/NaarsCarsTests/Features/Community/CommunityPageViewModelTests.swift` (fallback: second class in `MyCommunitiesViewModelTests.swift`); modify `NaarsCars/NaarsCarsTests/Features/Leaderboards/LeaderboardViewModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`joinPolicy`, `CommunityPolicyChip`, `CommunityMonogram`, `ruleSentence`), Task 3 (`fetchCommunityPreview`, `.notListed`, `CommunityPreview`).
- Produces: `enum CommunityPageMode: Equatable { case loading, member(CommunityMembership), pending(CommunityMembership), visitor(CommunityPreview), unavailable, failed }`; `enum CommunityVisitorAction: Equatable { case signUp, askToJoin(PublicCommunity), enterInviteCode, waitingForApproval }`; `@MainActor final class CommunityPageViewModel: ObservableObject` with `init(communityId: UUID, service: any CommunityServiceProtocol = CommunityService.shared, communityContext: CommunityContext? = nil, isGuest: @escaping @MainActor () -> Bool = { AuthService.shared.currentUserId == nil })`, `let communityId`, `@Published private(set) var mode: CommunityPageMode`, `var visitorAction: CommunityVisitorAction?`, `var policy: CommunityJoinPolicy?`, `func load() async`.
- Produces: `struct CommunityPageView: View` with `init(communityId: UUID)` and a preview/test init taking both view models; `LeaderboardViewModel.init(…, communityId: UUID? = nil)`: a set id pins the cache key whatever the Town Hall community is.

`load()`: an active membership → `.member` and an `.pending` row → `.pending` (no request); otherwise `.loading` → `fetchCommunityPreview` → `.visitor`, `.unavailable` on `.notListed`, `.failed` on any other error, unchanged on cancellation. `visitorAction`: guest → `.signUp`; pending → `.waitingForApproval`; invite → `.enterInviteCode`; approve, open or unknown → `.askToJoin(PublicCommunity(id:name:description:joinPolicy:isDefault:))` from the preview (the server decides).

**Screen (S4, without the map):** header (`CommunityMonogram`, name, member count with `community_member_count_one/_other`, `CommunityPolicyChip`, a `community_page_listed_chip` chip when listed, the role chip for owner or admin), the rule sentence. Member mode: Invite (`canInvite`; `CommunityInviteSheet`), Mute / Unmute, Manage for `isAdmin(of:)` with `NotificationBadge(pendingCount)` (`AdminPanelView(scope: .community(id), communityName:onCommunityArchived:)`), Leaderboard (top three of `LeaderboardViewModel(communityId:)` for This Month, See all → `LeaderboardView`), Community Guidelines (`CommunityGuidelinesView(showDismissButton: false)`), Report this community (`ReportContentSheet(context: .community(id:code: nil,name:))`), Leave <name> (`LeaveCommunitySheet` with `MyCommunitiesViewModel.leavePlan`; `last_owner` → the choose-a-new-owner alert and Members, copied from `MyCommunitiesView.swift:198-221`). Visitor mode: Open requests (rows "Ride · <poster> · <day time>" / favor title over "Favor · <poster> · <day time>", the poster through `UserAvatarLink`; rows are not tappable), Recent in Town Hall (snippet over "<author> · <relative time> · N comments"), a toolbar menu with Report this community (a guest gets the prompt), and a floating bar with `.glassEffect` whose content follows `visitorAction`: guest "Sign up to join" (prompt `.joinCommunity`), Ask to join (`JoinCommunitySheet(target: .publicCommunity(…))`), "Have an invite code?" (`JoinCommunitySheet(target: .code(prefilled: nil))`), Waiting for approval (disabled). Guests also see `community_page_guest_notice` at the top. `.pending`: header, rule, the waiting bar. `.unavailable` / `.failed`: `EmptyStateView` / `ErrorView` with Retry. Every push from the page is item- or bool-driven. Member actions run on a page-owned `@StateObject MyCommunitiesViewModel` (leave, mute, `didJoin` after a join sheet is dismissed: present-record-act-on-dismiss), then `viewModel.load()`; the view re-runs `load()` on `.onChange(of: CommunityContext.shared.membership(for: communityId))`.

Keys: `community_page_listed_chip` "Listed"; `community_page_manage` "Manage"; `community_page_manage_subtitle` "Requests to join, members, reports, settings, announcements"; `community_page_see_all` "See all"; `community_page_open_requests` "Open requests"; `community_page_no_open_requests` "No open requests right now."; `community_page_recent_town_hall` "Recent in Town Hall"; `community_page_no_posts` "No Town Hall posts yet."; `community_page_ride_row` "Ride · %1$@ · %2$@"; `community_page_favor_row` "Favor · %1$@ · %2$@"; `community_page_post_meta_one` "%1$@ · %2$@ · %3$lld comment"; `community_page_post_meta_other` "%1$@ · %2$@ · %3$lld comments"; `community_page_leave` "Leave %@"; `community_page_unavailable` "This community is no longer available."; `community_page_load_failed` "Couldn't load this community."; `community_page_bar_ask_subtitle` "An admin approves each person"; `community_page_bar_code_title` "Have an invite code?"; `community_page_bar_code_subtitle` "Invite only: join with a code or link"; `community_page_bar_signup_title` "Sign up to join"; `community_page_bar_signup_subtitle` "Free, and it takes a minute"; `community_page_guest_notice` "You're looking around as a guest. Sign up to join, offer help or post." Reused: `community_member_count_one/_other`, `community_policy_ask_to_join` (bar title), `community_status_pending`, `community_action_invite`, `community_action_mute` / `_unmute`, `leaderboard_title`, `settings_community_guidelines`, `community_report_this_community`. Identifiers: `communityPage.join`, `communityPage.invite`, `communityPage.mute`, `communityPage.manage`, `communityPage.leaderboard`, `communityPage.guidelines`, `communityPage.report`, `communityPage.leave`, `communityPage.retry`, `communityPage.more`.

- [ ] **Step 1: Failing tests** (`CommunityPageViewModelTests`, a context built as `MyCommunitiesViewModelTests.makeContext` does, `StubCommunityService`):
  `testMemberMode_ComesFromTheActiveMembershipWithoutARequest` (mode `.member(row)`, `fetchCommunityPreviewCalls` empty); `testPendingMode_ComesFromThePendingMembershipAndWaits` (`.pending`, `visitorAction == .waitingForApproval`, no call); `testVisitorMode_LoadsThePreviewForANonMember` (calls `== [id]`, `.visitor(preview)`, `visitorAction == .askToJoin(PublicCommunity(id: id, name: "Test Public A", description: nil, joinPolicy: "approve", isDefault: false))`); `testVisitor_InviteOnlyOffersTheInviteCode`; `testGuest_VisitorActionIsSignUp` (`isGuest: { true }`); `testVisitor_NotListedRefusalShowsUnavailable`; `testVisitor_NetworkFailureShowsFailedAndRetryLoads` (`URLError(.notConnectedToInternet)` → `.failed`; stub succeeds → `load()` → `.visitor`); `testVisitor_CancelledLoadIsNotAFailure` (`CancellationError` → mode stays `.loading`); `testLeavingAListedCommunity_ReloadsAsVisitor` (`.member`, then `forgetMembership` and `load()` → `.visitor`); `testLeavingAHiddenCommunity_ShowsUnavailable` (same with `.notListed` → `.unavailable`). `LeaderboardViewModelTests.testPinnedCommunity_LoadsThatCommunityWhateverTheTab` (context tab = A, `communityId: B` → `entryCalls.last?.communityId == B`).
- [ ] **Step 2: RED.** Expected: "cannot find 'CommunityPageViewModel' in scope".
- [ ] **Step 3: Implement** the view model, the leaderboard pin, then the view; add the keys. `#Preview`s inside `#if DEBUG` with `PreviewCommunityService`: member (owner of a community with 3 pending), visitor approve, visitor invite, guest visitor, pending, unavailable.
- [ ] **Step 4: GREEN.** BUILD; PREVIEWGUARD `CommunityPageView.swift`; TEST `CommunityPageViewModelTests`, `LeaderboardViewModelTests`, `MyCommunitiesViewModelTests`; RELEASE. Expected: 11 new tests pass. CAPTURE `CommunityPageView.swift` (the join bar stays clear of the home indicator and the last row at AX 5).
- [ ] **Step 5: Commit** (the Files paths, the catalog, `project.pbxproj`) `[R1-T5] Community page for members, pending members and visitors`.

---

### Task 6: Explore content

**Files:**
- Modify: `NaarsCars/Features/Community/Views/MyCommunitiesView.swift` (sections `:68-121`, rows `:314-415`, sheets `:440-508`, `.task` `:143-151`)
- Modify: `NaarsCars/Features/Community/ViewModels/MyCommunitiesViewModel.swift:84-149`
- Modify: `NaarsCars/Core/Models/GuestRestrictionReason.swift` (a case)
- Test: `MyCommunitiesViewModelTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 4, 5.
- Produces: `MyCommunitiesViewModel.init(…, isGuest: @escaping @MainActor () -> Bool = { AuthService.shared.currentUserId == nil }, now: @escaping () -> Date = Date.init)`; `var listedToShow: [PublicCommunity]` (listed minus every active or pending membership); `@Published private(set) var listedLoadFailed: Bool`; `load()` (members: memberships, limits and the listed list; guests: the listed list only); `func loadIfStale() async` (skips when the last successful `load()` is within `Constants.Timing.refreshStalenessWindow`). `GuestRestrictionReason.startCommunity`.

**Screen (S3 before typing, without search):** Your communities (rows are buttons to `CommunityPageView` through `communityPageTarget: UUID?`: monogram, name, `explore_row_detail` with the policy's chip text and the member count, the role chip, the muted chip; admins keep the "Requests to join N" row), Waiting for approval (unchanged, with its menu), the limit section (members), then Saved invite code (Use: Join sheet, guest prompt), "Have an invite code?" (`JoinCommunitySheet(target: .code(prefilled: joinPrefilledCode))`, replacing the `CommunityJoinOptionsView` sheet), "Start a community" with its subtitle (guest: `.startCommunity` prompt), then Listed communities (rows to the page; footer; empty text; on failure a Retry row). The active-row menu, the `.invite` sheet case, `adminPanelTarget` and the `newOwnerNeededFor` alert leave this screen (the page owns them). Guests: no skeleton (`hasLoadedMemberships` stays false for them) and no automatic Join for a saved code. `.task` calls `loadIfStale()`; `.refreshable` calls `load()`.

Keys: `explore_section_listed` "Listed communities"; `explore_listed_footer` "Only listed communities appear here. Others are joined with an invite code or link."; `explore_listed_empty` "No listed communities yet."; `explore_listed_load_failed` "Couldn't load the listed communities."; `explore_have_invite_code` "Have an invite code?"; `explore_start_community` "Start a community"; `explore_start_community_subtitle` "For your street, building or town"; `explore_row_detail` "%1$@ · %2$@"; `guest_prompt_title_start_community` "Sign In to Start a Community"; `guest_prompt_message_start_community` "Create a free account to start a community for your street, building or town." Identifiers: `explore.community.row`, `explore.listed.row`, `explore.listed.retry`, `explore.inviteCode`, `explore.startCommunity` (existing `community.my.inviteCode.use` / `.remove`, `community.my.requests` stay).

- [ ] **Step 1: Failing tests:** `testListedToShow_LeavesOutActiveAndPendingMemberships` (listed [A, B, C], memberships A active, B pending → [C]); `testLoad_GuestLoadsListedOnlyWithoutMembershipOrLimitCalls` (`isGuest: { true }` → `fetchCount == 0`, `fetchMyCommunityLimitsCalls == 0`, `fetchPublicCommunitiesCalls == 1`); `testLoadIfStale_SkipsWithinTheStalenessWindow` (`now` advanced 10 s → no new call; 31 s → one more of each); `testListedLoadFailure_SetsTheFlagAndKeepsTheRows`.
- [ ] **Step 2: RED.** Expected: "extra argument 'isGuest' in call".
- [ ] **Step 3: Implement**; add the keys; previews (member with two communities, an admin row with requests and a saved code; guest; listed load failed).
- [ ] **Step 4: GREEN.** BUILD; PREVIEWGUARD `MyCommunitiesView.swift`; TEST `MyCommunitiesViewModelTests`, `CommunityPageViewModelTests`, `PendingInviteStoreTests`; RELEASE. Expected: 4 new tests pass. CAPTURE `MyCommunitiesView.swift`.
- [ ] **Step 5: Commit** (the Files paths, the catalog) `[R1-T6] Explore: your communities, listed communities, invite code and Start a community`.

---

### Task 7: Town Hall tab

**Files:**
- Modify: `NaarsCars/Features/Community/Views/CommunityTabView.swift` (the whole body; `CommunityHeaderView` `:107-130` removed)
- Modify: `NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift` (published state `:44`; `navigate(to:request:)` step 2 `:404-409`)
- Modify: `NaarsCars/Features/TownHall/Views/TownHallFeedView.swift:111-112`
- Modify: `NaarsCars/UI/Components/Common/CommunityTitleMenu.swift:8-28` (doc comment: members of one community now see the menu)
- Test: `NaarsCars/NaarsCarsTests/Features/TownHall/TownHallFeedViewModelTests.swift`

**Interfaces:**
- Consumes: Task 4 (`.townHall`, `.explore`), Task 5 (`CommunityPageView(communityId:)`).
- Produces: `TownHallFeedViewModel.communitySwitchNotice: String?` (`@Published`), set to `String(format: "townhall_now_in_community".localized, name)` only when `open(_:)` switches the community; the view shows it with `.toast(message:style: .info)`.

**Screen:** `CommunityTabView` hosts `TownHallFeedView()` only (no segmented control, no `LeaderboardViewModel`). Title: the Town Hall community's name, `nav_tab_town_hall` for a guest or before memberships load. `communityTitleMenu(enabled: !appState.isGuest && !communityContext.activeMemberships.isEmpty)`: each community with its unread count (today's rows), a `Divider`, "About this community" (pushes `CommunityPageView(communityId: communityTabId)` through `aboutCommunityId: UUID?`), "Find communities" (`navigationCoordinator.selectedTab = .explore`). Bell unchanged; the `communityTabId` badge clear keeps its guard with `.townHall`.

Keys: `townhall_now_in_community` "Now in %@"; `community_menu_about` "About this community"; `community_menu_find` "Find communities". Identifiers: `townHall.titleMenu.about`, `townHall.titleMenu.find`.

- [ ] **Step 1: Failing tests** (the scoping harness of `:332-410`): `testOpen_TargetInAnotherCommunity_SetsTheNowInNotice` (tab A, target in B → `communitySwitchNotice == String(format: "townhall_now_in_community".localized, "B")`); `testOpen_TargetInTheShownCommunity_SetsNoNotice`; `testTitleMenuSwitch_SetsNoNotice` (set `communityTabId = B`, `activeCommunityDidChange()` → nil).
- [ ] **Step 2: RED.** Expected: "value of type 'TownHallFeedViewModel' has no member 'communitySwitchNotice'".
- [ ] **Step 3: Implement**; add the keys; `#Preview` of `CommunityTabView` with `PreviewCommunityService` memberships inside `#if DEBUG`.
- [ ] **Step 4: GREEN.** BUILD; PREVIEWGUARD; TEST `TownHallFeedViewModelTests`, `LeaderboardViewModelTests`. Expected: 3 new tests pass. CAPTURE `CommunityTabView.swift` (menu closed; Lane B on a guest for the title).
- [ ] **Step 5: Commit** (the Files paths, the catalog) `[R1-T7] Town Hall tab: no leaderboard switch, About and Find in the title menu, Now in notice`.

---

### Task 8: Requests filter model

**Files:**
- Modify: `NaarsCars/Core/Models/Community.swift:81-110` (`RequestsScope`)
- Modify: `NaarsCars/App/CommunityContext.swift` (`chipText` `:134-140`, `apply` `:291-310`, a toggle)
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift` (open counts), `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift` (`:29-34`, `:252-264`, a static header)
- Test: `CommunityPayloadDecodingTests.swift`, `AppLaunchManagerTests.swift`, `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift`; create `NaarsCars/NaarsCarsTests/Features/Requests/RequestsHeaderTests.swift` (fallback: second class in `CommunityStoreScopingTests.swift`)

**Interfaces:**
- Consumes: Task 2 (`subtitleText`, `joinPolicy(for:)`).
- Produces: `RequestsScope.excluding(Set<UUID>)`: `communityId` nil; `includes` true for nil and for ids not in the set; `storageValue` `"exclude:" + sorted ids joined by ","`; `init(storageValue:)` parses it, drops invalid ids, and an empty result is `.all`.
- Produces: `CommunityContext.toggleRequestsInclusion(_ communityId: UUID)`: `.all` → `.excluding([id])` unless that would exclude every active community; in `.excluding`, removing the last id → `.all`; adding the last included community is a no-op; `.community` is a no-op. `apply` keeps only active ids in `.excluding` and turns an empty set or one covering every active community into `.all`. `chipText(for:respectingScope:)` hides names only under `.community`.
- Produces: `struct OpenRequestCounts: Equatable { let all: Int; let byCommunity: [UUID: Int] }`; `RequestFilterManager.openCounts(in context: ModelContext) -> OpenRequestCounts` (the Open filter's rows under `.all`, the 12-hour rule included; rows with no community count only in `all`); `RequestsDashboardViewModel.openCounts` (`@Published private(set)`, refreshed with the lists).
- Produces: `struct RequestsHeader: Equatable { let title: String; let subtitle: String?; let showsCommunityChips: Bool }`; `static func RequestsDashboardViewModel.header(scope: RequestsScope, activeMemberships: [CommunityMembership], isGuest: Bool) -> RequestsHeader`: guest or none → `requests_nav_title`, nil, false; one membership → its name, its policy's `subtitleText`, false; `.community(id)` of an active one → that name and subtitle, false; otherwise `community_all_communities`, nil, true.

- [ ] **Step 1: Failing tests.**

```swift
// CommunityPayloadDecodingTests
func testRequestsScope_ExcludingStorageRoundTripAndMalformedValues() {
    let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB
    let scope = RequestsScope.excluding([b, a])
    XCTAssertEqual(scope.storageValue, "exclude:" + [a, b].map(\.uuidString).sorted().joined(separator: ","))
    XCTAssertEqual(RequestsScope(storageValue: scope.storageValue), scope)
    XCTAssertEqual(RequestsScope(storageValue: "exclude:"), .all)
    XCTAssertEqual(RequestsScope(storageValue: "exclude:garbage"), .all)
    XCTAssertEqual(RequestsScope(storageValue: "exclude:\(a.uuidString),garbage"), .excluding([a]))
    XCTAssertFalse(RequestsScope.excluding([a]).includes(a)); XCTAssertTrue(RequestsScope.excluding([a]).includes(b))
    XCTAssertTrue(RequestsScope.excluding([a]).includes(nil)); XCTAssertNil(RequestsScope.excluding([a]).communityId)
}
```
  `AppLaunchManagerTests`: `testRefresh_ExcludingScopeDropsCommunitiesNoLongerActive` (stored exclude A and C, memberships A and B → `.excluding([A])`, persisted); `testRefresh_ExcludingEveryActiveCommunityFallsBackToAll`; `testToggleRequestsInclusion_NeverExcludesTheLastCommunity` (A, B: toggle A → `.excluding([A])`; toggle B → unchanged; toggle A → `.all`; one membership: toggle → `.all`; `.community(A)`: toggle → unchanged); `testChipText_ShownWhenExcludingHiddenWhenNarrowed` (memberships A "A", B "B": under `.excluding([B])` `chipText(for: A, respectingScope: true) == "A"`; under `.community(A)` it is nil and `chipText(for: A, respectingScope: false) == "A"`; under `.all` it is "A"). `CommunityStoreScopingTests`: `testExcludingScope_LeavesOutTheExcludedCommunityKeepsUnlabelled` (`seedScopedRequests`, `.excluding([B])` → communities {A, nil}); `testOpenCounts_CountsOpenRowsPerCommunityAndAll` (future rides A, B, B, nil and a claimed A → `all == 4`, `[A: 1, B: 2]`). `RequestsHeaderTests` (A = "Harbor Riders" with policy `approve`, B = "Fremont Porch Club" with `invite`; English literals, test locale en): `testHeader_GuestIsRequests` (`header(scope: .all, activeMemberships: [A, B], isGuest: true) == RequestsHeader(title: "Requests", subtitle: nil, showsCommunityChips: false)`), `testHeader_OneMembershipNamesItWithItsRule` (`[A]`, `.all` → `("Harbor Riders", "Ask to join", false)`), `testHeader_TwoMembershipsShowAllCommunitiesAndChips` (`[A, B]`, `.all` → `("All communities", nil, true)`), `testHeader_NarrowedShowsTheCommunityAndItsRule` (`[A, B]`, `.community(B)` → `("Fremont Porch Club", "Invite only", false)`), `testHeader_ExcludingKeepsAllCommunitiesAndChips` (`[A, B]`, `.excluding([A])` → `("All communities", nil, true)`).
- [ ] **Step 2: RED.** Expected: "type 'RequestsScope' has no member 'excluding'".
- [ ] **Step 3: Implement.** No key in this task.
- [ ] **Step 4: GREEN.** BUILD; TEST `CommunityPayloadDecodingTests`, `AppLaunchManagerTests`, `CommunityStoreScopingTests`, `RequestsHeaderTests`; FULL. Expected: 12 new tests pass.
- [ ] **Step 5: Commit** (the Files paths, `project.pbxproj`) `[R1-T8] Requests include and exclude filter, open counts and header rules`.

---

### Task 9: Requests screen

**Files:**
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift` (title and menu `:35-67`, header `:282-318`, `RequestCardView` `:493-519`, a chips row view in the same file)
- Modify: `NaarsCars/Core/Models/RequestFilter.swift:16-22`
- Modify: `NaarsCars/UI/Components/Cards/RideCard.swift:11-16, 85-87, 130-138`; `NaarsCars/UI/Components/Cards/FavorCard.swift:12-16, 84-86, 132-136`; `NaarsCars/UI/Components/Common/NotificationBadge.swift:44-77` (`NaarsChip.isStruckThrough`)
- Create: `Docs/qa/push-fixtures/new_ride_other_community.apns`
- Test: `NavigationCoordinatorRoutingTests.swift`, `CommunityPayloadDecodingTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 4, 5, 8.
- Produces: `RideCard(…, policy: CommunityJoinPolicy? = nil)` and `FavorCard(…, policy:)` (a `CommunityPolicyChip` before the status chip; the card's combined accessibility label gains `community_policy_accessibility`); `RequestCardView` passes `communityContext.joinPolicy(for:)` on every card, Past Requests included. `RequestFilter.localizedKey`: `requests_tile_open`, `requests_tile_mine`, `requests_tile_helping` (`RequestFilter.claimed` is the Helping tile; raw values and identifiers unchanged).

**Screen (S2):** `navigationTitle` / subtitle from `RequestsDashboardViewModel.header`; `communityTitleMenu(enabled: !appState.isGuest && !communityContext.activeMemberships.isEmpty)` lists "All communities" (subtitle: count of `openCounts.all`) and each community (its count, "No open requests" at 0), then a `Divider`, "About this community" (narrowed or one membership: a button to that community; otherwise a submenu of the communities), "Find communities" (`selectedTab = .explore`); About pushes `CommunityPageView` through `aboutCommunityId: UUID?`. When `header.showsCommunityChips`, the pinned header gains, above the tiles, "Showing N of your M communities" and a horizontal row of one button per active community: included `NaarsChip(text:systemImage: "checkmark", tint: .naarsPrimary)`, excluded a neutral `NaarsChip` with `strikethrough` (add `var isStruckThrough = false` to `NaarsChip`); a tap calls `toggleRequestsInclusion`; the last included chip is disabled. The "N more in your other communities" hint keeps working with `.excluding`.

Keys: `requests_tile_open` "Open"; `requests_tile_mine` "Mine"; `requests_tile_helping` "Helping"; `requests_showing_communities` "Showing %1$lld of your %2$lld communities"; `requests_menu_open_count_one` "%lld open request"; `requests_menu_open_count_other` "%lld open requests"; `requests_menu_open_count_none` "No open requests"; `requests_chip_included_accessibility` "%@, included"; `requests_chip_excluded_accessibility` "%@, left out"; `requests_chip_hint_exclude` "Double-tap to leave this community's requests out"; `requests_chip_hint_include` "Double-tap to show this community's requests". Identifiers: `requests.communityChips`, `requests.communityChip`, `requests.titleMenu.all`, `requests.titleMenu.community`, `requests.titleMenu.about`, `requests.titleMenu.find`.

- [ ] **Step 1: Failing tests.**

```swift
// NavigationCoordinatorRoutingTests
func testNewRidePushFromAnotherCommunity_OpensOnRequestsAndLeavesTheFilter() {
    let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB, rideId = UUID()
    let context = CommunityContext(service: StubCommunityService(result: .success([])), defaults: suite)
    context.debugSetMemberships([CommunityFixtures.membership(a, name: "A"), CommunityFixtures.membership(b, name: "B")])
    context.requestsScope = .community(a); context.communityTabId = a
    let link = DeepLinkParser.parse(userInfo: ["type": "new_ride", "ride_id": rideId.uuidString, "community_id": b.uuidString])
    XCTAssertEqual(link, .ride(rideId))
    coordinator.applyPushDeepLink(link)
    XCTAssertEqual(coordinator.pendingIntent, .ride(rideId, anchor: nil))
    XCTAssertEqual(coordinator.pendingIntent?.targetTab, .requests)
    XCTAssertEqual(context.requestsScope, .community(a)); XCTAssertEqual(context.communityTabId, a)
}
// CommunityPayloadDecodingTests
func testRequestTiles_AreOpenMineHelpingWithUnchangedIdentifiers() {
    XCTAssertEqual(RequestFilter.allCases.map(\.localizedKey), ["requests_tile_open", "requests_tile_mine", "requests_tile_helping"])
    XCTAssertEqual(RequestFilter.claimed.rawValue, "Claimed Requests")
}
```
- [ ] **Step 2: RED.** Expected: the tile test fails on the keys; the push test passes already (it pins today's behaviour and stays as the regression check).
- [ ] **Step 3: Implement**; add the keys; write the fixture (`new_ride`, `ride_id` `<RIDE_ID>`, `community_id` `<COMMUNITY_ID>`, the form of `town_hall_post_with_community.apns`); update the `RideCard` / `FavorCard` previews with a policy.
- [ ] **Step 4: GREEN.** BUILD; PREVIEWGUARD; TEST `NavigationCoordinatorRoutingTests`, `CommunityPayloadDecodingTests`, `CommunityStoreScopingTests`. Expected: 2 new tests pass. CAPTURE `RideCard.swift`, `FavorCard.swift`, `RequestsDashboardView.swift` (the chips row at AX 5 scrolls and stays above the tiles; the tiles stack as today).
- [ ] **Step 5: Commit** (the Files paths, the catalog) `[R1-T9] Requests: community chips, title menu with counts, policy chips, Open, Mine and Helping`.

---

### Task 10: Profile admin row and Welcome

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:5, 86-92`
- Modify: `NaarsCars/Features/Authentication/Views/WelcomeView.swift:22-25, 47-56, 133-145, 198-202, 222-275`
- Test: `NavigationCoordinatorRoutingTests.swift`

**Interfaces:**
- Consumes: Task 4 (`.explore`).
- Produces: `static func WelcomeEntryRoute.lookAroundFirst(appState: AppState, launchManager: AppLaunchManager = .shared, coordinator: NavigationCoordinator = .shared)`: sets `coordinator.pendingIntent = .explore`, then `appState.isGuestMode = true`, then `launchManager.enterGuestMode()`.

**Profile:** the Admin panel row only for platform admins (`AdminPanelScope.initial(isPlatformAdmin: profile.isAdmin, administered: [])`); community admins reach the panel from Manage. Header comment no longer mentions invite codes. **Welcome (S8):** body `welcome_body_find_community`; the guest button reads `welcome_look_around` and calls `lookAroundFirst` (identifier `welcome.continueAsGuest` kept for the UI tests); `inviteCodeEntry` keeps only the saved-code banner (the "I have an invite code" link, `showInviteEntry` and its sheet go). Button order and the other labels stay.

Keys: `welcome_body_find_community` "Find your neighborhood's community. Get a ride, lend a hand, and meet the people next door."; `welcome_look_around` "Look around first".

- [ ] **Step 1: Failing test** `testLookAroundFirst_EntersGuestModeOnExplore` (a fresh `AppState`; after the call `coordinator.pendingIntent == .explore`, `appState.isGuestMode`, `AppLaunchManager.shared.state == .ready(.guest)`; the class's `tearDown` restores the launch state).
- [ ] **Step 2: RED.** Expected: "type 'WelcomeEntryRoute' has no member 'lookAroundFirst'".
- [ ] **Step 3: Implement**; add the keys.
- [ ] **Step 4: GREEN.** BUILD; TEST `NavigationCoordinatorRoutingTests`, `AdminPanelViewModelTests`, `MyProfileViewModelTests`. Expected: 1 new test passes. CAPTURE `WelcomeView.swift` (both previews) and `MyProfileView.swift` (no My communities row; Tasks 4 and 10); Lane B on `iPhone 16 Tests`: Look around first lands on Explore (screenshot).
- [ ] **Step 5: Commit** (the Files paths, the catalog) `[R1-T10] Platform-only admin row on Profile; Welcome opens Explore with Look around first`.

---

### Task 11: Design system, legal and review-note drafts

**Files:** `Docs/design-system/README.md`, `Legal/PRIVACY_POLICY.md:102`, `Legal/FAQ.md`, `Docs/AppStore/2026-10-multi-community-review-notes.md`. (`CLAUDE.md`, `AGENTS.md` and `SECURITY.md` say what was verified, so they are written in the gate, Task 12 O9, after the evidence.)

- [ ] **Step 1: Design system.** The policy chip and monogram (§3.2, §3.6), the join bar as the sixth glass surface (§2.5), the chips row, the Tab API bar with `tabBarMinimizeBehavior(.onScrollDown)`.
- [ ] **Step 2: Legal and review notes (owner reviews before release).** Privacy policy `:102`: signed-in people who are not members, like guests, can see a listed community's name, description and member count, its upcoming open requests without addresses or notes, its recent Town Hall posts, and the name, photo, car, rating and reviews of its members. FAQ: finding and joining communities in Explore. Review notes: the Explore tab, the community page, "Look around first".
- [ ] **Step 3: Commit** (the Files paths) `[R1-T11] Design system, legal and review-note drafts for Release 1`.

---

### Task 12: Gate

**Files:** `Docs/qa/2026-10-2x-community-release1-gate.md` (report), `CLAUDE.md`, `AGENTS.md`, `SECURITY.md`; captures under `build/R1-gate/` (local; only redacted captures are copied into `Docs/qa/` if the owner wants them).

**Without the owner:**
- [ ] **G1. Server.** Task 1's header reads APPLIED; through the MCP: the three `md5(prosrc)` values match the header; `has_function_privilege('anon', 'public.get_community_preview(uuid)', 'execute')` is true; the full probe file through the MCP except `posts_delete_policy` and `storage_private` (SQL editor, owner): every `PROBE … OK`.
- [ ] **G2. Static.** RELEASE; `scripts/validate-notification-types.sh` → "34 types in sync"; the Global Constraints `git diff --stat` is empty; `grep -rn "\.tabItem" NaarsCars/App NaarsCars/Features` prints nothing; PREVIEWGUARD over every touched view file.
- [ ] **G3. Full suite** on `iPhone 16 Tests` (signed out): executed = the Task 2 Step 0 baseline + 46 new tests, 0 failures, skips only in the session-gated classes.
- [ ] **G4. Guest pass** on `iPhone 16 Tests` (the only booted device; control tool with `device: "iPhone 16 Tests"`): Welcome (no invite link; Look around first) → Explore (listed rows, Have an invite code? and Start a community prompt) → Test Community's page (rule sentence, guest notice, requests and posts, Sign up bar prompts) → Requests (policy chips) → Town Hall (title Town Hall, no menu). Light, dark, AX 5 screenshots of Explore, the page and the tab bar. Shut the device down by UDID.

**With the owner (two simulators: the owner's `iPhone 16` "Owner", the `iPhone 17 (26.5)` "Test Owner"; writes only with the go-ahead; SQL checks through the MCP after each write):**
- [ ] **O1. Tab bar (S1).** Both devices: five items, Explore trailing as the round search button, captures light / dark / AX 5 and while scrolled (minimised bar). Answer and record: does the search tab show a badge (O3)? Under the iOS 26.5 SDK the prominence question of the iOS 27 SDK does not apply; record that.
- [ ] **O2. Explore and the page as a visitor (writes).** Test Owner posts a ride (a future date, public-place text only) and a Town Hall post in Test Public A. Owner: Explore → Test Public A (visitor): rule sentence, the ride row (no address anywhere), the post, Report in the menu (cancel), the poster's avatar opens NC Test Owner's profile with stats (the `public_profiles` widening). Ask to join (writes).
- [ ] **O3. Badge and admin (writes).** Test Owner: the Explore badge shows 1 (or, if the search tab cannot carry a badge, record it and check the count on the row and on Manage, the spec's fallback); Explore row "Requests to join 1" → approve. Owner: the page turns to member mode (Invite, Mute toggled twice, Leaderboard top three and See all, Community Guidelines; Manage shows because the owner is a platform admin, `isAdmin(of:)`); the Requests chips row lists every membership, all included. Test Owner (owner, not a platform admin): Manage opens the admin panel scoped to Test Public A.
- [ ] **O4. Requests.** Owner: title "All communities", menu counts, About this community (submenu), Find communities; exclude Test Community → only Test Public A rows; relaunch → the filter is remembered; narrow to Test Public A → title and "Ask to join" subtitle, chips gone; Helping tile; policy chips on every card. Captures light / dark / AX 5.
- [ ] **O5. Pushes.** Owner narrowed to Test Community: `new_ride_other_community.apns` with the O2 ride → the ride opens on top on Requests and the filter is unchanged; `town_hall_post_with_community.apns` for the O2 post → Town Hall switches to Test Public A with "Now in Test Public A"; a post in the shown community → no notice.
- [ ] **O6. Admin routes on Explore.** Test Owner: `pending_approval_with_community.apns`, `content_reported_community_admin.apns`, `membership_update_owner.apns` (each for Test Public A), each once warm and `pending_approval_with_community` once after `simctl terminate` (cold start): Explore selected, one push of the right screen. Owner (platform admin): `pending_approval_without_community.apns` → Profile → Requests to join of the default community.
- [ ] **O7. Profile and Town Hall.** Profile: no My communities row, no tab badge; the Admin panel row for the owner, none for Test Owner; Delete Account present. Town Hall: no Leaderboard segment; About and Find in the menu. Messages: open a thread and leave the tab; the app log shows the conversation unsubscribe; the composer is unchanged with the bar hidden in the thread.
- [ ] **O8. Leave and clean-up (writes).** Owner: Leave Test Public A from its page → the page returns to visitor mode with a toast; Test Owner deletes the O2 ride and post. `select count(*)` of the owner's Test Public A membership (active) and of the O2 rows: 0. Shut down the second simulator by UDID.
- [ ] **O9. CLAUDE.md, AGENTS.md and SECURITY.md** (written now, from what G1-O8 showed). CLAUDE.md Current State: a Release 1 paragraph (what shipped, the migration and its probes, what this gate verified and how, the open owner decision on Test Public A and B). Fragile system 4 and Notification Rules 9-11: community-admin routes and `.enterApp` open on Explore; platform-admin routes stay on Profile. Fragile system 6 and the critical-risks bullet: the tab-to-domain table with Explore → nil. State Management rule 2: recount with `grep -rln 'ObservableObject' NaarsCars/Features --include='*ViewModel.swift'`. File conventions: Explore code (`ExploreView`, `MyCommunitiesView` as the before-search content, `CommunityPageView` / `CommunityPageViewModel`, `CommunityBadges.swift`). Canonical Entry Points: "Open a community's page" → `CommunityPageView(communityId:)` (item-driven); "Read a community as a visitor" → `CommunityService.fetchCommunityPreview` / `get_community_preview`, never a table read; "Narrow or filter Requests" → `CommunityContext.requestsScope` / `toggleRequestsInclusion`. Audit Notes: the follow-ups of the self-review notes. AGENTS.md: the same conventions in its short form. SECURITY.md: §2.1.1 (`public_profiles` reads `my_visible_profile_ids()`, which now includes active members of listed communities for every caller), §2.13 reviews (the `is_listed_request` arm), the RPC list (`get_community_preview`: anon and authenticated, listed only, no address columns, blocks either way), §2.26.1 (EXECUTE of the two new functions). Verify: `grep -n "My communities" CLAUDE.md AGENTS.md` shows no "under Profile" route; `grep -n "get_community_preview" CLAUDE.md SECURITY.md AGENTS.md` finds each.
- [ ] **O10. Report.** The gate report: what ran and was seen (with capture names), the device badge answer, the Test Public A and B decision (Prerequisite 3), and the PR Impact Summary: (1) `MainTabView` on the `Tab` API with Explore (no domain); (2) `NavigationCoordinator.Tab` / `NavigationIntent` / `applyNotificationIntent`: community-admin routes on Explore, platform-admin routes on Profile, every consumer updated (`MainTabView`, `MyCommunitiesView`, `MyProfileView`, `CommunityTabView`, the routing tests); a missed consumer would have dropped a push on a tab with no handler; (3) `BadgeCountManager.BadgeCounts.explore` (renamed from `profile`); a missed reader would have shown the count on Profile; (4) `CommunityContext.requestsScope` gains `.excluding`; a missed `switch` would not compile, a missed normaliser would leave an empty feed (tests in Task 8); (5) the server widenings and the new RPC with their probes; (6) the App Store checklist: no permission, SDK, entitlement or privacy-manifest change; data shown to signed-in non-members widened to what guests already see (privacy policy text, Task 11); account deletion, reporting (now also on the community page), blocking and moderation intact; notification delivery unchanged. Commit (the Files paths) `[R1-T12] Release 1 gate` with the report, `CLAUDE.md`, `AGENTS.md` and `SECURITY.md`; the push waits for the owner.

---

## New files

| Path (Xcode navigator path) | Target | Task | Fallback when the MCP is unavailable |
|---|---|---|---|
| `NaarsCars/UI/Components/Common/CommunityBadges.swift` | NaarsCars | 2 | `UI/Components/Common/NotificationBadge.swift` |
| `NaarsCars/Features/Community/Views/ExploreView.swift` | NaarsCars | 4 | `Features/Community/Views/MyCommunitiesView.swift` |
| `NaarsCars/Features/Community/ViewModels/CommunityPageViewModel.swift` | NaarsCars | 5 | `Features/Community/ViewModels/MyCommunitiesViewModel.swift` |
| `NaarsCars/Features/Community/Views/CommunityPageView.swift` | NaarsCars | 5 | `Features/Community/Views/MyCommunitiesView.swift` |
| `NaarsCars/NaarsCarsTests/Features/Community/CommunityPageViewModelTests.swift` | NaarsCarsTests | 5 | second class in `MyCommunitiesViewModelTests.swift` |
| `NaarsCars/NaarsCarsTests/Features/Requests/RequestsHeaderTests.swift` (group created with `XcodeMakeDir`) | NaarsCarsTests | 8 | second class in `Core/Storage/CommunityStoreScopingTests.swift` |
| `supabase/migrations/20261021_0001_community_preview.sql` | none | 1 | n/a |
| `Docs/qa/push-fixtures/new_ride_other_community.apns` | none | 9 | n/a |
| `Docs/qa/2026-10-2x-community-release1-gate.md` | none | 12 | n/a |

## Interfaces later releases rely on

- **Screens:** `ExploreView` (root of the search tab; Release 2 adds `.searchable` and the search view model here), `MyCommunitiesView` (the before-search content and the Explore intent consumer, `MyCommunitiesView.exploreRoute(for:)`), `CommunityPageView(communityId:)` (Release 2 adds the area map and Merge under Manage; Release 3 the offers rules), `CommunityTabView` (the Town Hall tab).
- **ViewModels:** `CommunityPageViewModel` (`CommunityPageMode`, `CommunityVisitorAction`, `load()`), `MyCommunitiesViewModel` (`listedToShow`, `loadIfStale()`, leave, mute, `didJoin`), `RequestsDashboardViewModel.header(scope:activeMemberships:isGuest:)` and `openCounts`, `TownHallFeedViewModel.communitySwitchNotice`, `LeaderboardViewModel(communityId:)`.
- **Entry points:** `NavigationCoordinator.Tab.explore` / `.townHall`, `NavigationIntent.explore`, `NavigationCoordinator.Tab.refreshDomain`, `CommunityContext.listedCommunities` / `loadListedCommunities()` / `joinPolicy(for:)` / `toggleRequestsInclusion(_:)`, `RequestsScope.excluding`, `CommunityJoinPolicy.open` with `chipText` / `subtitleText` / `ruleSentence` / `systemImage`, `CommunityPolicyChip`, `CommunityMonogram`, `BadgeCounts.explore`, `WelcomeEntryRoute.lookAroundFirst`.
- **Server:** `get_community_preview(p_community_id uuid) → jsonb` with the row shape in Task 1 (`success`, `community{id, name, description, join_policy, is_public, is_default, member_count, timezone}`, `requests[{type, id, title, date, time, timezone, seats, poster_id, poster_name, poster_avatar_url}]`, `posts[{id, type, title, content, created_at, author_id, author_name, author_avatar_url, comment_count}]`; refusal code `not_listed`); keys are only ever added (Release 3: areas; Release 2: `is_example` filtering and the service area). `is_listed_request(uuid, uuid)`. `my_visible_profile_ids()`'s listed-member arm must also skip `is_test` communities for non-members when Release 2 adds the flag.

## Self-review notes

- **Spec coverage (Release 1 paragraph and 4.3, 4.9).** Tab migration and four tabs plus Explore with the badge and the device check: Tasks 4, 12 O1/O3. Explore flat list, your communities with roles and Requests to join, saved code, Have an invite code? (guest prompt), Start a community, My communities and admin entries moved: Tasks 4, 6. Community page without the map, rule sentence, live requests, recent posts, visitor bar, member actions, leaderboard, guidelines, Manage: Task 5. `get_community_preview` and the `public_profiles` extension: Task 1. Leaderboard out of the tab bar: Tasks 5, 7. Slimmer Profile: Tasks 4, 10. Welcome: Task 10. Merged feed with include/exclude chips, policy chip on every card, title menu with counts, Helping: Tasks 8, 9. Push behaviours: Task 9 (request on top) and Task 7 (Now in). About this community and Find communities: Tasks 7, 9. RefreshCoordinator mapping, `setVisibleDomain` single site, the Messages teardown, the bell-sheet routing and guest gating: Global Constraints, Task 4, Task 12 O6-O7.
- **Decisions the owner can veto.** (1) The Ask to join and Invite only sentences drop the spec's "only then are addresses shared": it becomes true only at Release 3b, and the page must not promise it before; the Open sentence is the spec's (an open community cannot exist before 3b). (2) Reviews of listed communities become readable to signed-in visitors in this release (4.6's builder's call), so a poster's profile reached from the page is complete. (3) The title menu shows for members of one community (About and Find live there), and Requests' title is then that community's name with its rule as the subtitle. (4) Tiles read Open, Mine, Helping (spec 4.3), raw values unchanged. (5) The visitor page offers Report this community in its toolbar (App Store 1.2: community names and descriptions are user content), beside the spec's member Report. (6) Members see no requests or posts on their own community's page (S4); visitors see at most 10 requests and 5 posts and no "See all". (7) Pending rows in Explore keep their menu (Report, Withdraw) and do not open the page. (8) A platform admin visiting a community they are not in gets no Manage; Profile's Admin panel covers them.
- **Not placed in Release 1:** the service-area map and distances (Release 2); "areas" on visitor rows (Release 3; rows carry no location at all now); S2's status chip left off on the Open tile (its reason, "Open" printed twice, appears only with the Open policy in Release 3); the Example chip and `is_example` (Release 2); search, "Use my location", Get started search-first and "remembers the community a guest was viewing" (Release 2); S8's button order and labels other than the guest button; the synthesis' "Posting to <community>" header and quick actions (not in the spec).
- **Follow-ups recorded:** `InviteCodeEntrySheet` has no caller after Task 10; `CommunityJoinOptionsView`'s public list remains on onboarding and the waiting screen until Release 2; `NaarsCarsUITests` drives `community.segmented` (removed) and does not run in CI; the unused keys of the removed segment stay in the catalog; `my_visible_profile_ids()` grows with listed membership (fine at today's size; revisit with town-sized communities).
- **Type and name consistency:** checked across tasks for `CommunityJoinPolicy.chipText/subtitleText/ruleSentence/systemImage`, `CommunityPolicyChip(policy:size:)`, `CommunityMonogram.initials(for:)`, `CommunityContext.listedCommunities/loadListedCommunities()/joinPolicy(for:)/toggleRequestsInclusion(_:)`, `CommunityPreview` and its nested types, `fetchCommunityPreview(communityId:)`, `fetchCommunityPreviewResult/Calls`, `CommunityRefusalCode.notListed`, `NavigationCoordinator.Tab.townHall/.explore/.refreshDomain`, `NavigationIntent.explore`, `BadgeCounts.explore`, `clearExploreBadge()`, `MyCommunitiesView.ExploreRoute/exploreRoute(for:)`, `CommunityPageMode`, `CommunityVisitorAction`, `CommunityPageViewModel(communityId:service:communityContext:isGuest:)`, `LeaderboardViewModel(communityId:)`, `MyCommunitiesViewModel(isGuest:now:)/listedToShow/listedLoadFailed/loadIfStale()`, `GuestRestrictionReason.startCommunity`, `communitySwitchNotice`, `RequestsScope.excluding`, `OpenRequestCounts`, `openCounts(in:)`, `RequestsHeader`, `header(scope:activeMemberships:isGuest:)`, `WelcomeEntryRoute.lookAroundFirst`, and the SQL names `get_community_preview`, `is_listed_request`, `my_visible_profile_ids`.
- **New test count:** Tasks 2 (6), 3 (2), 4 (5), 5 (11), 6 (4), 7 (3), 8 (12), 9 (2), 10 (1) = 46, the figure G3 checks.
