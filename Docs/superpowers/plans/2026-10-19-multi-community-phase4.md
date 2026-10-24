# Multi-community Phase 4 (multi-membership polish) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Phase 4 client: the "N more in your other communities" hint when Requests is narrowed; community chips on bell rows; the client half of the real announcement push (D13); one new notification type, `membership_update`, on every registry layer with its routes and fixtures; the Universal Link `https://naarscars.com/join#<code>` (entitlement, `onOpenURL`, parser, signed-in join sheet, signed-out Welcome banner, guest prompt) replacing the dead `AppDelegate` URL path; the community time zone (set from the device at creation, shown and editable in Settings, and used as the default of the ride and favor forms); and the open render and copy follow-ups from the Phase 2 and Phase 3 gates.

**Architecture:** Client-side wherever the data is already on the device. The hint is a second local count over the rows the dashboard already holds (D6: the merged feed loads every community; no RPC). Bell chips reuse `CommunityContext.chipText(for:respectingScope:)` and `NaarsChip`. Universal Links arrive through SwiftUI `onOpenURL` on the `WindowGroup`'s content, go through one pure parser (`DeepLinkParser.parse(url:)`) and one small handler (`IncomingLinkHandler`) that always saves the code in `PendingInviteStore` first and then routes by launch state; every screen that already reads the store (Welcome, onboarding, My communities) re-reads it on a new `PendingInviteStore.didChange` notification. `membership_update` follows the four-layer registry procedure; its producers and the real broadcast push are server changes that are **written and dry-run but GATED** (decision A5 point 2) in the companion SQL plan. `RefreshCoordinator`, realtime, the send path, reactions, SwiftData models and mappers, and `BadgeCountManager` are not modified.

