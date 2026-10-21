# Phone-log performance pass

Date: 2026-10-20 (evening, after the first performance pass in `Docs/qa/2026-10-20-performance-pass.md`). Branch `claude/naarscars-multi-community-roadmap-f08594`. The pass starts from `f10c904`; its commits are `e639cc0` to `b665dfe` (nine `[perf]` commits, listed in section 7).

Input: an Xcode console log the owner captured on their iPhone while using a **Debug build with the debugger attached** (called "the phone log" below). It is not a clean run of a fixed sequence: it includes a message send, the Leaderboard with three periods, a trip to the background, a community switch, two bell opens and one Mark All Read.

What was measured here:

- **Debug builds on the iOS Simulator.** The owner's simulator "iPhone 16" (`CAA2F1FD`, iOS 26.5) gave the signed-in baseline at 17:19. For the run after the fixes it had no session (see "Not verified" below), so that run was done as a guest. Unit tests ran on "iPhone 16 Tests" (`34742407`, never signed in).
- **Launch times only, in Release** (item 6). No Release build was measured for the other items, and nothing was measured on a physical device.

**Not verified on a device.** The owner's simulator lost its session at about 18:30. From then on, every launch logged `session_missing_or_invalid` and opened on Welcome. Signing in was not allowed in this pass. As a result:

- Items 2, 3 and 5 and the new send sub-timings were checked by unit tests only.
- Item 4 was checked on the simulator, in guest mode.
- The review fixes (`d0e3aab` to `b665dfe`) were never installed on the owner's simulator: `simctl install` hung twice.

The next signed-in run, on the phone or on the simulator, is what will confirm items 1, 2, 3 and 5. Section 1 says what to look for.

## 1. For the owner

### What the phone log showed, in plain words

1. **A sent message took about 3 seconds to show as sent locally** (`messaging.send.localVisible` 2,975 ms; it reached the server at 3,463 ms). On the simulator the same step takes 0.2 to 0.5 s. The server part on the phone took only 0.5 s, so the 2.5 s is spent on the phone itself, between the tap and the moment the message is saved locally. The cause is not proven. This pass adds measurements, so your next run will name the slow step (item 1).
2. **The Messages list downloaded the conversation list again on almost every visit and every Back from a thread.** That happened even 2 to 7 seconds after the last download, and twice in a row when two refreshes overlapped: 8 visits cost 10 downloads (item 2).
3. **Every Community visit downloaded the whole bell list (130 rows) to look for Town Hall rows to mark read, and found none every time.** That was 10 downloads, all for nothing (item 3).
4. **The Leaderboard downloaded its rankings again on every return** (12 downloads of the pair of rankings and spotlights). Switching to Town Hall and back also reset the period to This Month (item 4).
5. **Each bell open re-synced every ride, favor and bell row**, even 9 seconds and 0 seconds after the previous full sync (item 5).
6. **The launch line `launch.syncEngineSetup - 1906.54ms` looks alarming, but it is mostly a measuring error.** The real setup work takes about 4 to 8 ms. The metric keeps counting until the first frame is on screen, and the debugger makes that part much slower (item 6, measured only, not changed).

### Request counts: phone log, simulator before, simulator after

The phone log and the simulator sequence are different runs, so the table compares the same kind of action.

- **Phone log:** the owner's iPhone, Debug, debugger attached.
- **Simulator before:** 17:19, signed in, the build installed before this pass.
- **Simulator after:** 20:14, a guest, the build of `cd14c8d`.

A guest has no conversations, bell rows or badges, so the "after" column shows item 4's fix but not items 2, 3 and 5. The last column is what the final code (`b665dfe`) should log on the next signed-in run.

| Action | Phone log | Simulator before (signed in) | Simulator after (guest) | Expected next signed-in run |
|---|---|---|---|---|
| Cold launch | 4 syncs started, 1 joined; 1 conversations download, 1 bell download (130), 1 Town Hall page, 1 dashboard sync (298 rows), 2 badge requests | S1: the same (299 rows, 2 badge requests) | 1 dashboard sync (guest views) | Unchanged; launch was not in this pass's scope. Two badge requests at launch is still open |
| Messages tab visit | 8 list appearances (7 visits and 1 Back) cost 10 conversation downloads: 3 from the tab's own staleness check, 7 forced by the list; 4 of the forced ones 2 to 7 s after a sync, 2 right after one (0 s) | S2: 1 forced download while fresh (17 s); S7b: 1 (tab check, forced call joined) | 0 (guest prompt) | At most one sync per visit. `[conversations] skipped:current \| trigger=manualReload:conversations` when a full sync started since the last push, foreground or session start and is under 30 s old; otherwise one sync. One badge request (unchanged) |
| Back from a thread | P6: 1 forced download (19 s) | S3b: 1 forced download (28 s) | Not possible as a guest | The same rule as a visit. One forced sync after a change made on this device (new thread, rename, group photo, members added, leave) |
| Community visit or community switch | 10 bell downloads of 130 rows (8 visits, 2 switches), all with nothing to clear | S4, S7c: 1 bell download each, then 1 badge request | Town Hall page only; guests skip the badge clear | No bell download when nothing in the visible community (or with no community) is unread; one `Refreshing badges (clearCommunityBadge.skipped)` instead |
| Leaderboard return | Every return refetched: 12 pairs in all; the period reset to This Month after Town Hall | S5a: 1 pair (first show) | S5a: 1 pair; S9b, a return 103 s later: **0** | 0 within 15 minutes; 1 pair for each new period or community; pull-to-refresh 1 pair |
| Back to the Town Hall segment | P22: forced Town Hall sync at 21 s | S5b: 1 page at 27 s | S5b: 1 page at 24 s; S9c: 1 at 19 s | Unchanged (still open, section 6) |
| Bell open | Two opens: 1 full dashboard sync each (298 rows plus the 130-row bell download), 9 s and 0 s after the previous full sync | S8a: 1 full sync, 23 s after the previous one | Sign In Required sheet, no request | `[dashboard] skipped:current \| trigger=manualReload:notifications` when a full dashboard sync ran since the last push, foreground or session start, under 30 s ago, and the stored rows hold every unread group the bell badge counts; otherwise one sync |
| Requests tab visit | One sync when stale; `skipped:fresh` otherwise | S7a, S7e: 1 sync each (stale), plus 1 badge request | 1 sync each (stale) | Unchanged |
| Profile visit | 1 badge request, 1 own-badges fetch | S6: the same; S7d: 1 badge request | None (guest) | Unchanged |

