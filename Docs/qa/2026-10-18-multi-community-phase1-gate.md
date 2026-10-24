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

## Owner-present steps, run 2026-10-18 afternoon (signed in, built-in simulator panel)

Build: the Phase 1 snapshot app from `688ee98` (Phase 1 plus `[P2-T2]`, v1 build 11). Device: the owner's `iPhone 16` simulator (iOS 26.5) through the Claude desktop app's simulator panel, using the session that was already signed in on it (the owner's own account, a platform admin). The fixture account was not used because the sign-in screen could not be reached (finding 1). Nothing was submitted or written on the server; the three memberships came from the `-debugCommunityCount 3` launch argument. All captures are in `build/p1-gate/` (gitignored), 32 PNGs named `<screen>-<1member|3members>-<light|dark>[-ax5].png` for the Requests dashboard (`dash`), `create-ride`, `create-favor` and `community`, plus `push-1-townhall-with-community-banner.png`.

### Captures

| Screen | One membership (baseline) | Three memberships |
|---|---|---|
| Requests dashboard | Title "Requests", no chevron, no subtitle; empty state (the default community has no open request today). | Identical to the baseline: no chevron and no subtitle, in light and dark (finding 2). |
| Create Ride | No "Post to" section; the toolbar button reads "Post". | A "Post to" section with a Community picker ("Naar's Cars Seattle") above Date & Time; the toolbar button reads "Post to Naar's Cars Seattle". |
| Create Favor | No "Post to" section. | Same "Post to" section and button as the ride form. |
| Community tab | Title "Community", Town Hall / Leaderboard control, cards unchanged. | Title becomes the community name ("Naar's Cars Seattle"); no chevron, and tapping the title opens nothing (finding 2). |

Light, dark and AX 5 were captured for every cell. Dark mode comes from the app's own theme setting (the owner had it on Dark; it was switched to Light through Settings → Appearance for the light captures and set back to Dark). Dark contrast is readable everywhere; nothing clips at the default size.

### Findings

1. **Blocker to confirm: the Sign In and Sign Up pushes never render on `iPhone 17 Pro` / iOS 26.4.** On the owner's `iPhone 17 Pro` simulator (iOS 26.4 runtime, no session), tapping "Sign In with Email" or "Sign Up with Email" on the Welcome screen starts a main-thread render storm: `sample` shows 100 % of the main thread in `_UIHostingView.layoutSubviews → ViewGraphRootValueUpdater.render → LoginView.body` (or `SignupDetailsView.body`) for about three minutes, the pushed screen never appears, taps are ignored, and with `-UIViewLayoutFeedbackLoopDebuggingThreshold 50` the process aborts (SIGABRT, 45 s after the tap), which means UIKit saw a layout feedback loop. `LoginView.swift`, `SignupDetailsView.swift`, `WelcomeView.swift`, `NaarsTextField.swift` and `AppleSignInButton.swift` are byte-identical to `main`; the two pushed screens share `ScrollView` + `NaarsTextField` + `@FocusState` + a keyboard `ToolbarItemGroup`. Not reproduced on iOS 26.5, because the only 26.5 device holds the owner's session and signing it out would have blocked the rest of this gate if the storm reproduced. **Before any build goes to TestFlight, run the Welcome → Sign In push on an iOS 26.5 simulator with no session** (the `NaarsCarsUITests` login flow does exactly this), and if it reproduces, bisect the keyboard toolbar and the focus binding first. The owner's Mac was under heavy load from the Phase 2 agents during this (load average 50 to 115), which slows everything but does not explain a three-minute spin followed by an abort.
2. **The community switcher is not reachable on device.** With three memberships, neither the Requests title nor the Community title shows the title-menu chevron, and tapping the title opens nothing, in light and dark, after the memberships had loaded (the `get_my_memberships` call is in the Supabase API log and the create forms show the three communities). The gate renders in §8 showed the chevron, but those previews had `enabled == true` from the first render; on device `hasMultipleCommunities` flips from false to true after the first render (memberships load after the UI is up, and `restore(for:)` starts from an empty list), and the `ToolbarTitleMenu` added by `communityTitleMenu` at that point is not picked up by the navigation bar. The `[P1-fix]` that stopped branching on `enabled` removed the identity reset but left this. A member of two communities therefore cannot change the Requests scope or the Community tab's community from the title. Fix in a follow-up (`[P1-fix]`), verified on device: either give the title content a new identity when `enabled` flips (`.id(enabled)` on the navigation content, accepting one reset at load time), or seed `enabled` from a cached membership count so it is right at first render, or add an explicit control (a chip or picker under the title) that does not depend on the title menu. The Community tab title does change to the community name, so the rest of the plumbing works.
3. **AX 5: the "Post to <community>" toolbar button collapses into an overflow menu.** At the largest accessibility size the Post button in both create forms becomes a "•••" item in the sheet's toolbar; Post is still reachable but hidden behind a menu, while the one-membership "Post" button stays visible. Use the short "Post" label at accessibility sizes (the community is already named in the form's "Post to" section) or move the community name out of the button.
4. **Pre-existing AX 5 layout breaks, not from this branch:** the ride form's Time row breaks "Time" inside the word ("Ti / me") next to the three time pickers; the Town Hall card title collapses to its first letter ("N") beside the five-star rating; the Town Hall / Leaderboard segmented control does not scale. Same shape as the `RideCard` "Claim / ed by" break noted in §8. Layout follow-ups.
5. **The dashboard with three memberships shows no scope subtitle.** By design when the scope is "All communities" (`name(for:)` is nil), so nothing distinguishes the dashboard of a member of three communities from the baseline until finding 2 is fixed.