**Tech Stack:** Swift 6.3 toolchain in Swift 5 language mode, SwiftUI, supabase-swift, XCTest, Xcode 26.6, iOS 26.0 deployment target.

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` §4 "Phase 4 — Multi-membership polish" (lines 972-976, in full), §5 (the notification-routing, push, badge and App Store rows), D13, D15, D22, under `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` amendment **A5** (wins where they differ). The server contract is **`Docs/superpowers/plans/2026-10-19-multi-community-phase4-sql.md`** (File A applied now; Files B and C GATED); this plan cites its blocks. Read all three before starting a task.

## Global Constraints

- Deployment target `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; `SWIFT_VERSION = 5.0`; `SWIFT_APPROACHABLE_CONCURRENCY = YES`; `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. No build-setting change, no new permission, SDK or Info.plist key. **One new entitlement**, `com.apple.developer.associated-domains = ["applinks:naarscars.com"]`, in both entitlement files (Task 5; decision A5 point 1). No `CFBundleURLTypes` custom scheme is added (the app registers none today, `NaarsCars/Info.plist`), so nothing new can be opened by a crafted `naarscars://` link.
- `RefreshCoordinator.swift` is not edited and **no coordinator call is added** in this phase. Never `invalidate` or `refreshIfNeeded` from a ViewModel. Realtime, `MessageSendManager`, reactions, SwiftData models and mappers, `BadgeCountManager` and `get_badge_counts` are not touched (`membership_update` rows are counted by the bell's existing `else 'notification:' || id` arm, SQL plan "What the server needs").
- **Notification registry: 33 → 34 types.** `membership_update` is added to the Swift enum, `NotificationTypeRegistry.allTypes`, `supabase/functions/_shared/notificationTypes.ts` and the SQL `valid_notification_type` CHECK and `should_notify_user` (SQL plan File A) in this phase. **No server function writes a `membership_update` row until the A5 gate opens** (SQL plan File C, NOT APPLIED). The pre-community App Store build has no tolerant decoder (`NotificationType` decoding in that build throws on an unknown string, so one such row would fail its whole bell list); the Phase 1+ builds decode an unknown type as `.other` (`Core/Models/AppNotification.swift:149-161`).
- **Push payload keys** used by the new routes: `community_id` (existing), `membership_event` (new: `approved` | `owner`; SQL plan File C), `notification_id` (existing, added by `queue_push_notification`), `town_hall_post_id` (existing). Routing reads the payload, never a server role check: the parser stays pure (`Core/Utilities/DeepLinkParser.swift:46`).
- **An invite code is a bearer secret.** It never appears in a log line, a URL query, an analytics event or a request other than `validate_community_invite` / `redeem_community_invite`. `DeepLink.joinCommunity(code:)` is logged through `logDescription`, which hides the code (Task 3); the old `AppDelegate.handleURL` logged `url.absoluteString` (`App/AppDelegate.swift:132-133`) and is removed (Task 4).
- No new screen ViewModel is added in this phase; any that a fix needs is `final class … : ObservableObject` + `@MainActor` (State rule 2). `IncomingLinkHandler` is a `@MainActor final class` that holds no UI state. No ViewModel subscribes to a publisher or touches a repository in `init`. Copy `@State` into a local before starting a `Task` that reads it.
- Design system (`Docs/design-system/README.md`): `ColorTheme` tokens only (no `.white`, `.red`, hex literals), tags through `NaarsChip`, counts through `NotificationBadge`, failures through `.errorBanner(message:)` or a warning toast, every scrolling screen on `Color.naarsBackground`. Every interactive element gets an `accessibilityLabel`; new identifiers under `requests.otherCommunities.*`, `notifications.row.community`, `community.settings.timezone`, `welcome.inviteCode.*` (existing), `community.invite.*` (existing).
- Strings: every user-facing string is a key in `NaarsCars/Resources/Localizable.xcstrings` with `en`, `es`, `ko`, `vi`, `zh-Hans`, `zh-Hant`, added **only** with `python3 -I scripts/add-localization-keys.py build/P4-T<n>-keys.json`. Each task lists its keys and English; the implementer writes the five machine translations in the tone of neighbouring keys, keeping `%@`, `%lld`, `%1$@`. Counts use the two-key idiom (`<key>_one` / `<key>_other`, as `MyCommunitiesView.swift:501`). Never remove or edit an existing key (a changed sentence is a new key and the call site moves to it).
- **New Swift files** (decision 3): open this worktree's project (`.claude/worktrees/naarscars-multi-community-roadmap-f08594/NaarsCars/NaarsCars.xcodeproj`), `XcodeListWindows`, confirm the workspace path, `XcodeLS` the target group (navigator paths start `NaarsCars/…`), then `XcodeWrite`. If another project is open, or the MCP cannot add the file, write the file to disk, report "not yet in the project", and do not claim a green build. Let Xcode go idle (or quit it) before the Lane B build. Every task that creates a Swift file lists it **and** `NaarsCars/NaarsCars.xcodeproj/project.pbxproj` in its commit. Never hand-edit `project.pbxproj`. Entitlement files and JSON are edited with normal tools (they are already in the project or are not build inputs).
- **Chain stop rule (orchestrator).** When a task reports "not yet in the project", no later task runs until the file is in the right target, `BUILD` is green, the task's tests pass and its commit exists.
- One build at a time on this Mac. One headless simulator (`iPhone 16`, iOS 26.x). Unit tests run with the simulator **signed out**. Never run `RideServiceTests`, `FavorServiceTests`, `TownHallServiceTests` or the live cases of `TownHallFeedViewModelTests` while signed in. URLProtocol stubs are registered in `setUp` and reset and unregistered in `tearDown` (`CommunityServiceURLProtocol`, `NaarsCarsTests/Core/Services/CommunityServiceTests.swift:11-87`).
- Every task ends with a green Lane B build, its listed tests passing, and one commit whose subject starts `[P4-T<n>]` and whose body ends with the Co-Authored-By trailer the executing session was given. Stage files by path only; never `git add -A` / `git add .`. Tasks never push.
- **Every `#Preview` that names a DEBUG-only type sits inside `#if DEBUG … #endif`** (the Phase 2/3 idiom, `Features/Admin/Views/CommunitiesAdminView.swift:319-334`). Each UI task runs `PREVIEWGUARD` on its touched view files before GREEN; Tasks 5 and 13 run `RELEASE`.
- **Live checks** need the owner signed in and SQL plan File A applied; they are executed together in Task 13. A check that writes to production is marked **(writes)**, runs only with the owner's go-ahead, and names its clean-up.
- Models: opus for every fragile seam (notification registry and routing, push payloads, `DeepLinkParser` / `NavigationCoordinator` / `AppDelegate`, entitlements, every task that changes a Supabase RPC call site, launch-root transitions) and for SQL; sonnet for mechanical work (string keys, documentation, simple view tweaks); never fable (task index).

### Commands (used by every task; `<n>` is the task number)

```bash
# BUILD (from the worktree root). Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build > build/P4-T<n>-build.log 2>&1; echo "exit=$?"
grep -n "error:" build/P4-T<n>-build.log | head -20
# New warnings: every "warning:" line naming a file this task touched must also appear in build/P4-baseline-build.log (Task 1 Step 0).
grep -n "warning:" build/P4-T<n>-build.log | grep -E "<touched file basenames joined with |>"

# RED (compile-level failing test). Expected: exit≠0 and the named compile error.
xcodebuild build-for-testing -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/DerivedData -quiet > build/P4-T<n>-red.log 2>&1; echo "exit=$?"; grep -n "error:" build/P4-T<n>-red.log | head

# TEST <ONLY> = one or more -only-testing:NaarsCarsTests/<Class>[/<method>]. Expected: exit=0, 0 failures.
rm -rf build/P4-T<n>.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' <ONLY> -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P4-T<n>.xcresult -quiet > build/P4-T<n>-test.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P4-T<n>.xcresult

# FULL = CLAUDE.md's Lane B full unit-suite command, signed out. Expected: exit=0, 0 failures; skips only in the session-gated classes.
rm -rf build/P4-T<n>-full.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P4-T<n>-full.xcresult -quiet > build/P4-T<n>-full.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P4-T<n>-full.xcresult

# PREVIEWGUARD <files> = the touched view files. Prints every #Preview line outside an #if DEBUG block. Expected: no output.
# (An approximation: it pairs #if DEBUG with the next top-level #endif; RELEASE is the authoritative check.
#  Pre-existing unwrapped previews that name no DEBUG-only type, e.g. MyProfileView.swift:792, are allowed: Phase 3 gate.)
awk 'FNR==1{d=0} /^#if DEBUG/{d=1} /^#endif/{d=0} /^#Preview/{if(!d) print FILENAME":"FNR": #Preview outside #if DEBUG"}' <files>

# RELEASE = a Release build for the simulator (no signing needed), into the same DerivedData (one per worktree on this Mac,
# as the Phase 3 gate did). Catches DEBUG-only names used outside #if DEBUG. Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Release -derivedDataPath build/DerivedData -quiet build > build/P4-T<n>-release.log 2>&1; echo "exit=$?"
grep -n "error:" build/P4-T<n>-release.log | head -20

# REGISTRY = the cross-layer check. Expected: exit 0 and "34 types in sync" (after Task 1, which also makes it read the SQL CHECK).
scripts/validate-notification-types.sh

# ENTITLEMENTS = the entitlements the build applied (simulator build). Expected: the associated-domains key with applinks:naarscars.com.
# Not `codesign -d --entitlements`: a simulator .app keeps its entitlements in the binary's __TEXT,__entitlements section,
# not in the code signature, so codesign prints an empty <dict></dict> (checked on this worktree's build, 2026-10-19).
# The .xcent the build writes is the readable copy; at 4956682 it holds application-identifier WT4DGUYKL4.com.NaarsCars,
# aps-environment, com.apple.developer.applesignin and com.apple.developer.weatherkit.
plutil -p build/DerivedData/Build/Intermediates.noindex/NaarsCars.build/Debug-iphonesimulator/NaarsCars.build/NaarsCars.app-Simulated.xcent
# ENTITLEMENTS-RELEASE = the same after RELEASE (Release reads NaarsCars.entitlements; aps-environment reads production).
plutil -p build/DerivedData/Build/Intermediates.noindex/NaarsCars.build/Release-iphonesimulator/NaarsCars.build/NaarsCars.app-Simulated.xcent
```

`FULL` runs at the end of Tasks 2, 4 and 11 (fragile systems 4 and 5, high-blast seams) and in Task 13. Before the first `FULL`, confirm the simulator is signed out (install, launch, a screenshot shows Welcome); if it is signed in, stop and ask the owner. Record executed / passed / skipped in each task report. A new test file is in the right target when its `TEST` run reports the expected number of executed tests.

### Task index

| Task | Deliverable | Model | Effort |
|---|---|---|---|
| 1 | `membership_update` on every client layer (enum, registry, TS registry, fixtures, membership refresh); `validate-notification-types.sh` also checks the SQL CHECK | opus | high |
| 2 | Routing: `membership_update` → My communities or that community's Members (which refreshes a stale role first); the broadcast push contract → Announcements; push fixtures | opus | high |
| 3 | Universal Link parser and route: `DeepLinkParser.parse(url:)` (decoded fragment), `DeepLink.joinCommunity(code:)` (code hidden in logs), `NavigationIntent.joinCommunity`, guest prompt reason, `Constants.URLs.joinLink(code:)`; the Profile row drives the one My communities destination | opus | high |
| 4 | Incoming URLs: `onOpenURL` → `IncomingLinkHandler` → `PendingInviteStore` + route; `PendingInviteStore.didChange`; Welcome, onboarding and My communities re-read the store; the deprecated `AppDelegate` URL path removed; DEBUG `-debugIncomingURL` | opus | high |
| 5 | Associated Domains entitlement (both files), the `apple-app-site-association` file in the repo, the share message and the QR (the bare link) carry it behind `Constants.Community.shareInviteLinks` | opus | medium |
| 6 | "N more in your other communities" hint on a narrowed Requests list | sonnet | medium |
| 7 | Community chips on bell and announcement rows | sonnet | medium |
| 8 | Community time zone: sent at creation (`create_community(p_timezone)`), shown and editable in Settings; `TimeZonePicker` shows an off-list zone | opus | high |
| 9 | Ride and favor forms default to the posting community's time zone | sonnet | medium |
| 10 | Gate follow-ups (1): render and copy fixes from the Phase 2 and Phase 3 gates | sonnet | medium |
| 11 | Gate follow-ups (2): the admin panel's title after a rename; the archive confirmation survives the move to onboarding or the waiting screen; the A3 warning after an archive (by design, pinned) | opus | high |
| 12 | Documentation for Phase 4 | sonnet | medium |
| 13 | Phase gate | opus | high |

### Prerequisites outside this plan

1. **Owner, before the first signed on-device build after Task 5, before the next archive and (for b) before the release reaches users; not before this plan's simulator tasks:** (a) enable the **Associated Domains** capability on the App ID `WT4DGUYKL4.com.NaarsCars` in the Apple Developer portal (Certificates, Identifiers & Profiles → Identifiers → `com.NaarsCars` → Associated Domains → Save), then let Xcode's automatic signing regenerate the development and distribution profiles (or regenerate them by hand); an archive whose profile lacks the entitlement Task 5 adds **fails to sign**, and so does a **signed Debug build on the owner's own device** (automatic signing cannot add Associated Domains to a development profile until the App ID has the capability; simulator builds are not signed against a profile and are unaffected). So (a) is needed before the first on-device run after Task 5, not only before the archive. (b) Host `Docs/universal-links/apple-app-site-association` (written by Task 5, exact text in Task 5) at `https://naarscars.com/.well-known/apple-app-site-association`: HTTPS with a valid certificate, `Content-Type: application/json`, no redirect, no file extension, reachable without cookies; confirm with `curl -sI https://naarscars.com/.well-known/apple-app-site-association` (200, `application/json`) and, a day later, Apple's CDN copy `curl -s https://app-site-association.cdn-apple.com/a/v1/naarscars.com`. **The file must be live before the release reaches users, not only before the archive:** devices fetch it through Apple's CDN when the app is installed or updated, and a device that fetched nothing (or a 404) does not treat the links as Universal Links until a later update or re-install. Host it, and check the CDN copy, before the build is released (phased release included). (c) Host the landing page at `https://naarscars.com/join` (described in Task 5; not built here). (d) After (b) and (c) are live, set `Constants.Community.shareInviteLinks = true` (one line, Task 5) in the release-prep commit so new invites carry the link. Simulator and unit verification need none of these.
2. **SQL plan File A is applied before Task 8 runs** (orchestrator, SQL plan runbook steps 1-4). Task 8's client sends `p_timezone` to `create_community`; against the live 3-argument function PostgREST answers "Could not find the function" and Create fails. File A is safe for every installed build (SQL plan "What old clients see"). Task 8 Step 0 checks it.
3. **SQL plan Files B and C stay NOT APPLIED.** They are dry-run and probed by the orchestrator now; they are applied only when the owner confirms from App Store Connect that no pre-community build remains in use (A5 point 2). No task in this plan depends on them: Tasks 1-2 ship the registry and the routes, which are dormant until then, and Task 13 exercises the routes with `simctl push` fixtures.
4. The working tree is clean at `4956682` ([P4-plan]) apart from the Phase 4 and Phase 5 plan files under `Docs/superpowers/plans/2026-10-19-*` (Task 1 Step 0); those are committed by the orchestrator before Task 1.

## Review Focus

These are not exercised by any test the spec names. Each is pinned in its owning task.

1. **A Universal Link tapped while the app is not running, or before sign-in finished.** Expected: the code is saved before anything else, and exactly one join sheet opens (or, signed out, the Welcome banner shows) once the app is ready; never two sheets, never a lost code. Pinned by Task 4 (`testNotReady_DefersAndReplaysOnceWhenGuest`, `testNotReady_AuthenticatedReplayDoesNotRouteTwice`, `testAuthenticated_SavesCodeAndRoutesJoinIntent`) and Task 13 O3 (cold start with `-debugIncomingURL`).
2. **The code stays out of logs, queries and servers until redemption.** Expected: the parser reads only the fragment and refuses a code in the query or path; navigation logs show `joinCommunity(<code>)`. Pinned by Task 3 (`testParseURL_CodeInQueryOrPathIsIgnored`, `testJoinCommunityLogDescriptionHidesTheCode`) and Task 4 (no `url.absoluteString` log left: `grep`).
3. **A link while Welcome or onboarding is already on screen.** Expected: the banner or the prefilled join appears without a relaunch. Pinned by Task 4 (`testSave_PostsDidChange`) and Task 13 O3.
4. **A link while My communities is already open (from the Profile row or from an intent), or while one of its sheets is up, or under a pushed screen.** Expected: Join opens once with the code; with another sheet up, or Admin Panel pushed on top, the code stays in the saved-code row (`MyCommunitiesView.swift:91-93`) and nothing is replaced. Pinned by Task 3 (the Profile row drives the same `showMyCommunities` destination, so no second copy is pushed), Task 4 (`testStoreChange_OpensJoinWhenVisibleWithNoSheet`, `testStoreChange_NeverOpensUnderASheetOrWhenHidden`) and Task 13 O3 (captures, row-opened and intent-opened).
5. **A `membership_update` row or push on any build.** Expected: on this build it routes (Task 2); on a Phase 1-3 build it decodes as `.other` and opens the dashboard; on the pre-community build it never arrives, because no producer is live (SQL plan File C, GATED). Pinned by Task 1 (`testUnknownFutureRawValueDecodesAsOther`, renamed from `testUnknownRawValueDecodesAsOther` at `NotificationTypeDecodingTests.swift:54` and moved to `probe_future_type` in Step 0b, with the raw-type cache tests; and the new `testDecode_MembershipUpdate`) and the SQL plan's precondition P3.
6. **The hint count equals what the narrow hides, for the current filter.** Expected: rows with no community never count (the narrow shows them, `Core/Models/Community.swift:92-97`), rows the list itself hides for time never count, and `.all` shows no hint. Pinned by Task 6.
7. **A branch build with Task 8 against a server without File A.** Expected: impossible in the gate (Prerequisite 2, Task 8 Step 0); if it happens, Create shows `community_error_generic` and nothing is written. Task 8 Self-check.
8. **The archive of the account's only community.** Expected: the confirmation is readable on the onboarding root the app moves to (Phase 3 gate follow-up). Pinned by Task 11 (`testArchive_OnlyActiveCommunityLeavesARootNotice`).

---

### Task 1: `membership_update` on every client registry layer

**Model:** opus, high effort (the notification type registry is a high-blast seam; CLAUDE.md Notification rule 7 and `.cursor/rules/02-notification-contract.mdc`) · **Files:**
- Modify: `NaarsCars/Core/Models/AppNotification.swift:66-67` (new case after `accountRestricted`), `:72-109` (`icon`), `:111-127` (`canBeDisabled`), `:129-146` (`preferenceKey`, no arm: default nil), `:174-196` (`affectedDomains`), `:198-214` (`entityIdKey`, default nil)
- Modify: `NaarsCars/Core/Models/NotificationTypeRegistry.swift:12-46`
- Modify: `supabase/functions/_shared/notificationTypes.ts:32-34` (the only file under `supabase/` this plan touches; the SQL plan deploys it)
- Modify: `NaarsCars/Core/Services/PushNotificationService.swift:882` (`PushRefreshPlan.membershipRefreshTypes`)
- Modify: `scripts/validate-notification-types.sh:26-59`
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/NotificationFixtures.swift:11-` (`allRawValues`), `:47-` (`mandatoryTypes` gains `membership_update`), `:59-` (`preferenceMapping` gains `"membership_update": nil`), so the existing table tests `testCanBeDisabledMatchesMandatoryTypeFixture` / `testPreferenceKeyMappingMatchesFixtureForAllNotificationTypes` (`NotificationTypeDecodingTests.swift:27-43`) cover it, `NaarsCarsTests/Core/Decoding/NotificationTypeDecodingTests.swift:16` (33 → 34) and `:54-146` (the stand-in unknown type, Step 0b), `NaarsCarsTests/Core/Models/NotificationTypeDomainMappingTests.swift`, `NaarsCarsTests/Core/Models/AppNotificationTests.swift`, `NaarsCarsTests/Core/Services/PushNotificationServiceTests.swift`
- Reference: SQL plan File A blocks 1-2 (CHECK and `should_notify_user`), File C (producers, GATED)

**Interfaces:**
- Produces: `NotificationType.membershipUpdate = "membership_update"`. `icon` → `"person.2.badge.gearshape.fill"`; `canBeDisabled` → **false** (joins the account-status arm with `userApproved`, `userRejected`, `accountRestricted`: a membership change must reach the person, and `should_notify_user` answers true for it, SQL plan File A block 2); `preferenceKey` → nil; `affectedDomains` → `[.dashboard]` (joining or owning a community changes the merged Requests feed; the same arm as `userApproved`); `entityIdKey` → nil (the payload's `community_id` is not an entity of any coordinator domain; the dashboard is invalidated, as for `userApproved`). `PushRefreshPlan.membershipRefreshTypes` gains `.membershipUpdate` (the push refreshes `CommunityContext` memberships, `PushNotificationService.swift:817-821`).
- `notificationTypes.ts`: `MEMBERSHIP_UPDATE: 'membership_update',` before `OTHER`.
- `validate-notification-types.sh`: a fourth source, `SQL_TYPES`, read from **one named file**, `SQL_CHECK_FILE="${SQL_FILE:-supabase/migrations/20261019_0001_phase4_registry_and_timezone.sql}"`, extracting every `'…'` literal between that file's last `add constraint valid_notification_type` and the next `;`. Not "the newest migration by `sort | tail -1`": the folder mixes `YYYYMMDD_XXXX_` and 14-digit `YYYYMMDDHHMMSS_` names, which do not sort by date against each other (`20261019_0001…` sorts after `20261019120000…`). A comment above the variable says that whoever next changes the CHECK points it at the new file in the same change (Notification rule 7), and the script fails with "<file> does not define valid_notification_type" if the named file has no such constraint; a fourth diff "MISMATCH between Swift enum and the SQL CHECK"; the final line reports the four layers. If the named file does not exist the script fails with "No migration defines valid_notification_type: <file>". The environment variable `SQL_FILE=<path>` overrides the default (used only before File A's migration file is committed, Step 0).

- [ ] **Step 0: Preconditions and baseline.** `git status --porcelain` lists nothing but `Docs/superpowers/plans/2026-10-19-*` plan files (Prerequisite 4; else stop and ask; never commit, stash or discard files of another pass). Build `HEAD` with `BUILD`'s command into `build/P4-baseline-build.log`; record the warning count. Read the live CHECK through the Supabase MCP (read only): `select pg_get_constraintdef(oid) from pg_constraint where conname = 'valid_notification_type'`. If it already contains `membership_update` (File A applied), the script's SQL check passes once File A's migration file is committed; if File A is not yet committed, Step 4 runs the script with `SQL_TYPES` reading the SQL plan's File A block (copy it to `build/P4-T1-check.sql` and pass it as `SQL_FILE=build/P4-T1-check.sql`, an override the script accepts) and reports which.
- [ ] **Step 0b: Move the unknown-type tests off `membership_update`.** Five existing tests use `"membership_update"` as their example of a type the app does not know, and this task makes it known, so they would fail (`.membershipUpdate` instead of `.other`, and `NotificationType(rawValue:)` no longer nil). In `NotificationTypeDecodingTests.swift`, replace the string `"membership_update"` with `"probe_future_type"` (a name no layer will ever use; the SQL probe's `probe_unknown_type` is the same idea) in: `testUnknownRawValueDecodesAsOther` (`:54-57`), `testAppNotificationWithUnknownTypeDecodes` (`:70-75`), the shared `unknownTypeJSON` (`:79`), `testAppNotificationWithUnknownTypeKeepsRawValue` (`:87-96`, the two `typeRawValue` / encoded `type` assertions), `testSyncStoresOriginalRawTypeInCachedRow` (`:106-123`, the stored `type`, the `NotificationType(rawValue:) == nil` check and the mapped `typeRawValue`) and `testSyncHealsRowStoredAsOther` (`:127-146`). Rename `testUnknownRawValueDecodesAsOther` to `testUnknownFutureRawValueDecodesAsOther` so a later reader does not look for `membership_update` in it. **Every assertion stays as it is** (only the string changes), so the tolerant decoder (`AppNotification.swift:149-161`) and the raw-type cache stay pinned. Afterwards `grep -n '"membership_update"' NaarsCars/NaarsCarsTests/Core/Decoding/NotificationTypeDecodingTests.swift` names only `testDecode_MembershipUpdate`. (`grep -rln membership_update NaarsCars` at `4956682` names only this test file, so no other test uses it as a stand-in.)
- [ ] **Step 1: Write the failing tests** (CLAUDE.md fixture-test gate for registry changes):

```swift
// NotificationTypeDecodingTests
func testFixturesContainExactlyAllNotificationTypeRawValues() // edited (:15-18): count == 34
func testUnknownFutureRawValueDecodesAsOther()             // renamed from testUnknownRawValueDecodesAsOther (:54), Step 0b
func testDecode_MembershipUpdate()                         // "membership_update" → .membershipUpdate; typeRawValue kept
// NotificationTypeDomainMappingTests
func testMembershipUpdate_RefreshesDashboardWithoutEntityKey()   // affectedDomains == [.dashboard]; entityIdKey == nil
func testMembershipUpdate_IsMandatoryWithNoPreference()          // canBeDisabled == false; preferenceKey == nil
// AppNotificationTests
func testDecode_MembershipUpdateRowKeepsCommunityId()      // a row with community_id decodes; communityId set
// PushNotificationServiceTests
func testPushRefreshPlan_MembershipUpdateRefreshesMemberships()  // ["type":"membership_update","community_id":"<A>"] →
                                                                 // domains [.dashboard], entityId nil, refreshesMemberships true
```
- [ ] **Step 2: RED.** `RED`. Expected: "type 'NotificationType' has no member 'membershipUpdate'".
- [ ] **Step 3: Implement** the enum case and its five switch arms, the registry entry, `NotificationFixtures.allRawValues`, `PushRefreshPlan.membershipRefreshTypes`, the TS constant, and the script's fourth layer. Fix every exhaustive `switch` the compiler names (the router's `notificationIntent(for:)` has a `default`, `NotificationNavigationRouter.swift:183`; Task 2 gives the type its route).
- [ ] **Step 4: GREEN.** `BUILD`; `REGISTRY` (expected: exit 0, "34 types in sync across Swift enum, NotificationTypeRegistry, TypeScript registry and the SQL CHECK"); `TEST` with `-only-testing:NaarsCarsTests/NotificationTypeDecodingTests -only-testing:NaarsCarsTests/NotificationTypeDomainMappingTests -only-testing:NaarsCarsTests/AppNotificationTests -only-testing:NaarsCarsTests/PushNotificationServiceTests`. Expected: 5 new tests pass, the edited count test and the six Step 0b tests pass (on `probe_future_type`), the DEBUG `registryValidation` assert (`AppNotification.swift:73-75`) does not fire.
- [ ] **Step 5: Commit** `[P4-T1] Add the membership_update notification type to every registry layer` with the files above.

Strings: none (no screen shows a type's raw name except the accessibility hint, which already reads `type.rawValue`, `NotificationRow.swift:98`). Live check: Task 13 Step 1 (CHECK and `should_notify_user` live).

---

### Task 2: Routing — `membership_update` and the announcement push

**Model:** opus (Notification Routing, fragile system 4; `DeepLinkParser`, `NavigationCoordinator`, `NavigationIntent`, `NotificationNavigationRouter`, `AppDelegate` are high-blast seams) · **Files:**
- Modify: `NaarsCars/Core/Utilities/DeepLinkParser.swift:11-33` (case), `:146-157` (new `membership_update` arm beside `user_approved` and `account_restricted`)
- Modify: `NaarsCars/App/NavigationIntent.swift:24-51`
- Modify: `NaarsCars/App/NavigationCoordinator.swift:13-29` (`NotificationIntent`), `:167-231` (`applyDeepLink`), `:242-310` (`isSameDeepLink`), `:333-382` (`applyNotificationIntent`), `:390-410` (guest gating)
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift:15-26` (init), `:171-178` (new arm)
- Modify: `NaarsCars/App/AppDelegate.swift:381-384`
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:35-41` (state), `:166` (replay list), `:206-215` (destination), `:733-760` (`applyProfileIntent`)
- Modify: `NaarsCars/Features/Community/ViewModels/CommunityMembersViewModel.swift:108-124` (init), `:159-180` (`reload`: the stale-role refresh), `NaarsCars/Features/Community/Views/CommunityMembersView.swift:13-17` (`CommunityMembersTarget.refreshesRoleFirst`), `:30-38` (passes it to the view model)
- Create (normal tools): `Docs/qa/push-fixtures/membership_update_approved.apns`, `membership_update_owner.apns`, `membership_update_owner_without_community.apns`, `broadcast_community.apns`
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/DeepLinkParserTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift`, `NaarsCars/NaarsCarsTests/Features/Community/CommunityMembersViewModelTests.swift`

**Interfaces:**
- Consumes: `CommunityMembersView(target: CommunityMembersTarget(communityId:communityName:))` (Phase 3, `Features/Community/Views/CommunityMembersView.swift`), which checks the role itself and shows its inline not-admin state when the person is not an admin (`CommunityMembersViewModel.load`, Phase 3 Task 3); `CommunityContext.isAdmin(of:)` (`App/CommunityContext.swift:170`).
- Produces: `DeepLink.communityMembers(communityId: UUID)`; `NavigationIntent.communityMembers(UUID)` (`targetTab == .profile`); `NotificationIntent.openCommunityMembers(communityId: UUID)`; `NotificationNavigationRouter.init(authService:isPlatformAdmin:isAdminOf: @escaping @MainActor (UUID) -> Bool = { CommunityContext.shared.isAdmin(of: $0) })`.
- Parser (push): `membership_update` → `membership_event == "owner"` and a well-formed `community_id` → `.communityMembers(communityId:)`; any other case (`approved`, an unknown event, no event, no community) → `.myCommunities`. (Spec §4 Phase 4: "ownership changes and second-community approvals their own tap route"; the approval route replaces D22's reuse of `user_approved` → `.enterApp`, which keeps working for the first approval, `DeepLinkParser.swift:146-148`.)
- Router (bell row; rows have no event column): `.membershipUpdate` → `.openCommunityMembers(communityId:)` when the row has a `communityId` and `isAdminOf(communityId)` (an ownership row is read after the push refreshed the memberships, `PushNotificationService.swift:819-821`); else `.openMyCommunities`.
- Announcement push (D13; the server half is SQL plan File B, GATED): the existing arm (`DeepLinkParser.swift:162-165`) already maps `broadcast` / `announcement` / `admin_announcement` with `notification_id` to `.announcements(notificationId:)` and the coordinator opens the Announcements sheet (`MainTabView.swift:277-286`, `:432-445`). **No code change**: this task pins the contract File B produces (payload keys `type`, `notification_id`, `community_id`, `town_hall_post_id`) with a parser test and a fixture, and pins that `PushRefreshPlan` for `broadcast` invalidates `.townHall` (entity key nil, `AppNotification.swift:189-191`). The bell row of a broadcast keeps its existing tap (the linked post, `NotificationNavigationRouter.swift:81-89`).
- Coordinator: `applyDeepLink` `.communityMembers(id)` → `pendingIntent = .communityMembers(id)`; `isSameDeepLink` compares by id; `applyNotificationIntent(.openCommunityMembers)` sets the intent and `selectedTab = .profile`; `.communityMembers` joins `intentIsAdminOnly` and the admin arm of `intentRequiresAuth` (guests drop it silently, as `.communityReports`). `AppDelegate`'s group (`:381-384`) gains `.communityMembers`.
- **The role the members screen checks can be stale on a push tap.** Memberships are refreshed for a push only when it is delivered in the foreground: `PushNotificationService.handlePushReceived` is called only from `AppDelegate`'s `willPresent` (`App/AppDelegate.swift:273-278`), and the membership refresh is at `PushNotificationService.swift:819-821`. A banner tapped while the app was in the background (or not running) goes from `didReceive` (`:171`) straight to `handleDeepLink` (`:357-396`) with no refresh. `CommunityMembersViewModel.reload` refreshes only while `isAwaitingMemberships` (`CommunityMembersViewModel.swift:167-169`) and then checks `communityContext.isAdmin(of:)` (`:173`). So a member just made an owner (`set_member_role` allows member → owner, SQL plan File C block 3) would land on the not-admin state, and a former admin made owner would see admin actions instead of owner ones (`callerRole`, `:138-141`, read live from the context) — the stale-role problem the Phase 3 gate recorded after a hand-over made elsewhere. Fix, in the view model: `init(…, refreshesRoleFirst: Bool = false)`; in `reload`, (1) on the first load when `refreshesRoleFirst` is true, `await communityContext.refreshMemberships()` once, before the role check, whatever `isAwaitingMemberships` says; (2) whenever the role check fails and this view model has not refreshed yet in its lifetime (`didRefreshForRole`), `await communityContext.refreshMemberships()` once and check again before setting `.notAdmin`. Each refresh is at most once per view-model lifetime, so a real member is not refreshed on every pull. `refreshMemberships()` is not a coordinator call (it touches no engine, `App/CommunityContext.swift:219-245`), so no `RefreshCoordinator` rule changes. `CommunityMembersTarget` gains `var refreshesRoleFirst = false` (beside `highlightTransfer`), and `CommunityMembersView.init` passes it.
- `MyProfileView`: `@State private var communityMembersTarget: UUID?` with `.navigationDestination(item:) { CommunityMembersView(target: CommunityMembersTarget(communityId: $0, communityName: CommunityContext.shared.name(for: $0), refreshesRoleFirst: true)) }` (item-driven, the pattern the Phase 3 gate fixed in `930e906`); `applyProfileIntent` handles `.communityMembers(id)` and clears the intent; the `.onAppear` replay list (`:166`) gains `.communityMembers`.
- Fixtures (JSON, `aps` + `type` + keys; placeholders filled in Task 13): `membership_update_approved.apns` (`"membership_event": "approved"`, `community_id`), `membership_update_owner.apns` (`"membership_event": "owner"`, `community_id`), `membership_update_owner_without_community.apns` (`"membership_event": "owner"`, no `community_id`), `broadcast_community.apns` (`notification_id`, `community_id`, `town_hall_post_id`; alert title and body of an announcement). Same shape as `Docs/qa/push-fixtures/account_restricted_community.apns`.

- [ ] **Step 1: Write the failing tests:**

```swift
// DeepLinkParserTests
func testParse_MembershipUpdateApprovedOpensMyCommunities()
func testParse_MembershipUpdateOwnerWithCommunityOpensMembers()
func testParse_MembershipUpdateOwnerWithoutCommunityOpensMyCommunities()
func testParse_MembershipUpdateUnknownOrMissingEventOpensMyCommunities()
func testParse_BroadcastPushOpensAnnouncementsAtItsNotification()   // the broadcast_community.apns keys → .announcements(notificationId: N)
// NavigationCoordinatorRoutingTests
func testApplyPushDeepLink_CommunityMembersSetsIntentForProfileTab()
func testDeferredOpenCommunityMembers_SelectsProfileTab()
func testRouter_MembershipUpdateRowForAnAdminOpensMembers()          // isAdminOf: { _ in true }, row with communityId A
func testRouter_MembershipUpdateRowForAMemberOpensMyCommunities()    // isAdminOf: { _ in false }
func testRouter_MembershipUpdateRowWithoutCommunityOpensMyCommunities()
func testCommunityMembersIsAdminOnlyForGuests()
// CommunityMembersViewModelTests (makeContext, :68-80; the stub's `result` is changed after the first load to make the context stale)
func testLoad_StaleMemberRoleRefreshesOnceBeforeShowingNotAdmin()  // context loaded as .member, stub then answers .owner →
                                                                   // load() → access .allowed; stub.fetchCount == 2; owner actions offered
func testLoad_RealMemberRefreshesOnlyOnce()                        // stub keeps .member → .notAdmin; a second load() adds no fetch
func testLoad_RefreshesRoleFirstPicksUpANewOwnerOverAStaleAdmin()  // loaded as .admin, stub answers .owner, refreshesRoleFirst true →
                                                                   // actions(for: an admin) include the transfer and role actions
```
(`testLoad_NotAdminShowsInlineStateWithoutFetching`, `:146-157`, still passes: its stub keeps answering `.member`, so the one extra refresh changes nothing it asserts.)
- [ ] **Step 2: RED.** `RED`. Expected: "type 'DeepLink' has no member 'communityMembers'".
- [ ] **Step 3: Implement**; write the four fixtures; any other exhaustive `switch` over `DeepLink` / `NavigationIntent` the compiler names gets the Profile-tab behaviour.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/DeepLinkParserTests -only-testing:NaarsCarsTests/NavigationCoordinatorRoutingTests -only-testing:NaarsCarsTests/NavigationCoordinatorTests -only-testing:NaarsCarsTests/AppDelegateNotificationHandlingTests -only-testing:NaarsCarsTests/PushNotificationServiceTests -only-testing:NaarsCarsTests/CommunityMembersViewModelTests`. Expected: all pass (14 new).
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P4-T2] Route membership_update to My communities or the community's members, and pin the announcement push` with the files above.

Strings: none. Live check: Task 13 O2 (the four fixtures).

---

### Task 3: Universal Link parser and route

**Model:** opus (deep-link routing, fragile system 4; CLAUDE.md "Current State" lists the `application(_:open:options:)` replacement as a fragile follow-up) · **Files:**
- Modify: `NaarsCars/Core/Utilities/DeepLinkParser.swift:11-33` (case), new `static func parse(url:)` after `:176`, new `extension DeepLink { var logDescription: String }`
- Modify: `NaarsCars/App/NavigationIntent.swift:24-51` (`.joinCommunity`)
- Modify: `NaarsCars/App/NavigationCoordinator.swift:155-165` (new `applyExternalDeepLink(_:)` beside `applyPushDeepLink`), `:167-231` (`applyDeepLink` arm and the log line at `:230`), `:242-310`, `:390-410` (gating), new `func guestPromptReason(for:) -> GuestRestrictionReason`
- Modify: `NaarsCars/App/MainTabView.swift:157-166` (guest guard), `:345-357` (prompt sheet takes the reason)
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:166`, `:741-743` (`.joinCommunity` opens My communities like `.myCommunities`), `:678-706` (`myCommunitiesLink()`: the row becomes a `Button` that sets `showMyCommunities`)
- Modify: `NaarsCars/Core/Utilities/Constants.swift:221-233` (`URLs`)
- Modify: `NaarsCars/App/AppDelegate.swift:393-394` (`.joinCommunity` joins the `.unknown` warning arm, `case .joinCommunity, .unknown:`; no push produces it, and the `applyPushDeepLink` group at `:381-384` would set an intent with no saved code behind it)
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/DeepLinkParserTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift`

**Interfaces:**
- Produces:

```swift
// Constants.URLs
static let universalLinkHost = "naarscars.com"            // the applinks: domain (Task 5)
static let joinPath = "/join"
static func joinLink(code: String) -> String { "\(deepLinkBase)\(joinPath)#\(code)" }   // deepLinkBase, Constants.swift:232

// DeepLink
case joinCommunity(code: String)                           // a normalized, well-formed code (CommunityInviteCode, CommunityPayloads.swift:142-155)

extension DeepLinkParser {
    /// https://naarscars.com/join#<code> (spec §4 Phase 4, D15). The code is read from the fragment only, which
    /// never reaches the web server or a referrer. Anything else is .unknown and is not routed.
    static func parse(url: URL) -> DeepLink
}
extension DeepLink {
    /// For logs: `joinCommunity(<code>)` for an invite, `"\(self)"` otherwise.
    var logDescription: String { get }
}

// NavigationIntent
case joinCommunity                                         // the code is in PendingInviteStore (Task 4); targetTab .profile

// NavigationCoordinator
/// A Universal Link: the routing table of navigate(to:) without the "open link?" confirmation (a tapped link is
/// an explicit user action, like a notification tap).
func applyExternalDeepLink(_ deepLink: DeepLink)
/// The guest prompt for an auth-required intent: `.joinCommunity` for `.joinCommunity`, `.deepLinkSignIn` otherwise.
func guestPromptReason(for intent: NavigationIntent) -> GuestRestrictionReason
```
- `parse(url:)` rules, in order: scheme `https` (case-insensitive) else `.unknown`; host equal to `universalLinkHost` (case-insensitive; `www.naarscars.com` is **not** accepted: the entitlement names only the bare domain, Task 5) else `.unknown`; `url.path` equal to `joinPath` else `.unknown` (`url.path` already drops a trailing slash: `/join/` reads `/join`, checked 2026-10-19; so `/join/NC…` and `/joinx` are refused); a non-nil `url.query` is ignored for the code (never read); `code = CommunityInviteCode.normalize(url.fragment(percentEncoded: false) ?? "")` — **the decoded fragment**: `url.fragment` keeps percent escapes, so `#NC7K%202PQ9XA` reads `NC7K%202PQ9XA`, `normalize` (`Core/Models/CommunityPayloads.swift:144-148`, letters and digits only) keeps the `20` and returns the 12-character `NC7K202PQ9XA`, which `isWellFormed` refuses; `fragment(percentEncoded: false)` returns `NC7K 2PQ9XA` (both checked with Swift 6.3 on 2026-10-19). A shared link whose code went through percent-encoding (a space or `·` typed by hand, a messenger's escaping) is therefore kept; `CommunityInviteCode.isWellFormed(code)` else `.unknown`; then `.joinCommunity(code: code)`.
- `applyDeepLink` `.joinCommunity` → `pendingIntent = .joinCommunity`; `.unknown` keeps today's `.dashboard`, but `applyExternalDeepLink` returns early for `.unknown` (an unrecognized URL opens the app where it was). The log line at `:230` uses `deepLink.logDescription`. `isSameDeepLink(.joinCommunity)` is true when the pending intent is `.joinCommunity`.
- Gating: `intentRequiresAuth(.joinCommunity) == true`; `intentIsAdminOnly(.joinCommunity) == false`. `MainTabView`'s guest guard replaces `showGuestDeepLinkPrompt = true` with `guestPromptReason = navigationCoordinator.guestPromptReason(for: intent)` and presents `GuestSignInPromptView(reason:)` with `.sheet(item: $guestPromptReason)` (the `Identifiable` idiom `GuestRestrictionReason.swift:9-13` exists for); its two buttons are unchanged (`exitGuestMode()` first, CLAUDE.md "Guest mode").
- `MyProfileView.applyProfileIntent`: `.joinCommunity` → `showMyCommunities = true`, clear the intent (My communities opens the Join sheet from the store, Task 4).
- **One way into My communities.** Today the Profile row is a `NavigationLink { MyCommunitiesView() }` (`MyProfileView.swift:678-681`), separate from the intent-driven `.navigationDestination(isPresented: $showMyCommunities)` (`:209-211`). With My communities opened from the row, a `.joinCommunity` (or `.myCommunities`) intent sets `showMyCommunities = true` and pushes a **second** `MyCommunitiesView`; that copy's `.task` opens Join from the store by itself (`MyCommunitiesView.swift:132-138`) while the first copy's Task 4 `didChange` handler opens it as well: two presenters. Fix: `myCommunitiesLink()` becomes `Button { showMyCommunities = true } label: { …same HStack… }` with `.buttonStyle(.plain)` and the existing label, value and identifier (`profile.myCommunities`), so the row and every intent drive the one destination; setting `showMyCommunities = true` while it is already true pushes nothing. This also stops a `.myCommunities` push tap (`pending_approval`, Phase 2) from stacking a copy over one opened from the row. The `NavigationLink`'s chevron and badge stay in the label.

- [ ] **Step 1: Write the failing tests** (CLAUDE.md Notification rule 8: a routing mapping is validated by tests):

```swift
// DeepLinkParserTests
func testParseURL_JoinWithWellFormedFragment()            // https://naarscars.com/join#NC7K2PQ9XA → .joinCommunity("NC7K2PQ9XA")
func testParseURL_NormalizesCaseAndSeparators()           // #nc7k-2pq9-xa and #NC7K%202PQ9XA (a percent-encoded space) → "NC7K2PQ9XA";
                                                          // fails if the parser reads url.fragment instead of fragment(percentEncoded: false)
func testParseURL_TrailingSlashPath()                     // /join/#NC7K2PQ9XA → join
func testParseURL_MalformedOrMissingCodeIsUnknown()       // no fragment, #NC123, #NC7K2PQ9X0 (0 not in the alphabet) → .unknown
func testParseURL_OtherHostSchemeOrPathIsUnknown()        // www.naarscars.com, http://, naarscars.co, /joinx, /invite → .unknown
func testParseURL_CodeInQueryOrPathIsIgnored()            // /join?code=NC7K2PQ9XA and /join/NC7K2PQ9XA → .unknown
func testJoinCommunityLogDescriptionHidesTheCode()        // logDescription does not contain "NC7K2PQ9XA"
// NavigationCoordinatorRoutingTests
func testApplyExternalDeepLink_JoinCommunitySetsIntentWithoutConfirmation()  // with a pending .dashboard intent: no
                                                                             // showDeepLinkConfirmation; pendingIntent == .joinCommunity; targetTab .profile
func testJoinCommunity_RequiresAuthAndPromptsWithTheJoinReason()  // guestPromptReason(.joinCommunity) == .joinCommunity;
                                                                  // (.conversation(x)) == .deepLinkSignIn; not admin-only
func testJoinLink_RoundTripsThroughTheParser()            // parse(url: URL(string: Constants.URLs.joinLink(code: c))!) == .joinCommunity(c)
```
(The row-as-`Button` change has no unit seam; Task 4 pins the store-change rule it relies on, and Task 13 O3 captures "link while My communities is open from the Profile row".)
- [ ] **Step 2: RED.** `RED`. Expected: "type 'DeepLinkParser' has no member 'parse(url:)'" (or "type 'DeepLink' has no member 'joinCommunity'").
- [ ] **Step 3: Implement.** `DeepLink` is not `Equatable` today; the tests compare with `if case`.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/DeepLinkParserTests -only-testing:NaarsCarsTests/NavigationCoordinatorRoutingTests -only-testing:NaarsCarsTests/NavigationCoordinatorTests`. Expected: 10 new tests pass.
- [ ] **Step 5: Commit** `[P4-T3] Parse the join Universal Link and route it to My communities` with the files above.

Strings: none (the guest prompt's `guest_prompt_title_join_community` / `guest_prompt_message_join_community` exist, `GuestRestrictionReason.swift:45, 64`).

---

### Task 4: Incoming URLs — `onOpenURL`, the pending-invite store, and the retired `AppDelegate` path

**Model:** opus, high effort (launch-time routing across every launch state, fragile systems 4 and 5; removes the deprecated `AppDelegate` URL path) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Core/Utilities/IncomingLinkHandler.swift`
- Modify: `NaarsCars/App/NaarsCarsApp.swift:77-100` (`.onOpenURL` on the `WindowGroup`'s `Group`; DEBUG launch argument)
- Modify: `NaarsCars/App/ContentView.swift:127-134` (`.onChange(of: launchManager.state.id)` also tells the handler)
- Modify: `NaarsCars/Core/Utilities/PendingInviteStore.swift:16-59` (`didChange`)
- Modify: `NaarsCars/Features/Authentication/Views/WelcomeView.swift:204-212` (`.onReceive`)
- Modify: `NaarsCars/Features/Authentication/Views/CommunityOnboardingView.swift:81-86` (`.onReceive`)
- Modify: `NaarsCars/Features/Community/Views/MyCommunitiesView.swift:46-51`, `:133-140` (`.onReceive`)
- Modify: `NaarsCars/App/AppDelegate.swift:42-45` (launch-options URL, removed), `:125-136` (`application(_:open:options:)` and `handleURL`, removed)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Utilities/IncomingLinkHandlerTests.swift`
- Modify: `NaarsCars/NaarsCarsTests/Core/Utilities/PendingInviteStoreTests.swift`

**Interfaces:**
- Consumes: `DeepLinkParser.parse(url:)`, `NavigationCoordinator.applyExternalDeepLink(_:)`, `NavigationIntent.joinCommunity` (Task 3); `PendingInviteStore` (`Core/Utilities/PendingInviteStore.swift:16-59`); `LaunchState` / `AuthState` (`App/AppLaunchManager.swift:14`, `Core/Services/AuthService.swift:738-746`); `MainTabView.offerPendingInviteIfNeeded()` (`App/MainTabView.swift:387-396`), which already opens My communities once per `MainTabView` lifetime when a code is stored and the session is authenticated.
- Produces:

```swift
extension PendingInviteStore {
    /// Posted (object nil) after save(_:) stores a code and after clear() / clearIfMatches(_:) remove one.
    static let didChange = Notification.Name("PendingInviteStore.didChange")
}

enum IncomingLinkDecision: Equatable {
    case route        // save, then coordinator.applyExternalDeepLink (main UI: authenticated or guest)
    case saveOnly     // save; the screen on show reads the store (Welcome, onboarding) or offerPendingInviteIfNeeded does
    case defer        // save; decide again once the launch state is .ready (cold start)
}

@MainActor
final class IncomingLinkHandler {
    static let shared = IncomingLinkHandler()
    init(store: PendingInviteStore = PendingInviteStore(),
         coordinator: NavigationCoordinator = .shared,
         launchState: @escaping @MainActor () -> LaunchState = { AppLaunchManager.shared.state })
    /// Returns what was done; a URL that is not a join link is ignored and nothing is saved.
    @discardableResult func handle(_ url: URL) -> IncomingLinkDecision?
    /// ContentView calls this on every launch-state change; a deferred link is decided once, on the first .ready.
    func launchStateDidChange(_ state: LaunchState)
    /// Pure: first sight of a link.
    static func decision(for state: LaunchState) -> IncomingLinkDecision
    /// Pure: a deferred link at the first .ready. Authenticated → .saveOnly, because offerPendingInviteIfNeeded
    /// opens My communities from the store on MainTabView's first appearance; routing as well would navigate twice.
    static func replayDecision(for state: LaunchState) -> IncomingLinkDecision
}
```
- `decision(for:)`: `.ready(.authenticated)`, `.ready(.guest)` → `.route`; `.ready(.unauthenticated)`, `.ready(.needsApplication)`, `.ready(.pendingApproval)`, `.ready(.banned)`, `.ready(.loading)` → `.saveOnly`; `.initializing`, `.checkingAuth`, `.failed` → `.defer`. `replayDecision(for:)`: `.ready(.guest)` → `.route`; every other `.ready` → `.saveOnly`; not ready → `.defer` (stays pending). A second link replaces a pending one (the store keeps the newest code, `save(_:)`).
- `NaarsCarsApp`: `.onOpenURL { IncomingLinkHandler.shared.handle($0) }` on the `Group` at `:78` (it receives Universal Links and any URL the system hands the scene; with `UIApplicationSupportsMultipleScenes` the scene, not the `AppDelegate`, receives URLs, `Info.plist` `UIApplicationSceneManifest`, which is why `AppDelegate.swift:127-130` never runs today). `#if DEBUG`: a `.task` that reads `UserDefaults.standard.string(forKey: "debugIncomingURL")` (set by the launch argument `-debugIncomingURL <url>`), once per process, and passes it to `handle(_:)`; this is how Task 13 exercises the path in the simulator without the hosted AASA file.
- Screens: `WelcomeView` re-reads `savedInviteCode = pendingInviteStore.peek()` on `didChange` (the banner `community_invite_saved_banner` — "You have an invite. Sign up or sign in to use it." — exists, `WelcomeView.swift:217-249`); `CommunityOnboardingView` sets `viewModel.prefilledCode = PendingInviteStore().peek()` on `didChange` (`CommunityJoinOptionsView` re-opens on a changed code, `CommunityJoinOptionsView.swift:93`); `MyCommunitiesView` on `didChange`: `storedInviteCode = PendingInviteStore().peek()`, then `if let code = Self.joinCodeToOpenOnStoreChange(storedCode: storedInviteCode, hasSheet: activeSheet != nil, isVisible: isVisible) { openJoin(with: code) }` (`:214-217`). `@State private var isVisible` is set true in `.onAppear` and false in `.onDisappear` (it is false while Admin Panel or Members is pushed on top, `:125-131`), so a hidden copy never presents; with a sheet up or the view hidden it only refreshes the saved-code row, and the row's own Join button stays the way in. `static func joinCodeToOpenOnStoreChange(storedCode: String?, hasSheet: Bool, isVisible: Bool) -> String?` is pure (the code when all three allow it, else nil). `didAutoOpenStoredCode` (`:51`) keeps its meaning for the `.task` path. Together with Task 3's single destination this keeps one presenter: a link while My communities is on screen is opened by the `didChange` handler of the one copy, never by a second copy's `.task`.
- `AppDelegate`: remove `:42-45` and `:125-136` with the `// MARK: - URL Handling` header. Nothing else calls `handleURL` (`grep -rn "handleURL" NaarsCars --include='*.swift'` returns nothing afterwards). This removes the `OpenURLOptionsKey` deprecation CLAUDE.md lists.

- [ ] **Step 1: Write the failing tests** (Review Focus 1-3):

```swift
// IncomingLinkHandlerTests (store on a UserDefaults suite; NavigationCoordinator() fresh per test)
func testAuthenticated_SavesCodeAndRoutesJoinIntent()        // .ready(.authenticated) → store.peek() == code; pendingIntent == .joinCommunity
func testGuest_SavesCodeAndRoutesJoinIntent()
func testSignedOut_SavesCodeWithoutRouting()                 // .ready(.unauthenticated) → saved; pendingIntent nil
func testNeedsApplication_SavesCodeWithoutRouting()
func testNotReady_DefersAndReplaysOnceWhenGuest()            // .initializing → saved, no intent; launchStateDidChange(.ready(.guest))
                                                             // → .joinCommunity once; a second .ready call routes nothing
func testNotReady_AuthenticatedReplayDoesNotRouteTwice()     // .checkingAuth then .ready(.authenticated) → no intent (the
                                                             // MainTabView offer opens it from the store)
func testNonJoinURL_IsIgnoredAndSavesNothing()               // https://naarscars.com/other → nil; store empty
func testSecondLinkReplacesTheSavedCode()
// PendingInviteStoreTests
func testSave_PostsDidChange()
func testClear_PostsDidChangeOnlyWhenACodeWasStored()
// IncomingLinkHandlerTests (MyCommunitiesView's store-change rule; @testable, static)
func testStoreChange_OpensJoinWhenVisibleWithNoSheet()       // (code, hasSheet false, visible true) → code
func testStoreChange_NeverOpensUnderASheetOrWhenHidden()     // hasSheet true → nil; isVisible false → nil; no code → nil
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'IncomingLinkHandler' in scope".
- [ ] **Step 3: Implement** (the new files through the Xcode MCP: `XcodeLS NaarsCars/Core/Utilities`, `NaarsCars/NaarsCarsTests/Core/Utilities`; confirm the targets).
- [ ] **Step 4: Self-check before GREEN** (write the result into the task report): `grep -rn "absoluteString" NaarsCars/App NaarsCars/Core/Utilities/IncomingLinkHandler.swift` names no log of an incoming URL; `grep -rn "func application(_ app: UIApplication, open url" NaarsCars` returns nothing; the handler saves before it routes on every path; no path calls `validate_community_invite` or `redeem_community_invite` (only the join sheet does, after the person sees it); `SignupInviteCodeView.swift:104`'s `.onOpenURL` is in a view that is never presented (Phase 5a deletes it) and is left alone.
- [ ] **Step 5: GREEN.** `PREVIEWGUARD NaarsCars/Features/Authentication/Views/WelcomeView.swift NaarsCars/Features/Authentication/Views/CommunityOnboardingView.swift NaarsCars/Features/Community/Views/MyCommunitiesView.swift` (no output); `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/IncomingLinkHandlerTests -only-testing:NaarsCarsTests/PendingInviteStoreTests -only-testing:NaarsCarsTests/AppDelegateNotificationHandlingTests`. Expected: 12 new tests pass.
- [ ] **Step 6: FULL.**
- [ ] **Step 7: Commit** `[P4-T4] Open join links through onOpenURL and retire the AppDelegate URL path` with the files above and `project.pbxproj`.

Strings: none. Capture list (Task 13): Welcome with the banner after a link (light, dark, AX 5); the guest prompt "Join the Community"; My communities with the Join sheet holding the code; onboarding with the code prefilled. `#Preview`: `WelcomeView` "Saved invite" exists (`WelcomeView.swift:281-288`).

Live check: Task 13 O3.

---

### Task 5: Associated Domains, the AASA file, and the link in invites

**Model:** opus, medium effort (an entitlement the provisioning profile lacks fails the archive; App Store submission risk, CLAUDE.md "Current State") · **Files:**
- Modify: `NaarsCars/NaarsCars/NaarsCars.entitlements` (Release; `CODE_SIGN_ENTITLEMENTS`, `project.pbxproj:3367`), `NaarsCars/NaarsCars/NaarsCarsDebug.entitlements` (Debug, `:3320`) — both get the same key
- Create (normal tools): `Docs/universal-links/apple-app-site-association` (no extension; the file the owner uploads)
- Modify: `NaarsCars/Core/Utilities/Constants.swift:237-260` (`Community.shareInviteLinks`)
- Modify: `NaarsCars/Features/Community/ViewModels/CommunityInviteViewModel.swift:30-44` (init), `:48-56` (`shareMessage`), new `qrPayload`
- Modify: `NaarsCars/Features/Community/Views/CommunityInviteSheet.swift:72-73` (the QR renders `qrPayload`)
- Modify: `NaarsCars/NaarsCarsTests/Features/Community/CreateCommunityViewModelTests.swift` (`CommunityInviteViewModelTests`, `:34-`)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Both entitlement files gain, after `com.apple.developer.applesignin`:

```xml
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:naarscars.com</string>
	</array>
```
- `Docs/universal-links/apple-app-site-association` (exact text; `appIDs` / `components` for iOS 13+, `appID` / `paths` for older parsers; the fragment is never sent, so the server only matches the path). It matches `/join` and `/join/` **only**, not `/join/*`: `parse(url:)` refuses `/join/<anything>` (Task 3), so handing such a path to the app would open it and do nothing (`applyExternalDeepLink` returns early on `.unknown`), where Safari would at least have shown the landing page:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "WT4DGUYKL4.com.NaarsCars",
        "appIDs": ["WT4DGUYKL4.com.NaarsCars"],
        "paths": ["/join", "/join/"],
        "components": [
          { "/": "/join", "comment": "https://naarscars.com/join#<code>; the code is in the fragment" },
          { "/": "/join/" }
        ]
      }
    ]
  }
}
```
- `Constants.Community.shareInviteLinks: Bool = false` with a comment: true only once the AASA file and the landing page are live (Prerequisite 1d). `CommunityInviteViewModel.init` gains `inviteLinksEnabled: Bool = Constants.Community.shareInviteLinks`. `shareMessage`: when enabled, `community_invite_share_message_link` with `communityName`, `Constants.URLs.joinLink(code: code)` and the formatted code; else today's `community_invite_share_message`. The QR code (`CommunityInviteSheet.swift:72-80`) renders the whole `shareMessage` today (`QRCodeRenderer.image(for: message …)`, `:72-73`); a QR whose payload is a sentence is shown by the Camera as text, not opened as a Universal Link. So the view model gains `var qrPayload: String?`: when `inviteLinksEnabled`, `Constants.URLs.joinLink(code: code)` alone (the Camera offers it as a link; installed → the app, else the landing page); when not, `shareMessage` (today's behaviour, unchanged until the owner flips the constant). The sheet renders `qrPayload`; the share sheet keeps the prose `shareMessage`. The Copy button still copies the bare code (`:84`).
- **Landing page (owner web step; not built here).** A static page at `https://naarscars.com/join` that: reads `location.hash` in the browser, normalizes it like `CommunityInviteCode.normalize` (A-Z, 0-9, upper case), shows it grouped (`NC7K · 2PQ9 · XA`) with a Copy button and "Get Naar's Cars" linking to `Constants.URLs.appStore`; carries `<meta name="apple-itunes-app" content="app-id=6757571644">` (the Smart App Banner, which opens the installed app from Safari, where a same-site Universal Link does not); sends `Referrer-Policy: no-referrer`; loads no analytics or third-party script (the hash would be readable by it); never puts the code in a query, a form or a request. A missing or malformed hash shows "Ask your neighbor for a new invite link." The page is for people without the app, and for the installed pre-community build, which has no handler (spec §4 Phase 4 "What old clients see").
- Owner steps (Prerequisite 1a-1d) are restated in the task report, with: in Xcode, Signing & Capabilities shows Associated Domains on the NaarsCars target after this commit (no click needed: the entitlement file is the source); on a device, Settings → Developer → Associated Domains Development is **not** used (production AASA only).