Totals for the counted lines:

| Line | Phone log (whole log) | Simulator before (S1 to S8) | Simulator after, guest (S1 to S8) |
|---|---|---|---|
| `Fetched N conversations via RPC` | 12 | 4 | 0 |
| `Fetched N notifications from network` (130 rows) | 15 (10 from the Community badge clear) | 6 (2 from the badge clear) | 0 |
| Full dashboard syncs | 6 (2 from bell opens) | 4 | 3 |
| Leaderboard + spotlight requests | 24 | 2 | 2 |
| `Fetched N posts from network` | 6 | 4 | 3 |
| Badge requests (`Refreshing badges`) | 14 | 11 | 0 |
| `SLOW:` lines | 1 (the send, 3,463 ms) | 0 | 0 |

No count went up in the after run. Requests, Town Hall and the Leaderboard showed their rows. No skeleton stayed up, no error showed, and no list came back short. The drops in conversations, bell downloads and badge requests in the guest column come from guest mode, not from the fixes. Raw counts: `build/phonelog/baseline-counts.md` and `build/phonelog/after-counts.md` (local, gitignored).

### What to expect on the next phone run, and what to send back

Do two runs, because they answer different questions:

- **A Debug run with Xcode attached** gives the log lines below, comparable with the phone log you sent. The send sub-timings exist only in Debug builds.
- **A Release run** (next subsection) tells you whether the app still feels laggy for a customer.

For the Debug run, sign in and repeat roughly what you did before:

1. Launch. Stay on Requests for about 15 s.
2. Open Messages, open a thread, send a short text, go Back, and open Messages again within 30 s.
3. Open Community: the Town Hall segment, then the Leaderboard, then Town Hall again.
4. Leave the Community tab and come back to the Leaderboard within a few minutes.
5. Open the bell twice within 30 s, with no push arriving in between.

Then copy these lines from the Xcode console:

- every `[refresh]` decision line: `[<domain>] started(full) | trigger=…`, `joined:inFlight`, `skipped:fresh` and the new `skipped:current`;
- `Fetched N conversations via RPC`, `Fetched N notifications from network`, `Fetched N posts from network`, `Fetched N leaderboard entries for period:`, `Fetched N spotlight entries for period:`;
- `Refreshing badges (<reason>)`;
- every `messaging.send.` line from the send (list below);
- every `launch.` line and the "Previous session metrics" block at the top;
- every `SLOW:` line.

The `messaging.send.localVisible` and `messaging.send.serverAccepted` lines carry a conversation id. Pasting them into a chat is fine, but shorten the id to 8 characters before anything goes into the repository, which is public. The new sub-timing lines carry only `hasImage` and `reply`.

What each fix should show:

| Item | Line to look for | If it is missing |
|---|---|---|
| 2 (Messages list) | On a Messages visit or a Back within 30 s of a full conversations sync, with no push in between: `[conversations] skipped:current \| trigger=manualReload:conversations` and no `Fetched N conversations via RPC` | Send the `[conversations]` lines around it |
| 3 (Community visit) | `Refreshing badges (clearCommunityBadge.skipped)` and no `Fetched N notifications from network` right after the Community tab line, when the Community badge is 0 or only counts another community | Send the `Counts synced:` line before it |
| 4 (Leaderboard) | No `Fetched N leaderboard entries` on a return within 15 minutes; the period you chose is still selected | |
| 5 (bell) | On the second bell open: `[dashboard] skipped:current \| trigger=manualReload:notifications` and no full dashboard sync | Say whether a push or an app switch came between the two opens (either one makes the next open sync, by design) |

**How to read the send sub-timings (item 1).** The step that holds the seconds names the cause. On the simulator the whole local part takes about 0.2 to 0.5 s.

