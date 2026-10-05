# Post-merge test hardening and credential-rotation docs (2026-10-05)

Branch: `claude/quirky-gates-4bkmv4` after the merge of `claude/eloquent-hypatia-rar9pm` (e804569).
Goal: make the unit suite deterministic on the headless lane, fix the real assertion
failures where the code is wrong, and finish the publishable-key documentation.

## Global Constraints (binding for every task)

- Work only in `/Users/bcolf/Documents/naars-cars-ios` on the current branch. Commit each task; never push.
- **One build at a time on this Mac (8 GB).** Never run two `xcodebuild` processes. Never open Xcode.app or Simulator.app. Use exactly these commands (Lane B), substituting the test class/method:
  - build: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData -quiet build`
  - focused tests: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/<Class> -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|Test Case .* (passed|failed)|Executed [0-9]+ tests|BUILD|TEST"`
  - Do NOT run the whole suite; the controller runs it once at the end.
- Tests are XCTest; follow the patterns already in `NaarsCars/NaarsCarsTests/`. Do not add new test files (a new file is not compiled until it is added to the project in Xcode, which you cannot do). Edit existing test files only.
- Do not hand-edit `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`.
- `CLAUDE.md` governs. Fragile/high-risk files (`PushNotificationService.swift`, `MessagingSyncEngine.swift`, `MessagingRepository.swift`, `RealtimeManager.swift`, `MessageSendManager.swift`, `BadgeCountManager.swift`, `NavigationCoordinator.swift`, `AuthService.swift`, `BackgroundSyncActor.swift`, `SDModels.swift`, `RefreshCoordinator.swift`): change them only when the task explicitly allows it, keep the diff minimal, and state the invariant you preserved in your report. If fixing a test would require a behavioral change in one of these files, do not make it — report DONE_WITH_CONCERNS describing the suspected bug instead.
- A test that is skipped must use `XCTSkip` with a reason string that names what is missing (e.g. "requires an authenticated session"); never delete a test and never make a test assert nothing.
- Keep user-facing strings localized; do not touch `Localizable.xcstrings` in these tasks.
- Report test evidence: the exact command, and the `Test Case ... passed/failed` lines plus the `Executed N tests` line.

## Task 1: Make PushNotificationServiceTests deterministic

File: `NaarsCars/NaarsCarsTests/Core/Services/PushNotificationServiceTests.swift` (attached to the target; runs in every suite).
Current failures in the full headless run:
- `testRequestPermission_ReturnsStatus` calls `PushNotificationService.shared.requestPermission()`, which calls the real `UNUserNotificationCenter.requestAuthorization`; on the simulator this blocks on the permission alert and times out at 60 s.
- `testRegisterToken_SavesToDB` and `testRemoveToken_RemovesFromDB` call the live Supabase project and fail with HTTP 500 (no authenticated session).

Facts: `PushNotificationService` is a singleton (`static let shared`, `private override init()`) with `private let notificationCenter = UNUserNotificationCenter.current()` at line ~105; it is a high-risk file. `LeaderboardServiceTests` and `NotificationServiceTests` already use the pattern `guard let userId = AuthService.shared.currentUserId else { throw XCTSkip("No authenticated user for testing") }`.

Requirements:
1. The three tests must no longer block, time out, or hit the live backend when run on a simulator without an authenticated session.
2. Preferred for the permission test: if `PushNotificationService` can take an injectable notification-center seam with a diff of a few lines that does not change runtime behavior (e.g. an `internal`/`@testable` initializer or a protocol-typed property defaulting to `UNUserNotificationCenter.current()`), add it and drive the test with a stub whose `requestAuthorization` returns a fixed value. If that cannot be done without a behavioral change to the service, skip the test with `XCTSkip("requires a stubbed UNUserNotificationCenter; the real one blocks on the simulator permission alert")`.
3. The two token tests: skip with `XCTSkip` when `AuthService.shared.currentUserId` is nil (same pattern as the other service tests). Do not weaken their assertions when a session exists.
4. Run `-only-testing:NaarsCarsTests/PushNotificationServiceTests` and report the per-case result (passed or skipped; nothing failed, nothing timed out).