- [ ] **Step 1: Write the failing tests:**

```swift
// CommunityInviteViewModelTests
func testShareMessage_WithoutInviteLinksHasNoJoinLink()     // inviteLinksEnabled false → no "naarscars.com/join"; App Store URL present
func testShareMessage_WithInviteLinksCarriesTheJoinLink()   // true → contains Constants.URLs.joinLink(code: displayedCode)
func testQRPayload_WithInviteLinksIsTheBareJoinLink()      // true → qrPayload == Constants.URLs.joinLink(code: displayedCode), nothing else
func testQRPayload_WithoutInviteLinksIsTheShareMessage()   // false → qrPayload == shareMessage (today's QR)
```
- [ ] **Step 2: RED.** `RED`. Expected: "extra argument 'inviteLinksEnabled' in call".
- [ ] **Step 3: Implement**; write the AASA file; add the string.
- [ ] **Step 4: Verify the files.** `plutil -lint NaarsCars/NaarsCars/NaarsCars.entitlements NaarsCars/NaarsCars/NaarsCarsDebug.entitlements` (OK); `python3 -I -m json.tool Docs/universal-links/apple-app-site-association > /dev/null` (exit 0); `scripts/verify-apple-signin-config.sh` (still passes: the SIWA key is untouched).
- [ ] **Step 5: GREEN.** `BUILD`; `ENTITLEMENTS` (expected: `"com.apple.developer.associated-domains" => [ 0 => "applinks:naarscars.com" ]`, beside the four keys listed in the Commands block); `RELEASE`; `ENTITLEMENTS-RELEASE` (the same key); `TEST` with `-only-testing:NaarsCarsTests/CommunityInviteViewModelTests`. Expected: 4 new tests pass; `RELEASE` exit 0.
- [ ] **Step 6: Commit** `[P4-T5] Add the applinks entitlement, the AASA file and the invite link` with the files above.

