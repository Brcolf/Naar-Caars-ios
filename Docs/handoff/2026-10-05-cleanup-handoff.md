# Handoff — October 2026 cleanup branch

Branch: `claude/quirky-gates-4bkmv4` · PR: https://github.com/Brcolf/Naar-Caars-ios/pull/1 · Written 2026-10-05.

This branch was produced in a cloud session without Xcode. Everything below the
"Verified" line was checked against the live backend or by reading code; nothing in
the "Needs your Mac" section has been compiled or run. Do that first.

## Commits on this branch

- `e9efdb7` fix(backend): restore push delivery and lock down SECURITY DEFINER functions
- `7fcf3ff` chore(xcode): make every source and test file part of the project
- `15c76d1` docs: archive stale planning and setup notes, redact a committed service key
- `5b7517b` chore(supabase): import the 102 live migrations that were never committed
- `5e63054` fix(profiles): read other members through the public_profiles view
- `e1c0772` docs: align README, AGENTS, SECURITY and legal notes with the real project state
- `880f5c1` l10n: add catalog entries for previously hardcoded UI strings
- `a957338` refactor(architecture): bring the app in line with CLAUDE.md invariants
- `d9f7c0c` fix(review): address the three findings from the Phase E read-through
- `c435b63` l10n: add two missing account-deletion keys used by BannedAccountView
- `28de691` perf: apply the verified performance findings across services, storage and messaging UI

## Verified (done, checked)

- **Push delivery restored.** Webhooks were sending a legacy service-role JWT that the
  edge functions no longer accepted (401 since mid-April). Webhooks now send a Vault
  secret (`x-webhook-secret`), verified by `verify_webhook_secret()`; `send-notification`
  v21 and `send-message-push` v31 are deployed and byte-identical to the repo. A test
  queue row produced HTTP 200 and was claimed by the function. 330 stale queued alerts
  were suppressed with `sent_at = '2026-10-05 00:00:00+00'` (reversible by that value).
- **Function lockdown applied** (`20261005_0001`, `_0003`): anon EXECUTE revoked on 34
  SECURITY DEFINER functions, trigger functions and internal helpers closed to API
  roles, `upsert_profile_for_signup` neutralised, `get_reply_counts` search_path fixed,
  `pg_trgm` moved to `extensions`. Advisor now lists only intentional anon RPCs.
- **Repo is the schema source of truth again**: 102 live migrations imported, deployed
  edge-function sources imported.
- **Xcode project**: 11 test files that were never compiled are in the test target;
  misplaced sources moved; duplicates and machine-specific symlink references removed;
  12 new source files registered. Every build-phase reference resolves to a file on disk.
- **Docs**: README, AGENTS, SECURITY, privacy header, messaging review note, CLAUDE.md.

## Mac verification (2026-10-05, Xcode 26.6, headless Lane B)

- **Build**: `xcodebuild … build` succeeds after `3ed86da` (one compile error and two
  new warnings in the branch's files, one test-target compile error in `ThrottlerTests`,
  one test-mock mismatch in `ClaimServiceTests`). No warning in the build log is
  attributable to a line this branch added; the ~110 remaining warnings predate it.
- **Unit tests** (clean DerivedData, one simulator, UI tests skipped): 349 cases,
  314 passed, 25 failed, 10 skipped. Of the 25: 19 are the baseline failures already
  listed in CLAUDE.md (ImageCompressor ×4, Validators ×3, Leaderboard ×4,
  NotificationService ×4, AppLaunchManager state transition, ConversationDetailViewModel
  realtime, MessagingSyncEngine readBy, MyProfileViewModel); 3 are
  `PushNotificationServiceTests` (live backend ×2, permission alert timeout); 2 are the
  live-data `TownHallFeedViewModelTests` and 1 is the timing-based
  `PerformanceImprovementsTests.testPerformanceMonitorPercentiles`, all three of which
  pass when run in isolation. The handoff's named classes (`ClaimServiceTests`,
  `AppLaunchManagerTests` perf case, `SupabaseConnectionTests`, `ThrottlerTests`,
  `ConversationsListViewModelTests`, …) are green in isolation.
- **Credentials**: the local `Secrets.swift` now carries the `sb_publishable_…` key
  (legacy JWT copy kept outside the repo). `SupabaseConnectionTests` and the live
  Town Hall fetches pass against it, so REST accepts the new key. Legacy JWT keys must
  stay enabled until a build with this key has shipped.
- **Repo hygiene done**: `.DS_Store`, `package-lock.json`, `supabase/.temp/*`,
  `QA/Reports/**/*.log` untracked; the eight `NaarsCars/*.swift` symlinks deleted;
  `build/` gitignored.
