# Multi-community Phase 3 (community admin and moderation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Phase 3 client: a per-community admin panel (figures, announcements, requests to join, members, reports, settings) for community owners and admins and for platform admins, member management (remove with a note, let back in, make admin or member, hand over ownership), community settings (name, description, who joins, who invites, archive), the community reports list with hide / restore / dismiss and no reporter anywhere, announcements to one community under the 3-a-day cap, the `content_reported` and `account_restricted` routes, and the legal text that matches what community admins can now do.

**Architecture:** `AdminService` gains a narrow `AdminServiceProtocol` whose methods all take a community (figures, announcements, community reports, community moderation) and call the new RPCs of the companion SQL plan; `CommunityService` gains the member-management and settings wrappers on `CommunityAdminServiceProtocol`. New screens get `ObservableObject` ViewModels that check `CommunityContext.isAdmin(of:)` before fetching, mirror the server's permission rules only to decide what to show, and keep a row change when a follow-up reload fails. `RefreshCoordinator`, realtime, the send path, SwiftData, the notification registry and `BadgeCountManager` are not modified.

**Tech Stack:** Swift 6.3 toolchain in Swift 5 language mode, SwiftUI, supabase-swift, XCTest, Xcode 26.6, iOS 26.0 deployment target.

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` §4 "Phase 3 - Community admin and moderation" (in full), §2.1 rule 10, §2.2 F13-F15, F17, §2.4 (removal and rejection rows), §3.5 (`get_community_reports`, `moderate_community_content`, `get_community_stats`, INV-P2), §3.7 "Admin", "Screens", "Navigation" (the "Reports" bullet), §5 (moderation and notification rows), under `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` (wins where they differ). The server contract is **`Docs/superpowers/plans/2026-10-18-multi-community-phase3-sql.md`** (File A, File B); this plan cites its blocks. Read all three before starting a task.

## Global Constraints

- Deployment target `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; `SWIFT_VERSION = 5.0`; `SWIFT_APPROACHABLE_CONCURRENCY = YES`; `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. No build-setting change, no new permission, entitlement, SDK or Info.plist key.
- `RefreshCoordinator.swift` is not edited. The coordinator calls this phase adds, both `RefreshCoordinator.shared.forceFullRefreshAndWait(_:trigger:)` from ViewModels after an explicit user action: `(.dashboard, "removedMember")` after a removal (Task 3: the removed member's requests in that community are reopened, removed or cancelled) and `(.dashboard, "archivedCommunity")` after an archive (Task 4). Never `invalidate` or `refreshIfNeeded` from a ViewModel. Realtime, `MessageSendManager`, reactions, SwiftData models and mappers, `BadgeCountManager` and `PushNotificationService` are not touched.
- No new notification type (the registry stays at 33). `content_reported` gains a second audience: a community owner's or admin's push carries `community_id` (SQL plan File A block 2), a platform admin's push does not, so the push itself says which list to open. `account_restricted` pushes carry `community_id` (live since `20261017_0005` block 22).
- **RPC contract.** Argument names exactly as the SQL plan and `20261017_0005`: `p_community_id`, `p_status`, `p_report_id`, `p_action`, `p_reason`, `p_period`, `p_count`, `p_title`, `p_body`, `p_pinned`, `p_user_id`, `p_role`, `p_name`, `p_description`, `p_join_policy`, `p_members_can_invite`. An optional argument is omitted when nil (`encodeIfPresent`); the one deliberate empty value is `p_description: ""`, which clears a description (`20261017_0005:712-714`). Envelope RPCs go through `CommunityRPC.decode` / `decodeSuccess` (`Core/Models/CommunityPayloads.swift:85-136`); a refusal is shown as `CommunityRPCError.localizedMessage`, never the server's text. `send_community_broadcast` raises instead of answering an envelope: SQLSTATE `P0001` (the daily cap) and `42501` (not an admin of it) are mapped to `AdminServiceError` (Task 1). No refusal code is added (the 20 of Phase 2 stay).
- **Reporter privacy is a type rule (INV-P2).** `CommunityReport` has no reporter field; no community screen calls `admin_get_reports` or `admin_moderate_content`; the reporter's own free-text note is shown under the existing "Reporter's note" label.
- The server decides every admin action. A client action list (`CommunityMemberActions`, `CommunityReportActions`, `AdminPanelScope.initial`) only chooses what to show and must not offer what the cited server rule refuses.
- New ViewModels are `final class … : ObservableObject` + `@MainActor` (State rule 2). No ViewModel subscribes to a publisher or touches a repository in `init`; loading starts from the view's `.task`. Copy `@State` into a local before starting a `Task` that reads it. Every write method returns early while a write is in flight (one RPC per tap).
- Design system (`Docs/design-system/README.md`): `ColorTheme` tokens only, roles through `NaarsChip`, counts through `NotificationBadge`, full-width actions through `PrimaryButton` / `SecondaryButton`, failures through `.errorBanner(message:)` or a warning toast (never the success toast), cards through `.cardStyle()`, every scrolling screen on `Color.naarsBackground`, skeletons for list loading, destructive actions behind a confirmation. Every interactive element gets an `accessibilityLabel`; important controls get identifiers under `admin.panel.*`, `admin.broadcast.*`, `community.members.*`, `community.member.*`, `community.settings.*`, `community.reports.*`. The only community title menu is `.communityTitleMenu(enabled:subtitle:menu:)` (`UI/Components/Common/CommunityTitleMenu.swift`).
- Strings: every user-facing string is a key in `NaarsCars/Resources/Localizable.xcstrings` with `en`, `es`, `ko`, `vi`, `zh-Hans`, `zh-Hant`, added **only** with `python3 -I scripts/add-localization-keys.py build/P3-T<n>-keys.json`. Each task lists its keys and English; the implementer writes the five machine translations in the tone of neighbouring keys, keeping `%@`, `%lld`, `%1$@`. Never remove or edit an existing key (a changed sentence is a new key and the call site moves to it). Reuse the existing `admin_reports_*` keys where their English already fits, as each task says.
- **New Swift files** (decision 3): open this worktree's project (`.claude/worktrees/naarscars-multi-community-roadmap-f08594/NaarsCars/NaarsCars.xcodeproj`), `XcodeListWindows`, confirm the workspace path, `XcodeLS` the target group (navigator paths start `NaarsCars/…`), then `XcodeWrite`. One new group: `NaarsCars/NaarsCarsTests/Features/Admin` (Task 6 creates it with `XcodeMakeDir` and confirms with `XcodeLS` that it belongs to `NaarsCarsTests`). If another project is open, or the MCP cannot create the group, write the file to disk, report "not yet in the project", and do not claim a green build. Let Xcode go idle (or quit it) before the Lane B build. Every task that creates a Swift file lists it **and** `NaarsCars/NaarsCars.xcodeproj/project.pbxproj` in its commit. Never hand-edit `project.pbxproj`.
- **Chain stop rule (orchestrator).** When a task reports "not yet in the project", no later task runs until the file is in the right target, `BUILD` is green, the task's tests pass and its commit exists.
- One build at a time on this Mac. One headless simulator (`iPhone 16`, iOS 26.x). Unit tests run with the simulator **signed out**. Never run `RideServiceTests`, `FavorServiceTests`, `TownHallServiceTests` or the live cases of `TownHallFeedViewModelTests` while signed in. URLProtocol stubs are registered in `setUp` and reset and unregistered in `tearDown` (`CommunityServiceURLProtocol`, `NaarsCarsTests/Core/Services/CommunityServiceTests.swift:11-87`).
- Every task ends with a green Lane B build, its listed tests passing, and one commit whose subject starts `[P3-T<n>]` and whose body ends with the Co-Authored-By trailer the executing session was given. Stage files by path only; never `git add -A` / `git add .`. Tasks never push.
- **Live checks** need the owner signed in and the SQL plan applied; they are executed together in Task 11. A check that writes to production is marked **(writes)**, runs only with the owner's go-ahead, and names its clean-up.
- **Screen captures** (light, dark, AX5) are taken in Task 11; each UI task lists its captures and which views get a `#Preview`. Every new screen has one that renders signed out with no network.
- **Previews never use test-target code.** App-target stand-ins: `PreviewAdminService` (new, Task 1, whole file `#if DEBUG`) and `PreviewCommunityService` (extended in Task 2). Each new screen takes its view model as `init(…, viewModel: @autoclosure @escaping () -> XViewModel = XViewModel(…))` stored with `StateObject(wrappedValue:)`; a preview passes one built on the preview services and a `CommunityContext(service: PreviewCommunityService(), defaults: UserDefaults(suiteName: "preview")!)` after `debugSetMemberships`.
- **Every `#Preview` that names a DEBUG-only type sits inside `#if DEBUG … #endif`**, the Phase 2 idiom (`NaarsCars/Features/Admin/Views/CommunitiesAdminView.swift:319-334`: one `#if DEBUG` before the first `#Preview`, one `#endif` after the last). `PreviewAdminService`, `PreviewCommunityService` and `CommunityContext.debugSetMemberships` exist only in DEBUG, so an unwrapped `#Preview` that uses them compiles in Debug (Lane B and CI build Debug only) and fails the Release / Archive build at App Store submission. This applies to every preview added or edited in Tasks 3-7, including the edited previews of `AdminPanelView.swift:356-358` (Task 6) and `BroadcastView.swift:150-154` (Task 7). Each of those tasks runs `PREVIEWGUARD` on its touched view files before GREEN (expected: no output), and Tasks 7 and 11 run `RELEASE`.
- Models: opus for every fragile seam, every moderation path and every task that adds or changes a Supabase RPC call site (CLAUDE.md lists RPC call sites as a high-blast-radius seam), sonnet for documentation, never fable (task index).

### Commands (used by every task; `<n>` is the task number)

```bash
# BUILD (from the worktree root). Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build > build/P3-T<n>-build.log 2>&1; echo "exit=$?"
grep -n "error:" build/P3-T<n>-build.log | head -20
# New warnings: every "warning:" line naming a file this task touched must also appear in build/P3-baseline-build.log (Task 1 Step 0).
grep -n "warning:" build/P3-T<n>-build.log | grep -E "<touched file basenames joined with |>"

# RED (compile-level failing test). Expected: exit≠0 and the named compile error.
xcodebuild build-for-testing -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/DerivedData -quiet > build/P3-T<n>-red.log 2>&1; echo "exit=$?"; grep -n "error:" build/P3-T<n>-red.log | head

# TEST <ONLY> = one or more -only-testing:NaarsCarsTests/<Class>[/<method>]. Expected: exit=0, 0 failures.
rm -rf build/P3-T<n>.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' <ONLY> -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P3-T<n>.xcresult -quiet > build/P3-T<n>-test.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P3-T<n>.xcresult

# FULL = CLAUDE.md's Lane B full unit-suite command, signed out. Expected: exit=0, 0 failures; skips only in the session-gated classes.
rm -rf build/P3-T<n>-full.xcresult
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/P3-T<n>-full.xcresult -quiet > build/P3-T<n>-full.log 2>&1; echo "exit=$?"
xcrun xcresulttool get test-results summary --path build/P3-T<n>-full.xcresult

# PREVIEWGUARD <files> = the touched view files. Prints every #Preview line outside an #if DEBUG block. Expected: no output.
# (An approximation: it pairs #if DEBUG with the next top-level #endif; RELEASE is the authoritative check.)
awk 'FNR==1{d=0} /^#if DEBUG/{d=1} /^#endif/{d=0} /^#Preview/{if(!d) print FILENAME":"FNR": #Preview outside #if DEBUG"}' <files>

# RELEASE = a Release build for the simulator (no signing needed). Catches DEBUG-only names used outside #if DEBUG,
# which Debug builds never see. Expected: exit=0 and no "error:" line.
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Release -derivedDataPath build/DerivedData-Release -quiet build > build/P3-T<n>-release.log 2>&1; echo "exit=$?"
grep -n "error:" build/P3-T<n>-release.log | head -20
```

`FULL` runs at the end of Tasks 4, 6 and 8 (fragile systems 4 and 5, high-blast seams) and in Task 11. Before the first `FULL`, confirm the simulator is signed out (install, launch, a screenshot shows Welcome); if it is signed in, stop and ask the owner. Record executed / passed / skipped in each task report. A new test file is in the right target when its `TEST` run reports the expected number of executed tests.

### Task index

| Task | Deliverable | Model | Effort |
|---|---|---|---|
| 1 | `AdminServiceProtocol`: figures, announcements, community reports and moderation by community; `CommunityReport` with no reporter; `PreviewAdminService`; stubbed `AdminServiceTests` | opus | high |
| 2 | Member-management and settings wrappers on `CommunityAdminServiceProtocol`; their preview and stub conformance; stubbed tests | opus | high |
| 3 | Members and member detail: remove with a note, let back in, make admin / member, make owner | opus | high |
| 4 | Community settings and archive; "choose a new owner" when the last owner leaves | opus | high |
| 5 | Community reports: list, hide / restore / dismiss, no reporter | opus | high |
| 6 | Admin panel per community (scope, title menu, figures, links) and its entry points (Profile, My communities, Communities list) | opus | high |
| 7 | Announcements to one community under the 3-a-day cap; the legacy broadcast RPC call removed | opus | high |
| 8 | Routing: `content_reported` → that community's reports; `account_restricted` → My communities; push fixtures | opus | high |
| 9 | Legal and disclosure text for community moderation | opus | high |
| 10 | Documentation for Phase 3 | sonnet | medium |
| 11 | Phase gate | opus | high |

### Prerequisites outside this plan