Strings:
```
community_invite_share_message_link = "Join %1$@ on Naar's Cars, the app for neighbor rides and favors: %2$@ (invite code %3$@)."
```

Capture list (Task 13): the invite sheet's QR and share sheet text with `shareInviteLinks` true in a DEBUG build (light); scan the QR from the simulator screenshot with the Mac's Preview / `CIDetector` (or a phone camera) and record that it decodes to the bare `https://naarscars.com/join#…` link. App Store checklist: **new entitlement** (Associated Domains); no permission, data type or SDK.

---

### Task 6: "N more in your other communities" on a narrowed Requests list

**Model:** sonnet, medium effort (client-only, local SwiftData reads; no coordinator call, no network) · **Files:**
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift:159-211` (new method after `fetchFilteredFavors`)
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift:24-32` (state), `:237-243` (`refreshFilteredRequests`)
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift:167-210` (`listContentView`)
- Modify: `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift:391-420` (the existing narrow-scope tests; extend, do not add a parallel harness)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: the rows the dashboard already reads (D6: the merged feed syncs every community; `fetchFilteredRides` / `fetchFilteredFavors(in:filter:scope:)`, `getFilteredRequests(rides:favors:filter:)`); `RequestsScope.includes(_:)` (`Core/Models/Community.swift:92-97`: a narrow includes rows with a nil community).
- Produces:

```swift
// RequestFilterManager
/// Requests the current filter would list under `.all` but `scope` hides: what the "N more" hint counts.
/// 0 for `.all`. Rows with no community are shown by every narrow and never count; rows the list hides for
/// time (getFilteredRequests) never count.
func countOutsideScope(in context: ModelContext, filter: RequestFilter, scope: RequestsScope) -> Int
// RequestsDashboardViewModel
@Published private(set) var otherCommunitiesCount: Int = 0   // recomputed in refreshFilteredRequests(); 0 when scope == .all
```
- `countOutsideScope`: `scope == .all` → 0; else `getFilteredRequests(all rides, all favors, filter).count − getFilteredRequests(narrowed rides, narrowed favors, filter).count`, the `all` lists from the same two fetches with `scope: .all` (two extra local fetches only while narrowed).
- View: when `otherCommunitiesCount > 0` (implies narrowed and more than one membership), one row at the top of the section (above the cards, and above the empty state when the narrowed list is empty): `Text` with the count key, and a borderless `Button` `requests_other_communities_show_all` that sets `communityContext.requestsScope = .all` (the title menu's own action, `RequestsDashboardView.swift:42-44`; `.onChange` at `:65-67` re-filters). `.font(.naarsSubheadline)`, `.foregroundColor(.naarsTextSecondary)`, padded like the cards; identifiers `requests.otherCommunities.hint` and `requests.otherCommunities.showAll`; the row is one accessibility element with the button as its action.

- [ ] **Step 1: Write the failing tests** (Review Focus 6):

```swift
// CommunityStoreScopingTests
func testCountOutsideScope_CountsOtherCommunitiesOnly()     // open rides in A, B, B and one with nil community; narrowed to A → 2
func testCountOutsideScope_AllScopeIsZero()
func testCountOutsideScope_FollowsTheFilter()               // a claimed ride in B counts for .claimed, not for .open
func testCountOutsideScope_SkipsRowsTheListHidesForTime()   // a ride in B whose window ended more than 12 h ago → 0
```
- [ ] **Step 2: RED.** `RED`. Expected: "value of type 'RequestFilterManager' has no member 'countOutsideScope'".
- [ ] **Step 3: Implement**; add the strings.
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Requests/Views/RequestsDashboardView.swift`; `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityStoreScopingTests`. Expected: 4 new tests pass.
- [ ] **Step 5: Commit** `[P4-T6] Show how many requests a Requests narrow hides` with the files above.