- **Still manual**: deleting the dead source files in Xcode (`MessagingDebugView`,
  `Logger`, `RidesDashboardView`/`ViewModel` + test, `FavorsDashboardView`/`ViewModel`
  + test, `DirectMessageContainerView`) — their project references must go with them;
  `20261005_0004` in the SQL editor; dropping the two disabled triggers and
  `upsert_profile_for_signup`; leaked-password protection; the simulator checklist.

## Mac execution of the next steps (2026-10-05, later the same day)

Everything in sections A–C below that did not need Xcode's GUI or a dashboard login
was done on the Mac in commits `e804569`…`7e6c363`:

- **A done.** `claude/eloquent-hypatia-rar9pm` is merged (`e804569`), including the
  iOS 26.0 deployment target, the Xcode 26.6 verification lanes, the CI workflow and
  the project slash commands. Conflicts were resolved toward this branch's structure;
  `project.pbxproj` keeps this branch's references (the other branch's duplicate
  registrations of the same test files were removed; 72 test files, no duplicates,
  no dangling references).
- **B done**, as tasks 1–7 plus three follow-ups: push-notification tests use an
  injectable authorization seam (`NotificationAuthorizationRequesting`); Town Hall
  feed, leaderboard, notification-service and profile tests are session-gated with
  thrown `XCTSkip`; launch-path and percentile tests are deterministic; phone fixtures
  are PhoneNumberKit-valid; `ImageCompressor` now resizes in pixel space at scale 1
  (all 9 image tests pass). Two test-isolation bugs explained the long-standing
  "live backend 500" failures and are fixed (see CLAUDE.md Audit Notes).
- **C partly done.** Publishable-key docs updated (`4df914d`). The Supabase dashboard
  items (migration `20261005_0004`, the trigger/function drops, leaked-password
  protection) were declined by the MCP confirmation gate twice and remain manual.
- **Closing run** (clean DerivedData, Xcode 26.6, headless iPhone 16 / iOS 26.5):
  349 cases, 314 passed, 2 failed, 33 skipped; 0 compile errors; no build warning is
  attributable to any line added after `c921f14`.
- **Two confirmed production bugs are NOT fixed** (fix was blocked in the Mac session;
  needs the owner): `ConversationDetailViewModel` drops the `.conversationUpdated`
  object when re-posting on the main actor, and `MessagingSyncEngine.shouldIgnoreReadByUpdate`
  suppresses every `read_by`-only realtime update instead of only the current user's
  echo. Both are documented with file:line and fix sketches in CLAUDE.md Audit Notes;
  their two tests stay red on purpose.
- **Still manual:** dead-file deletion in Xcode; the simulator checklist with a
  non-admin account; the three dashboard items above.

## Next steps for the cloud session (written on the Mac, 2026-10-05)

> Executed on the Mac (see "Mac execution of the next steps" above). Only the Supabase dashboard items, the dead-file deletion in Xcode, the simulator checklist and the two production messaging bugs (`.conversationUpdated` object drop, `read_by` filter) remain.

The branch now has four Mac commits on top of `c921f14` (`0ad48c5`, `ec79930`,
`3ed86da`, `3cea181`). Pull before doing anything. Everything below is ordered by
what needs no Mac first.

### A. Reconcile with `claude/eloquent-hypatia-rar9pm` (cloud can do this)

That branch was developed in parallel from the same merge-base (`1898859`) and is
pushed. It carries `38d304d` (agent tooling for Xcode 26.6, Lane A/B/C), `0634cca`,
`5036a2c` (RenderPreview variant names), `e599c32` (test-target wiring repair) and
`6bb6df3` (deployment target raised to iOS 26.0 on all three targets — check whether
that was intended before merging it; CLAUDE.md on this branch still says the target
is iOS 17 and under review). Files modified by both branches since the merge-base,
so they will conflict:

`CLAUDE.md`, `README.md`, `AGENTS.md`, `.gitignore`, `.claude/settings.json`,
`scripts/verify-xcode-file-sync.sh`, `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`,
`NaarsCarsTests/Core/Services/PerformanceImprovementsTests.swift` (both branches move
it), and the eight `NaarsCars/*.swift` symlinks (both branches delete them).

Resolution guidance: for the docs, keep this branch's structure and fold in hypatia's
verification-lane and MCP-tool sections (they describe the only lanes that work on the
8 GB Mac). For `project.pbxproj`, take this branch's version wholesale — `7fcf3ff`
is a superset of `e599c32`, and the Mac build confirmed every reference resolves.
Do the merge in a scratch branch and leave it for a Mac build before merging to main.

### B. Tests the cloud can fix without a Mac (then a Mac run confirms)

1. `PushNotificationServiceTests` — now attached by `7fcf3ff`, so it runs in every
   suite: `testRequestPermission_ReturnsStatus` blocks on the simulator permission
   alert (times out at 60 s under `-test-timeouts-enabled`), and the register/remove
   token cases hit the live project. Inject a `UNUserNotificationCenter` stub and a
   mocked service, or `XCTSkip` the three until then.