1. **The working tree's `[P2-fix]` changes are committed before Task 1.** At plan time (2026-10-18) these files are modified and uncommitted: `CLAUDE.md`, `Docs/qa/2026-10-18-multi-community-phase2-gate.md`, `Legal/PRIVACY-DISCLOSURES.md`, `Legal/TERMS_OF_SERVICE.md`, `NaarsCars/Core/Services/AdminModerationService.swift` (`AdminReport.isCommunityReport`, `canDismissCommunityReport`), `NaarsCars/Features/Admin/Views/AdminReportsView.swift`, `LoginView.swift`, `SignupDetailsView.swift`, `JoinCommunityViewModel.swift`, `JoinCommunitySheet.swift`, `JoinCommunityViewModelTests.swift`, `Localizable.xcstrings` (including an edit of `guidelines_7_body`). They belong to another pass. Task 1 Step 0 stops if `git status --porcelain` lists any of them; never commit, stash or discard them.
2. **The SQL plan is applied before Task 11's live matrix.** Tasks 1-10 are verified with stubs and need no backend change. Until File A block 2 is live, community admins receive no `content_reported`; until File B is live, every figure and announcement call of the Phase 3 client fails (the client calls only the new RPCs).

## Review Focus

These are not exercised by any test the spec names. Each is pinned in its owning task.

1. **A second tap while a slow admin action runs** (Remove, Make owner, Save settings, Archive, Hide, Send announcement). Expected: one RPC. A second `transfer_community_ownership` would answer "Only the owner can hand over ownership" right after the first succeeded. Pinned by Task 3 (`testPerform_IgnoresSecondCallWhileActing`), Task 4 (`testSave_IgnoresSecondCallWhileSaving`), Task 5 (`testModerate_IgnoresSecondCallWhileActing`), Task 7 (`testSend_IgnoresSecondCallWhileSending`).
2. **A role that changed under an open screen** (demoted by the owner, removed, the community archived by a platform admin). The RPCs refuse with no `code` (`20261017_0005:1466-1468`, SQL plan File A blocks 3-4). `moderate_community_content` also refuses with codes this build does not know (`platform_handled`, `already_hidden`, `not_hidden`, `platform_hidden`, `already_closed`, SQL plan File A block 4); `CommunityRPC` decodes an unknown code as `nil` (`Core/Models/CommunityPayloads.swift:40-41, 124-134`), so they take the same path. Expected: one plain sentence, then the screen reloads into its inline "not an admin" state; never a generic error that repeats on every tap. Pinned by Task 3 (`testRefusalWithoutCode_ShowsNotAllowedAndReloads`) and Task 5 (`testLoad_RefusalWithoutCodeShowsNotAdmin`, `testModerate_RefusalShowsActionFailedAndReloads`).
3. **An action that succeeded whose follow-up reload fails** (the network drops right after the RPC). Expected: the removed member leaves the list, the hidden post shows as hidden, and no error is shown for the action that worked. Pinned by Task 3 (`testRemove_DropsRowRefreshesDashboardAndStaysGoneWhenReloadFails`) and Task 5 (`testModerate_UpdatesRowEvenWhenReloadFails`).
4. **Switching the admin panel's community while its figures load.** Expected: the tiles never show the previous community's numbers under the new title. Pinned by Task 6 (`testSelectScope_DropsStaleStats`).
5. **A platform admin's fourth announcement of the day**, new in Phase 3 (SQL plan File B block 10). Expected: a message that names the community and the limit, and the typed announcement is kept. Pinned by Task 1 (`testSendBroadcast_P0001MapsToDailyLimit`) and Task 7 (`testSend_DailyLimitShowsLocalizedMessageAndKeepsDraft`).
6. **A report platform moderators already handled, or content they (or the 3-reporter auto-hide) hid.** The server refuses a community admin's restore, hide and dismiss there (SQL plan File A block 4, D-S7) and says so per row (`platform_handled`, `can_restore`, block 3). Expected: the community list offers no button the server would refuse and says why in one line. Pinned by Task 5 (`testAvailableActions_MatchTheReportState`, `testAvailableActions_PlatformHandledAndPlatformHiddenOfferNothingTheServerRefuses`).

---

### Task 1: `AdminServiceProtocol` — figures, announcements, community reports and moderation

**Model:** opus, high effort (the moderation wrapper and the reporter-free report type are the client half of INV-P2; the argument names are the RPC seam) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Core/Protocols/AdminServiceProtocol.swift`, `NaarsCars/Core/Models/CommunityModerationPayloads.swift`, `NaarsCars/Core/Services/PreviewAdminService.swift` (whole file `#if DEBUG`)
- Modify: `NaarsCars/Core/Services/AdminService.swift:207-268` (the four figure methods), new methods after `:268`, `:512` (conformance)
- Modify (call sites, `communityId: nil`, and `count: 12` for the two breakdowns, since a protocol requirement carries no default): `NaarsCars/Features/Admin/ViewModels/AdminPanelViewModel.swift:88`, `NaarsCars/Features/Admin/Views/AdminFulfilledOverlay.swift:90`, `AdminSavingsOverlay.swift:92-103`, `AdminActiveRidesOverlay.swift:109`
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift` (fixtures, `StubAdminService`)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Core/Services/AdminServiceTests.swift`
- Reference: SQL plan File A blocks 3-4, File B blocks 2-5 and 10

**Interfaces:**
- Consumes: `CommunityRPC`, `CommunityRPCError` (`Core/Models/CommunityPayloads.swift:38-136`); `AdminDashboardStats`, `FulfilledPeriod`, `SavingsPeriod`, `ActiveRequestRow` (`AdminService.swift:27-89`, memberwise initializers kept); `CommunityServiceURLProtocol` and `CommunityServiceTests.bodyJSON(of:)` (test target, reused as is).
- Produces (`CommunityModerationPayloads.swift`; `Decodable, Equatable, Sendable`, explicit snake_case `CodingKeys`, decoded by `CommunityRPC.decode`):

```swift
/// One row of get_community_reports (SQL plan File A block 3). There is deliberately no reporter field.
struct CommunityReport: Identifiable, Equatable, Sendable {
    let reportId: UUID
    let targetType: String            // town_hall_post | town_hall_comment | ride | favor | user
    let reportedUserId: UUID?; let reportedUserName: String?
    let authorId: UUID?; let authorName: String?
    let reportedPostId: UUID?; let reportedCommentId: UUID?; let reportedRideId: UUID?; let reportedFavorId: UUID?
    let townHallPostId: UUID?
    let reportType: String; let description: String?
    let status: String                // the community's view: platform status once reviewed, else the community's decision, else "pending"
    let createdAt: Date; let reviewedAt: Date?
    let contentPreview: String?; let contentHidden: Bool; let reportCount: Int
    let canRestore: Bool              // can_restore: hidden, and the caller may restore it (block 3)
    let platformHandled: Bool         // platform_handled: a platform admin reviewed it; no hide, no dismiss here
    var id: UUID { reportId }
    var isPersonReport: Bool { targetType == "user" }
}
// Decodable in an extension (memberwise init kept for previews): contentHidden, canRestore and platformHandled
// default false, reportCount 1 when absent (an older server answers without the two flags; false offers less).
struct CommunityReportsPayload: Decodable, Sendable { let reports: [CommunityReport] }
enum CommunityModerationAction: String, CaseIterable, Sendable { case hide, restore, dismiss }
enum AdminServiceError: Error, Equatable {
    case broadcastDailyLimit   // send_community_broadcast SQLSTATE P0001
    case notCommunityAdmin     // SQLSTATE 42501
}
```

- Produces (`AdminServiceProtocol.swift`, and `extension AdminService: AdminServiceProtocol`):

```swift
protocol AdminServiceProtocol: AnyObject {
    /// nil = every community (platform admins only; the server refuses anyone else).
    func fetchDashboardStats(communityId: UUID?) async throws -> AdminDashboardStats
    func fetchFulfilledBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [FulfilledPeriod]
    func fetchSavingsBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [SavingsPeriod]
    func fetchActiveRequests(communityId: UUID?) async throws -> [ActiveRequestRow]
    /// Returns the number of members told. Throws AdminServiceError for the cap and for a non-admin.
    func sendBroadcast(communityId: UUID, title: String, message: String, pinToNotifications: Bool) async throws -> Int
    func fetchCommunityReports(communityId: UUID, status: String?) async throws -> [CommunityReport]
    func moderateCommunityContent(reportId: UUID, action: CommunityModerationAction, reason: String?) async throws
}
```

| Method | Call | Body keys |
|---|---|---|
| `fetchDashboardStats` | `rpc("get_community_stats")` → `CommunityRPC.decode(AdminDashboardStats.self)` | `p_community_id?` |
| `fetchFulfilledBreakdown` | `rpc("get_community_stats_fulfilled")` → private `StatsRows<FulfilledPeriod>` `{rows}` | `p_community_id?, p_period, p_count` |
| `fetchSavingsBreakdown` | `rpc("get_community_stats_savings")` | `p_community_id?, p_period, p_count` |
| `fetchActiveRequests` | `rpc("get_community_stats_active_requests")` | `p_community_id?` |
| `sendBroadcast(communityId:…)` | `rpc("send_community_broadcast")` → `Int` | `p_community_id, p_title, p_body, p_pinned` (`p_type` omitted: server default `'broadcast'`) |
| `fetchCommunityReports` | `rpc("get_community_reports")` → `CommunityReportsPayload.reports` | `p_community_id, p_status?` |
| `moderateCommunityContent` | `rpc("moderate_community_content")` → `decodeSuccess` | `p_report_id, p_action, p_reason?` |

- Each call uses a private `Encodable` params struct with explicit keys and a `nonisolated encode(to:)` (the `CommunityService.swift:15-195` idiom). The four figure methods replace the no-argument ones and **no longer call `verifyAdminStatus()`**: the server checks (`can_read_community_stats`, File B block 1), and a community admin must reach them; the platform-only panel keeps its own on-appear check (Task 6). `sendBroadcast(communityId:…)` catches `PostgrestError` and rethrows `AdminServiceError.broadcastDailyLimit` for `code == "P0001"`, `.notCommunityAdmin` for `"42501"`, anything else unchanged. The legacy `sendBroadcast(title:message:pinToNotifications:)` (`:480-509`) stays until Task 7.
- `PreviewAdminService` (`#if DEBUG`, `final class PreviewAdminService: AdminServiceProtocol`): settable `stats = AdminDashboardStats(fulfilledCount: 42, totalSavings: 1234, activeRidesCount: 3)`, `fulfilled`, `savings`, `active` (two rows each), `reports: [CommunityReport] = sampleReports` (a post report with author and a two-line reporter note, a comment report the caller hid (`canRestore` true), a ride report a platform moderator hid (`platformHandled` true, `canRestore` false), a person report), `broadcastError: Error?`, `reportsRefusal: CommunityRPCError?`; Swift values only, no network, no delay.
- Test target: `CommunityFixtures` gains `communityStatsJSON` (`{"success":true,"fulfilled_count":3,"total_savings":12.5,"active_rides_count":2}`), `fulfilledRowsJSON`, `savingsRowsJSON`, `activeRequestRowsJSON`, `communityReportsJSON` (two reports; the first is hidden with `"can_restore": true, "platform_handled": false` and also carries stray `"reporter_id"` and `"reporter_name"` keys, which must be ignored; the second has `"platform_handled": true` and no `can_restore` key), `statsRefusalJSON`, `reportsRefusalWithoutCodeJSON`, `moderateSuccessJSON`; `final class StubAdminService: AdminServiceProtocol` with one `var <name>Result` and one `private(set) var <name>Calls` per method and `var actionGate: (() async -> Void)?` awaited by `sendBroadcast` and `moderateCommunityContent` before they return.

- [ ] **Step 0: Preconditions and baseline.** `git status --porcelain` lists none of the files in Prerequisite 1 (else stop and ask). Build `HEAD` with `BUILD`'s command into `build/P3-baseline-build.log`; record the warning count.
- [ ] **Step 1: Write the failing tests** (spec §4 Phase 3: "stubbed `AdminServiceTests` (the service has no test class today) for every method that takes `communityId`"; CLAUDE.md fixture-test gate). Each asserts method and path (`POST /rest/v1/rpc/<name>`), the exact body key set, and the decoded value:

```swift
func testFetchDashboardStats_AllCommunitiesOmitsCommunityId()      // body key set == []; fulfilledCount 3, activeRidesCount 2
func testFetchDashboardStats_CommunitySendsCommunityId()           // keys == ["p_community_id"]
func testFetchDashboardStats_RefusalThrowsCommunityRPCError()      // statsRefusalJSON → CommunityRPCError, code nil
func testFetchFulfilledBreakdown_SendsPeriodAndCountAndDecodesRows() // keys == ["p_community_id","p_period","p_count"]; 2 rows
func testFetchSavingsBreakdown_AllCommunitiesOmitsCommunityId()    // keys == ["p_period","p_count"]
func testFetchActiveRequests_DecodesRows()                         // first row isRide, posterName set
func testSendBroadcast_SendsCommunityTitleBodyPinned()             // path rpc/send_community_broadcast; keys == ["p_community_id","p_title","p_body","p_pinned"]; returns 4
func testSendBroadcast_P0001MapsToDailyLimit()                     // stub answers 400 {"code":"P0001","message":"…","details":null,"hint":null} → .broadcastDailyLimit
func testSendBroadcast_42501MapsToNotCommunityAdmin()              // 403 {"code":"42501",…} → .notCommunityAdmin
func testFetchCommunityReports_SendsCommunityAndStatus()           // keys == ["p_community_id","p_status"]; 2 reports; [0].authorName set;
                                                                   // [0].canRestore true; [1].platformHandled true, [1].canRestore false (absent key)
func testFetchCommunityReports_NilStatusIsOmitted()                // keys == ["p_community_id"]
func testFetchCommunityReports_RefusalWithoutCodeThrowsNilCode()
func testCommunityReport_HasNoReporterField()                      // decodes communityReportsJSON; Mirror(reflecting: report).children
                                                                   // labels contain nothing with "reporter"
func testModerateCommunityContent_DismissOmitsNilReason()          // keys == ["p_report_id","p_action"]; p_action "dismiss"
func testModerateCommunityContent_HideSendsReason()                // keys == ["p_report_id","p_action","p_reason"]
func testModerateCommunityContent_RefusalThrows()
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find type 'AdminServiceProtocol' in scope".
- [ ] **Step 3: Implement** the three new files through the Xcode MCP (`XcodeLS NaarsCars/Core/Protocols`, `NaarsCars/Core/Models`, `NaarsCars/Core/Services`; confirm the app target), the service methods, the four call sites with `communityId: nil`, the fixtures and stub.
- [ ] **Step 4: Self-check before GREEN** (write the result into the task report): each params struct's keys match the SQL signature line by line (File A blocks 3-4, File B blocks 2-5, 10); no optional is encoded as an explicit null; `CommunityReport` has no property, coding key or computed value naming a reporter; nothing shows `serverMessage`; `PreviewAdminService.swift` is `#if DEBUG` from its first line to its last and imports nothing from the test target.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/AdminServiceTests -only-testing:NaarsCarsTests/CommunityServiceTests`. Expected: 16 new tests pass, `CommunityServiceTests` stays green.
- [ ] **Step 6: Commit** `[P3-T1] Add the community-scoped AdminService calls and a report type without a reporter` with the files above and `project.pbxproj`.

