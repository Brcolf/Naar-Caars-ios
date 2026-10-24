# Multi-community Phase 5 (deprecations, split into 5a and 5b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** *5a, built and applied now:* remove the dead invite UI, the superseded application and pending-users screens and the other dead files the Audit Notes list, together with their Xcode project references; stop the client writing `profiles.heard_about` / `join_reason`; move the ride-cost place lookup onto a definer RPC that returns only the multiplier; read message, group, Town Hall and review images (and, if the owner accepts D-1, voice notes) through signed storage URLs while the buckets are still public. *5b, written and dry-run now, NOT APPLIED:* retire the two legacy bridges, the `fill_request_community` default fallback and the default-community answer copy, revoke `admin_reject_pending_user`, drop `invite_codes`, revoke direct access to `geocoding_cache`, and make the four image buckets private; each file waits for the gate in amendment A5 point 2.

**Architecture:** 5a is client-heavy and server-light. Every remote image the app shows already goes through one function, `PersistentImageService.getImage(for:)` (`Core/Services/PersistentImageService.swift:33-67`), from the SwiftUI `CachedAsyncImage` (`UI/Components/Common/CachedAsyncImage.swift:62-63`), the UIKit `ImageBubbleView` (`UI/Components/Messaging/Cells/ImageBubbleView.swift:106`), `AvatarUIView` (`UI/Components/Common/AvatarUIView.swift:97`) and `ImageViewerView` (`UI/Components/Messaging/ImageViewerView.swift:130`). A new `StorageURLSigner` actor turns a stored public URL of a signed bucket into a short-lived signed URL at download time, in memory only. **What is stored does not change**: `messages.image_url`, `conversations.group_image_url`, `town_hall_posts.image_url`, `reviews.image_url` and `SDMessage.imageUrl` (`Core/Storage/SDModels.swift:51`) keep the public URL the upload returned, so the installed App Store build keeps showing images sent from the new build until 5b, and the SwiftData model, the mappers and the sync engines are not touched (decision D-2). The geocoding change replaces four direct table calls in `GeocodingCacheService.swift` with two RPCs. The deletions go through the Xcode MCP file tools, never a hand edit of `project.pbxproj`. `RefreshCoordinator`, realtime, `MessageSendManager`, `MessageSendWorker`, reactions, the notification registry, `BadgeCountManager` and the SwiftData schema are not modified.

**Tech Stack:** Swift 6.3 toolchain in Swift 5 language mode, SwiftUI + UIKit, supabase-swift 2.41.1 (`StorageFileApi.createSignedURL(path:expiresIn:)`, `build/DerivedData/SourcePackages/checkouts/supabase-swift/Sources/Storage/StorageFileApi.swift:268-292`), XCTest, Xcode 26.6, iOS 26.0 deployment target.

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` §4 "Phase 5 - Deprecations" (lines 976-980) and "What old clients see" (982), D16 (line 1094), D19, D20, INV-L1 (line 763), §5 rows "Storage and place data" and "Two-way `approved` mirror", under `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` amendment **A5** (lines 54-62; wins where they differ). The server contract is **`Docs/superpowers/plans/2026-10-19-multi-community-phase5-sql.md`** (File A applied now; Files B-E NOT APPLIED). Read all three before starting a task.

## Global Constraints

- Deployment target `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; `SWIFT_VERSION = 5.0`; `SWIFT_APPROACHABLE_CONCURRENCY = YES`; `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. No build-setting change, no new permission, entitlement, SDK or Info.plist key.
- **No user-visible change in 5a.** No screen is added or redesigned; no string key is added. The deleted screens are unreachable today (Task inventories prove it line by line). The only behaviour changes are where bytes come from (a signed URL instead of the public one) and which endpoint the cost estimate's place lookup calls.
- **Never persist or log a signed URL.** A signed URL lives only in `StorageURLSigner`'s in-memory cache and in the `URLRequest` that downloads the bytes. It is never written to Supabase, SwiftData, `UserDefaults`, the disk image cache's file name, `URLCache`, a temp-file name, or a log line (it carries a token). The disk cache keeps its key: the stored URL's `lastPathComponent` (`PersistentImageService.swift:37-38`). Two consequences:
  - **No `URLSession.shared` for a download that may be signed.** `App/AppDelegate.swift:17-21` gives `URLCache.shared` a 200 MB disk store, and `URLSession.shared` writes every cacheable response into it (`Library/Caches/<bundle id>/Cache.db`) keyed by the full request URL, token included. Every download in `PersistentImageService` and (Task 8) `MessageAudioPlayer` goes through `URLSession.signedStorageDownload`, a dedicated session built from `URLSessionConfiguration.ephemeral` with `urlCache = nil` and `requestCachePolicy = .reloadIgnoringLocalCacheData` (Task 7). The disk image cache and the audio temp-file cache already hold the bytes, keyed by the stored URL.
  - **No `Error` interpolated into a log line on these paths.** A `URLError`'s description carries `NSErrorFailingURLStringKey` / `NSErrorFailingURLKey`, i.e. the signed URL. `PersistentImageService` (today `AppLogger.error("images", "Failed to download image: \(error)")`, `:63`), `StorageURLSigner` and `SupabaseStorageSigner` log only `(error as NSError).domain` and `.code` (and the bucket name).
- **While the buckets are public (all of 5a), a signing failure falls back to the stored URL**, so no image disappears because of this phase. After 5b the fallback fails like any broken image and the next appearance signs again.
- `RefreshCoordinator.swift`, `RealtimeManager.swift`, `MessageSendManager.swift`, `MessageSendWorker.swift`, `MessagingRepository.swift`, `BackgroundSyncActor.swift`, `SDModels.swift`, `MessagingMapper.swift`, `NavigationCoordinator.swift`, `PushNotificationService.swift`, `BadgeCountManager.swift` are not edited. `MessagingSyncEngine.swift` is edited only in its private `precacheMedia(url:)` (`:508-511`), and only by Task 8 if the owner accepts D-1. `AuthService.swift` loses only dead methods (Task 3) and gains one line in `clearPerAccountLocalState` (Task 7).
- **RPC contract.** `get_geocoding_multiplier(p_location_key text) → numeric` (null on a miss or a refusal) and `put_geocoding_multiplier(p_location_key text, p_latitude numeric, p_longitude numeric, p_multiplier numeric) → boolean` (SQL plan File A blocks 1-2). Private `Encodable` params structs with explicit keys and a `nonisolated encode(to:)` (the `Core/Services/CommunityService.swift:15-195` idiom). No other RPC is added, changed or newly called. Task 2 removes the client's last call to `admin_reject_pending_user` (`Core/Services/AdminService.swift:463`).
- **Project files (decision 3 and A5 point 2).** Deletions use the Xcode MCP: open this worktree's project (`.claude/worktrees/naarscars-multi-community-roadmap-f08594/NaarsCars/NaarsCars.xcodeproj`), `XcodeListWindows`, confirm the workspace path of the tab, `XcodeLS` the group, then `XcodeRM` with `deleteFiles: true` (the file moves to the Trash and stays in git history). **Five of the files have two project references**, one in a normal group and one in the load-bearing "Recovered References" group (`project.pbxproj:1274-1333`, `name = "Recovered References"` at `:1333`). The "Recovered References" entries are file references **whose `path` is a slash path relative to the app group** (`path = Core/Utilities/Logger.swift`, `:630`), so their navigator name contains slashes; nothing shows yet that `XcodeRM` can address such an entry (Task 1 Step 1 probes it). Which reference carries the build file differs per file (read at `4956682`):

  | File | Normal-group reference | "Recovered References" reference | Build file (`PBXBuildFile` → `fileRef`) |
  |---|---|---|---|
  | `Logger.swift` | `:782` (child `:2145`) | `:630` (child `:1288`) | `:216` → `:782` (normal) |
  | `RidesDashboardView.swift` | `:762` (child `:1396`) | `:1090` (child `:1316`) | `:69` → `:1090` (Recovered) |
  | `RidesDashboardViewModel.swift` | `:758` (child `:1384`) | `:1124` (child `:1312`) | `:15` → `:1124` (Recovered) |
  | `FavorsDashboardView.swift` | `:755` (child `:1374`) | `:570` (child `:1300`) | `:78` → `:570` (Recovered) |
  | `FavorsDashboardViewModel.swift` | `:751` (child `:1363`) | `:668` (child `:1296`) | `:203` → `:751` (normal) |

  Remove **both** entries of each file, the "Recovered References" one with `deleteFiles: false`, then the normal-group one with `deleteFiles: true`, and never remove the "Recovered References" group itself (CLAUDE.md Audit Notes, project wiring). **Owner fallback** when the MCP cannot address or remove a "Recovered References" entry: the owner, in Xcode, selects the entry under "Recovered References", chooses Delete → **Remove Reference** (never Move to Trash for these: the normal-group entry still points at the same file on disk), and the task then runs `PBXCHECK` and `BUILD`; when both are clean the task records "Recovered References entry removed by the owner" and continues. New files go through `XcodeWrite` as in Phase 3. If another project is open, or a reference stays after the MCP and the owner fallback, stop: report "not removed from the project" and do not claim a green build. Never hand-edit `project.pbxproj`. Let Xcode go idle (or quit it) before each Lane B build.
- **Chain stop rule (orchestrator).** When a task reports a file "not yet in the project" or "not removed from the project", no later task runs until `PBXCHECK` is clean, `BUILD` is green, the task's tests pass and its commit exists.
- **String keys stay.** 75 keys become unused when the screens go (listed in Task 9). They are left in `NaarsCars/Resources/Localizable.xcstrings`: the pre-commit hook blocks removals (`scripts/pre-commit-localization-check.sh`), and removing keys is a separate, owner-approved cleanup.
- New ViewModels: none. State Management rule 2 (no migrations between `ObservableObject` and `@Observable`) is untouched.
- One build at a time on this Mac. One headless simulator (`iPhone 16`, iOS 26.x). Unit tests run with the simulator **signed out**. Never run `RideServiceTests`, `FavorServiceTests`, `TownHallServiceTests` or the live cases of `TownHallFeedViewModelTests` while signed in. URLProtocol stubs are registered in `setUp` and reset and unregistered in `tearDown` (`CommunityServiceURLProtocol`, `NaarsCarsTests/Core/Services/CommunityServiceTests.swift:11-87`, reused as is).
- Every task ends with a green Lane B build, its listed tests passing, and one commit whose subject starts `[P5-T<n>]` and whose body ends with the Co-Authored-By trailer the executing session was given. Stage files by path only (`git add -- <path>` also stages a deletion); never `git add -A` / `git add .`. Tasks never push.
- **Server.** Agents executing this plan never write under `supabase/`. The orchestrator applies SQL plan File A (5a) through the Supabase MCP under the owner's standing instruction (A5 last paragraph), writes Files B-E to disk with NOT APPLIED headers and dry-runs them (Task 11). **Nothing in Files B-E is applied in this phase.**
- **Public repository.** CLAUDE.md, Current State: ask before pushing a write-up of a hole that is still open on the live backend. Files B-E describe gaps that stay open until the gate (public image buckets, a table readable by any active account, an anon-callable `validate_invite_code`). Task 11 commits them locally; the orchestrator asks the owner before the push that carries them.
- Models: opus for every project-file removal through the Xcode MCP, every RPC call site, the messaging media path, and the gate; sonnet for documentation; never fable (task index).

### Commands (used by every task; `<n>` is the task number)

```bash
# BUILD (from the worktree root). Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build > build/P5-T<n>-build.log 2>&1; echo "exit=$?"
grep -n "error:" build/P5-T<n>-build.log | head -20
# New warnings: every "warning:" line naming a file this task touched must also appear in build/P5-baseline-build.log (Task 1 Step 0).
grep -n "warning:" build/P5-T<n>-build.log | grep -E "<touched file basenames joined with |>"

# RED (compile-level failing test). Expected: exit≠0 and the named compile error.
xcodebuild build-for-testing -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/DerivedData -quiet > build/P5-T<n>-red.log 2>&1; echo "exit=$?"; grep -n "error:" build/P5-T<n>-red.log | head

# TEST <ONLY> = one or more -only-testing:NaarsCarsTests/<Class>[/<method>]. Expected: exit=0, 0 failures.
rm -rf build/P5-T<n>.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' <ONLY> -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P5-T<n>.xcresult -quiet > build/P5-T<n>-test.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P5-T<n>.xcresult