| Line | What it measures | If it holds the seconds, the next fix is |
|---|---|---|
| `messaging.send.rateLimitCheck` | The hop to the rate limiter, and the wait to get back onto the main thread. On a phone the keyboard's own work can fill this wait | A synchronous per-conversation check on the main actor, before the bubble. Same limit and same refusal; it removes the only wait before the save |
| `messaging.send.haptic` | Creating and firing the tap haptic | Keep one prepared haptic generator, or fire it after the save |
| `messaging.send.imagePrepare` | Image compression and local copy (image sends only) | An image-path task |
| `messaging.send.optimisticUpsert` | Writing the new row into the local store | A separate task in the messaging repository (a fragile system) |
| `messaging.send.optimisticSave`, split into `messaging.send.save.context`, `messaging.send.save.conversationsPublish`, `messaging.send.save.messagesPublish` | Saving the store, then rebuilding the conversation list and the thread's messages | A separate repository task, aimed at whichever of the three is large |
| `messaging.send.localVisible` | Everything from the send to "saved and published" (unchanged name; this is not "on screen") | Read the lines above it |
| `messaging.send.mainActorResume` | How long the main thread stayed busy right after the save (277 ms on the simulator) | Points at work queued on the main thread, not at the send itself |
| `messaging.send.viewCommitted` | From the row's creation to the thread's view model showing it | |
| `messaging.send.snapshotApplied` | From the row's creation to the bubble being applied to the screen | |
| `messaging.send.serverCall`, `messaging.send.serverAccepted` | The network part, and the total | Already known: about 0.5 s on the phone |

### Release reminder

The numbers above come from Debug builds. Debug is unoptimized, loads the app from a debug library, and usually runs with the debugger attached. That makes SwiftUI, SwiftData and JSON decoding several times slower than in the App Store build. To judge lag the way a customer sees it, run Release on the phone:

1. Product > Scheme > Edit Scheme > Run > Info.
2. Set Build Configuration to **Release**.
3. Untick **Debug executable** (recommended).
4. Check that no sanitizer is ticked on the Diagnostics tab.
5. Run.
6. Afterwards, set it back to Debug, and do not commit the scheme file if Xcode marks it changed.

Product > Profile (Cmd+I) builds Release and opens Instruments for a Time Profiler trace. Section 1 of `Docs/qa/2026-10-20-performance-pass.md` has the full steps and the list of what to send if Release still lags.

## 2. Items

### Item 1. A sent message took 3 s to be saved locally on the phone (instrumented; cause not proven), `cd14c8d`

**Evidence.** Phone: `messaging.send.localVisible - 2974.98ms`, then `SLOW: messaging.send.serverAccepted took 3462.56ms`. That leaves 487 ms for the server part. The rest sits between the send and the end of the local save.