Strings: none. Live check: through Tasks 5, 6 and 7.

---

### Task 2: Member-management and settings wrappers

**Model:** opus, high effort (the wrappers for `remove_community_member`, `set_member_role` and `transfer_community_ownership` are the community's moderation tool for people, App Store 1.2; their argument encoding is the same RPC seam as Task 1, and a wrong or explicitly-null key changes who is removed or promoted) · **Files:**
- Modify: `NaarsCars/Core/Protocols/CommunityAdminServiceProtocol.swift:10-23`, `NaarsCars/Core/Services/CommunityService.swift:336-396` (and private params structs above `:197`), `NaarsCars/Core/Models/CommunityPayloads.swift` (three payloads, one `CommunityServiceError` case at `:79-82`), `NaarsCars/Core/Services/PreviewCommunityService.swift:162-245`
- Modify: `NaarsCars/NaarsCarsTests/Core/Fixtures/CommunityFixtures.swift:463-` (`StubCommunityAdminService`), `NaarsCars/NaarsCarsTests/Core/Services/CommunityServiceTests.swift`
- Reference: `20261017_0005_communities_rpcs.sql` blocks 11 (`update_community`, `:676-726`), 22-25 (`:1449-1705`); `20261017_0002_communities_rls.sql:232-247` (`communities` SELECT)

**Interfaces:**
- Produces:

```swift
struct RemovalResult: Decodable, Equatable, Sendable { let reopened: Int; let removed: Int; let cancelled: Int }   // :1508-1511
struct CommunitySettings: Decodable, Equatable, Sendable {
    let id: UUID; let name: String; let description: String?; let joinPolicy: String
    let membersCanInvite: Bool; let isPublic: Bool; let isDefault: Bool; let timezone: String
}
/// nil = leave unchanged. description "" clears it (update_community:712-714). timezone is never sent (no screen edits it).
struct CommunitySettingsChange: Equatable, Sendable {
    var name: String? = nil; var description: String? = nil
    var joinPolicy: CommunityJoinPolicy? = nil; var membersCanInvite: Bool? = nil
    var isEmpty: Bool { get }
}
enum CommunityServiceError: Error { case membershipNotUpdated, communityNotFound }   // + communityNotFound
// CommunityAdminServiceProtocol gains:
func removeMember(communityId: UUID, userId: UUID, reason: String?) async throws -> RemovalResult   // remove_community_member: p_community_id, p_user_id, p_reason?
func readmitMember(communityId: UUID, userId: UUID) async throws                                   // readmit_community_member: p_community_id, p_user_id
func setMemberRole(communityId: UUID, userId: UUID, role: CommunityRole) async throws               // set_member_role: p_community_id, p_user_id, p_role (rawValue)
func transferOwnership(communityId: UUID, userId: UUID) async throws                               // transfer_community_ownership: p_community_id, p_user_id
func fetchCommunitySettings(communityId: UUID) async throws -> CommunitySettings
    // from("communities").select("id, name, description, join_policy, members_can_invite, is_public, is_default, timezone")
    //   .eq("id", value:).limit(1); no row (archived, or not readable under the SELECT policy) → CommunityServiceError.communityNotFound
func updateCommunity(communityId: UUID, change: CommunitySettingsChange) async throws               // update_community: p_community_id + only the set fields
```
- `PreviewCommunityService` admin conformance gains the six methods (throw `adminRefusal` when set; `settings: CommunitySettings = sampleSettings`; `removal = RemovalResult(reopened: 1, removed: 0, cancelled: 0)`), and `fetchCommunityMembers` now answers by status: `.pending` → `members` (unchanged), `.active` → `activeMembers` (new, `sampleActiveMembers`: an owner, an admin, two members, one with a 60-character name), `.removed` → `removedMembers` (new, `sampleRemovedMembers`: one with a removal note). Swift values only.
- `StubCommunityAdminService` gains the six methods in its existing shape, with `actionGate` awaited by the four writes.

- [ ] **Step 1: Write the failing tests** in `CommunityServiceTests` (spec §4 Phase 3: stubbed tests for every method that takes `communityId`):

```swift
func testRemoveMember_SendsReasonAndDecodesCounts()        // keys == ["p_community_id","p_user_id","p_reason"]; RemovalResult(1, 1, 0)
func testRemoveMember_NilReasonIsOmitted()                 // keys == ["p_community_id","p_user_id"]
func testRemoveMember_LastOwnerThrowsLastOwner()
func testReadmitMember_NotRemovedThrowsNotRemoved()
func testSetMemberRole_SendsRawRole()                      // p_role == "admin"
func testTransferOwnership_SendsCommunityAndUser()
func testFetchCommunitySettings_QueriesByIdAndDecodes()    // GET /rest/v1/communities, query id=eq.<A>; membersCanInvite false
func testFetchCommunitySettings_NoRowThrowsNotFound()      // [] → CommunityServiceError.communityNotFound
func testUpdateCommunity_SendsOnlyChangedFields()          // change(name: "New name", membersCanInvite: false) →
                                                           // keys == ["p_community_id","p_name","p_members_can_invite"]
func testUpdateCommunity_ClearingDescriptionSendsEmptyString() // change(description: "") → body["p_description"] == ""
```
- [ ] **Step 2: RED.** `RED`. Expected: "value of type 'CommunityService' has no member 'removeMember'".
- [ ] **Step 3: Implement**; fixtures `removeResultJSON`, `lastOwnerRefusalJSON`, `notRemovedRefusalJSON`, `communitySettingsRowsJSON`, `successJSON` (`{"success":true}`).
- [ ] **Step 4: Self-check before GREEN** (write the result into the task report): each params struct's keys match the SQL signature line by line (`20261017_0005` blocks 11, 22-25: `remove_community_member(p_community_id, p_user_id, p_reason)`, `readmit_community_member(p_community_id, p_user_id)`, `set_member_role(p_community_id, p_user_id, p_role)`, `transfer_community_ownership(p_community_id, p_user_id)`, `update_community(p_community_id, p_name, p_description, p_join_policy, p_members_can_invite, p_timezone)`); `p_user_id` is always the target member, never the caller; no optional is encoded as an explicit null (`encodeIfPresent`), except the deliberate `p_description: ""`; `p_role` is `CommunityRole.rawValue` (`"admin"`, `"member"`), never a display string; `p_timezone` is never sent.
- [ ] **Step 5: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityServiceTests`. Expected: 10 new tests pass.
- [ ] **Step 6: Commit** `[P3-T2] Add the member-management and settings wrappers` with the files above.

Strings: none. Live check: through Tasks 3 and 4.

---

### Task 3: Members and member detail

**Model:** opus, high effort (removal unwinds a person's requests in that community and is the community's moderation tool for people, App Store 1.2; spec F13-F14) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Community/ViewModels/CommunityMembersViewModel.swift` (holds `CommunityMemberAction`, `CommunityMemberActions`, `CommunityMembersList`), `NaarsCars/Features/Community/Views/CommunityMembersView.swift` (holds `CommunityMembersTarget`), `NaarsCars/Features/Community/Views/CommunityMemberDetailView.swift` (holds `RemoveMemberSheet`)
- Modify: `NaarsCars/Core/Models/CommunityPayloads.swift` (`extension CommunityMember: Hashable {}`, `func replacingRole(_:) -> CommunityMember`)
- Modify: `NaarsCars/Core/Utilities/Constants.swift:246-260` (`Community.removalNoteMaxLength = 500`)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/CommunityMembersViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 2's wrappers and stub; `CommunityContext.isAdmin(of:)`, `membership(for:)`, `isPlatformAdmin`, `refreshMemberships()`, `isAwaitingMemberships` (`App/CommunityContext.swift:58-191`); `AuthServiceProtocol.currentUserId`.
- Produces:

```swift
enum CommunityMemberAction: Hashable { case remove, readmit, makeAdmin, makeMember, transferOwnership }
enum CommunityMembersList: Hashable, CaseIterable { case active, removed }
enum CommunityMemberActions {
    /// Mirrors the server (20261017_0005): remove_community_member :1466-1490, readmit :1536-1546,
    /// set_member_role :1602-1632, transfer_community_ownership :1664-1681. Pure; tested as a table.
    static func available(for member: CommunityMember, callerId: UUID?, callerRole: CommunityRole?,
                          isPlatformAdmin: Bool) -> [CommunityMemberAction]
}
struct CommunityMembersTarget: Hashable { let communityId: UUID; let communityName: String?; var highlightTransfer = false }
@MainActor final class CommunityMembersViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }
    @Published private(set) var access: Access = .checking
    @Published var list: CommunityMembersList = .active
    @Published var query = ""
    @Published private(set) var members: [CommunityMember] = []
    @Published private(set) var isLoading = false
    @Published var loadError: String?             // full-screen ErrorView only while members is empty
    @Published var actionErrorMessage: String?    // errorBanner
    @Published var toastMessage: String?
    @Published private(set) var actingOnUserId: UUID?
    let communityId: UUID; let communityName: String?
    init(communityId: UUID, communityName: String?,
         adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
         communityContext: CommunityContext? = nil, authService: any AuthServiceProtocol = AuthService.shared,
         refreshDashboard: @escaping @MainActor (String) async -> Void = {
             _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0) })
    var filteredMembers: [CommunityMember] { get }      // query matched against name, case- and diacritic-insensitive
    func actions(for member: CommunityMember) -> [CommunityMemberAction]
    func load() async                                   // also on list change
    @discardableResult func perform(_ action: CommunityMemberAction, on member: CommunityMember, reason: String? = nil) async -> Bool
}
struct CommunityMembersView: View { init(target: CommunityMembersTarget, viewModel: …defaulted…) }   // pushed; no NavigationStack
struct CommunityMemberDetailView: View { init(member: CommunityMember, viewModel: CommunityMembersViewModel) }
```

- `available(for:…)` rules: `[]` when `member.id == callerId` or the member is `pending` / `left`; `removed` → `[.readmit]` when the caller is an admin (owner, admin or platform admin), else `[]`; `active`, caller is admin: `.remove` when `member.role == .member` or the caller is the owner or a platform admin; `.makeAdmin` when the caller is the owner or a platform admin and `member.role` is `.member` or `.owner` (demoting a co-owner); `.makeMember` under the same caller rule when `member.role == .admin`; `.transferOwnership` only when `callerRole == .owner` and `member.role != .owner` (a platform admin who is not the owner cannot transfer, `:1664`). Order: transferOwnership, makeAdmin, makeMember, remove.
- `load()`: `isAwaitingMemberships` → `await refreshMemberships()`; `!isAdmin(of:)` → `access = .notAdmin`, no list call (`get_community_members` would answer the active directory to a plain member, `:1930`); else `fetchCommunityMembers(communityId:, status: list == .active ? .active : .removed, limit: Constants.Community.membersPageSize, offset: 0)`; a failure keeps the rows and sets `actionErrorMessage = "common_load_error".localized` when rows exist, `loadError` otherwise.
- `perform`: return false while `actingOnUserId != nil` or when `actions(for:)` no longer contains the action. Success: `.remove` → drop the row, `await refreshDashboard("removedMember")`, toast; `.readmit` → drop the row from the removed list, toast; `.makeAdmin` / `.makeMember` → replace the row with `replacingRole(_:)`, toast; `.transferOwnership` → toast; then, for every action, `await communityContext.refreshMemberships()` and `await load()` (their failures change nothing already shown). `.remove` sends `reason` trimmed, `nil` when empty, sanitized with `Validators.sanitizeUserInput` to `Constants.Community.removalNoteMaxLength`. Refusal with `code == nil` → `actionErrorMessage = community_member_action_not_allowed`, then `refreshMemberships()` and `load()` (which ends in `.notAdmin` when the role is gone); a coded refusal → `localizedMessage` (`.lastOwner`, `.notActive`, `.notRemoved`, `.restricted`, `.full`), and `.notActive` / `.notRemoved` also reload; a non-RPC error → `community_error_generic`.
- `CommunityMembersView`: a segmented `Picker` (Members / Removed), `.searchable(text: $viewModel.query)`, rows (`AvatarView(imageUrl:name:size: 40)`, name with `lineLimit(2)`, role `NaarsChip` for owner and admin using `community_role_owner` / `community_role_admin`, `community_member_joined` with the abbreviated `joinedAt`; removed rows show `community_member_removal_note` when set) as `NavigationLink(value: member)` → `CommunityMemberDetailView`; skeleton, `EmptyStateView` (`community_members_empty` / `community_members_removed_empty`), the inline not-admin state (`community_pending_not_admin`); `highlightTransfer` shows a card with `community_members_transfer_banner` above the list. `.task { await viewModel.load() }`, `.refreshable`, toast, `.errorBanner(message: $viewModel.actionErrorMessage)`.
- `CommunityMemberDetailView`: header (64-pt avatar, name, car, role chip, joined); for admins the answers and inviter when present (`admin_heard_about_label`, `admin_join_reason_label`, `community_pending_invited_by`); one button per `viewModel.actions(for:)`, each behind its confirmation alert with the copy below; Remove opens `RemoveMemberSheet` (body copy, optional note field with a live count to 500, footer copy, destructive Remove, `.interactiveDismissDisabled` while acting); after a successful remove or readmit the detail pops.

- [ ] **Step 1: Write the failing tests** (spec §4 Phase 3 member management; Review Focus 1-3). A `CommunityContext` on a suite as in `PendingMembersViewModelTests.swift:41-53`:

```swift
func testActions_PlainMemberCallerGetsNothing()                  // callerRole .member → [] for every target
func testActions_AdminCanRemoveMembersButNotAdminsOrOwners()     // admin caller: member → [.remove]; admin → []; owner → []
func testActions_OwnerGetsRoleAndTransferActions()               // owner: member → [.transferOwnership, .makeAdmin, .remove];
                                                                 // admin → [.transferOwnership, .makeMember, .remove]; co-owner → [.makeAdmin, .remove]
func testActions_PlatformAdminWhoIsNotOwnerCannotTransfer()      // callerRole nil, isPlatformAdmin → member: [.makeAdmin, .remove]
func testActions_NeverOnSelf()
func testActions_RemovedMemberOffersReadmitToAdminsOnly()
func testLoad_NotAdminShowsInlineStateWithoutFetching() async    // member role → access .notAdmin; fetchCommunityMembersCalls empty
func testPerform_IgnoresSecondCallWhileActing() async            // actionGate held; perform(.remove, a); perform(.remove, b) → removeMemberCalls.count == 1
func testRemove_DropsRowRefreshesDashboardAndStaysGoneWhenReloadFails() async
    // after the remove succeeds the fetch fails → members has no a; refreshDashboard got ["removedMember"]; actionErrorMessage nil
func testRemove_SendsTrimmedReasonOrNil() async                  // "  Spam  " → "Spam"; "   " → nil
func testRefusalWithoutCode_ShowsNotAllowedAndReloads() async    // setMemberRoleResult = refusal(code nil) → message == community_member_action_not_allowed.localized;
                                                                 // fetchMyMemberships called again; a member-role reload → access .notAdmin
func testLastOwnerRefusal_ShowsLocalizedMessage() async          // removeMember → .lastOwner → actionErrorMessage == community_error_last_owner.localized
func testFilteredMembers_MatchesNameIgnoringCaseAndDiacritics()  // "jose" matches "José Ruiz"
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CommunityMembersViewModel' in scope".
- [ ] **Step 3: Implement** (three app files through the Xcode MCP) with `#Preview`s on `PreviewCommunityService` (members as owner, removed list, not-admin, transfer banner; the detail for an owner looking at a member, an admin looking at an admin, a removed member; `RemoveMemberSheet`), every `#Preview` of a file inside one `#if DEBUG … #endif` (Global Constraints); add the strings.
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Community/Views/CommunityMembersView.swift NaarsCars/Features/Community/Views/CommunityMemberDetailView.swift` (no output); `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityMembersViewModelTests`. Expected: 13 pass.
- [ ] **Step 5: Commit** `[P3-T3] Add community members: remove, let back in, roles and ownership` with the files above and `project.pbxproj`.

Strings:
```
community_members_title = "Members"
community_members_segment_active = "Members"
community_members_segment_removed = "Removed"
community_members_search = "Search members"
community_members_empty = "No members yet."
community_members_removed_empty = "No one has been removed."
community_members_transfer_banner = "Choose who becomes the owner. You'll become an admin."
community_member_joined = "Joined %@"
community_member_removal_note = "Note: %@"
community_member_action_remove = "Remove from community"
community_member_action_readmit = "Let back in"
community_member_action_make_admin = "Make admin"
community_member_action_make_member = "Make member"
community_member_action_transfer = "Make owner"
community_member_remove_title = "Remove %@?"
community_member_remove_body = "Claims they made here reopen, their open requests here are removed, and requests they posted that a neighbor claimed are cancelled. They're told a community admin removed them. Only an admin can let them back in."
community_member_remove_note_label = "Note (optional)"
community_member_remove_note_footer = "Only they and this community's admins can see this note."
community_member_remove_confirm = "Remove"
community_member_readmit_title = "Let %@ back in?"
community_member_readmit_body = "They'll see this community's requests, Town Hall and members again."
community_member_make_admin_title = "Make %@ an admin?"
community_member_make_admin_body = "Admins approve requests to join, remove members, handle reports and send announcements."
community_member_make_member_title = "Make %@ a member?"
community_member_make_member_body = "They'll no longer be an admin of this community."
community_member_transfer_title = "Make %@ the owner?"
community_member_transfer_body = "You'll become an admin. Only the owner can change roles and settings or hand over ownership."
community_member_removed_toast = "%@ was removed."
community_member_readmitted_toast = "%@ is back in."
community_member_role_changed_toast = "%@'s role was changed."
community_member_transferred_toast = "%@ is now the owner."
community_member_action_not_allowed = "You can't do that here. Your role in this community may have changed."
```
Each sentence's source: removal effects `20261017_0004` `unwind_member_requests` (1)-(3) and `20261017_0005:1504-1506` (the notice names no remover); the note's readers `20261017_0002:251-256` (own row) and `:1923` (admins); readmit `:1523-1580`; roles `:1591-1642`, transfer `:1653-1702`.

Capture list (Task 11): Members (owner view, removed list, search, not-admin, transfer banner), the detail in each action set, the remove sheet, the 60-character name at AX5; light / dark / AX5. `#Preview`: `CommunityMembersView`, `CommunityMemberDetailView`, `RemoveMemberSheet` (yes).

Live check **(writes)**: Task 11 O3.

---

### Task 4: Community settings, archive, and "choose a new owner"

**Model:** opus (archiving ends every member's access and may end the owner's last membership → `onActiveMembershipsEmpty` → `recheckAccountStatus`, fragile system 5) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Community/ViewModels/CommunitySettingsViewModel.swift`, `NaarsCars/Features/Community/Views/CommunitySettingsView.swift`
- Modify: `NaarsCars/Features/Community/ViewModels/MyCommunitiesViewModel.swift:66-93` (state), `:166-189` (`leave`)
- Modify: `NaarsCars/Features/Community/Views/MyCommunitiesView.swift:112-133` (alert and destination)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/CommunitySettingsViewModelTests.swift`
- Modify: `NaarsCars/NaarsCarsTests/Features/Community/MyCommunitiesViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `fetchCommunitySettings`, `updateCommunity`, `CommunitySettingsChange` (Task 2); `archiveCommunity` (Phase 2); `CommunityMembersView`, `CommunityMembersTarget` (Task 3); `CommunityContext.forgetMembership(_:)` (`:237-245`).
- Produces:

```swift
@MainActor final class CommunitySettingsViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }
    @Published private(set) var access: Access = .checking
    @Published private(set) var settings: CommunitySettings?
    @Published var name = ""; @Published var description = ""
    @Published var requiresApproval = true; @Published var membersCanInvite = true
    @Published private(set) var isSaving = false; @Published private(set) var isArchiving = false
    @Published var errorMessage: String?; @Published var toastMessage: String?
    @Published private(set) var didArchive = false
    let communityId: UUID
    init(communityId: UUID, adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
         communityContext: CommunityContext? = nil,
         refreshDashboard: @escaping @MainActor (String) async -> Void = {
             _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0) })
    var canEdit: Bool { get }      // owner of it or platform admin (update_community :694-697); a plain admin reads only
    var canArchive: Bool { get }   // (owner or platform admin) && settings?.isDefault == false (archive_community :784-794)
    var change: CommunitySettingsChange { get }   // only fields that differ from `settings` after trimming
    var canSave: Bool { get }      // canEdit, !change.isEmpty, trimmed name in Constants.Community.nameLength,
                                   // description ≤ Constants.Community.descriptionMaxLength, !isSaving
    func load() async              // isAdmin(of:) gate as Task 3, then fetchCommunitySettings → fields
    @discardableResult func save() async -> Bool     // updateCommunity(change); success → settings refreshed by load(),
                                                     // refreshMemberships() (names in menus and chips), toast
    @Published private(set) var archiveConfirmation: String?   // "<name> was archived.", set before didArchive (Task 4 fix)
    @discardableResult func archive() async -> Bool  // archiveCommunity; success → archiveConfirmation, didArchive = true,
                                                     // forgetMembership(id), refreshMemberships(), refreshDashboard("archivedCommunity")
}
struct CommunitySettingsView: View {
    init(communityId: UUID, onArchived: @escaping (_ confirmation: String) -> Void = { _ in }, viewModel: …defaulted…)   // pushed; no NavigationStack
}
// MyCommunitiesViewModel
@Published var newOwnerNeededFor: CommunityMembership?   // set instead of errorMessage when leave is refused with .lastOwner
```
- `CommunitySettingsView` (`Form` on `Color.naarsBackground`): Name and Description (`TextField`s with counts, disabled unless `canEdit`), "Approve new members manually" and "Members can invite people" toggles with their footers, `community_settings_owner_only` footer when `!canEdit`, Save in the confirmation toolbar slot (`canSave`); an Archive section when `canArchive` with a destructive button behind an alert (`community_settings_archive_title`, `…_body`); `.onChange(of: viewModel.didArchive)` → `onArchived(viewModel.archiveConfirmation)` then `dismiss()` (the screen closes at once, so its presenter shows the confirmation, not this screen's toast). Skeleton while loading; the inline not-admin state. `#Preview`s for owner, admin (read-only), default community (no Archive).
- `MyCommunitiesViewModel.leave`: a `CommunityRPCError` with `code == .lastOwner` sets `newOwnerNeededFor = membership` and leaves `errorMessage` nil; every other path is unchanged. `MyCommunitiesView` shows an alert `community_leave_needs_owner_title` / `community_leave_needs_owner_body(name)` with `community_leave_needs_owner_action`, which sets `@State membersTarget = CommunityMembersTarget(communityId:, communityName:, highlightTransfer: true)` pushed through `.navigationDestination(item: $membersTarget)` (closes the Phase 2 follow-up "a sole owner with other members cannot leave until Phase 3's transfer screen").