# FULL = CLAUDE.md's Lane B full unit-suite command, signed out. Expected: exit=0, 0 failures; skips only in the session-gated classes.
rm -rf build/P5-T<n>-full.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P5-T<n>-full.xcresult -quiet > build/P5-T<n>-full.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P5-T<n>-full.xcresult

# PBXCHECK <basenames> = every removed file is gone from the project and from disk. Expected: no output.
# The leading non-letter keeps "Logger.swift" from matching AppLogger.swift / MessagingLogger.swift.
for b in <basenames>; do grep -nE "(^|[^A-Za-z])$b" NaarsCars/NaarsCars.xcodeproj/project.pbxproj; find NaarsCars -name "$b" -not -path "*/build/*"; done

# PREVIEWGUARD <files> = the touched view files. Prints every #Preview line outside an #if DEBUG block. Expected: no output.
awk 'FNR==1{d=0} /^#if DEBUG/{d=1} /^#endif/{d=0} /^#Preview/{if(!d) print FILENAME":"FNR": #Preview outside #if DEBUG"}' <files>

# RELEASE = a Release build for the simulator (no signing needed). Catches DEBUG-only names used outside #if DEBUG
# and dangling references a Debug build tolerates. Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Release -derivedDataPath build/DerivedData-Release -quiet build > build/P5-T<n>-release.log 2>&1; echo "exit=$?"
grep -n "error:" build/P5-T<n>-release.log | head -20
```

`FULL` runs at the end of Tasks 3, 5, 7 and in the gate (Task 10). `RELEASE` runs at the end of Tasks 5 and 7 and in the gate. Before the first `FULL`, confirm the simulator is signed out (install, launch, a screenshot shows Welcome); if it is signed in, stop and ask the owner. Record executed / passed / skipped in each task report. A new test file is in the right target when its `TEST` run reports the expected number of executed tests.

### Task index

| Task | Deliverable | Model | Effort |
|---|---|---|---|
| 1 | Delete the unreferenced files: `MessagingDebugView`, `Logger`, `InviteCodeCard`, `SignupInviteCodeView`, `SignupMethodChoiceView`, `AdminInviteView`, `InvitationWorkflowView` | opus | medium |
| 2 | Delete the platform Pending Users screens (`PendingUsersView`, `PendingUsersViewModel`, `PendingUserDetailView` with its view model) and `AdminService`'s legacy approve / reject / list (the last client call to `admin_reject_pending_user`) | opus | high |
| 3 | Delete the legacy invite-code stack: `InviteService`, `AuthService.signUp(email:password:inviteCode:)` / `validateInviteCode` / `createInviteCodeDecoder`, `ProfileService`'s invite-code methods, `InviteCode`, `InviteCodeGenerator` | opus | high |
| 4 | Delete the application form (`ApplicationFieldsView` + view model); move the name rules into `CommunityOnboardingViewModel`; remove `ProfileService.submitApplication` (the client's only `heard_about` / `join_reason` write to `profiles`) | opus | high |
| 5 | Delete the dead Rides and Favors dashboards with their tests (double project references) | opus | medium |
| 6 | Ride-cost place lookup through `get_geocoding_multiplier` / `put_geocoding_multiplier` | opus | high |
| 7 | Signed storage URLs for images: `StorageURLSigner`, `PersistentImageService`, sign-out reset | opus | high |
| 8 | Signed URLs for voice notes (only if the owner accepts D-1) | opus | high |
| 9 | Documentation for Phase 5a and the 5b gate | sonnet | medium |
| 10 | Phase 5a gate | opus | high |
| 11 | 5b: write the gated migration files and the probe additions, dry-run them, apply nothing | opus | high |
| 12 | 5b gate (runs only after the owner's App Store Connect confirmation; not part of this workflow) | opus | high |

### Prerequisites outside this plan

1. **Phase 4 is built, gated and pushed** (A5 point 3: Phase 4, then 5a). `git status --porcelain` is clean at Task 1 Step 0. Phase 4 (`Docs/superpowers/plans/2026-10-19-multi-community-phase4.md`, log names `P4-T<n>`, migrations `20261019_0001`-`0003`) touches `DeepLinkParser`, `AppDelegate`, `WelcomeView`, `PendingInviteStore` and the registry; it also edits two files this plan edits, `CommunityOnboardingViewModel.swift` (its onboarding fixes; this plan's Task 4) and `Constants.swift` (`URLs`, `Community`; this plan's Task 7 edits `Storage` only), plus `CLAUDE.md`, `AGENTS.md` and `SECURITY.md` (Task 9 edits on top of Phase 4's text). The line numbers here were read at `4956682`; every task's Step 0 re-greps and stops on a difference it cannot explain.
2. **Migration numbers.** Phase 4 uses `20261019_0001`-`0003`; this plan's SQL files are `20261019_0050` (5a) and `20261019_0060`-`0063` (5b), so they do not collide. If a later change took any of them, the orchestrator renumbers upward before writing, keeping the order.
3. **Xcode with this worktree's project open** for Tasks 1-5 (removals) and 6-8 (new files), idle during builds.
4. **SQL plan File A is applied before Task 10's live checks.** Task 6 is verified with stubs; until File A is live the new client finds no lookup function, turns the cache off for the session and still produces every estimate from the on-device rules (Review Focus 6).
5. **The owner's go-ahead for Task 10's writes** (two throwaway accounts, a test community, a thread with a photo, a group photo, a Town Hall photo, a ride), as in the Phase 3 gate.
6. **For Task 12 only:** the owner's confirmation from App Store Connect that no pre-community build remains in use, and, for SQL Files D and E, that every build in use contains this phase's client (Task 12 states both conditions).
7. **Owner decision D-1** (voice notes) before Task 8 runs. Without a yes, Task 8 is skipped and SQL File E's optional audio block is left out.

## Review Focus

These are not exercised by any test the spec names. Each is pinned in its owning task.

1. **A file removed from disk while a project reference stays, or a reference removed while the file stays** (the "Recovered References" duplicates). Expected: `PBXCHECK` prints nothing and `RELEASE` is green. Pinned by Tasks 1-5 (`PBXCHECK` step in each) and Task 10.
2. **A signed URL written anywhere** (database, SwiftData, the disk cache name, a log). Expected: never. Pinned by Task 7 (`testGetImage_CachesUnderTheStoredNameNotTheSignedOne`, `testResolve_ReturnsSignedURLWithoutChangingTheStoredValue`, `testGetImage_ResolvedDownloadLeavesNoURLCacheEntry`, `testSignedStorageDownloadSession_HasNoURLCache`, and the Step 4 log grep), Task 8 (`testResolvePlayableURL_DownloadsSignedAndCachesUnderTheStoredURL`) and Task 10 (the SQL and SwiftData checks after a live send).
3. **Signing fails while the buckets are public.** Expected: the stored URL is used and the image shows; the failure is not cached. Pinned by Task 7 (`testResolve_SignerFailureFallsBackToStoredURLAndRetriesNextTime`).
4. **A thread with 40 images scrolled at once.** Expected: one signing request per object, not one per cell configuration. Pinned by Task 7 (`testResolve_ConcurrentCallsForOnePathShareOneRequest`).
5. **A signed URL that expires while the app stays open** (a viewer opened an hour later). Expected: re-signed before expiry. Pinned by Task 7 (`testResolve_RenewsInsideTheRenewMargin`).
6. **The lookup functions are not live yet, or the server errors.** Expected: the estimate is still produced; a missing function turns the lookup off for the session (no repeated failing calls), a transient error does not. Pinned by Task 6 (`testMissingFunction_DisablesLookupForTheSession`, `testServerError_DoesNotDisableLookup`).
7. **The name step after the application form is gone.** A repeat Sign in with Apple creates "Apple User" (`Core/Services/AuthService+AppleSignIn.swift:378`). Expected: onboarding still asks for a name. Pinned by Task 4 (`testNameProblem_RejectsPlaceholderEmptyAndShortNames`) and the existing `CommunityOnboardingViewModelTests` (`NaarsCarsTests/Features/Community/CommunityOnboardingViewModelTests.swift:79-115`).
8. **A guest opening a public community's Town Hall photo.** Signing runs with the anon key. Expected: in 5a it works (public bucket); after 5b it works through File E's anon policy. Pinned by Task 10 (O4) and SQL probe `storage_private`.

---

### Task 1: Delete the unreferenced files

**Model:** opus, medium effort (project-file removals through the Xcode MCP; one of the files, `Logger.swift`, has a duplicate reference in "Recovered References") · **Files:**
- Remove (Xcode MCP): `NaarsCars/Core/Services/MessagingDebugView.swift`, `NaarsCars/Core/Utilities/Logger.swift` (two references), `NaarsCars/UI/Components/Cards/InviteCodeCard.swift`, `NaarsCars/Features/Authentication/Views/SignupInviteCodeView.swift`, `NaarsCars/Features/Authentication/Views/SignupMethodChoiceView.swift`, `NaarsCars/Features/Admin/Views/AdminInviteView.swift`, `NaarsCars/Features/Profile/Views/InvitationWorkflowView.swift`
- Modify: `NaarsCars/Core/Utilities/InviteCodeFormatter.swift:11` (the doc comment names the removed views; it becomes "Formats community invite codes for display.")
- Modify (by the MCP): `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`

**Caller inventory at plan time** (each caller traced to the line; nothing live):

| File | References outside itself | What they are |
|---|---|---|
| `MessagingDebugView.swift` (whole file `#if DEBUG`, `:9`; declares `MessagingDebugView`, `InfoRow` `:210`, `MessagingDebugViewModel` `:228`) | none | dead (CLAUDE.md Audit Notes item 5) |
| `Logger.swift` (`enum Log`, `:12`, six static functions `:16-47`) | no `Log.` call anywhere; the two "Logger" hits are `os.Logger` in `Core/Services/MessagingLogger.swift:39` and `Core/Services/AppLogger.swift:16-22, 246-262` | not callers; the file is dead (Audit Notes item 5) |
| `InviteCodeCard.swift` | none | dead |
| `SignupInviteCodeView.swift` | none | dead (CLAUDE.md database contract: "`SignupInviteCodeView` is not presented") |
| `SignupMethodChoiceView.swift` | `SignupInviteCodeView.swift:95` | dead caller (removed in the same task) |
| `AdminInviteView.swift` (declares `BulkInviteSheet` `:216`, `AdminInviteViewModel` `:286`) | `InviteCodeFormatter.swift:11` (comment) | comment only; `git grep AdminInviteView main` shows no presenter in the installed build either |
| `InvitationWorkflowView.swift` | `AdminInviteView.swift:180` (dead), `InviteCodeFormatter.swift:11` (comment) | dead caller + comment |

Tests referencing them: none (`grep -rn` over `NaarsCars/NaarsCarsTests`). UI tests: `NaarsCarsUITests.swift:246-247, 575` drive an invite-code screen by accessibility identifier only (no Swift type reference); they do not run in CI and already target a screen that is not presented. Left as a follow-up (Task 9 records it).