Strings:
```
requests_other_communities_hint_one = "1 more request in your other communities"
requests_other_communities_hint_other = "%lld more requests in your other communities"
requests_other_communities_show_all = "Show all"
```

Capture list (Task 13): Requests narrowed with the hint (open, mine), narrowed and empty with the hint, `.all` without it; light / dark / AX 5. One-membership Requests: unchanged.

---

### Task 7: Community chips on bell and announcement rows

**Model:** sonnet, medium effort · **Files:**
- Modify: `NaarsCars/Features/Notifications/Views/NotificationRow.swift:11-27` (init), `:43-79` (content), `:97` (accessibility label), `:106-` (previews)
- Modify: `NaarsCars/Features/Notifications/Views/NotificationsListView.swift:192-199`
- Modify: `NaarsCars/Features/Notifications/Views/AnnouncementsView.swift:52-55`
- Modify: `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift` (where the `CommunityContext` tests live)

**Interfaces:**
- Consumes: `CommunityContext.chipText(for:respectingScope:)` (`App/CommunityContext.swift:133-140`: nil with one active membership, nil for a community the person is not in); `AppNotification.communityId` (rows carry it from `derive_notification_community`, `notify_user_in_community`); `NaarsChip(text:tint: nil)` and `community_chip_accessibility` (the request-card pattern, `UI/Components/Cards/RideCard.swift:84-87, 133-136`).
- Produces: `NotificationRow.init(notification:isReadOverride:groupCount:communityChipText: String? = nil, onTap:)`. With a chip, the row shows `NaarsChip(text:, tint: nil)` on the line with the time (`:76-78`), and the combined accessibility label appends `community_chip_accessibility(name)`. `NotificationsListView` and `AnnouncementsView` pass `CommunityContext.shared.chipText(for: notification.communityId, respectingScope: false)`. No chip with one membership, so one-community bells are unchanged.

- [ ] **Step 1: Write the failing tests** (spec D6: chips hidden with one membership):

```swift
// AppLaunchManagerTests (CommunityContext section)
func testChipText_IgnoringScopeNamesTheCommunityWithTwoMemberships()   // narrowed Requests still names it (respectingScope false)
func testChipText_NilWithOneMembershipOrUnknownCommunity()
```
(The row is a view; its chip is checked in the previews and captures. These two pin the decision it renders.)
- [ ] **Step 2: RED.** Compile-level RED is not available for an existing method; run the two tests against `HEAD` first and record that they pass or fail, then add the row parameter (RED: "extra argument 'communityChipText' in call" once a preview passes it).
- [ ] **Step 3: Implement**; previews: a bell row with a chip, one without, an announcement with a 60-character community name; the `NotificationRow.swift` previews move inside one `#if DEBUG … #endif` if any uses a DEBUG-only type (they do not today).
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Notifications/Views/NotificationRow.swift NaarsCars/Features/Notifications/Views/NotificationsListView.swift NaarsCars/Features/Notifications/Views/AnnouncementsView.swift`; `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/AppLaunchManagerTests -only-testing:NaarsCarsTests/NotificationsListViewModelTests`. Expected: 2 new tests pass.
- [ ] **Step 5: Commit** `[P4-T7] Show the community on bell and announcement rows` with the files above.

Strings: none (`community_chip_accessibility` exists). Capture list (Task 13): the bell with two memberships (chips on a request row, a Town Hall row and an announcement), with one membership (no chips), the 60-character name at AX 5; light / dark / AX 5. `#Preview`: `NotificationRow` (exists; the chip variants added).

---

### Task 8: Community time zone at creation and in Settings