- [ ] **Step 1: Write the failing tests** (CLAUDE.md Testing Expectations, Auth: the zero-membership path through `forgetMembership`; Review Focus 1):

```swift
// CommunitySettingsViewModelTests
func testLoad_FillsFieldsFromSettings() async                 // requiresApproval == (joinPolicy == "approve")
func testCanEdit_OwnerOrPlatformAdminOnly() async             // owner true; admin false; platform admin with no membership true
func testChange_ContainsOnlyEditedFields() async              // name edited with trailing spaces → change == .init(name: "New")
func testSave_IgnoresSecondCallWhileSaving() async            // actionGate held → updateCommunityCalls.count == 1
func testCanSave_ValidatesNameAndDescription() async          // 1-character name false; 301-character description false
func testArchive_ForgetsMembershipAndRefreshesDashboard() async  // didArchive; context no longer has A; refreshDashboard == ["archivedCommunity"]
func testCanArchive_NeverForTheDefaultCommunity() async
// MyCommunitiesViewModelTests
func testLeave_LastOwnerRefusalOffersTransfer() async         // leaveCommunityResult = .lastOwner → newOwnerNeededFor == A; errorMessage nil
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CommunitySettingsViewModel' in scope".
- [ ] **Step 3: Implement**, the `CommunitySettingsView` `#Preview`s inside one `#if DEBUG … #endif` (Global Constraints), and any preview edited in `MyCommunitiesView.swift` likewise; add the strings.
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Community/Views/CommunitySettingsView.swift NaarsCars/Features/Community/Views/MyCommunitiesView.swift` (no output); `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunitySettingsViewModelTests -only-testing:NaarsCarsTests/MyCommunitiesViewModelTests`. Expected: 8 new tests pass, the Phase 2 cases stay green.
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P3-T4] Add community settings and archive; offer a new owner when the last owner leaves` with the files above and `project.pbxproj`.

Strings:
```
community_settings_title = "Community settings"
community_settings_name = "Name"
community_settings_description = "Description"
community_settings_requires_approval = "Approve new members manually"
community_settings_requires_approval_footer = "When off, anyone with an invite code joins right away. People who ask to join a public community still wait for an admin."
community_settings_members_can_invite = "Members can invite people"
community_settings_members_can_invite_footer = "When off, only admins can make invite codes, and codes that members made stop working."
community_settings_owner_only = "Only the owner can change these settings."
community_settings_save = "Save"
community_settings_saved_toast = "Settings saved."
community_settings_archive = "Archive community"
community_settings_archive_title = "Archive %@?"
community_settings_archive_body = "Members lose access at once and are told. Claimed requests are cancelled and their posters and helpers are told. Its content is kept, and only a platform moderator can restore it."
community_settings_archived_toast = "%@ was archived."
community_leave_needs_owner_title = "Choose a new owner first"
community_leave_needs_owner_body = "%@ needs an owner. Make another member the owner, then you can leave."
community_leave_needs_owner_action = "Choose a new owner"
```
Sources: invite policy `20261017_0005` block 18 and block 19 (public requests are always pending); member codes stop `lookup_community_invite` `:232-237`; archive `:281-343`, restore platform-only `:814-839`.