2. `TownHallFeedViewModelTests.testLoadMore_LoadsAdditionalPosts` /
   `testDeletePost_RemovesFromArray` — live-backend tests whose outcome depends on how
   many posts exist and on sign-in state (they failed in the full run, passed in
   isolation). Mock `TownHallService` through the existing protocol.
3. `PerformanceImprovementsTests.testPerformanceMonitorPercentiles` and
   `AppLaunchManagerTests.testCriticalLaunchPathPerformance` — timing thresholds
   (the latter was 2.016 s against a 2.0 s limit while the Mac was under load).
   Relax or move to a measure block.
4. `AppLaunchManagerTests.testLaunchStateTransitions` asserts `.initializing` after
   launch has already run — test bug, not app bug.
5. The remaining baseline failures that are real assertions, not live-backend:
   `ImageCompressorTests` ×4 (these corroborate the unverified findings
   `images-media-1-1` / `utilities-maps-1-1`: resize renders at screen scale, so the
   presets overshoot), `ValidatorsTests` phone ×3, `MessagingSyncEngineTests` readBy,
   `MyProfileViewModelTests`, `ConversationDetailViewModelRealtimeTests`. Each needs
   a decision: fix the code or fix the test.
6. `LeaderboardServiceTests` ×4 and `NotificationServiceTests` ×4 are live-backend
   tests that get HTTP 500 anonymously — mock the services or skip.

### C. Backend follow-ups (cloud can prepare; dashboard actions are the user's)

- `20261005_0004` is still unapplied: the MCP declined `CREATE OR REPLACE` here too.
  Once the user runs it in the SQL editor, update the file's STATUS header.
- Push delivery evidence is thin: the only queue row with a real `sent_at` in the
  last 24 h is the handoff's own test row, and `function_edge_logs` show two
  invocations with no status code. Ask the user to send a message between two
  accounts on real devices and confirm a push arrives before the two disabled
  triggers are dropped.
- `notification_queue` still has 197 rows with `sent_at IS NULL`, the oldest from
  2026-01-21. The 330-row suppression did not cover them; decide whether they are
  stale (suppress with the same sentinel timestamp) or stuck.
- Credential rotation: the local `Secrets.swift` is on the `sb_publishable_…` key and
  REST accepts it. Update `Secrets.swift.template`, `README.md` and the comment in
  `obfuscate.swift` to describe the publishable key as the expected value. Legacy JWT
  keys must stay enabled until a build with the new key has shipped on the App Store.

### D. Mac-only (the user)

- Delete the seven dead files and their references in Xcode (see "Still manual").
- Run the simulator checklist in "Needs your Mac" step 3 with a non-admin account.
- Decide what to do with the `.worktrees/hypatia` checkout once A is merged.

## Needs your Mac (in this order)

1. `git fetch && git checkout claude/quirky-gates-4bkmv4`, open the project, build
   (`xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build`).
   Expect a handful of compile fixes; the heaviest edits are in
   `Core/Services/MessageService.swift`, `Core/Storage/*`, `Features/Messaging/*`,
   `App/AppDelegate.swift`, `Core/Services/PushNotificationService.swift` and the eleven
   new ViewModels. Watch for: `@MainActor @Sendable` closure captures in
   `MessagingSyncEngine`/`TypingIndicatorManager`, `await MessageSendManager()` from
   `PushNotificationService`, `AnyCodable` imports, and `@StateObject` on the new VMs.
2. Run the unit suites: `RefreshCoordinatorTests`, `AppLaunchManagerTests`,
   `NotificationsListViewModelTests`, `NavigationCoordinatorRoutingTests`,
   `NavigationCoordinatorTests`, `AppDelegateNotificationHandlingTests`,
   `DeepLinkParserTests`, `PromptCoordinatorTests`, `ReviewPromptProviderTests`,
   `LeaveReviewViewModelTests`, `ConversationsListViewModelTests`,
   `TownHallFeedViewModelTests`, `RealtimeManagerTests`, `MessagingRepositoryTests`,
   `PushNotificationServiceTests`, `MessageServiceTests`, `ClaimServiceTests`,
   `BackgroundSyncActorConversationSyncTests`, then the whole target.
3. Manual checks on a simulator with a **non-admin** account: sender names/avatars in
   conversations, user search, a public profile page, rides list as a guest (names
   visible), Requests tab after sign-out then sign-in, pull-to-refresh on every tab,
   quick reply from a push, delete account from Profile and from the Banned screen,
   report a post/comment/ride/favor/user, block/unblock, admin moderate, group creation.
