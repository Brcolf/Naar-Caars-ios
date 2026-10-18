# Multi-community Phase 1: verification gate and PR Impact Summary

Date: 2026-10-18. Branch `claude/naarscars-multi-community-roadmap-f08594`, Swift state at `e4e5fdf` ("[P1-fix] Keep one view identity in the community title menu"), on top of `63fcf24` ([P1-T21]). Plan: `Docs/superpowers/plans/2026-10-17-multi-community-phase1.md`, Task 22. This file records what was run, what it showed, and what is still left to the owner. The **Impact Summary** below is the text the draft PR must carry.

## What was run

| Plan step | Result |
|---|---|
| 1. Preconditions (Supabase MCP, read only) | `get_my_memberships`, `get_profile_stats`, `search_community_members`, `get_community_leaderboard`, `get_community_spotlights` exist (5 of 5); `town_hall_posts.community_id` exists. |
| Build (Lane B, `build/DerivedData`) | 0 errors. Unique warnings compared with `build/baseline-build.log`: none new. Log: `build/p1fix-build.log`. |
| 2. Full unit suite | Simulator "iPhone 16 Tests" (never signed in; the baseline app on it opens on Welcome), single destination, no parallel clones, 60/120 s allowances. **445 cases: 412 passed, 0 failed, 33 skipped** (the session-gated live-backend classes). `xcodebuild` exit 0. Bundle: `build/P1-fix-full.xcresult`. The last CI run on `main` had 332 passed and 35 skipped. An earlier gate attempt on this branch (`build/P1-gate-full.log`, 07:05) failed once on `PerformanceImprovementsTests.testNetworkRetryExponentialBackoff`, a timing test; it passed in this run. |
| 3. Previous build | Worktree of `f164a0f` (merge base with `origin/main`), built into `build/DerivedData-baseline`: 0 errors. Worktree removed afterwards. |
| 4. Install over the previous build (online, signed out) | Baseline app installed fresh and launched (Welcome screen, `build/P1-installover-baseline.png`); its store had no `ZCOMMUNITYID` column. One probe row was written into `ZSDTOWNHALLPOST` so the migration had data to carry. Phase 1 app installed over it (no uninstall) and launched: Welcome screen, no data-error alert (`build/P1-installover-phase1.png`). `default.store` birth time and inode unchanged (`1792338472` / `1157498`), so the store was not deleted and `createModelContainer` did not throw (`App/NaarsCarsApp.swift`, the recovery path deletes the store). `ZCOMMUNITYID` (BLOB) now exists on `ZSDTOWNHALLPOST`, `ZSDRIDE`, `ZSDFAVOR` and `ZSDNOTIFICATION`; the probe row survived with `ZCOMMUNITYID = NULL`. No log line from the container recovery path. Pre-migration container copy: `build/p1-container-baseline`. |
| 8. Preview renders (Xcode MCP `RenderPreview`, light / dark / AX 5) | "Former member" previews of `RideCard` (poster, claimer, three communities), `FavorCard` (same three), `ReviewCard`, `PostCommentsView`; both `CommunityTitleMenu` previews. All rendered; no clipping in light or dark, dark contrast readable, names truncate with an ellipsis. One AX 5 finding below. |

### CommunityTitleMenu after the fix

The modifier no longer branches on `enabled` (see the commit). Renders of the disabled state are byte-identical to a navigation title with neither modifier, both large and inline title; the enabled state shows the chevron and, on Requests, the subtitle. An always-present `toolbarTitleMenu` with an empty menu was rejected: it draws the chevron once the title is inline.

### Findings from the renders

- At AX 5 the claimed row of `RideCard` and `FavorCard` breaks "Claimed by" inside the word ("Claim / ed by") and truncates the name ("Form…"). The row is an `HStack` of label and name; the same layout is used when the claimer is visible, so it is not specific to "Former member". The seats label on `RideCard` also breaks inside the word ("seat / s") at AX 5, in the original preview as well. Not fixed here; a layout follow-up (let the row wrap as a `ViewThatFits` or stack vertically at accessibility sizes).
- `TownHallPostCard` "Former member author" did not render: the preview's design-time thunk fails to type-check `TownHallPostCard.swift:468` in reasonable time. The app target builds; this affects previews only. Not verified on screen.

## Not run (owner steps)