Capture list (Task 11): settings as owner, as admin, the default community, the archive alert; My communities' "choose a new owner" alert and the pushed Members with the banner; light / dark / AX5. `#Preview`: `CommunitySettingsView` (yes).

Live check **(writes)**: Task 11 O3.

---

### Task 5: Community reports

**Model:** opus, high effort (moderation, App Store 1.2; reporter privacy INV-P2) · **Files:**
- Create (Xcode MCP, app target): `NaarsCars/Features/Community/ViewModels/CommunityReportsViewModel.swift` (holds `CommunityReportFilter`, `CommunityReportActions`), `NaarsCars/Features/Community/Views/CommunityReportsView.swift`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Community/CommunityReportsViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `AdminServiceProtocol.fetchCommunityReports`, `moderateCommunityContent`, `CommunityReport`, `CommunityModerationAction`, `StubAdminService`, `PreviewAdminService` (Task 1); `CommunityContext.isAdmin(of:)`.
- Produces:

```swift
enum CommunityReportFilter: CaseIterable, Hashable { case pending, all, resolved, dismissed
    var status: String? { get } }   // "pending", nil, "action_taken", "dismissed" (labels: admin_reports_filter_*)
enum CommunityReportActions {
    /// Mirrors moderate_community_content (SQL plan File A block 4, D-S7), not AdminReportsView: a community admin
    /// may not hide hidden content, may restore only when the server says so, and may not hide or dismiss a report a
    /// platform admin reviewed. Pure; tested as a table. Order: hide, restore, dismiss.
    ///   person report: [.dismiss] when status == "pending" && !platformHandled, else []
    ///   content:       .hide    when !contentHidden && !platformHandled
    ///                  .restore when contentHidden && canRestore
    ///                  .dismiss when status == "pending" && !platformHandled
    static func available(for report: CommunityReport) -> [CommunityModerationAction]
}
extension CommunityReport {
    /// The report type in the person's language, through the six-locale keys the report sheets already use
    /// (ReportContentSheet.swift:41-45, ReportMessageSheet.swift:24-28): MessageService.ReportType(rawValue:)
    /// (MessageServiceModels.swift:45-51) → messaging_report_spam / _harassment / _inappropriate_content / _scam /
    /// _other; an unknown or empty value → messaging_report_other. Never the raw value, never
    /// AdminReport.reportTypeDisplay's humanized English (AdminModerationService.swift:37-39).
    var reportTypeLabel: String { get }
    /// The row after a successful action, for the local update: hide → status "action_taken", contentHidden true,
    /// canRestore true; restore → contentHidden false, canRestore false; dismiss → status "dismissed".
    func applying(_ action: CommunityModerationAction) -> CommunityReport
}
@MainActor final class CommunityReportsViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }
    @Published private(set) var access: Access = .checking
    @Published private(set) var reports: [CommunityReport] = []
    @Published var filter: CommunityReportFilter = .pending
    @Published private(set) var isLoading = false
    @Published var loadError: String?; @Published var actionErrorMessage: String?
    @Published private(set) var actingOnReportId: UUID?
    let communityId: UUID
    init(communityId: UUID, adminService: any AdminServiceProtocol = AdminService.shared, communityContext: CommunityContext? = nil)
    func load() async
    @discardableResult func moderate(_ report: CommunityReport, action: CommunityModerationAction, reason: String?) async -> Bool
}
struct CommunityReportsView: View { init(communityId: UUID, communityName: String?, viewModel: …defaulted…) }   // pushed
```
- `load()`: the `isAdmin(of:)` gate as Task 3; `fetchCommunityReports(communityId:, status: filter.status)`; a `CommunityRPCError` with `code == nil` → `access = .notAdmin`; another failure → `loadError` while `reports` is empty, else `actionErrorMessage = "common_load_error".localized`.
- `moderate`: false while `actingOnReportId != nil`, when `available(for:)` lacks the action, or for `.hide` with an empty trimmed reason (no call). Success: replace the row locally with `report.applying(action)`, `HapticManager.success()`, then `load()` (a failure there keeps the replaced row). Refusal (any code, including the five codes this build does not know, which decode to `nil`) → `actionErrorMessage = community_reports_action_failed` and `load()`, whose fresh `platformHandled` / `canRestore` remove the refused button; a non-RPC error → `community_error_generic`.
- `CommunityReportsView`: the filter capsules of `AdminReportsView.swift:106-126` (same labels); a header card with `community_reports_scope_note`; one card per report: target label and icon from `admin_reports_target_post` / `_comment` / `_ride` / `_favor` / `_user`, a `NaarsChip` with `report.reportTypeLabel` (localized; never `reportType` itself), the count badge when `reportCount > 1` (`NotificationBadge`), the preview (3 lines) or, for a person report, `admin_reports_reported_member(name)`; `admin_reports_content_author(authorName)` when set; the reporter's note under `admin_reports_reporter_note`; relative time; when `platformHandled`, the line `community_reports_platform_handled` in place of buttons; when `contentHidden && !canRestore && !platformHandled` (the auto-hide, or a platform moderator's hide on a report still pending here), the line `community_reports_restore_platform_only`; then the action buttons from `CommunityReportActions`, or the resolved label when there are none. **No line names or links a reporter.** An action opens a sheet like `AdminReportsView.swift:161-210` (confirmation text from `admin_reports_*_confirm_message`, note field with `admin_reports_hide_reason_placeholder` / `admin_reports_optional_note_placeholder`, plus `community_reports_hide_author_told` under Hide and `community_reports_person_dismiss_hint` under a person report's Dismiss). Skeleton, `EmptyStateView`, inline not-admin (`community_pending_not_admin`).

- [ ] **Step 1: Write the failing tests** (spec §4 Phase 3 community reports; INV-P2; Review Focus 1-3):

```swift
func testAvailableActions_MatchTheReportState()                  // pending, visible → [.hide, .dismiss]; pending, hidden, canRestore → [.restore, .dismiss];
                                                                 // action_taken, hidden, canRestore → [.restore]; dismissed, visible → [.hide];
                                                                 // person pending → [.dismiss]; person dismissed → []
func testAvailableActions_PlatformHandledAndPlatformHiddenOfferNothingTheServerRefuses()
                                                                 // platformHandled, hidden, !canRestore → []; platformHandled, visible → [];
                                                                 // pending, hidden, !canRestore (auto-hide) → [.dismiss]; never .hide when contentHidden
func testReportTypeLabel_UsesTheReportKeysAndFallsBackToOther()  // "spam" → messaging_report_spam.localized;
                                                                 // "inappropriate_content" → messaging_report_inappropriate_content.localized;
                                                                 // "doxxing" and "" → messaging_report_other.localized
func testLoad_RefusalWithoutCodeShowsNotAdmin() async
func testLoad_FilterSendsStatus() async                          // .pending → "pending"; .all → nil; .resolved → "action_taken"
func testModerate_HideWithoutReasonSendsNothing() async          // reason "  " → false; moderateCommunityContentCalls empty
func testModerate_IgnoresSecondCallWhileActing() async
func testModerate_UpdatesRowEvenWhenReloadFails() async          // hide succeeds, reload throws → row status "action_taken", contentHidden true;
                                                                 // actionErrorMessage nil
func testModerate_RefusalShowsActionFailedAndReloads() async     // refusal(code nil) → community_reports_action_failed; fetch called again
```
- [ ] **Step 2: RED.** `RED`. Expected: "cannot find 'CommunityReportsViewModel' in scope".
- [ ] **Step 3: Implement** with `#Preview`s on `PreviewAdminService` (list with the four sample reports, empty, not-admin, the hide sheet), all inside one `#if DEBUG … #endif` (Global Constraints); add the strings.
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Community/Views/CommunityReportsView.swift` (no output); `grep -n "reportTypeDisplay\|capitalized" NaarsCars/Features/Community/Views/CommunityReportsView.swift NaarsCars/Features/Community/ViewModels/CommunityReportsViewModel.swift` (no output); `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/CommunityReportsViewModelTests`. Expected: 9 pass.
- [ ] **Step 5: Commit** `[P3-T5] Add community reports with hide, restore and dismiss and no reporter` with the files above and `project.pbxproj`.

Strings:
```
community_reports_title = "Reports"
community_reports_scope_note = "You don't see who reported. Reports about this community's owners and admins, and about anything you posted, go to platform moderators."
community_reports_empty_title = "No reports"
community_reports_empty_body = "Reports about posts, comments, requests and members of this community appear here."
community_reports_action_failed = "This report can't be changed here. A platform moderator may have handled it."
community_reports_hide_author_told = "The author is told it was hidden and sees your reason."
community_reports_person_dismiss_hint = "To act on a person, remove them in Members."
community_reports_platform_handled = "Platform moderators handled this report."
community_reports_restore_platform_only = "Hidden by platform moderators or automatically after several reports. Only platform moderators can restore it."
```
The report-type chip adds no key: it reuses `messaging_report_spam`, `messaging_report_harassment`, `messaging_report_inappropriate_content`, `messaging_report_scam` and `messaging_report_other`, which have all six locales today.
Sources: `get_community_reports` exclusions and flags (SQL plan File A block 3), the author's notice `create_content_hidden_notification` ("A moderator hid your content: <reason>"), person reports dismiss-only and the platform-wins rules (block 4, D-S7), the auto-hide at 3 reporters (`handle_new_report`, block 2).

Capture list (Task 11): the list (pending, all), a person report, a platform-handled report, an auto-hidden report, the hide sheet, empty, not-admin; light / dark / AX5; the type chip in one non-English locale (`-AppleLanguages (es)`). `#Preview`: `CommunityReportsView` (yes).

Live check **(writes)**: Task 11 O3.

---

### Task 6: Admin panel per community and its entry points

**Model:** opus, high effort (who sees which admin tools; `MyProfileView` and `CommunityContext` are shared state; spec §3.7 "Admin") · **Files:**
- Modify: `NaarsCars/Features/Admin/ViewModels/AdminPanelViewModel.swift:11-99`
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift:12-19` (init and state), `:24-88` (title, menu, access), `:109-155` (figures and overlays), `:221-319` (sections by scope), `:356-358` (previews)
- Modify: `NaarsCars/Features/Admin/Views/AdminFulfilledOverlay.swift:10-17`, `AdminSavingsOverlay.swift:10-17`, `AdminActiveRidesOverlay.swift:10-16` (`communityId: UUID?`, `service: any AdminServiceProtocol = AdminService.shared`)
- Modify: `NaarsCars/App/CommunityContext.swift:156-191` (two lookups)
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:81-84` (row condition), `:642-660` (`adminPanelLink(scope:)`)
- Modify: `NaarsCars/Features/Community/Views/MyCommunitiesView.swift:244-279` (menu item), `:112-117` (destination)
- Modify: `NaarsCars/Features/Admin/ViewModels/CommunitiesAdminViewModel.swift:11-13`, `:38-60`, `:100-121`; `NaarsCars/Features/Admin/Views/CommunitiesAdminView.swift:51`, `:224-251`, `:287-303`
- Create group (Xcode MCP `XcodeMakeDir`, confirmed with `XcodeLS`): `NaarsCars/NaarsCarsTests/Features/Admin`
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Admin/AdminPanelViewModelTests.swift`
- Modify: `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift` (one test)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `AdminServiceProtocol.fetchDashboardStats(communityId:)`, `StubAdminService`, `PreviewAdminService` (Task 1); `fetchDefaultCommunityId`, `fetchCommunitySettings` (Phase 2, Task 2); `CommunityMembersView` (Task 3), `CommunitySettingsView` (Task 4), `CommunityReportsView` (Task 5), `PendingMembersView(target:)` (Phase 2).
- Produces:

```swift
// CommunityContext
var administeredCommunities: [CommunityMembership] { get }   // active owner / admin rows, in membership order
var isAdminOfAnyCommunity: Bool { get }
// AdminPanelViewModel.swift
enum AdminPanelScope: Hashable {
    case all, community(UUID)
    var communityId: UUID? { get }
    /// platform admin → .all; else the first administered community; else nil (the Profile row is hidden)
    static func initial(isPlatformAdmin: Bool, administered: [CommunityMembership]) -> AdminPanelScope?
}
struct AdminPanelMenuEntry: Identifiable, Equatable { let scope: AdminPanelScope; let title: String; var id: AdminPanelScope { scope } }
struct BroadcastTarget: Equatable { let communityId: UUID; let communityName: String }
@MainActor final class AdminPanelViewModel: ObservableObject {
    // kept, same names: isVerifyingAdmin, isAdmin, verificationErrorMessage, fulfilledCount, totalSavings,
    // activeRidesCount, error, isLoading, statsErrorMessage, hasLoadedStats, formattedSavings
    @Published private(set) var scope: AdminPanelScope
    @Published private(set) var communityName: String?
    @Published private(set) var broadcastTarget: BroadcastTarget?
    init(initialScope: AdminPanelScope = .all, communityName: String? = nil,
         adminService: any AdminServiceProtocol = AdminService.shared,
         communityAdminService: any CommunityAdminServiceProtocol = CommunityService.shared,
         communityContext: CommunityContext? = nil,
         verifyPlatformAdmin: @escaping @MainActor () async throws -> Void = { try await AdminService.shared.verifyAdminStatus() })
    var title: String { get }                       // .all → admin_panel_title; community → its name
    var menuEntries: [AdminPanelMenuEntry] { get }  // platform admin: All + every active membership; community admin: administeredCommunities;
                                                    // the current community is always included (opened from Admin → Communities)
    var pendingCount: Int? { get }                  // community scope: membership(for:)?.pendingCount
    func verifyAdminAccess() async                  // once per scope; .all → verifyPlatformAdmin with today's mapping (:60-77);
                                                    // .community → refresh if awaiting, then isAdmin(of:); allowed → loadStats() and resolveBroadcastTarget()
    func select(_ scope: AdminPanelScope) async     // no-op for the current scope; resets figures (hasLoadedStats false), bumps a
                                                    // generation counter, verifies and loads for the new scope
    func loadStats() async                          // fetchDashboardStats(communityId: scope.communityId); applied only while the generation is unchanged
}
struct AdminPanelView: View {
    init(scope: AdminPanelScope = .all, communityName: String? = nil, autoOpenReports: Bool = false)
    init(viewModel: @autoclosure @escaping () -> AdminPanelViewModel, autoOpenReports: Bool = false)   // previews
}
enum CommunityAdminAction: Equatable { case requestsToJoin, archive, restore, makePrivate, makePublic, openAdminPanel }
```
- `resolveBroadcastTarget()`: `.community(id)` → `(id, communityName ?? context.name(for: id))`; `.all` → the `isDefault` membership, else `fetchDefaultCommunityId()` plus `fetchCommunitySettings(id).name`; a failure leaves it nil (Task 7 hides the row while nil).
- `AdminPanelView`: `.navigationTitle(viewModel.title)` and `.communityTitleMenu(enabled: viewModel.menuEntries.count > 1) { ForEach(entries) { Button { Task { await viewModel.select(entry.scope) } } label: { entry is current ? Label(title, systemImage: "checkmark") : Text(title) } } }`. Figures for both scopes; the overlays get `communityId: viewModel.scope.communityId`. `.all` keeps today's quick actions and management rows exactly (broadcast, share link, Pending approvals, Communities, All members, platform Reports, `autoOpenReports`). `.community` shows: Share app link; Requests to join (with `NotificationBadge(count:)` when `pendingCount > 0`) → `PendingMembersView(target: .community(id, name: communityName))`; Members → `CommunityMembersView(target:)`; Reports → `CommunityReportsView`; Settings → `CommunitySettingsView(communityId:, onArchived:)`, whose callback receives the archive confirmation text (Task 4 fix) and sets `@State didArchiveCommunity = true`; the panel `dismiss()`es itself on its next `.onAppear`, so the confirmation must be shown where it survives that dismissal (for example handed up to the panel's presenter and shown with `.toast`). New rows use one private row builder; the existing rows are not rewritten. The not-admin state of a community scope is today's denied view.
- `MyProfileView`: the row shows when `AdminPanelScope.initial(isPlatformAdmin: profile.isAdmin, administered: CommunityContext.shared.administeredCommunities)` is non-nil and opens `AdminPanelView(scope:)` (spec §3.7: "`MyProfileView`'s Admin Panel row shows for platform admins or admins of any community"). The `.adminPanel` / `.adminReports` intent path (`:206-209`) stays `.all`.
- `MyCommunitiesView.activeMenu`: an admin row gains `admin_panel_open` first, which pushes `AdminPanelView(scope: .community(id), communityName: name)` (`@State adminPanelTarget: UUID?` + `.navigationDestination(item:)`).
- `CommunitiesAdminViewModel.actions(for:)` appends `.openAdminPanel` for every non-archived community; `perform` returns early for it as for `.requestsToJoin`; `CommunitiesAdminView` pushes `AdminPanelView(scope: .community(id), communityName:)` for it (platform admins reach a community they do not belong to).
- Known risk to report, not fix: Phase 1 gate finding 2 (a title menu does not appear when memberships load after the first render). The panel is opened after memberships have loaded, so it is not expected here; Task 11 captures the menu.

- [ ] **Step 1: Create the test group and file, then write the failing tests** (Review Focus 4):

```swift
// AdminPanelViewModelTests
func testInitialScope_PlatformAdminAllCommunityAdminFirstOtherwiseNil()
func testMenuEntries_PlatformAdminGetsAllPlusMemberships() async
func testMenuEntries_CommunityAdminGetsOnlyAdministered() async      // member-only rows are left out; no .all
func testAllScope_NonPlatformAdminIsDenied() async                   // verifyPlatformAdmin throws AppError.unauthorized → isAdmin false,
                                                                     // verificationErrorMessage nil; fetchDashboardStatsCalls empty
func testCommunityScope_NotAdminIsDeniedWithoutFetchingStats() async
func testCommunityScope_LoadsStatsForThatCommunity() async           // fetchDashboardStatsCalls == [A]; fulfilledCount from the stub
func testSelectScope_DropsStaleStats() async                         // A's call held by actionGate; select(.community(B)) completes;
                                                                     // release A → fulfilledCount is B's value
func testBroadcastTarget_AllScopeResolvesTheDefaultCommunity() async // isDefault membership → its id and name; without one →
                                                                     // fetchDefaultCommunityId + settings name
func testCommunitiesAdminActions_OpenAdminPanelOnlyForLiveCommunities()
// AppLaunchManagerTests
func testCommunityContext_AdministeredCommunitiesAreActiveOwnerAndAdminRows() async   // pending owner row excluded
```
For `testSelectScope_DropsStaleStats`, extend `StubAdminService.actionGate` to gate `fetchDashboardStats` as well (Task 1's stub; note it in the report).
- [ ] **Step 2: RED.** `RED`. Expected: "type 'AdminPanelScope' has no member 'initial'" (or "cannot find 'AdminPanelScope' in scope").
- [ ] **Step 3: Implement**; `#Preview`s: the panel in `.all` and in a community scope, both on `PreviewAdminService` and a preview context with two administered memberships (title menu enabled). The preview section of `AdminPanelView.swift` (today the unwrapped `#Preview { AdminPanelView() }` at `:356-358`) becomes one `#if DEBUG … #endif` block holding the existing preview and the two new ones; any preview touched in `MyCommunitiesView.swift`, `CommunitiesAdminView.swift` (already wrapped, `:319-334`) or the three overlays follows the same rule. Add the strings.
- [ ] **Step 4: GREEN.** `PREVIEWGUARD NaarsCars/Features/Admin/Views/AdminPanelView.swift NaarsCars/Features/Admin/Views/AdminFulfilledOverlay.swift NaarsCars/Features/Admin/Views/AdminSavingsOverlay.swift NaarsCars/Features/Admin/Views/AdminActiveRidesOverlay.swift NaarsCars/Features/Community/Views/MyCommunitiesView.swift NaarsCars/Features/Admin/Views/CommunitiesAdminView.swift` (no output); `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/AdminPanelViewModelTests -only-testing:NaarsCarsTests/AppLaunchManagerTests`. Expected: 10 new tests pass.
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P3-T6] Open the admin panel per community for community admins` with the files above and `project.pbxproj`.

Strings:
```
admin_panel_all_communities = "All communities"
admin_panel_members = "Members"
admin_panel_members_hint = "See members, change roles, remove or let people back in"
admin_panel_reports_community_hint = "Review reports about this community"
admin_panel_settings = "Settings"
admin_panel_settings_hint = "Name, description, who can join and who can invite"
admin_panel_open = "Admin panel"
admin_communities_open_panel = "Open admin panel"
```
(The Requests to join row reuses `community_action_requests`; the Reports row reuses `admin_reports_title`.)

Capture list (Task 11): Profile with the Admin Panel row as a community admin who is not a platform admin; the panel in `.all` and in a community scope, the title menu open; My communities' admin menu; Admin → Communities' row menu; light / dark / AX5. `#Preview`: `AdminPanelView` (exists; two variants added).

