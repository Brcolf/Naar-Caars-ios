# Multi-community Phase 3: verification gate and PR Impact Summary

Date: 2026-10-18. Branch `claude/naarscars-multi-community-roadmap-f08594`, Swift state at `d25e580` ([P3-T10]); the phase runs from `a600f5c` ([P2-gate]) to that commit. Plan: `Docs/superpowers/plans/2026-10-18-multi-community-phase3.md`, Task 11. This file records the gate steps that need no owner, what they showed, and the owner steps still to run. The **PR Impact Summary** below is the text the draft PR must carry, together with the Phase 1 and Phase 2 summaries (`2026-10-18-multi-community-phase1-gate.md`, `2026-10-18-multi-community-phase2-gate.md`).

## What was run

| Plan step | Result |
|---|---|
| 1. Preconditions (Supabase MCP, read only) | **All present.** The 8 functions exist (`is_community_staff`, `get_community_reports`, `moderate_community_content`, `can_read_community_stats`, `get_community_stats`, `get_community_stats_fulfilled`, `get_community_stats_savings`, `get_community_stats_active_requests`). The `town_hall_posts` DELETE policy ("Users or admins can delete posts") mentions `my_admin_community_ids`. `reports.community_status` and `reports.community_reviewed_at` exist. `md5(prosrc)` of `send_community_broadcast` is `b49920cb7b9aacbb0a5b0bc9cf85f864`, the deployed value in `20261018_0002`'s header. Both migration headers read APPLIED with probe outcomes, including the owner's `posts_delete_policy` run in the SQL editor. The orchestrator's brief said the Phase 3 SQL was not applied yet; it was applied before this gate ran, so **there is no precondition gap** and the live matrix (O3) can run. |
| 2. Full unit suite, signed out | Simulator "iPhone 16 Tests" (iOS 26.5, never signed in), one destination, no parallel clones, 60/120 s allowances. **641 cases: 608 passed, 0 failed, 33 skipped.** `xcodebuild` exit 0. The skips are exactly the Phase 2 set (`TownHallServiceTests` 5, `NotificationsListViewModelTests` 5, `RideServiceTests` 4, `NotificationServiceTests` 4, `LeaderboardServiceTests` 4, `FavorServiceTests` 3, `PushNotificationServiceTests` 2, `TownHallFeedViewModelTests` 2, one each in `MessageServiceTests`, `MyProfileViewModelTests`, `ReviewPromptProviderTests`, `CompletionPromptProviderTests`); no new skip. Phase 2 gate: 552 cases, 519 passed, 33 skipped, so this branch adds 89 cases. The plan expected 83; the diff since `a600f5c` adds 88 `func test` methods (the review fix commits added tests beyond the plan's count), and the remaining case most likely comes from the `[P2-fix]` commits between the Phase 2 gate run (`c3924d1`) and `a600f5c`. Bundle: `build/P3-gate.xcresult`; log `build/P3-gate-full.log`. |
| 2b. Release build | `RELEASE` with `<n>` = `gate`: **exit 0, no `error:` line**, and no warning in a Phase 3 file (log `build/P3-gate-release.log`). It was built into the existing `build/DerivedData` with `-configuration Release`, as Task 7 did, not into a second `build/DerivedData-Release` folder (one DerivedData per worktree on this Mac). |
| 2b. `PREVIEWGUARD` | Run over every view, sheet and overlay file changed since `a600f5c` (14 files). Two lines: `CommunityGuidelinesView.swift:122` and `MyProfileView.swift:792`. Both are unwrapped previews that existed before Phase 3 (no `#Preview` line in the phase diff) and name no DEBUG-only type (`CommunityGuidelinesView()`, `MyProfileView()`), so they are allowed in a Release build. The rule the guard approximates (no preview that names a DEBUG-only type outside `#if DEBUG`) holds, and the Release build confirms it. Every preview added in Tasks 3-7 sits inside `#if DEBUG`. |
| 3. Previews (Lane A, Xcode MCP `RenderPreview` on the worktree tab `windowtab2`) | 22 previews in 8 files, each in light, dark and AX 5 (66 renders plus one retry). PNGs and side-by-side strips are in `build/p3-gate/previews/` (gitignored). Findings below. One dark render of `CommunityGuidelinesView` failed with "NaarsCars may have crashed" (the preview host); the retry rendered. Xcode was left open: the orchestrator uses the worktree tab. |

### Previews rendered

`CommunityMembersView` (members as owner, removed list, not admin, transfer banner); `CommunityMemberDetailView` (owner looking at a member, admin looking at an admin, removed member, remove sheet); `CommunitySettingsView` (owner, admin read-only, default community); `CommunityReportsView` (all reports, empty, not admin, hide sheet); `AdminPanelView` (all communities, one community); `BroadcastView` (in a community, daily limit); `ReportContentSheet` (post, community); `CommunityGuidelinesView`.

Not rendered: `AdminPanelView`'s first, unnamed preview (`AdminPanelView()` on the live services; Task 6 named only the two variants it added). `MyCommunitiesView` and `CommunitiesAdminView` were touched in Tasks 4 and 6, but Tasks 3-9 name no `#Preview` for them; their changes (the admin menu, "choose a new owner", the row menu) appear only in menus and alerts, and those are in the O1 capture list.

Light and dark: nothing clipped or overlapping, contrast readable in dark everywhere. Role chips (`Owner`, `Admin`), report-type chips (`Spam`, `Harassment`, `Other`), the report-count and Requests to join counts (`NotificationBadge`) and the Hide / Dismiss / Restore capsules read well in both. Every list screen is on the background token.

**Reporter privacy (INV-P2): no report card shows a reporter.** A card shows the target type, a type chip, the content preview, "Posted by" with the author, the reporter's own note under "Reporter's note", the age and the actions. The scope note says reporters are not shown. `CommunityReport` has no reporter field (`CommunityModerationPayloads.swift:13-15`).

**Server rules on screen.** An admin looking at another admin gets no actions; the removed member gets only Let back in; the admin read-only settings show "Only the owner can change these settings." with the toggles disabled; the default community has no Archive row; the hide sheet keeps Hide disabled until a reason is typed; the daily-limit preview keeps the typed announcement and shows "Ballard Neighbors has already sent 3 announcements today. Try again tomorrow."; `ReportContentSheet` shows two footer lines for a post and one for a community.

**60-character member name.** In the members list it wraps to two lines and then truncates with an ellipsis ("Maximiliana Alexandrina / Featherstonehaugh-Wolfeschl…") at the default size. Nothing overlaps. The row is not clipped at AX 5, but that sample is below the fold there.

### Findings from the renders

1. **Admin Panel stat tiles at AX 5 break inside words and numbers** ("Ful- / fille / d", "$1, / 23 / 4", "Savi / ngs", "Ac- / tive"), and the Quick Actions rows hyphenate ("Send / An-…"). The three `StatCard`s sit in a fixed `HStack` that predates Phase 3 (`AdminPanelView.swift:163`, `StatCard` at `:482`); Phase 3 made the panel reachable to community admins, so more people now see it. At accessibility sizes the tiles should stack vertically (`ViewThatFits` or a `dynamicTypeSize` switch). Fix before release.
2. **Settings, admin read-only: the Name and Description fields look editable.** They are `.disabled` (`CommunitySettingsView.swift:97, 110`) but keep the white field and black text, so only the dimmed toggles and the footer show that nothing can change. Use a secondary text colour or a plain read-only label when `canEdit` is false.
3. **Single-line fields truncate at AX 5**: the settings Name field ("Ballard Neigh…") and the announcement Title ("Street fair on…"). This is system `TextField` behaviour; acceptable, listed for completeness.
4. **The announcement button still reads "Send Broadcast"** under the title "Send Announcement", and the pin footer says "users' notification feeds". Both strings predate Phase 3; Task 7 left them alone. Copy follow-up.
5. **The daily-limit and other send errors appear as red text in a card**, not `.errorBanner(message:)`. This is `BroadcastView`'s existing pattern (`naarsError` text existed at `a600f5c`); Task 7 kept it. Design-system follow-up, not a regression.
6. **`ReportContentSheet` at AX 5:** the reason icons still touch their labels (Phase 2 finding 6, shared by every report type, not new).
7. **Not seen in a preview (below the fold, or only in menus and alerts):** the member detail's action buttons at AX 5 (seen at the default size: Make owner, Make admin, Remove from community); the remove sheet's Remove button at AX 5; the reports list's person, platform-handled ("Platform moderators handled this report") and auto-hidden cards (the first two cards and the Ride card header were seen); the reports filter capsules beyond "Pending, All, Re…" at AX 5 (they sit in a horizontal `ScrollView`, `CommunityReportsView.swift:176`, so they scroll rather than clip); guidelines section 7 at AX 5; the archive alert, the "choose a new owner" alert, the title menu open and the My communities admin menu. All are in the O1 capture list.

## Owner steps as planned (from the headless gate)

Each needs the owner signed in on the simulator through the built-in panel, a second account, or a write to production (writes only with the owner's go-ahead). The orchestrator runs them later with the owner.

- **O1. Captures (pending)** (light, dark, AX 5): every capture list in Tasks 3-9, signed in as the owner (platform admin) and, for the Profile row and the panel's community scope, as a second account that owns a test community and is not a platform admin. Include the items in finding 7, the type chip in Spanish (`-AppleLanguages (es)`), and a comparison of the one-membership Requests and Community tabs with the Phase 2 captures (expected unchanged).
- **O2. Push fixtures (pending)**: `content_reported_community_admin.apns` as the second account → Profile tab, that community's Reports; `content_reported_platform_admin.apns` as the owner → Admin → Reports; `account_restricted_community.apns` → My communities.
- **O3. Live matrix, writes (pending)**, in plan order: create "P3 Live Check", a third account joins, the owner reports its post, the bell row has no reporter, hide / restore, the platform-handled row, a person report dismissed, roles, ownership there and back, remove with a note (read `removal_reason`), let back in, settings, three announcements and the fourth refused, dismiss the "P2 Live Check" community report from Admin → Reports. Clean-up as the plan says. The SQL is live (step 1), so nothing blocks this.
- **O4. Installed build (optional, pending)**: Admin → Stats on an App Store build shows the runbook's step 1 snapshot figures.
- **O5. Shut down, push and update the draft PR (pending, owner).**
- **Carried from Phase 2, still open:** the Phase 2 render findings 1-4 (invite sheet AX 5 buttons, the "1 times" plural, the owned-limit sheet title, the two retry buttons on onboarding) have no fix commit on this branch; the offline install-over run.

## Owner-present steps, run 2026-10-19 morning (two simulators, driven by the orchestrator)

The owner asked that these steps run without them, so the orchestrator drove two of the owner's simulators through the built-in panel: the owner's `iPhone 16` (iOS 26.5, CAA2F1FD…, their own platform-admin account, dark theme) and `iPhone 17 (26.5)` (7CFBFB78…, simulator appearance dark, text size large), on which the two throwaway accounts were created through the app's own Sign Up. Build: the branch at `930e906` (`[P3-fix]` through the members-row fix; the earlier part of the run used `b7f4282` and was repeated after the fix where it mattered). Captures are in `build/p3-gate/captures/` (gitignored), `00`–`57` from this pass and `58`+ from the Opus agent that finished the tail (its log: `build/p3-gate/opus-steps-log.md`). Server checks ran through the Supabase MCP after every write. Test accounts: "P3 Second" (owner of the test community), "P3 Third" (joined by code), and the owner's account (joined by code, approved by the second account).

**Side effects on real accounts.** Every test report fanned out to the platform admins as designed: the three admins other than the owner each received four `content_reported` rows and pushes (12 in all) plus the "New community: P3 Live Check" announcement from the community's creation. No real member received anything else; the test announcements went only to the test community's members.

### O3. Live matrix (writes), in plan order

| Step | Outcome | Evidence |
|---|---|---|
| Create "P3 Live Check" as the second account | Done through onboarding ("Start your own community", approval on), then the invite sheet (one-use code, then a two-use code) and the guidelines | `02-*`, `03-*`; `communities` row, `join_policy = approve` |
| Owner's account joins by code, approved on the second device | The code resolved to the community with its two join questions; the request showed on the second account's Requests to join (Profile badge 1) and was approved; the owner's My communities then listed two memberships and the Requests and Community title menus offered both | `10-*`, `11-*`, `12-*`, `13-*`; membership pending → active, `user_approved` row |
| Third account joins by the two-use code, approved | Same flow; the two-use code reached 2/2 | `14-*`, `15-*`, `16-*`; `community_invites.use_count = 2` |
| Third account posts twice (as that user, through SQL) | Two posts in the test community; the owner's Community tab menu showed "2 new" and the feed listed both | `18-*` |
| Owner reports post 1 (Spam, with a note) | The second account got one `content_reported` row with `source_user_id` null and a queued push carrying `community_id`; the three other platform admins got one row each **with** the reporter; the author and reporter got none | `19-*`; `reports` row, `notifications`, `notification_queue` |
| Community Reports list (second account) | Privacy banner, the card with type, preview, "Posted by", the reporter's note, Hide and Dismiss, **no reporter**; Admin → Reports on the owner's device showed the same report with "Reported by" and Hide / Dismiss | `30-*`, `21-*` |
| Hide with a reason (community admin) | Post hidden (`hidden_by` = second account, reason stored), `reports.community_status = action_taken`, `status` still `pending`, one `hide` event, the author got "Your content was hidden" with the reason; the owner's Admin → Reports still listed it as pending with Hide / Dismiss | `31-*`, `32-*`, `33-*` |
| Restore (community admin) | Post visible again, `content_hidden = false`, `restore` event by the second account | `33-second-reports-all-restore`, `34-*` |
| Platform admin hides post 2 from Admin → Reports | `hidden_by` = owner, `reports.status = action_taken`, `reviewed_by` = owner; the community list showed "Platform moderators handled this report." with no actions; the owner then restored it (Resolved filter → Restore) | `35-*`, `37-*`, `38-*`, `39-*`, `40-*` |
| Person report about the third account (by the owner, as that user through SQL) | The community list offered Dismiss only ("To act on a person, remove them in Members."); dismissed for the community (`community_status = dismissed`, `status` pending) and then by the owner in Admin → Reports | `42-*`, `43-*`, `46-*` |
| Community report (by the third account) | Never reached the community list; Admin → Reports labelled it **Community** with the community's name and Dismiss worked (`dismiss` event with `target_type = community`), which closes the Phase 2 follow-up | `41-*`, `43-owner-*`, `44-*` |
| Make admin, then member | Role changed on the server each time, the chip and actions followed | `23-*` |
| Make owner, hand back | The second account became admin and the detail lost its actions; ownership was handed back as the third account through SQL. After the hand-back the detail showed no actions until the app was foregrounded (the membership cache refreshes on foreground, not on a transfer done elsewhere); then Make owner / Make admin / Remove returned | `24-*`, `25-*` |
| Remove with a note | Sheet footer reads "Only this community's admins and platform moderators see this note"; the member moved to the Removed list with the note under their name; `removal_reason` held the text; the third account got `account_restricted` ("A community admin removed you.", no note) with `community_id` in the push | `26-*`, `27-*`, `28-*` |
| Let back in | Active again, `removal_reason` cleared, `user_approved` row | `28-second-removed-member-detail-let-back-in`, `29-*` |
| Settings | "Members can invite" off, Save: `members_can_invite = false`; later renamed to "P3 Live Check renamed" | `09-*`, `57-second-settings-renamed-before-save` |
| Announcements | Two sent as the second account through SQL, the third from the app (pinned); each reached the two other members; the fourth was refused from the app with "P3 Live Check has already sent 3 announcements today. Try again tomorrow." and wrote no row | `51-*`, `52-*`, `53-*`, `54-*` |
| Admin → Reports: dismiss the community report | Done (see above); there was no "P2 Live Check" report left to dismiss, so a fresh community report from the third account stood in for it | `44-*` |
| Owner's account leaves the test community | Leave sheet, then My communities back to one membership; membership `left` | `57-owner-leave-p3-sheet` |

### O2. Push fixtures

| Fixture | Device | Route logged | Screen |
|---|---|---|---|
| `content_reported_platform_admin.apns` (no `community_id`) | owner's | `Navigating to: adminReports` | Admin → Reports, pending list | 
| `account_restricted_community.apns` | owner's | `Navigating to: myCommunities` | My communities |
| `content_reported_community_admin.apns` | second | `Navigating to: communityReports(communityId: 6D5E97BF…)` | Profile tab, that community's Reports (subtitle the community name). The second account's app had never asked iOS for notification permission, so the first train showed no banner; Account Settings → "Turn On Notifications" raised the prompt inside the app, Allow, and the next train's banner was tapped. |

### O1. Captures

Dark captures of every Phase 3 screen in the lists of Tasks 3–9 were taken on the way through the matrix: Profile with the Admin Panel row (community owner who is not a platform admin), the panel in a community scope and, on the owner's device, in the All scope and the P3 scope with the title menu open, Members (owner view, three members, the Removed list, search), member detail in each action set, the remove sheet, Reports (empty, pending, all, the platform-handled row, the person report, the dismissed filter), the hide / restore / dismiss sheets, settings as owner, Send Announcement (empty, filled, confirm, the daily-limit error, the discard alert), My communities' admin menu, the guidelines section 7 (light, dark and AX 5), and the Requests tab with one and two memberships. AX 5 on device: the admin panel's stat tiles stack with no broken word (render finding 1 fixed, `f97b8f0`). The light and AX 5 pass of the panel, Members, Reports and Settings, the Spanish type chip, the "choose a new owner" path and the archive are in the Opus agent's part below.

### Found on device and fixed

1. **Members rows did nothing** (`930e906`): `CommunityMembersView` is pushed with a destination-style link (Admin Panel) or `navigationDestination(item:)` (My communities), and from such a screen its own `navigationDestination(for:)` was invisible to the rows' `NavigationLink(value:)`; SwiftUI logged "Invalid Configuration" at each tap. The row is now a `Button` that sets `selectedMember`, presented through `navigationDestination(item:)`. Verified on the second device after a rebuild.
2. **Pull-to-refresh on community Reports showed "Failed to load data"** when the pull's task was cancelled before the request returned (`URLError.cancelled`); the list was replaced by the error view. `CommunityReportsViewModel.reload` now returns silently on a cancelled request (`8ee7da4`; Debug build exit 0, `CommunityReportsViewModelTests` 9 of 9 passed on the headless simulator).

### Tail of the owner steps, run by an Opus agent on the second device (log: `build/p3-gate/opus-steps-log.md`)

| Step | Outcome | Evidence |
|---|---|---|
| Settings: "Approve new members manually" off, Save | `join_policy` went from `approve` to `invite`; `members_can_invite` stayed false. The first tap on the toggle knob did not register, the second did. After Save the button greyed out with no toast | `58-*` |
| Leave as the sole owner with other members | The ordinary Leave sheet shows first; the "Choose a new owner first" alert appears after confirming it (the server answers `last_owner`), and its action pushes Members with the transfer banner "Choose who becomes the owner. You'll become an admin." Backed out without transferring; the account stayed owner | `59-*`, `60-*` |
| Light: admin panel, Members, Reports (All), Settings | All clean. The 21-character title fills the full width; no scope chevron with one community; the off-toggle track is the system's pale grey | `61-*` to `64-*` |
| Light + AX 5: panel, Members, Reports | Stat tiles stack; Members rows stack avatar above name; report card headers stack icon, type, chip. The Management rows centre their wrapped text and hyphenate "Mem-bers"; the Reports filter row cuts the third chip at the edge with no fade (it scrolls). Nothing clipped | `64b-*`, `65-*`, `66-*`, `66b-*`, `66c-*` |
| Spanish (`-AppleLanguages (es)`) | Type chips "Usuario" / "Publicación", reason chips "Acoso" / "Spam", filters Pendientes / Todos / Resueltos / Descartados, Members "Propietario" and "Se unió el oct 19, 2026" (month first: the simulator region stays US). No Phase 3 string in English. Outside Phase 3, the Profile stat labels "No Rating", "My Savings", "Fulfilled", "XP" stay English | `67-*`, `67a-*`, `67c-*` |
| Archive | Alert text as designed; `archived_at` set, the row kept. The confirmation toast "… was archived." showed on Profile for under a second before the app moved to the onboarding root, because the archived community was the account's only one | `68-*`, `69-*`, `69b-*` |
| Revoke the spare code | `revoke_community_invite` as the second account: `revoked_at` set for the one-use code; the two-use code was already fully used and redemption checks `archived_at` | SQL |
| Second account deletes itself | From the onboarding root's "Delete Account" link: generic confirmation, "Account Deleted", Welcome. The A3 owned-community warning did not show because the only owned community was already archived (`communitiesClosedByDeletion` counts live ones). `auth.users` and `profiles` rows gone; the community row stays archived with `created_by` null | `70-*`, `70b-*`, `71-*` |
| Third account deletes itself | Run by the orchestrator (the agent declined to type a password into the live app): signed in, landed on the onboarding root (its only community archived), deleted from the same link. Both throwaway accounts are gone; the community keeps only the owner's `left` row; no test post or report remains, and the six moderation events stay as the append-only log | `72-*`; SQL |

### Final headless run on the fixed code

Full unit suite, signed out, on `iPhone 16 Tests` at `8ee7da4` (every `[P3-fix]` commit included), the plan's single-simulator flags: **641 cases, 608 passed, 0 failed, 33 skipped** (the session-gated classes), `xcodebuild` exit 0, result bundle `build/p3-gate/final-full.xcresult`. No simulator was left booted.

### Observed, left as follow-ups

- After an ownership transfer performed elsewhere, the member detail keeps the old action set until the app is foregrounded (the membership cache refreshes on foreground). A role change made on the same screen refreshes at once.
- The first Sign Up on the iPhone 17 (iOS 26.5) rendered normally; the iOS 26.4 push storm from the Phase 1 gate was not seen.
- The Admin Panel opened from My communities keeps the community's old name in its title after a rename in Settings until it is reopened (the panel from Profile → Admin Panel showed the new name).
- The archive confirmation toast is not readable when the archived community was the account's only one: the onboarding root replaces the screen within a second.
- The A3 owned-community warning on account deletion cannot show for a community that was archived first; the onboarding root's "Delete Account" link uses the generic confirmation.
- At AX 5 the Management rows of the admin panel centre and hyphenate their labels, and the Reports filter row has no edge fade.
- The Profile stat labels ("No Rating", "My Savings", "Fulfilled", "XP") are not localized (predates Phase 3).
- The owner's platform-admin account had nothing to approve on the test community in the end, so `admin_moderate_content` on a community report was exercised with a fresh report rather than the "P2 Live Check" one the plan names (none was left over).

### Not run

- O4 (an installed App Store build's Admin → Stats against the runbook snapshot): no App Store build of this branch exists yet.
- The offline install-over run carried from Phase 2.

## PR Impact Summary

**Behaviour changes a reviewer must know about**

1. **Community owners and admins receive `content_reported` for their community, with no reporter, and handle it in a Reports list** (hide with a reason, restore, dismiss). Reports about the community's owners and admins, message reports and community reports stay with platform admins (INV-P2). The bell row a community admin gets has no source user; the push carries `community_id` and no reporter.
2. **`content_reported` with a `community_id` opens that community's Reports for a non-platform admin** (`.communityReports(id)`, Profile tab); without one, or for a platform admin, it opens Admin → Reports as before. **`account_restricted` opens My communities** (`.myCommunities`).
3. **The Profile's Admin Panel row shows for admins of any community**, and the panel has a community scope with a title menu (platform admins also get "All communities"). In a community scope it offers figures, Send Announcement, Requests to join, Members, Reports and Settings.
4. **Platform admins are held to 3 announcements a day per community, on every build** (the cap lives in `send_community_broadcast`, which the installed build's `send_broadcast_notifications` wrapper calls). The cap counts only announcements by platform admins and the community's owners and admins, so a member's directly inserted `announcement` row no longer counts.
4b. **A community admin's decision never leaves the platform queue**: it is written to `reports.community_status` / `community_reviewed_at`, never `status` / `reviewed_*`. Platform decisions and the 3-reporter auto-hide cannot be undone from a community; the community list shows "Platform moderators handled this report" and offers nothing the server would refuse.
5. **The admin figures and announcements call the community RPCs** (`get_community_stats*`, `send_community_broadcast`); the platform panel's All scope reads every community. The legacy `send_broadcast_notifications` call and `BroadcastParams` are removed from the client.
6. **Leaving as the last owner offers to choose a new owner**: the Members screen opens with a transfer banner, and the leaver becomes an admin.

New community-admin surfaces: Members (search, removed list) and member detail (remove with a note that only the community's admins and platform moderators see, since the removal push has a fixed body and no screen shows it to the member; let back in, make admin or member, make owner); Community settings (name, description, manual approval, member invites, archive behind a confirmation); Reports; announcements to one community.

**Coordinator calls added** (both `forceFullRefreshAndWait` from ViewModels after an explicit action; `RefreshCoordinator.swift` unchanged): `(.dashboard, "removedMember")` after a removal and `(.dashboard, "archivedCommunity")` after an archive. No `invalidate` or `refreshIfNeeded` from a ViewModel. Realtime, `MessageSendManager`, reactions, SwiftData models and mappers, `BadgeCountManager`, `PushNotificationService` and the notification registry (33 types) are unchanged.

**High-blast-radius seams touched, and what breaks if a consumer is missed**

| Seam | Change | If a consumer were missed |
|---|---|---|
| `NavigationIntent` | `.communityReports(UUID)`; it joins the Profile-tab group with `.myCommunities` | A `switch` without the case stops compiling; a tab mapping that omits it opens the wrong tab or none. |
| `NavigationCoordinator` | `DeepLink.communityReports` / `.myCommunities` → `pendingIntent`; `NotificationIntent.openCommunityReports(communityId:)` / `.openMyCommunities` → Profile tab; `.communityReports` in the deferred-intent match and admin groups | A push tapped while the app is closed is lost, or a deferred intent is applied twice; a group that omits the case leaves the person on the wrong tab. |
| `DeepLinkParser` | `content_reported` with `community_id` → `.communityReports(communityId:)`; `account_restricted` → `.myCommunities` | A path that drops `community_id` sends a community admin to Admin → Reports, which they cannot open; `account_restricted` falls back to the dashboard. |
| `NotificationNavigationRouter` | Injected `isPlatformAdmin`; a non-platform admin's `content_reported` bell row with a community → `.openCommunityReports`; `.accountRestricted` → `.openMyCommunities` | A platform admin who also owns a community would be sent to the community list instead of the platform queue, or a community admin to a screen they cannot open. |
| `AppDelegate` | `.communityReports` and `.myCommunities` added to the intent group it passes through | A notification-tap intent is dropped before it reaches the coordinator. |
| `CommunityContext` | `administeredCommunities`, `isAdminOfAnyCommunity` | The Profile row or the panel's title menu hides communities the person administers, or shows them after a demotion. |
| `Constants` | `removalNoteMaxLength = 500` | The client limit drifts from the server's; the server still enforces it. |
| `AdminService` (protocol added) | `AdminServiceProtocol`: figures, announcements, community reports and moderation, all by community; `PreviewAdminService` (DEBUG) and `StubAdminService` (tests) conform | A screen on the concrete type cannot be previewed or stubbed; a conformer missing a method stops compiling; a caller that passes no community would read every community's figures (the platform scope) instead of one. |
| Supabase RPC call sites | `get_community_reports`, `moderate_community_content`, `get_community_stats*`, `send_community_broadcast` (P0001 → daily limit, 42501 → not an admin), and the member and settings wrappers on `CommunityAdminServiceProtocol` | An argument-name mismatch fails every call; a refusal not mapped through `CommunityRPCError` shows the server's English text. |

**Database dependency.** `20261018_0001_community_moderation.sql` and `20261018_0002_community_stats_and_broadcast_cap.sql` are applied and verified (step 1). Refusals arrive as `{success:false, error, code}` and are shown as `CommunityRPCError.localizedMessage`; codes this build does not know decode as `nil` and take the "not allowed, reload" path.

**Follow-ups to record**

- Render findings 1 and 2 above (1 before release).
- The installed and Phase 3 Admin → Reports label a pending report that a community admin hid "Auto-hidden" (SQL plan D-S7).
- A member can still insert a row typed `announcement` directly (SQL plan D-S8); it no longer counts toward the cap.
- No co-owner action, no time-zone field, no `set_primary_community` screen, no admin delete of posts (plan self-review, deliberate departures 2-4).
- Release prerequisite: the Task 9 legal text must be mirrored to the Notion pages the app opens before this client ships.

**App Store checklist** (spec §5). New system permission: no. Stores data differently: yes, community admins now see report content and reporters' notes (never the reporter's identity) and can write a removal note; disclosed in the privacy policy, terms and FAQ (Task 9). Account deletion: unaffected. Reporting, blocking, moderation: extended, community admins moderate their own community and every report still reaches platform admins. Notification behaviour: altered, a second `content_reported` audience and the announcement cap for platform admins; no new type. Third-party SDK, entitlement, privacy-manifest change, payments: none.
