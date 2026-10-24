# Performance pass: baseline, findings, fixes

Date: 2026-10-20 (baseline measured 2026-10-19, 21:03 to 21:44). Branch `claude/naarscars-multi-community-roadmap-f08594`. Baseline taken at `0af6e16`; the last fix of the pass is `5fffcd6`, and the review follow-ups (`4812026` to `8d174ca`) are under "Review follow-ups" in section 6. Everything below was measured in a **Debug build on the iOS Simulator**. No Release build and no physical iPhone was measured.

## 1. For the owner: Debug versus Release on your phone

An Xcode "Run" installs the scheme's Run configuration. In this project the shared scheme `NaarsCars.xcscheme` has the Run action on **Debug** (`LaunchAction buildConfiguration = "Debug"`). Debug builds are compiled with `SWIFT_OPTIMIZATION_LEVEL = -Onone` (no compiler optimization), load the app code from `NaarsCars.debug.dylib`, and run with the debugger attached. SwiftUI, SwiftData and JSON decoding are often several times slower unoptimized, so a Debug build on a phone can feel laggy in places a shipped build does not. The App Store build is a Release build. The numbers in this report are Debug numbers, so absolute milliseconds are higher than what a customer sees. What moved off the main thread, and which requests no longer happen, hold in Release too.

To judge lag on your phone, run Release:

1. In Xcode choose Product > Scheme > Edit Scheme (Cmd+<), select **Run** on the left, open the **Info** tab.
2. Set **Build Configuration** to **Release**.
3. Optional but recommended: untick **Debug executable**. The app then runs without the debugger attached. (You can also stop the run and open the app from the Home screen.)
4. On the **Diagnostics** tab, check that no sanitizer or extra runtime checker is ticked.
5. Run on the phone. Set the configuration back to Debug afterwards, and do not commit `xcshareddata/xcschemes/NaarsCars.xcscheme` if Xcode marks it changed.