Live check: as the owner (platform admin), the panel opens in All communities with today's figures, which equal `admin_dashboard_stats()` (read-only); switching to Naar's Cars Seattle shows that community's figures, which equal `get_community_stats(<Seattle>)` (read-only, `execute_sql` under `set local role authenticated` with the owner's claims, rolled back).

---

### Task 7: Announcements to one community

**Model:** opus, high effort (it changes which RPC every announcement goes through, from `send_broadcast_notifications` to `send_community_broadcast`, removes the legacy `AdminService.sendBroadcast`, and changes who is notified: one community's unmuted members instead of the default community's; Supabase RPC call sites are a high-blast-radius seam, CLAUDE.md "Cross-Layer Synchronization Rules") · **Files:**
- Modify: `NaarsCars/Features/Admin/ViewModels/BroadcastViewModel.swift:13-88`
- Modify: `NaarsCars/Features/Admin/Views/BroadcastView.swift:11-16` (init), `:48-52` (footer), `:93-99` (error), `:131-140` (confirmation), `:150-154` (previews)
- Modify: `NaarsCars/Core/Services/AdminService.swift:18-23` (`BroadcastParams`, removed), `:93-101` (`createBroadcastParams`, removed), `:472-509` (legacy `sendBroadcast(title:message:pinToNotifications:)`, removed)
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift` (the announcement row: both scopes, through `broadcastTarget`)
- Create (Xcode MCP, test target): `NaarsCars/NaarsCarsTests/Features/Admin/BroadcastViewModelTests.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `AdminServiceProtocol.sendBroadcast(communityId:…)`, `AdminServiceError`, `StubAdminService`, `PreviewAdminService` (Task 1); `AdminPanelViewModel.broadcastTarget` (Task 6).
- Produces:

```swift
@MainActor final class BroadcastViewModel: ObservableObject {
    @Published var title = ""; @Published var message = ""; @Published var pinToNotifications = true
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?          // replaces `error: AppError?`
    @Published var successMessage: String?
    let communityId: UUID; let communityName: String
    init(communityId: UUID, communityName: String, adminService: any AdminServiceProtocol = AdminService.shared)
    func validate() -> Bool                         // both trimmed fields non-empty, else errorMessage = AppError.requiredFieldMissing's text
    func sendBroadcast() async                      // returns while isLoading; trimmed fields; success → today's haptic, success message and form reset;
                                                    // .broadcastDailyLimit → admin_broadcast_daily_limit(communityName); .notCommunityAdmin →
                                                    // community_pending_not_admin; other → community_error_generic; on any failure the form is kept
}
struct BroadcastView: View { init(communityId: UUID, communityName: String, viewModel: …defaulted…) }
```
- `BroadcastView`: footer `admin_broadcast_community_footer(name)` replaces `admin_announcement_footer`; the confirmation alert's message is `admin_broadcast_community_confirmation(name)`; the error section shows `errorMessage`. The panel's announcement row shows in both scopes while `broadcastTarget` is set and opens `BroadcastView(communityId: target.communityId, communityName: target.communityName)`. After this task nothing in the app calls `send_broadcast_notifications` (the installed build still does).

- [ ] **Step 1: Write the failing tests** (Review Focus 1 and 5):

```swift
func testSend_CallsCommunityBroadcastWithTrimmedFields() async     // stub sendBroadcastCalls == [(A, "Title", "Body", true)]
func testSend_DailyLimitShowsLocalizedMessageAndKeepsDraft() async // .broadcastDailyLimit → errorMessage == admin_broadcast_daily_limit(name);
                                                                   // title and message unchanged
func testSend_NotAdminShowsNotAdminMessage() async
func testSend_IgnoresSecondCallWhileSending() async
func testSend_SuccessClearsTheForm() async
```
- [ ] **Step 2: RED.** `RED`. Expected: "extra argument 'communityId' in call" (or "cannot find … in scope").
- [ ] **Step 3: Implement**; `grep -rn "send_broadcast_notifications\|createBroadcastParams\|sendBroadcast(title:" NaarsCars --include=*.swift` returns nothing; the `BroadcastView` previews (today the unwrapped `#Preview` at `:150-154`, now with a community and a daily-limit variant on `PreviewAdminService`) sit inside one `#if DEBUG … #endif`; add the strings.
- [ ] **Step 4: Self-check before GREEN** (write the result into the task report): the only announcement call left in the app is `AdminServiceProtocol.sendBroadcast(communityId:title:message:pinToNotifications:)`, whose body keys are `p_community_id, p_title, p_body, p_pinned` (SQL plan File B block 10's signature; `p_type` omitted, server default `'broadcast'`, the notification type the legacy path sent, so `should_notify_user` and the bell row's type are unchanged); `BroadcastView` cannot open without a `communityId` (no default-community fallback in the view: the panel passes `broadcastTarget`); the recipients sentence in `admin_broadcast_community_footer` matches the block's member loop (active, unbanned, not muted, not the sender).
- [ ] **Step 5: GREEN.** `PREVIEWGUARD NaarsCars/Features/Admin/Views/BroadcastView.swift NaarsCars/Features/Admin/Views/AdminPanelView.swift` (no output); `BUILD`; `RELEASE` (the first Release build of the phase: every preview added in Tasks 1-7 is now in place); `TEST` with `-only-testing:NaarsCarsTests/BroadcastViewModelTests -only-testing:NaarsCarsTests/AdminServiceTests`. Expected: 5 new tests pass; `RELEASE` exit 0.
- [ ] **Step 6: Commit** `[P3-T7] Send announcements to one community under the daily limit` with the files above and `project.pbxproj`.

Strings:
```
admin_broadcast_community_footer = "Sent to the members of %@ who haven't muted it. A community can send 3 announcements a day."
admin_broadcast_community_confirmation = "Send this announcement to the members of %@?"
admin_broadcast_daily_limit = "%@ has already sent 3 announcements today. Try again tomorrow."
```
Sources: recipients and mute `send_community_broadcast` (SQL plan File B block 10, the member loop); the cap, D14.

Capture list (Task 11): the screen in a community, the daily-limit error; light / dark / AX5. `#Preview`: `BroadcastView` (exists; now with a community, plus a variant whose preview service throws the daily limit).

Live check **(writes)**: Task 11 O3.

---

### Task 8: Routing — community reports and removal