## Task 2: Make TownHallFeedViewModelTests independent of live data

File: `NaarsCars/NaarsCarsTests/Features/TownHall/TownHallFeedViewModelTests.swift`.
`testLoadMore_LoadsAdditionalPosts` (asserts the post count is unchanged when `hasMore` is false, which is wrong when page 2 returns fewer than a page) and `testDeletePost_RemovesFromArray` (deletes the first real post, which fails without an authorized session) depend on live backend data; they failed in the full run and passed in isolation.

Facts: `TownHallFeedViewModel.init(repository: TownHallRepository? = nil, townHallService: TownHallService? = nil, ...)` (line ~37); `TownHallService` has no protocol in `Core/Protocols/`; `refreshFromNetwork` also calls `RefreshCoordinator.shared.forceFullRefreshAndWait(.townHall, ...)` so a full mock is not available without touching the coordinator (not allowed).

Requirements:
1. `testLoadMore_LoadsAdditionalPosts`: fix the assertion logic so it is correct for the real contract: after `loadMore()`, `posts.count >= initialCount`; if `hasMore` is false afterwards, the number of posts added must be less than `viewModel.pageSize` (expose `pageSize` to tests only if it is not already readable; `internal` is enough with `@testable`). Skip with `XCTSkip` when `AuthService.shared.currentUserId` is nil, because the feed requires a session.
2. `testDeletePost_RemovesFromArray`: skip with `XCTSkip` when there is no authenticated session or when the first post is not authored by the current user (deleting someone else's post is rejected by RLS). Keep the assertions as they are for the case that does run.
3. Do not change `TownHallFeedViewModel` behavior. Do not introduce a protocol for `TownHallService` in this task.
4. Run `-only-testing:NaarsCarsTests/TownHallFeedViewModelTests` and report per-case results.

## Task 3: Timing-sensitive and state-order tests in AppLaunchManagerTests and PerformanceImprovementsTests

Files: `NaarsCars/NaarsCarsTests/Core/Services/AppLaunchManagerTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/PerformanceImprovementsTests.swift`.
- `AppLaunchManagerTests.testCriticalLaunchPathPerformance` asserts the critical launch path takes under 2.0 s; it measured 2.016 s while the Mac was loaded. Raise the allowance to a value that still catches a regression (5.0 s) and say in the assertion message that the limit allows for a loaded CI/dev machine.
- `AppLaunchManagerTests.testLaunchStateTransitions` (line ~50) asserts the state equals `.initializing` after launch has already run and gets `ready(.unauthenticated)`. Rewrite the test so it asserts the actual contract of the state machine `initializing → checkingAuth → ready(authState)`: capture the initial state before launching if the manager exposes it, otherwise assert the post-launch state is a `.ready` case. Do not change `AppLaunchManager`.
- `PerformanceImprovementsTests.testPerformanceMonitorPercentiles` (line ~241) asserts "P50 should be around 50ms" from wall-clock sleeps. Make it deterministic: feed the monitor recorded durations directly (if `PerformanceMonitor.record(operation:duration:metadata:)` is available, use it with fixed durations such as 10, 20, …, 100 ms) and assert the percentiles exactly against those inputs with a small tolerance. If the monitor cannot be fed fixed durations, widen the tolerance so a loaded machine cannot fail it and document why.
Run `-only-testing:NaarsCarsTests/AppLaunchManagerTests -only-testing:NaarsCarsTests/PerformanceImprovementsTests` and report per-case results.

## Task 4: ImageCompressor presets must honor their max dimension

Files: `NaarsCars/Core/Utilities/ImageCompressor.swift`, `NaarsCars/NaarsCarsTests/Core/Utilities/ImageCompressorTests.swift`.
Failures: `testAvatarPresetReducesDimensionsCorrectly` got 3072 instead of 1024 px; `testMessageImagePresetReducesDimensionsCorrectly` got 6144 instead of 2048; `testFullSizePresetReducesDimensionsCorrectly` got 6000 instead of ≤ 2000; `testImageCompressionMeetsSizeLimits` got 553 KB instead of < 500 KB for `messageImage`.
Root cause (performance finding images-media-1-1): `ImageCompressor.resize(_:maxDimension:)` (line ~100) builds `UIGraphicsImageRenderer(size: newSize)` with the default format, whose `scale` is the screen scale (3× on the simulator), so the rendered bitmap is 3× the intended pixel size and the JPEG is correspondingly larger.
Requirements:
1. Render at scale 1 (`UIGraphicsImageRendererFormat` with `scale = 1`, or the `default()` format with `scale` set to 1) so the output bitmap has exactly `maxDimension` on its longer side. Keep the aspect ratio and the rest of the compression pipeline unchanged.
2. All four tests must pass without changing their expected values. Confirm the size-limit test now passes because of the smaller bitmap; if it still fails, report why rather than loosening the limit.
3. Check callers for any code that compensated for the 3× overshoot (e.g. dividing dimensions by screen scale) and report what you found; do not change callers unless one is demonstrably broken by the fix.
Run `-only-testing:NaarsCarsTests/ImageCompressorTests` and report per-case results.

## Task 5: ValidatorsTests phone cases

Files: `NaarsCars/Core/Utilities/Validators.swift` (uses PhoneNumberKit's `PhoneNumberUtility`), `NaarsCars/NaarsCarsTests/Core/Utilities/ValidatorsTests.swift`.
Failures: `testIsValidPhoneNumber_ValidUS_ReturnsTrue` (every case using area code 123), `testIsValidPhoneNumber_International_ReturnsTrue` (lines 39–40), `testFormatPhoneForStorage_ReturnsE164` (expects "+11234567890" and "+441234567890").
Requirements:
1. Determine whether the validator is wrong or the test fixtures are not real numbers. PhoneNumberKit rejects numbers like 123-456-7890 (area code 123 is not assignable), so the expected outcome is that the fixtures are invalid, not the code.
2. If the fixtures are the problem, replace them with numbers PhoneNumberKit accepts (e.g. US `2015550123` → `+12015550123`; UK `+44 20 7946 0958`) and keep each case's intent (10-digit, formatted, dashed, dotted, with country code, 11-digit leading 1; international; storage formatting adds `+` and the country code). If the validator is actually wrong for a realistic number, fix the validator and explain.
3. Do not relax `isValidPhoneNumber` to accept non-assignable numbers.
Run `-only-testing:NaarsCarsTests/ValidatorsTests` and report per-case results.

## Task 6: Three messaging/profile test failures — diagnose, fix test or report bug

Files: `NaarsCars/NaarsCarsTests/Core/Services/MessageServiceTests.swift` (contains `ConversationDetailViewModelRealtimeTests.testRealtimeMessageInsertUpdatesViewModel` at line ~129 and `MessagingSyncEngineTests.testShouldIgnoreReadByUpdate_ReturnsFalseForOtherUserRead` at line ~183) and `NaarsCars/NaarsCarsTests/Features/Profile/MyProfileViewModelTests.swift` (`testLoadProfile_Success_SetsAllProperties`, `XCTAssertNotNil failed` at line 34).
These have failed since before the cleanup branch. For each:
1. Read the test and the code it exercises. Decide whether the test encodes an outdated contract (fix the test to the current, documented behavior) or whether the code violates a documented invariant in `CLAUDE.md` (do not fix fragile code here: write the finding in your report with file:line and the invariant, and leave the test failing).
2. `testShouldIgnoreReadByUpdate_ReturnsFalseForOtherUserRead`: CLAUDE.md says metadata-only (readBy) updates must not trigger full recomputation; check what `shouldIgnoreReadByUpdate` is meant to return for another user's read and whether the test's expectation matches the current contract.
3. `testRealtimeMessageInsertUpdatesViewModel`: the active-conversation pipeline is WebSocket → adapter → sync engine → repository → publisher → view model; if the test posts a legacy NotificationCenter notification that the view model no longer observes, the test is outdated — rewrite it against the current publisher path only if that can be done with existing test seams; otherwise skip it with an `XCTSkip` reason naming the missing seam.
4. `MyProfileViewModelTests`: if the test needs a live session, apply the `XCTSkip` pattern when `AuthService.shared.currentUserId` is nil; if it uses a mock that no longer matches the view model, update the mock.
Run `-only-testing:NaarsCarsTests/ConversationDetailViewModelRealtimeTests -only-testing:NaarsCarsTests/MessagingSyncEngineTests -only-testing:NaarsCarsTests/MyProfileViewModelTests` and report per-case results.

## Task 7: LeaderboardServiceTests and NotificationServiceTests without a session

Files: `NaarsCars/NaarsCarsTests/Core/Services/LeaderboardServiceTests.swift`, `NaarsCars/NaarsCarsTests/Core/Services/NotificationServiceTests.swift`.
Both already `XCTSkip` the cases that need `AuthService.shared.currentUserId`; the remaining cases (`testFetchLeaderboard_OrderedByXP`, `testFetchSpotlights`, `testFindUserRank_NotInTop50`, `testBadgeConsistency`, `testFetchNotifications_PinnedFirst`, `testFetchUnreadCount_ReturnsCorrectCount`, `testMarkAsRead_Success`, `testMarkAllAsRead_Success`) call the live project anonymously and get HTTP 500.
Requirements:
1. Apply the same `XCTSkip` guard to every case that performs a network call, so the classes are green-or-skipped without a session and still run their real assertions when a session exists.
2. `NotificationServiceProtocol` exists in `Core/Protocols/`; if a mock conforming to it already exists under `NaarsCarsTests/`, prefer using it for the `NotificationServiceTests` cases that only need deterministic data (pinned-first ordering, unread count) instead of skipping. Do not create a protocol for `LeaderboardService` in this task.
Run `-only-testing:NaarsCarsTests/LeaderboardServiceTests -only-testing:NaarsCarsTests/NotificationServiceTests` and report per-case results.

## Task 8: Publishable-key documentation

Files: `NaarsCars/Core/Utilities/Secrets.swift.template`, `NaarsCars/Scripts/obfuscate.swift`, `README.md`, `SECURITY.md` (only the key-rotation subsection, §3.2 if present).
The app's local `Secrets.swift` now carries the Supabase `sb_publishable_…` key (modern publishable key) instead of the legacy anon JWT; `SupabaseConnectionTests.testCredentialsAreConfigured` asserts the `sb_publishable_` prefix. No code change.
Requirements:
1. `Secrets.swift.template`: name the second credential as the publishable key (`sb_publishable_…`), keep the property name `supabaseAnonKey` for source compatibility, and say in its doc comment that the legacy anon JWT is no longer the expected value.
2. `obfuscate.swift`: the usage text and the printed comments should say "publishable key (sb_publishable_…)"; drop the note that claims the publishable key is the same as the anon key.
3. `README.md` secrets-setup section: say the publishable key from Supabase → Project Settings → API keys is the value to obfuscate, and that legacy JWT keys stay enabled until a build with the publishable key has shipped (the live App Store build still uses the legacy anon key).
4. `SECURITY.md` §3.2 (service-role key in git history): add a dated line that the client moved to the publishable key on 2026-10-05, that the legacy service_role JWT must be rotated by disabling legacy keys in API settings once the publishable-key build has shipped, and that nothing server-side depends on it (webhooks use the Vault secret).
No build needed; run `scripts/pre-commit-secrets-check.sh` if it accepts a path, otherwise just commit (the pre-commit hook runs it).
