# Multi-community Phase 2 (create, invite, join, approve) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Phase 2 client of the multi-community design: the community onboarding screen, My communities (create, join with a code, requests to join with approve and reject, mute, report, leave, the limit-raise request), the waiting screen's membership list and actions, `PendingInviteStore`, the `pending_approval` route, the Profile badge from `pending_members_total`, the scoped Community badge clear with per-community counts, the platform Communities list, the account-deletion warning for sole-owned communities, and the legal and disclosure deliverable.

**Architecture:** One concrete `CommunityService` behind two protocols (`CommunityServiceProtocol` for member actions, `CommunityAdminServiceProtocol` for community and platform admin actions) wraps every Phase 0 step 5 RPC through one envelope decoder that turns `{success:false, error, code}` into a typed, localized `CommunityRPCError`. Screens get new `ObservableObject` ViewModels; the shared sheets (create, invite, join) know nothing about `CommunityContext`, their presenters record a success and act on dismiss. `RefreshCoordinator`, realtime, the send path, SwiftData and the notification registry are not modified.

**Tech Stack:** Swift 6.3 toolchain in Swift 5 language mode, SwiftUI + SwiftData, supabase-swift, Core Image (QR), XCTest, Xcode 26.6, iOS 26.0 deployment target.

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` (§2.1 rules 4–18, §2.2 F1–F6, F12, F15, F17, F19, F20, F22, §2.4, §3.7 "Screens", "Admin", "Navigation", "Switchers and the tab badge", §4 Phase 2 in full, §5) under the owner's decisions `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` (A1, A2, A3; no F21, no `owner_vacant`, no `claim_community_ownership`). That file wins where they differ. The RPC contract is `supabase/migrations/20261017_0005_communities_rpcs.sql`; the plan cites its line numbers. Read all three before starting a task.

## Global Constraints

- Deployment target `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; `SWIFT_VERSION = 5.0`; `SWIFT_APPROACHABLE_CONCURRENCY = YES`; `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. No build-setting changes. No new permission, entitlement, SDK or Info.plist key (the QR code is generated, never scanned).
- `RefreshCoordinator.swift` is not edited. The only coordinator calls this phase adds, all from ViewModels and all `RefreshCoordinator.shared.forceFullRefreshAndWait(_:trigger:)`: `(.badges, "communityMemberDecision")` after approve or decline, `(.dashboard, "leftCommunity")` after a leave (spec §3.7), `(.dashboard, "joinedCommunity")` after an in-app create or an instant join. Never `invalidate` or `refreshIfNeeded` from a ViewModel. Realtime, `MessageSendManager`, reactions, SwiftData models and mappers are not touched.
- No new notification type (registry stays at 33). `pending_approval` pushes carry `user_id` and `community_id` (`20261017_0001_communities_core.sql:1305-1307`); bell rows carry `notifications.community_id`.
- **RPC contract.** Argument names exactly as in `20261017_0005`: `p_name`, `p_description`, `p_join_policy`, `p_requested`, `p_reason`, `p_request_id`, `p_approve`, `p_community_id`, `p_is_public`, `p_max_uses`, `p_expires_at`, `p_invite_id`, `p_code`, `p_heard_about`, `p_join_reason`, `p_user_id`, `p_status`, `p_limit`, `p_offset`, `p_report_type`. Optional arguments are omitted when nil (`encodeIfPresent`), never sent as a key the function does not declare. Every envelope RPC answers HTTP 200; a refusal is `{success:false, error, code?}`. The server's English `error` text is logged and never shown; the user sees `CommunityRPCError.localizedMessage`. A `code` key inside a **successful** payload is not a refusal (`create_community_invite` returns the invite code under `code`, `:909`). The 20 refusal codes are exactly: `restricted`, `daily_limit`, `owned_limit`, `under_limit`, `request_open`, `too_many_codes`, `rate_limited`, `invalid`, `expired`, `exhausted`, `removed`, `already_member`, `already_pending`, `full`, `recently_rejected`, `not_pending`, `not_active`, `last_owner`, `not_member`, `not_removed`.
- The server enforces every limit (A1: 1 community a day, `max_owned_communities` default 3, limit requests 4–20 with a reason; member codes single-use for 7 days; admin codes 1–1,000 uses with an expiry of at most 90 days; 10 failed code attempts an hour; 500 members). The client pre-validates only to avoid pointless calls: names 2–60 characters, descriptions at most 300, answers and reasons at most 500, codes well formed before `validate_community_invite` is called (every call counts against the attempt limit, `:976-987`).
- New ViewModels are `final class … : ObservableObject` + `@MainActor` (State rule 2). `CommunityContext` stays `@Observable @MainActor` and keeps its equality-guarded setters. No ViewModel subscribes to a publisher or touches a repository in `init`; loading starts from the view's `.task` (CLAUDE.md render-loop rule). Copy `@State` into a local before starting a `Task` that reads it.
- **Present, record, act on dismiss.** The shared sheets report success through a callback (`onCreated(UUID)`, `onJoined(JoinResult)`); the presenter stores it and acts in the sheet's `onDismiss`, so nothing relaunches or reloads underneath a sheet that is still on screen. A relaunch from the onboarding or waiting screen is always `Task { @MainActor in await AppLaunchManager.shared.performCriticalLaunch() }` (unstructured: those screens leave the hierarchy at `.checkingAuth`).
- Design system (`Docs/design-system/README.md`): `ColorTheme` tokens only, role and status labels through `NaarsChip`, counts through `NotificationBadge`, full-width actions through `PrimaryButton` / `SecondaryButton`, failures through `.errorBanner(message:)` or `.toast(…, style: .warning)` (never the success toast), cards through `.cardStyle()`, every scrolling screen on `Color.naarsBackground`, skeletons for list loading. Every interactive element gets an `accessibilityLabel`; important controls get `accessibilityIdentifier`s under `community.*`, `onboarding.*`, `admin.communities.*`.
- Strings: every user-facing string is a key in `NaarsCars/Resources/Localizable.xcstrings` with `en`, `es`, `ko`, `vi`, `zh-Hans`, `zh-Hant`, added **only** with `python3 -I scripts/add-localization-keys.py build/P2-T<n>-keys.json`. Each task gives the keys and their English; the implementer writes the five machine translations in the tone of neighbouring keys, keeping `%@`, `%lld`, `%1$@` placeholders. Counts use the two-key idiom (`_one` / `_other`). Never remove or edit an existing key; new keys use the `community_`, `onboarding_`, `admin_communities_`, `guidelines_7_` prefixes (the legacy `invite_*` keys belong to the dead invite UI).
- **New Swift files** (decision 3): open this worktree's project (`.claude/worktrees/naarscars-multi-community-roadmap-f08594/NaarsCars/NaarsCars.xcodeproj`), call `XcodeListWindows`, confirm the workspace path, `XcodeLS` the target group (navigator paths start `NaarsCars/…`), then `XcodeWrite`. Two new groups are needed: `NaarsCars/Features/Community/ViewModels` and `NaarsCars/NaarsCarsTests/Features/Community` (Task 5 creates both with `XcodeMakeDir` and confirms with `XcodeLS` that each is a group of the right target). If another project is open, or the MCP cannot create a group, write the file to disk, report "not yet in the project", and do not claim a green build. Let Xcode go idle (or quit it) before the Lane B build. Every task that creates a Swift file lists that file **and** `NaarsCars/NaarsCars.xcodeproj/project.pbxproj` in its commit. Never hand-edit `project.pbxproj`.
- **Chain stop rule (orchestrator).** When a task reports "not yet in the project", no later task runs until the file is in the right target, `BUILD` is green, the task's tests pass and its commit exists.
- One build at a time on this Mac. One headless simulator (`iPhone 16`, iOS 26.x). Unit tests run with the simulator **signed out**. Never run `RideServiceTests`, `FavorServiceTests`, `TownHallServiceTests` or the live cases of `TownHallFeedViewModelTests` while signed in. URLProtocol stubs (Tasks 1–2) are registered in `setUp` and unregistered with their handler set to nil in `tearDown`; a leaked stub answered every later network call with a local 500 once before (CLAUDE.md Audit Notes).
- Every task ends with a green Lane B build, its listed tests passing, and one commit whose subject starts `[P2-T<n>]` and whose body ends with the Co-Authored-By trailer the executing session was given. Stage files by path only; never `git add -A` / `git add .`. Tasks never push; pushing and the draft pull request are the orchestrator's.
- **Live checks.** Every network-dependent behaviour has a stubbed unit test (where the plan names one) and a "Live check" line that needs the owner signed in on the simulator. Live checks are executed together in Task 18 (one owner sign-in). Any live check that writes to production is marked **(writes)**, runs only with the owner's go-ahead, and lists its clean-up.
- Screen captures (light, dark, AX5) for every touched screen are taken in Task 18; each UI task lists its captures and says which views get a `#Preview` (every new screen does, and renders signed out with no network).
- **Previews never use test-target code.** `CommunityFixtures`, `StubCommunityService` and `StubCommunityAdminService` live in `NaarsCarsTests` and cannot be referenced from an app-target `#Preview`. The app-target stand-in is `PreviewCommunityService` (`NaarsCars/Core/Services/PreviewCommunityService.swift`, the whole file inside `#if DEBUG`), created in Task 1 with every `CommunityServiceProtocol` method, extended in Task 2 with every `CommunityAdminServiceProtocol` method and in Task 7 with `ApplicantContactFetching`. It holds its canned answers as Swift values (`static let sample…`, no JSON, no network, no delay) in settable properties, so one preview can show an empty list or a failure. Each new screen takes its view model as `init(…, viewModel: @autoclosure @escaping () -> XViewModel = XViewModel())` stored with `StateObject(wrappedValue:)`, and a `#Preview` passes one built on `PreviewCommunityService` (and, where the view model takes a `CommunityContext`, `CommunityContext(service: PreviewCommunityService(), defaults: UserDefaults(suiteName: "preview")!)` after `debugSetMemberships`). The shared views that build their own view model (`CommunityJoinOptionsView`, `JoinCommunitySheet`, `CommunityInviteSheet`, `CreateCommunityView`) take a defaulted `service:` argument for the same reason. For that, the payload structs keep their memberwise initializers: a custom `init(from:)` goes in an extension, never in the struct body.

### Commands (used by every task; `<n>` is the task number)

```bash
# BUILD (from the worktree root). Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build > build/P2-T<n>-build.log 2>&1; echo "exit=$?"
grep -n "error:" build/P2-T<n>-build.log | head -20
# New warnings: every "warning:" line naming a file this task touched must also appear in build/P2-baseline-build.log (Task 1 Step 0).
grep -n "warning:" build/P2-T<n>-build.log | grep -E "<touched file basenames joined with |>"

# RED (compile-level failing test). Expected: exit≠0 and the named compile error.
xcodebuild build-for-testing -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/DerivedData -quiet > build/P2-T<n>-red.log 2>&1; echo "exit=$?"; grep -n "error:" build/P2-T<n>-red.log | head

# TEST <ONLY> = one or more -only-testing:NaarsCarsTests/<Class>[/<method>]. Expected: exit=0, 0 failures.
rm -rf build/P2-T<n>.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' <ONLY> -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P2-T<n>.xcresult -quiet > build/P2-T<n>-test.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P2-T<n>.xcresult

# FULL = CLAUDE.md's Lane B full unit-suite command, signed out. Expected: exit=0, 0 failures; skips only in the session-gated classes.
rm -rf build/P2-T<n>-full.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P2-T<n>-full.xcresult -quiet > build/P2-T<n>-full.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P2-T<n>-full.xcresult
```