- **Install-over run 2 (offline).** The Mac's network cannot be cut from this session. Container creation does not touch the network, so run 4 covers the migration itself; what run 2 adds is the cached feed staying up offline, which needs a signed-in session.
- **Signed-in captures** (spec §4 Phase 1): both create forms, the Requests dashboard and the Community tab with one membership and with three (`-debugCommunityCount 3`), light, dark and AX 5, and the comparison with a baseline signed-in capture (no chevron, no subtitle line, no chip, no "Post to" with one membership). Needs the owner to sign in on a simulator.
- **The three push fixtures** in `Docs/qa/push-fixtures/` (`simctl push`, then tapping the banner). Needs a signed-in session and a tap.
- **Draft PR and CI.** Opening the PR needs a push, which is the owner's step. Once it is open, CI (Lane C) runs the same build and unit suite.
- Live two-community behaviour: no member holds two memberships until Phase 2.

## PR Impact Summary

**Behaviour changes a reviewer must know about**

1. **Town Hall pushes do a targeted single-post refresh.** `NotificationType.entityIdKey` now returns `town_hall_post_id` for `townHallPost`, `townHallComment` and `townHallReaction`, so `PushNotificationService.handlePushReceived()` calls `RefreshCoordinator.performTargetedRefresh(.townHall, entityId:)` instead of `invalidate([.townHall])`; the background path in `AppDelegate` follows automatically. The targeted refresh fetches one post (`TownHallPostFetching.fetchPost`), enriches it like the feed does, and upserts it through `BackgroundSyncActor` with change detection. A push with no or a malformed id still falls back to invalidating the domain.
2. **The foreground re-check can now move a member out of the main UI for reasons other than a ban.** `AppLaunchManager.recheckAccountStatus()` replaces `recheckBanStatus()` on every foreground. The old check moved a session only to `.banned`; the new one maps the profile flags exactly as launch does, so a member whose approval is revoked server-side (`approved = false`) leaves the main UI on the next foreground for `.pendingApproval` (application complete) or `.needsApplication` (not complete), instead of on the next launch. It acts only on a successful read and only while the state is still `.ready(.authenticated)`; a failed read changes nothing. It also runs when the last active membership goes (`CommunityContext.onActiveMembershipsEmpty`).

**High-blast-radius seams touched, and what breaks if a consumer is missed**

| Seam | Change | If a consumer were missed |
|---|---|---|
| `NotificationType` / `AppNotification` | `entityIdKey` → `town_hall_post_id` for the three Town Hall types; `communityId` decoded from rows | A push routed by the old `post_id` key never finds the id: every Town Hall push degrades to a whole-domain invalidation, and the bell row loses its community. |
| `PushNotificationService` | targeted Town Hall refresh; `community_id` read from the payload | Refresh falls back to invalidation; a push for another community opens in the wrong one. |
| `DeepLinkParser` | `townHallPostComments` / `townHallPostHighlight` carry an optional `communityId` | Pattern matches written as `(let id)` stop compiling; a default of nil keeps old payloads working. |
| `NavigationCoordinator` | `.townHallPost` intent and `TownHallNavigationTarget` carry `communityId`; `.enterApp` calls `handleEnterAppIntent()` | A consumer that drops the id opens the post in the community already shown; `.enterApp` relaunching an authenticated session would re-run session setup. |
| `BadgeCountManager` | `BadgeCountsPayload` decodes the additive `pending_members_total`, `community_details`, `total` (optional, unread in Phase 1) | Non-optional keys would fail decoding against a server without them and zero every badge. |
| `BackgroundSyncActor` + the mapper trio (`SDModels`, mappers, sync engines) | `communityId: UUID?` on `SDRide`, `SDFavor`, `SDTownHallPost`, `SDNotification` and the domain models; single-post upsert for Town Hall | A mapper or upsert that skips the field leaves it nil, so community scoping and chips silently show nothing. The SwiftData change is additive-only (verified above). |
| `Constants` | `membershipRefreshMinInterval` (30 s), `townHallTargetMembershipWait` (10 s) | A second, unthrottled membership load per foreground; a cold-start push target dropped instead of waiting for memberships. |
| `AppLaunchManager` / `ContentView` / `AuthService` | `recheckAccountStatus()`, `handleEnterAppIntent()`, membership state cleared on sign-out | See behaviour change 2; a missed sign-out clear leaks one account's memberships to the next. |

**Database dependency.** The client reads Phase 0 objects (the five RPCs above, `community_id` on the request and post tables, `get_badge_counts` keys). They are live (step 1 above). Behaviour against a backend without them was not tested in this gate.

**App Store checklist.** No new permission, SDK, tracking, payment or privacy-manifest change. Account deletion, reporting, blocking and moderation paths are unchanged. Notification behaviour changes only as in item 1 (refresh scope, not delivery or routing).