- [ ] **Step 0: Preconditions and baseline.** `git status --porcelain` is empty (else stop and ask). Build `HEAD` with `BUILD`'s command into `build/P5-baseline-build.log`; record the warning count. Re-run the inventory: `grep -rn --include='*.swift' -w -e MessagingDebugView -e InviteCodeCard -e SignupInviteCodeView -e SignupMethodChoiceView -e AdminInviteView -e InvitationWorkflowView NaarsCars | grep -v -e '/MessagingDebugView.swift:' -e '/InviteCodeCard.swift:' -e '/SignupInviteCodeView.swift:' -e '/SignupMethodChoiceView.swift:' -e '/AdminInviteView.swift:' -e '/InvitationWorkflowView.swift:'` must print only `InviteCodeFormatter.swift:11`; `grep -rnE --include='*.swift' '\bLog\.[a-z]+\(' NaarsCars | grep -v Utilities/Logger.swift` must print nothing. Any other line: stop and report it.
- [ ] **Step 1: Open the project.** `XcodeListWindows`; pick the tab whose workspace path ends in `naarscars-multi-community-roadmap-f08594/NaarsCars/NaarsCars.xcodeproj`. `XcodeLS NaarsCars/Core/Services`, `NaarsCars/Core/Utilities`, `NaarsCars/UI/Components/Cards`, `NaarsCars/Features/Authentication/Views`, `NaarsCars/Features/Admin/Views`, `NaarsCars/Features/Profile/Views`, and the "Recovered References" group (find its navigator path with `XcodeLS NaarsCars`); write down the navigator path of every entry to remove. **Probe the "Recovered References" addressing (Global Constraints, project files):** `XcodeLS` the "Recovered References" group and copy, verbatim into the task report, the names the MCP prints for the five entries of Tasks 1 and 5 (`Core/Utilities/Logger.swift`, `Features/Rides/Views/RidesDashboardView.swift`, `Features/Rides/ViewModels/RidesDashboardViewModel.swift`, `Features/Favors/Views/FavorsDashboardView.swift`, `Features/Favors/ViewModels/FavorsDashboardViewModel.swift`, as `project.pbxproj:630, 1090, 1124, 570, 668` name them). Then try `XcodeRM` with `deleteFiles: false` on the `Logger.swift` entry only, addressed by the exact printed name under the group's printed path. Check with `grep -n '4B2C428BD1164C7C99F84038' NaarsCars/NaarsCars.xcodeproj/project.pbxproj` (the entry's id, `:630`, `:1288`): no output means the MCP can remove these entries, and Task 5 uses the same form; any output, or an MCP error, means the owner fallback is used for all five (record which in the report, so Task 5 does not probe again). `NaarsCars/Core/Utilities/Logger.swift` must still exist on disk after this step (`ls`).
- [ ] **Step 2: Remove** with `XcodeRM` (`deleteFiles: true`), in this order: `SignupMethodChoiceView.swift`, `SignupInviteCodeView.swift`, `InvitationWorkflowView.swift`, `AdminInviteView.swift`, `InviteCodeCard.swift`, `MessagingDebugView.swift`; for `Logger.swift`, when the Step 1 probe did not already remove its "Recovered References" entry, the owner removes it (Remove Reference), then the agent removes the `Core/Utilities` group entry with `deleteFiles: true` (that entry, `:782`, carries the build file `:216`).
- [ ] **Step 3: Edit** `InviteCodeFormatter.swift:11` (comment only).
- [ ] **Step 4: Verify.** `PBXCHECK MessagingDebugView.swift Logger.swift InviteCodeCard.swift SignupInviteCodeView.swift SignupMethodChoiceView.swift AdminInviteView.swift InvitationWorkflowView.swift` prints nothing; `grep -c "Recovered References" NaarsCars/NaarsCars.xcodeproj/project.pbxproj` is unchanged from before Step 2.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityInviteViewModelTests -only-testing:NaarsCarsTests/JoinCommunityViewModelTests` (the users of `InviteCodeFormatter`; `CommunityInviteViewModelTests` is declared in `NaarsCarsTests/Features/Community/CreateCommunityViewModelTests.swift`). Expected: green, executed count unchanged.
- [ ] **Step 6: Commit** `[P5-T1] Remove the unreferenced invite, signup-method and debug files` with the seven removed paths, `InviteCodeFormatter.swift` and `project.pbxproj`.

Tests: none added (deletion of code no test reaches). Captures: none.

---

### Task 2: Delete the platform Pending Users screens and the legacy approve / reject / list

**Model:** opus, high effort (removes the client's only call site of `admin_reject_pending_user`, an RPC call site and an account-deleting path; CLAUDE.md lists RPC call sites as a high-blast-radius seam) · **Files:**
- Remove (Xcode MCP): `NaarsCars/Features/Admin/Views/PendingUsersView.swift` (declares `PendingUserRow` `:121`), `NaarsCars/Features/Admin/ViewModels/PendingUsersViewModel.swift`, `NaarsCars/Features/Admin/Views/PendingUserDetailView.swift` (declares `PendingUserDetailViewModel` `:191`)
- Modify: `NaarsCars/Core/Services/AdminService.swift:211-230` (`fetchPendingUsers`), `:369-434` (`approveUser`, the direct `profiles.approved = true` write at `:386`), `:436-475` (`rejectUser`, the `admin_reject_pending_user` call at `:446-463`) — removed
- Modify (by the MCP): `project.pbxproj`

**Caller inventory at plan time:**

| Symbol | References | What they are |
|---|---|---|
| `PendingUsersView` | none outside the file (the Phase 2 router sends `.pendingUsers` to Requests to join; `MyProfileView` and `AdminPanelView` no longer present it, unlike `main:MyProfileView.swift:188`, `main:AdminPanelView.swift:227`) | dead |
| `PendingUsersViewModel` | `PendingUsersView.swift:12` | dead caller |
| `PendingUserDetailView` | `PendingUsersView.swift:43` | dead caller |
| `PendingUserDetailViewModel` | `PendingUserDetailView.swift:15`; uses `InviteService.shared` (`:200`, `:209`) | inside the removed file |
| `AdminService.fetchPendingUsers` | `PendingUsersViewModel.swift:54` | dead caller |
| `AdminService.approveUser` | `PendingUsersViewModel.swift:107`, `PendingUserDetailView.swift:228` | dead callers |
| `AdminService.rejectUser` | `PendingUsersViewModel.swift:142`, `PendingUserDetailView.swift:250` | dead callers |

None of the three `AdminService` methods is on `AdminServiceProtocol` (`Core/Protocols/AdminServiceProtocol.swift`, community methods only), so `StubAdminService` and `PreviewAdminService` are unaffected. `fetchApplicantContact` (`AdminService.swift:236`, behind `ApplicantContactFetching`) and `verifyAdminStatus` (`:188`) stay. Tests referencing the removed symbols: none. The `.pendingUsers` intent and `NotificationIntent` cases stay (they route to Requests to join, CLAUDE.md Notification rule 9).

- [ ] **Step 0: Inventory.** `grep -rn --include='*.swift' -e 'PendingUsersView\b' -e PendingUsersViewModel -e PendingUserDetailView -e 'fetchPendingUsers' -e '\.approveUser(' -e '\.rejectUser(' -e admin_reject_pending_user NaarsCars` lists only the lines in the table, `AdminService.swift`'s own definitions and `:446` / `:463`. Anything else: stop.
- [ ] **Step 1: Remove** the three files with `XcodeRM` (`deleteFiles: true`), `PendingUserDetailView.swift` first.
- [ ] **Step 2: Edit** `AdminService.swift`: delete the three methods with their doc comments. Do not touch `verifyAdminStatus`, `fetchApplicantContact`, `fetchAllMembers`, `setAdminStatus`, `banUser`, `unbanUser`.
- [ ] **Step 3: Verify.** `PBXCHECK PendingUsersView.swift PendingUsersViewModel.swift PendingUserDetailView.swift` prints nothing; `grep -rn admin_reject_pending_user NaarsCars --include='*.swift'` prints nothing; `grep -rn '"approved": AnyCodable' NaarsCars --include='*.swift'` prints nothing.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/AdminServiceTests -only-testing:NaarsCarsTests/PendingMembersViewModelTests -only-testing:NaarsCarsTests/NavigationCoordinatorRoutingTests`. Expected: green, counts unchanged.
- [ ] **Step 5: Commit** `[P5-T2] Remove the platform Pending Users screens and the legacy approve and reject calls` with the three removed paths, `AdminService.swift`, `project.pbxproj`.

Tests: none added (the `pending_approval` routes are pinned by `NavigationCoordinatorRoutingTests` and the Phase 2 fixtures). Captures: none.

---

### Task 3: Delete the legacy invite-code stack

**Model:** opus, high effort (`AuthService.swift` is a high-risk file; the removed methods are dead, but the file also holds sign-up, sign-out and teardown) · **Files:**
- Remove (Xcode MCP): `NaarsCars/Core/Services/InviteService.swift` (declares `InviteCodeWithInvitee` `:389`, `InviteStats` `:403`), `NaarsCars/Core/Models/InviteCode.swift`, `NaarsCars/Core/Utilities/InviteCodeGenerator.swift` (decision D-3)
- Modify: `NaarsCars/Core/Services/AuthService.swift:170-220` (`signUp(email:password:inviteCode:)` with its doc comment), `:412-526` (`validateInviteCode(_:)` with its doc comment), `:528-557` (`createInviteCodeDecoder()`) — removed
- Modify: `NaarsCars/Core/Services/ProfileService.swift:388-431` ("Invite Codes Operations": `fetchInviteCodes(forUserId:)`, `generateInviteCode(userId:)`) — removed
- Modify (by the MCP): `project.pbxproj`

**Caller inventory at plan time:**

| Symbol | References | What they are |
|---|---|---|
| `InviteService` | `AuthService.swift:204-207` (inside the dead `signUp(…inviteCode:)`), `AdminInviteView.swift:292`, `PendingUserDetailView.swift:200`, `InvitationWorkflowView.swift:227` | the last three are gone after Tasks 1-2; the first goes here |
| `AuthService.signUp(email:password:inviteCode:)` (`:177`) | none (not on `AuthServiceProtocol`, `Core/Protocols/AuthServiceProtocol.swift:21` declares only the public-signup overload; `SignupViewModel.swift:175` calls that one) | dead |
| `AuthService.validateInviteCode` (`:418`) | `AuthService.swift:183` (dead method), `SignupInviteCodeView.swift:141` (removed in Task 1) | dead |
| `AuthService.createInviteCodeDecoder` (`:530`) | `AuthService.swift:465` (inside `validateInviteCode`) | dead |
| `ProfileService.fetchInviteCodes` / `generateInviteCode` (`:394`, `:411`) | none; not on `ProfileServiceProtocol` | dead; they read and write `invite_codes`, which SQL File C drops |
| `InviteCode` | `AuthService.swift:418-468`, `ProfileService.swift:394-431`, `InviteService.swift` throughout, and files removed in Tasks 1-2 | none left after this task |
| `InviteCodeGenerator` | `AuthService.swift:420, 423`, `InviteService.swift:94, 113, 161, 178`, `ProfileService.swift:413` | none left after this task |

Stays: `InviteCodeFormatter` (used by `Features/Community/Views/CommunityInviteSheet.swift:63, 147` and `CommunityInviteViewModel.swift:54`), `AppError.invalidInviteCode` (`Core/Utilities/AppError.swift:19`, mapped by `LoginViewModel.swift:108`), `PendingInviteStore`. Tests referencing the removed symbols: none.