**Model:** opus (Notification Routing, fragile system 4; `NavigationCoordinator`, `NavigationIntent`, `DeepLinkParser` are high-blast seams) · **Files:**
- Modify: `NaarsCars/Core/Utilities/DeepLinkParser.swift:10-28` (cases), `:112-113` (`content_reported`), `:141-143` (add `account_restricted` beside `user_rejected`)
- Modify: `NaarsCars/App/NavigationIntent.swift:24-46`
- Modify: `NaarsCars/App/NavigationCoordinator.swift:13-27` (`NotificationIntent`), `:165-230` (`applyDeepLink`), `:234-300` (`isSameDeepLink`), `:317-360` (`applyNotificationIntent`), `:368-389` (guest gating)
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift:13-19` (init), `:135-136`, `:161-167`
- Modify: `NaarsCars/App/AppDelegate.swift:381-384`
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:35-40` (state), `:159-163` (replay list), `:200-208` (destination), `:719-756` (`applyProfileIntent`)
- Create (normal tools): `Docs/qa/push-fixtures/content_reported_community_admin.apns`, `content_reported_platform_admin.apns`, `account_restricted_community.apns`
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/DeepLinkParserTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift`

**Interfaces:**
- Consumes: `CommunityReportsView` (Task 5); `MyCommunitiesView` and `NavigationIntent.myCommunities` (Phase 2).
- Produces: `DeepLink.communityReports(communityId: UUID)` and `DeepLink.myCommunities`; `NavigationIntent.communityReports(UUID)` (`targetTab == .profile`); `NotificationIntent.openCommunityReports(communityId: UUID)` and `NotificationIntent.openMyCommunities`; `NotificationNavigationRouter.init(authService: AuthService = .shared, isPlatformAdmin: @escaping @MainActor () -> Bool = { AuthService.shared.currentProfile?.isAdmin == true })`.
- Parser: `content_reported` with a well-formed `community_id` → `.communityReports(communityId:)`, else `.adminReports` (spec §3.7 "Reports"; the payload decides the audience, SQL plan D-S6); `account_restricted` → `.myCommunities` (spec §2.4 removal row: "My communities or onboarding"; a session that just lost its last community is moved to onboarding by the membership refresh every such push triggers, `PushNotificationService.swift:882`).
- Router: `.contentReported` → `.openCommunityReports(communityId:)` when `!isPlatformAdmin()` and `notification.communityId != nil`, else `.openAdminReports` (a platform admin's bell row carries a derived community too); `.accountRestricted` → `.openMyCommunities`.
- Coordinator: `applyDeepLink` `.communityReports(id)` → `pendingIntent = .communityReports(id)`, `.myCommunities` → `.myCommunities`; `isSameDeepLink` compares `.communityReports` by id and `.myCommunities` with `.myCommunities`; `applyNotificationIntent` sets the intent and `selectedTab = .profile` for both; `.communityReports` joins `intentIsAdminOnly` and the admin arm of `intentRequiresAuth` (guests drop it). `AppDelegate`'s group (`:381-384`) gains `.communityReports, .myCommunities`. Any other exhaustive switch the compiler names gets the Profile-tab behaviour.
- `MyProfileView`: `@State private var communityReportsTarget: UUID?` with `.navigationDestination(item:) { CommunityReportsView(communityId: $0, communityName: CommunityContext.shared.name(for: $0)) }`; `applyProfileIntent` handles `.communityReports(id)` and clears the intent; the `.onAppear` replay list gains `.communityReports`.
- Fixtures (JSON, `aps` + `type` + ids; placeholders `<COMMUNITY_ID>`, `<POST_ID>`, `<REPORT_ID>` filled in Task 11): the community-admin fixture carries `community_id`, `town_hall_post_id`, `report_id`, `target_type`; the platform-admin one the same without `community_id`; `account_restricted_community.apns` carries `community_id`.

- [ ] **Step 1: Write the failing tests** (spec §4 Phase 3: "routing tests for `content_reported` with `community_id`"):

```swift
// DeepLinkParserTests
func testParse_ContentReportedWithCommunityIdRoutesToCommunityReports()
func testParse_ContentReportedWithoutCommunityIdStaysAdminReports()
func testParse_ContentReportedWithMalformedCommunityIdStaysAdminReports()
func testParse_AccountRestrictedRoutesToMyCommunities()
// NavigationCoordinatorRoutingTests
func testApplyPushDeepLink_CommunityReportsSetsIntentForProfileTab()
func testDeferredOpenCommunityReports_SelectsProfileTab()
func testRouter_ContentReportedRowForCommunityAdminOpensCommunityReports()   // NotificationNavigationRouter(isPlatformAdmin: { false })
func testRouter_ContentReportedRowForPlatformAdminOpensAdminReports()        // isPlatformAdmin true, row with communityId
func testRouter_ContentReportedRowWithoutCommunityOpensAdminReports()
func testRouter_AccountRestrictedRowOpensMyCommunities()
func testCommunityReportsIsAdminOnlyForGuests()
```
- [ ] **Step 2: RED.** `RED`. Expected: "type 'DeepLink' has no member 'communityReports'".
- [ ] **Step 3: Implement**; write the three fixtures.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/DeepLinkParserTests -only-testing:NaarsCarsTests/NavigationCoordinatorRoutingTests -only-testing:NaarsCarsTests/NavigationCoordinatorTests -only-testing:NaarsCarsTests/WebhookPayloadDecodingTests -only-testing:NaarsCarsTests/AppDelegateNotificationHandlingTests`. Expected: all pass (11 new).
- [ ] **Step 5: FULL.**
- [ ] **Step 6: Commit** `[P3-T8] Route content_reported to the community's reports and account_restricted to My communities` with the files above.

Strings: none. Live check: Task 11 O2 (the three fixtures).

---

### Task 9: Legal and disclosure text for community moderation

**Model:** opus, high effort (App Store rules 6 and 8: what the terms, privacy policy and in-app text say community admins can do must match the server) · **Files:**
- Modify: `Legal/TERMS_OF_SERVICE.md` §5 (the moderation sentence, `:46` in the `[P2-fix]` text), §6.2 (`:54-60`), §6.3 (`:62-64`), §10 (`:117-121`), both dates
- Modify: `Legal/PRIVACY_POLICY.md` §5 (`:85`), §6.1 (`:101`, `:103`, `:105`), both dates
- Modify: `Legal/FAQ.md:35`; review `Legal/PRIVACY-DISCLOSURES.md` against the same facts
- Modify: `NaarsCars/Features/Profile/Views/CommunityGuidelinesView.swift:100` (section 7 reads the new body key)
- Modify: `NaarsCars/Features/TownHall/Views/ReportContentSheet.swift:11-21` (`ReportContext.reachesCommunityAdmins`), `:125-132` (second footer line)
- Modify: `Docs/AppStore/2026-10-multi-community-review-notes.md` (a Phase 3 section and release notes)
- Modify: `NaarsCars/NaarsCarsTests/Features/TownHall/ReportContentViewModelTests.swift` (one test)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Interfaces:** content fixed by spec §2.1 rule 10, §3.5 INV-P2, §4 Phase 3, and the SQL plan; wording is the implementer's within it. Start from the committed text (Prerequisite 1: after the `[P2-fix]` pass the terms say community admins cannot hide content, which Phase 3 makes untrue).
- Terms: §5 — community owners and admins may hide reported content in their community; only the operator suspends accounts. §6.2 adds: review reports about content and members in their community without seeing who reported, and hide or restore reported posts, comments, rides and favors; change the community's name, description, who may join and who may invite; make members admins, hand over ownership (owners); archive the community (owners). §6.3: they may not see who reported, may not act on reports about themselves or about the community's other owners and admins (those go to the operator), may not restore content the operator hid or that was hidden automatically after several reports, may not reopen a report the operator has handled, may not hide messages, may not see email or phone, may not delete accounts. §10: moderation is shared — community admins handle reports about content in their community; platform moderators review every report whatever a community admin decided, see who reported, can act in any community, and their decisions stand.
- Privacy: §6.1 — owners and admins also see reports about content and members of their community (what was reported, the reason, and any note the reporter wrote) but never who reported; the Reports bullet says the same; a removal note is visible to the removed person and the community's admins. §5 "Run communities" gains "including letting community admins handle reports about their community".
- FAQ line 35: "Community admins review reports about content in their community and can hide it; they never see who reported. Platform moderators review every report, do see who reported, and their decisions stand."
- `ReportContext.reachesCommunityAdmins: Bool` — true for `.post`, `.comment`, `.ride`, `.favor`, `.user`, `.review`; false for `.community` (`report_community` reaches platform admins only). When true, the sheet adds `Text("report_note_visible_to_community_admins".localized)` under the existing privacy note.
- Guidelines section 7 reads `guidelines_7_body_moderation` (new key; the old key stays in the catalog, unreferenced).
- Review notes: community admins can hide reported content in their community and never see reporters; reports about owners and admins and every message report go to platform moderators; every report stays in the platform moderators' queue until they review it, whatever a community admin decided, and a community admin cannot undo a platform moderator's decision or the automatic hide; platform moderators see every report and can archive any community; a reviewer account that owns a test community can see its Reports list. Release notes: community owners and admins should update (an older build opens the platform reports screen and shows an error on a report notice); platform admins can send 3 announcements a day per community.
- Both legal documents' dates read `<RELEASE DATE>` for the owner. **Owner step:** mirror both documents to the Notion pages the app opens (`Core/Utilities/Constants.swift:227-228`) before submission.

- [ ] **Step 1: Write the failing test** in `ReportContentViewModelTests`:

```swift
func testReachesCommunityAdmins_AllButCommunityReports()   // .post/.comment/.ride/.favor/.user/.review true; .community false
```
- [ ] **Step 2: RED.** `RED`. Expected: "value of type 'ReportContext' has no member 'reachesCommunityAdmins'".
- [ ] **Step 3: Edit** the legal files, the guideline call site, the sheet; write the review and release notes; add the strings.
- [ ] **Step 4: GREEN.** `BUILD`; `TEST` with `-only-testing:NaarsCarsTests/ReportContentViewModelTests`. Expected: all pass.
- [ ] **Step 5: Verify** `grep -n "cannot remove or hide other people\|may not remove or hide other people" Legal/*.md` returns nothing, and list in the task report, beside each who-sees-what sentence, its source: recipients and no reporter (SQL plan File A block 2), the list's contents and exclusions (block 3), hide / restore / dismiss, the platform-wins rules and the author's notice (block 4, D-S7), settings (`update_community`, `20261017_0005:676-726`), roles and transfer (`:1591-1705`), removal note readers (`20261017_0002:251-256`, `20261017_0005:1923`), archive (`:774-806`). A sentence with no source is reworded or removed.
- [ ] **Step 6: Commit** `[P3-T9] Update the terms, privacy policy, FAQ and guidelines for community moderation` with the files above.

Strings:
```
guidelines_7_body_moderation = "Anyone can create a community. Its owners and admins approve members, remove people, and handle reports about content in it: they can hide a reported post, comment or request, or restore what they hid, and they never see who reported. They see your name, photo, car, your answers when you ask to join and who invited you, never your email or phone number. A community's name, description and public content follow the same rules as any post. Platform moderators review every report in any community, including private ones, and can close a community that breaks these guidelines."
report_note_visible_to_community_admins = "The community's admins see the report and what you write here, but not your name."
```

Capture list (Task 11): `ReportContentSheet` for `.post` (two footer lines) and `.community` (one); `CommunityGuidelinesView` section 7 at AX5. `#Preview`: both exist.

---

### Task 10: Documentation for Phase 3