**Model:** opus, high effort (changes the `create_community` RPC call site and its argument set, and adds one to `update_community`; CLAUDE.md lists RPC call sites as a high-blast seam) · **Files:**
- Modify: `NaarsCars/Core/Protocols/CommunityServiceProtocol.swift:14`, `NaarsCars/Core/Services/CommunityService.swift:15-30` (`CreateCommunityParams`), `:283-287`, `UpdateCommunityParams` (`:229-250`: gains `timezone` with `encodeIfPresent(…, forKey: .p_timezone)`, and its doc comment at `:229-230`, "`p_timezone` never is", is rewritten to say it is sent only on a change)
- Modify: `NaarsCars/Core/Services/PreviewCommunityService.swift:124`, `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift:433` (`createCommunityCalls` gains a `timezone: String?` element) and `:487-490` (the stub's `createCommunity` records it), so `testCreate_SendsTheDeviceTimeZone` can assert it; the existing readers of `createCommunityCalls` (`CreateCommunityViewModelTests.swift:22-29`) read `.count` and `.joinPolicy` only and are unaffected
- Modify: `NaarsCars/Features/Community/ViewModels/CreateCommunityViewModel.swift:29-38` (init), `:62` (call)
- Modify: `NaarsCars/Core/Models/CommunityPayloads.swift:521-532` (`CommunitySettingsChange.timezone`; the doc comment at `:521-522`, "The time zone is never sent (no screen edits it)", replaced)
- Modify: `NaarsCars/Features/Community/ViewModels/CommunitySettingsViewModel.swift` (state, `canEdit`, change builder, `:170-181` saved settings)
- Modify: `NaarsCars/Features/Community/Views/CommunitySettingsView.swift:95-157` (a time-zone section after "Members can invite"; Phase 3 gate render finding 2, read-only Name and Description, is already fixed at `4049998` with `readOnlyValue(_:label:identifier:)`, `:185`, and is not changed here)
- Modify: `NaarsCars/UI/Components/Common/TimeZonePicker.swift:10-37`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/CommunityServiceTests.swift`, `NaarsCarsTests/Features/Community/CreateCommunityViewModelTests.swift`, `NaarsCarsTests/Features/Community/CommunitySettingsViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`
- Reference: SQL plan File A block 3 (`create_community(p_name, p_description, p_join_policy, p_timezone)`; an unknown zone falls back to the column default); live `update_community(… p_timezone)` (`md5 7bf86ba02a90e5b996177ea86455a704`, owner or platform admin, refuses an unknown zone with "Unknown time zone" and no code)

**Interfaces:**
- `func createCommunity(name: String, description: String?, joinPolicy: CommunityJoinPolicy, timezone: String?) async throws -> CreatedCommunity`; `CreateCommunityParams` encodes `p_timezone` with `encodeIfPresent`. `CreateCommunityViewModel.init` gains `deviceTimeZone: @escaping () -> TimeZone = { .current }` and sends `deviceTimeZone().identifier`. The create form shows no time-zone field (spec: "the create-form default"; the owner changes it in Settings).
- `CommunitySettingsChange.timezone: String?` (nil = unchanged; `isEmpty` includes it); the `update_community` params encode `p_timezone` with `encodeIfPresent`. `CommunitySettingsViewModel`: `@Published var timezone: String` loaded from `CommunitySettings.timezone` (`CommunityPayloads.swift:510`); the change carries it only when it differs; the saved copy keeps the new value. `canEdit` is unchanged (owner or platform admin, the same rule as `update_community`).
- `CommunitySettingsView`: a section with `TimeZonePicker(selectedTimezone: $viewModel.timezone)` when `canEdit`, else `readOnlyValue(<localized zone name>, label: "community_settings_timezone".localized, identifier: "community.settings.timezone")` (the read-only idiom Name and Description already use, `:100-105`, `:185`); footer `community_settings_timezone_footer`.
- `TimeZonePicker`: `static func options(including selected: String) -> [(id: String, label: String)]` returns the six zones plus `selected` (labelled by `TimeZone.localizedName(for: .generic, …)`) when it is a valid identifier not among them, so a community created in `Europe/Berlin` or `America/Phoenix` shows its zone instead of a blank picker.

- [ ] **Step 0: Precondition.** Through the Supabase MCP (read only): `select pg_get_function_identity_arguments(oid) from pg_proc where proname = 'create_community' and pronamespace = 'public'::regnamespace` returns exactly one row containing `p_timezone text`. If not, stop: Prerequisite 2 (SQL plan File A) is not met.
- [ ] **Step 1: Write the failing tests:**

```swift
// CommunityServiceTests
func testCreateCommunity_SendsTimezone()                    // keys == ["p_name","p_description","p_join_policy","p_timezone"]
func testUpdateCommunity_SendsTimezoneOnlyWhenChanged()     // change(timezone: "America/New_York") → keys include "p_timezone"; empty change has none
// CreateCommunityViewModelTests
func testCreate_SendsTheDeviceTimeZone()                    // deviceTimeZone: { TimeZone(identifier: "America/Chicago")! } → stub got "America/Chicago"
// CommunitySettingsViewModelTests
func testSave_TimezoneChangeIsSentAndKept()
func testLoad_ReadsTheCommunityTimezone()
func testTimeZonePickerOptions_IncludeAnOffListZone()        // options(including: "Europe/Berlin") has 7 entries; "Not/AZone" → 6
```
- [ ] **Step 2: RED.** `RED`. Expected: "extra argument 'timezone' in call".
- [ ] **Step 3: Implement**; update every conformer the compiler names; add the strings.
- [ ] **Step 4: Self-check before GREEN** (task report): the `create_community` keys match SQL plan File A block 3 line by line; `p_timezone` is never sent as an explicit null; `update_community` gets `p_timezone` only on a change; no screen shows the server's "Unknown time zone" text (a refusal shows `CommunityRPCError.localizedMessage`, Phase 2 idiom); the Phase 2/3 path (3 keys) still resolves on the server (SQL plan File A block 3 keeps the defaults).
- [ ] **Step 5: GREEN.** `PREVIEWGUARD NaarsCars/Features/Community/Views/CommunitySettingsView.swift NaarsCars/UI/Components/Common/TimeZonePicker.swift`; `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityServiceTests -only-testing:NaarsCarsTests/CreateCommunityViewModelTests -only-testing:NaarsCarsTests/CommunitySettingsViewModelTests`. Expected: 6 new tests pass.
- [ ] **Step 6: Commit** `[P4-T8] Send the device time zone when creating a community and edit it in Settings` with the files above.

Strings:
```
community_settings_timezone = "Time zone"
community_settings_timezone_footer = "Rides and favors posted in this community start in this time zone."
```

Capture list (Task 13): Settings as owner (picker), as admin (read-only zone, read-only name and description), with an off-list zone; light / dark / AX 5. Live check **(writes)**: Task 13 O4.

---

### Task 9: Ride and favor forms default to the community's time zone

**Model:** sonnet, medium effort (form defaults only; the RPC call sites already send `timezone`) · **Files:**
- Modify: `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift:21` (default), `:28-35` (`selectedCommunityId` observer), `:74-90` (`configureCommunityChoice`), `:188` (edit keeps the ride's zone)
- Modify: `NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift:27`, its `selectedCommunityId` observer and `configureCommunityChoice` (`:76-`), `:185`
- Modify: `NaarsCars/Features/Rides/Views/CreateRideView.swift:102`, `NaarsCars/Features/Favors/Views/CreateFavorView.swift:155` (the picker's binding marks the zone as chosen)
- Test: `NaarsCars/NaarsCarsTests/Features/Rides/CreateRideViewModelTests.swift`, `NaarsCars/NaarsCarsTests/Features/Favors/CreateFavorViewModelTests.swift`

**Interfaces:**
- Consumes: `CommunityMembership.timezone` (`Core/Models/Community.swift:44`), `CommunityContext.membership(for:)` (`App/CommunityContext.swift:163`), `defaultPostCommunityId`.
- Produces (both view models): `private(set) var didChooseTimezone = false`; `func chooseTimezone(_ id: String)` (the picker's setter calls it; sets `timezone` and `didChooseTimezone = true`); `func applyCommunityTimezoneDefault()` — when creating (not editing) and `!didChooseTimezone`, sets `timezone` to the posting community's zone: `selectedCommunityId` when the form asks, else the single active membership, else today's `"America/Los_Angeles"`. Called from `configureCommunityChoice()` and when `selectedCommunityId` changes. Editing keeps the request's own zone (`:188`, `:185`).

- [ ] **Step 1: Write the failing tests:**

```swift
// CreateRideViewModelTests
func testNewRide_DefaultsToTheCommunityTimeZone()             // one membership in America/Denver → timezone "America/Denver"
func testNewRide_SwitchingCommunityMovesAnUntouchedTimeZone()  // two memberships, Denver → New_York on selection change
func testNewRide_KeepsATimeZoneThePersonChose()                // chooseTimezone("America/Chicago"), then switch → stays Chicago
func testEditRide_KeepsTheRideTimeZone()
// CreateFavorViewModelTests
func testNewFavor_DefaultsToTheCommunityTimeZone()
func testNewFavor_SwitchingCommunityMovesAnUntouchedTimeZone()
func testNewFavor_KeepsATimeZoneThePersonChose()
```
- [ ] **Step 2: RED.** `RED`. Expected: "value of type 'CreateRideViewModel' has no member 'chooseTimezone'".
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Rides/Views/CreateRideView.swift NaarsCars/Features/Favors/Views/CreateFavorView.swift`; `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CreateRideViewModelTests -only-testing:NaarsCarsTests/CreateFavorViewModelTests`. Expected: 7 new tests pass.
- [ ] **Step 5: Commit** `[P4-T9] Start ride and favor forms in the community's time zone` with the files above.

Strings: none. Capture list (Task 13): Create Ride with two memberships in different zones, before and after switching "Post to".

---

### Task 10: Gate follow-ups (1) — render and copy fixes

**Model:** sonnet, medium effort (view layout and strings; no logic) · **Files and fixes** (each from the named gate report; captures in Task 13):

| # | Finding (source) | Where | Fix |
|---|---|---|---|
| a | Invite sheet AX 5: "Copy code" and "Share invite" break inside words (Phase 2 render 1) | `NaarsCars/Features/Community/Views/CommunityInviteSheet.swift:82-101` | Wrap the two buttons in `ViewThatFits(in: .horizontal) { HStack(spacing: Constants.Spacing.md) { … } ; VStack(spacing: Constants.Spacing.sm) { … } }` with each button `.frame(maxWidth: .infinity)` in the vertical form; the buttons' content is extracted into one `@ViewBuilder` so it is written once. |
| b | "Can be used 1 times" (Phase 2 render 2) | `CommunityInviteSheet.swift:115-118` | `CommunityInviteViewModel.usesText(_ count: Int) -> String` with `community_invite_uses_one` / `_other`; the stepper's title calls it. The old key stays in the catalog, unreferenced. |
| c | Owned-limit sheet: inline title truncates at every size; AX 5 squeezes the stepper (Phase 2 render 3) | `NaarsCars/Features/Community/Views/OwnedLimitRequestSheet.swift:28-32`, `:51` | Title `community_limit_request_title_short` ("Higher limit"), the full sentence moves to the section header `community_limit_request_title` (existing key, unchanged); at `dynamicTypeSize.isAccessibilitySize` the stepper's label is a `Text` above a `Stepper(...).labelsHidden()`. |
| d | Onboarding shows "Retry" and "Try again" stacked when the public list fails (Phase 2 render 4, owner decision: relabel) | `NaarsCars/Features/Authentication/Views/CommunityOnboardingView.swift:51-57` | Relabel the relaunch button `onboarding_retry_check_account` ("Check my account again") with `accessibilityHint` `onboarding_retry_check_account_hint`; "Retry" (`CommunityJoinOptionsView.swift:119-122`) still reloads the list. **This task does the relabel only.** If the owner prefers removal, that is **not** done here: `CommunityOnboardingViewModel.retry()` (`:132-134`) re-runs the account check and launch routing (`relaunchOnce()`, fragile system 5), so removing it goes to a separate opus task with a `FULL` run (`CommunityOnboardingViewModelTests`, `AppLaunchManagerTests`); record the owner's choice. |
| e | Admin panel Management rows centre and hyphenate at AX 5 (Phase 3 tail) | `NaarsCars/Features/Admin/Views/AdminPanelView.swift:352-380` (`managementRow`) | `Text(title).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)`; at accessibility sizes an `AnyLayout(VStackLayout(alignment: .leading))` puts the icon above the title (the `.all` rows keep their own markup). |
| f | Reports filter row: no edge fade, and selected capsule uses literal `.white` (Phase 3 tail, design-system rule) | `NaarsCars/Features/Community/Views/CommunityReportsView.swift:175-198` | Selected: `NaarsChip`'s rule (status colour as text on a 12% tint): `.foregroundColor(.naarsPrimary)`, `Capsule().fill(Color.naarsPrimary.opacity(0.12))` and a 1-pt `naarsPrimary` stroke; unselected unchanged. Trailing fade: `.mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))` on the `ScrollView`, plus `.contentMargins(.horizontal, Constants.Spacing.md, for: .scrollContent)`. |
| g | Profile stat labels "No Rating", "My Savings", "Fulfilled", "XP" not localized (Phase 3 Spanish pass) | `NaarsCars/UI/Components/Common/ProfileStatsCard.swift:86, 100, 112, 124` | Keys `profile_stat_rating`, `profile_stat_no_rating`, `profile_stat_savings`, `profile_stat_fulfilled`, `profile_stat_xp` with `.localized`. |
| h | "Send Broadcast" button under "Send Announcement"; pin footer says "users' notification feeds" (Phase 3 render 4) | `NaarsCars/Features/Admin/Views/BroadcastView.swift:68, 81` | **Already fixed at `4956682`**: the button reads `admin_send_announcement` ("Send Announcement") and the footer `admin_pin_footer_members` ("…the community members' notification feeds…"). No change; confirm in the O1 capture and record it as closed. |
| i | `ReportContentSheet` at AX 5: the reason icons touch their labels (Phase 2 render 6, repeated as Phase 3 render 6; shared by every report type) | `NaarsCars/Features/TownHall/Views/ReportContentSheet.swift:116-120` | The icon's fixed `.frame(width: 24)` does not grow with Dynamic Type while the symbol does. `@ScaledMetric(relativeTo: .body) private var reasonIconWidth: CGFloat = 24` and `.frame(width: reasonIconWidth)`; `HStack(spacing: Constants.Spacing.ms)`. Layout only: the report types, the selection, the submit path and every identifier are unchanged (App Store rule: reporting stays intact on every UGC surface). |

- [ ] **Step 1: Write the failing test:**

```swift
// CommunityInviteViewModelTests
func testUsesText_OneAndMany()     // usesText(1) == community_invite_uses_one.localized; usesText(5) contains "5"
```
- [ ] **Step 2: RED.** `RED`. Expected: "value of type 'CommunityInviteViewModel' has no member 'usesText'".
- [ ] **Step 3: Implement** a-g and i (h needs no change); add the strings; for d, the relabel only, and record the owner's choice (relabel is the default; removal, if chosen, is an opus follow-up with `FULL`, not this sonnet task).
- [ ] **Step 4: GREEN.** `PREVIEWGUARD` over the eight view files above; `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityInviteViewModelTests`. Expected: 1 new test passes. `scripts/design-token-audit.sh` reports no new `.white` in `CommunityReportsView.swift`.
- [ ] **Step 5: Commit** `[P4-T10] Fix the open render and copy findings from the Phase 2 and 3 gates` with the files above.

Strings:
```
community_invite_uses_one = "Can be used once"
community_invite_uses_other = "Can be used %lld times"
community_limit_request_title_short = "Higher limit"
onboarding_retry_check_account = "Check my account again"
onboarding_retry_check_account_hint = "Checks whether a community has approved you."
profile_stat_rating = "Rating"
profile_stat_no_rating = "No Rating"
profile_stat_savings = "My Savings"
profile_stat_fulfilled = "Fulfilled"
profile_stat_xp = "XP"
```

Capture list (Task 13): each row a-g and i at AX 5 (i: the Report sheet for a post and for a community), and h's screen (and light / dark for f); Profile in Spanish.

---

### Task 11: Gate follow-ups (2) — the panel title, the archive notice, the A3 warning

**Model:** opus, high effort (the archive notice crosses the move from the main UI to the onboarding root, fragile system 5) · **Files:**
- Modify: `NaarsCars/Features/Admin/ViewModels/AdminPanelViewModel.swift:122-126` (`title`), new `refreshCommunityName()`
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift` (`.onAppear` calls it)
- Create (Xcode MCP, app target): `NaarsCars/Core/Utilities/RootNotice.swift`
- Modify: `NaarsCars/Features/Community/ViewModels/CommunitySettingsViewModel.swift:198-222` (`archive()`)
- Modify: `NaarsCars/Features/Authentication/ViewModels/CommunityOnboardingViewModel.swift`, `NaarsCars/Features/Authentication/Views/CommunityOnboardingView.swift:81-86` (toast)
- Modify: `NaarsCars/Features/Authentication/ViewModels/PendingApprovalViewModel.swift`, `NaarsCars/Features/Authentication/Views/PendingApprovalView.swift:111-125` (toast; the waiting screen is the other root the archive can lead to)
- Modify: `NaarsCars/Core/Services/AuthService.swift:656-` (`clearPerAccountLocalState`: `RootNotice.pending = nil` beside `PendingInviteStore().clear()` at `:680`; a high-risk file, one line)
- Test: `NaarsCars/NaarsCarsTests/Features/Admin/AdminPanelViewModelTests.swift`, `NaarsCarsTests/Features/Community/CommunitySettingsViewModelTests.swift`, `NaarsCarsTests/Features/Community/CommunityOnboardingViewModelTests.swift`, `NaarsCarsTests/Features/Community/PendingApprovalViewModelTests.swift`, `NaarsCarsTests/Features/Profile/MyProfileViewModelTests.swift`

**Fixes:**
1. **The Admin Panel opened from My communities keeps the old name after a rename** (Phase 3 gate follow-up). `AdminPanelViewModel.communityName` is set once (`:102-103`, `:214-216`, `:228`) and `title` prefers it (`:125`). Fix: `refreshCommunityName()` sets `communityName = displayName(for: id) ?? communityName` for a community scope; `AdminPanelView` calls it in `.onAppear` (the panel reappears when Settings pops; `CommunitySettingsViewModel.save` already refreshes the memberships, `:186-188`).
2. **The archive confirmation is unreadable when the archived community was the account's only one** (Phase 3 gate follow-up). `archive()` sets `archiveConfirmation` (`:217`), then `forgetMembership` (`:219`) ends the last active membership → `CommunityContext.onActiveMembershipsEmpty` → `AppLaunchManager.recheckAccountStatus()` → `.needsApplication`, and `ContentView` swaps to `CommunityOnboardingView` within a second. Fix: `@MainActor enum RootNotice { static var pending: String? }` (one-shot, in memory; the `WelcomeEntryRoute` idiom, `WelcomeView.swift:263-268`); `archive()` sets `RootNotice.pending = archiveConfirmation` **before** `forgetMembership` when the archived community is the account's only active membership; `RootNotice.take() -> String?` reads and clears it. **Whichever root appears consumes it**: after the last active membership goes, `AppLaunchManager.authState(for:)` (`App/AppLaunchManager.swift:278-287`) returns `.needsApplication` only when the application is not complete, and `.pendingApproval` when it is (for example, a request still waiting in another community), so the person can land on the waiting screen instead of onboarding. Both `CommunityOnboardingViewModel.takeRootNotice()` and `PendingApprovalViewModel.takeRootNotice()` delegate to `RootNotice.take()`, and `CommunityOnboardingView` and `PendingApprovalView` show it with `.toast(message:)` from their `.task`; taken once, it cannot surface stale on a later root. (A `.banned` root does not show it; a ban during an archive is not a case worth a third consumer, and sign-out clears it.) `AuthService.clearPerAccountLocalState()` (`Core/Services/AuthService.swift:656`, beside `PendingInviteStore().clear()` at `:680`) sets `RootNotice.pending = nil` (a notice never crosses accounts; CLAUDE.md "Sign-out clears per-account local state"). The launch state machine is not touched.
3. **The A3 owned-community warning does not show after an archive** (Phase 3 gate follow-up). **By design, no code change:** an archived community no longer closes on deletion, so there is nothing to warn about (`MyProfileViewModel.communitiesClosedByDeletion`, `:129-145`, counts live memberships; the onboarding root's Delete Account uses the generic confirmation, which is correct for an account that owns no live community). This task pins it with a test and the documentation task records it.

- [ ] **Step 1: Write the failing tests:**

```swift
// AdminPanelViewModelTests
func testRefreshCommunityName_PicksUpARename()                 // context renamed after init → title is the new name
// CommunitySettingsViewModelTests
func testArchive_OnlyActiveCommunityLeavesARootNotice()        // RootNotice.pending == archiveConfirmation, set before forgetMembership
func testArchive_WithOtherCommunitiesLeavesNoRootNotice()
// CommunityOnboardingViewModelTests
func testTakeRootNotice_ReturnsItOnceAndClearsIt()
// PendingApprovalViewModelTests
func testTakeRootNotice_WaitingScreenConsumesTheArchiveNotice()   // the .pendingApproval root: returns it once, then nil for onboarding
// MyProfileViewModelTests (a private stub AuthServiceProtocol with currentUserId = userA, the StubMembersAuthService pattern,
// CommunityMembersViewModelTests.swift:14; without a user id the method returns [] at MyProfileViewModel.swift:133 and the test
// would pass with no logic behind it)
func testCommunitiesClosedByDeletion_AnArchivedCommunityIsNotListed()
    // context loaded with an owner membership of A (sole owner; StubCommunityAdminService answers no other member):
    // first call → ["Community A"] (control); after forgetMembership(A), the archive path (CommunitySettingsViewModel.swift:219;
    // get_my_memberships leaves archived communities out, 20261017_0005 :41) → []
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'RootNotice' in scope".
- [ ] **Step 3: Implement** (`RootNotice.swift` through the Xcode MCP; `XcodeLS NaarsCars/Core/Utilities`).
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Admin/Views/AdminPanelView.swift NaarsCars/Features/Authentication/Views/CommunityOnboardingView.swift NaarsCars/Features/Authentication/Views/PendingApprovalView.swift`; `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/AdminPanelViewModelTests -only-testing:NaarsCarsTests/CommunitySettingsViewModelTests -only-testing:NaarsCarsTests/CommunityOnboardingViewModelTests -only-testing:NaarsCarsTests/PendingApprovalViewModelTests -only-testing:NaarsCarsTests/MyProfileViewModelTests -only-testing:NaarsCarsTests/AppLaunchManagerTests`. Expected: 6 new tests pass (`MyProfileViewModelTests`' live cases skip signed out, as today; the new case needs no session).
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P4-T11] Keep the panel title and the archive notice current across a rename and the move to onboarding` with the files above (`AuthService.swift` included) and `project.pbxproj`.

Strings: none. Live check **(writes)**: Task 13 O4 (rename, then archive the throwaway community as its only member).

---

### Task 12: Documentation for Phase 4

**Model:** sonnet · **Files:**
- Modify: `CLAUDE.md` — Current State (a Phase 4 paragraph: what shipped and was verified; the entitlement and the owner's App ID and AASA steps before the next archive; the two GATED server files and the A5 gate condition); Fragile system 4 "Notification Routing" (a Universal Link paragraph: `onOpenURL` → `IncomingLinkHandler` → `PendingInviteStore` first, then `DeepLinkParser.parse(url:)` → `DeepLink.joinCommunity` → `NavigationCoordinator.applyExternalDeepLink` → `.joinCommunity` → My communities' Join sheet; signed out → the Welcome banner; guest → the join prompt; the code is read from the fragment only and never logged; the `AppDelegate` URL path is gone); Notification Rules (a rule for `membership_update`: payload `membership_event` `approved` → My communities, `owner` + `community_id` → that community's Members; bell rows route by the person's role; its producers are GATED until no pre-community build is in use; and the announcement push of SQL plan File B: one `broadcast` push per unmuted active member regardless of the Town Hall preference, routed to Announcements, GATED); Cross-Layer seams (`NotificationType` registry: 34 types; `validate-notification-types.sh` now also reads the SQL CHECK); Canonical Entry Points (open an incoming URL → `IncomingLinkHandler.handle(_:)`; never `UIApplicationDelegate` URL methods); File conventions (`IncomingLinkHandler`, `RootNotice`, `Docs/universal-links/`); the Phase 2 "Current State" paragraph and the Phase 2 Audit Notes line still say community reports come back from `admin_get_reports` nameless and cannot be dismissed; the Phase 3 gate closed that (`Docs/qa/2026-10-18-multi-community-phase3-gate.md:70`: Admin → Reports names the community and Dismiss writes a `community` target), so both lines are corrected; Audit Notes (the `application(_:open:options:)` deprecation closed; follow-ups from Task 13; the A3-after-archive note; audit date); the deployment-target paragraph's deprecated-API list loses the `AppDelegate` URL path.
- Modify: `AGENTS.md` (the same facts, short); `.cursor/rules/02-notification-contract.mdc` (34 types; `membership_update`; the SQL CHECK in the validation script), `.cursor/rules/05-navigation-contract.mdc` (`communityMembers`, `joinCommunity`, `applyExternalDeepLink`, no URL handling in `AppDelegate`).
- Modify: `SECURITY.md` §6 Invite Code Security (the link carries the code in the fragment only; the app saves it on the device until redemption or 7 days, `PendingInviteStore`; never logged; the landing page loads no third-party script and sends `Referrer-Policy: no-referrer`), the entitlement list if one exists.
- Modify: `Docs/design-system/README.md` (bell-row community chip; the Requests hint row; the Reports filter's tinted selected capsule; the AX layout of the admin panel's management rows; no new tokens).
- Modify: `Docs/AppStore/2026-10-multi-community-review-notes.md` (a Phase 4 section: the Associated Domains entitlement and what it opens; how a reviewer tests a join link; release notes: announcements now reach every member who has not muted the community once the server change is made, which the release notes say only when File B is applied).

- [ ] **Step 1: Edit** each section with the Phase 4 facts (replace, do not append history).
- [ ] **Step 2: Verify** `grep -n "application(_:open:options:)" CLAUDE.md` names it only as removed; `grep -n "33 types\|registry stays at 33" CLAUDE.md AGENTS.md .cursor/rules/*.mdc` returns nothing stale; `scripts/validate-notification-types.sh` exits 0.
- [ ] **Step 3: Commit** `[P4-T12] Document the Phase 4 client`.

---

### Task 13: Phase gate

**Model:** opus · **Files:** a new `Docs/qa/2026-10-19-multi-community-phase4-gate.md` (report only; no code). Uses `Docs/qa/push-fixtures/*.apns`, `build/`.

**Steps the agent runs without the owner:**

- [ ] **Step 1: Preconditions** (Supabase MCP, read only). File A live: `valid_notification_type` contains `membership_update`; `should_notify_user`'s `md5(prosrc)` equals the deployed value in `20261019_0001`'s header; `create_community` has one overload with `p_timezone`. Files B and C **not** live: `md5(prosrc)` of `send_community_broadcast`, `notify_town_hall_post`, `approve_community_member`, `transfer_community_ownership`, `set_member_role`, `readmit_community_member` equal the SQL plan's P1 values (`b49920cb…`, `5c5d85a2…`, `d46e6536…`, `8fc784bf…`, `4e00bbdc…`, `3045087b…`); `select count(*) from notifications where type = 'membership_update'` is 0. Both gated headers read NOT APPLIED with dry-run outcomes. `scripts/validate-notification-types.sh` exits 0 with 34 types. If anything is off, run every step that does not need it and report the gap.
- [ ] **Step 2: Full unit suite, signed out**, one headless simulator, `-resultBundlePath build/P4-gate.xcresult`. Expected: exit 0, 0 failures, skips limited to the session-gated classes; record the counts against the Phase 3 final run (641 cases, 608 passed, 33 skipped) — Phase 4 adds 71 cases (Tasks 1-11: 5, 14, 10, 12, 4, 4, 2, 6, 7, 1, 6; Task 1's six Step 0b tests are edits, not new cases) and no new skip.
- [ ] **Step 2b: Release build.** `RELEASE` (with `<n>` = `gate`), `ENTITLEMENTS` (Debug) and `ENTITLEMENTS-RELEASE` (both read the build's `.xcent`, not `codesign`), and `PREVIEWGUARD` over every view file the phase touched (`git diff --name-only 4956682..HEAD -- 'NaarsCars/**/*View.swift' 'NaarsCars/**/*Sheet.swift' 'NaarsCars/**/*Row.swift' 'NaarsCars/**/*Card.swift'`). Expected: exit 0; the applinks entitlement present; no unwrapped preview naming a DEBUG-only type. A failure here is a blocker.
- [ ] **Step 3: Previews (Lane A).** Open the worktree project; `RenderPreview` every `#Preview` named in Tasks 4-11 with `{"Color Scheme": "Light Appearance"}`, `{"Color Scheme": "Dark Appearance"}`, `{"Dynamic Type": "AX 5"}`; retry once on a first-render timeout. Inspect: chips on bell rows, the hint row, the settings zone row, the invite sheet buttons at AX 5, the owned-limit sheet, the Reports filter in both appearances. Quit Xcode.
- [ ] **Step 4: Write the report** with the PR Impact Summary: (1) Universal Links: `https://naarscars.com/join#<code>` opens the Join sheet signed in, the Welcome banner signed out, the join prompt for a guest; the code is saved on the device first and never logged; the `AppDelegate` URL path is removed; (2) a new notification type `membership_update` on every registry layer, routed to My communities or the community's Members, with no producer live (GATED); (3) the announcement push contract is pinned and its server change is GATED; (4) Requests narrowed shows how many requests it hides; (5) bell rows carry the community chip with more than one membership; (6) the community time zone is set from the device at creation, editable by the owner in Settings, and starts the ride and favor forms; (7) the Phase 2 and 3 gate follow-ups. High-blast files touched: `DeepLinkParser`, `NavigationCoordinator`, `NavigationIntent`, `NotificationNavigationRouter`, `AppDelegate`, `NotificationType` / `NotificationTypeRegistry` / `notificationTypes.ts`, `PushNotificationService` (`PushRefreshPlan` only), `Constants`, the `create_community` / `update_community` call sites; for each, what would break if a consumer were missed. App Store checklist (spec §5): **new entitlement** (Associated Domains; needs the App ID capability and a regenerated profile before the archive); notification behaviour: unchanged until Files B and C are applied (then: announcements reach every unmuted member as a push, ownership and further-community approvals get their own notice); no permission, SDK, data type or privacy-manifest change; account deletion, reporting and moderation unchanged.

**Owner-present steps** (the orchestrator runs them on two of the owner's simulators through the built-in panel, as in the Phase 3 gate: the owner's `iPhone 16` with their platform-admin account, and a second simulator where throwaway accounts are created through the app's own Sign Up; writes only with the owner's go-ahead; server checks through the Supabase MCP after every write):

- [ ] **O1. Captures** (light, dark, AX 5; `simctl ui … appearance`, `content_size accessibility-extra-extra-extra-large`, reset afterwards): every capture list in Tasks 4-11, with the second simulator's account in two communities for the hint, the chips and the time-zone default, and in one community for the unchanged screens. Compare the one-membership Requests, bell and Community tabs with the Phase 3 captures: unchanged.
- [ ] **O2. Push fixtures** (`xcrun simctl push <device> com.NaarsCars <file>`; foreground banner tapped; `<COMMUNITY_ID>` = a community the account owns, `<NOTIFICATION_ID>` = one of its announcement bell rows, read with `execute_sql`): `membership_update_approved.apns` → My communities; `membership_update_owner.apns` → Profile tab, that community's Members, with the owner actions (the account must actually be that community's owner, else the not-admin state is correct); `membership_update_owner_without_community.apns` → My communities; `broadcast_community.apns` → the Announcements sheet scrolled to that row. Then the **background case**: on the second simulator, make the throwaway account an owner of the O4 community from the owner's device (`set_member_role` through the app, **(writes)**, part of O4's clean-up), send the app to the background (`xcrun simctl launch booted com.apple.Preferences`), `simctl push` `membership_update_owner.apns` with that community, tap the banner → Members with the owner actions, not the not-admin state (the push was never delivered to `willPresent`, so only Task 2's role refresh can have caught it up). Record the "Navigating to:" log line for each.
- [ ] **O3. Universal Link.** (a) `xcrun simctl openurl booted 'https://naarscars.com/join#<CODE>'` (a real code of the O4 community). **Without the hosted AASA file this opens Safari, which is expected and not a failure**; record what Safari shows (the landing page if the owner has published it, else whatever `naarscars.com/join` serves). The app registers no custom URL scheme (`Info.plist` has no `CFBundleURLTypes`), so there is no other `openurl` route into it. (b) The parser and handler through the DEBUG launch argument, on the second simulator: signed out, `xcrun simctl launch booted com.NaarsCars -debugIncomingURL 'https://naarscars.com/join#<CODE>'` → Welcome shows "You have an invite. Sign up or sign in to use it." (the app was cold-started: the deferred path); with Welcome on screen, `terminate` is **not** used: background the app, `launch` again with the argument → the banner (warm path); as a guest → the "Join the Community" prompt, then Sign Up → Welcome with the banner; signed in with one membership → Profile → My communities with the Join sheet showing the code's community (`validate_community_invite`, read only); with My communities already open **from the Profile row** (tap the row, then relaunch with the argument while it is on screen) → one My communities on the stack (back once returns to Profile) and the sheet opens once; the same with My communities opened by a `membership_update_approved.apns` tap; with Admin Panel pushed on top of My communities → no sheet, the saved-code row shows the code, and back to My communities shows the row (Review Focus 4). (c) After the owner has hosted the AASA file and a build with Task 5's entitlement is installed: repeat (a); the app opens on the Join sheet. If the owner has not hosted it yet, (c) is recorded as pending.
- [ ] **O4. Live matrix (writes),** in order: on the second simulator (simulator time zone = the Mac's) a throwaway account creates "P4 Live Check" → `select timezone from communities where name = 'P4 Live Check'` equals the Mac's `TimeZone.current.identifier` (read with `readlink /etc/localtime`); Settings: change the zone to `America/New_York`, save → the row reads it; Create Ride in that community starts in New York time; the owner's account joins by code and is approved → two memberships on the owner's device: the Requests narrow to Seattle shows "N more requests in your other communities" when the test community has an open request; the bell shows chips; rename the test community, the panel opened from My communities shows the new name on return; archive it as its only remaining member (after the owner leaves) → the onboarding root shows "… was archived."; delete the throwaway account. Clean-up: the community stays archived, no throwaway account remains, the owner's membership is `left`.
- [ ] **O5. Gated server files**: confirm with the owner that Files B and C stay NOT APPLIED and record the A5 gate condition in the report. Nothing is applied in this gate.
- [ ] **O6. Shut down** (`xcrun simctl shutdown booted`); push the branch and update the draft PR description with the Impact Summary (owner).

---

## New files

| Path (Xcode navigator path) | Target | Task | How |
|---|---|---|---|
| `Docs/qa/push-fixtures/membership_update_approved.apns`, `membership_update_owner.apns`, `membership_update_owner_without_community.apns`, `broadcast_community.apns` | none | 2 | normal tools |
| `NaarsCars/Core/Utilities/IncomingLinkHandler.swift` | NaarsCars | 4 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Core/Utilities/IncomingLinkHandlerTests.swift` | NaarsCarsTests | 4 | Xcode MCP |
| `Docs/universal-links/apple-app-site-association` | none | 5 | normal tools |
| `NaarsCars/Core/Utilities/RootNotice.swift` | NaarsCars | 11 | Xcode MCP |
| `Docs/qa/2026-10-19-multi-community-phase4-gate.md` | none | 13 | normal tools |

## Self-review notes

- **Spec §4 Phase 4 coverage (lines 972-976).** "N in other communities" hint (Task 6, client-side as D6 allows: no RPC); bell-row chips (7); real `broadcast` push honouring `canBeDisabled == false` and the community mute, routed to Announcements (client route pinned in 2; server in SQL plan File B, GATED by A5 point 2); `membership_update` through the four-layer registry (1: Swift enum + registry + TS + fixtures + script; SQL CHECK and `should_notify_user` in SQL plan File A; `get_badge_counts` needs no edit, SQL plan), its routes (2) and fixtures (2), producers GATED (SQL plan File C); the Universal Link with the code in the fragment (3, 4, 5), the `applinks:` entitlement (5), the AASA at `Constants.URLs.deepLinkBase` (5, owner hosts), `onOpenURL` → `DeepLinkParser.parse(url:)` → `DeepLink.joinCommunity(code)` → the join sheet (3, 4), signed out → `PendingInviteStore` + the Welcome banner with exactly the spec's sentence (4; the key exists), the revived `AppDelegate.handleURL` path replaced by the scene route (4); community time zone as the create-form default (8: device zone at creation, owner edits; 9: the ride and favor forms, the other reading of "create-form default"). "What old clients see": nothing different (File A is additive; B and C are gated); an old client's Universal Link tap falls back to Safari and the landing page (5).
- **Decisions.** D13 (a) is built except "platform admins may pick All communities": the Phase 3 `BroadcastView` sends to one community and the cap is per community; an "All" choice would be N announcements against N caps. Deferred (owner can veto). D15: link in Phase 4 with the code in the fragment (3, 5). D22: replaced for further-community approvals and for being let back into a further community (`approve_community_member` and `readmit_community_member`, SQL plan File C blocks 1 and 4) by `membership_update` once File C is applied; `user_approved` stays for the first approval.
- **Deliberate departures the owner can veto.** (1) Signed-in links go through `PendingInviteStore` and My communities (whose Join sheet already reads it) instead of a new sheet on `MainTabView`: one presenter, present-record-act-on-dismiss kept, and a cancelled sheet loses nothing. (2) `DeepLink.joinCommunity` carries the code but `NavigationIntent.joinCommunity` does not: the store is the single holder, and intents are logged. (3) `www.naarscars.com` is not accepted (the entitlement names only the bare domain). (4) The share message carries the link only after the owner flips `shareInviteLinks` (Task 5), so no build sends a link to a page that does not exist. (5) The DEBUG launch argument `-debugIncomingURL` (Task 4) exists only for simulator verification without the hosted AASA. (6) Bell `membership_update` rows route by the person's current role, push taps by `membership_event`; rows have no event column. (7) Settings lets the owner change the time zone (the server allows it; Phase 3 deferred the field). (8) No notice on promotion to admin or on demotion (the spec names ownership changes and further-community approvals only). (9) The pending-approval waiting screen does not prefill a code from a link (the code stays saved and opens once a membership is active or on onboarding). (10) The members screen refreshes the memberships itself (once per view-model lifetime) when it opens from a `membership_update` push or when its role check fails, instead of `AppDelegate` refreshing on every push tap; the refresh is `CommunityContext.refreshMemberships()`, not a coordinator call (Task 2). (11) The QR carries the bare link once links are on, and the share sheet the prose (Task 5).
- **Tests.** Spec-named: none beyond the registry procedure; CLAUDE.md-mandated: the fixture gate for the registry (1) and payload routes (2), the routing table for every new intent (2, 3), launch-state routing for URLs (4). Review Focus: 1 (4, 13), 2 (3, 4), 3 (4), 4 (3, 4, 13), 5 (1, SQL plan), 6 (6), 7 (8, SQL plan), 8 (11). Expected new cases: 71 (Task 13 Step 2).
- **Deferred: gate follow-ups this plan does not schedule** (each checked against the two gate reports and the Phase 5 plan's task index, which schedules none of them; the owner can pull any into Task 10 or 11):
  - *Community reports from `admin_get_reports` without a name, not dismissable* (Phase 2 gate follow-up; CLAUDE.md Phase 2 note): **closed in Phase 3**, not deferred — the Phase 3 gate (`:70`) saw the community named and Dismiss work. Task 12 corrects CLAUDE.md.
  - *The member detail keeps a stale action set after an ownership transfer made elsewhere* (Phase 3 gate `:117`): **partly closed by Task 2** — the members screen opened from a `membership_update` push refreshes the memberships first, and any load whose role check fails refreshes once before showing not-admin. Still open: a screen opened by another route while the role check still passes (an owner demoted to admin elsewhere keeps owner actions until the next foreground, `refreshMembershipsIfStale`). The server refuses the stale action and the view model reloads (Phase 3 "not allowed, reload" path), so nothing wrong is written. Deferred: a refresh on every open of the members screen would cost one `get_my_memberships` per open.
  - *`BroadcastView` send errors as red text in a card, not `.errorBanner(message:)`* (Phase 3 render 5; the screen's pattern since `a600f5c`, not a regression). Deferred design-system follow-up.
  - *The title-menu chevron missing when memberships load after the first render* (Phase 1 finding 2, a caveat in the Phase 2 gate, `:36`): **closed**, verified with the Phase 1 fix in the Phase 2 owner-present steps (`Docs/qa/2026-10-18-multi-community-phase2-gate.md:93`). Not deferred.
  - *Phase 3 deliberate departures and SQL deviations the gate recorded* (`Docs/qa/2026-10-18-multi-community-phase3-gate.md:163-169`): "Auto-hidden" label (D-S7), direct `announcement`-typed inserts (D-S8), no co-owner action, no `set_primary_community` screen, no admin delete of posts; the time-zone field is the one this plan builds (Task 8). The Notion mirror of the Task 9 legal text is a release prerequisite the owner owns, unchanged.
  - *Not verified at the earlier gates and not re-run here:* the Leave sheet at AX 5 and the 60-character community name at AX 5 (Phase 2 render 9a, 9c); Task 13 O1's 60-character capture covers the bell row only.
- **Release safety.** The entitlement is the one App Store risk: the archive, and any signed build for the owner's device, fails to sign until the owner adds the capability (Prerequisite 1a); and links work for users only once the AASA file is live before the release reaches them (Prerequisite 1b). `RELEASE` runs in Tasks 5 and 13; `ENTITLEMENTS` / `ENTITLEMENTS-RELEASE` prove the key is in what the build applied (the `.xcent`; `codesign -d` shows nothing on a simulator build).
- **Localization.** All new copy is in the catalog with six locales; no raw server value is shown (time zones by `TimeZone.localizedName`, refusals by `CommunityRPCError.localizedMessage`).
- **Type and name consistency.** `NotificationType.membershipUpdate`, `DeepLink.communityMembers(communityId:)` / `.joinCommunity(code:)` / `logDescription`, `NavigationIntent.communityMembers` / `.joinCommunity`, `NotificationIntent.openCommunityMembers(communityId:)`, `NavigationCoordinator.applyExternalDeepLink(_:)` / `guestPromptReason(for:)`, `NotificationNavigationRouter.init(…isAdminOf:)`, `Constants.URLs.universalLinkHost` / `joinPath` / `joinLink(code:)`, `Constants.Community.shareInviteLinks`, `PendingInviteStore.didChange`, `IncomingLinkHandler` / `IncomingLinkDecision`, `RequestFilterManager.countOutsideScope(in:filter:scope:)`, `RequestsDashboardViewModel.otherCommunitiesCount`, `NotificationRow(…communityChipText:)`, `CommunitySettingsChange.timezone`, `TimeZonePicker.options(including:)`, `chooseTimezone(_:)` / `applyCommunityTimezoneDefault()`, `CommunityInviteViewModel.usesText(_:)`, `AdminPanelViewModel.refreshCommunityName()`, `RootNotice.pending`, `CommunityOnboardingViewModel.takeRootNotice()` are spelled the same in every task that uses them.