- [ ] **Step 0: Inventory.** `grep -rn --include='*.swift' -e InviteService -e 'InviteCode\b' -e InviteCodeGenerator -e validateInviteCode -e createInviteCodeDecoder -e fetchInviteCodes -e 'generateInviteCode' -e '"invite_codes"' NaarsCars` lists only `AuthService.swift`, `ProfileService.swift` and the three files to remove. Anything else: stop.
- [ ] **Step 1: Edit** `AuthService.swift` and `ProfileService.swift` (delete the methods and their doc comments; nothing else in either file changes; re-read the surrounding 20 lines to confirm the `// MARK:` structure is intact).
- [ ] **Step 2: Remove** `InviteService.swift`, `InviteCode.swift`, `InviteCodeGenerator.swift` with `XcodeRM` (`deleteFiles: true`).
- [ ] **Step 3: Verify.** `PBXCHECK InviteService.swift InviteCode.swift InviteCodeGenerator.swift` prints nothing; `grep -rn '"invite_codes"\|InviteCodeGenerator\|InviteService' NaarsCars --include='*.swift'` prints nothing.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/AppLaunchManagerTests -only-testing:NaarsCarsTests/CommunityServiceTests -only-testing:NaarsCarsTests/PendingInviteStoreTests -only-testing:NaarsCarsTests/ProfileServiceTests`; then `FULL` (auth seam). Expected: green; `FULL` executed = the Phase 4 gate's count (no test removed yet).
- [ ] **Step 5: Commit** `[P5-T3] Remove the legacy invite-code service, model and sign-up path` with the three removed paths, `AuthService.swift`, `ProfileService.swift`, `project.pbxproj`.

Tests: none added. Captures: none.

---

### Task 4: Delete the application form; stop the client writing answers to `profiles`

**Model:** opus, high effort (auth and launch routing: the `.needsApplication` root and the Apple-placeholder name rule; scope item (b)) · **Files:**
- Modify first: `NaarsCars/Features/Authentication/ViewModels/CommunityOnboardingViewModel.swift:50, 59` (doc comments), `:87`, `:98` — gains `static let applePlaceholderName = "Apple User"` and `static func nameProblem(_ trimmedName: String) -> String?`, moved verbatim from `ApplicationFieldsViewModel.swift:21-24, 55-70`; `:87` and `:98` call `Self.…`
- Remove (Xcode MCP): `NaarsCars/Features/Authentication/Views/ApplicationFieldsView.swift`, `NaarsCars/Features/Authentication/ViewModels/ApplicationFieldsViewModel.swift`
- Modify: `NaarsCars/Core/Protocols/ProfileServiceProtocol.swift:28` (`submitApplication` requirement, removed), `NaarsCars/Core/Services/ProfileService+AccountStatus.swift:36-49` (`submitApplication`, removed; the file keeps `fetchBanReason`; header comment `:5` becomes "Own-row account status reads: ban reason")
- Modify: `NaarsCars/NaarsCarsTests/Features/Community/CommunityOnboardingViewModelTests.swift` (one test)
- Modify (by the MCP): `project.pbxproj`

**Caller inventory at plan time:**

| Symbol | References | What they are |
|---|---|---|
| `ApplicationFieldsView` | `ApplicationFieldsViewModel.swift:12` (comment) | dead; `ContentView` roots `.needsApplication` at `CommunityOnboardingView` (CLAUDE.md Fragile system 5); the installed build's `main:App/ContentView.swift:57` is the only presenter |
| `ApplicationFieldsViewModel` | `ApplicationFieldsView.swift:15` (removed), `ProfileService+AccountStatus.swift:37` (comment), `CommunityOnboardingViewModel.swift:50, 59` (comments), **`:87` and `:98` (live code)** | the two live uses move with the statics before the removal |
| `ProfileService.submitApplication` | `ApplicationFieldsViewModel.swift:114` | dead caller; the only conformer of `ProfileServiceProtocol` is `ProfileService` (no test double conforms) |

**What this does to `heard_about` / `join_reason` (scope (b)).** After this task no client code writes either column to `profiles`: `submitApplication` (`ProfileService+AccountStatus.swift:38-49`, a direct `UPDATE` of `heard_about`, `join_reason`, `application_complete`, `application_submitted_at`) was the only writer, and sign-up never sends them (`AuthService.swift:254-259` passes `p_user_id`, `p_email`, `p_name`, `p_car` to `create_signup_profile`, called at `:276`; `git log -S p_heard_about -- 'NaarsCars/*.swift'` finds only `[P2-T1]` in `CommunityService`, so no build ever sent them to `create_signup_profile`). Answers go only to `community_members` through `redeem_community_invite` / `request_to_join_community` (`CommunityService.swift:85-109, 336-353`), which Phase 2 already reads (`PendingMembersView.swift:250-251`, `CommunityMemberDetailView.swift:143-144`). `Profile.heardAbout` / `joinReason` (`Core/Models/Profile.swift:29-30, 85-86, 182-183`) stay decodable (the columns stay) and have no reader after Task 2. The server still copies a default-community applicant's answers into `profiles` for the installed admin screen (`redeem_community_invite` and `request_to_join_community`, live md5 `f18e6af6…` / `da89c233…`); removing that copy changes what the installed build shows, so it is SQL File B blocks 2-3 (gated).

- [ ] **Step 0: Inventory.** `grep -rn --include='*.swift' -e ApplicationFields -e submitApplication -e applePlaceholderName -e nameProblem NaarsCars` lists only the lines in the table and the definitions. Anything else: stop.
- [ ] **Step 1: Write the failing test** in `CommunityOnboardingViewModelTests`:

```swift
func testNameProblem_RejectsPlaceholderEmptyAndShortNames() {
    // Same rules and messages as the sign-up form's name field (moved from ApplicationFieldsViewModel).
    XCTAssertEqual(CommunityOnboardingViewModel.nameProblem(""), "signup_error_name_required".localized)
    XCTAssertEqual(CommunityOnboardingViewModel.nameProblem(CommunityOnboardingViewModel.applePlaceholderName),
                   "signup_error_name_required".localized)
    XCTAssertEqual(CommunityOnboardingViewModel.nameProblem("A"), "signup_error_name_too_short".localized)
    XCTAssertEqual(CommunityOnboardingViewModel.nameProblem(String(repeating: "a", count: 101)),
                   "signup_error_name_too_long".localized)
    XCTAssertNil(CommunityOnboardingViewModel.nameProblem("Sam Neighbor"))
    XCTAssertEqual(CommunityOnboardingViewModel.applePlaceholderName, "Apple User")   // AuthService+AppleSignIn.swift:378
}
```
- [ ] **Step 2: RED.** `RED`. Expected: "type 'CommunityOnboardingViewModel' has no member 'nameProblem'".
- [ ] **Step 3: Move** the two statics into `CommunityOnboardingViewModel` (verbatim bodies), point `:87` / `:98` at them, update the two doc comments (`:50` "The read the name step makes…", `:59` "The name update the name step makes."). `BUILD` green with both copies present.
- [ ] **Step 4: Remove** the protocol requirement and `ProfileService.submitApplication`; then `XcodeRM` (`deleteFiles: true`) `ApplicationFieldsView.swift`, then `ApplicationFieldsViewModel.swift`.
- [ ] **Step 5: Verify.** `PBXCHECK ApplicationFieldsView.swift ApplicationFieldsViewModel.swift` prints nothing; `grep -rn '"heard_about": AnyCodable\|"join_reason": AnyCodable\|"application_complete": AnyCodable' NaarsCars --include='*.swift'` prints nothing.
- [ ] **Step 6: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityOnboardingViewModelTests -only-testing:NaarsCarsTests/AppLaunchManagerTests -only-testing:NaarsCarsTests/PendingApprovalViewModelTests -only-testing:NaarsCarsTests/JoinCommunityViewModelTests`. Expected: 1 new test passes; the rest unchanged.
- [ ] **Step 7: Commit** `[P5-T4] Remove the application form and the client's profile answer write` with the two removed paths, `CommunityOnboardingViewModel.swift`, `ProfileServiceProtocol.swift`, `ProfileService+AccountStatus.swift`, the test file, `project.pbxproj`.

Tests: 1 new. Captures: `CommunityOnboardingView` "name needed" preview in light, dark, AX5 at the gate (Task 10 Step 3), to show the name step is intact.

---

### Task 5: Delete the dead Rides and Favors dashboards

**Model:** opus, medium effort (four app files with duplicate "Recovered References" entries that carry the build file, and two test files) · **Files:**
- Remove (Xcode MCP, both references each): `NaarsCars/Features/Rides/Views/RidesDashboardView.swift`, `NaarsCars/Features/Rides/ViewModels/RidesDashboardViewModel.swift` (declares `RideFilter` `:13`), `NaarsCars/Features/Favors/Views/FavorsDashboardView.swift`, `NaarsCars/Features/Favors/ViewModels/FavorsDashboardViewModel.swift` (declares `FavorFilter` `:13`)
- Remove (Xcode MCP, test target; the `Rides` and `Favors` test groups keep their other files): `NaarsCars/NaarsCarsTests/Features/Rides/RidesDashboardViewModelTests.swift` (2 tests: `testLoadRides_Success` `:20`, `testFilterRides_MineOnly` `:34`), `NaarsCars/NaarsCarsTests/Features/Favors/FavorsDashboardViewModelTests.swift` (1 test, `testLoadFavors_Success` `:20`)
- Modify (by the MCP): `project.pbxproj`

**Caller inventory at plan time:** `RidesDashboardViewModel` is referenced by `RidesDashboardView.swift:14` and its test (`:13, 17`); `FavorsDashboardViewModel` by `FavorsDashboardView.swift:14` and its test (`:13, 17`); neither view has a presenter; `RideFilter` and `FavorFilter` have no reference outside these files (CLAUDE.md Audit Notes item 5: "only referenced by previews/tests"). In `project.pbxproj` the build files of three of the four hang off the "Recovered References" reference (`RidesDashboardView.swift` `:69` → `:1090`, `RidesDashboardViewModel.swift` `:15` → `:1124`, `FavorsDashboardView.swift` `:78` → `:570`), while `FavorsDashboardViewModel.swift`'s hangs off the normal group reference (`:203` → `:751`; its "Recovered References" entry `:668` carries none). The table in Global Constraints has every line. Either way both entries go, so the order of removal does not depend on it.

- [ ] **Step 0: Inventory.** `grep -rn --include='*.swift' -e RidesDashboard -e FavorsDashboard -e 'RideFilter\b' -e 'FavorFilter\b' NaarsCars` lists only the six files. `XcodeLS` the "Recovered References" group and the four normal groups; write down the eight navigator paths and the two test-group paths (the "Recovered References" names exactly as Task 1 Step 1 recorded them).
- [ ] **Step 1: Remove** each app file's "Recovered References" entry (`deleteFiles: false` through the MCP when Task 1's probe showed it works; otherwise the owner fallback, Remove Reference), then its group entry (`deleteFiles: true`); then the two test files (`deleteFiles: true`). After the four "Recovered References" removals, `ls` the four app files: they still exist until their group entries go.
- [ ] **Step 2: Verify.** `PBXCHECK RidesDashboardView.swift RidesDashboardViewModel.swift FavorsDashboardView.swift FavorsDashboardViewModel.swift RidesDashboardViewModelTests.swift FavorsDashboardViewModelTests.swift` prints nothing; the "Recovered References" group still exists.
- [ ] **Step 3: GREEN.** `BUILD`; `RELEASE`; `FULL`. Expected: `FULL` executed = the Phase 4 gate's count + 1 (Task 4) − 3.
- [ ] **Step 4: Commit** `[P5-T5] Remove the unused Rides and Favors dashboards and their tests` with the six removed paths and `project.pbxproj`.

Tests: 3 removed. Captures: none.

---

### Task 6: Ride-cost place lookup through the definer RPCs

**Model:** opus, high effort (two new Supabase RPC call sites; replaces every client access to `geocoding_cache`, which SQL File D later closes) · **Files:**
- Modify: `NaarsCars/Core/Utilities/GeocodingCacheService.swift` — `:18-52` (`GeocodingCacheRow`, `GeocodingCacheUpsert`, `PlacemarkData` removed; two private params structs added), `:73-78` (the upsert call loses the placemark), `:83-102` (`cleanupGeocodingCache`, removed: no caller anywhere, and with no DELETE policy on the table its delete matches nothing), `:106-137` (`fetchCachedMultiplier` → the lookup RPC), `:139-169` (`upsertGeocodingCache(coordinate:locationKey:multiplier:)` → the write RPC; the `placemark` parameter goes), `:173-207` (`ensureGeocodingCacheAvailable` and `isMissingGeocodingCacheTable` replaced by `isMissingGeocodingFunction(_:)`), `:342-364` (`placemarkPayload`, `isoTimestamp`, removed; no other caller: `grep -rn isoTimestamp` finds only `:88, :110, :360`)
- Modify: `NaarsCars/Core/Utilities/RideCostEstimator.swift:29-36` (`geocodingCacheTable`, `geocodingCacheTtlHours`, `geocodingCacheCleanupDays` removed; `geocodingCacheAvailable` stays and now means "the lookup functions exist")
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Utilities/GeocodingCacheServiceTests.swift`
- Reference: SQL plan File A blocks 1-2

**What the client does today** (`GeocodingCacheService.swift`): on a zone miss (`RideCostEstimator.swift:335-353`; a zone multiplier above 1.0 skips the lookup), it probes the table (`select id limit 1`, `:173-198`), reads `multiplier` where `location_key = key and created_at >= now − 24 h` (`:106-137`), and on a miss reverse-geocodes on the device and upserts the row **with the full placemark** (street name, number, locality, postal code, areas of interest; `:139-169`, `:342-358`). Live table (2026-10-19): 7 rows, newest 2026-09-15; policies SELECT / INSERT / UPDATE for `authenticated` under `is_active_user`; table grants to `anon` and `authenticated` include every privilege. A PostgREST upsert never updates `created_at`, so a refreshed key stopped hitting after its first 24 hours; the RPC keys freshness on `updated_at` (SQL File A, D-7).

**Interfaces:**

```swift
private struct GeocodingLookupParams: Encodable { let locationKey: String          // p_location_key
    nonisolated func encode(to encoder: Encoder) throws }
private struct GeocodingWriteParams: Encodable { let locationKey: String; let latitude: Double
    let longitude: Double; let multiplier: Double                                       // p_location_key, p_latitude, p_longitude, p_multiplier
    nonisolated func encode(to encoder: Encoder) throws }