**Model:** sonnet · **Files:**
- Modify: `CLAUDE.md` — Current State (a Phase 3 paragraph: what shipped, what was verified, the two coordinator triggers); Fragile system 4 and Notification Rules (`content_reported` has two audiences and two routes: with `community_id` → `.communityReports(id)` for a non-platform admin, without → `.adminReports`; `account_restricted` → `.myCommunities`); Canonical Entry Points (moderate a community report → `AdminService.moderateCommunityContent`, never `admin_moderate_content` from a community screen; announce to a community → `AdminService.sendBroadcast(communityId:…)`; change roles, remove, transfer → `CommunityAdminServiceProtocol`); the database contract under Audit Notes (INV-P2 as implemented: community-admin rows have no source user, staff matters skip community admins, `get_community_reports` / `moderate_community_content`, `is_community_staff` is internal, the posts DELETE policy; platform moderation wins: a community admin's decision is written to `reports.community_status` / `community_reviewed_at` and never to `status` / `reviewed_*`, so every report stays in the platform queue, and a community admin cannot restore a platform or automatic hide, hide hidden content, or hide or dismiss a report a platform admin reviewed; the broadcast cap now applies to platform admins and counts only announcements by platform admins and community staff; a member can still insert a row typed `announcement` (follow-up, SQL plan D-S8); the `admin_*` statistics functions are wrappers over `get_community_stats*` with a null community); File conventions (`AdminServiceProtocol`, `PreviewAdminService`, `CommunityReport` has no reporter field by design; every `#Preview` that uses a DEBUG-only preview service sits inside `#if DEBUG`); State Management rule 2 (three more `ObservableObject` screen ViewModels); Testing Expectations (a Moderation row: no reporter field, action tables, one RPC per tap); Audit Notes (Phase 3 paragraph, follow-ups from Task 11, audit date).
- Modify: `AGENTS.md`; `.cursor/rules/05-navigation-contract.mdc` (`communityReports`, `myCommunities` from `account_restricted`).
- Modify: `SECURITY.md` §4 (community admins see reports without the reporter and hide content in their community; staff matters and message reports stay with platform admins; platform decisions and the auto-hide cannot be undone by a community admin, and community decisions never leave the platform queue; SEC-ADMIN-001 covers platform operations only), §5.3 (3 announcements a day per community, platform admins included), §2 (the `town_hall_posts` DELETE policy).
- Modify: `Docs/design-system/README.md` (the admin panel's scope title menu, report cards without a reporter line, member role chips; no new tokens).

- [ ] **Step 1: Edit** each section with the Phase 3 facts (replace, do not append history).
- [ ] **Step 2: Verify** `grep -n "platform admins are exempt" CLAUDE.md SECURITY.md AGENTS.md` returns nothing stale and `grep -rn "send_broadcast_notifications" CLAUDE.md` names it only as the installed build's wrapper.
- [ ] **Step 3: Commit** `[P3-T10] Document the Phase 3 community admin client`.

---

### Task 11: Phase gate

**Model:** opus · **Files:** a new `Docs/qa/2026-10-18-multi-community-phase3-gate.md` (report only; no code). Uses `Docs/qa/push-fixtures/*.apns`, `build/`.

**Steps the agent runs without the owner:**

- [ ] **Step 1: Preconditions** (Supabase MCP, read only). `select proname from pg_proc where pronamespace = 'public'::regnamespace and proname in ('is_community_staff','get_community_reports','moderate_community_content','can_read_community_stats','get_community_stats','get_community_stats_fulfilled','get_community_stats_savings','get_community_stats_active_requests')` returns 8 rows; `select qual from pg_policies where tablename = 'town_hall_posts' and cmd = 'DELETE'` mentions `my_admin_community_ids`; `select column_name from information_schema.columns where table_schema = 'public' and table_name = 'reports' and column_name in ('community_status','community_reviewed_at')` returns 2 rows; `send_community_broadcast`'s `md5(prosrc)` equals the deployed value recorded in `20261018_0002`'s header; both migration headers read APPLIED with probe outcomes (including the owner's `posts_delete_policy` run). If anything is missing, run every step that does not need it and report the gap.
- [ ] **Step 2: Full unit suite, signed out**, one headless simulator, `-resultBundlePath build/P3-gate.xcresult`. Expected: exit 0, 0 failures, skips limited to the session-gated classes; record the counts against the Phase 2 gate (552 cases, 519 passed, 33 skipped) — Phase 3 adds 83 cases (Tasks 1-9: 16, 10, 13, 8, 9, 10, 5, 11, 1) and no new skip.
- [ ] **Step 2b: Release build.** `RELEASE` (with `<n>` = `gate`) and `PREVIEWGUARD` over every view file the phase touched (`git diff --name-only <phase base>..HEAD -- 'NaarsCars/**/*View.swift' 'NaarsCars/**/*Sheet.swift'`). Expected: exit 0, no output. A failure here is a blocker: the App Store archive is a Release build.
- [ ] **Step 3: Previews (Lane A).** Open the worktree project; `RenderPreview` every `#Preview` named in Tasks 3-9 with `{"Color Scheme": "Light Appearance"}`, `{"Color Scheme": "Dark Appearance"}`, `{"Dynamic Type": "AX 5"}`; retry once on a first-render timeout. Inspect each: clipped or overlapping text, dark contrast, the 60-character member name, buttons not clipped at AX5, no reporter line on any report card. Quit Xcode.
- [ ] **Step 4: Write the report** with the PR Impact Summary: (1) community owners and admins receive `content_reported` for their community, with no reporter, and handle it in a Reports list (hide, restore, dismiss); reports about owners and admins, message reports and community reports stay with platform admins; (2) `content_reported` with a `community_id` opens that community's Reports for a non-platform admin, and `account_restricted` opens My communities; (3) the Profile's Admin Panel row shows for admins of any community and the panel has a community scope with a title menu; (4) platform admins are held to 3 announcements a day per community, on every build, and a member's announcement-typed row no longer counts; (4b) a community admin's decision never leaves the platform queue, and platform decisions and the auto-hide cannot be undone from a community; (5) the admin figures and announcements call the community RPCs (every community for the platform panel's All scope); (6) leaving as the last owner offers to choose a new owner. High-blast files touched: `NavigationCoordinator`, `NavigationIntent`, `DeepLinkParser`, `NotificationNavigationRouter`, `AppDelegate`, `CommunityContext`, `Constants`, `AdminService` (protocol added); for each, what would break if a consumer were missed. App Store checklist (spec §5): reporting and moderation extended (community admins moderate their community; every report still reaches platform admins); notification behaviour altered (a second `content_reported` audience; the broadcast cap for platform admins); data handling: community admins now see reports' content and reporters' notes, disclosed in the privacy policy; no permission, SDK, entitlement or privacy-manifest change.

**Owner-present steps (each needs the owner signed in on the simulator through the built-in panel, a second account, or a write to production; writes only with the owner's go-ahead):**

- [ ] **O1. Captures** (light, dark, AX5; `simctl ui … appearance`, `content_size accessibility-extra-extra-extra-large`, reset afterwards): every capture list in Tasks 3-9, signed in as the owner (platform admin) and, for the Profile row and the panel's community scope, as a second account that owns a test community and is not a platform admin. Compare the one-membership Requests and Community tabs with the Phase 2 captures: unchanged.
- [ ] **O2. Push fixtures** (`<COMMUNITY_ID>` = the test community, `<POST_ID>` / `<REPORT_ID>` from O3): `content_reported_community_admin.apns` as the second account → Profile tab, that community's Reports; `content_reported_platform_admin.apns` as the owner → Admin → Reports; `account_restricted_community.apns` → My communities.
- [ ] **O3. Live matrix (writes),** in this order, recording each outcome: create "P3 Live Check" as the second account (or reuse "P2 Live Check" restored); a third account joins it; the third account posts and the owner's account reports the post → the second account's bell row has no reporter and its push opens Reports (O2); hide with a reason → the post leaves the feed for others and its author gets "Your content was hidden" with the reason, and Admin → Reports as the owner still lists the report as pending; restore; the owner hides a second reported post of the third account from Admin → Reports → in the second account's community Reports that row reads "Platform moderators handled this report" with no Hide, Restore or Dismiss (then the owner restores it from Admin → Reports); a person report about the third account → dismiss; make the third account an admin, then a member; hand ownership to the third account and back; remove the third account with a note → they get "Removed from P3 Live Check" and `select removal_reason from community_members where user_id = <third> and community_id = <P3>` shows the note (read-only); let them back in; settings: rename, toggle approval and member invites; announcements: three from the second account, the fourth refused with the daily-limit message (they go only to the test community's members); Admin → Reports as the owner: dismiss the "P2 Live Check" community report (SQL plan D-S1). Clean-up: archive "P3 Live Check" from its settings, revoke its codes, the throwaway accounts delete themselves from Profile (or are left for the owner).
- [ ] **O4. Installed build** (optional, an App Store build on a device): as a platform admin, Admin → Stats shows the same figures as the runbook's step 1 snapshot.
- [ ] **O5. Shut down** (`xcrun simctl shutdown booted`); push the branch and update the draft PR description with the Impact Summary (owner).

---

## New files

| Path (Xcode navigator path) | Target | Task | How |
|---|---|---|---|
| `NaarsCars/Core/Protocols/AdminServiceProtocol.swift` | NaarsCars | 1 | Xcode MCP |
| `NaarsCars/Core/Models/CommunityModerationPayloads.swift` | NaarsCars | 1 | Xcode MCP |
| `NaarsCars/Core/Services/PreviewAdminService.swift` (whole file `#if DEBUG`) | NaarsCars | 1 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Core/Services/AdminServiceTests.swift` | NaarsCarsTests | 1 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/CommunityMembersViewModel.swift` | NaarsCars | 3 | Xcode MCP |
| `NaarsCars/Features/Community/Views/CommunityMembersView.swift`, `CommunityMemberDetailView.swift` | NaarsCars | 3 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/CommunityMembersViewModelTests.swift` | NaarsCarsTests | 3 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/CommunitySettingsViewModel.swift`, `Views/CommunitySettingsView.swift` | NaarsCars | 4 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/CommunitySettingsViewModelTests.swift` | NaarsCarsTests | 4 | Xcode MCP |
| `NaarsCars/Features/Community/ViewModels/CommunityReportsViewModel.swift`, `Views/CommunityReportsView.swift` | NaarsCars | 5 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Community/CommunityReportsViewModelTests.swift` | NaarsCarsTests | 5 | Xcode MCP |
| group `NaarsCars/NaarsCarsTests/Features/Admin` | NaarsCarsTests | 6 | `XcodeMakeDir` |
| `NaarsCars/NaarsCarsTests/Features/Admin/AdminPanelViewModelTests.swift` | NaarsCarsTests | 6 | Xcode MCP |
| `NaarsCars/NaarsCarsTests/Features/Admin/BroadcastViewModelTests.swift` | NaarsCarsTests | 7 | Xcode MCP |
| `Docs/qa/push-fixtures/content_reported_community_admin.apns`, `content_reported_platform_admin.apns`, `account_restricted_community.apns` | none | 8 | normal tools |
| `Docs/qa/2026-10-18-multi-community-phase3-gate.md` | none | 11 | normal tools |

## Self-review notes

- **Spec §4 Phase 3 coverage.** Server items: the companion SQL plan (recipients under INV-P2, `get_community_reports`, `moderate_community_content`, `get_community_stats` + breakdowns + `admin_*` wrappers, the DELETE policy, the platform-admin broadcast cap; the two producers are already live). Client: `AdminPanelView(communityId:)` under My communities for owners and admins (6), `CommunityMembersView` + member detail with remove, re-admit, promote, transfer (3), `CommunitySettingsView` with join policy, who can invite, archive (4), `CommunityReportsView` with the `content_reported` route (5, 8), broadcast to a community (7), stats (1, 6). Tests: stubbed `AdminServiceTests` for every method that takes `communityId` (1) — the `CommunityService` admin wrappers that take one are in `CommunityServiceTests` (2) — and routing tests for `content_reported` with `community_id` (8). Spec §3.7: `AdminService` methods take `communityId` (1), the title menu with "All" for platform admins (6), the Profile row for admins of any community (6). Spec §2.4: the removal tap → My communities (8). The probe additions are the SQL plan's `community_moderation` and `posts_delete_policy`. "What old clients see" and the release-note coordination: Task 9's release notes and the SQL plan's headers.
- **Deliberate departures the owner can veto.** (1) The member detail is `CommunityMemberDetailView`, not the spec's `MemberDetailView(communityId:)`: that name is taken by the platform admin's detail (`Features/Admin/Views/MemberDetailView.swift:12`). (2) No co-owner action and no time-zone field (`set_member_role('owner')` and `update_community(p_timezone)` exist; no screen asks for them). (3) `set_primary_community` still has no screen (Phase 2 self-review note 6 deferred it here; the spec names no screen for it, and it only matters for the installed build's posts). (4) No "delete post" for admins in the app, although the DELETE policy now allows it: today's app has no admin delete for platform admins either (`TownHallService.swift:230-258` checks authorship), and hiding is reversible. (5) Two coordinator triggers (`removedMember`, `archivedCommunity`) beside spec §3.7's two and Phase 2's three, so the merged Requests feed drops requests the action removed. (6) The legacy statistics wrappers answer "every community" (SQL plan D-S3). (7) The report sheet's second footer sentence (Task 9) tells reporters that community admins read their note; the spec's in-app sentence covers only the reporter's identity. (8) Admin → Reports learns community reports through the SQL plan's optional blocks 6-8 (D-S1); no client change is needed here because the `[P2-fix]` client already reads `targetType == "community"`. (9) The community list's actions follow the server's platform-wins rules (SQL plan D-S7) through `platformHandled` / `canRestore`, not the platform screen's table, and community decisions are shown from `community_status` while the platform queue is unchanged; the installed and Phase 3 Admin → Reports label a pending report a community admin hid "Auto-hidden" (follow-up in D-S7).
- **Tests.** Spec-named: `AdminServiceTests` (1), routing for `content_reported` with and without `community_id` (8). CLAUDE.md-mandated: the RPC fixture gate (1, 2), routing table (8), Auth zero-membership path through archive (4). Logic the spec states, pinned: the permission tables mirroring the server (3, 5, 6), no reporter field (1), the last-owner transfer offer (4). Review Focus: 1 (3, 4, 5, 7), 2 (3, 5), 3 (3, 5), 4 (6), 5 (1, 7), 6 (5). Tasks 9 and 10 add one test and none.
- **Release safety.** Every `#Preview` that uses `PreviewAdminService`, `PreviewCommunityService` or `debugSetMemberships` is inside `#if DEBUG` (Tasks 3-7, `PREVIEWGUARD`), and `RELEASE` runs in Tasks 7 and 11, because CI and Lane B build Debug only.
- **Localization.** No user-facing raw server value: the report-type chip uses the existing six-locale `messaging_report_*` keys (Task 5), refusals use `CommunityRPCError.localizedMessage` or a task key.
- **Type and name consistency.** `AdminServiceProtocol`, `CommunityReport` (`canRestore`, `platformHandled`, `reportTypeLabel`, `applying(_:)`), `CommunityReportsPayload`, `CommunityModerationAction`, `AdminServiceError.broadcastDailyLimit` / `.notCommunityAdmin`, `RemovalResult`, `CommunitySettings`, `CommunitySettingsChange`, `CommunityServiceError.communityNotFound`, `CommunityMemberAction`, `CommunityMemberActions.available(for:callerId:callerRole:isPlatformAdmin:)`, `CommunityMembersTarget`, `CommunityReportFilter`, `CommunityReportActions.available(for:)`, `AdminPanelScope.initial(isPlatformAdmin:administered:)`, `BroadcastTarget`, `CommunityContext.administeredCommunities` / `isAdminOfAnyCommunity`, `CommunityAdminAction.openAdminPanel`, `DeepLink.communityReports(communityId:)` / `.myCommunities`, `NavigationIntent.communityReports`, `NotificationIntent.openCommunityReports(communityId:)` / `.openMyCommunities`, `PreviewAdminService`, `StubAdminService` are spelled the same in every task that uses them.