`FULL` runs at the end of every task that changes a fragile system or a high-blast-radius seam: Tasks 3, 11, 12, 13, 14, 15 (and Task 18's gate run). Before the first `FULL` run, confirm the simulator is signed out (install and launch; a screenshot shows the Welcome screen); if it is signed in, stop and ask the owner. Record executed / passed / skipped in each task report.

A new test file is in the right target when its `TEST` run reports the expected number of executed tests (0 executed means it is not in `NaarsCarsTests`).

### Task index (model and suggested reasoning effort)

| Task | Deliverable | Model | Effort |
|---|---|---|---|
| 1 | RPC envelope, payload models, member-side `CommunityService` wrappers, `PreviewCommunityService`, stubbed `CommunityServiceTests` (+ opus review of the envelope) | sonnet | high |
| 2 | Admin-side wrappers (`CommunityAdminServiceProtocol`), their preview conformance and stubbed tests | sonnet | medium |
| 3 | Profile badge from `pending_members_total`, per-community counts, scoped `clearCommunityBadge`, title-menu counts | opus | high |
| 4 | Report a community (`ReportContext.community`), reporter-privacy sentence, guest Town Hall header report (the shared report path: moderation, App Store 1.2) | opus | high |
| 5 | Create a community and the invite sheet (code, share, QR, admin options, live codes, revoke) | sonnet | medium |
| 6 | Join sheet (typed code and public community) and the shared join options (result reported at once, gated auto-open of a prefilled code) | sonnet | high |
| 7 | Requests to join (`PendingMembersView`), `CommunityContext` admin lookups, Admin panel link | opus | high |
| 8 | My communities (list, mute, leave with counts, invite, report, requests to join, create, join) and the Profile row | opus | high |
| 9 | Owned-community limit: request sheet and status row (A1, member side) | sonnet | medium |
| 10 | Platform Communities list: archive, restore, public / private, requests to join, limit decisions (A1, A2; archive and make-private cancel claims and notify every member) | opus | high |
| 11 | Routing: `pending_approval` → Requests to join, `.myCommunities`, `.enterApp` while authenticated, push fixtures | opus | high |
| 12 | `CommunityOnboardingView` as the `.needsApplication` root, with `CommunityOnboardingViewModelTests` | opus | high |
| 13 | Waiting screen: membership list, Join another, Create your own, guarded relaunch | opus | high |
| 14 | `PendingInviteStore` (cleared on redemption), the signed-out code entry on Welcome, consumption, sign-out clear | opus | high |
| 15 | Account-deletion warning for sole-owned communities (A3) | opus | high |
| 16 | Legal and disclosure deliverable, guidelines section 7, App Store review notes, release notes (App Store rules 6 and 8) | opus | high |
| 17 | Documentation for Phase 2 | sonnet | medium |
| 18 | Phase gate | opus | high |

### Prerequisite outside this plan

Phase 0 step 5 must be fully live before Task 18, including the two bodies the owner applies in the SQL editor (`archive_community_with_notices`, block 5, and `reject_community_member`, block 21; `20261017_0005_communities_rpcs.sql:3-10`). Until then `archive_community` and the sole-member path of `leave_community` raise 42883 and `reject_community_member` does not exist. Tasks 1–17 are verified with stubs and need no backend change. This client must not be released before the legal deliverable (Task 16) is mirrored to the Notion pages the app opens (`Core/Utilities/Constants.swift:227-228`).

## Review Focus

These are not exercised by any test the spec names. Each is pinned by a test or check in its owning task.

1. **A code pasted the way the invite sheet shows it** ("NC7X · 9K2A · BQ", `InviteCodeFormatter.formatCode`, `Core/Utilities/InviteCodeFormatter.swift:22-30`), lower-case, or with spaces and dashes. Expected: it is accepted, and a malformed string never reaches `validate_community_invite`, where every failure counts against the 10-an-hour limit. Pinned by Task 1 (`CommunityInviteCode.normalize`) and Task 6 (`testValidate_SendsNormalizedCode`, `testValidate_MalformedCodeIsNotSent`).
2. **A second tap while a slow request is running** (Create, Join, Ask to join, Approve, Decline). Expected: one RPC. A second `create_community` would come back `daily_limit` right after the first succeeded. Pinned by Task 5, Task 6 and Task 7 (`…IgnoresSecondCall…` tests).
3. **A successful action whose follow-up membership refresh fails** (the network drops right after the RPC). `CommunityContext.refreshMemberships()` keeps its old rows on failure (`App/CommunityContext.swift:174-181`). Expected: a left community disappears from My communities, an approved applicant disappears from Requests to join, and no error is shown for the action that succeeded. Pinned by Task 7 (`testApprove_RemovesRowEvenWhenRefreshFails`) and Task 8 (`testLeave_HidesCommunityWhenRefreshFails`).
4. **The waiting screen deciding "relaunch" twice, or forever.** The 30-second tick and Refresh can both see an active membership; and a profile whose flags still say pending while `get_my_memberships` returns nothing would relaunch into the same screen in a loop. Expected: one relaunch, and no relaunch while the account route still reads `.pendingApproval`. Pinned by Task 13 (`testPoll_AfterRelaunchDecisionDoesNotFetchAgain`, `testPoll_NoMembershipRouteStillPendingWaits`).
5. **Reporting with no cached user id.** After a cold launch into onboarding, `AuthService.currentUserId` is nil (`Features/Authentication/ViewModels/BannedAccountViewModel.swift:109-120`), and `ReportContentViewModel.submitReport` returns false on that guard without a word (`Features/TownHall/ViewModels/ReportContentViewModel.swift:80-81`). Expected: a community report from the public preview or the code preview is submitted (`report_community` reads `auth.uid()` itself), and every other report type still stops at that guard. Pinned by Task 4 (`testSubmitCommunityReport_WorksWithoutCachedUserId`, `testSubmitPostReport_StillRequiresCachedUserId`).
6. **A join that succeeded while its sheet is swiped away.** A redeem or request that returned before the person swipes the sheet down must still be recorded, or onboarding stays on screen with a pending row and a second try answers `already_pending`. Expected: the result reaches the presenter as soon as it is set, not when Done is tapped, and the sheet cannot be swiped away while the request is running. Pinned by Task 6 (`testSubmit_ReportsResultAsSoonAsItIsSet`).
7. **The first invite code of a community that was just created.** `create_community_invite` refuses an admin caller with no `p_expires_at` and no `code` (`20261017_0005:854-855`), and right after Create (always so in onboarding) `CommunityContext` does not yet hold the new owner row. Expected: the invite sheet opens with a code. Pinned by Task 5 (`isAdmin: true` from Create; `testCreateCode_MemberSendsSevenDayExpiry`, `testCreateCode_AdminSendsUsesAndChosenExpiry`) and Task 1 (`testCreateInvite_SendsExpiryAndOmitsNilMaxUses`).

---

### Task 1: RPC envelope, payload models and the member-side wrappers

**Model:** sonnet, high effort, with an opus review step (the envelope decides what every community screen shows on refusal; the argument names are the RPC seam) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Core/Models/CommunityPayloads.swift`, `NaarsCars/Core/Services/PreviewCommunityService.swift` (whole file in `#if DEBUG`)
- Modify: `NaarsCars/Core/Models/Community.swift:33-75` (one computed property)
- Modify: `NaarsCars/Core/Protocols/CommunityServiceProtocol.swift:10-13`, `NaarsCars/Core/Services/CommunityService.swift:11-23`
- Modify: `NaarsCars/Core/Utilities/Constants.swift` (new `enum Community`; `Timing.pendingApprovalPollInterval` beside `membershipRefreshMinInterval`, `:142`)
- Modify: `NaarsCars/App/CommunityContext.swift:330` (DEBUG seam `joinPolicy: "invite"`)
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift` (fixtures; `membership(…)` helper `:107-134`; `StubCommunityService` `:162-176`; fix `join_policy` values `:46, :66, :91, :121` to the server's `invite` / `approve`)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Services/CommunityServiceTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`
- Reference: `supabase/migrations/20261017_0005_communities_rpcs.sql` blocks 7–9, 15–19, 26, 31; `20261017_0002_communities_rls.sql:215` (mute column grant), `:222-247` (communities SELECT), `:262-268` (`community_invites` SELECT)

**Interfaces:**
- Produces (`CommunityPayloads.swift`; all `Decodable, Equatable, Sendable` with explicit snake_case `CodingKeys`, decoded with `DateDecoderFactory.makeSupabaseDecoder()`):

```swift
enum CommunityRefusalCode: String, CaseIterable, Sendable { /* the 20 codes of Global Constraints, camelCase cases, snake_case raw values */ }
struct CommunityRPCError: Error, Equatable, Sendable {
    let code: CommunityRefusalCode?   // nil when absent or not one of the 20
    let serverMessage: String         // the server's `error`; logged, never shown
    let maxOwned: Int?                // owned_limit (:378)
    let ownedCount: Int?              // owned_limit
    let retryAfter: Date?             // recently_rejected (:1247)
    var localizedMessage: String { get }   // "community_error_<raw code>"; nil code → "community_error_generic";
                                           // owned_limit formats ownedCount ?? maxOwned ?? 0; recently_rejected formats
                                           // retryAfter with .formatted(date: .abbreviated, time: .omitted), generic when nil
}
enum CommunityServiceError: Error { case membershipNotUpdated }
enum CommunityRPC {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T   // reads `success` first; false → throws CommunityRPCError
    static func decodeSuccess(from data: Data) throws                               // same check, payload ignored
}
enum CommunityInviteCode {
    static func normalize(_ raw: String) -> String       // uppercase; drop every character that is not A–Z or 0–9 (the server's rule, :198)
    static func isWellFormed(_ normalized: String) -> Bool   // ^NC[A-HJKMNP-Z2-9]{8}$ (the CHECK in 20261017_0001)
}
enum CommunityJoinPolicy: String, Sendable { case invite, approve }
struct CreatedCommunity { let communityId: UUID }                                      // :405
struct CommunityLimits { let maxOwned: Int; let ownedCount: Int; let nextCreateAt: Date?; let canCreate: Bool; let latestRequest: CommunityLimitRequest? }  // :456-463
struct CommunityLimitRequest { let requestId: UUID; let requestedMax: Int; let reason: String; let status: LimitRequestStatus; let createdAt: Date; let decidedAt: Date? }
enum LimitRequestStatus: String, Sendable { case pending, approved, declined }        // tolerant init(from:): unknown → .pending
struct LimitRequestReceipt { let requestId: UUID }                                     // :550
struct CommunityInvite { let code: String; let inviteId: UUID; let maxUses: Int; let expiresAt: Date }   // :909-910
struct CommunityInviteRow: Identifiable { let id: UUID; let code: String; let maxUses: Int?; let useCount: Int; let expiresAt: Date?; let revokedAt: Date?; let createdAt: Date
    func isLive(at now: Date) -> Bool }   // not revoked, not expired, not used up
struct InvitePreview { let valid: Bool; let expired: Bool; let requiresApproval: Bool?; let communityName: String?; let alreadyMember: Bool?; let memberCount: Int? }  // :990-1014
struct JoinResult { let communityId: UUID; let status: MembershipStatus }               // :1166, :1280
struct LeaveResult { let reopened: Int; let removed: Int; let cancelled: Int; let archived: Bool }   // :1705, :1735-1739
struct CommunityReportResult { let reportId: UUID?; let duplicate: Bool }              // :2020, :2032; duplicate defaults false
struct PublicCommunity: Identifiable { let id: UUID; let name: String; let description: String?; let joinPolicy: String; let isDefault: Bool }
// Every struct keeps its memberwise initializer: tolerant decoders (LimitRequestStatus, CommunityReportResult.duplicate)
// are written as `extension X { init(from decoder: Decoder) throws { … } }`, so PreviewCommunityService can build values.
```
- Produces (app target, DEBUG only): `PreviewCommunityService.swift`:

```swift
#if DEBUG
/// Canned, offline answers for #Preview only. Never used outside DEBUG previews; no network, no delay.
final class PreviewCommunityService: CommunityServiceProtocol {
    var memberships: [CommunityMembership] = PreviewCommunityService.sampleMemberships
    var publicCommunities: [PublicCommunity] = PreviewCommunityService.samplePublicCommunities
    var failPublicCommunities = false              // previews the load-failure state
    var limits = CommunityLimits(maxOwned: 3, ownedCount: 1, nextCreateAt: nil, canCreate: true, latestRequest: nil)
    var invite = CommunityInvite(code: "NC7K2PQ9XA", inviteId: UUID(), maxUses: 1, expiresAt: Date().addingTimeInterval(7 * 86_400))
    var liveInvites: [CommunityInviteRow] = PreviewCommunityService.sampleLiveInvites
    var invitePreview = InvitePreview(valid: true, expired: false, requiresApproval: true, communityName: "Ballard Neighbors",
                                      alreadyMember: false, memberCount: 12)
    var joinStatus: MembershipStatus = .pending
    init() {}
    static func membership(name: String, role: CommunityRole = .member, status: MembershipStatus = .active,
                           memberCount: Int = 12, pendingCount: Int? = nil, isDefault: Bool = false) -> CommunityMembership
    static let sampleMemberships: [CommunityMembership]   // Naar's Cars Seattle (member, default), Ballard Neighbors (owner, 2 pending),
                                                          // Fremont Families (pending)
    static let samplePublicCommunities: [PublicCommunity] // two rows
    static let sampleLiveInvites: [CommunityInviteRow]    // two live rows
    // every CommunityServiceProtocol method returns the matching property (or a fixed success value: CreatedCommunity(UUID()),
    // LimitRequestReceipt, JoinResult(communityId:, status: joinStatus), LeaveResult(0, 0, 0, false), CommunityReportResult(nil, false));
    // fetchPublicCommunities throws URLError(.notConnectedToInternet) when failPublicCommunities
}
#endif
```
- `CommunityMembership` gains `var requiresApproval: Bool { joinPolicy == CommunityJoinPolicy.approve.rawValue }`.
- Produces in `Constants`: `enum Community { static let nameLength = 2...60; static let descriptionMaxLength = 300; static let answerMaxLength = 500; static let limitRequestRange = 4...20; static let memberInviteLifetimeDays = 7; static let adminInviteMaxUses = 1000; static let inviteExpiryDayChoices = [1, 7, 30, 90]; static let pendingMembersPageSize = 100; static let membersPageSize = 500; static let pendingInviteLifetime: TimeInterval = 7 * 24 * 3600 }`; `Timing.pendingApprovalPollInterval: TimeInterval = 30`.
- `CommunityServiceProtocol` gains (each one RPC or table call, through `SupabaseService.shared.client`; a private `Encodable` params struct per RPC with explicit keys and a `nonisolated encode(to:)`, the `CommunityLeaderboardParams` idiom, `Core/Services/LeaderboardService.swift:85-102`):

| Method | Call | Notes |
|---|---|---|
| `createCommunity(name: String, description: String?, joinPolicy: CommunityJoinPolicy) async throws -> CreatedCommunity` | `rpc("create_community")` `p_name, p_description?, p_join_policy` | block 7 |
| `fetchMyCommunityLimits() async throws -> CommunityLimits` | `rpc("get_my_community_limits")` | block 8 |
| `requestOwnedCommunityLimit(requested: Int, reason: String) async throws -> LimitRequestReceipt` | `rpc("request_owned_community_limit")` `p_requested, p_reason` | block 9 |
| `createInvite(communityId: UUID, maxUses: Int?, expiresAt: Date?) async throws -> CommunityInvite` | `rpc("create_community_invite")` `p_community_id, p_max_uses?, p_expires_at?` | `p_expires_at` sent as a `String` from `ISO8601DateFormatter` (`.withInternetDateTime`). The wrapper still omits a nil, but every caller in this plan passes an expiry (Task 5): the admin branch refuses a missing one with no `code` (`:854-855`), the member branch clamps any value to 7 days (`:861`) |
| `fetchLiveInvites(communityId: UUID, createdBy: UUID) async throws -> [CommunityInviteRow]` | `from("community_invites").select("id, code, max_uses, use_count, expires_at, revoked_at, created_at").eq("community_id").eq("created_by").is("revoked_at", value: nil).order("created_at", ascending: false)` | the service returns only `isLive(at: Date())` rows |
| `revokeInvite(inviteId: UUID) async throws` | `rpc("revoke_community_invite")` `p_invite_id` | block 16 |
| `validateInvite(code: String) async throws -> InvitePreview` | `rpc("validate_community_invite")` `p_code` | block 17; callers pass a normalized code |
| `redeemInvite(code: String, heardAbout: String?, joinReason: String?) async throws -> JoinResult` | `rpc("redeem_community_invite")` `p_code, p_heard_about?, p_join_reason?` | block 18 |
| `fetchPublicCommunities() async throws -> [PublicCommunity]` | `from("communities").select("id, name, description, join_policy, is_default").eq("is_public", value: true).order("name")` | RLS already hides archived rows |
| `requestToJoin(communityId: UUID, heardAbout: String?, joinReason: String?) async throws -> JoinResult` | `rpc("request_to_join_community")` `p_community_id, p_heard_about?, p_join_reason?` | block 19; always `pending` |
| `leaveCommunity(communityId: UUID) async throws -> LeaveResult` | `rpc("leave_community")` `p_community_id` | block 26 |
| `setCommunityMuted(communityId: UUID, muted: Bool) async throws` | `from("community_members").update(body).eq("community_id").select("community_id").execute()` | body exactly `{"notifications_muted": <muted>, "muted_until": null}` (explicit `encodeNil`, so a timed mute set elsewhere is cleared); zero rows back → `CommunityServiceError.membershipNotUpdated` (a PATCH that matches nothing still answers 200) |
| `reportCommunity(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?) async throws -> CommunityReportResult` | `rpc("report_community")` `p_community_id?, p_code?, p_report_type, p_description?` | block 31 |

- Produces (test target): fixtures in `CommunityFixtures` — `userA` (fixed UUID), `createCommunitySuccessJSON`, `ownedLimitRefusalJSON` (`{"success":false,"error":"…","code":"owned_limit","max_owned":3,"owned_count":3}`), `refusalWithoutCodeJSON`, `unknownCodeRefusalJSON` (`"code":"brand_new_code"`), `inviteSuccessJSON` (contains `"code":"NC7K2PQ9XA"`), `limitsWithPendingRequestJSON`, `liveInvitesJSON` (one live, one expired, one used up), `validateValidJSON` (requires approval, `member_count` 12, `already_member` false), `validateExpiredJSON`, `validateInvalidJSON`, `redeemPendingJSON`, `recentlyRejectedJSON` (with `retry_after`), `leaveResultJSON`, `reportDuplicateJSON`, `publicCommunitiesJSON`; `membership(…)` gains defaulted `memberCount: Int = 1, pendingCount: Int? = nil, isDefault: Bool = false, joinPolicy: String = "invite", notificationsMuted: Bool = false, canInvite: Bool = true`.
- `StubCommunityService` implements every new method with one `var <name>Result: Result<T, Error>` (a sensible success default) and one `private(set) var <name>Calls: [<argument tuple>]`, plus `var actionGate: (() async -> Void)?` awaited by every write before it returns (Review Focus 2). Later tasks only read these.
- `CommunityServiceTests` declares `final class CommunityServiceURLProtocol: URLProtocol` on the `ClaimServiceURLProtocol` pattern (`NaarsCarsTests/Core/Services/ClaimServiceTests.swift:11-48`) that also records each request, and a `bodyJSON(of: URLRequest) -> [String: Any]` helper that reads `httpBody` or, when nil, drains `httpBodyStream` (URLProtocol usually receives the stream).

- [ ] **Step 0: Baseline.** Build `HEAD` before any edit with `BUILD`'s command into `build/P2-baseline-build.log`; record the warning count.
- [ ] **Step 1: Write the failing tests** (spec §4 Phase 2: "stubbed `CommunityServiceTests` for every RPC wrapper"; CLAUDE.md fixture-test gate). Each wrapper test asserts the method and path (`POST /rest/v1/rpc/<name>`, `GET` / `PATCH /rest/v1/<table>`), the exact body key set or query items, and the decoded value:

```swift
func testEnvelope_RefusalWithCodeThrowsTypedError()          // ownedLimitRefusalJSON → code .ownedLimit, maxOwned 3, ownedCount 3
func testEnvelope_RefusalWithoutCodeHasNilCode()             // code nil; localizedMessage == "community_error_generic".localized
func testEnvelope_UnknownCodeDecodesAsNil()
func testEnvelope_SuccessPayloadWithCodeKeyIsNotARefusal()   // inviteSuccessJSON decodes as CommunityInvite(code: "NC7K2PQ9XA", …)
func testLocalizedMessage_EveryCodeHasAKey()                 // for code in allCases: message != "community_error_\(code.rawValue)" (the key itself means it is missing)
func testInviteCode_NormalizesFormattedPastedCode()          // normalize("nc7k · 2pq9-xa ") == "NC7K2PQ9XA"; isWellFormed true; isWellFormed("NC0O1IL234") false
func testCreateCommunity_SendsNameDescriptionPolicy()        // keys == ["p_name","p_description","p_join_policy"]; "approve"; id decoded
func testCreateCommunity_OmitsNilDescription()               // keys == ["p_name","p_join_policy"]
func testFetchMyCommunityLimits_DecodesLatestRequest()       // status .pending, requestedMax 5, canCreate false
func testRequestOwnedCommunityLimit_SendsRequestedAndReason()
func testCreateInvite_SendsExpiryAndOmitsNilMaxUses()        // maxUses nil, expiresAt fixed → keys == ["p_community_id","p_expires_at"]
func testCreateInvite_AdminSendsUsesAndISO8601Expiry()       // p_max_uses 25; p_expires_at == ISO8601DateFormatter().string(from: fixedDate)
func testFetchLiveInvites_QueriesOwnLiveCodesAndDropsDeadOnes()  // query has community_id=eq.<A>, created_by=eq.<userA>, revoked_at=is.null; 1 row back
func testRevokeInvite_SendsInviteId()
func testValidateInvite_DecodesValidExpiredAndInvalid()      // three stubbed answers
func testRedeemInvite_SendsAnswersAndDecodesPending()
func testRedeemInvite_RemovedThrowsRemoved()
func testFetchPublicCommunities_QueriesPublicOnly()          // query has is_public=eq.true
func testRequestToJoin_RecentlyRejectedCarriesRetryAfter()
func testLeaveCommunity_DecodesCounts()
func testSetCommunityMuted_PatchesWithExplicitNullMutedUntil()   // PATCH; body == ["notifications_muted": true, "muted_until": NSNull()]
func testSetCommunityMuted_ZeroRowsThrows()                  // stub answers [] → CommunityServiceError.membershipNotUpdated
func testReportCommunity_ByCodeOmitsCommunityId()            // keys == ["p_code","p_report_type"]
func testReportCommunity_DuplicateIsSuccess()                // duplicate true, reportId nil
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CommunityRPC' in scope".
- [ ] **Step 3: Implement** the payload file and `PreviewCommunityService.swift` (both through the Xcode MCP: `XcodeLS NaarsCars/Core/Models` and `NaarsCars/Core/Services`, then `XcodeWrite`; confirm each is in the `NaarsCars` app target, not the test target), the protocol, the service, the constants, the fixture and stub additions, and add the strings below with the script. `PreviewCommunityService` must conform to the whole protocol, so it grows with it: Task 2 and Task 7 extend it.
- [ ] **Step 4: Opus review** (separate read-only opus subagent, given the diff). It checks: `CommunityRPC.decode` reads `success` before anything else and never treats `code` as a refusal when `success` is true; every params struct's keys match the SQL signature line by line (blocks 7, 8, 9, 15–19, 26, 31); no optional is encoded as an explicit null except `muted_until`; nothing shows `serverMessage`; the URLProtocol stub is unregistered in `tearDown`; `PreviewCommunityService.swift` is wrapped in `#if DEBUG` from the first line to the last and imports nothing from the test target. Fix findings before the commit.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityServiceTests -only-testing:NaarsCarsTests/CommunityPayloadDecodingTests`. Expected: 25 new tests pass; the existing decoding tests stay green.
- [ ] **Step 6: Commit** `[P2-T1] Add the community RPC envelope and the member-side CommunityService wrappers` with every file above (including `NaarsCars/Core/Services/PreviewCommunityService.swift`) and `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`.

Strings:
```
community_error_generic = "Something went wrong. Try again."
community_error_restricted = "This isn't available for this account."
community_error_daily_limit = "You can create one community a day. Try again tomorrow."
community_error_owned_limit = "You already own %lld communities, the most your account allows."
community_error_under_limit = "You can still create communities under your current limit."
community_error_request_open = "You already have a request waiting for a decision."
community_error_too_many_codes = "You have too many codes that still work. Revoke one first."
community_error_rate_limited = "Too many tries. Try again later."
community_error_invalid = "This code isn't valid."
community_error_expired = "This code has expired."
community_error_exhausted = "This code has been used up."
community_error_removed = "A community admin has to let you back in."
community_error_already_member = "You're already a member of this community."
community_error_already_pending = "Your request to join is already waiting for an admin."
community_error_full = "This community is full."
community_error_recently_rejected = "You can ask to join again after %@."
community_error_not_pending = "This request was already handled."
community_error_not_active = "This person isn't an active member."
community_error_last_owner = "A community needs an owner. Make another member owner first."
community_error_not_member = "You're not a member of this community."
community_error_not_removed = "This person wasn't removed."
```

Live check: covered through the screens of Tasks 5–10; each wrapper appears in Task 18's live matrix.

---

### Task 2: Admin-side wrappers

**Model:** sonnet · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Core/Protocols/CommunityAdminServiceProtocol.swift`
- Modify: `NaarsCars/Core/Models/CommunityPayloads.swift`, `NaarsCars/Core/Services/CommunityService.swift`, `NaarsCars/Core/Services/PreviewCommunityService.swift`
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift`, `NaarsCars/NaarsCarsTests/Core/Services/CommunityServiceTests.swift`
- Reference: `20261017_0005_communities_rpcs.sql` blocks 10, 12, 13, 14, 20, 21, 29, 32

**Interfaces:**
- Consumes: `CommunityRPC`, `CommunityRPCError`, `CommunityRefusalCode`, `MembershipStatus`, `CommunityRole` (Task 1, Phase 1).
- Produces (`CommunityPayloads.swift`):

```swift
struct CommunityMember: Identifiable, Decodable, Equatable, Sendable {   // get_community_members row (:1849-1862)
    let id: UUID; let name: String; let avatarUrl: String?; let car: String?; let role: CommunityRole; let status: MembershipStatus
    let joinedAt: Date; let activatedAt: Date?; let heardAbout: String?; let joinReason: String?; let invitedByName: String?; let removalReason: String?
    // name: decodeIfPresent ?? "" (one blank profile must not fail the list); that init(from:) lives in an extension (memberwise init kept)
}
struct PlatformCommunities: Decodable, Equatable, Sendable { let communities: [PlatformCommunity]; let limitRequests: [PlatformLimitRequest] }  // :2091
struct PlatformCommunity: Identifiable, …  { let id: UUID; let name: String; let description: String?; let createdBy: UUID?; let creatorName: String?
    let createdAt: Date; let isPublic: Bool; let isDefault: Bool; let joinPolicy: String; let archivedAt: Date?; let archivedBy: UUID?
    let memberCount: Int; let pendingCount: Int; let ownerCount: Int; let openReportCount: Int }   // :2064-2073
struct PlatformLimitRequest: Identifiable, … { let requestId: UUID; let userId: UUID; let userName: String?; let requestedMax: Int; let reason: String
    let createdAt: Date; let currentMax: Int; let ownedCount: Int; var id: UUID { requestId } }   // :2081-2085
struct LimitDecision: Decodable, Equatable, Sendable { let status: LimitRequestStatus; let maxOwned: Int }   // :617-618
```
- Produces: `protocol CommunityAdminServiceProtocol: AnyObject` and `extension CommunityService: CommunityAdminServiceProtocol`:

| Method | Call |
|---|---|
| `fetchCommunityMembers(communityId: UUID, status: MembershipStatus, limit: Int, offset: Int) async throws -> [CommunityMember]` | `rpc("get_community_members")` `p_community_id, p_status, p_limit, p_offset` (a table, no envelope; an unauthorized call returns `[]`, `:1883-1890`) |
| `approveMember(communityId: UUID, userId: UUID) async throws` | `rpc("approve_community_member")` `p_community_id, p_user_id` |
| `rejectMember(communityId: UUID, userId: UUID) async throws` | `rpc("reject_community_member")` `p_community_id, p_user_id` |
| `fetchDefaultCommunityId() async throws -> UUID?` | `from("communities").select("id").eq("is_default", value: true).limit(1)` (the default community is public, so RLS returns it) |
| `fetchPlatformCommunities() async throws -> PlatformCommunities` | `rpc("get_platform_communities")` |
| `archiveCommunity(communityId: UUID) async throws` | `rpc("archive_community")` `p_community_id` |
| `unarchiveCommunity(communityId: UUID) async throws` | `rpc("unarchive_community")` `p_community_id` |
| `setCommunityPublic(communityId: UUID, isPublic: Bool) async throws` | `rpc("set_community_public")` `p_community_id, p_is_public` |
| `decideOwnedCommunityLimit(requestId: UUID, approve: Bool) async throws -> LimitDecision` | `rpc("decide_owned_community_limit")` `p_request_id, p_approve` |

- Produces (app target, DEBUG): `extension PreviewCommunityService: CommunityAdminServiceProtocol` with settable `members: [CommunityMember] = sampleApplicants` (two applicants with both answers and one `invitedByName`), `platformCommunities: PlatformCommunities = samplePlatformCommunities` (Seattle default and public; Ballard with 2 pending; one archived community with `openReportCount` 1 and `ownerCount` 0; one limit request), `adminRefusal: CommunityRPCError?` (when set, approve / reject / archive throw it, for the not-admin preview); `fetchDefaultCommunityId` returns Seattle's sample id; `decideOwnedCommunityLimit` returns `LimitDecision(status: approve ? .approved : .declined, maxOwned: 5)`. Swift values only, as in Task 1.
- Produces (test target): `CommunityFixtures.pendingMembersAdminJSON` (two pending rows with answers and `invited_by_name`), `activeMembersMemberViewJSON` (null answers), `platformCommunitiesJSON` (Seattle default + public, one archived community with `open_report_count` 1, one limit request), `limitDecisionJSON`, `approveRefusalWithoutCodeJSON`; `final class StubCommunityAdminService: CommunityAdminServiceProtocol` with the same Result / Calls / `actionGate` shape as Task 1's stub.

- [ ] **Step 1: Write the failing tests** in `CommunityServiceTests` (spec §4 Phase 2):

```swift
func testFetchCommunityMembers_SendsAllFourArgumentsAndDecodesAdminFields()  // keys == ["p_community_id","p_status","p_limit","p_offset"]; p_status "pending"; heardAbout set
func testFetchCommunityMembers_MemberViewHasNullAnswers()
func testApproveMember_SendsCommunityAndUser()
func testApproveMember_RefusalWithoutCodeThrowsNilCode()
func testRejectMember_NotPendingThrowsNotPending()
func testFetchDefaultCommunityId_QueriesIsDefault()           // query has is_default=eq.true
func testFetchPlatformCommunities_DecodesCommunitiesAndLimitRequests()
func testArchiveUnarchiveAndSetPublic_SendCommunityId()       // three requests; set_community_public body has p_is_public false
func testDecideOwnedCommunityLimit_SendsApproveFlagAndDecodes()
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find type 'CommunityAdminServiceProtocol' in scope".
- [ ] **Step 3: Implement** (protocol file through the Xcode MCP; `XcodeLS NaarsCars/Core/Protocols` first) and the `PreviewCommunityService` admin conformance (inside its `#if DEBUG`).
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityServiceTests`. Expected: 34 pass.
- [ ] **Step 5: Commit** `[P2-T2] Add the admin-side community wrappers` with the files above (including `PreviewCommunityService.swift`) and `project.pbxproj`.

Live check: through Tasks 7 and 10.

---

### Task 3: Profile badge, per-community counts and the scoped Community clear

**Model:** opus (Badge Count System, fragile system 7; `BadgeCountManager` is a high-blast seam) · **Files:**
- Modify: `NaarsCars/Core/Services/BadgeCountManager.swift:36-46` (`BadgeCounts`), `:54` (`adminService`, removed), `:85-191` (`refreshAllBadges`), `:243-272` (`clearCommunityBadge`), `:293-313` (`calculateProfileBadgeCount`, removed)
- Modify: `NaarsCars/Core/Protocols/BadgeCountManaging.swift:11`
- Modify: `NaarsCars/App/MainTabView.swift:130-133`
- Modify: `NaarsCars/Features/Community/Views/CommunityTabView.swift:48-62, 71-76`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/BadgeCountManagerTests.swift`

**Interfaces:**
- Consumes: `BadgeCountsPayload.pendingMembersTotal`, `.communityDetails` (Phase 1, `:336-353`); `CommunityContext.communityTabId`, `activeMemberships`, `hasMultipleCommunities`.
- Produces:

```swift
// BadgeCounts gains:
var communityUnreadById: [UUID: Int] = [:]
static func makeCounts(from payload: BadgeCountsPayload) -> BadgeCounts
    // requests, messages, community, bell as today; profile = adminPanel = payload.pendingMembersTotal ?? 0;
    // totalUnread = requests + messages + community; communityUnreadById = communityDetails entries with communityTotal > 0
static func communityNotificationIdsToClear(_ notifications: [AppNotification], visibleCommunityId: UUID?) -> [UUID]
    // unread rows of .townHallPost / .townHallComment / .townHallReaction whose communityId is visibleCommunityId or nil;
    // visibleCommunityId nil (context not loaded) → every unread community row, today's behaviour
func clearCommunityBadge(visibleCommunityId: UUID?) async   // replaces clearCommunityBadge(); same mark-read and refresh, over the scoped ids
```
- `refreshAllBadges` assigns `Self.makeCounts(from:)` once; the `async let profileCount` and every `_ = await profileCount` go with `calculateProfileBadgeCount()` and `adminService` (spec §3.7 Admin: the second client-side aggregation path is removed; Fragile system 7: "prefer cached/stale values" when the RPC fails, which the cached payload already gives). `BadgeCountManaging.clearCommunityBadge(visibleCommunityId: UUID?) async`.
- Callers pass `CommunityContext.shared.communityTabId`: `MainTabView` case 2 (`:132`), `CommunityTabView.onAppear` (`:71-76`), and a new `CommunityTabView.onChange(of: communityContext.communityTabId)` (switching communities marks the newly visible one read; spec §2.1 rule 12, §3.7 "Switchers and the tab badge").
- `CommunityTabView` holds `@State private var badgeManager = BadgeCountManager.shared`; each **non-selected** menu row whose `badgeManager.counts.communityUnreadById[membership.communityId] ?? 0 > 0` adds a second `Text("community_menu_unread_count".localized(with: count))` to its label (title and subtitle idiom of menu buttons). The menu is still applied only through `.communityTitleMenu(enabled:)`, so one membership changes nothing.
- Impact Summary item: a platform admin's Profile badge now counts pending rows of the communities they administer (and of communities with no owner or admin), no longer every `approved = false` profile (`AdminService.fetchPendingUsers`, `Core/Services/AdminService.swift:151-167`), which also counted accounts that never applied.

- [ ] **Step 1: Write the failing tests** (CLAUDE.md fixture-test gate for the badge seam; spec §4 Phase 2 "the Profile badge from `pending_members_total`", "the scoped `clearCommunityBadge`"):

```swift
func testMakeCounts_ProfileBadgeReadsPendingMembersTotal()       // payload pending_members_total 2 → profile 2, adminPanel 2
func testMakeCounts_MissingPendingMembersTotalIsZero()
func testMakeCounts_CommunityUnreadByIdKeepsPositiveTotals()     // details A community 3, B community 0 → [A: 3]
func testCommunityIdsToClear_ScopesToVisibleAndUnlabelledRows()  // A post unread, B comment unread, nil reaction unread, A post read, A ride_claimed unread
                                                                 // visible A → ids == [A post, nil reaction]
func testCommunityIdsToClear_NilVisibleClearsEveryCommunityRow() // → A post, B comment, nil reaction
```
- [ ] **Step 2: RED.** `RED`. Expected: "type 'BadgeCountManager.BadgeCounts' has no member 'makeCounts'".
- [ ] **Step 3: Implement**; add the string.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/BadgeCountManagerTests`. Expected: all pass.
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P2-T3] Read the Profile badge from pending_members_total and scope the Community badge clear` with the files above.

Strings: `community_menu_unread_count = "%lld new"`.

Capture list (Task 18): Community tab title menu open with three memberships and an unread count on a non-selected row (DEBUG seam plus a seeded count is not possible offline; captured live), light / dark / AX5. `#Preview`: `CommunityTabView` (yes).

Live check: with the owner signed in, `select get_badge_counts(true)` as the owner (read-only, MCP `execute_sql` under `set local role authenticated` with the owner's claims, rolled back) and the Profile tab badge agree on `pending_members_total`.

---

### Task 4: Report a community

**Model:** opus, high effort (`ReportContentViewModel.submitReport` is the one report path every content type uses: moderation and reporting, CLAUDE.md "When to slow down" and App Store non-negotiable 3) · **Files:**
- Modify: `NaarsCars/Features/TownHall/Views/ReportContentSheet.swift:11-19, 46-66, 120-126`
- Modify: `NaarsCars/Features/TownHall/ViewModels/ReportContentViewModel.swift:21-36, 41-53, 80-153`
- Modify: `NaarsCars/Features/TownHall/Views/TownHallFeedView.swift:28-42`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/TownHall/ReportContentViewModelTests.swift`

**Interfaces:**
- Consumes: `CommunityServiceProtocol.reportCommunity`, `CommunityRPCError`, `StubCommunityService` (Task 1).
- Produces: `ReportContext.community(id: UUID?, code: String?, name: String)` (A2: a community the caller can see, by id, or one they hold a valid code for, by code). `contentPreview` = name; `contentTypeLabel` = `report_content_type_community`; `blockableAuthorId(for: .community)` = nil.
- `ReportContentViewModel.init(…, communityService: any CommunityServiceProtocol = CommunityService.shared)`. `submitReport(context: .community…)` calls `reportCommunity(communityId: id, code: code, type: type, description: description.isEmpty ? nil : description)` **before** the `authService.currentUserId` guard, which keeps applying to every other case; `duplicate == true` returns true; a `CommunityRPCError` sets `submitError = error.localizedMessage`; any other error `"community_error_generic".localized`.
- Invariant to state in the task report before editing: every existing `ReportContext` case keeps its call, its arguments and its `authService.currentUserId` guard exactly as today (`ReportContentViewModel.swift:80-153`); only `.community` returns before that guard. Implement it as an early `if case .community(let id, let code, _) = context { return await submitCommunityReport(…) }` above the guard, leaving the existing `switch` body untouched apart from the new `case .community: return false` arm (unreachable, keeps the switch exhaustive), and add `case .community: return nil` to `blockableAuthorId` (`:41-53`). `git diff -U0` of the file must show no change inside the existing cases.
- `ReportContentSheet` adds, as the footer of its "messaging_description" section, `Text("report_reporter_privacy_note".localized)` (spec §3.5 INV-P2, §4 Phase 2 in-app sentence; exact copy below).
- `TownHallFeedView`: when `appState.isGuest`, a `ToolbarItem(placement: .navigationBarLeading)` `Menu` (label `Image(systemName: "ellipsis.circle")`, `accessibilityLabel("community_more_actions".localized)`, identifier `community.townHall.more`) with one button `community_report_this_community` that sets `guestPromptReason = .reportContent` (A2: guests tapping Report get the existing sign-in prompt; a signed-in person's Town Hall shows only their own communities, whose Report is in My communities, Task 8).

- [ ] **Step 1: Write the failing tests** (Review Focus 5):

```swift
func testSubmitCommunityReport_WorksWithoutCachedUserId() async   // AuthService.shared.currentUserId saved, set nil, restored in tearDown
    // vm.submitReport(context: .community(id: nil, code: "NC7K2PQ9XA", name: "Ballard"), type: .spam, description: "") == true
    // stub.reportCommunityCalls.first?.code == "NC7K2PQ9XA"; .communityId == nil; .description == nil
func testSubmitCommunityReport_DuplicateCountsAsSuccess() async
func testSubmitCommunityReport_RateLimitedShowsLocalizedMessage() async   // submitError == "community_error_rate_limited".localized
func testSubmitPostReport_StillRequiresCachedUserId() async       // currentUserId nil; .post(…) → false; stub.reportCommunityCalls empty (the guard is unchanged)
```
- [ ] **Step 2: RED.** `RED`. Expected: "type 'ReportContext' has no member 'community'".
- [ ] **Step 3: Implement**; add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/ReportContentViewModelTests`. Expected: 4 pass.
- [ ] **Step 5: Diff check.** `git diff -U0 NaarsCars/Features/TownHall/ViewModels/ReportContentViewModel.swift` shows only the new init parameter, the early community return, the new helper and the two new `case .community` arms.
- [ ] **Step 6: Commit** `[P2-T4] Report a community; state reporter privacy in the report sheet` with the files above and `project.pbxproj`.

Strings:
```
report_content_type_community = "Community"
report_reporter_privacy_note = "Community admins do not see who reported. Platform moderators do."
community_report_this_community = "Report this community"
community_more_actions = "More"
```

Capture list (Task 18): `ReportContentSheet` for `.community` and for `.post` (the footer), Town Hall as a guest with the menu open; light / dark / AX5. `#Preview`: add one to `ReportContentSheet` for `.community`.

Live check **(writes; owner opt-in)**: report the test community created in Task 5's live check from My communities → Report; `select reported_community_id, community_id from reports order by created_at desc limit 1` shows the id and a null `community_id`; the platform Communities list (Task 10) shows "Reported (1)". Clean-up: archiving the test community (Task 10 live check) ends it; the report stays pending (see Task 18 follow-ups).

---

### Task 5: Create a community and the invite sheet

**Model:** sonnet · **Files:**
- Create groups (Xcode MCP `XcodeMakeDir`, confirmed with `XcodeLS`): `NaarsCars/Features/Community/ViewModels` (app), `NaarsCars/NaarsCarsTests/Features/Community` (tests)
- Create (Xcode MCP, app target): `NaarsCars/Core/Utilities/QRCodeRenderer.swift`, `NaarsCars/Features/Community/ViewModels/CreateCommunityViewModel.swift`, `NaarsCars/Features/Community/Views/CreateCommunityView.swift`, `NaarsCars/Features/Community/ViewModels/CommunityInviteViewModel.swift`, `NaarsCars/Features/Community/Views/CommunityInviteSheet.swift`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/CreateCommunityViewModelTests.swift` (holds two classes: `CreateCommunityViewModelTests` and `CommunityInviteViewModelTests`)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `createCommunity`, `createInvite`, `fetchLiveInvites`, `revokeInvite` (Task 1); `PreviewCommunityService` (Task 1, previews only); `setCommunityPublic` (Task 2); `InviteCodeFormatter.formatCode` (display); `Constants.Community`, `Constants.URLs.appStore`.
- Produces:

```swift
@MainActor final class CreateCommunityViewModel: ObservableObject {
    @Published var name = ""; @Published var description = ""
    @Published var requiresApproval = true        // D11: new communities default to manual approval
    @Published var allowGuests = false            // shown to platform admins only (D7)
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var lastRefusal: CommunityRPCError?   // Task 9 reads .code == .ownedLimit
    let showsGuestToggle: Bool
    init(service: any CommunityServiceProtocol = CommunityService.shared,
         adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
         isPlatformAdmin: Bool = AuthService.shared.currentProfile?.isAdmin == true)
    var canSubmit: Bool                           // trimmed name in Constants.Community.nameLength, description ≤ 300, not submitting
    func submit() async -> CreatedCommunity?      // ignores a call while isSubmitting; sanitized name (Validators.sanitizeUserInput, max 60),
                                                  // nil description when blank, .approve / .invite; when allowGuests && showsGuestToggle,
                                                  // setCommunityPublic(true) afterwards (its failure sets errorMessage = community_create_public_failed
                                                  // and still returns the created community)
}
struct CreateCommunityView: View { init(service: any CommunityServiceProtocol = CommunityService.shared, onCreated: @escaping (UUID) -> Void) }
    // NavigationStack Form: name, description (character counts), approval toggle + footer, guest toggle (platform admins) + footer.
    // Create (confirmation toolbar item) → submit; success calls onCreated(id) at once, then pushes CommunityInviteSheet's content
    // in the same stack (back button hidden) with isAdmin: true — the creator is the community's owner; never
    // CommunityContext.isAdmin(of:), whose memberships have not refreshed yet (and never have in onboarding) — so the invite
    // opens immediately with a code (F1, Review Focus 7). .interactiveDismissDisabled(viewModel.isSubmitting). Cancel dismisses.
@MainActor final class CommunityInviteViewModel: ObservableObject {
    @Published private(set) var invite: CommunityInvite?
    @Published private(set) var liveCodes: [CommunityInviteRow] = []
    @Published var maxUses = 1                    // admin: 1...Constants.Community.adminInviteMaxUses
    @Published var expiryDays = 7                 // admin: one of inviteExpiryDayChoices
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    let communityId: UUID; let communityName: String; let isAdmin: Bool
    init(communityId:communityName:isAdmin:service: any CommunityServiceProtocol = CommunityService.shared,
         authService: any AuthServiceProtocol = AuthService.shared, now: @escaping () -> Date = Date.init)
    func prepare() async        // loadLiveCodes(); if none live, createCode()
    func createCode() async     // always sends an expiry, so a role the client has wrong is harmless (20261017_0005:849-866):
                                // member: createInvite(communityId:, maxUses: nil, expiresAt: now() + memberInviteLifetimeDays days)
                                //   (the server's member branch fixes 1 use and clamps the expiry to 7 days, :860-865);
                                // admin: createInvite(communityId:, maxUses: maxUses, expiresAt: now() + expiryDays days − 300 s)
                                //   (the margin keeps a 90-day choice inside the server's `now() + 90 days` check, :854, when the
                                //   phone's clock runs a little ahead). A member-path call the server treats as admin then gets 1 use
                                //   and the 7-day expiry; an admin-path call the server treats as member is clamped. Refusal → localizedMessage
    func loadLiveCodes() async  // needs SignedInUser.resolveId(authService:) (onboarding has no cached id)
    func revoke(_ row: CommunityInviteRow) async
    var displayedCode: String? { get }   // invite?.code ?? liveCodes.first?.code
    var shareMessage: String? { get }    // community_invite_share_message(communityName, Constants.URLs.appStore, code)
}
struct CommunityInviteSheet: View { init(communityId: UUID, communityName: String, isAdmin: Bool,
                                         service: any CommunityServiceProtocol = CommunityService.shared, onDone: @escaping () -> Void) }
    // code in InviteCodeFormatter.formatCode, monospaced, selectable; Copy (UIPasteboard + success toast), ShareLink(item: shareMessage),
    // QR image of shareMessage; member rule line or admin options (Stepper uses, Picker expiry) + New code; "Codes that still work"
    // list with Revoke; Done → onDone. .task { await viewModel.prepare() }
enum QRCodeRenderer { static func image(for text: String, dimension: CGFloat) -> UIImage? }
    // CIFilter.qrCodeGenerator(), correctionLevel "M", scaled with CGAffineTransform, rendered through one CIContext; interpolation .none in the view
```
- The QR encodes the share text (code plus App Store link): there is no Universal Link before Phase 4, which is outside this build (decision 1).

- [ ] **Step 1: Create the two groups and the test file**, then write the failing test (Review Focus 2):

```swift
func testSubmit_IgnoresSecondCallWhileSubmitting() async {
    // stub.actionGate suspends on a continuation; vm.name = "Ballard Neighbors"
    // let first = Task { await vm.submit() }; wait until stub.createCalls.count == 1; _ = await vm.submit(); resume; _ = await first.value
    // XCTAssertEqual(stub.createCalls.count, 1); XCTAssertEqual(stub.createCalls[0].joinPolicy, .approve)
}
// CommunityInviteViewModelTests (Review Focus 7), now = fixed date
func testCreateCode_MemberSendsSevenDayExpiry() async     // isAdmin false → createInviteCalls[0] == (A, maxUses: nil, expiresAt: now + 7 days)
func testCreateCode_AdminSendsUsesAndChosenExpiry() async // isAdmin true, maxUses 25, expiryDays 90 → (A, 25, now + 90 days − 300 s)
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CreateCommunityViewModel' in scope".
- [ ] **Step 3: Implement** the five app files (Xcode MCP) with `#Preview`s on `PreviewCommunityService` (`CreateCommunityView`; `CommunityInviteSheet` with its sample `NC7K2PQ9XA` and two live codes, member and admin variants); add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CreateCommunityViewModelTests -only-testing:NaarsCarsTests/CommunityInviteViewModelTests`. Expected: 3 pass.
- [ ] **Step 5: Commit** `[P2-T5] Create a community and open its invite sheet` with the files above and `project.pbxproj`.

Strings:
```
community_create_title = "Create a community"
community_create_name_label = "Name"
community_create_name_placeholder = "Ballard Neighbors"
community_create_name_length = "Use 2 to 60 characters."
community_create_description_label = "Description (optional)"
community_create_description_length = "Use at most 300 characters."
community_create_approval_toggle = "Approve new members manually"
community_create_approval_footer = "When this is off, anyone with an invite code joins right away."
community_create_guests_toggle = "Allow guests to browse"
community_create_guests_footer = "Guests can see its open requests, without addresses, and its Town Hall. Only platform admins can change this."
community_create_submit = "Create"
community_create_public_failed = "The community was created, but guests can't browse it yet. Try again from the Communities list."
community_invite_title = "Invite people"
community_invite_code_label = "Invite code"
community_invite_member_rule = "This code lets one person join and expires in 7 days."
community_invite_uses = "Can be used %lld times"
community_invite_expires_after = "Expires after"
community_invite_days_one = "%lld day"
community_invite_days_other = "%lld days"
community_invite_new_code = "New code"
community_invite_share = "Share invite"
community_invite_copy = "Copy code"
community_invite_copied = "Code copied"
community_invite_qr_accessibility = "QR code with the invite"
community_invite_share_message = "Join %1$@ on Naar's Cars, the app for neighbor rides and favors. Download it from %2$@, then enter the invite code %3$@."
community_invite_live_codes = "Codes that still work"
community_invite_revoke = "Revoke"
community_invite_expires_on = "Expires %@"
community_invite_used = "%1$lld of %2$lld used"
```

Capture list (Task 18): `CreateCommunityView` (member; platform admin with the guest toggle), `CommunityInviteSheet` (member, admin), light / dark / AX5; the 60-character name in the share line at AX5. `#Preview`: both (yes).

Live check **(writes; owner opt-in)**: as the owner, My communities → Create "P2 Live Check" with approval on → the invite sheet opens with a code; `select count(*) from notifications where type = 'announcement' and title = 'New community: P2 Live Check'` equals the number of other platform admins. Share and Copy work; New code adds a row; Revoke removes it (`revoked_at` set). Clean-up: archive it in Task 10's live check (one community a day: run this once).

---

### Task 6: Join sheet and the shared join options

**Model:** sonnet, high effort · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Community/ViewModels/JoinCommunityViewModel.swift`, `NaarsCars/Features/Community/Views/JoinCommunitySheet.swift`, `NaarsCars/Features/Community/ViewModels/CommunityJoinOptionsViewModel.swift`, `NaarsCars/Features/Community/Views/CommunityJoinOptionsView.swift`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/JoinCommunityViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `validateInvite`, `redeemInvite`, `requestToJoin`, `fetchPublicCommunities`, `CommunityInviteCode` (Task 1); `ReportContext.community` (Task 4).
- Produces:

```swift
enum JoinTarget: Equatable { case code(prefilled: String?), publicCommunity(PublicCommunity) }
@MainActor final class JoinCommunityViewModel: ObservableObject {
    @Published var code: String
    @Published private(set) var preview: InvitePreview?
    @Published var heardAbout = ""; @Published var joinReason = ""
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var result: JoinResult?
    let target: JoinTarget
    init(target: JoinTarget, service: any CommunityServiceProtocol = CommunityService.shared,
         onResult: @escaping @MainActor (JoinResult) -> Void = { _ in })
    var normalizedCode: String { get }          // CommunityInviteCode.normalize(code)
    var communityName: String? { get }          // preview?.communityName, or the public community's name
    var requiresApproval: Bool { get }          // code: preview?.requiresApproval ?? true; public: always true (request_to_join_community always makes a pending row, :1250-1268)
    var canSubmit: Bool { get }                 // a valid preview (or a public target), not already a member, answers present when requiresApproval, each ≤ 500
    func validate() async                       // malformed → errorMessage community_join_code_malformed, no call; otherwise validateInvite(normalizedCode):
                                                // valid → preview; expired → community_join_expired_named(name); invalid → community_error_invalid;
                                                // alreadyMember → community_join_already_member (preview kept, submit disabled)
    func submit() async                         // ignores a call while isWorking; answers sanitized (Validators.sanitizeUserInput, max 500, nil when blank);
                                                // redeemInvite(normalizedCode…) or requestToJoin(id…); sets result and calls onResult(result) in the
                                                // same main-actor turn, once (Review Focus 6); refusal → localizedMessage
}
struct JoinCommunitySheet: View { init(target: JoinTarget, service: any CommunityServiceProtocol = CommunityService.shared,
                                       onJoined: @escaping (JoinResult) -> Void) }
    // builds its view model with onResult: onJoined, so the presenter records the join the moment the server answers — a swipe
    // down from the done state loses nothing; .interactiveDismissDisabled(viewModel.isWorking) so the sheet cannot leave while
    // the request runs (a result that arrived after the view was gone would have nowhere to go).
    // code field + Check code (code target); preview card (name, approval line, member count when given); the two existing questions
    // (application_heard_about_label / application_join_reason_label and their placeholders, 500-character counters), required or
    // "answers optional"; the disclosure sentence community_join_disclosure(name) always shown above the button (spec §4 Phase 2);
    // Ask to join / Join; a done state (active or pending copy) whose Done only dismisses (the result was already reported);
    // toolbar Report → ReportContentSheet(.community(id: nil, code: normalizedCode, name:)) for a validated code target,
    // .community(id: community.id, code: nil, name:) for a public target (F20, A2)
@MainActor final class CommunityJoinOptionsViewModel: ObservableObject {
    @Published private(set) var publicCommunities: [PublicCommunity] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    init(service: any CommunityServiceProtocol = CommunityService.shared)
    func load(excluding excluded: Set<UUID>) async   // fetchPublicCommunities minus excluded; failure keeps [] and sets community_join_public_load_failed
}
struct CommunityJoinOptionsView: View { init(excludedCommunityIds: Set<UUID> = [], isEnabled: Bool = true, prefilledCode: String? = nil,
                                             service: any CommunityServiceProtocol = CommunityService.shared,
                                             onJoined: @escaping (JoinResult) -> Void) }
    // a VStack (no ScrollView, no NavigationStack, so onboarding, the waiting screen and My communities can host it): "Enter an invite code"
    // card → JoinCommunitySheet(.code(prefilled:)); "Ask to join a public community" with one card per public community → JoinCommunitySheet
    // (.publicCommunity); empty and failure states. Every card is .disabled(!isEnabled).
    // Presents the join sheet itself. The sheet's onJoined stores the result in @State recordedResult at once; the sheet's onDismiss
    // (Done or a swipe, either way) forwards onJoined(recordedResult) to the host once and clears it.
    // Prefilled code: .onChange(of: AutoOpen(code: prefilledCode, enabled: isEnabled), initial: true) — `initial: true` because the host
    // usually sets the code in its own .task, after this view appeared — opens the code sheet when the code is non-nil, isEnabled is true,
    // no sheet is up and that code is not the one already opened (@State openedPrefilledCode). A code that arrives while isEnabled is
    // false (onboarding's name step) opens when isEnabled turns true. This view never clears a stored code (Task 14 clears on redemption).
// Hosts: onboarding hosts it inline and acts in onJoined directly (the join sheet is already gone). My communities (Task 8) and the
// waiting screen (Task 13) host it inside their own sheet: in onJoined they record the result and set that outer sheet's flag to false,
// and they act in the outer sheet's onDismiss.
```

- [ ] **Step 1: Write the failing tests** (Review Focus 1 and 2):

```swift
func testValidate_SendsNormalizedCode() async        // code = "nc7k · 2pq9-xa" → stub.validateCalls == ["NC7K2PQ9XA"]
func testValidate_MalformedCodeIsNotSent() async     // "NC12" → validateCalls empty; errorMessage == "community_join_code_malformed".localized
func testSubmit_IgnoresSecondCallWhileSubmitting() async   // public target, answers filled, actionGate held → requestToJoinCalls.count == 1
func testSubmit_ReportsResultAsSoonAsItIsSet() async       // onResult records; after `await vm.submit()` (no Done) recorded == [JoinResult(B, .pending)];
                                                           // a second submit while result is set makes no call and records nothing more
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'JoinCommunityViewModel' in scope".
- [ ] **Step 3: Implement** the four app files with `#Preview`s on `PreviewCommunityService` (code target before and after validation; public target; options with two public communities, with none, with `failPublicCommunities`, and disabled); add the strings. `submit()` also returns at once when `result != nil`.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/JoinCommunityViewModelTests`. Expected: 4 pass.
- [ ] **Step 5: Commit** `[P2-T6] Join a community with a code or by asking a public one` with the files above and `project.pbxproj`.

Strings:
```
community_join_title = "Join a community"
community_join_enter_code = "Enter an invite code"
community_join_code_placeholder = "Invite code"
community_join_check_code = "Check code"
community_join_code_malformed = "That doesn't look like an invite code."
community_join_expired_named = "This code for %@ has expired or has been used up."
community_join_already_member = "You're already in this community or waiting for approval."
community_join_requires_approval = "An admin approves new members."
community_join_instant = "You'll join right away."
community_member_count_one = "%lld member"
community_member_count_other = "%lld members"
community_join_disclosure = "%@'s admins will see your name, photo, car and these answers. They never see your email or phone number."
community_join_answers_optional = "Answers are optional for this community."
community_join_submit_request = "Ask to join"
community_join_submit_join = "Join"
community_join_done_active_title = "You're in"
community_join_done_active_body = "Welcome to %@."
community_join_done_pending_title = "Request sent"
community_join_done_pending_body = "An admin of %@ will review your request."
community_join_public_section = "Ask to join a public community"
community_join_public_empty = "No public communities to join right now."
community_join_public_load_failed = "Couldn't load public communities."
community_join_public_hint = "Shows the community and lets you ask to join"
```

Capture list (Task 18): `JoinCommunitySheet` (code entry, preview needing approval with the disclosure, done pending, done active; public target), `CommunityJoinOptionsView` (list, empty); light / dark / AX5. `#Preview`: all four (yes).

Live check: as the owner, Join a community → Enter an invite code → the Task 5 code: preview shows "P2 Live Check", "An admin approves new members.", `already_member` disables Join. A malformed string shows the local message and `select count(*) from community_invite_attempts where user_id = <owner>` does not grow. **(writes)** Redeeming as a second account is Task 18 step 6.

---

### Task 7: Requests to join

**Model:** opus (moderation path, App Store 1.2; `CommunityContext` is a Core state holder) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Community/ViewModels/PendingMembersViewModel.swift`, `NaarsCars/Features/Community/Views/PendingMembersView.swift` (holds `PendingMemberDetailView`), `NaarsCars/Core/Protocols/ApplicantContactFetching.swift`
- Modify: `NaarsCars/Core/Services/AdminService.swift` (one method after `fetchPendingUsers`, `:151-167`, and the conformance; Architecture rule 5: a narrow protocol is added because the service is edited anyway)
- Modify: `NaarsCars/Core/Services/PreviewCommunityService.swift` (`ApplicantContactFetching` conformance, DEBUG)
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift` (`StubApplicantContactFetcher`)
- Modify: `NaarsCars/App/CommunityContext.swift:113-121` (init), `:123-150` (lookups)
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift:227` (Pending approvals link)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/PendingMembersViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityAdminServiceProtocol` (Task 2), `StubCommunityAdminService`, `CommunityRPCError`.
- Produces on `CommunityContext`:

```swift
init(service:defaults:now:, platformAdminProvider: @escaping @MainActor () -> Bool = { AuthService.shared.currentProfile?.isAdmin == true })
var isPlatformAdmin: Bool { get }
func membership(for communityId: UUID?) -> CommunityMembership?
func isAdmin(of communityId: UUID) -> Bool          // active owner / admin membership, or isPlatformAdmin
var pendingMemberships: [CommunityMembership] { get }
var administeredPendingTotal: Int { get }           // sum of pendingCount over active owner / admin memberships
```
- Produces:

```swift
enum PendingMembersTarget: Hashable { case community(UUID, name: String?), defaultCommunity }
// ApplicantContactFetching.swift
struct ApplicantContact: Decodable, Equatable, Sendable { let email: String?; let phoneNumber: String? }   // keys email, phone_number
protocol ApplicantContactFetching: AnyObject { func fetchApplicantContact(userId: UUID) async throws -> ApplicantContact }
// AdminService (platform admins only):
func fetchApplicantContact(userId: UUID) async throws -> ApplicantContact
    // try await verifyAdminStatus() (AdminService.swift:125-144), then from("profiles").select("email, phone_number")
    // .eq("id", value: userId.uuidString).single(), decoded with JSONDecoder — the fetchPendingUsers idiom (:151-167). The table, not
    // public_profiles: that view has no email or phone (20261017_0002:343-345), and profiles_select_admin lets a platform admin read
    // the row (20260417015221_security_profiles_projection_split.sql:43-45). No CacheManager read or write: ProfileService.fetchProfile
    // (ProfileService.swift:39-60) reads public_profiles for anyone but the caller and can answer from a cached public profile.
extension AdminService: ApplicantContactFetching {}
@MainActor final class PendingMembersViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }
    @Published private(set) var access: Access = .checking
    @Published private(set) var communityId: UUID?
    @Published private(set) var communityName: String?
    @Published private(set) var applicants: [CommunityMember] = []
    @Published private(set) var isLoading = false
    @Published var loadError: String?            // full-screen ErrorView only while applicants is empty
    @Published var actionErrorMessage: String?   // errorBanner
    @Published private(set) var actingOnUserId: UUID?
    @Published private(set) var contacts: [UUID: ApplicantContact] = [:]
    init(target: PendingMembersTarget, adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
         communityContext: CommunityContext? = nil, contactFetcher: any ApplicantContactFetching = AdminService.shared,
         refreshBadges: @escaping @MainActor () async -> Void = { _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "communityMemberDecision") })
    func load() async
    func approve(_ member: CommunityMember) async
    func reject(_ member: CommunityMember) async
    func loadContact(for member: CommunityMember) async   // returns unless communityContext.isPlatformAdmin and contacts[id] is nil;
                                                          // contactFetcher.fetchApplicantContact(userId:) → contacts[id]; failure leaves it
                                                          // nil and the detail shows no contact section (no banner)
}
struct PendingMembersView: View { init(target: PendingMembersTarget) }   // no NavigationStack: always pushed
```
- `load()`: (1) resolve the id — `.community(id, _)`; `.defaultCommunity` → the `isDefault` membership, else `adminService.fetchDefaultCommunityId()`; (2) when the context has not loaded memberships (`isAwaitingMemberships`), `await communityContext.refreshMemberships()`; (3) `isAdmin(of:)` false → `access = .notAdmin`, **no list call** (`get_community_members` answers `[]` to a non-admin, `:1883-1890`, which would read as "no requests"); (4) `fetchCommunityMembers(communityId:, status: .pending, limit: Constants.Community.pendingMembersPageSize, offset: 0)`. Name: the target's name, else `communityContext.name(for:)`.
- `approve` / `reject`: return while `actingOnUserId != nil`; on success remove the row **first**, then `await communityContext.refreshMemberships()` (pending counts) and `await refreshBadges()`, `HapticManager.success()`. Refusal with `code == nil` (the unauthorized answers, `:1309`, `:1373`) → `access = .notAdmin` (spec §3.7: "an inline … state rather than an error screen"); `.notPending` → drop the row, no banner; any other code → `actionErrorMessage = localizedMessage`; a non-RPC error → `community_error_generic`.
- Rows (`.cardStyle()` cards on `Color.naarsBackground`): `AvatarView(imageUrl:name:size: 44)`, name, car, `community_pending_invited_by` when set, `community_pending_applied` with the relative date, the two answers under `admin_heard_about_label` / `admin_join_reason_label`, Approve (`PrimaryButton`) and Decline (`SecondaryButton`), each behind a confirmation alert; a platform admin's row links to `PendingMemberDetailView` (same content plus `contacts[id]`, loaded in its `.task` through the `AdminService` read above; spec §3.7 Admin: "they still see email and phone on the detail, through their existing `profiles` read"). Empty state `EmptyStateView`; not-admin state a centred icon and `community_pending_not_admin`; skeleton while loading.
- `AdminPanelView` Pending approvals row → `PendingMembersView(target: .defaultCommunity)` (spec §3.7 Admin: a new-build platform admin never uses the legacy direct UPDATE again). `PendingUsersView` stays in the project unreferenced once Task 11 lands (Phase 5 deletes it).

- [ ] **Step 1: Write the failing tests** (spec §3.7 inline not-admin state; Review Focus 2 and 3):

```swift
func testLoad_NotAdminShowsInlineStateWithoutFetching() async     // member role → access .notAdmin; fetchMembersCalls empty
func testApprove_IgnoresSecondTapWhileActing() async               // actionGate held; approve(a); approve(b) → approveCalls.count == 1
func testApprove_RemovesRowEvenWhenRefreshFails() async            // context stub fails its refresh → applicants no longer contains a; actionErrorMessage nil
func testReject_RefusalWithoutCodeShowsNotAdminState() async       // rejectResult = refusal with nil code → access .notAdmin
func testLoadContact_OnlyPlatformAdminsReadContact() async        // platformAdminProvider false → fetcher.calls empty; true → calls == [a.id],
                                                                    // contacts[a.id] == stubbed email and phone
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'PendingMembersViewModel' in scope".
- [ ] **Step 3: Implement** (the protocol file through the Xcode MCP, app target); `#Preview`s on `PreviewCommunityService` (it serves as admin service and contact fetcher) for list, empty, not-admin (`adminRefusal` set, or a context with a member-role membership), detail with contact; add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/PendingMembersViewModelTests -only-testing:NaarsCarsTests/AppLaunchManagerTests/testCommunityContext_RestoreReadsThePersistedKeys`. Expected: all pass (5 new).
- [ ] **Step 5: Commit** `[P2-T7] Approve and decline requests to join` with the files above and `project.pbxproj`.

Strings:
```
community_pending_title = "Requests to join"
community_pending_empty_title = "No requests to join"
community_pending_empty_body = "New requests appear here."
community_pending_not_admin = "You are not an admin of this community."
community_pending_invited_by = "Invited by %@"
community_pending_applied = "Asked %@"
community_pending_approve = "Approve"
community_pending_decline = "Decline"
community_pending_approve_title = "Approve %@?"
community_pending_approve_body = "They'll see this community's requests, Town Hall and members."
community_pending_decline_title = "Decline %@?"
community_pending_decline_body = "Their request is removed. Their account is not deleted."
community_pending_contact = "Contact (platform admins only)"
```

Capture list (Task 18): list, empty, not-admin, detail; light / dark / AX5. `#Preview`: `PendingMembersView`, `PendingMemberDetailView` (yes).

Live check: as the owner (platform admin), Admin → Pending approvals opens Seattle's Requests to join; its row count equals `select count(*) from community_members m join communities c on c.id = m.community_id where c.is_default and m.status = 'pending'`; opening an applicant shows the email and phone that `select email, phone_number from profiles where id = <applicant>` returns (read-only). **(writes)** Approve and Decline are Task 18 step 6.

---

### Task 8: My communities

**Model:** opus (a leave can end the person's last membership and moves the session through `recheckAccountStatus`, fragile system 5) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Community/ViewModels/MyCommunitiesViewModel.swift`, `NaarsCars/Features/Community/Views/MyCommunitiesView.swift`, `NaarsCars/Features/Community/Views/LeaveCommunitySheet.swift`
- Modify: `NaarsCars/App/CommunityContext.swift:229-248` (add `forgetMembership`)
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:70-75` (new row between the admin link and Account settings)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/MyCommunitiesViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 1 member wrappers; `CreateCommunityView` (Task 5); `CommunityInviteSheet` (Task 5); `CommunityJoinOptionsView` (Task 6); `PendingMembersView`, `PendingMembersTarget`, `CommunityContext.isAdmin(of:)`, `administeredPendingTotal` (Task 7); `ReportContentSheet(.community…)` (Task 4).
- Produces:

```swift
// CommunityContext
func forgetMembership(_ communityId: UUID) async   // drops the row locally through apply(_:) (tab, narrow and last-posted normalise as on a load);
                                                   // calls onActiveMembershipsEmpty when no active row is left
// MyCommunitiesViewModel.swift
struct LeaveConsequences: Equatable { let reopened: Int; let removed: Int; let cancelled: Int
    static func estimate(rides: [SDRide], favors: [SDFavor], userId: UUID, communityId: UUID) -> LeaveConsequences }
    // the unwind_member_requests rules (20261017_0004, STEP (1)-(3)), over rows of that communityId only:
    // reopened = claimedBy == userId && status == "confirmed"; cancelled = userId == userId && claimedBy != nil && status != "completed";
    // removed = userId == userId && claimedBy == nil && status != "completed"
enum LeavePlan: Equatable { case withdrawRequest, leave(LeaveConsequences), closesCommunity(LeaveConsequences) }
    // pending → withdrawRequest; owner with memberCount <= 1 and not default → closesCommunity; otherwise leave
    // (a sole owner with other members gets the server's last_owner refusal, shown as its localized message; Phase 3 adds transfer)
@MainActor final class MyCommunitiesViewModel: ObservableObject {
    @Published private(set) var limits: CommunityLimits?
    @Published var toastMessage: String?; @Published var errorMessage: String?
    @Published private(set) var busyCommunityId: UUID?
    init(service: any CommunityServiceProtocol = CommunityService.shared, communityContext: CommunityContext? = nil,
         authService: any AuthServiceProtocol = AuthService.shared,
         refreshDashboard: @escaping @MainActor (String) async -> Void = { _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0) })
    func setup(modelContext: ModelContext)            // the RequestsDashboardViewModel idiom (RequestsDashboardViewModel.swift:103-104)
    var active: [CommunityMembership] { get }; var pending: [CommunityMembership] { get }
    func load() async                                 // refreshMemberships(); fetchMyCommunityLimits() (failure → limits nil, no error)
    func leavePlan(for membership: CommunityMembership) -> LeavePlan   // counts from the local SDRide / SDFavor store
    func leave(_ membership: CommunityMembership) async -> Bool
        // leaveCommunity; on success: forgetMembership(id) then refreshMemberships() (either may end in recheckAccountStatus through
        // onActiveMembershipsEmpty), refreshDashboard("leftCommunity"), toast community_left_toast; refusal → errorMessage
    func setMuted(_ muted: Bool, for membership: CommunityMembership) async   // setCommunityMuted, then refreshMemberships()
    func didJoin(_ result: JoinResult) async          // refreshMemberships(); active → refreshDashboard("joinedCommunity") + community_joined_toast; pending → community_requested_toast
    func didCreate(_ communityId: UUID) async         // refreshMemberships(); refreshDashboard("joinedCommunity")
}
struct MyCommunitiesView: View      // pushed from Profile; no NavigationStack
struct LeaveCommunitySheet: View { init(membership: CommunityMembership, plan: LeavePlan, isOnlyActiveCommunity: Bool, onConfirm: @escaping () -> Void) }
```
- `MyCommunitiesView` (`List`, `.insetGrouped`, on `Color.naarsBackground`): "Your communities" rows (name; role `NaarsChip` `community_role_*`; `community_muted_chip` when `notificationsMuted || mutedUntil > now`; member count) with a trailing `Menu` (`community_actions_accessibility(name)`): Invite (`canInvite`) → `CommunityInviteSheet(isAdmin: isAdmin(of:))`; Requests to join (n) (`isAdmin(of:)`); Mute / Unmute; Report → `ReportContentSheet(.community(id:, code: nil, name:))`; Leave → `LeaveCommunitySheet`. An admin row with `pendingCount > 0` also shows an inline `NavigationLink(value: PendingMembersTarget.community(id, name: name))` with a `NotificationBadge`. "Waiting for approval" rows: `community_status_pending` chip; Menu: Report, Withdraw request. Actions section: Create (sheet `CreateCommunityView`, record id, `didCreate` on dismiss), Join a community (sheet hosting `CommunityJoinOptionsView(excludedCommunityIds: every membership id, prefilledCode: joinPrefilledCode)` in a `NavigationStack` + `ScrollView`; its `onJoined` stores the result and sets `showJoin = false`, closing the outer sheet; `didJoin` runs in that outer sheet's `onDismiss`, so a join whose inner sheet was swiped away is still recorded; `joinPrefilledCode` stays nil until Task 14). `.navigationDestination(for: PendingMembersTarget.self)`. `.task { setup; await load() }`, `.refreshable { await load() }`, success toast, `.errorBanner(message: $viewModel.errorMessage)`.
- `LeaveCommunitySheet` shows `community_leave_title(name)`, then only the non-zero count lines (`_one` / `_other`), or `community_leave_nothing`; always `community_leave_keeps`; `community_leave_only_community` when it is the only active membership; `community_leave_closes(name)` for `closesCommunity`; withdraw copy for `withdrawRequest` (spec §2.1 rule 13, D26, S12).
- `MyProfileView` row: `community_my_profile_row` with `person.3.fill`, a `NotificationBadge(count: CommunityContext.shared.administeredPendingTotal)` when above zero, `NavigationLink { MyCommunitiesView() }`, identifier `profile.myCommunities` (spec §1.1: the one new Profile row).

- [ ] **Step 1: Write the failing tests** (spec §3.7: the `leftCommunity` refresh; rule 13 counts; Review Focus 3). In-memory `ModelContainer(for: SDRide.self, SDFavor.self …)` as `CommunityStoreScopingTests` does, and a `CommunityContext` on a suite with `debugSetMemberships`:

```swift
func testEstimate_FollowsTheUnwindRulesInThatCommunityOnly()   // in A: my confirmed claim, my open, my confirmed-with-helper, my completed; in B: my open
                                                                 // → LeaveConsequences(reopened: 1, removed: 1, cancelled: 1)
func testLeave_RefreshesDashboardWithLeftCommunityTrigger() async   // refreshDashboard records ["leftCommunity"]
func testLeave_HidesCommunityWhenRefreshFails() async           // context service fails after the leave succeeds → active no longer contains A
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'MyCommunitiesViewModel' in scope".
- [ ] **Step 3: Implement**; `#Preview`s for My communities (one membership; `PreviewCommunityService.sampleMemberships`: an owner row with requests and a pending row; the view model and its `CommunityContext` both on `PreviewCommunityService`) and the Leave sheet (each plan); add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/MyCommunitiesViewModelTests`. Expected: 3 pass.
- [ ] **Step 5: Commit** `[P2-T8] Add My communities: mute, leave, invite, report, requests to join` with the files above and `project.pbxproj`.

Strings:
```
community_my_title = "My communities"
community_my_profile_row = "My communities"
community_section_yours = "Your communities"
community_section_waiting = "Waiting for approval"
community_role_owner = "Owner"
community_role_admin = "Admin"
community_role_member = "Member"
community_status_pending = "Waiting for approval"
community_muted_chip = "Muted"
community_action_create = "Create a community"
community_action_join = "Join a community"
community_action_invite = "Invite people"
community_action_requests = "Requests to join"
community_action_mute = "Mute notifications"
community_action_unmute = "Unmute notifications"
community_action_report = "Report"
community_action_leave = "Leave"
community_action_withdraw = "Withdraw request"
community_actions_accessibility = "Actions for %@"
community_leave_title = "Leave %@?"
community_leave_reopened_one = "%lld claim you made will reopen and its poster will be told."
community_leave_reopened_other = "%lld claims you made will reopen and their posters will be told."
community_leave_removed_one = "%lld open request you posted will be removed."
community_leave_removed_other = "%lld open requests you posted will be removed."
community_leave_cancelled_one = "%lld request you posted that a neighbor claimed will be cancelled, and the helper will be told."
community_leave_cancelled_other = "%lld requests you posted that neighbors claimed will be cancelled, and the helpers will be told."
community_leave_nothing = "You have no open requests or claims here."
community_leave_keeps = "Your posts and comments stay. Invite codes you made for this community stop working."
community_leave_only_community = "This is your only community. After you leave you can join or create another."
community_leave_closes = "You're the only member, so leaving closes %@."
community_leave_confirm = "Leave"
community_withdraw_title = "Withdraw your request to join %@?"
community_withdraw_confirm = "Withdraw"
community_left_toast = "You left %@."
community_joined_toast = "You joined %@."
community_requested_toast = "Request sent to %@."
```

Capture list (Task 18): My communities (one membership; three via `-debugCommunityCount 3`), the Leave sheet (counts, nothing, closes, withdraw), the Profile row; light / dark / AX5, the 60-character name at AX5. `#Preview`: `MyCommunitiesView`, `LeaveCommunitySheet` (yes).

Live check: as the owner, Profile → My communities lists Naar's Cars Seattle with the Owner chip. **(writes)** Mute → `select notifications_muted, muted_until from community_members where user_id = <owner>` reads true / null and the Muted chip shows; Unmute restores false. Leave is checked only on the Task 5 test community, as Task 18 step 6 says.

---

### Task 9: Owned-community limit request (A1, member side)

**Model:** sonnet · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Community/ViewModels/OwnedLimitRequestViewModel.swift`, `NaarsCars/Features/Community/Views/OwnedLimitRequestSheet.swift`
- Modify: `NaarsCars/Features/Community/ViewModels/MyCommunitiesViewModel.swift`, `NaarsCars/Features/Community/Views/MyCommunitiesView.swift`, `NaarsCars/Features/Community/Views/CreateCommunityView.swift`
- Modify: `NaarsCars/NaarsCarsTests/Features/Community/MyCommunitiesViewModelTests.swift` (one test: a crash guard)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `fetchMyCommunityLimits`, `requestOwnedCommunityLimit` (Task 1); `CreateCommunityViewModel.lastRefusal` (Task 5). A platform admin can approve exactly 20 (`decide_owned_community_limit`, block 10; requests are 4–20, `:503`), so `currentMax` reaches the ceiling.
- Produces:

```swift
enum LimitOffer: Equatable { case requestPending(requestedMax: Int), canRequest(currentMax: Int, ownedCount: Int) }
// MyCommunitiesViewModel
var limitOffer: LimitOffer? { get }   // latestRequest pending → requestPending; ownedCount >= maxOwned && OwnedLimitRequestViewModel.canRequestMore(currentMax: maxOwned)
                                      // → canRequest; else nil
@MainActor final class OwnedLimitRequestViewModel: ObservableObject {
    @Published var requested: Int; @Published var reason = ""
    @Published private(set) var isSubmitting = false; @Published var errorMessage: String?
    init(currentMax: Int, service: any CommunityServiceProtocol = CommunityService.shared)   // requested = range.lowerBound
    static func canRequestMore(currentMax: Int) -> Bool   // currentMax < Constants.Community.limitRequestRange.upperBound (20)
    var range: ClosedRange<Int> { get }     // total for every currentMax (never builds lower > upper, which traps):
                                            // let r = Constants.Community.limitRequestRange; let lower = min(max(r.lowerBound, currentMax + 1), r.upperBound)
                                            // return lower...r.upperBound   (20...20 at or above the ceiling)
    var canSubmit: Bool { get }             // canRequestMore(currentMax:), trimmed reason 1...500, requested in range, not submitting
    func submit() async -> Bool             // returns false without a call unless canSubmit; refusal (request_open, under_limit) → localizedMessage
}
struct OwnedLimitRequestSheet: View { init(currentMax: Int, service: any CommunityServiceProtocol = CommunityService.shared, onSent: @escaping () -> Void) }
struct CreateCommunityView: View { init(service:…, onCreated: @escaping (UUID) -> Void, onRequestHigherLimit: (() -> Void)? = nil) }
    // on an owned_limit refusal, the error section shows community_limit_request_button only when onRequestHigherLimit is set and
    // OwnedLimitRequestViewModel.canRequestMore(currentMax: lastRefusal.maxOwned ?? 0) — at maxOwned 20 the refusal text alone shows
```
- My communities shows, above the actions, `community_limit_request_pending(n)` for `requestPending` (A1: "the request's status shows on that screen until decided") or `community_limit_offer(owned)` with the request button for `canRequest`; Create's refusal path opens the same sheet; after `onSent`, `load()` again.

- [ ] **Step 1: Write the failing test** (a crash guard, not a spec-named test; `ClosedRange` traps when its lower bound exceeds its upper bound):

```swift
func testLimitRequestRange_IsTotalAtAndAboveTheCeiling() async   // currentMax 3 → 4...20; 19 → 20...20; 20 → 20...20, canRequestMore false;
                                                                  // 25 → 20...20; limitOffer with limits(maxOwned 20, ownedCount 20) == nil
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'OwnedLimitRequestViewModel' in scope".
- [ ] **Step 3: Implement** with `#Preview`s on `PreviewCommunityService` (sheet; My communities with each offer, set through `limits`); add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/MyCommunitiesViewModelTests`. Expected: 4 pass. The two wrappers are pinned in Task 1.
- [ ] **Step 5: Commit** `[P2-T9] Ask for a higher owned-community limit` with the files above and `project.pbxproj`.

Strings:
```
community_limit_offer = "You own %lld communities, the most your account allows."
community_limit_request_button = "Request a higher limit"
community_limit_request_title = "Request a higher limit"
community_limit_request_number = "Own up to %lld communities"
community_limit_request_reason = "Why do you need more?"
community_limit_request_submit = "Send request"
community_limit_request_pending = "Your request to own up to %lld communities is waiting for a platform admin."
community_limit_request_sent = "Request sent"
```

Capture list (Task 18): the sheet, both offer rows; light / dark / AX5. `#Preview`: yes.

Live check: as the owner, My communities shows no offer while under the limit (`get_my_community_limits` as the owner, read-only, reads `can_create` false only because of the Task 5 creation today, `owned_count` below `max_owned`).

---

### Task 10: Platform Communities list (A1 decisions, A2 remedy, F22)

**Model:** opus, high effort (platform moderation: `archive_community` notifies every active member, cancels each confirmed request and drops its completion reminder, `20261017_0005:227-234`; `set_community_public(false)` takes a community away from guests and the public join list; one mistaken tap reaches a whole community) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Admin/ViewModels/CommunitiesAdminViewModel.swift`, `NaarsCars/Features/Admin/Views/CommunitiesAdminView.swift`
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift:221-260` (a "Communities" link after Pending approvals)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `fetchPlatformCommunities`, `archiveCommunity`, `unarchiveCommunity`, `setCommunityPublic`, `decideOwnedCommunityLimit` (Task 2); `PendingMembersView`, `PendingMembersTarget` (Task 7).
- Produces:

```swift
enum CommunityAdminAction: Equatable { case requestsToJoin, archive, restore, makePrivate, makePublic }
@MainActor final class CommunitiesAdminViewModel: ObservableObject {
    @Published private(set) var communities: [PlatformCommunity] = []
    @Published private(set) var limitRequests: [PlatformLimitRequest] = []
    @Published private(set) var isLoading = false
    @Published var loadError: String?; @Published var actionErrorMessage: String?; @Published var toastMessage: String?
    @Published private(set) var busyId: UUID?
    init(adminService: any CommunityAdminServiceProtocol = CommunityService.shared)
    static func actions(for community: PlatformCommunity) -> [CommunityAdminAction]
        // requestsToJoin when pendingCount > 0 and not archived; archive when not default and not archived; restore when archived;
        // makePrivate when public, not default, not archived (A2 remedy; the default community stays public, :710-712);
        // makePublic when not public and not archived
    func load() async
    func perform(_ action: CommunityAdminAction, on community: PlatformCommunity) async   // returns while busyId != nil (one action at a time);
                                                                                          // re-checks actions(for:) contains it; then load();
                                                                                          // refusal → localizedMessage (these RPCs refuse with no code,
                                                                                          // so the generic message); never a success toast on refusal
    func decide(_ request: PlatformLimitRequest, approve: Bool) async                      // removes the row on success, toast
}
struct CommunitiesAdminView: View    // pushed from AdminPanelView
```
- Rows: name, `NaarsChip`s `admin_communities_default_chip`, `…_public_chip`, `…_archived_chip`, `…_no_owner_chip` (ownerCount == 0), `…_reported_chip(n)` (openReportCount > 0, tint the warning token); `admin_communities_members(member, pending)`; `admin_communities_created_by(creator ?? "—", date)`; a trailing `Menu` of `actions(for:)`; Archive behind a destructive confirmation (`…_archive_title`, `…_archive_body`) and Make private behind one (`…_make_private_title`, `…_make_private_body`); Restore and Make public run at once; Requests to join pushes `PendingMembersView(target: .community(id, name: name))`. A "Limit requests" section above the list (only when non-empty): `admin_communities_limit_row(name, requested, current, owned)`, the reason, Approve / Decline.

- [ ] **Step 1: Implement** with a `#Preview` on `PreviewCommunityService` (its `samplePlatformCommunities`: Seattle, Ballard with requests, an archived reported community, one limit request; Swift values, nothing from the test target); add the strings. Invariant to state in the report: `actions(for:)` never offers Archive or Make private for the default community (the server refuses both, `:710-712`, `:747-748`), and no action runs without its confirmation where one is listed.
- [ ] **Step 2: BUILD.** No unit test is named; the wrappers are pinned in Task 2.
- [ ] **Step 3: Commit** `[P2-T10] Add the platform Communities list with archive, restore and limit decisions` with the files above and `project.pbxproj`.

Strings:
```
admin_communities_title = "Communities"
admin_communities_hint = "Review, archive and restore communities"
admin_communities_limit_requests = "Limit requests"
admin_communities_limit_row = "%1$@ asks to own up to %2$lld (now %3$lld, owns %4$lld)"
admin_communities_approve = "Approve"
admin_communities_decline = "Decline"
admin_communities_default_chip = "Default"
admin_communities_public_chip = "Public"
admin_communities_archived_chip = "Archived"
admin_communities_no_owner_chip = "No owner"
admin_communities_reported_chip = "Reported (%lld)"
admin_communities_members = "%1$lld members · %2$lld waiting"
admin_communities_created_by = "Created by %1$@ · %2$@"
admin_communities_requests = "Requests to join"
admin_communities_archive = "Archive"
admin_communities_restore = "Restore"
admin_communities_make_private = "Make private"
admin_communities_make_public = "Make public"
admin_communities_archive_title = "Archive %@?"
admin_communities_archive_body = "Members lose access at once and are told. Claimed requests are cancelled and their posters and helpers are told. Its content is kept and you can restore it."
admin_communities_make_private_title = "Make %@ private?"
admin_communities_make_private_body = "Guests can no longer browse it, and people can join only with an invite code. Members keep their access."
admin_communities_empty = "No communities yet."
```

Capture list (Task 18): the list with a limit request, a row's menu for Seattle (no Archive, no Make private) and for an archived row; light / dark / AX5. `#Preview`: yes.

Live check: as the owner, Admin → Communities lists Naar's Cars Seattle with Default and Public and no Archive or Make private item. **(writes)** Archive "P2 Live Check" → `archived_at` set and it leaves My communities after a refresh; Restore → back; Archive again as the final clean-up (needs block 5 live).

---

### Task 11: Routing — `pending_approval`, My communities, `.enterApp`

**Model:** opus (Notification Routing, fragile system 4; `NavigationCoordinator` and `DeepLinkParser` are high-blast seams) · **Files:**
- Modify: `NaarsCars/Core/Utilities/DeepLinkParser.swift:11-27, 101-103`
- Modify: `NaarsCars/App/NavigationIntent.swift:24-46`
- Modify: `NaarsCars/App/NavigationCoordinator.swift:13-26` (`NotificationIntent`), `:169-214` (`applyDeepLink`), `:226-277` (`isSameDeepLink`), `:299-342` (`applyNotificationIntent`), `:352-371` (guest gating)
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift:128-129`
- Modify: `NaarsCars/App/AppDelegate.swift:381-384`
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:27` (state), `:137-152` (intent handlers), `:187-192` (destinations), `:594-622` (`applyProfileIntent`)
- Create (normal tools): `Docs/qa/push-fixtures/pending_approval_with_community.apns`, `pending_approval_without_community.apns`, `user_approved_further_community.apns`
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/DeepLinkParserTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift:38-47`

**Interfaces:**
- Consumes: `PendingMembersView`, `PendingMembersTarget` (Task 7); `MyCommunitiesView` (Task 8).
- Produces: `DeepLink.pendingMembers(communityId: UUID)`; the parser returns it for `pending_approval` when `community_id` parses, else `.pendingUsers` as today (spec §3.7 Navigation "Applicants"). `NavigationIntent.pendingMembers(UUID)` and `NavigationIntent.myCommunities`, both `targetTab == .profile`. `NotificationIntent.openPendingMembers(communityId: UUID)` → `pendingIntent = .pendingMembers(id); selectedTab = .profile`. The router returns `.openPendingMembers(communityId:)` for a `pendingApproval` bell row with `communityId`, else `.openPendingUsers`.
- `applyDeepLink`: `.pendingMembers(id)` → `.pendingMembers(id)`; `.enterApp` → `.myCommunities` (spec §3.7: "`.myCommunities` from Phase 2"; only `AppLaunchManager.handleEnterAppIntent` reaches it, and only while authenticated, D22). `isSameDeepLink` compares `.pendingMembers` by id and `.enterApp` against `.myCommunities` (split from `.dashboard`).
- `intentIsAdminOnly` and the admin arm of `intentRequiresAuth` include `.pendingMembers` (guests drop it, spec §3.7); `intentRequiresAuth(.myCommunities) == true`. The `AppDelegate` group at `:381-384` gains `.pendingMembers`. Any other exhaustive switch the compiler names gets the Profile-tab behaviour.
- `MyProfileView`: `@State private var pendingMembersTarget: PendingMembersTarget?` with `.navigationDestination(item:)`, `@State private var showMyCommunities` with `.navigationDestination(isPresented:)`; `applyProfileIntent`: `.pendingUsers` → `.defaultCommunity` (replaces `showPendingUsersList` and the `PendingUsersView` destination), `.pendingMembers(id)` → `.community(id, name: nil)`, `.myCommunities` → `showMyCommunities = true`; each clears `pendingIntent`. The `.onAppear` list (`:146-150`) gains both new cases. `affectedDomains` of `pending_approval` stays `[.dashboard]`; the badge refresh every push triggers picks up `pending_members_total` (Task 3).
- Push fixtures (JSON, `aps` + `type` + ids; placeholders `<COMMUNITY_ID>`, `<USER_ID>` filled in Task 18).

- [ ] **Step 1: Write the failing tests** (spec §4 Phase 2: parser and routing tests for `pending_approval` with and without `community_id`):

```swift
// DeepLinkParserTests
func testParse_PendingApprovalWithCommunityIdRoutesToPendingMembers()   // .pendingMembers(communityId: c)
func testParse_PendingApprovalWithMalformedCommunityIdStaysPendingUsers()
// (existing testParse_AdminNotification keeps asserting .pendingUsers without the key)
// NavigationCoordinatorRoutingTests
func testApplyPushDeepLink_PendingMembersSetsIntentForProfileTab()   // pendingIntent == .pendingMembers(c); .targetTab == .profile
func testRouter_PendingApprovalBellRowWithCommunityOpensPendingMembers()
func testRouter_PendingApprovalBellRowWithoutCommunityOpensPendingUsers()
func testPendingMembersIsAdminOnlyAndMyCommunitiesRequiresAuth()
// edit testEnterAppWhileAuthenticated_DoesNotRelaunch: XCTAssertEqual(coordinator.pendingIntent, .myCommunities)
```
- [ ] **Step 2: RED.** `RED`. Expected: "type 'DeepLink' has no member 'pendingMembers'".
- [ ] **Step 3: Implement**; write the three fixtures.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/DeepLinkParserTests -only-testing:NaarsCarsTests/NavigationCoordinatorRoutingTests -only-testing:NaarsCarsTests/NavigationCoordinatorTests -only-testing:NaarsCarsTests/WebhookPayloadDecodingTests -only-testing:NaarsCarsTests/AppDelegateNotificationHandlingTests`. Expected: all pass.
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P2-T11] Route pending_approval to Requests to join and .enterApp to My communities` with the files above.

Live check (Task 18 step 5): the three `simctl push` fixtures.

---

### Task 12: Community onboarding as the `.needsApplication` root

**Model:** opus (Auth and Launch State, fragile system 5: the root of an `AuthState`) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Authentication/ViewModels/CommunityOnboardingViewModel.swift`, `NaarsCars/Features/Authentication/Views/CommunityOnboardingView.swift`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/CommunityOnboardingViewModelTests.swift`
- Modify: `NaarsCars/App/ContentView.swift:55-58` (one line)
- Modify: `NaarsCars/Features/Authentication/ViewModels/ApplicationFieldsViewModel.swift:24, 56` (`applePlaceholderName` and `nameProblem(_:)` from `private` to internal; no other change)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityJoinOptionsView(isEnabled:prefilledCode:service:onJoined:)` (Task 6), `CreateCommunityView` + `CommunityInviteSheet` (Task 5), `PreviewCommunityService` (previews), `accountDeletionFlow`, `AccountTextAction`, `BannedAccountViewModel` (`Features/Authentication/Views/BannedAccountView.swift:128-229`), `SignedInUser.resolveId(authService:)`, `ApplicationFieldsViewModel.loadNameRequirement` (`ApplicationFieldsViewModel.swift:39-53`) and the `updateProfile` call of its `submitApplication` (`:101-109`).
- Produces:

```swift
@MainActor final class CommunityOnboardingViewModel: ObservableObject {
    @Published private(set) var needsName = false
    @Published private(set) var hasLoadedNameRequirement = false
    @Published var name = ""; @Published var nameError: String?
    @Published private(set) var isSavingName = false
    @Published var prefilledCode: String?                  // Task 14 fills it
    // Two closures instead of the 14-method ProfileServiceProtocol, so the tests and the preview need no profile stub:
    init(loadStoredName: @escaping @MainActor () async -> String? = CommunityOnboardingViewModel.storedNameFromProfile,
         updateName: @escaping @MainActor (String) async throws -> Void = CommunityOnboardingViewModel.saveNameToProfile,
         relaunch: @escaping @MainActor () -> Void = { Task { @MainActor in await AppLaunchManager.shared.performCriticalLaunch() } })
    static func storedNameFromProfile() async -> String?   // the loadNameRequirement read: SignedInUser.resolveId(authService: AuthService.shared);
                                                           // AuthService.shared.currentProfile?.name when its id matches, else
                                                           // ProfileService.shared.fetchProfile(userId:).name; nil on any failure
    static func saveNameToProfile(_ name: String) async throws   // resolveId (throws AppError.unauthorized when nil), then
                                                                 // ProfileService.shared.updateProfile(userId:, name:, phoneNumber: nil, car: nil,
                                                                 // avatarUrl: nil, shouldUpdateAvatar: false), as ApplicationFieldsViewModel does
    var optionsEnabled: Bool { get }     // hasLoadedNameRequirement && !needsName && !isSavingName
    func loadNameRequirement() async     // stored = await loadStoredName(); needsName = stored is non-nil and its trimmed value is blank or
                                         // ApplicationFieldsViewModel.applePlaceholderName; nil (a failed read) leaves needsName false, as the
                                         // application form did; hasLoadedNameRequirement = true in every case
    func saveName() async -> Bool        // ignores a call while isSavingName; trimmed; ApplicationFieldsViewModel.nameProblem → nameError, no call;
                                         // Validators.sanitizeUserInput(max 100); updateName; success → needsName = false, nameError nil;
                                         // failure → nameError = "community_error_generic".localized, needsName stays true
    func didJoin(_ result: JoinResult)   // relaunch() once per view model (didRelaunch guard): active → app, pending → waiting screen
    func didCreate(_ communityId: UUID)  // relaunch() once, called from the create sheet's onDismiss
    func retry()                         // relaunch() once: re-runs the account check (an offline launch also lands here, open finding
                                         // "offline launch showing the application form")
}
struct CommunityOnboardingView: View {   // inside ContentView's NavigationStack
    init(viewModel: @autoclosure @escaping () -> CommunityOnboardingViewModel = CommunityOnboardingViewModel(),
         service: any CommunityServiceProtocol = CommunityService.shared)
}
```
- Content (ScrollView on `Color.naarsBackground`): header (`person.3.fill`, `onboarding_title`, `onboarding_body`); when `needsName`, the name field (`application_name_label` / `application_name_placeholder`) with `onboarding_name_continue` (a repeat Sign in with Apple authorization creates "Apple User", which admins would review); `CommunityJoinOptionsView(isEnabled: vm.optionsEnabled, prefilledCode: vm.prefilledCode, service: service, onJoined: vm.didJoin)` — the options, and any auto-open of a prefilled code, wait until the name requirement is loaded and, when needed, saved; a card `onboarding_create_title` / `onboarding_create_body` → `CreateCommunityView` sheet, also `.disabled(!vm.optionsEnabled)` (record the id in `onCreated`, `vm.didCreate` in `onDismiss`: the invite sheet shows first, F1); when the public list failed to load, a `SecondaryButton("onboarding_retry")` → `vm.retry()`; the account actions copied from `ApplicationFieldsView.swift:175-200` (Sign out, Delete account with `accountDeletionFlow(message: "account_delete_pre_approval_message".localized)`, Guideline 5.1.1(v)), never disabled. Navigation title `onboarding_nav_title`, inline. `.task { await vm.loadNameRequirement() }`.
- `ContentView` `.needsApplication` → `NavigationStack { CommunityOnboardingView() }`. `checkAccountStatus` and every other route stay as they are. `ApplicationFieldsView` becomes unreferenced (Phase 5 deletes it; Task 17 lists it).
- Behaviour change for the Impact Summary: a newcomer on the new build applies by choosing a community; for Seattle, "Ask to join" calls `request_to_join_community`, which copies the answers to `profiles` (`:1273-1278`) so the installed admin build still shows them.

- [ ] **Step 1: Write the failing tests** (CLAUDE.md Testing Expectations, Auth: launch routing; this view is the root of `.needsApplication`). The view model gets counting closures; no network:

```swift
func testDidJoin_RelaunchesExactlyOnce()                 // didJoin(active); didJoin(pending) → relaunchCount == 1
func testDidCreate_RelaunchesExactlyOnce()               // didCreate(A) twice, then retry() → relaunchCount == 1
func testOptions_GatedUntilNameRequirementLoaded() async // before loadNameRequirement: optionsEnabled false; stored "Sam" → needsName false, optionsEnabled true
func testLoadNameRequirement_FailedReadKeepsOptionsOpen() async   // loadStoredName returns nil → needsName false, optionsEnabled true
func testSaveName_RejectsApplePlaceholderAndBlank() async // stored "Apple User" → needsName true, optionsEnabled false; name "Apple User" →
                                                          // false, nameError == "signup_error_name_required".localized; name "   " → same;
                                                          // updateName never called; optionsEnabled still false
func testSaveName_SuccessClearsNeedsNameAndOpensOptions() async   // name " Sam Lee " → true; updateName received ["Sam Lee"]; needsName false;
                                                                  // optionsEnabled true
func testSaveName_FailureKeepsNameStep() async            // updateName throws → false; needsName true; nameError == "community_error_generic".localized
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CommunityOnboardingViewModel' in scope".
- [ ] **Step 3: Implement** with `#Preview`s (a view model built with `loadStoredName: { "Apple User" }` and with `{ "Sam" }`, `updateName: { _ in }`, `relaunch: {}`; options on `PreviewCommunityService`, and a third preview with `failPublicCommunities`); add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityOnboardingViewModelTests -only-testing:NaarsCarsTests/AppLaunchManagerTests`. Expected: 7 new tests pass; the launch-routing tests stay green.
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P2-T12] Make community onboarding the root for accounts with no community` with the files above and `project.pbxproj`.

Strings:
```
onboarding_nav_title = "Get started"
onboarding_title = "Join a community"
onboarding_body = "Naar's Cars works inside communities of neighbors. Use an invite code, ask to join a public community, or start your own."
onboarding_name_continue = "Continue"
onboarding_create_title = "Start your own community"
onboarding_create_body = "Create a community and invite your neighbors."
onboarding_retry = "Try again"
```

Capture list (Task 18): onboarding with the name field, without it, with the public-list failure; light / dark / AX5. `#Preview`: yes.