static func fetchCachedMultiplier(locationKey: String) async -> Double?
    // rpc("get_geocoding_multiplier", params:) → JSONDecoder().decode(Double?.self, from: response.data); JSON null → nil
static func upsertGeocodingCache(coordinate: CLLocationCoordinate2D, locationKey: String, multiplier: Double) async
    // rpc("put_geocoding_multiplier", params:); a false answer is logged at info level and ignored
static func isMissingGeocodingFunction(_ error: Error) -> Bool
    // PostgrestError code "PGRST202" (PostgREST: function not found) or "42883"
```

Both calls `guard geocodingCacheAvailable != false`; a missing-function error sets it to `false` for the session; any other error logs a warning and leaves it unchanged. `getReverseGeocodedMultiplier(coordinate:)` (`:57-81`) keeps its flow (lookup, else geocode on the device, compute, write). The multiplier rules (`:241-288`) and the cache key (`:211-217`, 3 decimals, `en_US_POSIX`) do not change.

- [ ] **Step 1: Write the failing tests** (`GeocodingCacheServiceTests`, `CommunityServiceURLProtocol` reused; `setUp` and `tearDown` also set `RideCostEstimator.geocodingCacheAvailable = nil`):

```swift
func testFetchCachedMultiplier_CallsLookupRPCWithTheKeyOnly()   // POST /rest/v1/rpc/get_geocoding_multiplier; body keys == ["p_location_key"]; answer "1.2" → 1.2
func testFetchCachedMultiplier_NullAnswerIsAMiss()              // answer "null" → nil
func testFetchCachedMultiplier_NeverTouchesTheTable()           // no recorded path contains "/rest/v1/geocoding_cache"
func testUpsert_SendsKeyCoordinatesAndMultiplierOnly()          // POST /rest/v1/rpc/put_geocoding_multiplier;
                                                                // keys == ["p_location_key","p_latitude","p_longitude","p_multiplier"]; no "placemark_data"