4. Delete the dead files in Xcode (remove references too): `Features/Messaging/Views/DirectMessageContainerView.swift`,
   `Core/Services/MessagingDebugView.swift`, `Core/Utilities/Logger.swift`,
   `Features/Rides/Views/RidesDashboardView.swift` + `RidesDashboardViewModel.swift` + its test,
   `Features/Favors/Views/FavorsDashboardView.swift` + `FavorsDashboardViewModel.swift` + its test,
   and the eight `NaarsCars/*.swift` symlinks. Also `git rm --cached` the tracked
   `.DS_Store` files, `package-lock.json`, `supabase/.temp/*` and `QA/Reports/**/*.log`
   (all now gitignored).
5. Optional: Xcode 16+ "Convert to Folder" on the App/Core/Features/UI/NaarsCarsTests
   groups so new files are auto-discovered; then simplify `scripts/verify-xcode-file-sync.sh`.

## Needs the Supabase dashboard

- Run `supabase/migrations/20261005_0004_function_caller_guards.sql` in the SQL editor
  (admin guard on `send_approval_notification`, self-only typing RPCs). The MCP holds
  `CREATE OR REPLACE` for interactive confirmation, so it could not be applied here.
- Drop the disabled key-embedding triggers once you have seen a push arrive:
  `drop trigger "notifcation-queue-processor" on public.notification_queue;`
  `drop trigger message_push_webhook on public.messages;` and
  `drop function public.upsert_profile_for_signup(uuid, text, text, text, uuid);`
- Auth → Password security: enable leaked-password protection.
- **Rotate the service-role credential.** The legacy service_role JWT was committed in
  `WEBHOOK_CONFIG.md` (now redacted, still in history). Recommended path: move the app
  to the `sb_publishable_…` key in `Secrets.swift`, ship that build, then disable legacy
  JWT keys in API settings. Nothing server-side depends on the legacy key any more.

## Deferred on purpose (follow-ups)

- Immediate WebSocket teardown on background + foreground resubscribe (CLAUDE.md
  realtime rule 11); today a 30 s timer does it. Needs on-device verification.
- Idempotent message insert (client id as server id) so a network flap mid-send cannot
  duplicate a message. Requires simulator verification of the SwiftData reconciliation.
- Aggregate vote/comment-count RPC for Town Hall (client + migration + fixture test).
- Message-window pagination in `MessagingRepository.getMessages` and incremental
  hydration gating in `MessagingSyncEngine` (verifiers judged the proposed versions unsafe).
- Pruning of `SDNotification` rows; `TownHallFeedViewModel.loadMore` still writes on the
  main actor; `SDTownHallPost` lacks vote/review columns (enrichment fetch remains).
- ~24 services still have no protocol (see CLAUDE.md Architecture rule 4 note).
- Dependency bumps: supabase-swift 2.41.1 → 2.52+, firebase-ios-sdk 12.10 → 12.18 (do in Xcode).

## Performance findings applied (verified by two reviewers each)