Live check (owner step, optional): a throwaway account with no membership (owner signs up a test address) lands on onboarding, sees Seattle under "Ask to join a public community"; Sign out works. **(writes)** asking to join Seattle with it creates a pending Seattle row (decline it in Task 18 step 6).

---

### Task 13: The waiting screen's membership list and actions

**Model:** opus (fragile system 5: the screen's relaunch decisions) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Authentication/ViewModels/PendingApprovalViewModel.swift`
- Modify: `NaarsCars/Features/Authentication/Views/PendingApprovalView.swift:12-21, 37-51, 74-87, 92-144, 146-171, 257-286`
- Modify: `NaarsCars/App/AppLaunchManager.swift:238-264` (extract `readAccountRoute()`)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/PendingApprovalViewModelTests.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityServiceProtocol.fetchMyMemberships` (Phase 1); `CommunityJoinOptionsView` (Task 6); `CreateCommunityView` (Task 5); `AppLaunchManager.authState(for:)`, `sessionUserId`, `fetchAccountStatus` (Phase 1).
- Produces:

```swift
// AppLaunchManager
func readAccountRoute() async throws -> AuthState   // the session id and the throwing flags read of recheckAccountStatus, mapped by authState(for:);
                                                    // recheckAccountStatus now calls it and keeps its guards (its six tests stay unchanged and green)
enum PendingApprovalOutcome: Equatable { case relaunch, waiting }
@MainActor final class PendingApprovalViewModel: ObservableObject {
    @Published private(set) var pendingCommunityNames: [String] = []   // empty → today's generic copy
    @Published private(set) var membershipIds: Set<UUID> = []          // excluded from "Join another community"
    init(service: any CommunityServiceProtocol = CommunityService.shared,
         accountRoute: @escaping @MainActor () async throws -> AuthState = { try await AppLaunchManager.shared.readAccountRoute() },
         approvalCheck: @escaping @MainActor () async -> Bool = { await AppLaunchManager.shared.checkApprovalStatusOnly() })
    func poll() async -> PendingApprovalOutcome
}
```
- `poll()` (spec §3.7 `.pendingApproval`):

```text
if decidedRelaunch: return .relaunch                  # one relaunch per screen (Review Focus 4)
rows = try? await service.fetchMyMemberships()
if rows == nil:                                       # failed: keep the names; fall back to today's approval check
    result = await approvalCheck() ? .relaunch : .waiting
else:
    pendingCommunityNames = rows.pending names; membershipIds = all row ids
    if rows has an active row:          result = .relaunch
    elif rows has a pending row:        result = .waiting
    elif let route = try? await accountRoute(), route != .pendingApproval: result = .relaunch   # rejected / nothing left → onboarding
    else:                               result = .waiting   # flags still say pending: never relaunch into the same screen (Review Focus 4)
if result == .relaunch: decidedRelaunch = true
return result
```
- `PendingApprovalView` holds `@StateObject private var viewModel`, set from a new `init(viewModel: @autoclosure @escaping () -> PendingApprovalViewModel = PendingApprovalViewModel())` (the preview passes one on `PreviewCommunityService`). Its `.task` polls once on appear, then every `Constants.Timing.pendingApprovalPollInterval` (replacing the 10 s / 30 s literals at `:261`, `:278`); Refresh polls and keeps its status message (`still_pending` online, `check_failed` offline, `:162-169`); `.relaunch` → the unstructured relaunch (`:156-158`). With names, the title area shows one `pending_waiting_for_community(name)` line per pending community under the existing title; without, today's copy. Two new actions above Contact Support: `pending_join_another` (sheet: `NavigationStack { ScrollView { CommunityJoinOptionsView(excludedCommunityIds: viewModel.membershipIds, onJoined: …) } }`; `onJoined` records the result and sets `showJoinAnother = false`, closing this outer sheet; its `onDismiss` polls when a result was recorded and relaunches on `.relaunch`, so a join whose inner sheet was swiped away still counts) and `pending_create_own` (sheet `CreateCommunityView`, relaunch in `onDismiss` when an id was recorded).

- [ ] **Step 1: Write the failing tests** (CLAUDE.md Testing Expectations, Auth: pending approval; Review Focus 4):

```swift
func testPoll_ActiveMembershipRelaunches() async
func testPoll_PendingOnlyListsNamesAndWaits() async              // names == ["Ballard"]
func testPoll_NoMembershipAndRouteNeedsApplicationRelaunches() async
func testPoll_NoMembershipRouteStillPendingWaits() async
func testPoll_FetchFailureFallsBackToApprovalCheck() async       // approvalCheck false → .waiting, names unchanged; true → .relaunch
func testPoll_AfterRelaunchDecisionDoesNotFetchAgain() async     // first .relaunch; second poll .relaunch with stub.fetchCount still 1
// AppLaunchManagerTests
func testReadAccountRoute_MapsFlags() async throws               // sessionUserId + fetchAccountStatus (false,false,true) → .pendingApproval
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'PendingApprovalViewModel' in scope".
- [ ] **Step 3: Implement**; confirm `git diff -U0 NaarsCars/App/AppLaunchManager.swift` has no hunk inside `checkAccountStatus` (`:314-367`); add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/PendingApprovalViewModelTests -only-testing:NaarsCarsTests/AppLaunchManagerTests/testReadAccountRoute_MapsFlags` plus the six `AppLaunchManagerTests/testRecheck_*` methods. Expected: all pass.
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P2-T13] List pending communities on the waiting screen; join another or create your own` with the files above and `project.pbxproj`.

Strings:
```
pending_waiting_for_community = "Waiting for %@ to approve you"
pending_join_another = "Join another community"
pending_create_own = "Create your own"
```

Capture list (Task 18): waiting screen with one and with two named communities, generic copy, both sheets; light / dark / AX5. `#Preview`: `PendingApprovalView` (exists; add a variant with names: a `PendingApprovalViewModel` on `PreviewCommunityService` whose memberships hold two pending rows, `accountRoute: { .pendingApproval }`, `approvalCheck: { false }`).

Live check (owner step, with Task 12's throwaway account): after asking to join Seattle, the waiting screen reads "Waiting for Naar's Cars Seattle to approve you"; **(writes)** when the owner declines it (Task 18 step 6), the next tick moves the account to onboarding.

---

### Task 14: `PendingInviteStore` and the signed-out code entry

**Model:** opus, high effort (sign-out teardown, fragile system 5; `MainTabView`'s first-launch presentations) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Core/Utilities/PendingInviteStore.swift`, `NaarsCars/Features/Authentication/Views/InviteCodeEntrySheet.swift`
- Modify: `NaarsCars/Features/Authentication/Views/WelcomeView.swift:117-139`
- Modify: `NaarsCars/Core/Services/AuthService.swift:656-679` (`clearPerAccountLocalState`)
- Modify: `NaarsCars/App/MainTabView.swift:214-231` (first `.task`), `:238-241` (second `.task`), `:282` (guidelines cover `onDismiss`), one helper
- Modify: `NaarsCars/Features/Community/ViewModels/JoinCommunityViewModel.swift` (clears the stored code on redemption)
- Modify: `NaarsCars/Features/Authentication/Views/CommunityOnboardingView.swift`, `NaarsCars/Features/Community/Views/MyCommunitiesView.swift`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Utilities/PendingInviteStoreTests.swift`
- Modify: `NaarsCars/NaarsCarsTests/Features/Community/JoinCommunityViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityInviteCode` (Task 1); `JoinCommunityViewModel`, `CommunityJoinOptionsView(isEnabled:prefilledCode:…)` and its gated `.onChange(…, initial: true)` auto-open (Task 6); `CommunityOnboardingViewModel.prefilledCode`, `optionsEnabled` (Task 12); `NavigationIntent.myCommunities` (Task 11).
- Produces:

```swift
struct PendingInviteStore {
    static let codeKey = "community.pendingInviteCode", savedAtKey = "community.pendingInviteSavedAt"
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init)
    func save(_ raw: String)               // stores CommunityInviteCode.normalize(raw) and now()
    func peek() -> String?                 // nil, and both keys removed, when older than Constants.Community.pendingInviteLifetime (spec §3.7: 7 days)
    func clearIfMatches(_ normalized: String)   // removes both keys only when the stored code equals it
    func clear()
}
// No take(): handing a code to a sheet never clears it. Spec §3.7 clears the store on redemption, so a sheet that fails to present
// (another presentation in the same turn) or is cancelled loses nothing.
// JoinCommunityViewModel gains `pendingInviteStore: PendingInviteStore = PendingInviteStore()` (last init argument) and calls
// pendingInviteStore.clearIfMatches(normalizedCode) when the code is used or dead: a successful redeem (active or pending), validate
// answering invalid or expired, or a redeem refusal .invalid / .expired / .exhausted / .removed / .alreadyMember / .alreadyPending.
// A network failure, .rateLimited, .full, .recentlyRejected or a cancel keeps it.
struct InviteCodeEntrySheet: View { init(onSaved: @escaping () -> Void) }   // one field, Save enabled only for a well-formed code; no network
```
- The one producer this build has (Universal Links are Phase 4, outside the build): Welcome gains a low-emphasis `community_invite_entry_link` button under Continue as guest → `InviteCodeEntrySheet`; after saving, Welcome shows `community_invite_saved_banner` with a `community_invite_remove` button (the spec's Phase 4 banner text; no community details, no lookup while signed out, spec §3.5 `validate_community_invite`). Welcome's footer points at the new `welcome_footer_communities` key (the old one says every account is reviewed, which a creator's is not).
- Consumers (each **reads** with `peek()`; only the join view model clears):
  - `CommunityOnboardingView` `.task` (after `loadNameRequirement`) sets `vm.prefilledCode = PendingInviteStore().peek()`. `CommunityJoinOptionsView(isEnabled: vm.optionsEnabled, prefilledCode: vm.prefilledCode, …)` opens the code sheet through its `.onChange(…, initial: true)` once both are set, so the code waits for the name step and for the name requirement to load, and is not lost when the child appeared before the parent's task ran.
  - `MainTabView`: a helper `offerPendingInviteIfNeeded()` sets `navigationCoordinator.pendingIntent = .myCommunities` and `didOfferPendingInvite = true` (`@State`) only when `!didOfferPendingInvite && !appState.isGuest && !showGuidelinesAcceptance && AuthService.shared.currentProfile != nil && PendingInviteStore().peek() != nil`. It is called at the end of the first `.task`, after `checkGuidelinesAcceptance()` in the second `.task` (`:238-241`, which runs when the profile arrives on a cold launch), and in the guidelines cover's new `onDismiss` (`:282`). So My communities never tries to present its join sheet underneath the guidelines cover, which is raised from the same first `.task`.
  - `MyCommunitiesView`: `@State storedInviteCode = PendingInviteStore().peek()` re-read in `.task` and in the Join sheet's `onDismiss`. In `.task`, once per view lifetime (`didAutoOpenStoredCode`), a stored code sets `joinPrefilledCode` and `showJoin = true`. While a code is stored, a row at the top of the actions section shows `community_invite_saved_row` with `community_invite_use` (opens the same Join sheet with the code) and `community_invite_remove` (`PendingInviteStore().clear()`), so a code whose sheet was dismissed or never shown stays reachable and can be dropped.
- `clearPerAccountLocalState` adds `PendingInviteStore().clear()` beside `CommunityContext.shared.resetForSignOut(userId:)` (spec §5 Sign-out row).

- [ ] **Step 1: Write the failing tests** (spec §5: "unit test asserting the keys are gone"; spec §3.7: cleared on redemption; Review Focus 1 for the stored form). Suite `UserDefaults` per test, removed in `tearDown`:

```swift
// PendingInviteStoreTests
func testSave_StoresNormalizedCode()           // save("nc7k · 2pq9-xa") → peek() == "NC7K2PQ9XA"
func testPeek_DoesNotClear()                   // peek() twice → same code both times
func testClearIfMatches_OnlyClearsTheSameCode()  // clearIfMatches("NC2222222A") → still stored; clearIfMatches("NC7K2PQ9XA") → both keys gone
func testPeek_ExpiresAfterSevenDays()          // now advanced by 7 days + 1 s → nil and both keys gone
func testClear_RemovesBothKeys()               // suite.object(forKey: codeKey) == nil && savedAtKey == nil
// JoinCommunityViewModelTests
func testRedeem_ClearsTheMatchingStoredCode() async     // store holds NC7K2PQ9XA; validate + submit succeed → store.peek() == nil
func testRedeemRateLimited_KeepsTheStoredCode() async   // redeemResult = refusal .rateLimited → store.peek() == "NC7K2PQ9XA"
func testValidateInvalid_ClearsTheMatchingStoredCode() async
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'PendingInviteStore' in scope".
- [ ] **Step 3: Implement**; `#Preview` for the sheet and for Welcome with the banner (a suite-backed store); add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/PendingInviteStoreTests -only-testing:NaarsCarsTests/JoinCommunityViewModelTests`. Expected: 5 + 7 pass.
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P2-T14] Keep a typed invite code until it is redeemed and clear it on sign-out` with the files above and `project.pbxproj`.

Strings:
```
community_invite_entry_link = "I have an invite code"
community_invite_entry_title = "Invite code"
community_invite_entry_footer = "You'll use it after you sign up or sign in."
community_invite_entry_save = "Save code"
community_invite_saved_banner = "You have an invite. Sign up or sign in to use it."
community_invite_remove = "Remove"
welcome_footer_communities = "Join a community with an invite, ask to join a public one, or start your own. Community admins review new members."
community_invite_saved_row = "You have a saved invite code."
community_invite_use = "Use code"
```

Capture list (Task 18): Welcome with and without the banner, the entry sheet, My communities with the saved-code row; light / dark / AX5. `#Preview`: both (yes).

Live check: signed out, save a code on Welcome, sign in as the owner → the app opens My communities with the join sheet holding the code; Cancel → the saved-code row stays, Remove drops it; signing out removes `community.pendingInviteCode` (`xcrun simctl spawn booted defaults read com.NaarsCars community.pendingInviteCode` fails).

---

### Task 15: Account-deletion warning for sole-owned communities (A3)

**Model:** opus (account deletion, App Store 5.1.1(v)) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Profile/ViewModels/AccountDeletionCommunityCheck.swift`
- Modify: `NaarsCars/Features/Profile/ViewModels/MyProfileViewModel.swift:28-35` (init), add one method
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:20-24` (state), `:244-260` (alerts)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Profile/AccountDeletionCommunityCheckTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityAdminServiceProtocol.fetchCommunityMembers` (Task 2); `CommunityContext.memberships` (Phase 1).
- Produces:

```swift
enum AccountDeletionCommunityCheck {
    /// Communities the server will archive when this account is deleted (A3, 20261017_0004 STEP A): active owner memberships,
    /// not the default community (A3 + INV-L1), where no other active owner and no active admin is among the members.
    /// A members fetch that fails counts the community in: the warning errs on the side of telling.
    static func communitiesClosed(byDeleting userId: UUID, memberships: [CommunityMembership],
                                  fetchActiveMembers: (UUID) async throws -> [CommunityMember]) async -> [CommunityMembership]
}
// MyProfileViewModel
init(profileService:authService:, communityContext: CommunityContext? = nil, communityAdminService: any CommunityAdminServiceProtocol = CommunityService.shared)
func communitiesClosedByDeletion() async -> [String]   // names; fetches each owned community's active members (limit Constants.Community.membersPageSize)
```
- `MyProfileView`: the first alert's Delete (`:246-248`) runs `communitiesClosedByDeletion()` (row shows `community_delete_checking` meanwhile); a non-empty list raises a new alert `community_delete_closes_title` with `community_delete_closes_message(ListFormatter.localizedString(byJoining: names))` and a destructive `community_delete_closes_confirm` that leads to today's final confirmation (`:252-260`); an empty list goes straight to it. The server applies A3 whatever the client shows; nothing else in the deletion path changes. The pre-approval delete flows are unchanged: a person there holds no active membership (a banned account's memberships are hidden by `get_my_memberships`, `:1825`).

- [ ] **Step 1: Write the failing tests** (CLAUDE.md Testing Expectations, Auth: account deletion; A3):

```swift
func testSoleOwnerWithOnlyMembersIsClosed() async
func testSoleOwnerAloneIsClosed() async
func testOwnerWithAnAdminIsNotClosed() async
func testOwnerWithACoOwnerIsNotClosed() async
func testDefaultCommunityIsNeverListed() async
func testMemberAndAdminMembershipsAreNotFetched() async     // fetch closure records nothing
func testFetchFailureListsTheCommunity() async
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'AccountDeletionCommunityCheck' in scope".
- [ ] **Step 3: Implement**; add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/AccountDeletionCommunityCheckTests -only-testing:NaarsCarsTests/MyProfileViewModelTests`. Expected: 7 pass (the old case skips signed out).
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P2-T15] Warn before deleting an account that closes communities` with the files above and `project.pbxproj`.

Strings:
```
community_delete_checking = "Checking your communities…"
community_delete_closes_title = "Your communities will close"
community_delete_closes_message = "You're the only owner of %@ and no admin can take over. Deleting your account closes it, and every member loses access."
community_delete_closes_confirm = "Delete and close"
```

Capture list (Task 18): the warning alert with one and with two names; light / dark / AX5 (Lane B screenshot of a DEBUG-seeded state or the preview of the profile with a stubbed check).

Live check (no write): as the owner, Delete Account → Delete → no warning for Seattle (default) → the final confirmation appears → **Cancel**. With the Task 5 test community still live and owned alone, the warning names it → **Cancel**.

---

### Task 16: Legal and disclosure deliverable

**Model:** opus, high effort (the privacy policy, terms and in-app disclosures are what App Store rules 6 and 8 hold the build to: a claim that does not match the server is a misleading claim) · **Files:**
- Modify: `Legal/PRIVACY_POLICY.md:3, 5` (both dates), `:36-46` (§4.1), `:86-94` (§6.1), `:133-146` (§9)
- Modify: `Legal/TERMS_OF_SERVICE.md:3, 5`, `:23` (§4), `:88` (§9), new section "Community owners and admins" after §5
- Modify: `Legal/FAQ.md:13-15, 23, 35`
- Modify: `Legal/PRIVACY-DISCLOSURES.md` (reviewed against the same changes; edited where it describes who sees what)
- Modify: `NaarsCars/Features/Profile/Views/CommunityGuidelinesView.swift:93-100` (seventh entry)
- Create (normal tools): `Docs/AppStore/2026-10-multi-community-review-notes.md`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:** the content below is fixed by spec §4 Phase 2 "Legal and disclosure deliverable" and decisions A1–A3; wording is the implementer's within it.
- Privacy policy: §4.1 adds application answers, community memberships, invite redemptions (who invited whom) and notes an admin writes when removing a member; §6.1 is rewritten per community — members of the communities you belong to see your name, photo and car; owners and admins of a community you apply to or belong to also see your application answers, who invited you and your join date, never your email or phone number; platform moderators may review reported content in any community, including private ones, and see who reported it; phone-number visibility restated per community; §9 lists memberships, invites and admin notes among what deletion removes or anonymises, and states A3 (a community you own alone with no admin is closed; with an admin, ownership passes to the longest-standing admin).
- Terms: "Community owners and admins": anyone may create a community (one a day, three owned by default, more on request, A1); owners and admins may approve, remove, moderate and announce; they may not see email or phone or delete anyone's account; ownership passes to the longest-standing admin when an owner's account is closed, otherwise the community is closed (A3); the operator may archive any community or make a public one private (A2). §4 and §9 reworded so "we" is no longer the only approver and moderator.
- FAQ: line 15 describes the three ways in (an invite code, a request to a public community, creating your own); line 23 "visible to all community members" → "visible to the members of the community you post it in"; line 35 gains "Community admins do not see who reported. Platform moderators do."
- Guidelines section 7 (`guidelines_7_title`, `guidelines_7_body`): communities, their admins and platform moderators, and A2's rule that a community's name, description and public content follow the same rules as any post.
- Review notes: the invite flow with a test invite code (placeholder `<TEST CODE>` the owner fills from a code made for the review account), that a reviewer can also create a community and enters the app at once, that platform moderators see every report and can archive any community, the report paths for content, people and communities; release notes asking the four platform admins to update with this build (D10).
- Both legal documents' effective and updated dates read the release date the owner sets (placeholder `<RELEASE DATE>` left for the owner). **Owner step:** mirror both documents to the Notion pages before submission.

- [ ] **Step 1: Edit** the four legal files, add the guideline entry and its two keys, write the review notes.
- [ ] **Step 2: BUILD.**
- [ ] **Step 3: Verify** `grep -n "visible to all community members\|submit an application to join the community" Legal/FAQ.md` returns nothing. Then check each who-sees-what sentence against the server and list the source beside it in the task report: community admins' applicant fields (`get_community_members`, `20261017_0005:1849-1862`, no email or phone), the member projection (`public_profiles`, `20261017_0002:343-345`), reporter privacy (`20261005_0022_reports_reporter_privacy.sql`; `report_community`, block 31), A3 (`20261017_0004` STEP A), the creation limits (blocks 7–9). A sentence with no source is reworded or removed.
- [ ] **Step 4: Commit** `[P2-T16] Update the privacy policy, terms, FAQ and guidelines for communities` with the files above.

Strings:
```
guidelines_7_title = "Communities and their admins"
guidelines_7_body = "Anyone can create a community. Its owners and admins approve members, remove people and moderate it. They see your name, photo, car, your answers when you ask to join and who invited you, never your email or phone number. A community's name, description and public content follow the same rules as any post. Platform moderators can review reported content in any community, including private ones, and can close a community that breaks these guidelines."
```

Capture list (Task 18): `CommunityGuidelinesView` with section 7, AX5. `#Preview`: exists.

---

### Task 17: Documentation for Phase 2

**Model:** sonnet · **Files:**
- Modify: `CLAUDE.md` — Current State (a Phase 2 paragraph: what shipped, what was verified); Notification Rules (`pending_approval` has two audiences, community admins and platform admins, and two routes: `.pendingMembers(communityId)` with the key, `.pendingUsers` → the default community's Requests to join without; `.enterApp` while authenticated → My communities); Fragile system 7 and Canonical Entry Points (the Profile badge reads `pending_members_total`; no client-side pending aggregation; `clearCommunityBadge(visibleCommunityId:)`; the three sanctioned `forceFullRefreshAndWait` triggers of this phase); Fragile system 5 and the Sign-out row (`CommunityOnboardingView` is the `.needsApplication` root; the waiting screen relaunches only when the route no longer reads pending; `PendingInviteStore().clear()` in `clearPerAccountLocalState`); File conventions (`CommunityAdminServiceProtocol`, `ApplicantContactFetching`, `PreviewCommunityService` as the only app-target stand-in for `#Preview`s, `Features/Community/ViewModels`, the present-record-act-on-dismiss rule for the shared community sheets, the `CommunityRPCError` refusal convention); Testing Expectations Auth row (community approval, zero-membership routing on the waiting screen); Audit Notes: dead files awaiting deletion (`ApplicationFieldsView.swift`, `PendingUsersView.swift`, `PendingUsersViewModel.swift`, `PendingUserDetailView.swift` with its view model), the follow-ups of Task 18, the audit date.
- Modify: `AGENTS.md`; `.cursor/rules/04-badges-contract.mdc` (Profile badge from `pending_members_total`), `.cursor/rules/05-navigation-contract.mdc` (`pendingMembers`, `myCommunities`).
- Modify: `SECURITY.md` §4 (two admin notions: platform, `profiles.is_admin` / `verifyAdminStatus`; community, the role checked inside each RPC; community admins never see email, phone or reporters; only the user and, for a default-community applicant with no other membership, a platform admin can delete an account, INV-M9).
- Modify: `Docs/design-system/README.md` §3 / §4 (role and muted chips, the Requests to join card, the join disclosure line; no new tokens).

- [ ] **Step 1: Edit** each section with the Phase 2 facts (replace, do not append history).
- [ ] **Step 2: Verify** `grep -n "ApplicationFieldsView()" CLAUDE.md AGENTS.md` returns nothing stale and `grep -n "PendingUsersView()" NaarsCars/App NaarsCars/Features -r` returns nothing.
- [ ] **Step 3: Commit** `[P2-T17] Document the Phase 2 community client`.

---

### Task 18: Phase gate

**Model:** opus · **Files:** none modified (reports only). Uses `Docs/qa/push-fixtures/*.apns`, `build/`.

- [ ] **Step 1: Preconditions** (Supabase MCP, read-only). `select proname from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_community','get_my_community_limits','request_owned_community_limit','decide_owned_community_limit','set_community_public','archive_community','unarchive_community','archive_community_with_notices','create_community_invite','revoke_community_invite','validate_community_invite','redeem_community_invite','request_to_join_community','approve_community_member','reject_community_member','leave_community','get_community_members','report_community','get_platform_communities')` returns 19 rows. If `archive_community_with_notices` or `reject_community_member` is missing, run every step except the archive, decline and sole-member-leave checks and report the gap.
- [ ] **Step 2: Full unit suite, signed out**, one headless simulator, `-resultBundlePath build/P2-gate.xcresult`. Expected: exit 0, 0 failures; skips limited to the session-gated classes. Record the counts against Phase 1's gate.
- [ ] **Step 3: Previews (Lane A).** Open the worktree project; `RenderPreview` every `#Preview` named in the capture lists of Tasks 3–16 with `{"Color Scheme": "Light Appearance"}`, `{"Color Scheme": "Dark Appearance"}`, `{"Dynamic Type": "AX 5"}`; retry once on the first-render timeout. Inspect each: clipped or overlapping text, dark contrast, the 60-character name truncating, buttons not clipped at AX5. Quit Xcode.
- [ ] **Step 4: Running app (Lane B), owner signed in.** **Owner step:** sign in. Captures in light, dark and AX5 (`simctl ui … appearance`, `content_size accessibility-extra-extra-extra-large`) of: Profile with the My communities row, My communities, Requests to join (Seattle), Admin → Communities, the Community tab title menu with counts (`-debugCommunityCount 3`); then reset appearance and size. Compare the one-membership Requests and Community tab with Phase 1's gate captures: unchanged apart from the Profile row.
- [ ] **Step 5: Push fixtures.** Fill `<COMMUNITY_ID>` with Seattle's id. `pending_approval_with_community.apns` → Profile tab, Seattle's Requests to join; `pending_approval_without_community.apns` → the same screen through `.pendingUsers`; `user_approved_further_community.apns` while authenticated → My communities, no loading screen.
- [ ] **Step 6: Live matrix.** Run each task's "Live check" line in this order, **(writes)** items only with the owner's go-ahead, recording each outcome: 3, 7, 8 (read, then mute and unmute), 9, 14, 15 (no write), then the write sequence — 5 (create "P2 Live Check" and a code), 6 (preview the code), second account: the owner signs into a throwaway account on the simulator (or the gate redeems as it with `execute_sql` under `set local role authenticated` and its claims in a committed transaction, owner approval required), redeems the code → the owner's bell holds one `pending_approval` row for "P2 Live Check" and the Profile badge counts it → back as the owner, approve it in My communities → Requests to join → the throwaway account's next poll enters the app; a second request from Task 12's account to Seattle → decline it → that account's waiting screen moves to onboarding and `user_rejected` arrives; 4 (report "P2 Live Check"); 8 (leave "P2 Live Check" as the throwaway member: the Leave sheet counts match `leave_community`'s answer); 10 (archive, restore, archive). Clean-up: "P2 Live Check" archived, codes revoked, the throwaway accounts deleted from their own Profile (or left for the owner), the owner's mute off.
- [ ] **Step 7: Shut down and report.** `xcrun simctl shutdown booted`. Report: build result, suite counts, every preview and capture with findings, push fixture outcomes, the live matrix, what was not verified, and the PR Impact Summary: (1) the Profile badge counts `pending_members_total` instead of every unapproved profile; (2) opening the Community tab or switching its community marks only that community's Town Hall rows read; (3) `.enterApp` while authenticated opens My communities; (4) `pending_approval` with a `community_id` opens that community's Requests to join, and platform admins' Pending approvals is the default community's Requests to join; (5) `.needsApplication` shows community onboarding instead of the application form. High-blast files touched: `BadgeCountManager`, `BadgeCountManaging`, `NavigationCoordinator`, `NavigationIntent`, `DeepLinkParser`, `NotificationNavigationRouter`, `AppDelegate`, `AppLaunchManager`, `AuthService`, `CommunityContext`, `Constants`; what would break if a consumer were missed. Follow-ups to record: community reports are not returned by `admin_get_reports` and cannot be dismissed from the app (the Communities list's "Reported" marker stays until a server change); a sole owner with other members cannot leave until Phase 3's transfer screen. App Store checklist answers per spec §5 (stores data differently: yes; new UGC surfaces with report paths; no permission, SDK or entitlement).

---

## New files

| Path (Xcode navigator path) | Target | Task | How |
|---|---|---|---|
| `NaarsCars/Core/Models/CommunityPayloads.swift` | NaarsCars | 1 | Xcode MCP |
| `NaarsCars/Core/Services/PreviewCommunityService.swift` (whole file `#if DEBUG`; extended in Tasks 2 and 7) | NaarsCars | 1 | Xcode MCP (`XcodeWrite`) |
| `NaarsCars/NaarsCarsTests/Core/Services/CommunityServiceTests.swift` | NaarsCarsTests | 1 | Xcode MCP |
| `NaarsCars/Core/Protocols/CommunityAdminServiceProtocol.swift` | NaarsCars | 2 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/TownHall/ReportContentViewModelTests.swift` | NaarsCarsTests | 4 | Xcode MCP |
| group `NaarsCars/Features/Community/ViewModels` | NaarsCars | 5 | `XcodeMakeDir` |
| group `NaarsCars/NaarsCarsTests/Features/Community` | NaarsCarsTests | 5 | `XcodeMakeDir` |
| `NaarsCars/Core/Utilities/QRCodeRenderer.swift` | NaarsCars | 5 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/CreateCommunityViewModel.swift`, `CommunityInviteViewModel.swift` | NaarsCars | 5 | Xcode MCP |
| `NaarsCars/Features/Community/Views/CreateCommunityView.swift`, `CommunityInviteSheet.swift` | NaarsCars | 5 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/CreateCommunityViewModelTests.swift` (classes `CreateCommunityViewModelTests`, `CommunityInviteViewModelTests`) | NaarsCarsTests | 5 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/JoinCommunityViewModel.swift`, `CommunityJoinOptionsViewModel.swift` | NaarsCars | 6 | Xcode MCP |
| `NaarsCars/Features/Community/Views/JoinCommunitySheet.swift`, `CommunityJoinOptionsView.swift` | NaarsCars | 6 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/JoinCommunityViewModelTests.swift` | NaarsCarsTests | 6 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/PendingMembersViewModel.swift`, `Views/PendingMembersView.swift` | NaarsCars | 7 | Xcode MCP |
| `NaarsCars/Core/Protocols/ApplicantContactFetching.swift` | NaarsCars | 7 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/PendingMembersViewModelTests.swift` | NaarsCarsTests | 7 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/MyCommunitiesViewModel.swift`, `Views/MyCommunitiesView.swift`, `Views/LeaveCommunitySheet.swift` | NaarsCars | 8 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/MyCommunitiesViewModelTests.swift` | NaarsCarsTests | 8 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/OwnedLimitRequestViewModel.swift`, `Views/OwnedLimitRequestSheet.swift` | NaarsCars | 9 | Xcode MCP |
| `NaarsCars/Features/Admin/ViewModels/CommunitiesAdminViewModel.swift`, `Views/CommunitiesAdminView.swift` | NaarsCars | 10 | Xcode MCP |
| `Docs/qa/push-fixtures/pending_approval_with_community.apns`, `pending_approval_without_community.apns`, `user_approved_further_community.apns` | none | 11 | normal tools |
| `NaarsCars/Features/Authentication/ViewModels/CommunityOnboardingViewModel.swift`, `Views/CommunityOnboardingView.swift` | NaarsCars | 12 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/CommunityOnboardingViewModelTests.swift` | NaarsCarsTests | 12 | Xcode MCP |
| `NaarsCars/Features/Authentication/ViewModels/PendingApprovalViewModel.swift` | NaarsCars | 13 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/PendingApprovalViewModelTests.swift` | NaarsCarsTests | 13 | Xcode MCP |
| `NaarsCars/Core/Utilities/PendingInviteStore.swift`, `NaarsCars/Features/Authentication/Views/InviteCodeEntrySheet.swift` | NaarsCars | 14 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Core/Utilities/PendingInviteStoreTests.swift` | NaarsCarsTests | 14 | Xcode MCP |
| `NaarsCars/Features/Profile/ViewModels/AccountDeletionCommunityCheck.swift` | NaarsCars | 15 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Profile/AccountDeletionCommunityCheckTests.swift` | NaarsCarsTests | 15 | Xcode MCP |
| `Docs/AppStore/2026-10-multi-community-review-notes.md` | none | 16 | normal tools |

## Self-review notes

- **Models.** opus for every fragile seam: the badge (3), the shared report path (4), Requests to join (7), My communities (8), platform archive and make-private (10), routing (11), the onboarding root (12), the waiting screen (13), `PendingInviteStore` and `MainTabView` (14), account deletion (15), the legal text (16), the gate (18). sonnet for the envelope and wrappers (1, with an opus review; 2), Create and the invite sheet (5), the join sheets (6), the limit-request sheet (9) and the documentation (17). Never fable.
- **Spec §4 Phase 2 coverage.** Onboarding as the `.needsApplication` root (12); My communities with Create (5, 8), Join with a code (6, 8), Requests to join (7, 8), Mute (8), Report (4, 8), Leave (8); the invite sheet after Create (5); the join sheet with typed codes, the "what the approver sees" line and Report (6); the waiting screen's list and two actions (13); `PendingInviteStore` (14); the `pending_approval` route (11); the Profile badge from `pending_members_total` and the per-community counts with the scoped clear (3); the platform Communities list with archive and restore (10); the legal deliverable and the two in-app sentences (4, 6, 16); stubbed `CommunityServiceTests` for every wrapper (1, 2); parser and routing tests for `pending_approval` with and without `community_id` and the `simctl` fixture (11). Decisions: A1 member side (9) and decision rows (10); A2 from the code preview and the public preview (6), from My communities (8), the guest Town Hall header (4) and the remedies in the platform list (10); A3 warning (15); no Take over, no `owner_vacant` (none of the tasks reads them; `get_my_memberships` has no such column, `:1782`).
- **Deliberate departures and choices the owner can veto.** (1) `PendingInviteStore`'s producer in this build is a Welcome "I have an invite code" entry (Task 14): the spec's producer, the Universal Link, is Phase 4, outside decision 1's scope, and the store would otherwise have no writer. Without it, drop Task 14's Welcome part and keep the store for Phase 4. (2) `(.dashboard, "joinedCommunity")` after an in-app create or instant join is a third sanctioned refresh call beside spec §3.7's two, so a new community's requests appear without waiting out the staleness window. (3) `welcome_footer_communities` replaces the Welcome footer's claim that every account is reviewed. (4) The QR encodes the share text, not a link (no link before Phase 4). (5) A sole owner with other members is refused by the server (`last_owner`) until Phase 3 adds transfer; the Leave sheet shows the server's localized reason. (6) `set_primary_community` and `update_community` have no Phase 2 screen (spec §3.7 lists none); they wait for Phase 3's settings.
- **Tests.** Spec-named: `CommunityServiceTests` (1, 2), parser and routing (11), the `simctl` fixture (11), the sign-out keys and the clear-on-redemption rule (14). CLAUDE.md-mandated: the badge seam (3), Auth launch routing for the `.needsApplication` root (12: one relaunch, the name rules, the gated options), Auth pending approval (13), Auth account deletion (15), the RPC fixture gate (1, 2), the shared report path (4: the community case and the unchanged guard for every other case). Review Focus pins: 1 (1, 6), 2 (5, 6, 7), 3 (7, 8), 4 (13), 5 (4), 6 (6), 7 (1, 5). Spec-stated behaviour pinned where it is logic rather than layout: the inline not-admin state and the platform-admin-only contact read (7), the `leftCommunity` refresh and the Leave counts (8). One crash guard that no spec names: the limit-request range at the ceiling (9). Tasks 10, 16, 17 add no test (layout and documents; their RPCs are pinned in 1–2).
- **Previews.** Every `#Preview` in Tasks 3–16 builds on `PreviewCommunityService` (app target, DEBUG), never on `CommunityFixtures` or the test stubs, and every new screen takes its view model through a defaulted `viewModel:` argument (Global Constraints).
- **Type and name consistency.** `CommunityRPCError.localizedMessage`, `CommunityInviteCode.normalize` / `isWellFormed`, `JoinResult`, `PendingMembersTarget.community(_:name:)` / `.defaultCommunity`, `CommunityContext.isAdmin(of:)`, `administeredPendingTotal`, `forgetMembership(_:)`, `clearCommunityBadge(visibleCommunityId:)`, `BadgeCounts.makeCounts(from:)`, `NavigationIntent.pendingMembers` / `.myCommunities`, `DeepLink.pendingMembers(communityId:)`, `NotificationIntent.openPendingMembers(communityId:)`, `AppLaunchManager.readAccountRoute()`, `PendingInviteStore.peek()` / `clearIfMatches(_:)`, `CommunityJoinOptionsView(excludedCommunityIds:isEnabled:prefilledCode:service:onJoined:)`, `CommunityOnboardingViewModel.optionsEnabled`, `OwnedLimitRequestViewModel.canRequestMore(currentMax:)`, `ApplicantContactFetching.fetchApplicantContact(userId:)`, `PreviewCommunityService` are spelled the same in every task that uses them.
- **Phase 1 carry-overs closed here:** `PendingInviteStore` and its sign-out clear (Phase 1 self-review note 1), the A3 deletion warning (note 2), the `.myCommunities` target of `.enterApp` (spec §3.7), `isPlatformAdmin` / `isAdmin(of:)` on `CommunityContext`. The Phase 1 fixture and DEBUG seam `join_policy` values (`invite_only`, `approval`) are corrected to the server's `invite` / `approve` in Task 1, because Task 1 adds `requiresApproval`.
