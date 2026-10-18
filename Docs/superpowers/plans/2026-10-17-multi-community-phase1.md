# Multi-community Phase 1 (iOS hardening and community-aware reads) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Phase 1 client of the multi-community design: notification hardening, community-aware reads (Town Hall, leaderboard, member search, reputation, badges), the `CommunityContext` with its launch ordering, the guarded launch and routing paths, and the multi-membership UI (chips, two title menus, "Post to"), all invisible to a member of one community.

**Architecture:** One new `@Observable @MainActor` state holder (`CommunityContext`) restored synchronously from UserDefaults before the sync engines start and refreshed from `get_my_memberships` off the launch path; a nil community means "no filter" everywhere. The mapper trio gains one optional `communityId` per entity. Town Hall reads one scope at a time through the existing coordinator; the feed ViewModel owns the switch and the push target. `RefreshCoordinator`, realtime and the send path are not modified.

**Tech Stack:** Swift 6.3 toolchain in Swift 5 language mode, SwiftUI + SwiftData, supabase-swift, XCTest, Xcode 26.6, iOS 26.0 deployment target.

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` (§3.7 in full, §4 Phase 1, §5, §10) under the owner's decisions `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` (that file wins where they differ). Read both before starting a task.

## Global Constraints

- Deployment target `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; `SWIFT_VERSION = 5.0`; `SWIFT_APPROACHABLE_CONCURRENCY = YES`; `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. No build-setting changes.
- `RefreshCoordinator.swift` is not edited. A ViewModel's only coordinator call is `RefreshCoordinator.shared.forceFullRefreshAndWait(_:trigger:)`. Never `invalidate` or `refreshIfNeeded` from a ViewModel. Realtime, `MessageSendManager`, reactions and messaging mappers are not touched.
- No new notification type (the registry stays at 33 raw values). Push payload key for the community is `community_id`; the Town Hall entity key is `town_hall_post_id`.
- **Nil community means "no filter"** in the service, the engine, the repository and the leaderboard; a nil row community means "unknown, show it". Nothing shows an empty state because `CommunityContext` has not loaded.
- With one active membership, every chip, title menu and the "Post to" section is hidden (D6). Chips are `NaarsChip(text:tint: nil)`; no new color tokens.
- SwiftData: exactly four new stored properties, all `var communityId: UUID?` with no default expression, on `SDRide`, `SDFavor`, `SDTownHallPost`, `SDNotification`. No new `@Model`, no renames.
- Persisted per account in `UserDefaults.standard`: `community.tab.<userId>`, `community.requestsScope.<userId>`, `community.lastPosted.<userId>`.
- New ViewModel-like types follow the file's existing observation style; `CommunityContext` is `@Observable @MainActor` (spec §3.7, State rule 2 exception for Core state holders).
- "Post to" default (D24): Requests narrow if set and active, else `communityTabId` if active, else `lastPostedCommunityId` if active, else the `is_primary` active membership, else the first active membership.
- Strings: every user-facing string is a key in `NaarsCars/Resources/Localizable.xcstrings` with `en`, `es`, `ko`, `vi`, `zh-Hans`, `zh-Hant`, `"extractionState" : "manual"`, each `"state" : "translated"`. Add keys only with `scripts/add-localization-keys.py` (created in Task 15); it preserves Xcode's byte layout. Never remove a key.
- **New Swift files** (decision 3): open this worktree's project (`.claude/worktrees/naarscars-multi-community-roadmap-f08594/NaarsCars/NaarsCars.xcodeproj`) in Xcode, call `XcodeListWindows`, confirm the window's workspace path is that file, `XcodeLS` the target group to confirm the navigator path (it starts `NaarsCars/…`, for example `NaarsCars/Core/Models`), then `XcodeWrite`. If another project is open, write the file to disk with normal tools, report "not yet in the project", and do not claim a green build. After writing, let Xcode go idle (or quit it) before the Lane B build. Every task that creates a Swift file lists that file **and** `NaarsCars/NaarsCars.xcodeproj/project.pbxproj` in its commit step.
- **Chain stop rule (orchestrator).** When a task reports "not yet in the project", the orchestrator stops the chain: no later task runs (every later task may depend on the type) until the file has been added to the right target through Xcode, `BUILD` is green, the task's tests pass and its commit exists. Then the chain resumes at the next task.
- Existing files are edited with normal tools. Never hand-edit `project.pbxproj`.
- One build at a time on this Mac. One headless simulator (`iPhone 16`, iOS 26.x). Unit tests run with the simulator **signed out** (a signed-in run writes to the live app). Never run `RideServiceTests`, `FavorServiceTests`, `TownHallServiceTests` or the old live cases of `TownHallFeedViewModelTests` while signed in.
- Every task ends with a green Lane B build, its listed tests passing, and one commit whose subject starts `[P1-T<n>]` and whose body ends with the Co-Authored-By trailer the executing session was given. Stage files by path only: the worktree holds untracked Phase 0 migrations and probes (`supabase/migrations/20261017_*`, `supabase/probes/`) that belong to Phase 0 commits. Never `git add -A` / `git add .`. Tasks never push; pushing and the draft pull request (decision 4) are the orchestrator's.
- Screen captures for every touched screen are taken together in Task 22 (one owner sign-in); each UI task lists its captures under "Capture list" and says which views have a `#Preview`.

### Commands (used by every task; `<n>` is the task number)

```bash
# BUILD (from the worktree root). Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build > build/P1-T<n>-build.log 2>&1; echo "exit=$?"
grep -n "error:" build/P1-T<n>-build.log | head -20
# New warnings: every "warning:" line naming a file this task touched must also appear in build/baseline-build.log.
grep -n "warning:" build/P1-T<n>-build.log | grep -E "<touched file basenames joined with |>"

# RED (compile-level failing test). Expected: exit≠0 and the named compile error.
xcodebuild build-for-testing -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/DerivedData -quiet > build/P1-T<n>-red.log 2>&1; echo "exit=$?"; grep -n "error:" build/P1-T<n>-red.log | head

# TEST <ONLY> = one or more -only-testing:NaarsCarsTests/<Class>[/<method>]. Expected: exit=0, 0 failures.
rm -rf build/P1-T<n>.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' <ONLY> -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P1-T<n>.xcresult -quiet > build/P1-T<n>-test.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P1-T<n>.xcresult

# FULL = CLAUDE.md's Lane B full unit-suite command, signed out. Expected: exit=0, 0 failures; skips only in the session-gated classes.
rm -rf build/P1-T<n>-full.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P1-T<n>-full.xcresult -quiet > build/P1-T<n>-full.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P1-T<n>-full.xcresult
```