| id | site | finding |
|---|---|---|
| services-network-1-1 | `Core/Services/MessageService.swift:503` | sendMessage issues 4 sequential round trips per text message (2 redundant membership pre-checks + insert + upd |
| services-network-1-2 | `Core/Services/RideService.swift:733` | fetchRide(id:) performs 5-6 serial round trips (poster, claimer, participants x2, QA count) that are all indep |
| services-network-1-3 | `Core/Services/TownHallService.swift:49` | fetchPosts chains 6 sequential round trips per page (posts → profiles → votes → comment rows → reviews → fulfi |
| services-network-1-4 | `Core/Services/MessageService.swift:143` | fetchMessages runs 4-7 serial round trips before returning (membership x2, joined_at, optional cursor lookup,  |
| services-network-1-5 | `Core/Services/RideService.swift:347` | updateRide/updateFavor pre-read the full enriched entity (6 RTTs) just to diff a few scalar fields before the  |
| services-network-1-6 | `Core/Services/ClaimService.swift:93` | claimRequest re-reads the request row twice after updating it and serializes two independent notification writ |
| services-network-1-7 | `Core/Services/NotificationService.swift:200` | markAsRead(notificationId:) wipes the whole notification cache and cancels in-flight fetches per call, and cal |
| services-network-1-8 | `Core/Services/MessageReactionService.swift:45` | addReaction performs two client-side lookup round trips before the upsert that RLS already enforces |
| services-network-1-9 | `Core/Services/RideService.swift:444` | fetchQA fetches asker profiles one-by-one in a serial loop instead of using the existing batch fetchProfiles |
| services-network-1-10 | `Core/Services/TownHallService.swift:463` | Comment and vote counts are computed by downloading every comment/vote row for the page; comment threads are f |
| services-network-1-12 | `Core/Services/LeaderboardService.swift:627` | findCurrentUserRank re-executes the full get_xp_leaderboard RPC immediately after the ViewModel already fetche |
| services-network-1-14 | `Core/Services/ConversationService.swift:242` | Conversation-list fallback downloads all unread message ids to count them and bypasses the profile cache, fann |
| storage-swiftdata-1-1 | `Core/Storage/MessagingRepository.swift:80` | getConversations() runs an N+1 last-message query on the main actor and is re-executed on every save() |
| storage-swiftdata-1-2 | `Core/Storage/BackgroundSyncActor.swift:249` | syncConversations loads the entire SDMessage table, saves unconditionally, flags every conversation as changed |
| storage-swiftdata-1-3 | `Core/Storage/MessagingRepository.swift:184` | getMessages() fetches and maps the entire conversation history with no fetchLimit on every save; getLatestMess |
| storage-swiftdata-1-4 | `Core/Storage/TownHallRepository.swift:36` | Town hall publishers subscribe to the global NSManagedObjectContextDidSave, so every save anywhere (messages,  |
| storage-swiftdata-1-5 | `Core/Storage/DashboardSyncEngine.swift:116` | performFullSync posts rides, favors AND notifications DidSync whenever any one record changed, and the rides/f |
| storage-swiftdata-1-6 | `Core/Storage/TownHallRepository.swift:59` | upsertPosts does a per-post fetch loop, a full-table fetch, and deletes every local post not in the page it wa |
| storage-swiftdata-1-7 | `Core/Storage/MessagingSyncEngine.swift:333` | hydrateConversation always downloads 50 messages and upserts them one-by-one with an individual SwiftData fetc |
| storage-swiftdata-1-10 | `Core/Storage/BackgroundSyncActor.swift:734` | SDNotification is never pruned: every dashboard sync loads the whole table and unbounded @Query lists grow for |
| storage-swiftdata-1-11 | `Core/Storage/TownHallRepository.swift:101` | upsertComments runs a fetch-by-id per comment and a full-field rewrite on the main actor; the BackgroundSyncAc |
| storage-swiftdata-1-12 | `Core/Storage/MessagingRepository.swift:163` | messageSubjects/messageMetadataSubjects are never evicted and each retains a fully mapped [Message] array for  |
| storage-swiftdata-1-13 | `Core/Storage/MessagingSyncEngine.swift:451` | precacheMedia downloads every incoming image/audio in full with an untracked URLSession task into URLCache, wh |
| messaging-ui-1-1 | `UI/Components/Messaging/Cells/ImageBubbleView.swift:96` | Image bubbles decode and retain full-resolution bitmaps for a 220x300pt view (no downsampling) |
| messaging-ui-1-2 | `Features/Messaging/Views/ConversationDetailView.swift:365` | highlightedMessageId is never cleared after tapping a reply preview, so every later update re-scrolls the list |
| messaging-ui-1-3 | `Features/Messaging/Views/MessagesViewControllerRepresentable.swift:157` | Input-bar reply/edit/image state is re-applied on every SwiftUI body evaluation: banner re-animates, edit text |
| messaging-ui-1-4 | `Features/Messaging/Views/ConversationsListView.swift:420` | Creating a group chat issues N+1 sequential Supabase queries (up to 100 round trips) |
| messaging-ui-1-5 | `UI/Components/Messaging/LinkPreviewView.swift:34` | LinkPreviewService reuses a single one-shot LPMetadataProvider, has no in-flight dedup, and keeps an unbounded |
| messaging-ui-1-6 | `UI/Components/Messaging/InputBarController.swift:168` | Every attached photo is JPEG-encoded at full resolution and the result is never used |
| messaging-ui-1-8 | `UI/Components/Messaging/Overlay/ReactionDetailsRowView.swift:308` | Reaction-details overlay downloads every reactor avatar with raw URLSession on each open, decoding on the main |
| messaging-ui-1-9 | `UI/Components/Messaging/Cells/MessageCellView.swift:195` | Avatars are re-read from disk and re-decoded on every cell configure/reconfigure (no same-URL guard, no memory |
| messaging-ui-1-11 | `Features/Messaging/Views/MessageThreadViewController.swift:653` | Full-screen image viewers bypass the disk cache and re-download images already cached by the bubble |
| messaging-ui-1-12 | `Features/Messaging/Views/MessagesViewController.swift:354` | Targeted reconfigure uses count-based proxies and misses reaction swaps, reply-context and sender hydration, m |

## Performance findings found but never verified (budget cut-off) — triage backlog

| id | site | finding |
|---|---|---|
| messaging-ui-1-13 | `Features/Messaging/Views/MessageDetailsPopup.swift:553` | Group details reload fetches profiles one by one (N+1) although a batch API is already used elsewhere |
| messaging-ui-1-14 | `Features/Messaging/Views/ConversationDetailView.swift:842` | participantIds is written to SwiftData and saved on every conversation open without compare-before-write |
| messaging-ui-1-15 | `UI/Components/Messaging/Cells/MessageCellView.swift:807` | Tap-to-show-timestamp invalidates the entire collection layout twice, and the height cache then returns the pr |
| swiftui-views-1-1 | `Features/Requests/Views/RequestsDashboardView.swift:104` | Requests tab re-fetches all rides+favors from network and rewrites SwiftData on main thread on every appearanc |
| swiftui-views-1-2 | `Features/Requests/Views/RequestsDashboardView.swift:109` | didSync observers trigger a second network fetch and second SwiftData write pass right after DashboardSyncEngi |
| swiftui-views-1-3 | `UI/Components/Common/CachedAsyncImage.swift:353` | Avatars and post photos are loaded full-resolution with no downsampling, no in-memory cache and no in-flight d |
| swiftui-views-1-4 | `Features/Rides/Views/RideDetailView.swift:113` | Detail screens re-run ride/favor fetch, Q&A fetch, review fetch, two geocodes and MKDirections on every appear |
| swiftui-views-1-5 | `UI/Components/Common/AvatarView.swift:99` | Every AvatarView observes the whole @Observable BadgeCache dictionary, so any badge store re-renders every ava |
| swiftui-views-1-6 | `Features/Community/Views/CommunityTabView.swift:261` | Explicit .id() on Town Hall / Leaderboard recreates their ViewModels on every segment toggle, defeating the 15 |
| swiftui-views-1-7 | `Features/Notifications/Views/NotificationsListView.swift:29` | Notification grouping/sorting of every SDNotification runs inside body on each render, and a DateFormatter is  |
| swiftui-views-1-8 | `Features/TownHall/Views/PostCommentsView.swift:328` | Each comment row builds a new RelativeDateTimeFormatter on every render |
| swiftui-views-1-9 | `Features/Profile/Views/SettingsView.swift:26` | LAContext/canEvaluatePolicy is executed in body up to three times per render of SettingsView (and 3x in AppLoc |
| swiftui-views-1-10 | `Features/Profile/Views/PublicProfileView.swift:137` | PublicProfileView fires 5 requests on every appearance with no loaded-guard, and re-stores badges that invalid |
| swiftui-views-1-11 | `Features/Community/Views/CommunityTabView.swift:277` | Community tab onAppear triggers a badge RPC via clearCommunityBadge even when there is nothing to clear |
| swiftui-views-1-12 | `Features/Profile/Views/XPHistorySheet.swift:477` | XPHistorySheet re-groups and re-sorts events with a freshly allocated DateFormatter on every body evaluation |
| swiftui-views-1-13 | `Features/Profile/Views/GuidelinesAcceptanceSheet.swift:115` | Guidelines sheet logs through os_log and writes state on every scroll frame |
| swiftui-views-1-14 | `Features/Profile/Views/SettingsView.swift:466` | Opening Settings performs a profile UPDATE as a side effect of loading preferences (write-on-read) |
| swiftui-views-1-15 | `Features/Authentication/Views/PendingApprovalView.swift:218` | Pending-approval screen polls the backend every 30 seconds for as long as it is on screen |
| viewmodels-1-1 | `/home/user/Naar-Caars-ios/Features/Requests/ViewModels/RequestsDashboardViewModel.swift:154` | Dashboard VM re-fetches all rides+favors over REST and re-writes SwiftData on the main actor every time the co |
| viewmodels-1-2 | `/home/user/Naar-Caars-ios/Features/Requests/ViewModels/RequestsDashboardViewModel.swift:350` | refreshFilteredRequests runs 4x per load, each doing 4 SwiftData fetches, full model conversions three times o |
| viewmodels-1-3 | `/home/user/Naar-Caars-ios/Features/Messaging/ViewModels/ConversationDetailViewModel.swift:351` | Read-receipt (readBy) metadata updates mutate `messages[index]`, which fires the full `messages` didSet cascad |
| viewmodels-1-4 | `/home/user/Naar-Caars-ios/Features/Messaging/ViewModels/ConversationDetailViewModel.swift:428` | Conversation open awaits a network round-trip (hasUserLeftConversation) before the locally cached messages are |
| viewmodels-1-5 | `/home/user/Naar-Caars-ios/Features/Messaging/ViewModels/ConversationsListViewModel.swift:292` | Conversations list VM performs its own remote conversation sync (main-actor SwiftData writes, no change detect |
| viewmodels-1-6 | `/home/user/Naar-Caars-ios/Features/TownHall/ViewModels/TownHallFeedViewModel.swift:162` | Town Hall feed re-fetches, re-sorts and republishes all posts on every SwiftData save anywhere in the app (mes |
| viewmodels-1-7 | `/home/user/Naar-Caars-ios/Features/TownHall/ViewModels/TownHallFeedViewModel.swift:66` | TownHall feed VM fetches posts from the network on every appear in addition to TownHallSyncEngine's coordinato |
| viewmodels-1-8 | `/home/user/Naar-Caars-ios/Features/Messaging/ViewModels/ConversationsListViewModel.swift:217` | applyUnreadCounts assigns `conversations[index]` inside a loop, re-running the filtered-list recompute and a S |
| viewmodels-1-9 | `/home/user/Naar-Caars-ios/Features/Profile/ViewModels/EditProfileViewModel.swift:129` | Every profile save re-encodes and re-uploads the user's existing avatar at JPEG quality 1.0, even when only na |
| viewmodels-1-10 | `/home/user/Naar-Caars-ios/Features/Messaging/ViewModels/TypingIndicatorManager.swift:152` | Every typing_indicators realtime event discards the payload and refetches the typing-user list via RPC (about  |
| viewmodels-1-11 | `/home/user/Naar-Caars-ios/Features/Notifications/ViewModels/NotificationsListViewModel.swift:107` | Notifications sheet re-fetches the 30-day notifications feed already synced by DashboardSyncEngine and re-sync |
| viewmodels-1-12 | `/home/user/Naar-Caars-ios/Features/Messaging/ViewModels/MessageSendManager.swift:203` | sendAudioMessage reads the recorded audio file from disk twice |
| viewmodels-1-13 | `/home/user/Naar-Caars-ios/Features/Messaging/ViewModels/MessageThreadViewModel.swift:196` | Thread view loads the parent message and its replies serially instead of concurrently |
| images-media-1-1 | `Core/Utilities/ImageCompressor.swift:121` | Resize renders at screen scale, so 'max 2048px' uploads are actually 4096-6144px (and 1920 becomes 5760) |
| images-media-1-2 | `Core/Services/PersistentImageService.swift:40` | Image loader always decodes full-resolution with no downsampling and no memory cache; every cell appearance re |
| images-media-1-3 | `Core/Services/MessageMediaService.swift:40` | Message photo is JPEG-encoded three times per send (one encode is discarded), and re-encoded again on retry |
| images-media-1-4 | `Features/Profile/ViewModels/EditProfileViewModel.swift:129` | Every profile save re-downloads, triple-encodes and re-uploads the avatar even when the photo was not changed |
| images-media-1-5 | `Core/Services/PersistentImageService.swift:37` | Disk cache key drops the URL query, so avatar cache-busting (?t=) never invalidates and users see stale avatar |
| images-media-1-6 | `Features/Messaging/Views/ConversationDetailView.swift:695` | Tapping an image in the canonical conversation screen uses raw AsyncImage, bypassing the disk cache and re-dow |
| images-media-1-7 | `Core/Storage/MessagingSyncEngine.swift:449` | Realtime media precache re-downloads our own just-uploaded photos and audio into a cache the UI does not read, |
| images-media-1-8 | `Core/Services/PersistentImageService.swift:57` | Disk image cache has no size bound, no eviction, and is never cleared (clearCache() has zero callers, includin |
| images-media-1-9 | `Core/Services/PersistentImageService.swift:52` | No in-flight request coalescing: N visible views for the same URL trigger N parallel downloads and N writes of |
| images-media-1-10 | `UI/Components/Common/AvatarUIView.swift:83` | Message-cell avatar is cleared and reloaded from disk on every reconfigure, including read-receipt and reactio |
| images-media-1-11 | `Features/Messaging/Views/MessageDetailsPopup.swift:451` | Group photo is JPEG-encoded at full resolution on the main actor, then decoded and compressed again by the ser |
| images-media-1-12 | `Core/Services/ReviewService.swift:187` | Review photo is compressed in the ViewModel and then decoded and compressed again in the service |
| images-media-1-13 | `UI/Components/Messaging/LinkPreviewView.swift:33` | Link-preview cache stores full-size image Data without bounds and views re-decode it on every configure; metad |
| images-media-1-14 | `UI/Components/Messaging/Overlay/ReactionDetailsRowView.swift:307` | Reaction-details avatars are fetched with URLSession directly, bypassing the image cache and decoding full-siz |
| images-media-1-15 | `UI/Components/Common/CachedAsyncImage.swift:58` | URL change while a load is in flight is dropped, leaving the old image or error state on screen |
| realtime-push-badges-1-1 | `/home/user/Naar-Caars-ios/Core/Storage/MessagingSyncEngine.swift:359` | Reactions WebSocket channel is unfiltered: every reaction in the community is streamed to every client with an |
| realtime-push-badges-1-2 | `/home/user/Naar-Caars-ios/Core/Services/PushNotificationService.swift:789` | One foreground push triggers the coordinator twice (willPresent + didReceiveRemoteNotification), and the badge |
| realtime-push-badges-1-3 | `/home/user/Naar-Caars-ios/Core/Services/BadgeCountManager.swift:89` | refreshAllBadges debounce is neither an in-flight guard nor trailing-edge: concurrent triggers all run, later  |
| realtime-push-badges-1-4 | `/home/user/Naar-Caars-ios/Core/Services/RefreshCoordinator.swift:276` | "Targeted" conversations refresh ignores entityId and performs a full conversation-list RPC + sync for every m |
| realtime-push-badges-1-5 | `/home/user/Naar-Caars-ios/Core/Services/BadgeCountManager.swift:303` | Admin badge refresh fetches every pending user's full profile (plus a separate admin re-check) just to count t |
| realtime-push-badges-1-6 | `/home/user/Naar-Caars-ios/Core/Storage/MessagingSyncEngine.swift:240` | Subscribe-then-fetch 3s deadline is never enforced and channel joins are serialized, delaying the REST hydrate |
| realtime-push-badges-1-7 | `/home/user/Naar-Caars-ios/Core/Storage/MessagingSyncEngine.swift:62` | Conversation list is fetched and synced by startSync() outside the coordinator at launch, so the first Message |
| realtime-push-badges-1-8 | `/home/user/Naar-Caars-ios/Core/Storage/MessagingSyncEngine.swift:167` | Every realtime message event performs a main-actor SwiftData save plus a full N+1 conversation re-fetch and fu |
| realtime-push-badges-1-9 | `/home/user/Naar-Caars-ios/Core/Services/RealtimeManager.swift:605` | Foreground restore runs twice (willEnterForeground + didBecomeActive) with no in-progress guard, producing dup |
| realtime-push-badges-1-10 | `/home/user/Naar-Caars-ios/Core/Storage/MessagingSyncEngine.swift:451` | Media precache double-downloads every received image (and fully downloads audio) with untracked, uncancellable |
| realtime-push-badges-1-11 | `/home/user/Naar-Caars-ios/Core/Services/BadgeCountManager.swift:260` | Tab switches add a second badge RPC via clear*Badge, and clearCommunityBadge issues one PATCH per unread commu |
| realtime-push-badges-1-12 | `/home/user/Naar-Caars-ios/Core/Services/BadgeCountManager.swift:100` | Every badge refresh requests include_details=true, paying two extra server aggregations and decoding request d |
| realtime-push-badges-1-13 | `/home/user/Naar-Caars-ios/Core/Services/RealtimeManager.swift:149` | Realtime payload normalization uses Mirror reflection (with a JSONEncoder/JSONSerialization fallback) for ever |
| realtime-push-badges-1-14 | `/home/user/Naar-Caars-ios/Core/Services/RealtimeManager.swift:290` | Every channel subscribe re-reads the auth session and re-sends setAuth/connect, and spawns a 2s sleeper task,  |
| utilities-maps-1-1 | `/home/user/Naar-Caars-ios/Core/Utilities/ImageCompressor.swift:121` | Image resize renders at screen scale, producing a 2x/3x-pixel bitmap instead of the preset's max dimension |
| utilities-maps-1-2 | `/home/user/Naar-Caars-ios/Core/Services/MapService.swift:96` | Single shared CLGeocoder driven concurrently by batchGeocode and async-let callers causes cancelled/rate-limit |
| utilities-maps-1-3 | `/home/user/Naar-Caars-ios/Core/Services/MapService.swift:113` | No geocode memoization: identical addresses re-geocoded (up to 5 remote calls each) on every map open, every r |
| utilities-maps-1-4 | `/home/user/Naar-Caars-ios/Core/Utilities/DateDecoderFactory.swift:30` | makeSupabaseDecoder allocates an ISO8601DateFormatter and a DateFormatter for every Date field decoded |
| utilities-maps-1-5 | `/home/user/Naar-Caars-ios/Core/Utilities/GeocodingCacheService.swift:60` | Ride cost estimation performs a Supabase round-trip 'cache' in front of on-device reverse geocoding, upserts a |
| utilities-maps-1-6 | `/home/user/Naar-Caars-ios/Core/Services/CurrentLocationProvider.swift:23` | One-shot origin lookup demands 10m GPS accuracy with a 2s timeout and issues requestLocation twice, so users w |
| utilities-maps-1-7 | `/home/user/Naar-Caars-ios/Core/Utilities/FlightCodeParser.swift:97` | Flight parsers compile NSRegularExpression on every call (up to ~14 compiles per ride) and the first parse dec |
| utilities-maps-1-8 | `/home/user/Naar-Caars-ios/Core/Utilities/URLDetectionCache.swift:17` | URLDetectionCache is unbounded and keyed by full message text, retaining every rendered message body for the p |
| utilities-maps-1-9 | `/home/user/Naar-Caars-ios/Core/Utilities/RideCostEstimator.swift:511` | formatCost builds a currency NumberFormatter on every call from RideDetailView's body |