Product > Profile (Cmd+I) already builds Release (the scheme's Profile action is Release) and opens Instruments, so Time Profiler runs against an optimized build without editing the scheme.

If Release still lags, send:

- the phone model and iOS version;
- which screen and which action (tab switch, scrolling Town Hall, opening a thread, launch), and whether it happens on every try or only the first after launch;
- roughly how long a stall lasts, ideally a screen recording (Control Center > Screen Recording);
- whether Low Power Mode was on, and whether Xcode was attached;
- a Time Profiler trace taken with Product > Profile while the stall happens (this is the data this pass could not collect, see section 3).

## 2. Summary

- Eight distinct findings were confirmed (eleven reports, three of them duplicates), seven reports were refuted, and each confirmed finding has a `[perf]` commit.
- None of the confirmed costs was introduced by Phases 1 to 5. Each pattern existed at the merge base `f164a0f` or earlier. The verifiers found no cost that Phases 1 to 5 added; some phase code made an existing pass heavier, but that path (`countOutsideScope`) does not run for the owner's scope.
- The largest measured cost was image decoding in lists: on a 30 s Town Hall scroll the main thread spent 874 of 1,239 non-idle samples (about 1.15 s) blocked on JPEG decode, and the process footprint reached about 1 GB. After the fix those samples are 0 and the footprint stayed at 86 MB.
- Every dashboard and Town Hall sync write ran on the main thread (13 to 80 ms per dashboard sync). It now runs off it.
- Not measured: Release, a physical device, cold-launch time after the fixes, and tab-switch latency in seconds after the fixes. See section 7.

## 3. What was measured and how

| Item | Detail |
|---|---|
| Owner device | "iPhone 16" simulator `CAA2F1FD-2908-4CE5-8F52-BC3DAD9E066F`, iOS 26.5, signed in as the owner (three memberships). Used read only: launch, tab switches, scrolling, opening screens. No send, post, claim, setting change, sign-out or deletion. In-app theme (Dark) and text size (`large`) were left as found. |
| Test device | "iPhone 16 Tests" (`34742407…`), never signed in. Used for all `xcodebuild test` runs; shut down by name afterwards. |
| Build | Debug, `-sdk iphonesimulator`, `NaarsCars.debug.dylib`, one DerivedData (`build/DerivedData`). One `xcodebuild` at a time. |
| Host | MacBook Pro, 8 GB RAM, swap already 8.5 of 9.2 GB used before profiling. Load average is recorded beside each number. It was 2.2 to 5.4 in the baseline and 1.7 to about 30 in the fix runs; sampling waited when load was above 30. |
| Profiler | `xctrace record --template "Time Profiler"` refused to attach to the simulator app (by pid, by name, and through the host device), so there is no `.trace` file. The substitute was `/usr/bin/sample <pid> <seconds> 1` (1 ms interval; the effective interval was 1.3 to 1.5 ms per sample), summarized with scripts. |
| Other sources | `top -pid` for CPU and memory, `xcrun simctl io <udid> screenshot` bursts for launch and tab-switch timing, `xcrun simctl spawn <udid> log stream` for the `[performance]`, `[refresh]` and per-domain log lines and CFNetwork task counts. The baseline stream ran at debug level, which adds system-framework logging overhead to every number; the fix runs used info level for subsystem `com.naarscars.app`. |

Commands:

```
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,id=<Tests UDID>' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120
/usr/bin/sample <pid> <seconds> 1
top -pid <pid> -l <n> -s 2
xcrun simctl io <udid> screenshot <file>
xcrun simctl spawn <udid> log stream --level info --predicate 'subsystem == "com.naarscars.app"'
```

Captures are in `build/perf/` (gitignored, local to the Mac). Main files: `baseline.md`, `owner.log`, `requests-tabswitch.sample.txt`, `community-tabswitch.sample.txt`, `scroll-townhall.sample.txt`, `scroll-thread.sample.txt`, `after-*.sample.txt`, and one `fix-*` or `verify-*` folder per finding.

## 4. Baseline (commit `0af6e16`, Debug, owner's simulator)

### Cold launch (`simctl terminate`, 3 s pause, `simctl launch`)

| Run | Host load | First app log (s) | `ready_authenticated` (s) | First main-UI frame, skeleton (s) | Content frame (s) | Skeleton until content |
|---|---|---|---|---|---|---|
| cold1 | 3.54 | 2.89 | 5.13 | 5.85 to 6.29 | 6.92 to 7.43 | about 1.1 s |
| cold2 | 5.38 | 1.33 | 3.43 | 3.91 to 4.23 | 5.27 to 5.48 | about 1.2 s |
| cold3 | 2.22 | 1.00 | 2.48 | 3.06 to 3.36 | 4.14 to 4.41 | about 1.05 s |

`launch.approvalCheck` was 572, 857 and 456 ms (the first two over the 500 ms threshold). From `ready_authenticated`, the main actor stayed busy for 568 to 750 ms with the first `MainTabView` render.

### Idle CPU (every tab, two rounds of 4 samples each)

Every tab's mean was 0.0 to 0.2 % except Community round 1 (2.7 %), whose one 10.8 % sample was the 5-minute safety poll. No render loop. Idle windows made 0 HTTP requests apart from the safety poll (9 to 13 requests per 5 minutes).

### Scrolling (CPU as % of one host core, during repeated swipes)

| Surface | Mean | Peak | Footprint | Host load |
|---|---|---|---|---|
| Requests, My Requests list (2 runs) | 16.5 %, 15.9 % | 25.7, 28.2 | 321 to 435 MB, swinging about 56 MB per swipe | 2.5 to 2.9 |
| Town Hall feed (3 runs) | 25.3 %, 16.8 %, 15.5 % | 46.3, 28.8, 26.6 | 380 to 896 MB, peak 925 MB | 2.7 to 3.4 |
| Message thread, UIKit (2 runs) | 6.5 %, 12.6 % | 8.8, 20.9 | 847 to 850 MB | 2.3 to 2.7 |

### Tab-switch latency (screenshot burst)

| Switch | First frame of new content | Settled | Host load |
|---|---|---|---|
| Messages to Community | +0.75 to +1.04 s | +1.5 to +1.8 s | about 2.3 |
| Community to Requests | +0.43 to +0.63 s | +1.25 s | about 2.3 |
| Requests to Community | +0.58 to +0.83 s | +1.22 s | about 2.3 |

### HTTP tasks in the 12 s after a tab tap (domain more than 30 s stale)

| Switch | HTTP tasks | What was logged |
|---|---|---|
| to Messages (2 runs) | 6, 5 | two full conversation RPCs back to back (`tabAppear`, then `manualReload:conversations`) |
| to Community (4 runs) | 15, 15, 15, 15 | posts fetched twice, `get_badge_counts` twice, 122 notifications refetched |
| to Requests (3 runs) | 9, 8, 9 | dashboard sync of 290 rows, 1.7 to 2.7 s wall |
| to Profile | 10 (first visit), 1 | badge clear, leaderboard badges |

### Main-thread profiles (`sample`)

| Profile | Main-thread samples | Busy | Largest items |
|---|---|---|---|
| Town Hall scroll, 30 s, 12 swipes (load 2.89 to 2.95) | 20,621 at 1.455 ms | 11.5 % (2,379 samples, 3.46 s) | 793 samples (about 1.15 s) blocked in `-[_SwiftUIProxyImage finish]`; off main, 923 samples of JPEG decode on `com.apple.SwiftUI.prepare-image`; app code 22 samples |
| Requests tab switch with dashboard sync, 10 s (load 2.3 to 2.9) | 6,830 at 1.464 ms | 8.6 % (585 samples, 0.86 s) | `BackgroundSyncActor.syncAllWithChangeDetection` 39 samples (57 ms) on main; `refreshFilteredRequests` 41 (60 ms); `MainTabView.body` 28; image wait 59 (86 ms); `ConversationsListView.body` while hidden 15 |
| Community tab switch, 12 s (load about 2.3) | 9,068 at 1.323 ms | 3.2 % (292 samples, 0.39 s) | `TownHallPostCard.body` 23 samples (30 ms); `loadPosts` 8; `getPosts` 5; image wait 51 |
| Message thread scroll, 20 s (load about 2.6) | 14,493 at 1.38 ms | 7.1 % (1,035 samples, 1.43 s) | cell provider 124 samples (171 ms), `MessageCellView.configure` 98, `URLDetectionCache.urls` 36; one-time system conformance scan 172 samples (about 240 ms) |

### Hypotheses from the earlier reviews

| Hypothesis | Result |
|---|---|
| `countOutsideScope` runs extra fetches on every filter pass | Code is as described, but it returns 0 at once for the owner's scope (All), so it never ran. Measured repeat fetches cost about 0 samples after the first. Estimated extra cost when narrowed: 2 to 4 ms per refresh. |
| `CommunityContext` (`@Observable`) read widely | 3 samples in the profiles. No cost attributable to it. |
| Signed storage URL resolution per image | `StorageURLSigner` had 0 samples in every profile; signing runs only on a disk-cache miss. The cost was the decode. |
| Town Hall enrichment fetch beside the coordinator refresh | Confirmed (finding F7 below). |
| `TownHallFeedViewModel.loadMore` writes SwiftData on the main actor | Refuted by code: later pages stay in memory (`TownHallFeedViewModel.swift` lines 167 to 173). The CLAUDE.md audit note 3 saying otherwise is out of date. |

## 5. Findings

Eleven reports came back as confirmed. Three describe the same code as another report (the Requests re-read and the Community badge clear each reported two or three times), so there are eight distinct findings. "Severity" is the verifier's rating, which in several cases is lower than the original.

### Confirmed

| # | Finding | Severity (verified) | Measured cost (Debug) | Predates Phases 1 to 5 | Fix |
|---|---|---|---|---|---|
| F1 | `BackgroundSyncActor` jobs (every dashboard, Town Hall, conversation sync write) run on the main thread | medium (reported high) | 39 samples (57 ms) in one tab switch; 19 dashboard syncs took 13 to 80 ms in the actor (median 24, mean about 29); Town Hall syncs 1 to 13 ms | yes (Feb to Mar 2026) | `138538f` |
| F2 | List images decoded at full camera resolution on every reappearance; no memory cache, no downsampling | high | 793 to 931 main-thread samples (about 1.15 to 1.6 s) blocked per 20 to 30 s of Town Hall scrolling, 60 to 70 % of non-idle main time; footprint up to 1.2 GB | yes (P5-T7 changed only the miss path) | `8606c8e` |
| F3 | Requests `.task` re-runs `setup()` and `loadRequests()` on every appearance: the list is rebuilt twice and the badge counts three times (reported twice) | low to medium | 54 samples (79 ms) in one appearance (111 samples, about 160 ms, over four appearances) | yes (Jan to Mar 2026) | `84506d7` |
| F4 | Town Hall `.task` re-runs `loadPosts()` on every appearance: store re-read, list swap, forced `manualReload:townHall` sync even inside the 30 s window | medium | about 16 ms per re-entry (46 samples over four re-entries); one extra full sync and two page fetches that changed nothing | yes (same code on `main`) | `8a8b867` |
| F5 | First Requests load shows the skeleton for about 1.1 s on every cold launch when the selected filter is empty but the store holds rows | medium (waiting time, no CPU) | 0.75 to 1.67 s from first main-UI frame to the empty state | yes (Mar and early Oct 2026) | `5b3fc13` |
| F6 | Entering the Community tab clears its badge twice (`MainTabView` onChange plus `CommunityTabView` onAppear), so `get_badge_counts` runs twice; onAppear also fires on Back (reported three times) | low | one extra RPC per visit; 4 ms or less on main | yes (Jan 2026; present at `f164a0f`) | `9479aad` |
| F7 | Town Hall first page fetched twice per Community visit (coordinator sync and the ViewModel's enrichment fetch) | low for lag (network only) | 5 to 6 extra HTTP requests per visit; the duplicate runs off main | yes (present at `f164a0f`) | `5498a43` |
| F8 | Town Hall page and single-post decoding runs on the main thread (nonisolated service methods inherit the caller's actor) | low | 2 to 4 ms per page on the Mac | yes | `5fffcd6` |

### Refuted or not a lag source

| Report | Verdict and reason |
|---|---|
| Community title menu reads all of `BadgeCountManager.counts`, so any badge change re-emits the toolbar | Refuted. `BadgeCounts` is `Equatable` and an equal assignment notifies no one. All 36 "Counts synced" lines in the 35-minute log carried identical values, so the menu was invalidated 0 times. The read is inside a lazily run closure. No profile has a frame for it. The same toolbar item reads `counts.bell` anyway. |
| `countOutsideScope` repeats four fetches and two filter passes while narrowed | Refuted as a lag cause. It never runs for the owner (scope All). The 290-row figure was wrong (the store holds 107 rides and 61 favors; the filter returns 1 to 8 rows). Repeat fetches cost about 0 samples. Estimated extra cost 2 to 4 ms when narrowed. It came with Phase 4 (`4eb88c4`), not Phase 1. Low-priority cleanup only. |
| `clearCommunityBadge` downloads the notification list on every visit | Not a lag source. The request is real (one GET per visit) but runs off the main thread, delays nothing visible, and exists at `f164a0f`. |
| `fetchPost(id:)` now runs vote and review lookups no caller reads | Not a lag source. One wasted request per Town Hall push for a normal post (3 for a review post), concurrent with the others, off the main thread, and bursts are joined by the coordinator. |
| Every Town Hall appear forces a full coordinator sync and a duplicate fetch | Refuted as a Phases 1 to 5 main-thread cost (the code is the same on `main`; main-thread cost 10 to 20 ms). The code path itself was correct and is covered by F4 and F7. |
| Phase 5 voice-note prefetch writes the file on the main actor and does not share an in-flight download with a tap | Not a lag source. The write is real (about 112 KB average) but happens after a network round trip, only for voice notes received over realtime in an open thread (4 voice notes exist in total, 0 in the last 30 days). The tap path already wrote on the main thread before Phase 5. |
| Map batch geocoding runs every address at once, uncapped | Dead code. `RequestMapView` is not presented anywhere since `700d7a0` deleted the dashboards that opened it. Deleting `RequestMapView.swift`, `batchGeocode` and `createMapRequests` is a cleanup, not a performance fix. |

## 6. Fixes

The Mac load is recorded for each run. Fix runs share the protocol of their "before" run unless noted. Fixes F2 to F8 were measured on the owner's iPhone 16 simulator; samples are from `/usr/bin/sample` at 1.3 to 1.5 ms per sample.

### F1. Sync writes off the main thread (`138538f`)

The original cause was wrong. Creating the actor in `App.init` is not the problem: a `@ModelActor` executor runs each job on the thread that hands it over. A probe on the iOS 26.5 simulator runtime and on macOS showed an actor created in `Task.detached` still ran on the main thread when called from a `@MainActor` function (3 of 3), and a main-created actor ran off the main thread when called from a detached task. So the fix enters the actor from `Task.detached` in `DashboardSyncEngine.performFullSync` and `TownHallSyncEngine.performFullSync`. Compare-before-write, the conditional save and posting `*DidSync` only after a save are unchanged. Files: `DashboardSyncEngine.swift`, `TownHallSyncEngine.swift` (16 and 7 lines).

| Measure | Before | After |
|---|---|---|
| `syncAllWithChangeDetection` on the Main Thread, one Requests tab switch | 39 samples (57 ms) | 0 (run 2: 0 on main, 34 on `NSManagedObjectContext` and cooperative queues; run 3: the same, 0 and 34) |
| Main thread busy, whole sample | 585 of 6,830 (8.6 %) | 122 of 11,221 (1.1 %) and 159 of 12,442 (1.3 %) |
| Town Hall `syncPostsWithChangeDetection` on main | 1 to 2 samples | 0 (1 sample off main) |
| In-actor dashboard sync duration | 13 to 80 ms | 16 to 72 ms (19, 16, 36, 72, 61): unchanged, as expected |
| Host load | 2.3 to 2.9 | 4.2 to 5.7 |

Verification:
- Debug build: exit 0, 0 errors.
- Targeted classes (`CommunityStoreScopingTests`, `BackgroundSyncActorConversationSyncTests`, `RefreshCoordinatorTests`, `PushNotificationServiceTests`, `MessagingSyncEngineTests`, `TownHallFeedViewModelTests`): 62 cases, 58 passed, 4 skipped.
- **Full unit suite, signed out, on "iPhone 16 Tests": 742 cases, 709 passed, 0 failed, 33 skipped** (usual session-gated skips).
- A sync that changes rows still reaches the UI: on the test simulator as a guest, the dashboard sync logged `ins=168 saved=true` and the open request appeared; the Town Hall sync logged `ins=20 saved=true` and the feed showed the posts. This path could not be exercised on the owner's device without writing, so it was not tested there.

Remaining: see section 7, items 1 and 2.

### F2. List images at their shown size, held in memory (`8606c8e`)

`PersistentImageService.getImage(for:maxPixelSize:)` takes an optional size. With a size, ImageIO decodes off the main thread to a bitmap whose long side is at most that size (never upscaled, orientation applied), and the result goes into an `NSCache` keyed by `<disk file name>@<pixels>`, bounded by `Constants.Storage.imageMemoryCacheMaxBytes` (80 MB), emptied on a memory warning and in `clearCache()`. Without a size the old path is unchanged. `CachedAsyncImage` returns early when it already shows an image for the same URL. `AvatarView` and `AvatarUIView` pass their size times the display scale; `TownHallPostCard` passes `Constants.Storage.feedImageMaxPixelSize` (1440 px). Disk cache keys and the signed-URL path are unchanged. Seven files, +145 lines; one test added to `PersistentImageServiceTests`.

Protocol (both runs): fresh launch, open Town Hall, warm-up of 8 flings down and 9 up so every image has been shown once, then `sample 30 1` during 7 flings down and 7 up between y=250 and y=720 pt.

| Measure | Before (the HEAD build before this fix, built 09:19; load 2.16 to 2.09) | After (load 4.70 to 3.68) |
|---|---|---|
| Main-thread samples | 22,741 | 22,684 |
| Non-idle main-thread samples | 1,239 | 535 |
| Blocked in `-[_SwiftUIProxyImage finish]` | 874 (about 1.15 s, 70 % of non-idle) | 0 |
| `CA::Transaction::commit` | 987 | 204 |
| `prepare-image` queue: `CA::Render::copy_image` / `applejpeg_decode_image_all` | 911 / 485 | 0 / 0 |
| Footprint (start, end; peak) | 970 and 994 MB; peak 1.2 GB | 85 and 86 MB; peak 85.3 MB |

An earlier run on a different swipe range (load 8 to 11) had 931 waits, 1,023 `copy_image` samples and a 1.0 GB peak, matching the first row. The photo (4608x6144) and avatars were checked on screen: sharp, upright, full width.

Verification: Debug build exit 0, no new warnings. `PersistentImageServiceTests`: 5 passed (4 existing, 1 new that checks the downsampled size, the identical-instance reuse and the unchanged full-size path). Full suite not run for this commit (no fragile system touched).

Not measured: the Requests tab-switch image wait (Open Requests is empty, so no image) and the 56 MB My Requests swing (needs the My Requests filter). Callers that pass no size still decode at full size; see section 7.

Corrected by the review follow-up `4812026`: the size passed to ImageIO capped the long side, so portrait feed photos and avatars were decoded below the size they are shown at. The size is now the short side, and the feed passes 1128 px instead of 1440. See "Review follow-ups" below; the figures above were measured before that change.

### F3. Requests re-entry passes (`84506d7`)

`setup(modelContext:)` returns early when handed the context it already holds, and the list pass in `loadRequests` skips the badge counts on a local-only re-entry because `refreshUnseenRequestKeys` recomputes them right after with fresher summaries. One file, +12 -4. The first load, pull-to-refresh, filter and scope changes are unchanged.

| Measure (main-thread samples in `RequestsDashboardViewModel`) | Before (4 appearances, load 2.94 to 2.81) | After (4 appearances, load 5.32 to 3.29) |
|---|---|---|
| Total | 111 (about 160 ms; about 40 ms each) | 33 (about 47 ms; about 12 ms each) |
| `setup(modelContext:)` | 44 | 0 |
| List pass in `loadRequests` | 35 | 4 |
| Summaries plus badge counts | 32 | 29 |
| `computeFilterBadgeCounts` | 97 (three passes per appearance) | 27 (one pass) |
| `RequestsDashboardView.body` | 46 | 0 |
| `ToolbarBridge` | 129 | 73 |

A later independent run on `5b3fc13` (load 11.0 to 9.2, 3 appearances) counted 26 samples (about 8.7 per appearance, about 12 ms), and `-com.apple.CoreData.SQLDebug 1` showed 4 row SELECTs per appearance instead of 10 (1 filtered ride, 1 filtered favor, 1 notification, 1 unfiltered ride, 1 unfiltered favor, plus one `COUNT(*)` from F5). Tests: `CommunityStoreScopingTests` and `RequestNotificationMappingTests`, 22 passed. No test class constructs `RequestsDashboardViewModel`, and none was added. The narrowed-scope case was not measured.

### F4. Town Hall feed re-entry (`8a8b867`)

`TownHallFeedViewModel.loadPosts()` tells the first load apart from a re-entry with `hasLoadedPosts`. A re-entry with posts on screen hides posts by an author blocked in the meantime (writing `posts` only if one exists), clears `error` only if set, returns if the last successful network refresh was under `Constants.Timing.refreshStalenessWindow` (30 s) ago, and otherwise starts the same `manualReload:townHall` refresh as before. `lastRefreshSucceededAt` is set behind the generation guard and reset on a community switch. Error retry with an empty feed, pull-to-refresh, post-created and comments-changed refreshes, community switch and navigation targets are unchanged. One file, +30.

| Measure | Before (HEAD `84506d7`, load 1.94) | After (load 2.72 to 2.45) |
|---|---|---|
| Four re-entries in a 24 s sample (before: all within 30 s of the last refresh; after: at 19, 23, 27 and 31 s): forced `manualReload:townHall` syncs | 4 (each ended `saved=false`) | 1 (only the 31 s one, as designed); the three inside 30 s logged `skipped:fresh` only |
| "Fetched 20 posts from network" | 8 | 2 |
| Main-thread samples in `TownHallFeedViewModel`, feed body and cards | 46 (about 64 ms; `loadPosts` 21, `error.setter` 11, feed body 18) | 1 (about 1.5 ms) |
| One entry 74 to 78 s after the last sync, 12 s sample | about 14 samples (about 20 ms) | about 6 samples (about 8 ms) |
| Back from an author profile inside 30 s | store re-read plus forced sync | no Town Hall log line; feed kept its enriched rows |

Tests: `TownHallFeedViewModelTests` 8 passed, 2 skipped (session-gated). A stale entry still fetches the page twice at that commit, which is what F7 addresses. The Town Hall to Leaderboard segment switch builds a new ViewModel and still takes the first-load path.

The 30 s skip also skipped changes made elsewhere. Three are handled by the review follow-up `5e91b00`: a block whose refresh returns after the feed reappeared, an unblock made in Settings, and the Town Hall post a review creates. One is accepted: **a moderator who hides a post from admin or community Reports and returns to the feed within 30 s still sees the post until they pull to refresh or the 30 s pass.**

### F5. Requests empty state without the skeleton (`5b3fc13`)

`RequestFilterManager.hasStoredRequests(in:)` runs two `fetchCount` queries, and `loadRequests` shows the skeleton only when the filter has no rows **and** the store has none. The refresh and its coordinator call are unchanged. Two files, +12 -1.

| Run | Skeleton to empty state before (HEAD `8a8b867`) | After |
|---|---|---|
| 1 | 1.03 s (load 2.46) | 0 s, no skeleton frame (load 7.32) |
| 2 | 1.04 s (load 1.81) | 0 s (load 6.82) |
| 3 | 1.67 s (load 2.00) | 0 s (load 6.12) |
| 4 | 0.75 s (load 2.22) | not run |

Baseline: 1.05 to 1.22 s. The `manualReload:requests` refresh still runs in every "after" run. Tests: `CommunityStoreScopingTests` 21 passed. Side effects: a filter with no rows over a filled store shows its empty state during the first refresh and a row may appear after; an empty store (first sign-in) still shows the skeleton; after a failed first load the retry shows the empty state. The forced first-load refresh still repeats a launch refresh the coordinator had skipped as fresh (about 1 s of network, `saved=false`); that is a `RefreshCoordinator` contract question and was left alone.

Review follow-up `5e44b37`: the store-rows shortcut now applies only to a plain load, so the error panel's Retry and pull-to-refresh show the skeleton again until the refresh returns. **Left as a product call: on a cold launch, a filter with no rows over a filled store shows its empty state for about a second, and a row the first sync adds can then appear in it.**

### F6. Community badge cleared once per visit (`9479aad`)

The `.onAppear` call to `clearCommunityBadge` in `CommunityTabView` was removed. `MainTabView.onChange(selectedTab)` case 2 remains the clear on arrival (tap or routed push), and `onChange(communityTabId)` covers a community switch. One file, +3 -7.

| Measure | Before | After |
|---|---|---|
| Clears and `get_badge_counts` per Community tab tap | 2 and 2 (10 of 10 earlier taps; 2 of 2 on the HEAD build, load 3.2 to 4.7) | 1 and 1 (7 of 7, plus 2 of 2 on the committed build, load 3.0 to 8.1) |
| Back from an author profile to the Community root | 1 clear (notification fetch plus RPC) | 0 |

Tests: `BadgeCountManagerTests` 13 passed. Behavior change: returning from a pushed screen inside the Community tab no longer marks that community's Town Hall rows read (the Requests and Profile tabs already clear only on arrival). Not changed: the cold-launch pair (`Refreshing badges (init)` then `(mainTabAppear)`, two RPCs) and the underlying race in `BadgeCountManager.refreshAllBadges` (the 5 s debounce is read before the await and written after it); that file is a fragile system. Not exercised: the community-switch path and the bypass-debounce path with unread rows in the visible community (the owner's one unread row is in another community, so every visit took the no-op path).

### F7. Town Hall first page fetched once (`5498a43`)

`TownHallService.fetchPostsPage` joins identical in-flight calls through the existing `RequestDeduplicator`, keyed by limit, offset, community id and user id. The coordinator, the engine contract, the store and the ViewModel are unchanged. One file, +19 -3.

| Measure, Community visit with the domain stale | Before (HEAD `9479aad`, load 3.1 to 7.4) | After (load 2.7 to 3.4) |
|---|---|---|
| HTTP tasks in the 12 s after the tap (3 visits) | 14, 14, 14 | 8, 8, 8 |
| "Fetched 20 posts from network" | 2, 2, 2 (one on main) | 1, 1, 1 (off main) |

Each visit now logs one "Started new request" and one "Request already in-flight" for the page key. Tests: 56 cases across `TownHallFeedViewModelTests`, `TownHallServiceTests`, `TownHallPostTests`, `PerformanceImprovementsTests` and `CommunityStoreScopingTests`: 49 passed, 7 skipped (session-gated). Behavior change: a refresh that starts while an earlier page fetch is in flight (for example after creating a post) receives that earlier result; the window is one fetch, under a second. The vote counts could not be seen on screen because none of the visible posts had votes; the enriched value is the same as before. The deduplicator logs its key (which holds user and community ids) at info level.

Review follow-ups: `7e26e3b` moves the blocked-author filter out of the shared fetch, which ran off the main thread and read a set the main actor writes (a data race); `136ae1e` adds a write count to the key, so a refresh after a write no longer receives a page fetched before it. The window described above is closed for Town Hall writes made through the app's services.

### F8. Town Hall decode off the caller's actor (`5fffcd6`)

A `@concurrent` `decodePosts` helper now decodes both the page and `fetchPost(id:)`. Signatures, the protocol, the blocked-author filter and the coordinator are unchanged. One file, +12 -5. Most of this finding was already resolved by F7: running inside the deduplicator's task moved the page decode off the main thread.

| Measure | Before | After |
|---|---|---|
| Main-thread `JSONDecoder` samples under `TownHallService`, Community tab switch | 2 in the baseline (pre-F7); 0 at `5498a43` (page only; `fetchPost` still on caller) | 0 (decode shows 9 samples on a cooperative thread; load 14.5 at the start) |
| Load-more page | 0 | 0 (offset 20, 13 posts, background thread) |
| `fetchPost(id:)` | on the caller's executor (main) | off main by `@concurrent` semantics; **not exercised on a device** (needs a push or a notification-row tap) |

Tests: `TownHallServiceTests`, `TownHallFeedViewModelTests`, `CommunityStoreScopingTests`: 37 cases, 30 passed, 7 skipped (session-gated; so no unit test ran the changed decode against real rows).

### Test coverage of the whole pass

The full unit suite ran at `138538f` (742 cases, 0 failed) and again on the final code, `f1a99e6` (the report commit after it changes only this file), signed out, on "iPhone 16 Tests" (iOS 26.5): **745 cases, 712 passed, 0 failed, 33 skipped**. The 33 skips are the usual session-gated live-backend cases (`TownHallServiceTests` 5, `NotificationsListViewModelTests` 5, `RideServiceTests` 4, `NotificationServiceTests` 4, `LeaderboardServiceTests` 4, `FavorServiceTests` 3, `PushNotificationServiceTests` 2, `TownHallFeedViewModelTests` 2, and one each in `MessageServiceTests`, `MyProfileViewModelTests`, `ReviewPromptProviderTests`, `CompletionPromptProviderTests`). Commits between the two runs ran the targeted classes listed above. Release build (simulator SDK, `-configuration Release`) on `f1a99e6`: exit 0, 0 errors. The fragile-system changes are F1 and the sign-out fix for section 7 item 1 (`RefreshCoordinator`); F6 touches a view that calls the badge manager but not `BadgeCountManager` itself.

### Review follow-ups (2026-10-20)

An independent read-only review of the pass's commits found seven issues. Each was checked against the code before it was changed; all seven were confirmed as described. Fixes, one commit per finding (items 1, 2 and 7 share one):

| # | Finding (commit reviewed) | Fix | Commit | Test |
|---|---|---|---|---|
| 1 | Portrait list images decoded below their shown width (`8606c8e`). `kCGImageSourceThumbnailMaxPixelSize` caps the long side, and feed photos are shown aspect-fit at the card's width: a 945x2048 screenshot was decoded at 664x1440 for a 987 px card (stretched 1.5x), a 9:16 photo 1.22x. | `PersistentImageService` reads the source's pixel width and height and asks for a long side of `min(long, target * long / short)`, so the short side is the target, or the source's own when smaller (never upscaled). Memory key unchanged (stored file name plus target). `Constants.Storage.feedImageMaxPixelSize` is now a short side: 1128 px, the card on the widest iPhone (440 pt less 64 pt of padding) at 3x. Kept at 1440 it would have decoded a 3:4 photo at 1440x1920 (11 MB) for a card at most 1128 px wide; at 1128 it is 1128x1504 (6.8 MB), close to the 1080x1440 measured in F2. A landscape photo now decodes wider than the card, by its aspect ratio. | `4812026` | `PersistentImageServiceTests`: a portrait fit-width target decodes at least the target wide with the long side within the source's; a source smaller than the target comes back at its own size (150x400 for 300, 40x30 for 100); the existing downsample case now expects a 100 px short side (400x300 to about 134x100). |
| 2 | Avatars decoded below the circle they fill (`8606c8e`): aspect-fill shows the short side, so a 3:4 avatar in a 120 pt circle was decoded 270x360 and stretched 1.33x. | The item 1 formula. `AvatarView` passes `size * displayScale` and `AvatarUIView` `size * scale`, both the circle's side in pixels (confirmed). | `4812026` | `PersistentImageServiceTests`: an avatar-style fill target gives a short side of at least the target, portrait and landscape. |
| 3 | Data race on `MessageService.cachedBlockedUserIds` (`5498a43`): the page fetch now runs inside the `RequestDeduplicator` task, off the main thread, and read the set that `refreshBlockedUsers` writes on the main actor. | The shared closure returns the posts unfiltered with `serverCount`; `fetchPostsPage` removes blocked authors after `pageRequests.fetch` returns, on the caller's executor (the main actor for `TownHallSyncEngine` and `TownHallFeedViewModel`). Each joined caller filters with its own current set. The set is read through an internal `blockedAuthorIds` closure (default `MessageService.shared.cachedBlockedUserIds`) so a test can stand in. | `7e26e3b` | `TownHallServiceTests.testFetchPostsPage_FiltersBlockedAuthorsAfterTheSharedFetch`, stubbed with a new test URLProtocol (`TownHallPageURLProtocol`, holds the page read until released) because the class was otherwise live-backend or session-gated: two identical calls make one page request; both results leave the blocked author out with `serverCount` 2; the set is read twice, once per caller, both times on the main thread. |
| 4 | Feed re-entry within 30 s missed changes made elsewhere (`8a8b867`). | (c) and (d): `MessageService.refreshBlockedUsers` posts the new `.blockedUsersDidChange` (`NotificationNames.swift`) when the set changes; `TownHallFeedViewModel` hides newly blocked authors and drops `lastRefreshSucceededAt`, so the next appearance refreshes. (b): `open()` with a target missing from a list this generation has already refreshed drops `lastRefreshSucceededAt` and starts `refreshAfterPostCreated()` (the existing `postCreated:townHall` trigger; no new coordinator trigger); the target still resolves at once. This also runs for a push or bell row whose post is not in the list (one extra refresh). | `5e91b00` | `TownHallFeedViewModelTests.testBlockedUsersChange_RefiltersAndEndsTheReentrySkip` ((d) then (c), with the blocked set set through the real `refreshBlockedUsers` against a stubbed `get_blocked_users`) and `testOpenTargetMissingFromRefreshedList_RefreshesAsAfterACreatedPost` ((b)). |
| 5 | A refresh after a write could join a page fetch that began before it (`5498a43`): vote, then pull-to-refresh while a pre-vote fetch is in flight, and the joined result put the old counts back in the vote cache. | A write count in `TownHallService` (`OSAllocatedUnfairLock`) is part of the page key. `noteWrite()` bumps it when each write returns, success or not: `TownHallService` `createPost`, `createSystemPost`, `deletePost`, `votePost`; `TownHallCommentService` `createComment`, `createReply`, `deleteComment`, `voteComment`; `TownHallVoteService` `votePost`, `voteComment` (no callers today). The review's own post goes through `createPost` (`ReviewService`). Reads that start together still join. Moderation (admin and community Reports) writes through its own RPCs and does not bump the count. | `136ae1e` | `TownHallServiceTests.testFetchPostsPage_ReadAfterAWriteDoesNotJoinAReadFromBeforeIt`: two overlapping identical reads join (one page request); a read started after `votePost` while a pre-vote read is held makes its own request (three in all). |
| 6 | The Requests empty state replaced the skeleton on Retry and pull-to-refresh (`5b3fc13`). | The store-rows shortcut applies only when `forceRefresh` is false; the cold-launch gain stays. | `5e44b37` | None. There is no `RequestsDashboardViewModelTests`, no test class constructs the ViewModel, and it calls `RefreshCoordinator.shared` directly, so testing the `isLoading` timing needs a coordinator seam this change does not add. `CommunityStoreScopingTests` and `RequestNotificationMappingTests` ran (22 passed). |
| 7 | Magic number: the fallback display scale `3` in `AvatarUIView` (`8606c8e`). | `Constants.Storage.fallbackDisplayScale` (the surrounding code reads `traitCollection.displayScale` and falls back when it is 0). | `4812026` | Covered by the build. |

Accepted, stated plainly:

- **Town Hall (F4, case a):** a moderator who hides a post from admin or community Reports and returns to the feed within 30 s still sees it until they pull to refresh or the 30 s pass.
- **Community badge (F6):** going Back into the feed from a screen pushed inside the Community tab no longer marks that community's Town Hall rows read; only arriving on the tab does.
- **Requests cold launch (F5):** a filter with no rows over a filled store shows its empty state for about a second, and a row the first sync adds can then appear in it.

**Interleaved saves since F1 (`138538f`).** The review could not tell by reading whether a `BackgroundSyncActor` save that interleaves with a main-context save of the same rows throws, or which value wins. `BackgroundSyncActorConversationSyncTests.testDashboardSyncInterleavedWithMainContextSaves_ActorSaveDoesNotThrow` (`8d174ca`) runs `syncAllWithChangeDetection` from `Task.detached` while the main context flips `SDNotification.read` on the same 20 rows and saves, 50 rounds on a SQLite store, the main save landing at three different points relative to the job. Answer: **no save threw**, the actor's or the main context's, in three runs (150 rounds: two targeted runs and the full suite). **The later save wins the whole row, not each property.**

| Run | `read` held the actor's value | the main context's | differed between rows | stored title went back to the previous round's |
|---|---|---|---|---|
| 1 (targeted) | 44 | 4 | 2 | 2 |
| 2 (targeted) | 36 | 12 | 2 | 7 |
| 3 (inside the full suite) | 5 | 41 | 4 | 14 |

The main context never sets the title, so a title that went back means a main-context save made from a snapshot older than the actor's save overwrote the actor's write, row and all. The rounds runs 2 and 3 list (the first five of each: 8, 11, 14, 17, 20 and 5, 8, 11, 14, 20) are all rounds where the main save came 1 ms after the job started. In the app the next sync writes the server's values again, so such a revert lasts until then. Before F1 the actor job ran on the main thread and could not overlap main-actor code, so this window was one main-queue turn (the main context merging the actor's save) rather than the whole job. No engine was changed; whether to act on it is a fragile-system decision for the owner.

Verification of the follow-ups (Lane B, "iPhone 16 Tests", never signed in):

- Debug build (`-sdk iphonesimulator -configuration Debug`): exit 0, 0 errors, no warnings in the touched files.
- Targeted classes, run after each change: `PersistentImageServiceTests` 8 passed; `TownHallServiceTests` 3 passed, 5 skipped; `TownHallFeedViewModelTests` with `MessageServiceTests` 16 passed, 3 skipped; `BackgroundSyncActorConversationSyncTests`, `CommunityStoreScopingTests` and `RequestNotificationMappingTests` 26 passed. All skips are the usual session-gated ones.
- Full unit suite, signed out, on `8d174ca` (`build/p5b-gate/TestResults-followup.xcresult`): **753 cases, 720 passed, 0 failed, 33 skipped**. The 33 skips are the same session-gated cases as before (`TownHallServiceTests` 5, `NotificationsListViewModelTests` 5, `RideServiceTests` 4, `NotificationServiceTests` 4, `LeaderboardServiceTests` 4, `FavorServiceTests` 3, `PushNotificationServiceTests` 2, `TownHallFeedViewModelTests` 2, and one each in `MessageServiceTests`, `MyProfileViewModelTests`, `ReviewPromptProviderTests`, `CompletionPromptProviderTests`); the 8 new cases all passed (745 before).
- Release build (`-configuration Release`, simulator SDK) on `8d174ca`: exit 0, 0 errors, no warnings in the touched files.
- Not done: Lane B screenshots of the feed photos and avatars after items 1 and 2 (optional), any check on the owner's simulator or a device, and a test for item 6.

**Regression found by the 5b device gate (G1), fixed in `48bd1ee`.** On the owner's simulator a Town Hall photo post that reached the Community tab's feed while the tab was off screen logged `Failed to download image: NSURLErrorDomain -999` about once per frame (4,795 and 4,278 lines in the gate, 26 % CPU, no request reached the server), and when the tab opened the card showed the error view until it was re-created (`Docs/qa/2026-10-20-multi-community-phase5b-gate.md`, G1).

- Cause, confirmed with temporary logging on the device (not committed): `CachedAsyncImage` puts `.task(id: url)` on a `Group` (`NaarsCars/UI/Components/Common/CachedAsyncImage.swift:55` before the fix), and a modifier on a `Group` applies to each branch, so every switch between the image, error and placeholder branches starts a new load and cancels the running one. A card inserted into a tab that is not on screen appears and disappears in the same update, which cancels its first load. The cancelled load set `hasFailed = true` (`:80`), the error branch appeared and started a load, that load set `hasFailed = false` (`:69`) and was cancelled at once, and so on, once per frame for as long as the tab stayed hidden. When the tab opened, the `isLoading` guard (`:67`) made the new appearance's load return early while a cancelled one was still returning, and that one left `hasFailed` set.
- Not caused by this pass, by the code: `0af6e16` has the same `Group` and `.task`, the same `isLoading` guard and the same `hasFailed` writes; F2 added only `loadedURL` and `maxPixelSize`, and neither takes part (the image is nil throughout). The trigger, a photo post arriving in a loaded, hidden feed with the photo not on disk, evidently did not occur in the 5a run. The 5a build was not run to confirm.
- Fix: a load writes no state when it starts; a load cancelled before an image arrived changes nothing (`CachedImageLoadOutcome.unchanged`), so the next appearance loads again; an image that arrives is shown even if the task was cancelled meanwhile; the `isLoading` guard is removed. `PersistentImageService` is unchanged, so a cancelled download still logs one -999 line.
- Device proof (owner's iPhone 16, Debug, the same reproduction before and after: a photo post in NH Neighbors inserted by a `town_hall_post` push from `simctl push` while the Requests tab was showing and the feed was loaded): before, 1,613 -999 lines in 27 s (app CPU 19 %) and the error view when the tab opened; with temporary logging, 3,183 lines in 54 s and the cycle described above; after, 1 line in 30 s, app CPU 0 %, and the photo shown when the tab opened. A post whose image does not exist, in the visible feed: one sign and one GET in the edge log, then the error view, no loop. The test posts were deleted from the app; the uploaded image (`town-hall-images/09B9C955-….jpg`, the owner's) stays in the bucket because deleting a post does not delete its image, and no visible post refers to it.
- Tests: `PersistentImageServiceTests.testGetImage_FromACancelledTask_IsNotAFailure` (a load from a cancelled task is not reported as a failure) and `CachedImageLoadOutcomeTests` (3 cases for the state rule). The SwiftUI part (the `Group` branch switch and the hidden tab's appear and disappear) has no unit seam and rests on the device proof.

Verification of the post-gate fixes (G1 `48bd1ee`, G2 `e0f3670`, G4 `5e560f7`, G5 `1ff452a`; Lane B):

- Debug build: exit 0, 0 errors, no warnings in the touched files.
- Targeted classes on "iPhone 16 Tests" (never signed in): `PersistentImageServiceTests`, `CachedImageLoadOutcomeTests`, `TownHallFeedViewModelTests`, `MyCommunitiesViewModelTests`, `AppLaunchManagerTests`, `MyProfileViewModelTests`: 53 cases, 50 passed, 0 failed, 3 skipped (session-gated).
- Full unit suite, signed out, on the code of `1ff452a` (`build/p5b-gate/TestResults-g1.xcresult`): **757 cases, 724 passed, 0 failed, 33 skipped**, the same 33 session-gated skips as on `8d174ca`; the 4 new cases passed.
- Release build (`-configuration Release`, simulator SDK): exit 0, 0 errors; no warnings in the touched files.

## 7. What remains open

Follow-up: the phone-log pass (`Docs/qa/2026-10-20-phone-log-performance-pass.md`) fixes item 5 (`e639cc0`, `d0e3aab`) and the notification-download part of item 11 (`2f9fdac`, `b665dfe`), also fixes the Leaderboard refetch and the bell's forced sync, instruments the slow send, and measures the launch metrics; items 7 and 9 stay open there.

| # | Item | Notes |
|---|---|---|
| 1 | **Sign-out race with the detached sync writes (from F1): fixed in `f1a99e6`.** `RefreshCoordinator.reset()` now waits for the refreshes it cancels to finish, at most `Constants.Timing.refreshResetDrainTimeout` (3 s), before it clears state and returns, so a job already inside `BackgroundSyncActor` saves before `AuthService` wipes SwiftData. | Two new `RefreshCoordinatorTests` cases (a cancelled job's write lands before `reset()` returns; a job that never ends releases `reset()` at the timeout); both fail with the wait disabled. The race itself was found by reading the code and was not reproduced on a device. |
| 2 | The conversation-list sync (`MessagingSyncEngine`) and the single-row upserts (`performTargetedSync`, `deletePostWithChangeDetection`) still enter `BackgroundSyncActor` from the main actor. | Same executor behavior as F1. Not measured as a cost. |
| 3 | Image callers without a size still decode at full size: group conversation avatar, `GroupAvatarComposite`, `ReviewCard`, the media gallery, `MessageDetailsPopup`, `ReactionDetailsRowView`. `ImageViewerView` is full size by design. | One line each. The memory cache is not cleared at sign-out (the disk cache is not either). |
| 4 | Remaining Requests appearance cost: one badge-count pass (23 to 29 samples: two unfiltered fetches of about 290 rows plus in-memory filtering). | The next lever if Requests still feels slow. |
| 5 | Messages tab: two full conversation RPCs back to back on a stale switch (`tabAppear`, then `manualReload:conversations`), 5 to 6 HTTP tasks. | Seen in the baseline; not investigated in this pass. |
| 6 | Cold launch: 3.1 to 6.3 s to the first main-UI frame; `approvalCheck` over 500 ms in two of three runs; the main actor is busy 0.57 to 0.75 s with the first `MainTabView` render after `ready_authenticated`. The forced `manualReload:requests` still repeats a launch refresh that was skipped as fresh. | Not investigated beyond the skeleton (F5); not re-measured after the fixes. |
| 7 | Badge refresh at launch runs twice (`init` and `mainTabAppear`), and `refreshAllBadges` lets two concurrent callers both pass the debounce. | `BadgeCountManager` is a fragile system; needs a `BadgeCountManagerTests` case and an impact summary. |
| 8 | Message thread: cell provider 171 ms per 20 s of scrolling (`MessageCellView.configure`, `URLDetectionCache.urls`). `ConversationsListView.body` re-evaluates while hidden (22 ms in one Requests switch). `String.localized` inside `TownHallPostCard.body` (about 10 samples). | Not investigated. |
| 9 | Town Hall re-entry after more than 30 s still starts the forced `manualReload:townHall` (it joins the `tabAppear` sync; both run). The Town Hall / Leaderboard segment switch rebuilds the ViewModel and takes the first-load path. | By design in F4. |
| 10 | Not measured: Release builds, any physical device, tab-switch latency in seconds after the fixes, cold-launch time after the fixes, a sync that changes rows on the owner's device, the My Requests scroll after F2, and a Time Profiler trace (`xctrace` refuses the simulator). | The Release procedure in section 1 covers the first two. |
| 11 | Optional cleanups, each saving network or a few milliseconds: delete the dead `RequestMapView`, `batchGeocode` and `createMapRequests`; fetch only the author and comment count in `fetchPost(id:)`; skip the notification download when nothing in the visible community can be unread; take the narrowed count in `countOutsideScope` from `filteredRequests.count`. | None is a lag fix. |
| 12 | CLAUDE.md audit note 3 (`loadMore` writes SwiftData on the main actor) is out of date: later pages stay in memory. | Documentation only; this pass did not edit CLAUDE.md. |
| 13 | Since F1 a main-context save made from a snapshot older than a concurrent `BackgroundSyncActor` save of the same row overwrites the whole row, including fields the main context did not change, until the next sync writes the server's values again. Nothing throws. | Found by the review follow-up test (`8d174ca`, see "Review follow-ups"). Sync engines and SwiftData are fragile systems; no change was made. |
| 14 | Moderation (admin and community Reports) does not bump the Town Hall page-key write count, and the feed's 30 s re-entry skip does not see a hide made there. | Accepted (F4 case a); pull-to-refresh shows it. |

## 8. Impact summary

| Commit | Files | Fragile system? | What would have broken if a consumer were missed |
|---|---|---|---|
| `138538f` | `DashboardSyncEngine.swift`, `TownHallSyncEngine.swift` | Yes (sync engines, section 6 of CLAUDE.md) | A sync save that does not reach `@Query`/the UI, or a `*DidSync` notification posted before the save. Covered by the full suite and the guest-sync check. |
| `8606c8e` | `PersistentImageService.swift`, `Constants.swift`, `CachedAsyncImage.swift`, `AvatarView.swift`, `AvatarUIView.swift`, `TownHallPostCard.swift`, `PersistentImageServiceTests.swift` | No | A signed URL persisted in a cache key; none is (keys use the stored file name). |
| `84506d7` | `RequestsDashboardViewModel.swift` | No | Badge counts stale after a re-entry; `refreshUnseenRequestKeys` recomputes them. |
| `8a8b867` | `TownHallFeedViewModel.swift` | No | A blocked author's post staying visible after returning from a profile; handled. |
| `5b3fc13` | `RequestFilterManager.swift`, `RequestsDashboardViewModel.swift` | No | An empty first sign-in showing no skeleton; the store count keeps it. |
| `9479aad` | `CommunityTabView.swift` | No (calls `BadgeCountManager`, unchanged) | The Community badge not clearing on arrival; `MainTabView` still does. |
| `5498a43` | `TownHallService.swift` | No | A refresh after a write receiving a result older than the write (window under 1 s). |
| `5fffcd6` | `TownHallService.swift` | No | A decode isolation error; the build is clean. |
| `4812026` | `PersistentImageService.swift`, `Constants.swift`, `CachedAsyncImage.swift`, `AvatarUIView.swift`, `PersistentImageServiceTests.swift` | No | A caller that shows the long side at full size (none today) would get a larger bitmap than it needs; the cache key is unchanged. |
| `7e26e3b` | `TownHallService.swift`, `TownHallServiceTests.swift` | No | A caller of `fetchPostsPage` off the main actor would read the blocked set off it again; both callers are `@MainActor`. |
| `136ae1e` | `TownHallService.swift`, `TownHallCommentService.swift`, `TownHallVoteService.swift`, `TownHallServiceTests.swift` | No | A write method without `noteWrite()` would let a later read join an earlier one; every write in the three services calls it. Moderation RPCs do not. |
| `5e91b00` | `MessageService.swift`, `NotificationNames.swift`, `TownHallFeedViewModel.swift`, `TownHallFeedViewModelTests.swift` | No | A screen that filters by the blocked set and does not observe `.blockedUsersDidChange` keeps its old list until it reloads, as before. |
| `5e44b37` | `RequestsDashboardViewModel.swift` | No | None outside the ViewModel. |
| `8d174ca` | `BackgroundSyncActorConversationSyncTests.swift` | No (test only; it probes the F1 sync engine change) | Nothing; no engine changed. |