`FULL` runs at the end of every task that changes a fragile system or a high-blast-radius seam (CLAUDE.md Verification Loop step 2): Tasks 1, 2, 4, 6, 7, 8, 12 and 14 (and Task 22's gate run). Before the first `FULL` run, confirm the simulator is signed out (install and launch the app; a screenshot shows the Welcome screen); if it is signed in, stop and ask the owner to sign out, because a signed-in run writes to the live app. Record executed / passed / skipped in the task's report so a later regression can be traced to the task that introduced it.

A new test file is in the right target when its `TEST` run reports the expected number of executed tests (0 executed means it is not in `NaarsCarsTests`). A new app file is in the app target when `BUILD` resolves the types it declares from other files.

### Task index (model and suggested reasoning effort)

| Task | Deliverable | Model | Effort |
|---|---|---|---|
| 1 | Tolerant `NotificationType` decoder, registry fixtures (+ opus review of `init(from:)`) | sonnet | high |
| 2 | Mapper trio: `communityId` on four entities, every field site | opus | high |
| 3 | Community models, `CommunityService` + protocol, fixtures | sonnet | medium |
| 4 | `CommunityContext` and its sign-out reset | opus | high |
| 5 | Launch ordering: restore before engines, membership load after | opus | high |
| 6 | `recheckAccountStatus` (foreground, successful reads only) | opus | high |
| 7 | `.enterApp` guard and the waiting screen's `performCriticalLaunch` | opus | high |
| 8 | `entityIdKey` fix, zero-row-tolerant post fetch, push refresh plan | opus | high |
| 9 | Town Hall store scoping (service, engine, repository) | opus | high |
| 10 | Town Hall feed: active community, switch, joined-sync guard | opus | high |
| 11 | Community tab title menu (+ shared conditional `communityTitleMenu` modifier) | opus | medium |
| 12 | `community_id` on Town Hall push and bell-row targets | opus | high |
| 13 | Community-aware leaderboard (+ params and row fixture test) | sonnet | medium |
| 14 | `get_badge_counts` payload keys | opus | medium |
| 15 | Reputation through `get_profile_stats` (+ strings helper) | sonnet | medium |
| 16 | Member search through `search_community_members` | sonnet | medium |
| 17 | Requests narrow and its title menu | sonnet | medium |
| 18 | Community chips on cards, details, edit screens | sonnet | medium |
| 19 | "Former member" fallbacks (poster, author, helper, reviewer) | sonnet | medium |
| 20 | "Post to" on the create forms; Town Hall post community | sonnet | medium |
| 21 | Documentation for Phase 1 | sonnet | medium |
| 22 | Phase gate | opus | high |

### Prerequisite outside this plan

Phase 0 steps 1–5 must be live before Task 22 (it checks). Tasks 1–21 are verified with stubs and need no backend change. This client must not be released before Phase 0 step 3 (`get_profile_stats`, `get_community_leaderboard`, `get_community_spotlights`) and step 5 (`get_my_memberships`, `search_community_members`) are applied: without them the profile screens fail to load (Task 15 replaces the direct reads) and member search fails (Task 16).

## Review Focus

These are not exercised by the spec-named unit tests. Each is pinned by a requirement in its owning task and a check in Task 22.

1. **A Town Hall push now runs a single-post upsert (Task 8).** The current `fetchPost(id:)` (`Core/Services/TownHallService.swift:91-100`) returns an un-enriched post, and `updateSDPostIfChanged` (`Core/Storage/BackgroundSyncActor.swift:657-674`) would then overwrite the cached author name with nil and the comment count with 0. Expected: after a `town_hall_comment` push the card keeps its author and count. Task 8 enriches the single post; Task 22 checks it with a `simctl push` fixture.
2. **Approval seen on the waiting screen (Task 7).** `performCriticalLaunch()` started from the screen's `.task` is cancelled when that screen leaves the hierarchy (it does, the moment the state becomes `.checkingAuth`), and a cancelled session read lands in `.ready(.unauthenticated)`. Expected: approval enters the app. Task 7 starts it in an unstructured `Task`; reviewed in code.
3. **A member of one community sees no change (Tasks 11, 17, 18, 20).** A `toolbarTitleMenu` with conditional (empty) content can still draw a title chevron, an empty `navigationSubtitle` can still reserve a line, and a chip with one membership would be visible. Expected: Requests, Community tab and both forms look exactly like the previous build. Tasks 11 and 17 therefore apply both modifiers only through `.communityTitleMenu(enabled:subtitle:menu:)` (Task 11), so with one membership the view tree is the same as today's; Task 22 compares one-membership captures with the previous build's.
4. **A forwarded push for a community the person is not in (Task 12).** Switching `communityTabId` to a non-member community would leave an empty Town Hall. Expected: the toast "This content is no longer available." and the tab stays on the current community. Task 12 switches only to an active membership; Task 22 sends a fixture with a random `community_id`.
5. **Long community names at AX5 (Tasks 11, 17, 20).** The names are up to 60 characters (`communities.name` CHECK). Expected: titles, menu rows and "Post to <name>" truncate instead of overlapping. The Task 4 DEBUG seam includes one 60-character name; Task 22 captures AX5.

---

### Task 1: Tolerant `NotificationType` decoder and complete registry fixtures

**Model:** sonnet, high effort, with an opus review step (`NotificationType` is a high-blast-radius seam; the decoder runs on every notification decode in `NotificationService`) · **Files:**
- Modify: `NaarsCars/Core/Models/AppNotification.swift:11-154` (add an extension after line 154)
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/NotificationFixtures.swift:11-86`
- Test: `NaarsCars/NaarsCarsTests/Core/Decoding/NotificationTypeDecodingTests.swift:12-84`

**Interfaces:**
- Produces: `extension NotificationType { init(from decoder: Decoder) throws }` — an unknown raw string decodes as `.other`; `NotificationType(rawValue:)` still returns nil for unknown strings (the existing `testUnknownRawValueReturnsNil` at :82-84 stays green). `NotificationService`'s fast path (`Core/Services/NotificationService.swift:126-130`) then no longer falls back to the lenient per-item decode for a future type.

- [ ] **Step 1: Write the failing tests** in `NotificationTypeDecodingTests`: replace the hand list `allTypes` (:12-45) with `NotificationType.allCases`, and add:

```swift
func testFixturesContainExactlyAllNotificationTypeRawValues() {   // replaces the body at :47-50
    XCTAssertEqual(NotificationFixtures.allRawValues.count, 33)
    XCTAssertEqual(Set(NotificationFixtures.allRawValues), Set(NotificationType.allCases.map(\.rawValue)))
}
func testUnknownRawValueDecodesAsOther() throws {
    let decoded = try JSONDecoder().decode(NotificationType.self, from: Data("\"membership_update\"".utf8))
    XCTAssertEqual(decoded, .other)
}
func testAppNotificationWithUnknownTypeDecodes() throws {
    let json = #"{"id":"0A000000-0000-0000-0000-000000000001","user_id":"0A000000-0000-0000-0000-000000000002","type":"membership_update","title":"T","body":null,"read":false,"pinned":false,"created_at":"2026-10-17T12:00:00Z"}"#
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    XCTAssertEqual(try decoder.decode(AppNotification.self, from: Data(json.utf8)).type, .other)
}
```

- [ ] **Step 2: RED.** Run `RED`. Expected: `testFixturesContainExactlyAllNotificationTypeRawValues` would fail at runtime (30 ≠ 33) and `testUnknownRawValueDecodesAsOther` throws; the build itself succeeds, so run `TEST` with `<ONLY>` = `-only-testing:NaarsCarsTests/NotificationTypeDecodingTests` and expect those two failures.
- [ ] **Step 3: Complete the fixtures.** In `NotificationFixtures.allRawValues` add `"content_reported"`, `"content_hidden"`, `"account_restricted"`; in `mandatoryTypes` add `"account_restricted"` (its `canBeDisabled` is false, `AppNotification.swift:118-119`); in `preferenceMapping` add the three with `nil`.
- [ ] **Step 4: Implement** `init(from decoder: Decoder) throws` in an extension of `NotificationType`: decode a single `String`, `self = NotificationType(rawValue: raw) ?? .other`. Encoding stays synthesized.
- [ ] **Step 5: GREEN.** `BUILD`, then `TEST` with `-only-testing:NaarsCarsTests/NotificationTypeDecodingTests -only-testing:NaarsCarsTests/NotificationTypeDomainMappingTests -only-testing:NaarsCarsTests/AppNotificationTests`. Expected: all pass.
- [ ] **Step 6: Opus review** (a separate opus subagent, read-only, given the diff). It checks: the extension decodes through `singleValueContainer()` and nothing else; synthesized `Encodable` still writes the raw value (encode `.other` and an ordinary case, compare strings); no call site uses `NotificationType(rawValue:)` to mean "decode" in a way the new fallback changes (`grep -rn "NotificationType(rawValue" NaarsCars/Core NaarsCars/Features NaarsCars/App`: each hit keeps its nil-on-unknown behaviour, which is unchanged); `NotificationService.swift:126-130`'s fast path and its lenient per-item fallback still compile and behave the same for known types. The implementer fixes any finding before the commit.
- [ ] **Step 7: FULL.** Expected: exit 0, 0 failures.
- [ ] **Step 8: Commit** `[P1-T1] Decode unknown notification types as .other; complete registry fixtures` with the three files.

---

### Task 2: Mapper trio — `communityId` on rides, favors, posts and notifications

**Model:** opus, high effort (`SDModels.swift` and `BackgroundSyncActor.swift` are High-Risk Files, and the SwiftData-to-domain mappers are a mandatory trio: one missed `updateSD*IfChanged` comparison means rows cached by the previous build are never rewritten) · **Files:**
- Modify: `NaarsCars/Core/Models/Ride.swift:40-64, 110-135, 139-195`; `Favor.swift:69-91, 130-153, 157-210`; `TownHallPost.swift:25-153`; `AppNotification.swift:203-269`
- Modify: `NaarsCars/Core/Storage/SDModels.swift:138-205` (SDRide), `:207-270` (SDFavor), `:272-307` (SDNotification), `:311-369` (SDTownHallPost)
- Modify: `NaarsCars/Core/Storage/BackgroundSyncActor.swift` ride sites `44-63, 66-96, 347-377, 478-504, 538-567, 718-733, 845-860`; favor sites `109-126, 130-158, 401-429, 506-531, 570-598, 754-770, 887-903`; notification sites `189-198, 201-216, 455-470, 601-614, 790-801`; post sites `657-674, 933-942, 1033-1042`
- Modify: `NaarsCars/Core/Storage/TownHallRepository.swift:169-197, 199-218, 222-239`
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift:41-68, 76-101`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationGroupingManager.swift:47-63`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift`

**Interfaces:**
- Produces: `Ride.communityId`, `Favor.communityId`, `TownHallPost.communityId`, `AppNotification.communityId` — all `let communityId: UUID?`, `CodingKeys` case `communityId = "community_id"` (synthesized decoding uses `decodeIfPresent`), an init parameter `communityId: UUID? = nil` placed directly after `hiddenReason` (after `sourceUserId` for `AppNotification`). `TownHallPost.encode(to:)` (:75-90) adds `encodeIfPresent(communityId, forKey: .communityId)` (nil is omitted, so the fill trigger resolves it); `TownHallPost.==` (:138-153) compares it. SD models: `var communityId: UUID?` plus init parameter `communityId: UUID? = nil` (last).
- Every field site copies or compares `communityId`; `updateSD*IfChanged` and `TownHallRepository.updateIfChanged` compare it unconditionally, which is what rewrites a row cached by the previous build. `RidesDashboardViewModel.swift:171` and `FavorsDashboardViewModel.swift:156` are dead files (CLAUDE.md Audit Notes item 5) and are left on the defaulted parameter.
- `Conversation`, `Message`, `MessagingMapper` are not touched.

- [ ] **Step 1: Create the test file** via the Xcode MCP (Global Constraints) at `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift`, `@MainActor final class CommunityStoreScopingTests: XCTestCase`, with an in-memory `ModelContainer(for: SDRide.self, SDFavor.self, SDNotification.self, SDTownHallPost.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))`, whole-second dates and fixed UUIDs (`BackgroundSyncActorConversationSyncTests.swift:13-28` style). Tests:

```swift
func testSyncAll_WritesCommunityIdForRideFavorAndNotification()  // community A on each → SD rows carry A
func testSyncAll_NilCommunityStaysNil()                         // payloads without community → SD rows nil
func testSyncAll_RewritesCachedRowWithNilCommunity()            // seed SDRide/SDFavor/SDNotification with nil; sync identical payloads with A
    // XCTAssertTrue(result.ridesChanged); XCTAssertTrue(result.favorsChanged); XCTAssertTrue(result.notificationsChanged); rows == A
func testUpsertRideAndFavorWithChangeDetection_WriteCommunityId()
func testSyncPosts_InsertsAndRewritesCommunityId()              // syncPostsWithChangeDetection: insert A; seed nil then rewrite → A, savedToStore true
func testUpsertPostWithChangeDetection_WritesCommunityId()
func testRequestFilterManager_ReverseMapCarriesCommunityId()    // open, unclaimed rows dated tomorrow (the 12 h window drops past ones);
                                                                // getFilteredRequests(rides: [sd ride A], favors: [sd favor A], filter: .open) → items' communityId == A (signed out: guest path)
func testNotificationGroupingManager_CarriesCommunityId()       // getFilteredNotifications(sdNotifications: [sd ride_claimed with A]).first?.communityId == A
func testTownHallRepository_MapsAndRewritesCommunityId()        // TownHallRepository().setup(modelContext:); upsertPosts([post A]); getPosts().first?.communityId == A;
                                                                // seed SD post nil, upsertPosts([same post with A]) → A
func testTownHallPostEncode_OmitsNilCommunityIdAndWritesSetOne() // JSONEncoder: nil → no "community_id" key (the insert lets the fill trigger resolve it); A → "community_id" == A
```

- [ ] **Step 2: RED.** Run `RED`. Expected: "extra argument 'communityId' in call" / "value of type 'SDRide' has no member 'communityId'".
- [ ] **Step 3: Models.** Add the property, coding key and init parameter to the four domain models as listed in Interfaces, plus the `TownHallPost` encode and `==` lines.
- [ ] **Step 4: SD models.** Add `var communityId: UUID?` and the defaulted init parameter to the four `@Model` classes.
- [ ] **Step 5: BackgroundSyncActor ride and favor sites.** Insert sites pass `communityId: ride.communityId` / `favor.communityId`; update branches and `updateSDRide` / `updateSDFavor` assign it; `updateSDRideIfChanged` / `updateSDFavorIfChanged` add `if sd.communityId != ride.communityId { sd.communityId = ride.communityId; changed = true }`.
- [ ] **Step 6: BackgroundSyncActor notification and post sites**, same three kinds of edit.
- [ ] **Step 7: Reverse maps.** `TownHallRepository.mapToTownHallPost` / `mapToSDTownHallPost` / `updateIfChanged`, `RequestFilterManager` ride and favor reverse maps, `NotificationGroupingManager.getFilteredNotifications`.
- [ ] **Step 8: Site audit** (before GREEN). Run and paste the output into the task report:

```bash
grep -rn "SDRide(\|SDFavor(\|SDNotification(\|SDTownHallPost(" NaarsCars/Core NaarsCars/Features NaarsCars/App
grep -rn "func updateSD\w*IfChanged\|func updateSD\w*(\|func mapTo\w*\|func updateIfChanged" NaarsCars/Core NaarsCars/Features
```

Every construction must pass `communityId:` (except the two dead dashboard ViewModels named in Interfaces and the test/preview files, which use the default), and every listed body must copy (`updateSD*`, `mapTo*`) or compare-and-assign (`updateSD*IfChanged`, `updateIfChanged`) `communityId`. A hit not in the Files list above is added to this task, not left for later.
- [ ] **Step 9: GREEN.** `BUILD`, then `TEST` with `-only-testing:NaarsCarsTests/CommunityStoreScopingTests -only-testing:NaarsCarsTests/BackgroundSyncActorConversationSyncTests -only-testing:NaarsCarsTests/RideTests -only-testing:NaarsCarsTests/FavorTests -only-testing:NaarsCarsTests/TownHallPostTests -only-testing:NaarsCarsTests/AppNotificationTests`. Expected: 10 new tests executed and passing.
- [ ] **Step 10: FULL.** Expected: exit 0, 0 failures.
- [ ] **Step 11: Commit** `[P1-T2] Add communityId to the ride, favor, post and notification mapper trio` with every file above, `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift` and `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`.

---

### Task 3: Community models, `CommunityService` and its protocol

**Model:** sonnet · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Core/Models/Community.swift`, `NaarsCars/Core/Protocols/CommunityServiceProtocol.swift`, `NaarsCars/Core/Services/CommunityService.swift`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift`, `NaarsCars/NaarsCarsTests/Core/Decoding/CommunityPayloadDecodingTests.swift`
- Reference: `supabase/migrations/20261017_0005_communities_rpcs.sql:1777-1820` (`get_my_memberships` columns), `NaarsCars/Core/Utilities/DateDecoderFactory.swift:23`, `NaarsCars/Core/Services/ProfileService.swift:480` (the no-parameter `.rpc` idiom)

**Interfaces:**
- Produces (`Community.swift`; file header per CLAUDE.md):

```swift
enum CommunityRole: String, Decodable, Sendable {
    case owner, admin, member
    init(from decoder: Decoder) throws   // tolerant: an unknown raw string decodes as .member (least privilege)
}
enum MembershipStatus: String, Decodable, Sendable {
    case pending, active, left, removed
    init(from decoder: Decoder) throws   // tolerant: an unknown raw string decodes as .pending (never counted as active)
}
// Both read one String from singleValueContainer() and fall back as noted, so a role or status the
// server adds later cannot make the whole [CommunityMembership] decode throw (the failure Task 1 fixes
// for NotificationType). rawValue init keeps returning nil for unknown strings.
struct CommunityMembership: Decodable, Identifiable, Equatable, Sendable {
    let communityId: UUID; let name: String; let description: String?
    let role: CommunityRole; let status: MembershipStatus; let isPrimary: Bool
    let joinPolicy: String; let isPublic: Bool; let isDefault: Bool; let membersCanInvite: Bool
    let timezone: String; let canInvite: Bool; let memberCount: Int; let pendingCount: Int?
    let notificationsMuted: Bool; let mutedUntil: Date?; let joinedAt: Date; let activatedAt: Date?
    var id: UUID { communityId }
    // explicit CodingKeys: community_id, name, description, role, status, is_primary, join_policy, is_public,
    // is_default, members_can_invite, timezone, can_invite, member_count, pending_count,
    // notifications_muted, muted_until, joined_at, activated_at
}
enum RequestsScope: Equatable, Hashable, Sendable {
    case all
    case community(UUID)
    var communityId: UUID? { get }
    func includes(_ communityId: UUID?) -> Bool   // .all → true; .community(id) → communityId == id || communityId == nil
    var storageValue: String { get }              // "all" or the uuidString
    init(storageValue: String?)                   // nil, "all" or unparsable → .all
}
```
- Produces: `protocol CommunityServiceProtocol: AnyObject { func fetchMyMemberships() async throws -> [CommunityMembership] }`; `final class CommunityService: CommunityServiceProtocol` with `static let shared`, `private init()`, `fetchMyMemberships()` = `SupabaseService.shared.client.rpc("get_my_memberships").execute()` decoded with `DateDecoderFactory.makeSupabaseDecoder()`.
- Produces (test target, `CommunityFixtures.swift`): `enum CommunityFixtures` with `static let communityA`, `communityB`, `communityC` (fixed UUIDs), `static let myMembershipsJSON: String` (two rows: A active `is_primary: false` member, B active `is_primary: true` admin with `pending_count: 2`; ISO-8601 timestamps with fractional seconds), `static let myMembershipsUnknownEnumsJSON: String` (one row of the same shape with `"role": "moderator"`, `"status": "suspended"`), `static func membership(_ id: UUID, name: String, isPrimary: Bool = false, status: MembershipStatus = .active, role: CommunityRole = .member) -> CommunityMembership` (memberwise init), and

```swift
final class StubCommunityService: CommunityServiceProtocol {
    var result: Result<[CommunityMembership], Error>
    var gate: (() async -> Void)?          // awaited before returning; lets a test hold a fetch in flight
    private(set) var fetchCount = 0
    init(result: Result<[CommunityMembership], Error>)
    func fetchMyMemberships() async throws -> [CommunityMembership]   // fetchCount += 1; await gate?(); return try result.get()
}
```
- Not in Phase 1 (first consumers are Phase 2): `Community`, `CommunityInvite`, `PendingInviteStore` and every write RPC wrapper. This is a deliberate departure from spec §4 Phase 1's "new types" and spec §5's sign-out row (which clears `PendingInviteStore`): nothing in Phase 1 reads or writes them, and spec §4 Phase 2 already lists `PendingInviteStore` among its client deliverables. See Self-review notes.

- [ ] **Step 1: Create `CommunityFixtures.swift` and `CommunityPayloadDecodingTests.swift`** via the Xcode MCP. Test:

```swift
func testMyMembershipsRowsDecode() throws {
    let rows = try DateDecoderFactory.makeSupabaseDecoder().decode([CommunityMembership].self, from: Data(CommunityFixtures.myMembershipsJSON.utf8))
    XCTAssertEqual(rows.map(\.communityId), [CommunityFixtures.communityA, CommunityFixtures.communityB])
    XCTAssertEqual(rows[1].role, .admin); XCTAssertTrue(rows[1].isPrimary); XCTAssertEqual(rows[1].pendingCount, 2)
    XCTAssertNil(rows[0].pendingCount); XCTAssertEqual(rows[0].status, .active)
}
func testRequestsScopeStorageRoundTripAndIncludes() {
    XCTAssertEqual(RequestsScope(storageValue: RequestsScope.community(CommunityFixtures.communityA).storageValue), .community(CommunityFixtures.communityA))
    XCTAssertEqual(RequestsScope(storageValue: "garbage"), .all)
    XCTAssertTrue(RequestsScope.community(CommunityFixtures.communityA).includes(nil))
    XCTAssertFalse(RequestsScope.community(CommunityFixtures.communityA).includes(CommunityFixtures.communityB))
}
func testMembershipWithUnknownRoleAndStatusDecodesTolerantly() throws {
    // CommunityFixtures.myMembershipsUnknownEnumsJSON: one row, "role": "moderator", "status": "suspended"
    let rows = try DateDecoderFactory.makeSupabaseDecoder().decode([CommunityMembership].self, from: Data(CommunityFixtures.myMembershipsUnknownEnumsJSON.utf8))
    XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].role, .member); XCTAssertEqual(rows[0].status, .pending)
}
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find type 'CommunityMembership' in scope".
- [ ] **Step 3: Create the three app files** via the Xcode MCP with the interfaces above.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityPayloadDecodingTests`. Expected: 3 executed, 3 passed.
- [ ] **Step 5: Commit** `[P1-T3] Add community membership models and CommunityService` with `NaarsCars/Core/Models/Community.swift`, `NaarsCars/Core/Protocols/CommunityServiceProtocol.swift`, `NaarsCars/Core/Services/CommunityService.swift`, `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift`, `NaarsCars/NaarsCarsTests/Core/Decoding/CommunityPayloadDecodingTests.swift` and `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`.

---

### Task 4: `CommunityContext` and its sign-out reset

**Model:** opus · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/App/CommunityContext.swift`
- Modify: `NaarsCars/Core/Utilities/Constants.swift:95-135` (add one `Timing` constant)
- Modify: `NaarsCars/Core/Services/AuthService.swift:566-615` (`handleSignOut`: capture the id before :589 clears it), `:652-672` (`clearPerAccountLocalState`)
- Test: `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift` (add a `// MARK: - CommunityContext` section)

**Interfaces:**
- Consumes: `CommunityServiceProtocol`, `CommunityMembership`, `RequestsScope` (Task 3).
- Produces:

```swift
@Observable @MainActor
final class CommunityContext {
    static let shared = CommunityContext()
    static let tabKeyPrefix = "community.tab.", requestsScopeKeyPrefix = "community.requestsScope.", lastPostedKeyPrefix = "community.lastPosted."
    init(service: any CommunityServiceProtocol = CommunityService.shared, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init)
    private(set) var memberships: [CommunityMembership]          // active and pending rows, server order
    var activeMemberships: [CommunityMembership] { get }         // status == .active
    var hasMultipleCommunities: Bool { get }                     // activeMemberships.count > 1
    var communityTabId: UUID?          // equality-guarded; persisted on set when a user is restored
    var requestsScope: RequestsScope   // equality-guarded; persisted
    var lastPostedCommunityId: UUID?   // persisted
    var onActiveMembershipsEmpty: (@MainActor () async -> Void)?
    func name(for communityId: UUID?) -> String?                              // nil for nil or unknown ids
    func chipText(for communityId: UUID?, respectingScope: Bool) -> String?   // nil unless hasMultipleCommunities; nil when respectingScope && requestsScope != .all
    var defaultPostCommunityId: UUID? { get }                                 // the D24 chain (Global Constraints)
    func restore(for userId: UUID)               // synchronous; reads the three keys; no network; clears memberships if the user changed
    func refreshMemberships() async              // never throws; no-op before restore
    func refreshMembershipsIfStale() async       // skips when the last attempt is newer than Constants.Timing.membershipRefreshMinInterval
    func resetForSignOut(userId: UUID?)          // clears memory (restoredUserId = nil) and removes the three keys of `userId`
                                                 // and of the restored user, when either is set and they differ
    #if DEBUG
    static let debugCommunityCountArgument = "-debugCommunityCount"
    func debugSetMemberships(_ memberships: [CommunityMembership])
    #endif
}
```
- `communityTabId` and `requestsScope` use the equality-guarded `@ObservationIgnored` backing plus `access` / `withMutation` pattern of `App/NavigationCoordinator.swift:44-71`, so a same-value assignment does not invalidate views.
- `refreshMemberships()` captures `let requestedFor = restoredUserId` before the `await` and, when the fetch returns, **drops the result (success or failure) unless `restoredUserId == requestedFor`**. A refresh already waiting on the network when sign-out runs therefore cannot repopulate `memberships` or `communityTabId` for the guest session or the next account. Remaining rules (spec §3.7 "Membership load"): on failure log through `AppLogger.warning("community", …)` and keep everything; on success set `memberships`; if `communityTabId` is nil or not an active membership, set it to the `isPrimary` active membership, else the first active one, else nil; a `requestsScope` naming a non-active community becomes `.all`; a non-active `lastPostedCommunityId` becomes nil; when the active list is empty, `await onActiveMembershipsEmpty?()`.
- DEBUG seam: when `ProcessInfo.processInfo.arguments` contains `-debugCommunityCount` followed by `N`, every successful load appends synthetic active memberships until there are N, named `"Debug Community 2"` and, for the third, the 60-character `"Debug Community With A Deliberately Long Name For Truncation"` (Review Focus 5). DEBUG builds only; not localized.
- Produces: `Constants.Timing.membershipRefreshMinInterval: TimeInterval = 30`.
- `AuthService.handleSignOut()` adds `let signingOutUserId = currentUserId` before `currentUserId = nil` (:589) and calls `await clearPerAccountLocalState(userId: signingOutUserId)` (:615); `clearPerAccountLocalState(userId: UUID?)` calls `CommunityContext.shared.resetForSignOut(userId: userId)` inside its existing `MainActor.run` block (:668-671). The id may already be nil when the session ended first (:59, :93); `resetForSignOut` then still removes the restored user's keys. This covers sign-out from the waiting screen, the banned screen and before deferred loading ran (`restore` never ran, so only the passed id names the keys).
- Not in Phase 1: `isPlatformAdmin`, `isAdmin(of:)` (first consumers Phase 2).

- [ ] **Step 1: Write the failing tests** in `AppLaunchManagerTests` using `CommunityContext(service: StubCommunityService(...), defaults: suite)` where `suite = UserDefaults(suiteName: "CommunityContextTests-\(UUID())")!`, removed in `tearDown` with `removePersistentDomain(forName:)`:

```swift
func testCommunityContext_RestoreReadsThePersistedKeys()     // seed community.tab.<uid> = A, requestsScope = B.uuidString, lastPosted = A → restore → values match
func testCommunityContext_AssignmentPersistsPerUser()        // restore(uid); communityTabId = B → suite.string(forKey: "community.tab.\(uid)") == B.uuidString
func testCommunityContext_ResetForSignOutRemovesPersistedKeys()  // spec §5 "keys are gone": all three keys nil, communityTabId nil, memberships empty
func testCommunityContext_ResetWithoutRestoreRemovesSigningOutUsersKeys() // seed uid's three keys; no restore; resetForSignOut(userId: uid) → all three nil
func testCommunityContext_RefreshCompletingAfterResetIsDropped() async {
    // stub.result = .success([A, B]); stub.gate suspends on a CheckedContinuation the test resumes
    // restore(for: uid); let t = Task { await ctx.refreshMemberships() }; wait until stub.fetchCount == 1
    // ctx.resetForSignOut(userId: uid); resume the gate; await t.value
    // XCTAssertTrue(ctx.memberships.isEmpty); XCTAssertNil(ctx.communityTabId); XCTAssertNil(suite.string(forKey: "community.tab.\(uid)"))
}
func testCommunityContext_RefreshClearsStaleNarrowAndLastPosted() // scope .community(C), lastPosted C, rows A,B → .all and nil; tab resolves to the primary (B)
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CommunityContext' in scope".
- [ ] **Step 3: Implement** `CommunityContext.swift` (Xcode MCP), the constant, and the two `AuthService` edits.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with the six `-only-testing:NaarsCarsTests/AppLaunchManagerTests/<method>` entries (not the whole class: its two old cases go to the network). Expected: 6 passed.
- [ ] **Step 5: FULL** (sign-out teardown is fragile system 5). Expected: exit 0, 0 failures.
- [ ] **Step 6: Commit** `[P1-T4] Add CommunityContext and clear it on sign-out` with `NaarsCars/App/CommunityContext.swift`, `Constants.swift`, `AuthService.swift`, `AppLaunchManagerTests.swift`, `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`.

---

### Task 5: Launch ordering — restore before the engines, memberships after

**Model:** opus · **Files:**
- Modify: `NaarsCars/App/AppLaunchManager.swift:53-70` (properties), `:283-310` (`performDeferredLoading`), `:319-338` (`startDeferredSyncEnginesIfNeeded` stays as is)
- Test: `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift`

**Interfaces:**
- Consumes: `CommunityContext.restore(for:)`, `refreshMemberships()` (Task 4).
- Produces on `AppLaunchManager` (internal, for production defaults and test injection):

```swift
var communityContext: CommunityContext = .shared
var startSyncEngines: ((UUID) -> Void)?            // nil → startDeferredSyncEnginesIfNeeded(for:)
private(set) var membershipLoadTask: Task<Void, Never>?
func beginDeferredSession(userId: UUID)           // synchronous, see order below
```
- Order inside `beginDeferredSession` (spec §3.7 "Restore", "Membership load"): (1) set `authService.currentUserId` when nil (today's :291-293); (2) `communityContext.restore(for: userId)`; (3) start the engines (`startSyncEngines ?? startDeferredSyncEnginesIfNeeded`); (4) `membershipLoadTask = Task { await communityContext.refreshMemberships() }`. `performDeferredLoading` replaces lines 291-295 with `beginDeferredSession(userId:)` and keeps the rest. Launch routing and `checkAccountStatus` (:226-279) never wait for the membership load.

- [ ] **Step 1: Write the failing tests** (spec §4 "launch"). `setUp` saves `AuthService.shared.currentUserId`, `launchManager.state`; `tearDown` restores both and resets `communityContext = .shared`, `startSyncEngines = nil` (a leaked `currentUserId` broke later classes before, CLAUDE.md Audit Notes):

```swift
func testBeginDeferredSession_RestoresContextBeforeEnginesStart() // stored tab A; startSyncEngines = { _ in seen = ctx.communityTabId } → seen == A
func testBeginDeferredSession_NoStoredCommunityStartsEnginesWithNilContext() // seen == nil (nil = no filter)
func testMembershipLoadFailure_LeavesLaunchUnaffected()          // state = .ready(.authenticated); stub throws; await membershipLoadTask?.value
    // XCTAssertEqual(state, .ready(.authenticated)); XCTAssertEqual(ctx.communityTabId, A); XCTAssertEqual(engineStarts, 1)
func testMembershipLoad_ResolvesNilTabToPrimary()                // rows A (member), B (primary) → tab == B and persisted
```
- [ ] **Step 2: RED.** `RED`. Expected: "value of type 'AppLaunchManager' has no member 'beginDeferredSession'".
- [ ] **Step 3: Implement** the properties and `beginDeferredSession`, and call it from `performDeferredLoading`.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with the four new methods plus the six from Task 4. Expected: 10 passed.
- [ ] **Step 5: Commit** `[P1-T5] Restore the community before the launch sync; load memberships after` with `AppLaunchManager.swift`, `AppLaunchManagerTests.swift`.

---

### Task 6: `recheckAccountStatus` on foreground

**Model:** opus · **Files:**
- Modify: `NaarsCars/App/AppLaunchManager.swift:192-206` (replace `recheckBanStatus`), `beginDeferredSession` (Task 5). `checkAccountStatus` (:223-279) stays **byte-identical** (spec §3.7: untouched; CLAUDE.md Refactor rules 2-3: no refactor in the same diff as a fragile-system behaviour change).
- Modify: `NaarsCars/App/ContentView.swift:135-144`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift`

**Interfaces:**
- Produces:

```swift
struct AccountStatusFlags: Equatable, Sendable { let isBanned: Bool; let approved: Bool; let applicationComplete: Bool }
nonisolated static func authState(for flags: AccountStatusFlags) -> AuthState   // the mapping at :259-267
var fetchAccountStatus: ((UUID) async throws -> AccountStatusFlags)?  // nil → fetchAccountStatusFlags(userId:)
var sessionUserId: (() async throws -> UUID)?                          // nil → supabase.auth.session.user.id
private func fetchAccountStatusFlags(userId: UUID) async throws -> AccountStatusFlags
    // its own throwing read: the same select("is_banned, approved, application_complete").eq("id").single() as :243-249,
    // decoded into a private Decodable with the same CodingKeys, mapped to AccountStatusFlags; errors propagate
func recheckAccountStatus() async
```
- `checkAccountStatus` is not edited and keeps "a failed read answers `.needsApplication`" at launch (:268-278). `authState(for:)` repeats its five-line mapping (:259-267) for the re-check only; consolidating the two is a follow-up refactor in its own diff, listed in the task report.
- `recheckAccountStatus()`: return unless `state == .ready(.authenticated)`; read the flags with the throwing read; **on any error log and return** (a failed read must never eject a member, spec §10 "found while revising"); compute the new `AuthState`; return if it is `.authenticated` or if `state` changed during the await; otherwise set `state = .ready(newState)` directly, with no `.checkingAuth` hop (as the ban path does today).
- `beginDeferredSession` sets `communityContext.onActiveMembershipsEmpty = { [weak self] in await self?.recheckAccountStatus() }`.
- `ContentView` (:137-139) replaces `recheckBanStatus()` with `await launchManager.recheckAccountStatus(); await CommunityContext.shared.refreshMembershipsIfStale()` in the same `Task`.
- Behaviour change for the PR's Impact Summary: a member whose approval is revoked server-side leaves the main UI on the next foreground, not the next launch.

- [ ] **Step 1: Write the failing tests** (spec §4 "recheckAccountStatus with each flag combination and with a failed read"), injecting `sessionUserId = { uid }` and `fetchAccountStatus`:

```swift
func testRecheck_BannedMovesToBanned()                       // (true, true, true) → .ready(.banned)
func testRecheck_ApprovedStaysAuthenticated()                // (false, true, true) → .ready(.authenticated)
func testRecheck_NoApplicationMovesToNeedsApplication()      // (false, false, false) → .ready(.needsApplication)
func testRecheck_PendingMovesToPendingApproval()             // (false, false, true) → .ready(.pendingApproval)
func testRecheck_FailedReadIsANoOp()                         // fetch throws → .ready(.authenticated)
func testRecheck_DoesNothingUnlessAuthenticated()            // state .ready(.pendingApproval); fetch closure records a call → not called
```
- [ ] **Step 2: RED.** `RED`. Expected: "has no member 'recheckAccountStatus'".
- [ ] **Step 3: Implement** the flags, the mapping, the seams, `fetchAccountStatusFlags`, the re-check, the wiring and the `ContentView` call; delete `recheckBanStatus` (its only caller is `ContentView.swift:139`). Confirm `git diff -U0 NaarsCars/App/AppLaunchManager.swift` shows no hunk inside `checkAccountStatus` (:223-279).
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with the six methods plus Tasks 4–5's ten. Expected: 16 passed.
- [ ] **Step 5: FULL.** Expected: exit 0, 0 failures.
- [ ] **Step 6: Commit** `[P1-T6] Re-check account status on foreground, acting only on a successful read` with `AppLaunchManager.swift`, `ContentView.swift`, `AppLaunchManagerTests.swift`.

---

### Task 7: `.enterApp` guard and the waiting screen's relaunch

**Model:** opus · **Files:**
- Modify: `NaarsCars/App/AppLaunchManager.swift` (add `handleEnterAppIntent`)
- Modify: `NaarsCars/App/AppDelegate.swift:386-390`
- Modify: `NaarsCars/Features/Authentication/Views/PendingApprovalView.swift:155-157, 268-270`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift`

**Interfaces:**
- Produces: `func handleEnterAppIntent() async` on `AppLaunchManager`: when `state == .ready(.authenticated)`, start `Task { await communityContext.refreshMemberships() }` and call `NavigationCoordinator.shared.applyPushDeepLink(.enterApp)` (which sets `pendingIntent = .dashboard`, `App/NavigationCoordinator.swift:217-218`), and do not relaunch; in every other state `await performCriticalLaunch()` as today (spec §3.7, D22).
- `AppDelegate` `.enterApp` case calls `await AppLaunchManager.shared.handleEnterAppIntent()` inside its existing `Task { @MainActor in … }`.
- `PendingApprovalView`: both `launchManager.state = .ready(.authenticated)` lines become `Task { @MainActor in await AppLaunchManager.shared.performCriticalLaunch() }` followed by `return`. The unstructured `Task` is required (Review Focus 2): the screen leaves the hierarchy when the state becomes `.checkingAuth`, which would cancel a call made from its `.task` and end in `.ready(.unauthenticated)`. This runs `performDeferredLoading`, which the direct state write skipped (open finding gap-3-5).

- [ ] **Step 1: Write the failing test** (spec §4 routing: "`.enterApp` while authenticated does not change the launch state"). `NavigationCoordinatorRoutingTests`' `setUp` / `tearDown` (:15-25) only reset the coordinator today; extend them:

```swift
private var suiteName = ""
private var suite: UserDefaults!
private var savedLaunchState: LaunchState!                   // AppLaunchManager.swift:14, :59
private var savedCommunityContext: CommunityContext!

override func setUp() {
    super.setUp()
    coordinator.resetNavigation(); coordinator.selectedTab = .requests        // existing lines
    suiteName = "CommunityContextTests-\(UUID())"; suite = UserDefaults(suiteName: suiteName)!
    savedLaunchState = AppLaunchManager.shared.state
    savedCommunityContext = AppLaunchManager.shared.communityContext
}
override func tearDown() {
    AppLaunchManager.shared.state = savedLaunchState
    AppLaunchManager.shared.communityContext = savedCommunityContext
    suite.removePersistentDomain(forName: suiteName)
    coordinator.resetNavigation(); coordinator.selectedTab = .requests        // existing lines
    super.tearDown()
}

func testEnterAppWhileAuthenticated_DoesNotRelaunch() async {
    let launch = AppLaunchManager.shared
    launch.communityContext = CommunityContext(service: StubCommunityService(result: .success([])), defaults: suite)
    launch.state = .ready(.authenticated)
    await launch.handleEnterAppIntent()
    XCTAssertEqual(launch.state, .ready(.authenticated))
    XCTAssertEqual(coordinator.pendingIntent, .dashboard)
}
```
- [ ] **Step 2: RED.** `RED`. Expected: "has no member 'handleEnterAppIntent'".
- [ ] **Step 3: Implement** the method, the `AppDelegate` call and the two `PendingApprovalView` edits.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/NavigationCoordinatorRoutingTests`. Expected: all pass.
- [ ] **Step 5: FULL.** Expected: exit 0, 0 failures.
- [ ] **Step 6: Commit** `[P1-T7] Do not relaunch an authenticated session on .enterApp; relaunch properly on approval` with `AppLaunchManager.swift`, `AppDelegate.swift`, `PendingApprovalView.swift`, `NavigationCoordinatorRoutingTests.swift`.

**Capture list (Task 22):** none (`PendingApprovalView` has a `#Preview` and no visual change).

---

### Task 8: `entityIdKey` fix, zero-row-tolerant post fetch, push refresh plan

**Model:** opus · **Files:**
- Modify: `NaarsCars/Core/Models/AppNotification.swift:190-191`
- Create (Xcode MCP, app target): `NaarsCars/Core/Protocols/TownHallPostFetching.swift`
- Modify: `NaarsCars/Core/Services/TownHallService.swift:36-68` (`fetchPosts`, `fetchPostsPage`), `:90-100` (`fetchPost`), `:344-373` (reuse `enrichPosts`)
- Modify: `NaarsCars/Core/Storage/TownHallSyncEngine.swift:14-29, 54-86`
- Modify: `NaarsCars/Core/Storage/BackgroundSyncActor.swift` (new method after `upsertPostWithChangeDetection`, :1022-1056)
- Modify: `NaarsCars/Core/Services/PushNotificationService.swift:791-824`
- Modify: `NaarsCars/NaarsCarsTests/Core/Models/NotificationTypeDomainMappingTests.swift:67-76`
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/WebhookFixtures.swift:10-50`, `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/PushNotificationServiceTests.swift`

**Interfaces:**
- `NotificationType.entityIdKey` returns `"town_hall_post_id"` for `.townHallPost`, `.townHallComment`, `.townHallReaction`. Behaviour change for the Impact Summary: a Town Hall push now calls `performTargetedRefresh(.townHall, entityId:)` instead of `invalidate([.townHall])` (`PushNotificationService.swift:812-818`; the background path `AppDelegate.swift:318-342` follows automatically).
- Produces:

```swift
protocol TownHallPostFetching: AnyObject {
    func fetchPostsPage(limit: Int, offset: Int, communityId: UUID?) async throws -> (posts: [TownHallPost], serverCount: Int)
    func fetchPost(id: UUID) async throws -> TownHallPost?
}
extension TownHallService: TownHallPostFetching {}   // in TownHallService.swift
```
- `TownHallService.fetchPostsPage(limit: Int = 20, offset: Int = 0, communityId: UUID? = nil)` builds `var query = …select()`, adds `.eq("community_id", value: communityId.uuidString)` only when non-nil, then `.order("created_at", ascending: false).range(…)` (spec §3.7 Town Hall piece 1). `fetchPosts(limit:offset:)` passes nil (its test caller `TownHallServiceTests.swift:33` stays).
- `fetchPost(id:) -> TownHallPost?`: `.eq("id").limit(1).execute()`, decode `[TownHallPost]` with `createDateDecoder()`, return nil for zero rows **or** when the author is in `MessageService.shared.cachedBlockedUserIds` (the page fetch drops those too, :60-64), otherwise return `await enrichPosts([post], userId: AuthService.shared.currentUserId).first` so a targeted upsert keeps the author snapshot and comment count (Review Focus 1).
- Produces: `func deletePostWithChangeDetection(id: UUID) throws -> RefreshMetrics` on `BackgroundSyncActor` (deletes the row if present; `recordsDeleted` 1 or 0; saves only when it deleted).
- `TownHallSyncEngine.init(repository: TownHallRepository? = nil, postFetcher: (any TownHallPostFetching)? = nil, commentService: TownHallCommentService? = nil)` (replaces the `townHallService:` parameter; the only construction is `.shared`). `performFullSync` calls `postFetcher.fetchPostsPage(limit: Constants.PageSizes.townHall, offset: 0, communityId: nil).posts` (Task 9 supplies the scope). `performTargetedSync`: when `fetchPost` returns nil, delete the local row (through `deletePostWithChangeDetection`, or `repository.deletePost(id:)` when no actor), post `.townHallPostsDidSync` only if a row was deleted, record success and return the metrics — **never throw**, so the domain stays out of backoff (spec §3.7 Notifications 3).
- Produces in `PushNotificationService.swift`:

```swift
struct PushRefreshPlan: Equatable {
    let domains: Set<RefreshDomain>; let entityId: UUID?; let refreshesMemberships: Bool
    static let membershipRefreshTypes: Set<NotificationType> = [.userApproved, .userRejected, .accountRestricted, .pendingApproval]
    static func make(userInfo: [AnyHashable: Any]) -> PushRefreshPlan?   // nil when "type" is missing or unknown
}
```
`handlePushReceived` uses the plan (same coordinator calls as today) and, when `refreshesMemberships`, adds `await CommunityContext.shared.refreshMemberships()` in the same main-actor `Task` (spec §3.7 "Later refreshes").
- Fixtures: `WebhookFixtures.communityId`, `notificationPushPayloadWithCommunity` (today's `notificationPushPayload` plus `"community_id"`), `townHallPostPushPayload` (`type: town_hall_post`, `town_hall_post_id: postId`, `community_id: communityId`), `townHallCommentPushPayload` (no `community_id`). `CommunityFixtures` gains `StubTownHallPostFetcher: TownHallPostFetching` (`pagesByCommunity: [UUID?: [TownHallPost]]`, `postsById: [UUID: TownHallPost]`, `private(set) var requestedCommunityIds: [UUID?]`; offset 0 returns the page and its count, other offsets return empty) and `static func post(_ id: UUID, community: UUID?, createdAt: Date) -> TownHallPost`.

- [ ] **Step 1: Write the failing tests.** Correct `testEntityIdKeyPresent` (:72-73) to expect `"town_hall_post_id"` and add `.townHallReaction`. In `PushNotificationServiceTests`:

```swift
func testRefreshPlan_TownHallPostTargetsThePost() {
    let plan = PushRefreshPlan.make(userInfo: WebhookFixtures.townHallPostPushPayload)
    XCTAssertEqual(plan?.domains, [.townHall]); XCTAssertEqual(plan?.entityId, WebhookFixtures.postId)
}
func testRefreshPlan_TownHallCommentWithoutCommunityStillTargets()   // entityId == postId
func testRefreshPlan_RideWithCommunityKeyIsUnchanged()               // notificationPushPayloadWithCommunity → [.dashboard], rideId, refreshesMemberships false
func testRefreshPlan_UserApprovedRefreshesMemberships()              // ["type": "user_approved"] → true
@MainActor func testTargetedSync_UnreadablePostDeletesLocalRowWithoutThrowing() async throws {
    // in-memory container seeded with SDTownHallPost(id: p); engine = TownHallSyncEngine(repository: TownHallRepository(), postFetcher: StubTownHallPostFetcher())
    // engine.setupBackgroundActor(container:); let m = try await engine.performTargetedSync(entityId: p)
    // XCTAssertEqual(m.recordsDeleted, 1); row gone; a second call returns m.savedToStore == false
}
```
- **What stands in for "leaves `.townHall` out of backoff" (spec §4 push-to-coordinator row).** `RefreshCoordinator` builds its engines from `.shared` and cannot take a stub, and `RefreshCoordinator.swift` is not edited (Global Constraints). The domain goes to `.failed(retryAfter:…)` only from the `catch` at `RefreshCoordinator.swift:259` → :317, that is, only when the engine throws. `testTargetedSync_UnreadablePostDeletesLocalRowWithoutThrowing` therefore uses "does not throw" as the proxy for "no backoff". That `handlePushReceived` calls `performTargetedRefresh(.townHall, entityId:)` for a `town_hall_post_id` payload is checked two ways: `testRefreshPlan_*` pins the plan it acts on, and Step 4 below checks the call in code. Task 22 step 6 checks it end to end.
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'PushRefreshPlan' in scope".
- [ ] **Step 3: Implement** the key fix, the protocol file (Xcode MCP), the service changes, the actor method, the engine changes, the plan and its use in `handlePushReceived`, and the fixtures.
- [ ] **Step 4: Code check.** In `handlePushReceived` (`PushNotificationService.swift:791-824`), confirm that every non-nil `plan.entityId` reaches `RefreshCoordinator.shared.performTargetedRefresh(domain, entityId:, trigger:)` for each domain in `plan.domains`, that `invalidate` is used only when `entityId` is nil (today's fallback), and that the `.badges` targeted refresh at :822 still runs for every push. Quote the resulting lines in the task report.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/NotificationTypeDomainMappingTests -only-testing:NaarsCarsTests/PushNotificationServiceTests -only-testing:NaarsCarsTests/WebhookPayloadDecodingTests`. Expected: all pass (the session-gated token cases skip).
- [ ] **Step 6: FULL.** Expected: exit 0, 0 failures.
- [ ] **Step 7: Commit** `[P1-T8] Target Town Hall pushes by town_hall_post_id; tolerate unreadable posts` with `AppNotification.swift`, `NaarsCars/Core/Protocols/TownHallPostFetching.swift`, `TownHallService.swift`, `TownHallSyncEngine.swift`, `BackgroundSyncActor.swift`, `PushNotificationService.swift`, `NotificationTypeDomainMappingTests.swift`, `WebhookFixtures.swift`, `CommunityFixtures.swift`, `PushNotificationServiceTests.swift` and `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`.

---

### Task 9: Town Hall store scoping — engine scope, scoped repository reads

**Model:** opus · **Files:**
- Modify: `NaarsCars/Core/Storage/TownHallRepository.swift:23-89` (`getPosts`, `getPostsPublisher`, `upsertPosts`; add the two types at file scope)
- Modify: `NaarsCars/Core/Storage/TownHallSyncEngine.swift:21-29, 54-70`
- Modify: `NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift:72, 127, 220-228` (mechanical call-site updates only)
- Test: `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift`

**Interfaces:**
- Produces (in `TownHallRepository.swift`):

```swift
enum TownHallSyncScope: Equatable, Sendable {
    case unfiltered, community(UUID)
    init(communityId: UUID?); var communityId: UUID? { get }
    static let userInfoKey = "townHallSyncScope"
}
struct TownHallPostsEmission { let posts: [TownHallPost]; let syncedScope: TownHallSyncScope? }  // nil = targeted or repository write
func getPosts(communityId: UUID?) throws -> [TownHallPost]
    // nil → today's query; non-nil → predicate `communityId == target || communityId == nil` (compare against a captured `UUID?` local)
func getPostsPublisher(communityId: @escaping @MainActor () -> UUID?) -> AnyPublisher<TownHallPostsEmission, Never>
    // on .townHallPostsDidSync: posts = getPosts(communityId: communityId()) read at emission time; syncedScope from userInfo[TownHallSyncScope.userInfoKey]
func upsertPosts(_ posts: [TownHallPost], replaceAll: Bool = false, syncScope: TownHallSyncScope? = nil) throws
    // posts .townHallPostsDidSync with userInfo [userInfoKey: syncScope] when non-nil
```
- `TownHallSyncEngine.init` gains `communityScope: (@MainActor () -> UUID?)? = nil` (nil → `{ CommunityContext.shared.communityTabId }`). `performFullSync` reads the scope **once at fetch start** (spec §3.7 Town Hall piece 2), passes it to `fetchPostsPage`, keeps "prune every local post absent from the page", and posts `.townHallPostsDidSync` with `userInfo: [TownHallSyncScope.userInfoKey: TownHallSyncScope(communityId: scope)]`; the no-actor fallback passes `syncScope:` to `upsertPosts(…, replaceAll: true, …)`. Targeted upserts and deletes post without a scope (`.townHallPostsDidSync` contract, spec §5 `NSNotification.Name` row).
- `TownHallFeedViewModel` in this task only compiles against the new API with unchanged behaviour: `getPosts(communityId: nil)` at :72 and :127; `bindPosts` subscribes with `communityId: { nil }` and uses `emission.posts`.

- [ ] **Step 1: Write the failing tests** (spec §4 "Town Hall scoping", repository half):

```swift
func testGetPosts_NilCommunityReturnsEveryRow()                       // rows A, B, nil → 3
func testGetPosts_CommunityReturnsMatchingAndUnlabelledButNotOther()  // getPosts(communityId: A) ids == [a, unlabelled]
func testFullSync_FetchesTheScopeAndStampsItOnTheNotification() async throws
    // engine(postFetcher: stub with pagesByCommunity[A], communityScope: { A }); expectation(forNotification: .townHallPostsDidSync)
    // → stub.requestedCommunityIds == [A]; userInfo scope == .community(A)
```
- [ ] **Step 2: RED.** `RED`. Expected: "extra argument 'communityId' in call".
- [ ] **Step 3: Implement** the repository and engine changes and the mechanical feed call sites.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityStoreScopingTests -only-testing:NaarsCarsTests/PushNotificationServiceTests/testTargetedSync_UnreadablePostDeletesLocalRowWithoutThrowing`. Expected: all pass.
- [ ] **Step 5: Commit** `[P1-T9] Scope the Town Hall full sync and repository reads by community`.

---

### Task 10: Town Hall feed — active community, switch and the joined-sync guard

**Model:** opus · **Files:**
- Modify: `NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift:29-62, 67-91, 94-119, 121-131, 220-228, 276-321`
- Test: `NaarsCars/NaarsCarsTests/Features/TownHall/TownHallFeedViewModelTests.swift`

**Interfaces:**
- Consumes: `TownHallPostFetching`, `StubTownHallPostFetcher` (Task 8); `getPosts(communityId:)`, `getPostsPublisher(communityId:)`, `upsertPosts(_:replaceAll:syncScope:)`, `TownHallSyncScope` (Task 9); `CommunityContext.communityTabId` (Task 4).
- Produces:

```swift
init(repository: TownHallRepository? = nil, townHallService: TownHallService? = nil, voteService: TownHallVoteService? = nil,
     authService: any AuthServiceProtocol = AuthService.shared, messageService: any MessageServiceProtocol = MessageService.shared,
     postFetcher: (any TownHallPostFetching)? = nil,            // nil → TownHallService.shared (page and single-post reads)
     communityContext: CommunityContext? = nil,                  // nil → .shared
     refreshTownHall: (@MainActor (String) async -> RefreshResult?)? = nil)  // nil → RefreshCoordinator.shared.forceFullRefreshAndWait(.townHall, trigger:)
private(set) var activeCommunityId: UUID?    // initialised from communityContext.communityTabId
func activeCommunityDidChange() async
```
- `townHallService` stays for delete and vote; page reads (:101, :283) go through `postFetcher` with `communityId: activeCommunityId`; `loadPosts` / `refreshPosts` read `getPosts(communityId: activeCommunityId)`.
- A private `generation: Int` is captured at the start of `refreshFromNetwork` and `loadMore`; results that come back after `generation` moved are dropped before touching `posts`, `error`, `bannerMessage` or paging. `refreshFromNetwork` records the enrichment page's ids in a private `lastEnrichmentPostIds: [UUID]`.
- `bindPosts` subscribes with `communityId: { [weak self] in self?.activeCommunityId }` and **ignores an emission whose `syncedScope` is non-nil and whose `communityId` differs from `activeCommunityId`** (nil equals nil); unscoped emissions apply as today. This is what keeps a sync that started for A from blanking B through `keepingPagedPosts`' empty-store rule (:246-259).
- `activeCommunityDidChange()` algorithm:

```text
new = communityContext.communityTabId; guard new != activeCommunityId else return
wasUnfiltered = (activeCommunityId == nil); activeCommunityId = new; generation += 1
if wasUnfiltered:                       # launch resolution nil → X: same rows for a one-community member
    await refreshFromNetwork(showLoading: false, trigger: "communityResolved"); return
gen = generation
posts = []; currentOffset = 0; hasMore = true; firstPageIsWholeFeed = false; error = nil; isLoading = true
await refreshFromNetwork(showLoading: false, trigger: "communitySwitch")
guard gen == generation; isLoading = false
for _ in 1...2:                         # store reconciliation, decided from a repository read (spec §3.7 joined-sync rule)
    stored = Set(getPosts(communityId: activeCommunityId).map(\.id))
    if Set(lastEnrichmentPostIds).isSubset(of: stored): break
    _ = await refreshTownHall("communitySwitch:retry"); guard gen == generation else return
```
No `reset()`, no `invalidate`, no store wipe, no engine call.

- [ ] **Step 1: Write the failing tests** (spec §4 "Town Hall scoping", ViewModel half). Build an in-memory container, `TownHallRepository().setup(modelContext:)`, a `CommunityContext` on a suite, and `StubTownHallPostFetcher` with pages for A (`a1, a2`), B (`b1, b2`) and nil (`a1, a2`):

```swift
func testSwitchWhileSyncForPreviousCommunityInFlight_EndsOnNewCommunity() async throws {
    // refreshTownHall stub, keyed by trigger (it records every trigger in refreshTriggers):
    //   "manualReload:townHall" → upsertPosts(aPage, replaceAll: true, syncScope: .community(A)); return .completed(.empty)
    //   "communitySwitch"       → the joined sync that started for A: upsertPosts(aPage, replaceAll: true, syncScope: .community(A)); return .joined(inFlightTrigger: "launch")
    //   "communitySwitch:retry" → upsertPosts(bPage, replaceAll: true, syncScope: .community(B)); return .completed(.empty)
    // ctx.communityTabId = A; vm = TownHallFeedViewModel(repository: repo, postFetcher: stub, communityContext: ctx, refreshTownHall: refresher)
    // await vm.loadPosts(); record every vm.$posts value after b1 first appears
    // ctx.communityTabId = B; await vm.activeCommunityDidChange(); try await Task.sleep(for: .milliseconds(100))   // drain RunLoop.main deliveries
    XCTAssertEqual(Set(vm.posts.map(\.id)), [b1, b2])
    XCTAssertFalse(recordedAfterBArrived.contains { $0.isEmpty })
    XCTAssertEqual(Set(try repo.getPosts(communityId: B).map(\.id)), [b1, b2])
    XCTAssertEqual(refreshTriggers, ["manualReload:townHall", "communitySwitch", "communitySwitch:retry"])
}
func testNilToCommunityResolution_DoesNotClearTheList() async throws {
    // refreshTownHall stub (any trigger): upsertPosts(stub page for vm.activeCommunityId, replaceAll: true,
    //   syncScope: TownHallSyncScope(communityId: vm.activeCommunityId)); return .completed(.empty)
    // ctx.communityTabId = nil; await vm.loadPosts() → posts [a1, a2]; record values; ctx.communityTabId = A; await vm.activeCommunityDidChange()
    XCTAssertFalse(recorded.contains { $0.isEmpty }); XCTAssertEqual(Set(vm.posts.map(\.id)), [a1, a2])
}
```
- [ ] **Step 2: RED.** `RED`. Expected: "extra arguments 'postFetcher', 'communityContext', 'refreshTownHall'".
- [ ] **Step 3: Implement** the seams, `activeCommunityId`, the generation guard, the sink rule and `activeCommunityDidChange()`.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with the two new methods only (`-only-testing:NaarsCarsTests/TownHallFeedViewModelTests/<method>`; the old cases need the network). Expected: 2 passed.
- [ ] **Step 5: Commit** `[P1-T10] Switch the Town Hall feed by community without blanking on a joined sync`.

---

### Task 11: Community tab title menu

**Model:** opus · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/UI/Components/Common/CommunityTitleMenu.swift`
- Modify: `NaarsCars/Features/Community/Views/CommunityTabView.swift:11-67`
- Modify: `NaarsCars/Features/TownHall/Views/TownHallFeedView.swift:11-78`

**Interfaces:**
- Consumes: `CommunityContext` (`hasMultipleCommunities`, `activeMemberships`, `communityTabId`, `name(for:)`), `TownHallFeedViewModel.activeCommunityDidChange()` (Task 10).
- Produces (`CommunityTitleMenu.swift`, shared UI, used by this task and Task 17 so neither feature imports the other):

```swift
struct CommunityTitleMenuModifier<MenuContent: View>: ViewModifier {
    let enabled: Bool
    let subtitle: String?
    @ViewBuilder let menu: () -> MenuContent
    func body(content: Content) -> some View {
        if enabled, let subtitle {
            content.toolbarTitleMenu { menu() }.navigationSubtitle(subtitle)
        } else if enabled {
            content.toolbarTitleMenu { menu() }
        } else {
            content            // one membership: no toolbarTitleMenu, no navigationSubtitle at all
        }
    }
}
extension View {
    func communityTitleMenu<M: View>(enabled: Bool, subtitle: String? = nil, @ViewBuilder menu: @escaping () -> M) -> some View
}
```
  With `enabled == false` the modifier returns `content` unchanged, so the one-membership view tree has no title-menu chevron and no reserved subtitle line (Review Focus 3); this does not depend on how the default large-title mode treats an empty menu. Apply it to the same view that carries `.navigationTitle`. Flipping `enabled` changes that subtree's identity once, when a multi-community member's memberships finish loading; a one-community member never flips.
- `CommunityTabView` holds `@State private var communityContext = CommunityContext.shared`. Title: `community_title` with one membership, otherwise `communityContext.name(for: communityContext.communityTabId) ?? "community_title".localized`. `.communityTitleMenu(enabled: communityContext.hasMultipleCommunities) { ForEach(communityContext.activeMemberships) { m in Button { communityContext.communityTabId = m.communityId } label: { if selected { Label(m.name, systemImage: "checkmark") } else { Text(m.name) } } } }` (no empty `systemImage`), each row with `.accessibilityAddTraits(.isSelected)` when selected. The same row shape is used by Task 17's menu. The existing `.onChange(of: pendingIntent)` at :60-64 is unchanged (it matches without bindings).
- `TownHallFeedView` holds `@State private var communityContext = CommunityContext.shared` and adds `.onChange(of: communityContext.communityTabId) { _, _ in Task { await viewModel.activeCommunityDidChange() } }` (spec §3.7 "Switching"; the launch membership load also lands here).

- [ ] **Step 1: Create** `CommunityTitleMenu.swift` via the Xcode MCP (Global Constraints), with a `#Preview` showing a `NavigationStack` titled `"community_title".localized` in both states (`enabled: false` and `enabled: true` with two rows).
- [ ] **Step 2: Implement** both views (no new strings: community names are data; `community_title` exists).
- [ ] **Step 3: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/TownHallFeedViewModelTests/testSwitchWhileSyncForPreviousCommunityInFlight_EndsOnNewCommunity`. Expected: pass.
- [ ] **Step 4: Commit** `[P1-T11] Add the Community tab's community title menu` with `NaarsCars/UI/Components/Common/CommunityTitleMenu.swift`, `CommunityTabView.swift`, `TownHallFeedView.swift` and `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`.

**Capture list (Task 22):** Community tab, one and three memberships, menu closed and open, light / dark / AX5. `#Preview`: `CommunityTabView`, `TownHallFeedView`, `CommunityTitleMenu` (yes).

---

### Task 12: `community_id` on Town Hall push and bell-row targets

**Model:** opus · **Files:**
- Modify: `NaarsCars/Core/Utilities/DeepLinkParser.swift:16-17, 73-82, 114-117`
- Modify: `NaarsCars/App/NavigationIntent.swift:21`
- Modify: `NaarsCars/App/NavigationCoordinator.swift:19, 96-104, 183-187, 248-252, 319-321, 399-405`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift:80, 124-127, 142-144`
- Modify: `NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift` (add `open` and the action), `NaarsCars/Features/TownHall/Views/TownHallFeedView.swift:61-78, 170-192`
- Modify: `NaarsCars/NaarsCarsTests/Core/Decoding/WebhookPayloadDecodingTests.swift:49`
- Create (normal tools, not in any target): `Docs/qa/push-fixtures/town_hall_post_with_community.apns`, `town_hall_comment_without_community.apns`, `town_hall_post_foreign_community.apns`
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/DeepLinkParserTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift`, `NaarsCars/NaarsCarsTests/Features/TownHall/TownHallFeedViewModelTests.swift` (+ `CommunityFixtures.swift`)

**Interfaces:**
- `DeepLink.townHallPostComments(id: UUID, communityId: UUID? = nil)`, `.townHallPostHighlight(id: UUID, communityId: UUID? = nil)`; the parser reads `(userInfo["community_id"] as? String).flatMap(UUID.init)` for `town_hall_post`, `town_hall_comment`, `town_hall_reaction` and the `content_hidden` post branch.
- `NavigationIntent.townHallPost(UUID, mode: …Mode = .openComments, communityId: UUID? = nil)`; `NotificationIntent.openTownHallPost(postId: UUID, mode: …Mode, communityId: UUID? = nil)`; `TownHallNavigationTarget` gains `var communityId: UUID? = nil`. Constructions keep compiling through the defaults; the **binding** sites are edits: `NavigationCoordinator.swift:183-187, 248-249, 319-320, 399-405`, `TownHallFeedView.swift:174`, `DeepLinkParserTests.swift:122`, `WebhookPayloadDecodingTests.swift:49` (spec §3.7 Navigation). `AppDelegate.swift:381-384` and `CommunityTabView.swift:61` match without bindings and are unchanged.
- `NotificationNavigationRouter` passes `communityId: notification.communityId` (field from Task 2) at the announcement-with-post case, the post / comment / reaction cases and `content_hidden`.
- Produces on `TownHallFeedViewModel`:

```swift
enum TownHallFeedAction: Equatable { case scrollAndOpenComments(UUID), scrollAndHighlight(UUID), openComments(UUID), unavailable }
@Published private(set) var pendingFeedAction: TownHallFeedAction?
func open(_ target: NavigationCoordinator.TownHallNavigationTarget) async
func consumeFeedAction()
```
`open` holds the target and: (1) resolves the community — `target.communityId` when it is one of `communityContext.activeMemberships`, otherwise `postFetcher.fetchPost(id:)`; nil → publish `.unavailable` and stop (Review Focus 4); (2) when the resolved community is an active membership different from `activeCommunityId`, set `communityContext.communityTabId` and `await activeCommunityDidChange()` (the view's `onChange` then finds no difference); (3) resolves: the post is in `posts` → `.scrollAndOpenComments` / `.scrollAndHighlight` by mode; else, once the current generation has finished a `refreshFromNetwork`, `.openComments(id)` (the sheet loads by id); else waits — `refreshFromNetwork` re-runs the resolution at its end. "Finished" means **either outcome**: `refreshFromNetwork` marks the generation finished and re-runs the pending-target resolution on success **and** on failure (offline, server error), in a `defer`-style tail that runs after `posts` / `error` are set and is skipped only when the generation moved. On failure the post is usually not in `posts`, so the result is `.openComments(id)` and the comments sheet shows its own load error; a held target never waits forever. (If step 1's `fetchPost` itself throws, treat it like nil only when `target.communityId` is also nil: publish `.unavailable`; otherwise use `target.communityId` as given.)
- `TownHallFeedView`: the `pendingIntent` handler moves from `postsListView` (:173-192) to the outer body, keeps `initial: true`, and does `if let target = navigationCoordinator.consumeTownHallNavigationTarget() { Task { await viewModel.open(target) } }` (consumed exactly once, in the same pass). The outer body handles `.openComments` (→ `openCommentsTarget`) and `.unavailable` (→ `toastMessage = "moderation_content_unavailable".localized`); `postsListView` handles the two scroll actions with today's `proxy.scrollTo` / `highlightPost`; each handler calls `viewModel.consumeFeedAction()` for the cases it owns. Both use `.onChange(of: viewModel.pendingFeedAction, initial: true)`.
- Push fixtures (JSON, keys `aps`, `type`, `town_hall_post_id`, `community_id`; placeholders `<POST_ID>` and `<COMMUNITY_ID>` filled in Task 22; the foreign fixture uses `00000000-0000-4000-8000-000000000001` for both).

- [ ] **Step 1: Write the failing tests** (spec §4 routing, with and without `community_id` for the three Town Hall types and `content_hidden`):

```swift
// DeepLinkParserTests
func testParse_TownHallTypesCarryCommunityIdWhenPresent()   // for type in [post, comment, reaction]: parse → the case's communityId == c
func testParse_TownHallTypesWithoutCommunityIdParseAsBefore() // communityId == nil, id unchanged
func testParse_ContentHiddenTownHallPostCarriesCommunityId()  // with and without
// NavigationCoordinatorRoutingTests
func testApplyPushDeepLink_TownHallCommentsCarriesCommunityId() // pendingIntent == .townHallPost(p, mode: .openComments, communityId: c)
func testApplyPushDeepLink_TownHallHighlightWithoutCommunityId() // communityId nil
func testDeferredOpenTownHallPost_ConsumeCarriesCommunityId()    // consumeTownHallNavigationTarget()?.communityId == c
func testRouter_ContentHiddenBellRowCarriesCommunityId()         // NotificationNavigationRouter().notificationIntent(for: AppNotification(userId: u, type: .contentHidden, title: "t", townHallPostId: p, communityId: c))
                                                                 // == .openTownHallPost(postId: p, mode: .highlightPost, communityId: c)
// TownHallFeedViewModelTests (stubs only, no network)
func testOpen_RefreshFailureStillResolvesHeldTarget() async {
    // ctx with active membership A, communityTabId A; StubTownHallPostFetcher with failPages = true (every fetchPostsPage throws)
    // vm = TownHallFeedViewModel(repository: in-memory repo, postFetcher: stub, communityContext: ctx, refreshTownHall: { _ in nil })
    // await vm.open(TownHallNavigationTarget(postId: p, mode: .openComments, communityId: A)); await vm.refreshPosts()  // the refresh fails
    // XCTAssertEqual(vm.pendingFeedAction, .openComments(p))
}
```
`StubTownHallPostFetcher` (Task 8) gains `var failPages = false` (throws `URLError(.notConnectedToInternet)` from `fetchPostsPage` when set) in `CommunityFixtures.swift`.
- [ ] **Step 2: RED.** `RED`. Expected: "extra argument 'communityId' in call".
- [ ] **Step 3: Implement** the parser, the intent types, the coordinator and router edits, the binding-site test edits, `open` and the view hand-off; write the three fixture files.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/DeepLinkParserTests -only-testing:NaarsCarsTests/NavigationCoordinatorRoutingTests -only-testing:NaarsCarsTests/WebhookPayloadDecodingTests -only-testing:NaarsCarsTests/NavigationCoordinatorTests -only-testing:NaarsCarsTests/TownHallFeedViewModelTests/testOpen_RefreshFailureStillResolvesHeldTarget`. Expected: all pass.
- [ ] **Step 5: FULL.** Expected: exit 0, 0 failures.
- [ ] **Step 6: Commit** `[P1-T12] Carry community_id on Town Hall push and bell-row targets` with every modified file above, `TownHallFeedViewModelTests.swift`, `CommunityFixtures.swift` and `Docs/qa/push-fixtures/*.apns`.

**Capture list (Task 22):** the three push fixtures (Task 22 step 6). `#Preview`: `TownHallFeedView` (yes).

---

### Task 13: Community-aware leaderboard

**Model:** sonnet · **Files:**
- Modify: `NaarsCars/Core/Services/LeaderboardService.swift:64-81, 102-170`
- Modify: `NaarsCars/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift:28-114`
- Modify: `NaarsCars/Features/Leaderboards/Views/LeaderboardView.swift:14, 26-31`
- Test: `NaarsCars/NaarsCarsTests/Core/Decoding/CommunityPayloadDecodingTests.swift`, `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift`

**Interfaces:**
- `fetchLeaderboard(period: LeaderboardPeriod, communityId: UUID? = nil)` and `fetchSpotlights(period:communityId:)`: non-nil → `rpc("get_community_leaderboard" / "get_community_spotlights", params: CommunityLeaderboardParams(p_community_id: uuidString, start_date:, end_date:))` (a file-scope **internal** `struct CommunityLeaderboardParams: Encodable, Sendable` with a `nonisolated encode(to:)`, shaped like the private `LeaderboardParams` at :64-81; internal so the fixture test can encode it); nil → today's `get_xp_leaderboard` / `get_leaderboard_spotlights` (the server resolves the primary). Both return the same columns (`supabase/migrations/20261017_0003_communities_fanout.sql:944-950, 1108-1114, 1551-1555`), so `LeaderboardEntry` / `SpotlightEntry` are unchanged.
- `LeaderboardViewModel.init(authService:communityContext: CommunityContext? = nil)`; the cache (:31-35) is keyed by `struct LeaderboardCacheKey: Hashable { let period: LeaderboardPeriod; let communityId: UUID? }` (spec §3.7 "the cache key includes the community"); `displayedPeriod` becomes `displayedKey`; `func communityDidChange() async` runs `loadLeaderboard()`, whose existing "never leave another period's rows" rule (:61-65) now compares keys.
- `LeaderboardView` holds `@State private var communityContext = CommunityContext.shared` and adds `.onChange(of: communityContext.communityTabId) { Task { await viewModel.communityDidChange() } }`.

- [ ] **Step 1: Write the failing tests** (CLAUDE.md fixture-test gate: two new RPC call sites; spec §4 names no test here, which does not lift the gate). Add `CommunityFixtures.communityLeaderboardRowsJSON` (one row with the RPC's columns, `20261017_0003_communities_fanout.sql:944-950`: `user_id`, `name`, `avatar_url`, `xp`, `badges: ["<a raw value LeaderboardBadge accepts>"]`, `streak_weeks`, `requests_fulfilled`, `requests_made`) and:

```swift
func testCommunityLeaderboardParamsEncodeTheRPCKeys() throws {
    let data = try JSONEncoder().encode(CommunityLeaderboardParams(p_community_id: CommunityFixtures.communityA.uuidString, start_date: "2026-10-01", end_date: "2026-10-17"))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    XCTAssertEqual(Set(object.keys), ["p_community_id", "start_date", "end_date"])
    XCTAssertEqual(object["p_community_id"], CommunityFixtures.communityA.uuidString)
}
func testCommunityLeaderboardRowDecodesAsLeaderboardEntry() throws  // decoder LeaderboardService uses for get_xp_leaderboard → one entry, userId/name/xp match
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CommunityLeaderboardParams' in scope".
- [ ] **Step 3: Implement** the service, the ViewModel cache key and the view hook.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityPayloadDecodingTests -only-testing:NaarsCarsTests/LeaderboardViewModelTests`. Expected: `CommunityPayloadDecodingTests` 5 passed; `LeaderboardViewModelTests` pass or session-gated skips.
- [ ] **Step 5: Commit** `[P1-T13] Read the leaderboard and spotlights for the Community tab's community` with `LeaderboardService.swift`, `LeaderboardViewModel.swift`, `LeaderboardView.swift`, `CommunityPayloadDecodingTests.swift`, `CommunityFixtures.swift`.

**Capture list (Task 22):** Leaderboard segment with three memberships, light. `#Preview`: `LeaderboardView` (yes).

---

### Task 14: `get_badge_counts` payload keys

**Model:** opus · **Files:**
- Modify: `NaarsCars/Core/Services/BadgeCountManager.swift:322-341`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/BadgeCountManagerTests.swift`

**Interfaces:**
- `BadgeCountManager.BadgeCountsPayload` becomes internal (was `private struct`) and gains `let pendingMembersTotal: Int?`, `let communityDetails: [CommunityCountDetail]?`, `let total: Int?`, plus `static func decode(_ data: Data) throws -> BadgeCountsPayload` (the `.convertFromSnakeCase` decoder now inlined at :337-340); `fetchBadgeCounts` uses it. New nested `struct CommunityCountDetail: Decodable, Equatable { let communityId: UUID; let requestsTotal: Int; let communityTotal: Int; let bellTotal: Int }`. Nothing reads the new fields in Phase 1 (the Profile badge moves to `pendingMembersTotal` in Phase 2). Key names are the server's (`supabase/migrations/20261017_0003_communities_fanout.sql:2410-2438, 2794-2796`).

- [ ] **Step 1: Write the failing tests** (spec §4 "badges", each key present and absent):

```swift
func testBadgePayload_DecodesCommunityKeysWhenPresent() throws  // pending_members_total 2, community_details [{community_id, requests_total 1, community_total 3, bell_total 4}], total 9
func testBadgePayload_DecodesTodaysPayloadWithoutCommunityKeys() throws  // all three nil; existing totals intact
```
- [ ] **Step 2: RED.** `RED`. Expected: "'BadgeCountsPayload' is inaccessible due to 'private' protection level".
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/BadgeCountManagerTests`. Expected: all pass.
- [ ] **Step 5: FULL.** Expected: exit 0, 0 failures.
- [ ] **Step 6: Commit** `[P1-T14] Decode pending_members_total, community_details and total from get_badge_counts` with `BadgeCountManager.swift`, `BadgeCountManagerTests.swift`.

---

### Task 15: Reputation through `get_profile_stats`

**Model:** sonnet · **Files:**
- Create (normal tools): `scripts/add-localization-keys.py`
- Create (Xcode MCP, app target): `NaarsCars/Core/Models/ProfileStats.swift`
- Modify: `NaarsCars/Core/Protocols/ProfileServiceProtocol.swift:12-13`
- Modify: `NaarsCars/Core/Services/ProfileService.swift:378-396, 446-467, 550-552` (`ReviewRating` goes when unused)
- Modify: `NaarsCars/Features/Profile/ViewModels/PublicProfileViewModel.swift:16-21, 60-74`; `MyProfileViewModel.swift:16-22, 63-83`
- Modify: `NaarsCars/Features/Profile/Views/PublicProfileView.swift:265-285`; `NaarsCars/Features/Profile/Views/MyProfileView.swift:440-444`; `NaarsCars/Features/Reviews/Views/AllReviewsView.swift:10-14, 39-71`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`
- Test: `NaarsCars/NaarsCarsTests/Core/Decoding/CommunityPayloadDecodingTests.swift`, `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift`

**Interfaces:**
- `scripts/add-localization-keys.py <keys.json>`: input `{"key": {"en": …, "es": …, "ko": …, "vi": …, "zh-Hans": …, "zh-Hant": …}}`; refuses a key that exists or misses a locale; asserts first that re-serializing the unmodified catalog with `json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ' : '))` then `.replace('{}', '{\n\n    }')` reproduces the file byte for byte (it does today), then **inserts each new key at its sorted position** in `strings` instead of appending: before the first existing key `k` for which `k.casefold() > new.casefold()` (Xcode's order for snake_case keys; the catalog's 1,586 keys follow it except eight symbol or digit keys such as `messaging_mute_8_hours`, which the new `community_*` / `profile_*` keys never sit next to), rebuilding the dict in that order. Entries are `{"extractionState": "manual", "localizations": {lang: {"stringUnit": {"state": "translated", "value": v}}}}` in the locale order above; it writes without a trailing newline. After writing it re-reads the file and asserts that the key list equals the old list with the new keys inserted and that every old entry is unchanged. Xcode's next save of the catalog therefore moves nothing. Run with `python3 -I`. Key files live in `build/` (gitignored).
- Produces:

```swift
struct ProfileStats: Decodable, Equatable, Sendable {
    let averageRating: Double?; let reviewCount: Int; let fulfilledCount: Int
    init(averageRating: Double?, reviewCount: Int, fulfilledCount: Int)
    init(from decoder: Decoder) throws   // keys avg_rating, review_count, fulfilled_count via decodeIfPresent; missing → nil / 0 (the RPC answers {} when the viewer may not see the person)
}
// ProfileServiceProtocol: replace calculateAverageRating(userId:) and fetchFulfilledCount(userId:) with
func fetchProfileStats(userId: UUID) async throws -> ProfileStats   // rpc("get_profile_stats", params: ["p_user_id": userId.uuidString])
```
- `PublicProfileViewModel`: one `async let statsTask = profileService.fetchProfileStats(userId:)` replaces :63-64; adds `@Published var otherCommunityReviewCount = 0` = `max(0, stats.reviewCount - fetchedReviews.count)`. `MyProfileViewModel` likewise and adds `@Published var reviewCount = 0` (spec §3.7 "Reputation on profiles", D5). `fetchReviews(forUserId:)` (:311-376) stays a direct, RLS-scoped read.
- `PublicProfileView.reviewsSection` (:264-280) and `AllReviewsView` show, when the count is above zero, `Text(key.localized(with: n))` in `.naarsCaption` / `.secondary` under the list. **When the visible list is empty and the count is above zero, only that line is shown, not the "No reviews yet" `EmptyStateView`** (`reviews.isEmpty && otherCommunityReviewCount > 0` → the line alone; `reviews.isEmpty && count == 0` → today's empty state; the same rule in `AllReviewsView`'s empty branch, :32-39, where the line replaces the `EmptyStateView`), with `key = n == 1 ? "profile_more_reviews_other_communities_one" : "profile_more_reviews_other_communities_other"` (the two-key idiom of `Ride.seatsDisplayText`, `Core/Models/Ride.swift:102-106`). `AllReviewsView.init(userId: UUID, totalReviewCount: Int = 0)`; `MyProfileView` (:442) passes `viewModel.reviewCount`.
- Strings:

| Key | en | es | ko | vi | zh-Hans | zh-Hant |
|---|---|---|---|---|---|---|
| `profile_more_reviews_other_communities_one` | %lld more review in other communities | %lld reseña más en otras comunidades | 다른 커뮤니티의 리뷰 %lld개 더 있음 | Còn %lld đánh giá ở các cộng đồng khác | 其他社区还有 %lld 条评价 | 其他社區還有 %lld 則評價 |
| `profile_more_reviews_other_communities_other` | %lld more reviews in other communities | %lld reseñas más en otras comunidades | 다른 커뮤니티의 리뷰 %lld개 더 있음 | Còn %lld đánh giá ở các cộng đồng khác | 其他社区还有 %lld 条评价 | 其他社區還有 %lld 則評價 |

- [ ] **Step 1: Write the failing tests** (fixture-test gate, RPC seam): add `CommunityFixtures.profileStatsJSON` (`{"avg_rating": 4.5, "review_count": 3, "fulfilled_count": 7}`) and `profileStatsEmptyJSON` (`{}`), and

```swift
func testProfileStatsDecode()       // == ProfileStats(averageRating: 4.5, reviewCount: 3, fulfilledCount: 7)
func testProfileStatsEmptyObjectDecodesAsNothingVisible()  // == ProfileStats(averageRating: nil, reviewCount: 0, fulfilledCount: 0)
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'ProfileStats' in scope".
- [ ] **Step 3: Write `scripts/add-localization-keys.py`**; dry-run it on an empty key file and confirm `git diff --stat NaarsCars/Resources/Localizable.xcstrings` is empty.
- [ ] **Step 4: Implement** the model (Xcode MCP), the protocol and service change, both ViewModels and the three views; add the two keys with the script.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityPayloadDecodingTests`. Expected: 7 passed.
- [ ] **Step 6: Commit** `[P1-T15] Read rating, review and fulfilled counts from get_profile_stats` with `scripts/add-localization-keys.py`, `NaarsCars/Core/Models/ProfileStats.swift`, `ProfileServiceProtocol.swift`, `ProfileService.swift`, `PublicProfileViewModel.swift`, `MyProfileViewModel.swift`, `PublicProfileView.swift`, `MyProfileView.swift`, `AllReviewsView.swift`, `Localizable.xcstrings`, `CommunityPayloadDecodingTests.swift`, `CommunityFixtures.swift` and `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`. Also check every other conformer of `ProfileServiceProtocol` (test mocks: `grep -rln "ProfileServiceProtocol" NaarsCars/NaarsCarsTests`) is updated and staged.

**Capture list (Task 22):** none required by the spec (the line appears only for a person with reviews in a community the viewer is not in). `#Preview`: `PublicProfileView`, `MyProfileView` (yes); `AllReviewsView` (no).

---

### Task 16: Member search through `search_community_members`

**Model:** sonnet · **Files:**
- Modify: `NaarsCars/Core/Services/ProfileService+Search.swift:11-43`; `NaarsCars/Core/Protocols/ProfileServiceProtocol.swift:30`
- Modify: `NaarsCars/Features/Messaging/ViewModels/UserSearchViewModel.swift:32-90`
- Modify: `NaarsCars/UI/Components/Messaging/UserSearchView.swift:11-35, 46-48`
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift:313-316`; `NaarsCars/Features/Favors/Views/FavorDetailView.swift:301-304`
- Test: `NaarsCars/NaarsCarsTests/Core/Decoding/CommunityPayloadDecodingTests.swift`, `CommunityFixtures.swift`

**Interfaces:**
- Replaces `searchPublicProfiles(query:limit:)` (one caller) with `func searchCommunityMembers(query: String, communityId: UUID?, limit: Int) async throws -> [Profile]`: `rpc("search_community_members", params: SearchCommunityMembersParams(p_query:, p_community_id:, p_limit:))` — a private `Encodable` that omits `p_community_id` when nil (`encodeIfPresent`; the server default null means "the union of my communities") — decoded with `DateDecoderFactory.makeSupabaseDecoder()` into `[Profile]` (the RPC returns `public_profiles`' columns, `supabase/migrations/20261017_0005_communities_rpcs.sql:1904-1940`; `Profile`'s decoder defaults the rest). Blocks are filtered on the server; the client's `isBlocked` filter (:77) stays.
- `UserSearchViewModel.scheduleSearch(query:excludeUserIds:communityId: UUID?)` and `searchUsers(query:excludeUserIds:communityId:)`. `UserSearchView.init(…, communityId: UUID? = nil, onDismiss:)`. Callers: `RideDetailView` / `FavorDetailView` add-participants pass `ride.communityId` / `favor.communityId`; the two create forms pass nil until Task 20; `ConversationsListView` (new message) and `MessageDetailsPopup` keep the default nil (spec §3.7 "Member search").

- [ ] **Step 1: Write the failing test** (fixture-test gate): `CommunityFixtures.searchMemberRowsJSON` (one row: `id`, `name`, `avatar_url`, `car`, `approved`, `created_at`, `updated_at`) and `func testSearchCommunityMembersRowsDecodeAsProfiles()` (decodes one `Profile` with the fixture's id and name).
- [ ] **Step 2: RED/GREEN.** The test passes against the existing `Profile` decoder once written; then implement the service, protocol, ViewModel and view changes.
- [ ] **Step 3: BUILD; TEST** with `-only-testing:NaarsCarsTests/CommunityPayloadDecodingTests`. Expected: 8 passed.
- [ ] **Step 4: Commit** `[P1-T16] Search members through search_community_members` with every modified file above, `CommunityPayloadDecodingTests.swift`, `CommunityFixtures.swift` and any updated `ProfileServiceProtocol` test mock.

**Capture list (Task 22):** none (no visual change). `#Preview`: `UserSearchView` (yes).

---

### Task 17: Requests narrow and its title menu

**Model:** sonnet · **Files:**
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift:157-205, 207-226, 241-281`
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift:52-77, 234-251`
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift:13-62, 117-127`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`
- Test: `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift`

**Interfaces:**
- `fetchFilteredRides(in:filter:scope: RequestsScope = .all)`, `fetchFilteredFavors(in:filter:scope: RequestsScope = .all)`, `computeFilterBadgeCounts(in:requestNotificationSummaries:scope: RequestsScope = .all)` and the two in-memory filters apply `scope.includes(row.communityId)` after the existing predicate (spec §3.7 "Requests (merged)"; unlabelled rows stay visible). The fetches stay unfiltered: `DashboardSyncEngine` is not touched.
- `RequestsDashboardViewModel.init(…, communityContext: CommunityContext? = nil)` passes `communityContext.requestsScope` in `refreshFilteredRequests` / `refreshFilterBadgeCounts`; `func requestsScopeDidChange()` re-runs `refreshFilteredRequests()` (local only).
- Consumes: `.communityTitleMenu(enabled:subtitle:menu:)` (Task 11).
- `RequestsDashboardView` holds `@State private var communityContext = CommunityContext.shared`; adds `.communityTitleMenu(enabled: communityContext.hasMultipleCommunities, subtitle: narrowName) { Button("community_all_communities".localized) { scope = .all }; ForEach(activeMemberships) { Button(name) { scope = .community(id) } } }` with Task 11's row shape (checkmark `Label` and `.isSelected` on the selection), where `narrowName = communityContext.name(for: communityContext.requestsScope.communityId)` (nil for `.all`, so no subtitle modifier is applied), and `.onChange(of: communityContext.requestsScope) { viewModel.requestsScopeDidChange() }`. The bell and `+` toolbar items (:35-62) are unchanged. With one membership neither `toolbarTitleMenu` nor `navigationSubtitle` is applied (Review Focus 3).
- String:

| Key | en | es | ko | vi | zh-Hans | zh-Hant |
|---|---|---|---|---|---|---|
| `community_all_communities` | All communities | Todas las comunidades | 모든 커뮤니티 | Tất cả cộng đồng | 所有社区 | 所有社區 |

- [ ] **Step 1: Write the failing tests** (spec §4 "filters"), signed out so `.open` takes the guest path:

```swift
func testNarrowScope_KeepsScopedAndUnlabelledRides()   // rows A, B, nil; fetchFilteredRides(in:, filter: .open, scope: .community(A)) ids == [a, unlabelled]
func testNarrowScope_KeepsScopedAndUnlabelledFavors()
func testAllScope_KeepsEveryRow()
func testNarrowScope_BadgeCountsCountOnlyScopedRequests() // summaries: A ride and B ride unread 1 each → counts[.open] == 1 with scope .community(A), 2 with .all
```
- [ ] **Step 2: RED.** `RED`. Expected: "extra argument 'scope' in call".
- [ ] **Step 3: Implement**; add the key with the script.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityStoreScopingTests`. Expected: all pass.
- [ ] **Step 5: Commit** `[P1-T17] Add the optional Requests narrow` with `RequestFilterManager.swift`, `RequestsDashboardViewModel.swift`, `RequestsDashboardView.swift`, `Localizable.xcstrings`, `CommunityStoreScopingTests.swift`.

**Capture list (Task 22):** Requests dashboard, one and three memberships, menu open, narrowed, light / dark / AX5. `#Preview`: `RequestsDashboardView` (yes).

---

### Task 18: Community chips on cards, detail headers and edit screens

**Model:** sonnet · **Files:**
- Modify: `NaarsCars/UI/Components/Cards/RideCard.swift:11-13, 59-89, 126-130`; `FavorCard.swift:11-13, 59-90, 127-130`
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift:438-452`; `NaarsCars/Features/Requests/Views/PastRequestsView.swift:85`
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift:362-371`; `NaarsCars/Features/Favors/Views/FavorDetailView.swift:349-358`
- Modify: `NaarsCars/Features/Rides/Views/EditRideView.swift:27-28`; `NaarsCars/Features/Favors/Views/EditFavorView.swift:27-28`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityContext.chipText(for:respectingScope:)` (Task 4), `communityId` on the models (Task 2).
- `RideCard` / `FavorCard` gain `var communityChipText: String? = nil`; when set, `NaarsChip(text:tint: nil)` sits before the status chip in the header `HStack` (:126-130) with `.accessibilityLabel("community_chip_accessibility".localized(with: text))`, and the card's combined accessibility label appends the same phrase.
- `RequestCardView` gains `var respectsRequestsScope: Bool = true` and `@State private var communityContext = CommunityContext.shared`, and passes `chipText(for: ride.communityId, respectingScope: respectsRequestsScope)` in the `.ride` arm and `favor.communityId` in the `.favor` arm (`RequestItem` has no `communityId` of its own). `PastRequestsView` passes `respectsRequestsScope: false` (it chips whenever the person has two or more communities).
- Detail headers add the chip (`size: .large`) under the status chip with `respectingScope: true` (spec §3.7 "detail headers likewise": the card rule, so the chip is hidden while Requests is narrowed); the edit screens add a first `Section { NaarsChip(…) }` when the chip text is non-nil (read-only; `updateRide` / `updateFavor` never send `community_id`).
- Bell-row chips are Phase 4 (spec §4 Phase 4), not here.
- String:

| Key | en | es | ko | vi | zh-Hans | zh-Hant |
|---|---|---|---|---|---|---|
| `community_chip_accessibility` | Community: %@ | Comunidad: %@ | 커뮤니티: %@ | Cộng đồng: %@ | 社区：%@ | 社區：%@ |

- [ ] **Step 1: Implement** the cards, `RequestCardView`, `PastRequestsView`, details and edit screens; add a three-membership variant (`CommunityContext.shared.debugSetMemberships(…)` plus `communityChipText:`) to the `RideCard` and `FavorCard` previews; add the key.
- [ ] **Step 2: BUILD.** No test is named for chips in spec §4.
- [ ] **Step 3: Commit** `[P1-T18] Show a community chip when the person belongs to several communities` with every modified file above.

**Capture list (Task 22):** Requests dashboard (chips visible in three-membership mode), a ride detail, an edit-ride sheet, light / dark / AX5. `#Preview`: `RideCard`, `FavorCard`, `RideDetailView`, `FavorDetailView`, `EditRideView`, `EditFavorView` (yes); `PastRequestsView` (no).

---

### Task 19: "Former member" fallbacks

**Model:** sonnet · **Files:**
- Modify: `NaarsCars/UI/Components/Cards/RideCard.swift:80-84, 100-116, 194-215`; `FavorCard.swift:79-83, 99-115, 184-205`
- Modify: `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift:366-371`; `NaarsCars/Features/TownHall/Views/PostCommentsView.swift:127, 386-389, 893-…`
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift:357-371, 615-640`; `NaarsCars/Features/Favors/Views/FavorDetailView.swift:344-358, 505-530`
- Modify: `NaarsCars/UI/Components/Cards/ReviewCard.swift:28-46, 152-…`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Every row whose author, poster, helper (claimer) or reviewer profile is missing because that person is no longer visible shows `"community_former_member".localized` with `AvatarView(imageUrl: nil, name: "community_former_member".localized, size: <the row's size>)` (spec §3.7 "Cards and chips"): the card poster rows (today `common_unknown_user` / `"Unknown"`), the post author row (today `townhall_unknown_user`), the comment author and "replying to" (today `townhall_unknown`), the detail headers (today nothing: add the avatar and `ride_detail_requested_by` / `favor_detail_requested_by` with the fallback name), and `ReviewCard`'s reviewer (today `common_anonymous`). **Helper rows:** when `claimedBy != nil && claimer == nil`, the card's claimer row (`RideCard.swift:194-215` drops it today at :198; `FavorCard.swift:184-205` at :188), the detail claimer card (`RideDetailView.swift:617`, `FavorDetailView.swift:507`, which show nothing today) and the card's combined accessibility label (`RideCard.swift:82-84`, `FavorCard.swift:81-83`, which skip the phrase today) show `community_former_member` with the placeholder `AvatarView` (in the detail card a plain `AvatarView` replaces `UserAvatarLink`, since there is no profile to open). Strings that already fall back to `common_someone` (delete confirmation, the participant prompt) are unchanged. Existing keys stay in the catalog.
- Previews: add a nil-profile variant (nil poster) and a nil-claimer variant (`claimedBy` set, `claimer` nil) to the `RideCard` and `FavorCard` previews, a nil-profile variant to the `TownHallPostCard` and `ReviewCard` previews, and a `CommentRow` preview with `comment.author == nil` (`CommentRow` is internal at `PostCommentsView.swift:234`).
- String:

| Key | en | es | ko | vi | zh-Hans | zh-Hant |
|---|---|---|---|---|---|---|
| `community_former_member` | Former member | Exmiembro | 이전 멤버 | Cựu thành viên | 前成员 | 前成員 |

- [ ] **Step 1: Implement** the fallbacks and previews; add the key.
- [ ] **Step 2: BUILD.**
- [ ] **Step 3: Commit** `[P1-T19] Show "Former member" where a profile is no longer visible` with every modified file above.

**Capture list (Task 22):** each nil-profile preview (post card, comment, ride card, favor card, review card) and the two nil-claimer card previews, light / dark / AX5 via `RenderPreview`; the detail header and the detail claimer card are checked in code (a nil poster cannot be produced in the running app with one community).

---

### Task 20: "Post to" on the create forms; Town Hall post community

**Model:** sonnet · **Files:**
- Modify: `NaarsCars/Core/Protocols/RideServiceProtocol.swift:11-21`; `FavorServiceProtocol.swift:11-22`
- Modify: `NaarsCars/Core/Services/RideService.swift:120-160`; `FavorService.swift:120-166`; `TownHallService.swift:111-162`
- Modify: `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift:15-56, 164-186`; `NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift:29, 42-60, 155-205`
- Modify: `NaarsCars/Features/Rides/Views/CreateRideView.swift:66-69, 183-190, 209-233`; `NaarsCars/Features/Favors/Views/CreateFavorView.swift:66-69, 193-200, 219-245`
- Modify: `NaarsCars/Features/TownHall/ViewModels/CreatePostViewModel.swift:43-46, 84-88`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- `createRide(…, timezone: String, communityId: UUID?)` on the protocol; `RideService.createRide(…, communityId: UUID? = nil)` makes `rideData` a `var` and adds `"community_id"` only when non-nil (nil lets the fill trigger use the primary). Same for `createFavor`. `TownHallService.createPost(userId:content:imageUrl:communityId: UUID? = nil)` passes it to `TownHallPost(…, communityId:)` (encoded only when non-nil, Task 2). `updateRide` / `updateFavor` are unchanged.
- `CreateRideViewModel` / `CreateFavorViewModel`: `init(…, communityContext: CommunityContext? = nil)`; `@Published var selectedCommunityId: UUID?`; `@Published private(set) var communityOptions: [CommunityMembership] = []`; `var requiresCommunityChoice: Bool { communityOptions.count > 1 }`; `func configureCommunityChoice()` (options = `activeMemberships` when `hasMultipleCommunities`, else []; selection = `defaultPostCommunityId`); `selectedCommunityId` has a `didSet` that clears `selectedParticipantIds` when `requiresCommunityChoice`, `oldValue != nil` and the value changed (participants are searched within the selected community, so people picked for A may not be members of B and `addRideParticipants` / `addFavorParticipants` would fail under RLS; the initial selection from nil keeps them); `var postButtonTitle: String` (`"community_post_to_button".localized(with: name)` when the section shows, else today's `ride_create_post` / `favor_create_post`); `hasRequiredFields` adds `(!requiresCommunityChoice || selectedCommunityId != nil)` (spec: part of `hasRequiredFields`, `CreateRideViewModel.swift:53-56`); create passes `requiresCommunityChoice ? selectedCommunityId : nil` and on success sets `communityContext.lastPostedCommunityId`. The edit screens never call `configureCommunityChoice()`, so they are unaffected.
- Views: a first `Section("community_post_to_section".localized) { Picker("community_post_to_picker".localized, selection: $viewModel.selectedCommunityId) { ForEach(viewModel.communityOptions) { Text($0.name).tag(Optional($0.communityId)) } } }` above `ride_create_section_date_time` / `favor_create_section_title_description`, only when `requiresCommunityChoice`; the confirmation button uses `viewModel.postButtonTitle`, and when `requiresCommunityChoice` its `.accessibilityLabel` (`CreateRideView.swift:221`, `CreateFavorView.swift:231`) is `viewModel.postButtonTitle` so VoiceOver names the community (otherwise today's `ride_create_post_accessibility` / `favor_create_post_accessibility`); `configureCommunityChoice()` runs in the existing `.onAppear` (:183 / :193); `UserSearchView` gets `communityId: viewModel.requiresCommunityChoice ? viewModel.selectedCommunityId : nil` (Task 16).
- `CreatePostViewModel` takes `communityContext` and passes `communityContext.communityTabId` to `createPost` (spec: "A Town Hall post goes to the Community tab's community").
- Strings:

| Key | en | es | ko | vi | zh-Hans | zh-Hant |
|---|---|---|---|---|---|---|
| `community_post_to_section` | Post to | Publicar en | 게시할 커뮤니티 | Đăng lên | 发布到 | 發布到 |
| `community_post_to_picker` | Community | Comunidad | 커뮤니티 | Cộng đồng | 社区 | 社區 |
| `community_post_to_button` | Post to %@ | Publicar en %@ | %@에 게시 | Đăng lên %@ | 发布到%@ | 發布到%@ |

- [ ] **Step 1: Implement** services, protocols, both ViewModels, both views and `CreatePostViewModel`; add the keys.
- [ ] **Step 2: BUILD; TEST** with `-only-testing:NaarsCarsTests/CreateRideViewModelTests -only-testing:NaarsCarsTests/CreateFavorViewModelTests -only-testing:NaarsCarsTests/CreatePostViewModelTests` (signed out; their creates are session-gated). Expected: pass or skip.
- [ ] **Step 3: Commit** `[P1-T20] Ask "Post to" when the person belongs to several communities` with every modified file above and any updated `RideServiceProtocol` / `FavorServiceProtocol` test mock (`grep -rln "RideServiceProtocol\|FavorServiceProtocol" NaarsCars/NaarsCarsTests`).

  No unit test is added for the `community_id` insert key: the ride and favor insert dictionaries are built inline in network methods with no stub seam, and a nil community is resolved by the server's fill trigger. The Town Hall insert key is pinned by Task 2's `testTownHallPostEncode_OmitsNilCommunityIdAndWritesSetOne`. Recorded as a known gap in the task report.

**Capture list (Task 22):** both create forms, one and three memberships, light / dark / AX5 (AX5 also checks the long name in the button, Review Focus 5). `#Preview`: `CreateRideView`, `CreateFavorView`, `CreatePostView` (yes).

---

### Task 21: Documentation for Phase 1

**Model:** sonnet · **Files:**
- Modify: `CLAUDE.md` — State Management rule 2; Testing Expectations table, Auth row (append "zero-membership routing": `onActiveMembershipsEmpty` → `recheckAccountStatus`, spec §4 Phase 1 documentation row); Fragile system 4 and 7 and the Cross-Layer seams (`community_id` push key, `entityIdKey` = `town_hall_post_id`, Town Hall pushes do a targeted refresh, the three `get_badge_counts` keys); Fragile system 5 and Quick Reference "Auth state" (`recheckAccountStatus` acts only on a successful read; the waiting screen runs `performCriticalLaunch()`; `.enterApp` does not relaunch an authenticated session); Fragile system 6 and Canonical Entry Points ("Switch the Community tab's community" = set `CommunityContext.communityTabId`; the feed calls `forceFullRefreshAndWait(.townHall, …)`; `.townHallPostsDidSync` carries the synced scope; `TownHallSyncEngine` reads `CommunityContext` at fetch start); the Sign-out row and "Sign-out clears per-account local state" (`CommunityContext.resetForSignOut(userId:)`, called with the signing-out id captured in `handleSignOut`); File conventions (`CommunityServiceProtocol`, `TownHallPostFetching`, the shared `communityTitleMenu` modifier); Audit Notes date bump.
- Modify: `AGENTS.md`; `.cursor/rules/04*`, `05*`, `06*` (badge contract, navigation intent, mapper mirroring) in their shorter form.
- Modify: `Docs/design-system/README.md` — the community chip (`NaarsChip(tint: nil)`, hidden with one membership) and the two title-menu patterns; no new tokens.
- Modify: `CLAUDE.md` Audit Notes "Left open on purpose" and `Docs/qa/2026-10-06-audit-findings.md` — mark fixed: "Town Hall pushes using `post_id` instead of `town_hall_post_id` for the targeted refresh" (Task 8) and "approval on the waiting screen entering the app without session setup", gap-3-5 (Task 7).

**Interfaces:** replacing text per spec §4 "Documentation changes per phase", Phase 1 rows (spec lines 993-1007).

- [ ] **Step 1: Edit** each section to state the Phase 1 facts above (replace, do not append history).
- [ ] **Step 2: Verify** `grep -n "recheckBanStatus\|\"post_id\"" CLAUDE.md AGENTS.md .cursor/rules/*` returns nothing stale.
- [ ] **Step 3: Commit** `[P1-T21] Document the Phase 1 community client`.

---

### Task 22: Phase gate

**Model:** opus · **Files:** none modified (reports only). Uses `Docs/qa/push-fixtures/*.apns`, `build/`.

- [ ] **Step 1: Preconditions.** With the Supabase MCP, read-only: `select proname from pg_proc where proname in ('get_my_memberships','get_profile_stats','search_community_members','get_community_leaderboard','get_community_spotlights')` returns 5 rows and `select column_name from information_schema.columns where table_name='town_hall_posts' and column_name='community_id'` returns 1. If not, stop and report: the captures below need Phase 0 steps 1–5 live.
- [ ] **Step 2: Full unit suite, signed out, one headless simulator.** Confirm signed out (launch the app, screenshot shows Welcome), then CLAUDE.md's Lane B unit-test command with `-resultBundlePath build/P1-gate.xcresult`. Expected: exit 0, 0 failures; skips limited to the session-gated classes. Record executed / passed / skipped against the last CI run (332 passed, 35 skipped) plus this plan's new tests.
- [ ] **Step 3: Build the previous build.** `git worktree add <scratchpad>/p1-baseline f164a0f` (the merge base with `origin/main`), copy `NaarsCars/Core/Utilities/Secrets.swift` and `NaarsCars/NaarsCars/GoogleService-Info.plist` into it, build with `-derivedDataPath build/DerivedData-baseline`. Then the Phase 1 `BUILD`.
- [ ] **Step 4: Install-over run 1 (online).** `xcrun simctl uninstall booted com.NaarsCars`; install the baseline app; launch. **Owner step:** sign in. Open the Community tab (iOS Simulator MCP `tap`), wait for posts, take a screenshot (baseline reference, one membership, light), terminate. Save `DATA=$(xcrun simctl get_app_container booted com.NaarsCars data)`; `cp -R "$DATA" build/p1-container-baseline`; record `stat -f '%B %i' "$DATA/Library/Application Support/default.store"`. Install the Phase 1 app over it (no uninstall); launch; open the Community tab at once; screenshot. Expected: the cached feed shows, then refreshes; the `stat` birth time and inode are unchanged (the store was not deleted, so `createModelContainer` did not throw, `App/NaarsCarsApp.swift:41-56`); `sqlite3 "$DATA/Library/Application Support/default.store" "PRAGMA table_info(ZSDTOWNHALLPOST);"` lists `ZCOMMUNITYID`.
- [ ] **Step 5: Install-over run 2 (offline).** Terminate the app; replace `$DATA`'s contents with `build/p1-container-baseline` (the pre-migration store; the session lives in the Keychain and is unaffected). The Phase 1 app stays installed, so its next launch migrates that store. **Owner step** (the Mac's network cannot be cut without dropping this session): turn on the Network Link Conditioner "100% Loss" profile (or disconnect), launch the app, open the Community tab, take a screenshot, restore the network. Expected: the cached feed shows and stays (no empty state, no full-screen error); same `stat` and `PRAGMA` checks.
- [ ] **Step 6: Push fixtures.** Fill `<POST_ID>` / `<COMMUNITY_ID>` from `select id, community_id from town_hall_posts where hidden_at is null order by created_at desc limit 1` into copies under `build/`. With the app on the Requests tab: `xcrun simctl push booted com.NaarsCars build/town_hall_post_with_community.apns`, tap the banner → Community tab, comments sheet for that post. `town_hall_comment_without_community.apns` → the card is highlighted and **keeps its author name and comment count** after the targeted refresh (Review Focus 1). `town_hall_post_foreign_community.apns` → toast "This content is no longer available." and the Community tab's community is unchanged (Review Focus 4).
- [ ] **Step 7: Captures (spec §4 Phase 1).** For one membership (normal launch) and three (`xcrun simctl launch booted com.NaarsCars -debugCommunityCount 3`), each in light, dark (`simctl ui booted appearance dark`) and AX5 (`simctl ui booted content_size accessibility-extra-extra-extra-large`): the create-ride form, the create-favor form, the Requests dashboard (three: title menu open and a narrowed state), the Community tab (three: title menu open, then switched to "Debug Community 2"). Reset appearance and size afterwards. Inspect each: clipped or overlapping text, unreadable dark contrast, the 60-character name truncating cleanly (Review Focus 5). Compare the one-membership light captures with step 4's baseline reference: no chevron, no subtitle line, no chip, no "Post to" section (Review Focus 3).
- [ ] **Step 8: "Former member" rows.** Open the worktree project in Xcode (Lane A) and `RenderPreview` the nil-profile and nil-claimer previews from Task 19 (`TownHallPostCard`, `CommentRow`, `RideCard`, `FavorCard`, `ReviewCard`) and the `CommunityTitleMenu` preview (Task 11) with `{"Color Scheme": "Light Appearance"}`, `{"Color Scheme": "Dark Appearance"}` and `{"Dynamic Type": "AX 5"}`; retry once on the first-render timeout.
- [ ] **Step 9: Shut down and report.** `xcrun simctl shutdown booted`; remove the baseline worktree. Report: build result, suite counts, both install-over outcomes with evidence, each push fixture outcome, the capture list with findings, what was not verified (live two-community behaviour: no member holds two memberships until Phase 2), and the PR Impact Summary: (1) Town Hall pushes do a single-post refresh instead of invalidating the domain; (2) a member whose approval is revoked server-side leaves the main UI on the next foreground; files touched on high-blast seams (`PushNotificationService`, `NavigationCoordinator`, `DeepLinkParser`, `NotificationType`, `BadgeCountManager`, `BackgroundSyncActor`, the mapper trio, `Constants`) and what would break if a consumer were missed.

---

## New files

| Path (Xcode navigator path) | Target | Task | How |
|---|---|---|---|
| `NaarsCars/NaarsCarsTests/Core/Storage/CommunityStoreScopingTests.swift` | NaarsCarsTests | 2 | Xcode MCP `XcodeWrite` |
| `NaarsCars/Core/Models/Community.swift` | NaarsCars | 3 | Xcode MCP |
| `NaarsCars/Core/Protocols/CommunityServiceProtocol.swift` | NaarsCars | 3 | Xcode MCP |
| `NaarsCars/Core/Services/CommunityService.swift` | NaarsCars | 3 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift` | NaarsCarsTests | 3 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Core/Decoding/CommunityPayloadDecodingTests.swift` | NaarsCarsTests | 3 | Xcode MCP |
| `NaarsCars/App/CommunityContext.swift` | NaarsCars | 4 | Xcode MCP |
| `NaarsCars/Core/Protocols/TownHallPostFetching.swift` | NaarsCars | 8 | Xcode MCP |
| `NaarsCars/UI/Components/Common/CommunityTitleMenu.swift` | NaarsCars | 11 | Xcode MCP |
| `NaarsCars/Core/Models/ProfileStats.swift` | NaarsCars | 15 | Xcode MCP |
| `scripts/add-localization-keys.py` | none | 15 | normal tools |
| `Docs/qa/push-fixtures/town_hall_post_with_community.apns`, `town_hall_comment_without_community.apns`, `town_hall_post_foreign_community.apns` | none | 12 | normal tools |

## Self-review notes

- Spec §4 Phase 1 contents map to tasks: decoder (1), `entityIdKey` + tolerant fetch (8), `.enterApp` guard and waiting screen (7), `recheckAccountStatus` (6), new types (3, 4), context loading (4, 5, 6, 8), mapper trio (2), fetch scoping (8, 9, 10, 13, 14, 16, 17), reputation (15), "Post to" (20), chips (18), title menus (11, 17), the switch (10, 11), Town Hall targets (12), "Former member" (19), docs (21), verification (22).
- Deferred on purpose, with the target phase: `PendingInviteStore`, `Community`, `CommunityInvite`, write RPC wrappers, `isPlatformAdmin`, `isAdmin(of:)`, the scoped `clearCommunityBadge`, `pendingMembers` routing, leave and its `forceFullRefreshAndWait(.dashboard, trigger: "leftCommunity")` (Phase 2); bell-row chips and the narrowed-Requests hint (Phase 4).
- **Departures from the spec, deliberate:** (1) spec §4 Phase 1 lists the §3.7 "new types", which include `Community`, `CommunityInvite` and `PendingInviteStore`, and spec §5's sign-out row clears `PendingInviteStore`; this plan builds only `CommunityMembership`, `CommunityRole`, `MembershipStatus` and `RequestsScope`, because no Phase 1 screen or service reads or writes the other three (their first consumers are Phase 2's join and invite flows, where spec §4 Phase 2 already lists `PendingInviteStore`). The sign-out clear of `PendingInviteStore` lands with the store in Phase 2, in the same `clearPerAccountLocalState(userId:)` Task 4 extends. (2) The client-side warning from decision A3 (deleting the account of a community's only owner, `2026-10-17-multi-community-decisions.md` §A3) is **not in any Phase 1 task; target Phase 2**, alongside `MyCommunitiesView`, where ownership and Take over first appear. It must be added to the Phase 2 plan's account-deletion task so it is not lost. (3) `checkAccountStatus` is left byte-identical (Task 6), so `authState(for:)` duplicates its mapping until a separate refactor.
- Tests are the spec §4 table plus the fixture-test gate (memberships including unknown enum values, profile stats, search rows, the community leaderboard params and row, `TownHallPost` encoding of `community_id`), spec §5's sign-out keys tests, the stale-refresh-after-reset test (Task 4) and the offline push-target test (Task 12); Review Focus items without a spec-named test are pinned by Task 22 checks.
- Full-suite runs: `FULL` after Tasks 1, 2, 4, 6, 7, 8, 12 and 14 and in Task 22, per CLAUDE.md Verification Loop step 2 (fragile systems and high-blast-radius seams); no deviation from CLAUDE.md is needed.