Simulator (owner's session, Debug), two text sends to a one-to-one thread. Both were unsent from the bubble menu afterwards, which leaves the usual "You unsent a message" rows.

- **Send 1** (installed build, app running for 26 minutes): `localVisible` 544.99 ms, `serverAccepted` 1,735.72 ms.
- **Send 2** (temporary, uncommitted log markers; app running for 1 minute): `localVisible` 214.10 ms, `serverAccepted` 1,875.54 ms.

Send 2's breakdown:

| Step | Time |
|---|---|
| Tap handler (clearing the text view 36 ms, resizing the text field 17 ms) | 60 ms |
| Rate-limit hop | 8 ms |
| Haptic | 11 ms |
| Writing the row into the store (upsert) | 106 ms |
| Store save | 66 ms |
| Conversation-list rebuild | 14 ms |
| Messages re-read | 9 ms |
| Main thread busy after `localVisible` | 277 ms |

- The bubble reached the screen 549 ms after the send started (614 ms after the tap).
- On the server side, the insert round trip took 785 ms and a second round trip, which updates the conversation's `updated_at`, took 534 ms.

**Cause.** Not proven. The candidates, ranked:

1. A wait for the main thread at the first suspension point, the hop to the rate limiter. On the phone the software keyboard is up, and the phone log's keyboard lines fall in exactly this window.
2. The local save, which runs synchronously on the main thread: the upsert (including the inverse relationship to the conversation), the store save, and the two publisher rebuilds with their subscribers. It may run much slower on a device with the debugger attached.
3. The haptic. A new generator is created and fired on every send; on a device this starts the Taptic Engine.
4. A write-lock wait in the save, if a background sync transaction was open. Nothing was logged in that window on the phone.
5. The debugger, multiplying all of the above.

Ruled out by the code and the measurements: no network call, typing request, Keychain read or `UserDefaults` synchronize is awaited before the insert.

**Fix.** Measurements only, all inside `#if DEBUG`, so Release builds contain none of the timing code:

- Twelve new `PerformanceMonitor` keys (the table in section 1).
- Each key's time comes from timestamps taken synchronously at its step, and all of them are recorded in one detached utility-priority task. That task runs after the local save, after the server call, and on each early return.
- No new wait was added before the insert.
- `MessagingRepository.save` fills a DEBUG-only `lastSaveTimings` and keeps its three steps in the same order for every caller.

The behavior fix waits for the phone run; section 1 lists the minimal change for each outcome. The send-path rules still hold: the row is saved as `sending` before the network call, there is one inline `MessageService` call, the status changes are unchanged, and no drain trigger was added.

**Test.** `MessageSendManagerSendPathTests` (inside `MessageServiceTests.swift`, because new files cannot be added to the project). It runs on an in-memory store with the network stubbed, and asserts that:

- the row is in the store with status `sending` when the insert request arrives;
- the server row then replaces it as `sent`;
- each of the nine text-send keys has one sample.

With the local save removed, the test fails (`[]` instead of `["sending"]`).

**Proof on the simulator.** The test host, with the server stubbed:

| Key | ms |
|---|---|
| `rateLimitCheck` | 0.48 |
| `haptic` | 5.87 |
| `optimisticUpsert` | 8.67 |
| `optimisticSave` | 26.83 |
| `save.context` | 23.94 |
| `save.conversationsPublish` | 2.33 |
| `save.messagesPublish` | 0.53 |
| `localVisible` | 42.43 |
| `mainActorResume` | 0.29 |
| `serverCall` (stub) | 80.43 |
| `serverAccepted` | 170.62 |

`viewCommitted` and `snapshotApplied` need a screen and have not been seen yet.

### Item 2. The Messages list fetched on every appearance, `e639cc0`, then `d0e3aab` and `a534c98`

**Evidence.** Phone: 8 list appearances cost 10 conversation downloads: 3 from the tab's own staleness check (`tabAppear`) and 7 forced by the list (`manualReload:conversations`).

- 4 of the forced ones ran while the data was fresh: P4 at 2 s, P13 at 4 s, P16 at 3 s, P20 at 7 s.
- 2 ran right after a `tabAppear` sync had finished (`hydrated(0s ago)`, P11 and P24).
- 1 was the Back from a thread (P6, 19 s).

Simulator:

- S2: `skipped:fresh | trigger=tabAppear | state=hydrated(17s ago)`, then `started(full) | trigger=manualReload:conversations`.
- S3b (Back): a forced sync at 28 s.

**Cause.** The list's `.task` called `loadConversations()` on every appearance, and that always ended in `forceFullRefreshAndWait(.conversations, …)`, gated only by a 2 s minimum. `MainTabView.onChange(of: selectedTab)` had already asked the coordinator for the staleness-gated sync. So:

- if the data was fresh, the list fetched anyway;
- if the tab's sync finished while the list was loading profiles, a second fetch followed it at once.

The list does not need the network to appear. Every coordinator save, send and realtime receive already reaches it through the repository publisher.

**Fix, as it stands at `b665dfe`.**

- `loadConversations(trigger:forceRemote:)` gained `forceRemote`. Pull-to-refresh, the error Retry and the reload after composing pass `true` and always sync.
- The appearance passes `false`. It shows the stored rows, loads the missing profiles, and then calls `forceFullRefreshAndWait(.conversations, trigger: "manualReload:conversations", unlessCurrent: true)`. The coordinator answers that call in one of three ways:
  - it skips when a full sync started after the last push, foreground or session start and is inside the 30 s window, which covers the tab's sync or the launch sync;
  - it joins a sync in flight;
  - otherwise it runs one sync.

  A skip returns at once.
- `e639cc0` first returned before any coordinator call. The review found two problems with that (section 4): a new thread could be missing, and Back no longer refreshed anything. `d0e3aab` moved the appearance to the `unlessCurrent` call.
- `d0e3aab` also covers changes made on this device, which no push reports. The view model watches `.conversationUpdated` posts that carry no message, and such a post makes the next appearance force one sync.
  - `ConversationService.createConversationWithUsers` posts one after a successful create, which covers the profile, ride, favor and compose paths.
  - Rename, group photo, leave, remove and delete already posted one.
  - `a534c98` makes adding members post one too.
- The view model takes the coordinator by injection (`nil` means `.shared`) for the tests.

Rules kept: the coordinator owns every conversations fetch and its in-flight dedup, the view model calls only `forceFullRefreshAndWait`, and no trigger was added. `loadMutedConversations()` still runs on every appearance. Loading it once would go stale after a mute set from a thread's details, or after a timed mute expires.

**Tests.** `ConversationsListViewModelTests` (class: 15 of 15 passed):

- `testAppearanceAfterASyncDoesNotForceAnotherConversationsSync`
- `testFirstEmptyAppearanceWaitsOnTheCoordinator`
- `testAppearanceAfterALocalConversationChangeForcesOneSync`: a post with a message does not force a sync; a post without one forces one.
- `testAppearanceSyncsWhenTheLastFullSyncIsOutsideTheWindow`

The first fails with the guard disabled; the last two fail with `e639cc0`'s guard put back. `a534c98` is not unit-tested, because the participant service is the shared network singleton.

**Proof on the simulator.** None signed in. As a guest the Messages tab shows the sign-up prompt and makes no request.

### Item 3. A Community visit downloaded the whole bell list, `2f9fdac`, then `b665dfe`

**Evidence.** On the phone the Community count was 1 throughout. There were 10 downloads of 130 bell rows from `clearCommunityBadge` (8 visits and 2 community switches), all with nothing to clear; 4 logged `clearCommunityBadge.noop` and the others were debounced. On the simulator (Community count 0), S4 and S7c each logged `Fetched 130 notifications from network`, then `Refreshing badges (clearCommunityBadge.noop)`.

**Cause.** `BadgeCountManager.clearCommunityBadge(visibleCommunityId:)` always fetched the bell list (up to 200 rows). The list's 2 s cache almost never covers a tab visit. Only after the download did it look for unread Town Hall rows in the visible community or with no community.

The badge request already says whether anything can be cleared. `get_badge_counts` returns two counts:

- `community_total`: every unread Town Hall row;
- `community_details`: a per-community total for every community with unread rows.

`community_total` minus the sum of the per-community totals is the number of unread rows with no community.

**Fix.**

- `communityClearNeedsFetch(_:visibleCommunityId:countsAreCurrent:)` decides whether a fetch can find something. It fetches when:
  - the visible community has unread rows;
  - rows with no community are unread;
  - there is no visible community and anything is unread;
  - the counts are stale, failed or not loaded yet.

  An old server without `community_details` gives an empty map, so the client fetches whenever anything is unread.
- When the guard says skip, the visit makes one badge refresh (`clearCommunityBadge.skipped`) and decides again on the new counts. A row that arrived with no push is then still cleared on this visit.
- `b665dfe` makes that refresh bypass the 5 s debounce, after a review finding (section 4). It costs one badge request per Community visit or switch, as the old path did, and saves the bell download.
- The client computes no badge; the counts only decide whether to fetch. Push-driven refreshes keep the debounce, and the 5-minute safety poll is unchanged.

**Tests.** Seven `BadgeCountManagerTests` cases for the guard:

- nothing unread;
- the visible community unread;
- only another community unread (the phone's case);
- rows with no community;
- no visible community;
- a server without details;
- counts not current.

Class: 20 of 20 passed. The refresh-then-decide-again path and `b665dfe` are not unit-tested, because `BadgeCountManager` is the shared singleton calling the request directly.

**Proof on the simulator.** None. Guests skip the badge clear, so the guest run does not reach it.

### Item 4. The Leaderboard refetched on every return, `5519824`

**Evidence.** Phone: 12 pairs of `get_community_leaderboard` and `get_community_spotlights`. With the Leaderboard left on All Time, every Community return refetched All Time (P10, P14, P17, P21). In P22, after the Town Hall segment, it came back on This Month.

**Cause.**

1. `CommunityTabView` builds `LeaderboardView` only while its segment is selected, and the view owned its view model, so every return from Town Hall made a new view model with an empty cache and the period reset.
2. Even with the same view model, every appearance on a cache hit inside the 15-minute window still started a background refetch.

**Fix.**

- `CommunityTabView` owns the `LeaderboardViewModel` (`@StateObject`, created once) and passes it to `LeaderboardView` as `@ObservedObject`.
- A cache hit within `Constants.CacheTTL.leaderboard` (15 minutes) shows the cached rows and returns.
- `LeaderboardFetching`, in `LeaderboardService.swift`, is the test seam.

What stays the same:

- The cache is keyed by period and community.
- Pull-to-refresh still drops the key and fetches.
- A community switch picks another key.
- The view model is released with `MainTabView` at sign-out.
- No coordinator call was added.

Two visible changes for the owner to accept:

- The chosen period now survives a segment switch within a session.
- Rankings can be up to 15 minutes old unless pulled to refresh.

**Tests.** `LeaderboardViewModelTests` (stubbed):

- `testLoadLeaderboard_CacheHitWithinTTLDoesNotFetchAgain`
- `testRefresh_FetchesEvenWithAFreshCache`
- `testPeriodChange_FetchesEachPeriodOnceThenUsesCache`

The first and third fail with the background refetch put back.

**Proof on the simulator** (guest, read only):

- The fix stage: This Month cost 1 pair and All Time 1 pair. Then Town Hall and back, Requests and back, and This Month again cost **0**, with All Time kept. Pull-to-refresh cost 1 pair.
- The after run: S9b, a return 103 s after the first show, cost **0** requests, and the rows appeared at once.

### Item 5. Every bell open forced a full dashboard sync, `37f395b`, then `2dfbccf`

**Evidence.** Simulator S8a: `[dashboard] started(full) | trigger=manualReload:notifications | state=hydrated(23s ago)`, then `Fetched 130 notifications from network` and a 299-row sync, with no push since the previous full sync. Phone: bell opens at `hydrated(9s ago)` and `hydrated(0s ago)`, a 298-row sync each.

**Cause.** `loadNotifications()` always ended in `forceFullRefreshAndWait(.dashboard, "manualReload:notifications")`.

A plain staleness gate would have been a regression, because pushes do not bring bell rows into the local store:

- A dashboard push runs a targeted sync that fetches only the ride or favor, but still marks the whole domain fresh.
- Town Hall, announcement and broadcast pushes map to Town Hall only.

So the forced sync on open is what brings a just-pushed bell row into the list. Opening the bell marks nothing read, so badges need nothing.

**Fix.**

- **The coordinator.** `RefreshCoordinator.forceFullRefreshAndWait(_:trigger:unlessCurrent:)` gained a parameter (default `false`, so every existing caller is unchanged). With it set, the coordinator logs `skipped:current` and returns `.skipped(.fresh)` only when all of these hold:
  - nothing is in flight;
  - the domain is fresh;
  - the last full sync started after the last server signal (any `performTargetedRefresh`, which only push paths call, an app foreground, or a session start) and is inside the 30 s window.

  A full sync counts from its start, so a push during the fetch defeats the skip. Targeted syncs never count, and `reset()` clears the new state.
- **The bell.** It passes `unlessCurrent` only when it is not a pull-to-refresh and the stored rows hold at least as many unread groups as the server's `bell_total` (`2dfbccf`, after a review finding, section 4). Groups are counted with `NotificationGrouping.groupBellNotifications`, the grouping the list draws. The badge is read through `BadgeCountManaging.bellBadgeCount` (read only).
- **Retry** passes `forceRefresh: true`, so it always reaches the network.
- **Announcements**, which use the same view model, skip the same way. Their Retry follows a failed sync, and a failed domain always syncs.

The coordinator still owns the dashboard fetch and its in-flight dedup (an in-flight sync is joined, never skipped or cancelled), and the view model calls only `forceFullRefreshAndWait`. The change to the coordinator API needs the owner's approval; section 6 lists it.

**Tests.**

- `RefreshCoordinatorTests`, seven cases:
  - skips right after a full sync;
  - runs again after a push;
  - runs again after a push during the sync;
  - runs again after a foreground;
  - runs again after a session start;
  - runs when the sync is older than the window;
  - the default still forces.
- `NotificationsListViewModelTests.testOpenSkipsTheDashboardSyncRightAfterAFullSync`: fails with the gate disabled.
- `NotificationsListViewModelTests.testOpenSyncsWhenTheBadgeCountsAGroupTheStoredRowsLack`: three unread rows of one ride; a badge of 1 skips, a badge of 2 syncs. It fails with a raw row count.

**Proof on the simulator.** None. A guest's bell shows the Sign In Required sheet.

## 3. Item 6. Launch metrics: Debug versus Release (measured, not implemented)

Phone (Debug, debugger attached), from the current launch, with the previous session's figures in brackets:

| Metric | ms |
|---|---|
| `launch.syncEngineSetup` | 1,907 (1,862) |
| `launch.appInit` | 3,086 (3,550) |
| `launch.performCriticalLaunch` | 1,585 |
| `launch.approvalCheck` | 374 |
| `launch.initialContentTask` | 4,652 |
| `launch.deferredLoading` | 1,925 |

The log prints `initializing -> checkingAuth` before the `syncEngineSetup` line.

**Why the number is wrong.** Both `launch.syncEngineSetup` and `launch.appInit` compute their duration with `Date()` inside a `Task { … }` on the main actor. That task first runs only when the main thread is free, which is after:

- the app finishes launching;
- the scene connects;
- the first SwiftUI update and frame;
- the start of `ContentView`'s launch task.

So both metrics end at about the first frame, 3 to 4 ms apart. The real main-thread cost of `setupSyncEngines`, sampled at 1 ms, is 8 samples in Debug and 4 in Release: the main context, three repository setups, the engine singletons and the three background actor inits together come to about 4 to 8 ms.

Simulator "iPhone 16 Tests", signed out, launched with `simctl` (no debugger), all times in ms:

| Run | Build | syncEngineSetup (reported) | appInit (reported) | init start to setup start | setup start to `UIApplicationMain` | setup start to checkingAuth | process start to checkingAuth |
|---|---|---|---|---|---|---|---|
| 1 | Debug | 525 | 706 | 178 | 49 | 504 | 1,663 |
| 2 | Debug | 526 | 706 | 178 | 55 | 494 | 1,687 |
| 3 | Debug | 613 | 790 | 175 | 61 | 570 | 1,886 |
| sampler attached | Debug | 1,837 | 2,231 | 390 | 889 | 1,798 | 3,938 |
| 1 | Release | 265 | 436 | 167 | 25 | 249 | 904 |
| 2 | Release | 273 | 442 | 166 | 21 | 219 | 640 |
| 3 | Release | 264 | 455 | 190 | 23 | 247 | 689 |
| sampler attached | Release | 643 | 877 | 232 | 66 | 616 | 2,935 |

- Release about halves the reported numbers.
- With a sampler attached, Debug reports 1,837 ms, close to the phone's 1,907 ms with the debugger.
- Host load (1-minute average) was 4.1 to 6.2 during these runs.

Where the real time before setup goes, in samples from the app's init (Debug / Release):

| Step | Debug | Release | Notes |
|---|---|---|---|
| `createModelContainer` | 108 | 93 | Mostly SwiftData building its schema by reflection (about 75 / 65); opening the store is about 17 |
| `FirebaseApp.configure` | 68 | 48 | |
| `AppState` → `AuthService` → `SupabaseService` property initializers | 54 | 25 | Outside every metric today |

**Recommendation (not implemented):**

1. **Fix the two metrics** (low risk, not a fragile system). Read the elapsed time synchronously before the `Task`, for example `let elapsed = Date().timeIntervalSince(setupStart)`, then record `elapsed` inside it, and do the same for `appInit`. If the time to the first frame is still wanted, record it under its own name, such as `launch.firstMainActorTurn`. Optionally also time the property initializers.

   After the fix, the "Previous session metrics" will show `syncEngineSetup` at about 5 to 10 ms and `appInit` at about 170 to 250 ms. Say in the commit that this corrects the measurement and is not a speed-up.
2. **Do not move `setupSyncEngines` or the background actor inits.** They take 4 to 8 ms. Fragile Systems 6 requires setup once per container, before `startSync` and before any view, view model, push handler or deferred launch work touches a repository or engine, and `clearLocalDataAndRetry` calls it again with a new container. Moving it saves nothing measurable and opens a race on a nil context.
3. **Keep `createModelContainer` on the main thread for now** (about 90 to 110 ms, mostly schema reflection that Release barely changes). The only way off the main thread is to build the container in a detached task, keep `LoadingView` up meanwhile, then run `setupSyncEngines` and inject the container. Consider that only if Release measurements on a device say launch is still slow.

## 4. Review findings and outcome

Two independent read-only reviews read the five item commits (`e639cc0`, `2f9fdac`, `5519824`, `37f395b`, `cd14c8d`) and every code path they touch. Each finding was checked against the code before anything changed, and all five were confirmed.

| # | Finding (severity, commit reviewed) | Outcome | Commit |
|---|---|---|---|
| 1 | Messages list: a thread started outside the Messages tab (from a profile, ride or favor) within 30 s of the last full sync was missing from the list. Only a conversations sync stores a conversation row, and the creator gets no push (medium, `e639cc0`) | Fixed. The appearance asks the coordinator with `unlessCurrent: true` instead of returning. A `.conversationUpdated` post without a message (posted after a successful create) makes the next appearance force one sync | `d0e3aab` |
| 2 | Messages list: Back from a thread no longer refreshed it. A rename, group photo or added members stayed stale, and a push-off user's other threads waited up to 60 s for the poll (low, `e639cc0`) | Fixed. Rename, photo and leave already posted `.conversationUpdated`; adding members now posts one too. For push-off users, a Back syncs whenever no current full sync covers it | `d0e3aab`, `a534c98` |
| 3 | Bell: an open could skip while a Town Hall bell row waits for its batched push. The row is written at once, but its push is queued for up to 5 minutes, so the badge counts a row the list lacked (low, `37f395b`) | Fixed. The open skips only when the stored rows hold at least as many unread groups as `bell_total`. The review proposed a raw unread count, which was not used: three unread rows of one ride are one group, so the raw count would hide a missing second group | `2dfbccf` |
| 4 | Community visit: the decision refresh was debounced, so a Town Hall row created a few seconds before the visit was not cleared, and the badge later showed 1 for a feed already viewed (low, `2f9fdac`) | Fixed. The skip branch's refresh bypasses the debounce: one badge request per visit or switch, and still no bell download | `b665dfe` |
| 5 | Messages list (second reviewer): Back from a thread no longer refreshed it, so your own rename or group photo, and messages in a muted thread, stayed stale (medium, `e639cc0`) | Covered by finding 1's fix. Rename and photo post `.conversationUpdated`, so Back forces one sync, which writes them through the sync path. A muted thread waits at most the 30 s window. The proposed local write of the title and photo was not made: it would add a second writer of the stored conversation outside the sync path, in a high-risk file | `d0e3aab` |

Both reviews found the other commits sound. Their main points:

- the coordinator still owns every fetch and joins in-flight syncs;
- every push path sets the server signal;
- a failed sync never counts as current;
- the badge guard matches the server's counting exactly;
- the Leaderboard view model is rebuilt at sign-in and sign-out;
- the send timings add no wait before the save and compile out of Release.

Residuals the fixes leave, stated plainly:

- A thread created before the Messages list has been opened in this session, within 30 s of the launch sync, is not flagged. The first visit then waits up to the 30 s window.
- A store that cannot hold every unread bell row (over the fetch limit or the window) syncs on every bell open, as it did before this pass. A missing row inside a group that is already unread is not detected.
- A bell row created without a push to this device (push off, or a muted type) can still be missing for at most 30 s after a full dashboard sync, when the badge counts were also refreshed before the row arrived.
- Messages in a muted thread appear on Back after at most 30 s, where every Back used to sync.

## 5. Verification

| Tree | Build | Unit suite on "iPhone 16 Tests" (cases / passed / failed / skipped) |
|---|---|---|
| `e639cc0` | Debug: 0 errors, no warnings in the touched files | 759 / 726 / 0 / 33 |
| `2f9fdac` | Debug: 0 errors | 766 / 733 / 0 / 33 |
| `5519824` | Debug: 0 errors | Targeted only: 11 cases, 7 passed, 4 session-gated skips |
| `37f395b` | Debug: 0 errors | 777 / 744 / 0 / 33 |
| `cd14c8d` | Debug and Release: 0 errors. Unique warnings: Debug 71, Release 70, the same sets as before the pass | 778 / 745 / 0 / 33 |
| **`b665dfe` (final)** | Debug: 0 errors, warning lines unchanged (316). Release: 0 errors, 70 unique warnings, identical by file and message to `cd14c8d` and to the build before the pass | **781 / 748 / 0 / 33** (`build/phonelog/suite-review.xcresult`) |

- The bar before the pass was 757 cases, 724 passed. The 24 new cases all pass: item 2 four, item 3 seven, item 4 three, item 5 nine, item 1 one.
- The 33 skips are the same session-gated set as before, checked class by class.
- Each new test that guards a behavior was run red against the old code (noted per item).
- A signed-in unit run was not done (it writes to the live app).
- Nothing was seen on a device for items 1, 2, 3 and 5.

## 6. What remains open

| # | Item | Notes |
|---|---|---|
| 1 | Signed-in checks of items 2, 3 and 5, and the send sub-timings with a real network and a screen (`viewCommitted`, `snapshotApplied`) | Section 1 lists the lines. The owner's simulator has had no session since about 18:30. Before that the app got 42501 on `get_badge_counts` and `get_conversations_with_details` at 18:30, 18:36 and 18:41; the cause was not investigated |
| 2 | The cause of the phone's 3 s local send | Waits for the phone run. The minimal fix for each outcome is in section 1 |
| 3 | Item 6: correct `launch.syncEngineSetup` and `launch.appInit` | Recommended in section 3, not implemented |
| 4 | Owner approval of `forceFullRefreshAndWait(_:trigger:unlessCurrent:)` | An additive coordinator parameter, used by the bell and the Messages list appearance. CLAUDE.md's Current State names it; the Canonical Entry Points table is not changed |
| 5 | Returning to the Town Hall segment forces a full Town Hall sync while fresh (S5b at 27 s and 24 s, S9c at 19 s, phone P22 at 21 s) | Item 9 of the first report. `unlessCurrent: true` in `TownHallFeedViewModel`, or lift its view model as item 4 did |
| 6 | Two badge requests at every launch (`init` and `mainTabAppear`) | Item 7 of the first report. Two concurrent refreshes both pass the debounce, because it is set only after the request returns. Fragile system |
| 7 | One badge request (with per-community details) on almost every tab switch: `clearRequestsBadge`, `clearMessagesBadge` without an id, and `clearProfileBadge` | A badge-freshness decision for the owner |
| 8 | `loadMutedConversations()` runs a network select on every Messages list appearance | Not done in item 2; a once-per-lifetime set would go stale (section 2) |
| 9 | The Community badge can stick at 1 | On the phone it survived 10 visits and a community switch until Mark All Read. Likely cause: an unread Town Hall row in a community the person no longer has active, which `community_total` counts but no screen clears. Not verified; the row has since been marked read |
| 10 | Pushes do not bring bell rows into the local store | A dashboard push's targeted sync fetches only the ride or favor but marks the domain fresh; Town Hall and announcement pushes skip the dashboard. This also affects the "unseen request" keys. The bell's open check relies on the push signal and the badge's group count instead |
| 11 | For about 0.2 s after a send, the thread can hold the local row and the server's copy | Seen in a simulator log. The realtime echo of the server row (a new id) was committed before the local row was replaced. Same root as the deferred idempotent insert ("E5b") |
| 12 | `MessageService.sendMessage` makes a second round trip to update `conversations.updated_at` (534 ms on the simulator), which the database trigger already does | It is also one of the paths where an insert that committed is reported as failed (Audit Notes risk (a)). Fragile system, out of scope |
| 13 | When the conversations request was denied, the fallback `ConversationService.fetchCreatedConversations` failed with a decoding type mismatch ("expected String, found an array") | Seen in the 18:30 history log; not touched |
| 14 | `MyProfileView` refetches user badges on every visit for a person with no badges | Not the owner's case |
| 15 | `LeaderboardFetching` lives in `LeaderboardService.swift`, not `Core/Protocols/` | New files could not be added. `CommunityTabView` now re-renders on each Leaderboard update (about 8 per load); no loop |
| 16 | Not unit-tested: `a534c98` (members added) and `b665dfe` (the debounce bypass) | Both depend on shared singletons with no seam |
| 17 | Environment | The host's sandbox refused simulator processes read access to `/Volumes/DevSSD` from about 16:36, so every new simulator process crashed at launch. It was fixed with `killall -9 com.apple.CoreSimulatorService`, and the Full Disk Access entry may need the owner's check. In the review-fix stage `simctl install` hung twice under memory pressure. The working tree still has the owner's uncommitted build-number change in `project.pbxproj` (11 to 12) |

## 7. Impact summary

| Commit | Files | Fragile system or seam | What would have broken if a consumer were missed |
|---|---|---|---|
| `e639cc0` | `ConversationsListViewModel.swift`, `ConversationsListView.swift`, `ConversationsListViewModelTests.swift` | Coordinator consumer | A list that never syncs on appearance (review finding 1, fixed in `d0e3aab`) |
| `2f9fdac` | `BadgeCountManager.swift`, `BadgeCountManagerTests.swift` | Badge counts | A Community badge that no visit clears, if the guard skipped while something was clearable. It fetches whenever the counts are stale or say a clearable row exists |
| `5519824` | `CommunityTabView.swift`, `LeaderboardView.swift`, `LeaderboardViewModel.swift`, `LeaderboardService.swift`, `LeaderboardViewModelTests.swift` | No | A Leaderboard that never refreshes. Pull-to-refresh and the 15-minute window still fetch |
| `37f395b` | `RefreshCoordinator.swift`, `NotificationsListViewModel.swift`, `NotificationsListView.swift`, `RefreshCoordinatorTests.swift`, `NotificationsListViewModelTests.swift` | `RefreshCoordinator` (high-blast-radius) | A caller relying on `forceFullRefreshAndWait` always syncing. The default is unchanged, and only the bell and the Messages list pass `unlessCurrent` |
| `cd14c8d` | `MessageSendManager.swift`, `MessagingRepository.swift`, `ConversationDetailViewModel.swift`, `MessagesViewController.swift`, `MessageServiceTests.swift` | Send path, repository (DEBUG only) | A wait added before the local save, or a changed save order. Neither happened (test and review) |
| `d0e3aab` | `ConversationsListViewModel.swift`, `ConversationsListView.swift`, `ConversationService.swift`, `ConversationsListViewModelTests.swift` | Coordinator consumer | A local change with no `.conversationUpdated` post stays stale for up to 30 s. Create, rename, photo, members, leave, remove and delete all post one |
| `a534c98` | `MessageDetailsViewModel.swift` | No | An untitled group's row keeps the old names after members are added |
| `2dfbccf` | `BadgeCountManaging.swift`, `BadgeCountManager.swift`, `NotificationsListViewModel.swift`, `NotificationsListViewModelTests.swift` | Badge protocol (read only) | Another `BadgeCountManaging` conformer would need `bellBadgeCount`. The only one is `BadgeCountManager` (the test stubs add it) |
| `b665dfe` | `BadgeCountManager.swift` | Badge counts | A push burst bypassing the debounce. Only the user-driven Community visit bypasses it |