func testMissingFunction_DisablesLookupForTheSession()          // 404 {"code":"PGRST202",…} → nil; a second fetch records no request
func testServerError_DoesNotDisableLookup()                      // 500 → nil; a second fetch records a request
```
- [ ] **Step 2: RED.** `RED` after creating the test file through the Xcode MCP (`XcodeLS NaarsCars/NaarsCarsTests/Core/Utilities`, then `XcodeWrite`). Expected: "cannot find 'isMissingGeocodingFunction' in scope" (or the upsert's extra-argument error).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Self-check** (write into the task report): the two params structs' keys match File A's signatures; `grep -n 'geocoding_cache\|geocodingCacheTable\|placemark' NaarsCars/Core/Utilities/*.swift` prints nothing outside comments; the `RideCostEstimatorTests` class (declared in `NaarsCarsTests/Core/Services/MessageServiceTests.swift:258`, ending before `AnyCodableEncodingTests` at `:380`) is untouched.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/GeocodingCacheServiceTests -only-testing:NaarsCarsTests/RideCostEstimatorTests`. Expected: 6 new tests pass; `RideCostEstimatorTests` unchanged.
- [ ] **Step 6: Commit** `[P5-T6] Look up ride-cost place multipliers through the definer RPCs` with `GeocodingCacheService.swift`, `RideCostEstimator.swift`, the test file, `project.pbxproj`.

Tests: 6 new. Live check: Task 10 O6.

---

### Task 7: Signed storage URLs for images

**Model:** opus, high effort (the messaging media path: every image bubble, the viewer and the media gallery; `AuthService` sign-out teardown; CLAUDE.md lists both as fragile) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Core/Protocols/StorageURLResolving.swift`, `NaarsCars/Core/Services/StorageURLSigner.swift`
- Modify: `NaarsCars/Core/Services/PersistentImageService.swift:13-67` (an injectable resolver; resolve after a disk-cache miss, download from the resolved URL, cache under the stored name)
- Modify: `NaarsCars/Core/Services/AuthService.swift:656-680` (`clearPerAccountLocalState`: `await StorageURLSigner.shared.reset()` after `PendingInviteStore().clear()`)
- Modify: `NaarsCars/Core/Utilities/Constants.swift:214-219` (`Constants.Storage`: `signedURLLifetime: Int = 3600`, `signedURLRenewMargin: TimeInterval = 300`, `signedURLCacheMaxEntries = 500`)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Services/StorageURLSignerTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/PersistentImageServiceTests.swift`

**What is read today.** The uploads store `getPublicURL` output: `MessageMediaService.swift:61-66` (`message-images`, path `<conversationId>/<uuid>.jpg`), `ConversationService.swift:674-680` (`group-images`, `<conversationId>/avatar_<uuid>.jpg`), `CreatePostViewModel.swift:141-145` (`town-hall-images`, `<uuid>.jpg`), `ReviewService.swift:221-229` (`review-images`, `<UUID>.jpg` where the UUID is a fresh `UUID()` per upload, not the review id: `createReview` passes `reviewId: UUID()` at `:60` and `uploadReviewImage` names the file at `:196`; with a `?t=<timestamp>` cache-bust query and a fallback upload to `town-hall-images` at `:208-218`). Avatars (`ProfileService.swift:242-244`) stay public (spec D16 lists four buckets). Every display path reaches `PersistentImageService.getImage(for:)`: `CachedAsyncImage` (used by `ReviewCard.swift:70`, `GroupAvatarComposite.swift:98`, `AvatarView.swift:65`, `MessageDetailsPopup.swift:111`, `ConversationAvatar.swift:43`, `TownHallPostCard.swift:262`, `ConversationMediaGalleryView.swift:199`), `PersistentAsyncImage` (`PersistentImageService.swift:104-115`), `ImageBubbleView.swift:106`, `AvatarUIView.swift:97`, `ImageViewerView.swift:130`. No other code downloads an image (`grep -rn 'AsyncImage(\|URLSession.shared.data' --include='*.swift'` finds only `PersistentImageService.swift:53` and the audio paths of Task 8). Live data (2026-10-19): 13 messages with an image, 4 group photos, 1 Town Hall post with an image, **0 reviews with an image** (`select count(*) from reviews where image_url is not null` = 0; the 5 objects in `review-images` are orphans that no review row names, consistent with the fresh-UUID naming above); every stored URL has the `/storage/v1/object/public/<bucket>/` form on the project's host. Review-image signing is therefore exercised live only by a review the gate writes (Task 10 O5).

**Interfaces** (`StorageURLResolving.swift`):

```swift
/// Signs one storage object. The production conformer calls supabase-swift's createSignedURL.
protocol StorageObjectSigning: Sendable {
    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL
}
/// Turns a stored URL into the URL to download from. Never fails: a URL it does not sign, or cannot sign, comes back unchanged.
protocol StorageURLResolving: AnyObject, Sendable {
    func resolvedURL(for storedURL: URL) async -> URL
    func reset() async
}
/// A stored public URL of this project, split into bucket and object path. Query and fragment are ignored.
struct StoredObjectReference: Hashable, Sendable {
    let bucket: String; let path: String
    /// Nil unless host == expectedHost and the path is /storage/v1/object/public/<bucket>/<path…> with a non-empty path.
    static func parse(_ url: URL, expectedHost: String) -> StoredObjectReference?
}
```

`StorageURLSigner.swift`:

```swift
actor StorageURLSigner: StorageURLResolving {
    static let shared = StorageURLSigner()
    /// The buckets 5b makes private. "audio-messages" joins only through Task 8 (D-1). Avatars are never signed.
    static let signedBuckets: Set<String> = ["message-images", "group-images", "town-hall-images", "review-images"]
    init(signer: any StorageObjectSigning = SupabaseStorageSigner(),
         expectedHost: String? = nil,                  // nil = the SupabaseClient's supabaseURL host, read once on the main actor
         now: @escaping @Sendable () -> Date = Date.init,
         lifetime: Int = Constants.Storage.signedURLLifetime,
         renewMargin: TimeInterval = Constants.Storage.signedURLRenewMargin,
         maxEntries: Int = Constants.Storage.signedURLCacheMaxEntries)
    func resolvedURL(for storedURL: URL) async -> URL
        // not a signed bucket → storedURL; cached and now < expiry − renewMargin → cached URL;
        // a sign already in flight for this reference → await it; else sign, cache, return;
        // a thrown error → storedURL, nothing cached (Review Focus 3)
    func reset()
}
struct SupabaseStorageSigner: StorageObjectSigning {
    // await MainActor.run { SupabaseService.shared.client }.storage.from(bucket).createSignedURL(path:, expiresIn:)
}
extension URLSession {
    /// The only session that downloads a stored object of a signed bucket. Ephemeral, urlCache = nil,
    /// requestCachePolicy = .reloadIgnoringLocalCacheData: a signed URL (and its token) never reaches URLCache's disk store.
    static let signedStorageDownload: URLSession = makeSignedStorageDownloadSession()
    /// protocolClasses is for tests only (a custom session does not reliably pick up URLProtocol.registerClass).
    static func makeSignedStorageDownloadSession(protocolClasses: [AnyClass]? = nil) -> URLSession
}
```

Failure logging in `StorageURLSigner` / `SupabaseStorageSigner`: `AppLogger.warning("images", "Signing failed for \(bucket): \(ns.domain) \(ns.code)")` with `let ns = error as NSError`; never the URL, the path or `\(error)`.

Cache bound: at most `maxEntries`; on insert past the bound the entry with the earliest expiry goes. `PersistentImageService` gains `var urlResolver: any StorageURLResolving = StorageURLSigner.shared` and `var downloadSession: URLSession = .signedStorageDownload` (both internal, for tests); `getImage(for:)` keeps `fileName = url.lastPathComponent` from the **stored** URL (`:37-38`), checks the disk first, and only on a miss does `let downloadURL = await urlResolver.resolvedURL(for: url)` before `downloadSession.data(from: downloadURL)` (replacing `URLSession.shared.data(from: url)` at `:53`; every download, avatars included, uses this session, since the disk cache already keeps the bytes and avatars never relied on `URLCache`). Nothing logs `downloadURL`; the existing failure log (`:63`, `"Failed to download image: \(error)"`, which would print the signed URL through the `URLError`'s failing-URL key) becomes `"Failed to download image: \(ns.domain) \(ns.code)"` with `let ns = error as NSError`. The upload functions are not changed: they still return the public URL, which is still what the database and SwiftData store (D-2).

- [ ] **Step 1: Write the failing tests.** `StorageURLSignerTests` (a `StubStorageObjectSigning` actor that counts calls, can throw, and can be gated; `now` from a test clock; `expectedHost: "example.supabase.co"`):

```swift
func testParse_MessageImage()                         // …/object/public/message-images/C0/A1.jpg → ("message-images", "C0/A1.jpg")
func testParse_ReviewURLDropsTheCacheBustQuery()      // …/object/public/review-images/R1.jpg?t=17 → path "R1.jpg"
func testParse_ForeignHostAndSignPathAreNotParsed()   // other host → nil; /object/sign/… → nil; empty path → nil
func testResolve_AvatarsPassThroughUnsigned()         // avatars bucket → same URL, 0 signer calls
func testResolve_ReturnsSignedURLWithoutChangingTheStoredValue() // returns the signer's URL; the input URL value is unchanged
func testResolve_SignsOncePerPathWithinTheLifetime()  // two calls, clock +10 min → 1 signer call
func testResolve_RenewsInsideTheRenewMargin()         // clock + lifetime − margin + 1 s → 2 signer calls
func testResolve_ConcurrentCallsForOnePathShareOneRequest() // 20 concurrent resolves on a gated signer → 1 call
func testResolve_SignerFailureFallsBackToStoredURLAndRetriesNextTime() // throw → stored URL; next call → signer called again
func testResolve_CacheIsBounded()                     // maxEntries 2, three paths → the earliest expiry is signed again
func testReset_ForgetsEverySignedURL()                // reset → next resolve signs again
func testSupabaseStorageSigner_PostsToTheSignRoute()  // CommunityServiceURLProtocol: POST /storage/v1/object/sign/message-images/C0/A1.jpg,
                                                      // body expiresIn == 3600; answer {"signedURL":"/object/sign/message-images/C0/A1.jpg?token=t"}
                                                      // → a URL whose query contains token=t
func testSignedStorageDownloadSession_HasNoURLCache()  // URLSession.signedStorageDownload.configuration: urlCache == nil,
                                                      // requestCachePolicy == .reloadIgnoringLocalCacheData
```

`PersistentImageServiceTests` (a `StubStorageURLResolver` that returns `<stored>?token=t` and counts calls; `downloadSession = URLSession.makeSignedStorageDownloadSession(protocolClasses: [CommunityServiceURLProtocol.self])`, whose handler answers a 1×1 PNG; `setUp` and `tearDown` call `clearCache()` and restore `urlResolver = StorageURLSigner.shared` and `downloadSession = .signedStorageDownload`):

```swift
func testGetImage_DownloadsFromTheResolvedURL()                  // the recorded request's query has token=t
func testGetImage_CachesUnderTheStoredNameNotTheSignedOne()      // the disk write is a detached task (PersistentImageService.swift:56-59), so poll
                                                                 // the cache directory (Caches/PersistentImageCache, :21-22) every 20 ms for up to 2 s
                                                                 // until "A1.jpg" appears (fail on timeout); then no file name contains "token"
func testGetImage_DiskHitDoesNotResolve()                         // second call (after the same poll): resolver count stays 1, no new request
func testGetImage_ResolvedDownloadLeavesNoURLCacheEntry()        // after a download: URLCache.shared.cachedResponse(for: URLRequest(url: <signed URL>)) == nil
                                                                 // and service.downloadSession.configuration.urlCache == nil (the stub itself answers
                                                                 // with .notAllowed, so the configuration assertion is the one that bites)
```
- [ ] **Step 2: RED.** `RED` after creating both test files through the Xcode MCP. Expected: "cannot find type 'StorageObjectSigning' in scope".
- [ ] **Step 3: Implement** the two app files through the Xcode MCP (`XcodeLS NaarsCars/Core/Protocols`, `NaarsCars/Core/Services`; confirm the app target), `PersistentImageService`, the `Constants` values, the sign-out line.
- [ ] **Step 4: Self-check** (write into the task report): no `print`, `AppLogger` or `MessagingLogger` call receives a resolved URL (`grep -rn 'downloadURL\|resolvedURL' NaarsCars --include='*.swift'` and read each hit); no log line on these paths interpolates an error (`grep -nE '\\\(error(\.localizedDescription|\.description)?\)' NaarsCars/Core/Services/PersistentImageService.swift NaarsCars/Core/Services/StorageURLSigner.swift NaarsCars/Core/Protocols/StorageURLResolving.swift` prints nothing); `grep -n 'URLSession.shared' NaarsCars/Core/Services/PersistentImageService.swift NaarsCars/Core/Services/StorageURLSigner.swift` prints nothing; `MessageMediaService`, `ConversationService`, `CreatePostViewModel`, `ReviewService`, `SDModels.swift`, `MessagingMapper.swift` are unchanged (`git diff --stat`); the actor holds no reference to a ViewModel or view; `clearPerAccountLocalState` still clears every store it cleared before.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/StorageURLSignerTests -only-testing:NaarsCarsTests/PersistentImageServiceTests -only-testing:NaarsCarsTests/AppLaunchManagerTests`; `RELEASE`; `FULL`. Expected: 17 new tests pass (13 + 4); `FULL` executed = Task 5's count + 6 + 17.
- [ ] **Step 6: Commit** `[P5-T7] Read message, group, Town Hall and review images through signed storage URLs` with the four new files, `PersistentImageService.swift`, `AuthService.swift`, `Constants.swift`, `project.pbxproj`.

Tests: 17 new. Live check: Task 10 O2-O5. Captures: the Lane B screenshots of the thread with an image (light, dark, AX5) in Task 10 O2 (`ImageBubbleView` has no preview).

---

### Task 8: Signed URLs for voice notes (only if the owner accepts D-1)

**Model:** opus, high effort (touches `MessagingSyncEngine`, a fragile high-risk file, in its private prefetch helper, and the audio player) · **Files:**
- Modify: `NaarsCars/Core/Services/StorageURLSigner.swift` (`signedBuckets` gains `"audio-messages"`)
- Modify: `NaarsCars/UI/Components/Messaging/MessageAudioPlayer.swift` — gains `var urlResolver: any StorageURLResolving = StorageURLSigner.shared` and `var downloadSession: URLSession = .signedStorageDownload` (internal, for tests; the class is a `@MainActor` singleton with a private `init`, `:12-14`, `:31`, so tests set and restore them on `.shared`); `resolvePlayableUrl(for:)` (`:113-137`): the in-memory `cachedFiles` map and the temp file stay keyed by the **stored** URL (`cachedFiles[url]`, `"audio-\(abs(url.absoluteString.hashValue)).m4a"`, `:118-131`), and only the download at `:127` changes, to `downloadSession.data(from: await urlResolver.resolvedURL(for: url))`; the function becomes `internal` for the test; new `func prefetch(_ storedURL: URL) async` = `_ = try? await resolvePlayableUrl(for: storedURL)` (fills the player's own temp-file cache). The player logs nothing today (`play(url:)` swallows the error, `:71-73`); it stays that way.
- Modify: `NaarsCars/Core/Storage/MessagingSyncEngine.swift:508-511` (`precacheMedia(url:)`, called only at `:177-179` on an inserted message with an `audioUrl`): `URLSession.shared.dataTask(with: mediaURL).resume()` (a warm-up of `URLCache.shared`, which would now store the signed URL on disk) becomes `Task { await MessageAudioPlayer.shared.prefetch(mediaURL) }`. The first tap then plays from the temp file the prefetch wrote, so the warm-up keeps its purpose without `URLCache`. The resolver reaches the prefetch through the player's injectable `urlResolver`; the engine gains no stored property.
- Modify (test target): `StorageURLSignerTests.swift` (one test); create `NaarsCars/NaarsCarsTests/Features/Messaging/MessageAudioPlayerTests.swift` through the Xcode MCP (`XcodeLS NaarsCars/NaarsCarsTests/Features/Messaging` first; the group exists)

Invariant preserved: the realtime receive path (`MessagingSyncEngine` handler → repository upsert → `.conversationUpdated`) is unchanged; the prefetch stays fire-and-forget, as today: the `Task` is created after the upsert and before the `.conversationUpdated` post and suspends on the network, so the handler does not wait for it. A tap while the prefetch is still downloading downloads once more (as a tap during today's URLCache warm-up did); both write the same temp file atomically (`:129`). The engine now names `MessageAudioPlayer.shared` (a `@MainActor` singleton in `UI/Components/Messaging/`, the same app module; the engine is `@MainActor` too); that is one narrow call in a private helper, recorded in the report as a known Core-to-UI reference (Architecture rule 6), not a new service dependency. If the owner prefers, a one-method protocol in `Core/Protocols/` (`VoiceNotePrefetching`) can front it; the plan does not add it. Stored `messages.audio_url` and `SDMessage.audioUrl` are unchanged.

- [ ] **Step 0:** Confirm the owner's yes to D-1 in the orchestrator's brief. Without it, mark the task skipped and stop.
- [ ] **Step 1: Write the failing tests.** `testResolve_AudioMessagesAreSigned` (signer called for `audio-messages`); `MessageAudioPlayerTests.testResolvePlayableURL_DownloadsSignedAndCachesUnderTheStoredURL` (on `MessageAudioPlayer.shared`: `urlResolver` = the `StubStorageURLResolver` of Task 7, `downloadSession = URLSession.makeSignedStorageDownloadSession(protocolClasses: [CommunityServiceURLProtocol.self])`, the handler answers a few bytes; the recorded request's query has `token=t`; the returned file name does not contain `token`; a second call for the same stored URL makes no request; `URLCache.shared.cachedResponse(for: URLRequest(url: <signed URL>))` is nil; `tearDown` restores both properties).
- [ ] **Step 2: RED.** Expected: compile errors first ("value of type 'MessageAudioPlayer' has no member 'urlResolver'"); once the properties exist, the signer test fails (0 signer calls).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/StorageURLSignerTests -only-testing:NaarsCarsTests/MessageAudioPlayerTests -only-testing:NaarsCarsTests/MessagingSyncEngineTests` (that class lives in `NaarsCarsTests/Core/Services/MessageServiceTests.swift`). Expected: 2 new tests pass.
- [ ] **Step 5: Commit** `[P5-T8] Play voice notes through signed storage URLs`.

Tests: 2 new. Live check: Task 10 O2 (a voice note, if recording is possible on the simulator; otherwise an existing one).

---

### Task 9: Documentation for Phase 5a and the 5b gate

**Model:** sonnet · **Files:**
- Modify: `CLAUDE.md` — Current State (a Phase 5a paragraph: what was removed, the signed-URL read path, the geocoding RPCs, what was verified; one paragraph on 5b: the four files, NOT APPLIED, the gate in A5 point 2 and the stricter condition for Files D and E); Audit Notes: delete item 5 ("Dead files awaiting manual deletion", `CLAUDE.md:960`) and the dead-file sentence of the Phase 2 documentation-pass paragraph (`:858`), record the follow-ups; Fragile system 5 (drop "`ApplicationFieldsView` is unreferenced"; `CommunityOnboardingViewModel` owns the Apple-placeholder name rule); State Management rule 2 (recount `ObservableObject` screen ViewModels with `grep -rln 'ObservableObject' NaarsCars/Features --include='*ViewModel.swift'` and the in-view view models that went: `PendingUserDetailViewModel`, `AdminInviteViewModel`; replace "36 … (34 once …)" with the new number); the database contract (`invite_codes` note `:928`: the client no longer reads or writes it, File C drops it; `geocoding_cache` is read and written only through `get_geocoding_multiplier` / `put_geocoding_multiplier` by this client, direct access closes in File D; the answer copy into `profiles` stays only for the installed build until File B); Canonical Entry Points (a row: "Show a stored image of a signed bucket" → `PersistentImageService.getImage(for:)` / `CachedAsyncImage`, which sign through `StorageURLSigner`; "Do not": persist or log a signed URL, store anything but the upload's returned URL); Sign-out row (`StorageURLSigner.reset()`); File conventions (`StorageURLResolving`, `StorageURLSigner`, `SupabaseStorageSigner`); Testing Expectations (Storage row: signed-URL cache and fallback).
- Modify: `AGENTS.md:69` (the dead-file line goes; one line each for the signed-URL rule and the geocoding RPCs).
- Modify: `SECURITY.md` §2.11 (`invite_codes`: no client access since 5a; dropped by File C at the gate), §2.24 (`geocoding_cache`: the table today reads `is_active_user` in all three policies, not `true` as the section says; clients read and write only through the two definer functions, which require an active account, validate the key, the coordinates and the multiplier range, and return or store only the multiplier; no placemark data is written; File D revokes direct access), a new §2.28 "Storage buckets" (today: six public buckets and their policies as read on 2026-10-19; 5a: the client reads four of them through signed URLs with a 1-hour lifetime and an in-memory cache, avatars stay public; 5b File E: the four buckets private, who can read each object, owners read their own uploads), §6 (legacy codes retired; community invites are the only codes).
- Modify: `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` — nothing (A5 already records the split); `Legal/*` — nothing in 5a (`Legal/PRIVACY_POLICY.md:129-131` already says images may be reachable by URL; tightening it after File E is an owner follow-up, recorded in the gate report).
- String keys left in the catalog (unused after Tasks 1-5; recorded in CLAUDE.md Audit Notes as an owner-approved cleanup): `admin_account_created_label admin_all_approved admin_application_info admin_approve admin_approve_confirmation admin_approve_failed admin_approve_user admin_generate_invite_code admin_invite_bulk admin_invite_bulk_code admin_invite_bulk_code_desc admin_invite_bulk_desc admin_invite_bulk_failed admin_invite_codes admin_invite_copy admin_invite_create_code admin_invite_expires_at admin_invite_generate_bulk admin_invite_generated_code admin_invite_not_signed_in admin_invite_regular admin_invite_regular_desc admin_invite_share admin_loading_pending admin_no_pending_users admin_not_provided admin_reject admin_reject_confirmation admin_reject_failed admin_reject_user admin_submitted_at_label admin_user_details application_error_fields_required application_error_not_signed_in application_error_submit_failed application_helper_text application_nav_title application_submit_button application_subtitle application_title common_copy common_list common_map favors_dashboard_title favors_empty_all favors_empty_claimed favors_empty_mine favors_empty_title invite_code_generated invite_copied invite_copy invite_create invite_created_ago invite_generate_code invite_generate_failed invite_share invite_share_prompt invite_statement_required invite_statement_too_long invite_status_available invite_status_used invite_tell_us invite_who_and_why invite_your_code rides_dashboard_title rides_empty_all rides_empty_claimed rides_empty_mine rides_empty_title signup_continue_with_email signup_invite_code_placeholder signup_invite_subtitle signup_method_subtitle signup_next_button signup_or_divider` (75; computed by listing every `"…".localized` literal in the removed files and keeping those no remaining Swift file names; re-run before writing, since Phase 4 may reuse one).

- [ ] **Step 1: Edit** each section with the Phase 5a facts (replace, do not append history).
- [ ] **Step 2: Verify** `grep -n "awaiting deletion\|awaiting manual deletion\|ApplicationFieldsView\|PendingUsersView\|MessagingDebugView\|RidesDashboard" CLAUDE.md AGENTS.md` prints nothing stale; `grep -n "geocoding_cache" CLAUDE.md SECURITY.md AGENTS.md` names the RPCs.
- [ ] **Step 3: Commit** `[P5-T9] Document Phase 5a and the gated 5b set`.

---

### Task 10: Phase 5a gate

**Model:** opus · **Files:** a new `Docs/qa/2026-10-19-multi-community-phase5a-gate.md` (report only; no code). Uses `build/`.

**Steps the agent runs without the owner:**

- [ ] **Step 1: Preconditions** (Supabase MCP, read only). File A is live: `get_geocoding_multiplier(text)` and `put_geocoding_multiplier(text, numeric, numeric, numeric)` exist, SECURITY DEFINER, `search_path=""`, EXECUTE held by `authenticated` and not `anon` (`has_function_privilege`), `md5(prosrc)` equal to the deployed values in `20261019_0050`'s header. **5b is not applied**, recorded with the query result: the triggers `legacy_application_to_membership` and `a_sync_legacy_approval_to_membership` exist; `to_regclass('public.invite_codes')` is not null; `has_function_privilege('authenticated', 'public.admin_reject_pending_user(uuid)', 'execute')` is true; `has_table_privilege('authenticated', 'public.geocoding_cache', 'select')` is true; `select id, public from storage.buckets` shows all six public; `md5(prosrc)` of `fill_request_community`, `redeem_community_invite`, `request_to_join_community`, `protect_admin_fields`, `delete_user_account` equal the "live" column of the SQL plan's preconditions table. Files B-E headers read NOT APPLIED with their dry-run outcomes (Task 11).
- [ ] **Step 2: Full unit suite, signed out**, `-resultBundlePath build/P5-gate.xcresult`. Expected: exit 0, 0 failures, skips limited to the session-gated classes; executed = the Phase 4 gate's count + 24 (Tasks 4, 6, 7: 1 + 6 + 17) − 3 (Task 5), + 2 with Task 8; no new skip.
- [ ] **Step 2b: Static checks.** `RELEASE` (`<n>` = `gate`). `PBXCHECK` over all 21 removed basenames (Tasks 1-5: 7 + 3 + 3 + 2 + 6) prints nothing. `git grep -n -e '"invite_codes"' -e 'geocoding_cache"' -e admin_reject_pending_user -e '"heard_about": AnyCodable' -- 'NaarsCars/*.swift'` prints nothing. `git grep -n 'URLSession.shared' -- NaarsCars/Core/Services/PersistentImageService.swift NaarsCars/UI/Components/Messaging/MessageAudioPlayer.swift NaarsCars/Core/Storage/MessagingSyncEngine.swift` prints nothing when Task 8 ran (only `PersistentImageService.swift` is checked when it did not). `git grep -n getPublicURL -- 'NaarsCars/*.swift'` lists only the five upload functions (`MessageMediaService.swift`, `ConversationService.swift`, `ProfileService.swift`, `CreatePostViewModel.swift`, `ReviewService.swift`). `git diff --stat <phase base>..HEAD -- NaarsCars/Core/Storage NaarsCars/Core/Services/RefreshCoordinator.swift NaarsCars/Features/Messaging/ViewModels/MessageSendManager.swift NaarsCars/Core/Services/MessageSendWorker.swift` lists nothing but `MessagingSyncEngine.swift` (Task 8 only).
- [ ] **Step 3: Previews (Lane A).** `RenderPreview` the `CommunityOnboardingView` previews ("name needed", "name on file") in light, dark, AX 5 (the name rule moved, Task 4). No other SwiftUI view changed.
- [ ] **Step 4: Write the report** with the PR Impact Summary: (1) the removed screens and services (none was reachable; the list with the caller inventories); (2) no client writes `profiles.heard_about` / `join_reason` / `application_complete` / `approved`, and none calls `admin_reject_pending_user`; (3) ride-cost place lookups go through two definer RPCs that return or store only the multiplier, the cache is fresh for 24 hours from its last write, and no placemark data is sent; (4) images of four buckets download through signed URLs, while what is stored is unchanged; (5) nothing in 5b is applied, with the Step 1 query as evidence. High-blast files touched: `AuthService` (dead methods removed, one sign-out line), `PersistentImageService` (every image), `AdminService` (legacy methods removed), `Constants`, `MessagingSyncEngine` (Task 8 only); for each, what would break if a consumer were missed. App Store checklist (spec §5): no permission, SDK, entitlement or privacy-manifest change; data handling: less place data stored (no placemarks), images requested with a token; account deletion, reporting, blocking and moderation untouched (the removed admin Reject was unreachable; Requests to join is the approval path); notification behaviour unchanged.

**Owner-present steps (two simulators driven by the orchestrator through the built-in panel, as in the Phase 3 gate: the owner's `iPhone 16` with their platform-admin account and a second simulator with throwaway accounts created through the app's own Sign Up; writes only with the owner's go-ahead; server checks through the Supabase MCP after each write):**

- [ ] **O1. Setup (writes).** "P5 Second" signs up, creates "P5 Live Check"; "P5 Third" signs up and joins with a code; the second account approves.
- [ ] **O2. A photo in a thread (writes).** P5 Second sends P5 Third a direct message with a photo (and a voice note if Task 8 ran and recording works). P5 Third sees the bubble, opens the viewer and the media gallery (this device has never cached the file, so the bytes really come through a signed URL; the sender's own bubble may come from its local attachment or disk cache and proves nothing). Checks: `select image_url like '%/storage/v1/object/public/message-images/%' and image_url not like '%token=%' from messages where id = <id>`; the storage API log (Supabase MCP `query_logs`, the storage service) shows `POST /object/sign/message-images/<conversation>/<file>` from both sessions; on both simulators the SwiftData store (`xcrun simctl get_app_container <device> com.NaarsCars data`, then `sqlite3 <…>/Library/Application\ Support/default.store "select count(*) from ZSDMESSAGE where ZIMAGEURL like '%token=%' or ZAUDIOURL like '%token=%'"`) answers 0, and `sqlite3 <…>/Library/Caches/com.NaarsCars/Cache.db "select count(*) from cfurl_cache_response where request_key like '%token=%'"` answers 0 (no signed URL in `URLCache`'s disk store; a missing `Cache.db` also passes). Lane B captures of the thread in light, dark and AX5.
- [ ] **O3. A group photo (writes).** P5 Second starts a group thread with P5 Third and the owner, sets a group photo; both other devices show it in the conversations list and the thread header. Sign log as in O2 for `group-images`.
- [ ] **O4. Town Hall photos (writes).** P5 Third posts in P5 Live Check with a photo; P5 Second sees it in the feed and the post. Then P5 Third signs out, continues as a guest, opens Seattle's Town Hall, and the existing post with a photo (1 live today) shows: signing works with the anon key. On P5 Second's simulator, `sqlite3 <…>/Library/Application\ Support/default.store "select count(*) from ZSDTOWNHALLPOST where ZIMAGEURL like '%token=%'"` answers 0 (`SDTownHallPost.imageUrl`, `Core/Storage/SDModels.swift:332`, stores the URL too).
- [ ] **O5. A review photo (writes, after O6).** No live review carries a photo (`select count(*) from reviews where image_url is not null` = 0 on 2026-10-19; the 5 objects in `review-images` are orphans), so the gate writes one. In O6's flow: P5 Third claims the ride P5 Second posted (post it for the earliest time the form allows, so it is past within minutes); once its time has passed, P5 Second marks it complete and, at the review prompt, writes a review of P5 Third **with a photo**. Then P5 Third (not the uploader; this device has never cached the file) opens their own profile's reviews, and the owner opens P5 Third's profile if their admin account can read it: the photo shows. Checks: `select image_url like '%/storage/v1/object/public/review-images/%' and image_url not like '%token=%' from reviews where id = <id>`; the sign log (`query_logs`, storage) shows `POST /object/sign/review-images/<UUID>.jpg` from P5 Third's session. The ride's estimate (O6's checks) is read before the claim.
- [ ] **O6. A ride cost estimate (writes; run before O5, whose review uses this ride).** P5 Second posts a ride in P5 Live Check between two addresses outside the premium zones (residential Kirkland or Renton addresses: `RideCostEstimator.swift:335-344` skips the lookup when a zone multiplier exceeds 1.0). Within a minute `rides.estimated_cost` is set; the API log shows `POST /rest/v1/rpc/get_geocoding_multiplier` (and `put_geocoding_multiplier` on a miss) and no request to `/rest/v1/geocoding_cache` from that session; `select location_key, multiplier, placemark_data is null, updated_at from geocoding_cache order by updated_at desc limit 2` shows the new keys with no placemark.
- [ ] **O7. Clean-up.** P5 Third deletes their account from Profile, then P5 Second (the community's only member, so it is archived; their storage objects are removed by `delete_user_account` STEP 4, `20261017_0004:428-458`); `select count(*) from storage.objects where owner_id in (<both ids>)` answers 0. Shut the second simulator down.
- [ ] **O8. 5b is not applied.** Repeat Step 1's 5b query after the matrix and paste it into the report under the heading "5b: NOT APPLIED".
- [ ] **O9. Shut down; push** (owner). The push carries Files B-E only with the owner's explicit yes (Global Constraints, public repository).

---

### Task 11: 5b — write the gated files and the probe additions, dry-run them, apply nothing

**Model:** opus · **Executor:** the orchestrator (writes under `supabase/`) · **Files:** `supabase/migrations/20261019_0060_retire_legacy_bridges.sql` (File B), `20261019_0061_drop_invite_codes.sql` (File C, SQL editor), `20261019_0062_geocoding_cache_direct_access_revoked.sql` (File D), `20261019_0063_private_image_buckets.sql` (File E, SQL editor), `supabase/dryruns/20261019_0060_retire_legacy_bridges.dryrun.sql`, `…0061_drop_invite_codes.dryrun.sql`, `…0062_geocoding_cache_direct_access_revoked.dryrun.sql`, `…0063_private_image_buckets.dryrun.sql`, `supabase/dryruns/20261019_phase5b_not_applied_check.sql` (outside `supabase/migrations`, never applied), `supabase/probes/communities_probe.sql` (the additions of the SQL plan's last section, which also hold the 5a block `geocoding_lookup` written when File A is applied).

- [ ] **Step 1:** Copy each fenced block of the SQL plan to its file, header first. Every 5b header reads **NOT APPLIED** and names the gate (A5 point 2; Files D and E add "and every build in use contains the Phase 5a client").
- [ ] **Step 2: Build the dry-run scripts.** Assemble one script per gated file under `supabase/dryruns/` exactly as the SQL plan's section "Dry-run scripts (5b)" says (order: PARAMETERS; HELPERS without the trailing `commit;`; `begin;`; the file's blocks without the file's own `begin;` / `commit;`; each probe block of that file's row in the SQL plan's dry-run table with its `begin;` / `rollback;` turned into `savepoint probe;` / `rollback to savepoint probe; release savepoint probe;`; the `DRYRUN … OK` select; `rollback;`), plus the read-only `supabase/dryruns/20261019_phase5b_not_applied_check.sql`. Run the SQL plan's structural check on each script; any mismatch: fix the script, never run it. **Never paste a migration file, or the probe file, into the SQL editor for a dry run**: the HELPERS `commit;` (`communities_probe.sql:363`) and each probe's own `rollback;` would end the outer transaction, and the rest would apply for real.
- [ ] **Step 3: Dry runs.** File B (probes `legacy_retired`, `legacy_bridges`, `broadcast_cap`, `privileged_columns`, `account_deletion`, `short`, the list in File B's header) and File D (`geocoding_revoked`, `geocoding_lookup`, `short`) through the MCP, each script verbatim in one `execute_sql` call. File C and File E contain statements the MCP declines (`delete from auth.users` inside `delete_user_account`, `DROP TABLE`, `DROP POLICY`, writes to `storage.*`): **owner step in the SQL editor**, the committed script pasted verbatim (nothing else in the editor tab). After **each** of the four runs, run the not-applied check (MCP `execute_sql`, read only) and confirm `all_unchanged = true`; if it is false, stop and tell the owner at once (the SQL plan's runbook says how to recover). Record each outcome in the file's header ("Dry run 2026-10-xx: DRYRUN … OK, PROBE … OK, rolled back; not-applied check true").
- [ ] **Step 4: Verify nothing changed.** Re-run Task 10 Step 1's 5b query; the answer is identical.
- [ ] **Step 5: Commit** `[P5-T11] Write the gated Phase 5b migrations, dry-run scripts and probes (NOT APPLIED)` with the four migration files, the five `supabase/dryruns/` files and the probe file. Do not push without the owner's yes.

---

### Task 12: 5b gate (not run in this workflow)

**Model:** opus · **Runs only when** the owner states, from App Store Connect (App Analytics → Metrics → by App Version, and TestFlight builds), that **no pre-community build remains in use** (A5 point 2) — and, for Files D and E, that **every build in use contains the Phase 5a client** (signed URLs and the geocoding RPCs). If the first community build to reach the App Store is the one that contains Phase 5a, the two conditions are the same; if an earlier community build shipped (or is in TestFlight use), Files D and E wait for it too: their effect on a build without signed URLs is that every message, group, Town Hall and review photo stops loading.

- [ ] **Step 1:** Record the owner's confirmation (date, the App Store Connect figures quoted) in `Docs/qa/<date>-multi-community-phase5b-gate.md`.
- [ ] **Step 2:** Re-run the SQL plan's preconditions (md5 table; the six counts of P5); stop on any difference.
- [ ] **Step 3: Apply in order, one block per call, `short` after each:** File B through the MCP (blocks 1-6; block 7 only if the owner keeps D-S3); File D through the MCP; **owner:** File C, then File E, in the SQL editor, each as one transaction. After each file: its probe block(s), `short`, `account_deletion`, `privileged_columns`; after all four: the full probe file (`broadcast_cap` takes its 42501 branch when block 7 is applied; `legacy_bridges` prints SKIPPED).
- [ ] **Step 4: Two-simulator check on the current build** (as Task 10 O1-O6, shortened): a photo in a thread, a group photo, a Town Hall photo (also as a guest), a review photo (a review written with a photo in this check, as in Task 10 O5; no live review has one), a ride estimate, and a direct `curl -s -o /dev/null -w '%{http_code}' <a stored public image URL>` answering 400 (the public route no longer serves the private bucket); an avatar still loads publicly. Account deletion of a throwaway account succeeds (App Store 5.1.1(v)).
- [ ] **Step 5:** Headers read APPLIED with dates, migration-history versions, deployed md5 values and probe outcomes; CLAUDE.md Current State and SECURITY.md §2.11, §2.24, §2.28 move from "gated" to "applied"; the privacy policy's §7 can be tightened (owner). Commit; push with the owner's yes.

---

## New files

| Path (Xcode navigator path) | Target | Task | How |
|---|---|---|---|
| `NaarsCars/NaarsCarsTests/Core/Utilities/GeocodingCacheServiceTests.swift` | NaarsCarsTests | 6 | Xcode MCP |
| `NaarsCars/Core/Protocols/StorageURLResolving.swift` | NaarsCars | 7 | Xcode MCP |
| `NaarsCars/Core/Services/StorageURLSigner.swift` | NaarsCars | 7 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Core/Services/StorageURLSignerTests.swift`, `PersistentImageServiceTests.swift` | NaarsCarsTests | 7 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Messaging/MessageAudioPlayerTests.swift` | NaarsCarsTests | 8 (D-1) | Xcode MCP |
| `supabase/migrations/20261019_0050_geocoding_multiplier_lookup.sql` (APPLIED by the orchestrator) | none | SQL plan runbook | normal tools |
| `supabase/migrations/20261019_0060`-`0063` (NOT APPLIED) | none | 11 | normal tools |
| `supabase/dryruns/20261019_0060`-`0063_*.dryrun.sql`, `supabase/dryruns/20261019_phase5b_not_applied_check.sql` (never applied) | none | 11 | normal tools |
| `Docs/qa/2026-10-19-multi-community-phase5a-gate.md` | none | 10 | normal tools |

## Removed files

| Path | Task | References removed |
|---|---|---|
| `Core/Services/MessagingDebugView.swift`, `Core/Utilities/Logger.swift` (2), `UI/Components/Cards/InviteCodeCard.swift`, `Features/Authentication/Views/SignupInviteCodeView.swift`, `SignupMethodChoiceView.swift`, `Features/Admin/Views/AdminInviteView.swift`, `Features/Profile/Views/InvitationWorkflowView.swift` | 1 | 8 |
| `Features/Admin/Views/PendingUsersView.swift`, `Features/Admin/ViewModels/PendingUsersViewModel.swift`, `Features/Admin/Views/PendingUserDetailView.swift` | 2 | 3 |
| `Core/Services/InviteService.swift`, `Core/Models/InviteCode.swift`, `Core/Utilities/InviteCodeGenerator.swift` | 3 | 3 |
| `Features/Authentication/Views/ApplicationFieldsView.swift`, `Features/Authentication/ViewModels/ApplicationFieldsViewModel.swift` | 4 | 2 |
| `Features/Rides/Views/RidesDashboardView.swift`, `Features/Rides/ViewModels/RidesDashboardViewModel.swift`, `Features/Favors/Views/FavorsDashboardView.swift`, `Features/Favors/ViewModels/FavorsDashboardViewModel.swift` (2 each), `NaarsCarsTests/Features/Rides/RidesDashboardViewModelTests.swift`, `NaarsCarsTests/Features/Favors/FavorsDashboardViewModelTests.swift` | 5 | 10 |

## Self-review notes

- **Spec §4 Phase 5 and A5 coverage.** 5a: the dead invite UI (`SignupInviteCodeView`, `SignupMethodChoiceView`, `AdminInviteView`, `InvitationWorkflowView`, `InviteCodeCard`, `InviteService`, `AuthService.signUp(email:password:inviteCode:)`) — Tasks 1, 3; `ApplicationFieldsView` and `PendingUsersView` — Tasks 4, 2; the Audit Notes' dead files — Tasks 1, 5; stop maintaining `profiles.heard_about / join_reason` for new rows — Task 4 (client) and SQL File B blocks 2-3 (the server copy, gated because the installed admin screen reads it); the definer geocoding lookup — SQL File A and Task 6; signed URLs for the four buckets — Task 7. 5b: the bridges, the `fill_request_community` fallback and the default-community answer copy — File B blocks 1-5; `admin_reject_pending_user` revoked — File B block 6; `invite_codes` dropped — File C; `geocoding_cache` direct access revoked — File D; private buckets — File E. "What old clients see" per file: the SQL plan headers.
- **Deliberate departures the owner can veto.** (D-1) **Voice notes.** The spec and A5 name four buckets; `audio-messages` is also public (live, 2026-10-19: 5 objects, 4 messages with audio) and holds private-thread content of the same kind as `message-images`. Task 8 and File E's optional block cover it; without the owner's yes both are skipped and voice notes stay publicly addressable. (D-2) **Stored values stay public URLs.** The brief suggested persisting the object path. Keeping the upload's URL in the database and in `SDMessage` leaves the installed build able to show images sent from the new build until File E, needs no SwiftData or mapper change (the trio of CLAUDE.md's seams), and the object path is recoverable from the URL (`StoredObjectReference.parse`). (D-3) `InviteCodeGenerator` and `ProfileService`'s two invite-code methods go too: they are unreferenced after Task 3 and the methods read and write the table File C drops. `InviteCodeFormatter` stays (community invites use it). (D-4) `AdminService.fetchPendingUsers` / `approveUser` / `rejectUser` go with the screens (the last client call to `admin_reject_pending_user` and the last direct `approved` write). (D-5) `create_signup_profile` is not changed: no build ever sent `p_heard_about` / `p_join_reason`, so it already writes null for every new row; replacing a sign-up function for no observable effect is risk without benefit. (D-6) `cleanupGeocodingCache` is deleted (no caller; its DELETE matched nothing under RLS) and no placemark data is sent any more. (D-7) Cache freshness moves to the server and keys on `updated_at`. (D-8) The name rules move into `CommunityOnboardingViewModel` rather than a new file. (D-9) **The server copy of the answers is gated, although A5 point 2 lists "stop writing `heard_about` / `join_reason` to `profiles` for new rows" under 5a.** This plan does the client half in 5a (Task 4: no client code writes either column) and moves the server half, the default-community copy inside `redeem_community_invite` / `request_to_join_community` (live md5 `f18e6af6…` / `da89c233…`), to gated SQL File B blocks 2-3, because the installed build's Pending Users screen reads those columns (`main:NaarsCars/Features/Admin/Views/PendingUserDetailView.swift:63, 78`, `heardAbout ?? "admin_not_provided"`) and the change would show its admins "Not provided" for applicants who joined through a community build. The owner can veto this and have blocks 2-3 applied in 5a (as two separate `apply_migration` calls with the md5 checks they already carry), accepting that effect on the installed admin screen. (D-10) **Downloads of stored objects bypass `URLCache`** (`URLSession.signedStorageDownload`, Tasks 7-8): the voice-note warm-up in `MessagingSyncEngine.precacheMedia` fills the player's temp-file cache instead of `URLCache`.
- **Tests.** CLAUDE.md fixture gate for RPC call sites: Task 6 (both RPCs, body key sets, missing-function behaviour). Storage: Task 7 (parse, sign once, renew, concurrent dedup, fallback, bound, reset, the sign route, the disk cache name, no `URLCache` entry, the no-cache download session). Auth: Task 4 (the moved name rule) plus the existing onboarding and launch tests. Review Focus: 1 (Tasks 1-5, 10), 2 (7, 10), 3 (7), 4 (7), 5 (7), 6 (6), 7 (4), 8 (10, SQL probe `storage_private`).
- **Release safety.** `RELEASE` in Tasks 5, 7 and the gate; the removals touch no `#Preview` that remains; no DEBUG-only type is added outside `#if DEBUG`.
- **Type and name consistency.** `StorageObjectSigning`, `StorageURLResolving`, `StoredObjectReference.parse(_:expectedHost:)`, `StorageURLSigner.shared` / `.signedBuckets` / `resolvedURL(for:)` / `reset()`, `SupabaseStorageSigner`, `PersistentImageService.urlResolver`, `Constants.Storage.signedURLLifetime` / `signedURLRenewMargin` / `signedURLCacheMaxEntries`, `RideCostEstimator.fetchCachedMultiplier(locationKey:)` / `upsertGeocodingCache(coordinate:locationKey:multiplier:)` / `isMissingGeocodingFunction(_:)`, `CommunityOnboardingViewModel.applePlaceholderName` / `nameProblem(_:)`, and the RPC names `get_geocoding_multiplier`, `put_geocoding_multiplier` are spelled the same in every task and in the SQL plan.
- **Follow-ups recorded, not done here:** the 75 unused string keys; `NaarsCarsUITests.swift:246-247, 575` (invite-code UI test helpers for a screen that no longer exists); `NotificationService.sendApprovalNotification` (`Core/Services/NotificationService.swift:328-340`) has no caller; `profiles` keeps table-level UPDATE grants on `heard_about`, `join_reason` and `application_complete` (File B's trigger closes the flags; the answers columns could be revoked per column later); the disk image cache (`Library/Caches/PersistentImageCache`) is not cleared at sign-out, before or after this phase; `EmailService.sendWelcomeEmail` (`Core/Services/EmailService.swift:35`) loses its only caller (`AdminService.swift:421`, inside `approveUser`) in Task 2 and becomes dead (remove it, or wire it to the community approval path, in a later change); `URLCache.shared` may still hold public-URL responses written before this phase (no token, harmless; they age out).