### Push fixtures (`xcrun simctl push`, app in the foreground, banner tapped)

Placeholders were filled with the default community `7a8ed131-…`, post `f671bf78-…` ("New Review") and the fixture account's user id. Each banner was tapped from the foreground app; the navigation line is from the app's `navigation` log category.

| Fixture | Received (targeted refresh) | Tap |
|---|---|---|
| `town_hall_post_with_community` | `[townHall] started(targeted(F671BF78…)) trigger=push:town_hall_post` | `townHallPostComments(id: F671BF78…, communityId: 7A8ED131…)`: the post's comments opened in the right community. |
| `town_hall_comment_without_community` | targeted refresh of the post, `trigger=push:town_hall_comment` | `townHallPostHighlight(id: F671BF78…, communityId: nil)`: the post in the community already shown (the documented fallback). |
| `town_hall_post_foreign_community` | targeted refresh of the unknown post id, no error | `townHallPostComments(id: 00000000-…-0001, communityId: 00000000-…-0001)`: the Community tab came forward on the current community; no crash, nothing opened for the foreign post. |
| `pending_approval_with_community` | badges refresh, `trigger=push:pending_approval` | `pendingUsers` (the admin Pending Approvals screen). |
| `pending_approval_without_community` | same | `pendingUsers`. |
| `user_approved_further_community` (signed in) | badges refresh, `trigger=push:user_approved` | "Enter app" → `enterApp`; no launch-state change and no session re-setup in the log; the app stayed where it was. |

Note that `[P2-T11]` (`4f3e246`, after this snapshot) re-routes `pending_approval` to Requests to join and `.enterApp` to My communities, so the last three rows describe the Phase 1 snapshot only; the Phase 2 gate must repeat them.

### Still not run

- The fixture account's sign-in and anything signed out on iOS 26.5 (finding 1).
- Install-over run 2 (offline) and the two-community live matrix (no member holds two memberships until Phase 2).

### Notes for whoever repeats this

- The Phase 2 workflow agents end their Lane B runs with `xcrun simctl shutdown all` or `shutdown booted`; the gate device was shut down under this pass four times. Boot it again and relaunch; nothing is lost. Agents should shut down only the device they booted, by UDID.
- The app's theme is the in-app setting (`naars_theme_mode`), not the simulator's appearance. Editing the container plist does not survive cfprefsd's cache; switch it in Settings → Appearance.
- A banner lasts about five seconds, so to tap one, send the same fixture every four seconds for half a minute and tap at the top of the screen (points `196, 88` on an iPhone 16).
- Delivered banners do not stay in Notification Center (the app clears them), so the shade cannot be used instead.

## Fixes for the findings above (2026-10-18, evening)

- **Finding 1 (Sign In / Sign Up push storm).** A main-thread sample of the storm was dominated by the iOS 26 toolbar bridge (`ToolbarBridge.preferencesDidChange`, the keyboard items' label layouts). Controlled runs on the iPhone 17 Pro / iOS 26.4 showed the storm is load-dependent: the unpatched build stormed on 3 of 3 pushes with a host load average above 50 and on none of 2 on a quiet machine; iOS 26.5 never stormed (4 pushes, loaded and quiet). Fix `81fdbc9`: the keyboard toolbar is built only while a field has focus, as separate `ToolbarItem`s with a `ToolbarSpacer`. With it, 3 of 3 pushes under a load of about 50 and 2 of 2 quiet rendered within a second at under 4 % CPU, and the up / down / Done bar works on both screens. One storm was seen with the patched build in its very first run, under the heaviest conditions of the day (four simulators booted, load about 100), before the controlled runs; treat the fix as narrowing the exposure, not as proof that it is gone, and judge any recurrence on a quiet machine.
- **Finding 2 (title menu never appears).** Cause: on iOS 26 a title menu is drawn and tappable only on an inline title, and these root screens never collapse. Fix `4f2a937`: `communityTitleMenu` sets `toolbarTitleDisplayMode(.inline)` while enabled (`.automatic` otherwise). Verified on the signed-in iPhone 16 with `-debugCommunityCount 3`: both titles show the chevron once memberships load, the menu lists All communities and the three memberships, picking one sets the Requests subtitle and keeps the selected tile, and switching the Community tab runs a coordinator refresh (trigger `communitySwitch`) and changes the title. Visible change: members of several communities see an inline title instead of a large one on those two screens; one membership is unchanged.
- **Findings 3 and 4.** Fix `4d4b92a`: at accessibility sizes the create forms show "Post" and name the community in a confirmation alert before posting; the Time row stacks when it does not fit; the Town Hall card stacks the stars under the title. Verified at AX 5 on the iPhone 16 (build/p1-fix/). The alert was reviewed in code only. A width-estimation heuristic the fix agent had added for the largest standard sizes was removed before commit (an estimated constant with no device measurement); at XXL / XXXL with a long community name the button can still fold into •••, which hides but does not remove Post.
- **Finding 5** is by design (no subtitle for "All communities"); with the chevron visible it no longer looks like the baseline.

Captures: `build/p1-fix/` and `build/p1-gate/fix1-*.png` (gitignored). Simulator use for these checks followed the owner's constraint of one device at a time.
