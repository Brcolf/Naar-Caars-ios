# Naars Cars iOS Performance + Reliability Implementation Plan

Date: 2026-02-07
Owner: Engineering
Status: In progress

## 1) Goals and non-negotiables

- Keep all existing functionality intact while improving startup speed, smoothness, and chat latency.
- Prioritize critical request flow: create -> claim -> complete -> review.
- Secondary priority: messaging quality approaching iMessage responsiveness.
- Maintain security and RLS integrity (no policy weakening that opens data access).
- Preserve current subtle message-send UI.
- Claiming must stay server-confirmed (no offline claim completion).

## 2) Product decisions captured

- Device certification target: iPhone 12 through iPhone 17 Pro Max.
- OS target: iOS 17+ (certify on lowest supported and latest available OS).
- Environments: execute rollout path in both staging and production.
- Physical device baseline available: iPhone 12 and iPhone 17 Pro.
- Large-screen certification: include at least one Pro Max device in manual matrix.
- Read receipts: mark as read immediately in UI.
- Typing indicators: realtime only (no polling fallback).
- Search behavior: exact substring search.
- Eventual consistency: acceptable for non-claim operations, user-visible convergence within 1-2 seconds where applicable.
- Offline support: offline read for cached requests/messages, queued message send with retry/edit/cancel.
- Queue retention: unsent queued messages persist indefinitely while labeled unsent.
- Queue cap: no hard limit requested.
- Queue ordering on reconnect: server-accept ordering.
- Claims: require live server confirmation.
- Claim UX: show explicit server-confirming state and immediate modal error on failure.
- Badge parity: notification badge and inbox unread must match exactly.
- Rollout preference: sequential with manual test checklist and rollback safety.
- Rollout gate cadence: evaluate phases sequentially (no parallel gate windows).
- Performance priority: latency first, with battery-aware limits.
- Memory: aggressive control on lower-end devices is acceptable.
- Offline cache purge window target: 14 days.
- Debug controls: feature toggles remain debug-only.

## 3) Performance SLOs and release gates

## Startup and interaction

- Cold start to first interactive frame (iPhone 12, release build):
  - p50 <= 1.5s
  - p95 <= 2.5s
- Warm foreground resume:
  - p95 <= 700ms
- App launch failure rate:
  - <= 0.2%

## Smoothness

- Critical screens (requests list, conversation detail, claim sheets):
  - >= 55 FPS p95 on iPhone 12
  - Main-thread stalls > 250ms: <= 0.5 per 10 min active session
- Text-entry freeze rate (conversation input focus):
  - <= 0.1% sessions

## Messaging

- Send tap -> local bubble visible:
  - p95 <= 120ms
- Send tap -> server accepted (normal network):
  - p95 <= 500ms
- Conversation open to render first messages:
  - cached p95 <= 250ms
  - network p95 <= 1.2s

## Reliability

- Crash-free sessions: >= 99.9%
- Fatal crash-free users (7-day rolling): >= 99.8%
- Realtime subscription failure events: <= 0.5% sessions

## 4) Current high-impact issues to resolve first

- Too much service work isolated to `@MainActor` in hot paths:
  - `NaarsCars/Core/Services/MessageService.swift`
  - `NaarsCars/Core/Services/ConversationService.swift`
  - `NaarsCars/Core/Services/RideService.swift`
  - `NaarsCars/Core/Services/FavorService.swift`
  - `NaarsCars/Core/Services/NotificationService.swift`
- Message row invalidation storm from shared audio progress updates:
  - `NaarsCars/UI/Components/Messaging/MessageBubble.swift`
  - `NaarsCars/UI/Components/Messaging/MessageAudioPlayer.swift`
- Frequent `last_seen` writes from UI lifecycle/list updates:
  - `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- Startup duplication and eager sync work:
  - `NaarsCars/App/NaarsCarsApp.swift`
  - `NaarsCars/App/ContentView.swift`
  - `NaarsCars/App/AppLaunchManager.swift`
- Realtime event handling triggers full refreshes:
  - `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
  - `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift`
- N+1 database/service patterns in conversation and request enrichment.

## 5) Execution phases (sequential, rollback-safe)

## Phase 0: Instrumentation + guardrails (no behavior changes)

- Wire runtime instrumentation to production-safe metrics:
  - Launch metrics, conversation-open latency, send latency, claim latency, input focus stalls.
- Reuse existing services:
  - `NaarsCars/Core/Services/CrashReportingService.swift`
  - `NaarsCars/Core/Services/AppLogger.swift`
  - `NaarsCars/Core/Services/PerformanceMonitor.swift` (currently test-heavy; wire to runtime call sites).
- Add MetricKit integration (`MXMetricManager`) for hang/stall diagnostics.
- Add feature flags for each phase; default off in release until staged rollout.
- Add debug-only “Performance Flags” section in settings for internal testing.

Exit criteria:
- Metrics dashboard is populated for all target operations.
- All new behavior changes are flag-protected.

## Phase 1: Startup optimization and boot orchestration

- Consolidate launch/auth checks into one orchestrator.
- Defer non-critical sync engines until first frame is rendered.
- Keep request/notification/message lightweight prewarm, not full-refresh at launch.
- Remove duplicate startup calls and redundant observer-triggered boot paths.

Target files:
- `NaarsCars/App/NaarsCarsApp.swift`
- `NaarsCars/App/ContentView.swift`
- `NaarsCars/App/AppLaunchManager.swift`

Exit criteria:
- Cold start p95 meets target on iPhone 12.
- No launch regressions in auth/deep-link flows.

## Phase 2: Main-thread budget recovery

- Refactor service classes so heavy decode/mapping/query composition runs off main actor.
- Restrict `@MainActor` to UI state mutation points in ViewModels/Views.
- Convert mutable shared caches to actor-protected stores where needed.
- Replace blocking `Data(contentsOf:)` paths with async file/network APIs.

Target files:
- `NaarsCars/Core/Services/MessageService.swift`
- `NaarsCars/Core/Services/ConversationService.swift`
- `NaarsCars/Core/Services/RideService.swift`
- `NaarsCars/Core/Services/FavorService.swift`
- `NaarsCars/Core/Services/PersistentImageService.swift`
- `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`
- `NaarsCars/UI/Components/Messaging/ImageViewerView.swift`

Exit criteria:
- Main-thread stall rate reduced by at least 50% from baseline.
- No regression in functionality or security checks.

## Phase 3: Messaging latency + smoothness hardening

- Scope audio progress updates to active message only; stop global bubble invalidation.
- Debounce and batch `last_seen` writes; keep read state immediate in UI.
- Route all send operations through queue-aware repository path.
- Add explicit queued states internally while preserving subtle visual treatment.
- Enable edit/cancel for queued pending messages.
- Remove polling-based typing manager and use realtime-only typing updates.

Target files:
- `NaarsCars/UI/Components/Messaging/MessageBubble.swift`
- `NaarsCars/UI/Components/Messaging/MessageAudioPlayer.swift`
- `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`
- `NaarsCars/Core/Storage/MessagingRepository.swift`
- `NaarsCars/Core/Storage/MessagingSyncEngine.swift`
- `NaarsCars/Features/Messaging/ViewModels/TypingIndicatorManager.swift`

Exit criteria:
- Input-focus freeze rate <= 0.1% sessions.
- Send->server p95 <= 500ms under standard network profile.

## Phase 4: Requests + notifications decoupling

- Replace full-list refresh on realtime events with incremental item patching.
- Split bell badge updates from heavy requests dashboard refresh logic.
- Add coalescing window for bursts of realtime changes (short debounce).
- Preserve deep-link and breadcrumb behavior.

Target files:
- `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
- `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift`
- `NaarsCars/Core/Services/BadgeCountManager.swift`
- `NaarsCars/App/NavigationCoordinator.swift`

Exit criteria:
- Request flow remains correct with lower refresh overhead.
- Notification bell updates in <= 1-2s without full dashboard recompute.

## Phase 5: Database path optimization (RLS-safe)

- Replace N+1 query sequences with batched queries/RPCs.
- Keep exact substring search semantics; optimize with indexes suited to `%query%` workloads.
- Add/adjust indexes for hottest tables/filters used in requests, conversations, and messages.
- Prefer additive migrations only; no edits to existing SQL migration files.

Expected migration additions (new files in `database/`):
- batched conversation details RPC (if existing RPC not sufficient)
- participant lookup optimization
- message search index tuning for exact substring
- request/notification hot query indexes

Exit criteria:
- p95 DB-backed API latencies reduced materially from baseline.
- RLS policy checks remain correct across all role paths.

## Phase 6: RLS policy performance audit and hardening

- Audit policy cost and failure patterns in messaging + claim-related tables.
- Simplify high-cost policy expressions while preserving access boundaries.
- Use narrowly scoped RPC wrappers only where policy cost is proven high.
- Validate with claim flow and messaging access matrix tests.

Exit criteria:
- Fewer RLS-related operational errors.
- No unauthorized access paths introduced.

## Phase 7: Offline resilience completion

- Ensure cached conversation/request reads work offline.
- Queue compose/send/edit/cancel operations for messages only.
- Enforce server-required online path for claims.
- Reconnect replay processes queued actions in server-accept order.

Exit criteria:
- Offline message workflow is predictable and non-destructive.
- Claims remain online-only and reliable.

## Phase 8: Cleanup, accessibility, localization, and flag retirement

- Remove remaining hardcoded user-facing strings.
- Validate accessibility labels/hints/identifiers for critical controls.
- Remove or compile-gate temporary debug flag UI for production.
- Keep feature flags in internal builds for emergency rollback only.

Exit criteria:
- No accessibility/localization regressions in critical flows.
- Production build has no exposed developer toggles.

## 6) Anti-regression engineering constraints

- Keep existing public function signatures where possible; introduce adapters instead of rewiring call sites in one step.
- Avoid broad refactors that reorder initialization semantics in one PR.
- One behavior change category per PR (startup, messaging, requests, DB, etc.).
- All risky changes behind flags with immediate rollback path.
- No schema-destructive migrations; additive only.
- Claims path explicitly validated after every phase.

## 7) Supabase and schema audit plan

- Run schema inventory:
  - tables, indexes, RLS policies, RPC functions, trigger functions.
- Pull query plans for hot queries:
  - conversation list/details
  - message search
  - request feed filters
  - notification feed + unread counts
- Produce RLS simplification plan with before/after policy checks.
- Produce migration set with rollback notes.

## 8) Release strategy

- Stage A: Internal/devfood with all phase flags ON.
- Stage B: 5% external with strict gates (24-48h).
- Stage C: 25%, then 50%, then 100% only if gates pass.
- If a gate fails, disable the phase flag and re-baseline.

## 9) Manual certification matrix (required devices)

- iPhone 12
- iPhone 12 Pro/Pro Max
- iPhone 13
- iPhone 13 Pro/Pro Max
- iPhone 14
- iPhone 14 Pro/Pro Max
- iPhone 15
- iPhone 15 Pro/Pro Max
- iPhone 16
- iPhone 16 Pro/Pro Max
- iPhone 17
- iPhone 17 Pro/Pro Max

Minimum test OS span:
- Oldest supported iOS (17.x)
- Latest production iOS available at rollout time

## 10) Manual test checklist (high-priority)

- Launch cold/warm/offline.
- Create/claim/complete/review flow end-to-end.
- Claim failure handling and retry.
- Notifications in-app + background + deep link + clear states.
- Messaging send/receive/read/typing/search/media under good and degraded network.
- Text-field focus stress test in conversation detail (repeat open/close + typing + incoming events).
- Offline read and message queue replay behavior.
- Multi-device conflict tests for requests and messaging.
- Accessibility verification for critical controls.

## 11) Implementation work breakdown (initial sprint-ready backlog)

- Task 0.1: Add launch and messaging latency markers.
- Task 0.2: Add MetricKit collector and Crashlytics bridge keys.
- Task 0.3: Add `PerformanceFlags` debug UI (DEBUG only).
- Task 1.1: Consolidate launch flow and defer non-critical sync.
- Task 2.1: Remove `@MainActor` from heavy service operations.
- Task 2.2: Replace synchronous file I/O in messaging/media paths.
- Task 3.1: Isolate audio progress updates to active row.
- Task 3.2: Debounce `last_seen` writes.
- Task 3.3: Route send/edit/cancel through repository queue.
- Task 4.1: Incremental realtime patching for requests dashboard.
- Task 4.2: Bell badge decoupling from full request refresh.
- Task 5.1: Add batched conversation enrichment RPC/indexes.
- Task 5.2: Add exact-substring search index tuning.
- Task 6.1: RLS policy performance simplification pass.
- Task 7.1: Offline read + queue replay hardening.
- Task 8.1: Localization/accessibility cleanup + flag retirement.

## 12) Risk register

- Risk: startup regressions from launch refactor.
  - Mitigation: feature flag + launch snapshots + staged rollout.
- Risk: messaging behavior drift from queue unification.
  - Mitigation: keep subtle UI, add internal queued-state model, side-by-side verification.
- Risk: RLS breakage while optimizing policy cost.
  - Mitigation: explicit access matrix validation before rollout.
- Risk: realtime subscription churn with channel cap.
  - Mitigation: subscription budget policy + coalesced updates + monitoring.

## 13) Definition of done

- All SLO gates met at rollout cohort target.
- Critical request flow passes on full device matrix.
- Messaging latency/smoothness targets met.
- Security posture unchanged or stronger.
- Feature flags removable without dead code in production path.

## 14) Execution status (2026-02-07)

Implemented now (build-verified):

- Startup deferral changes:
  - `NaarsCars/App/NaarsCarsApp.swift`
  - `NaarsCars/App/AppLaunchManager.swift`
  - `NaarsCars/App/AppState.swift`
  - `NaarsCars/App/MainTabView.swift`
  - `NaarsCars/Core/Services/AuthService.swift`
  - Sync engines are set up during app init but started after critical launch state via deferred loading.
  - Removed duplicate startup `checkAuthStatus()` call from `NaarsCarsApp` and now keep `AppState` synchronized to `AuthService` publishers to avoid redundant launch auth fetches.
  - Added a profile-change-driven guideline-check safety hook in `MainTabView` so launch optimization does not skip guidelines flow.
- Messaging realtime + presence optimizations:
  - `NaarsCars/Features/Messaging/ViewModels/TypingIndicatorManager.swift`
  - `NaarsCars/Core/Services/MessageService.swift`
  - `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`
  - `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
  - Typing indicator polling replaced with realtime channel observation.
  - Typing-user fetch now uses RPC-first path (`get_typing_users`) with table-query fallback.
  - `markAsRead` now supports optional immediate `last_seen` update so callers can throttle presence writes while keeping read state immediate.
  - Conversation detail now uses throttled last-seen heartbeat updates.
- Requests + notifications realtime coalescing:
  - `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
  - `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift`
  - `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift`
  - `NaarsCars/Features/Notifications/Views/NotificationsListView.swift`
  - Realtime burst updates are now coalesced (short debounce) before triggering full refreshes.
  - Requests dashboard ride/favor realtime handling now performs per-item sync (`fetchRide` / `fetchFavor`) and local delete patching instead of always forcing a full rides+favors reload.
  - Full dashboard reload remains as fallback only for malformed payloads or targeted-sync failures.
  - Request list filtering now precomputes a published `filteredRequests` list to avoid repeat conversion work during SwiftUI re-renders.
  - Mark-read flows in notifications now avoid forced server reload when local SwiftData context is present.
- Messaging freeze/jank mitigation:
  - `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`
  - `NaarsCars/UI/Components/Messaging/MessageBubble.swift`
  - `NaarsCars/UI/Components/Messaging/MessageAudioPlayer.swift`
  - Audio file read for send path moved off main actor via detached task.
  - Audio playback observation scoped to an isolated audio content subview so non-audio message bubbles are not invalidated on each playback tick.
  - Playback timer interval and update threshold tuned to reduce redraw churn.
- Messaging fetch/sync and diagnostics hardening:
  - `NaarsCars/Core/Services/MessageService.swift`
  - `NaarsCars/Core/Storage/MessagingRepository.swift`
  - `NaarsCars/Core/Services/BadgeCountManager.swift`
  - `NaarsCars/Features/Messaging/ViewModels/ConversationSearchManager.swift`
  - `NaarsCars/Features/Messaging/Views/ConversationSearchBar.swift`
  - `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
  - `NaarsCars/UI/Components/Messaging/MessageInputBar.swift`
  - Message membership checks now use local SwiftData conversation membership first (with secure server fallback).
  - Repository sync now uses incremental fetch (`created_at > latest`) with periodic short backfill to catch edits/deletes.
  - In-conversation search now supports loading older matches on demand.
  - Added debug-only counters for frame-drop events and input-focus stall occurrences.
  - Badge refresh debounce tightened to 2 seconds target window.
- Additional jank-reduction hardening:
  - `NaarsCars/Core/Storage/MessagingRepository.swift`
  - `NaarsCars/Core/Storage/MessagingSyncEngine.swift`
  - `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`
  - Removed global `NSManagedObjectContextDidSave`-driven messaging publishers in favor of repository-scoped publishers.
  - Save paths now pass conversation-specific invalidation hints to reduce unnecessary message-stream updates.
  - Conversation-list participant hydration switched to batched profile fetches.
- Conversation details loading optimization:
  - `NaarsCars/Core/Services/ConversationService.swift`
  - `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
  - Replaced broad `fetchConversations(limit: 100)` for per-thread title/details with a single-conversation details fetch.
- Realtime fallback tuning:
  - `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift`
  - `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
  - Added payload-aware filtering and delayed fallback refresh windows for malformed realtime payloads.
- Audio cache budget controls:
  - `NaarsCars/UI/Components/Messaging/MessageAudioPlayer.swift`
  - Added bounded on-disk playback cache with LRU trimming.
- Database performance migration added:
  - `database/101_message_search_and_badge_hot_indexes.sql`
  - Adds `pg_trgm` + targeted message/notification indexes for substring search and badge hot paths.
- Constants added for controlled throttling/typing timing:
  - `NaarsCars/Core/Utilities/Constants.swift`

Build verification:

- `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build -quiet`
- Result: success (existing warnings remain; no new build failures).

## 15) Detailed sequential rollout + certification checklist

### Phase gate order (strict)

1. Phase 0 metrics gates pass in staging.
2. Phase 1 startup gates pass on iPhone 12 + iPhone 17 Pro + iPhone 17 Pro Max simulator.
3. Phase 2 main-thread gates pass before enabling phase 3 in production.
4. Phase 3 messaging gates pass with multi-device conversation tests.
5. Phase 4 requests/notifications decoupling gates pass with deep-link and breadcrumb tests.
6. Phase 5/6 database + RLS gates pass with access matrix validation.
7. Phase 7 offline gates pass.
8. Phase 8 cleanup gates pass; debug-only controls removed/hidden in release.

### Rollout cohorts (each gate requires 24-48h stable metrics)

1. Internal only (debug + staging backend)
2. 5% external cohort
3. 25% external cohort
4. 50% external cohort
5. 100% rollout

Rollback rule:

- If any cohort breaches startup p95, send->server p95, crash-free, freeze rate, or claim-flow correctness: disable the phase flag and stop advancement.

### Manual certification matrix (minimum per gate)

- Devices:
  - Physical: iPhone 12, iPhone 17 Pro
  - Large-screen validation: iPhone 17 Pro Max simulator (or physical if available)
- Network profiles:
  - Good Wi-Fi
  - Typical LTE/5G
  - Offline and reconnect
- iOS versions:
  - Oldest supported 17.x
  - Latest current major version

### Detailed manual checklist

Critical request flow (must pass 100% before progressing):

1. Create ride/favor as poster.
2. Claim from second account/device.
3. Confirm poster receives in-app + push notification.
4. Complete from poster account.
5. Review prompt appears and submit/skip paths both work.
6. Verify request state consistency after app relaunch on both devices.
7. Verify unclaim and reclaim work, with notification parity.
8. Verify claim failure path shows immediate blocking error and no stale local success state.

Notifications:

1. Receive notifications foreground/background/terminated.
2. Tap notification deep-links to exact destination (ride/favor/conversation/announcement).
3. Ensure badge count in app, bell, and OS icon converge exactly.
4. Mark single and group notifications read; confirm server and local state match.
5. Verify review and completion reminders are not incorrectly auto-cleared.

Messaging (iMessage-like expectations):

1. Open conversation cold and warm; confirm no visible jump/freeze entering text field.
2. Send text/image/audio/location; verify subtle optimistic bubble appears immediately.
3. Confirm server acceptance ordering after reconnect for queued messages.
4. Edit and unsend sent messages; verify all devices converge.
5. Typing indicator appears/disappears in realtime without polling lag.
6. Read receipts appear immediately and remain correct after reload.
7. Search in conversation returns exact substring matches.
8. Verify offline read behavior for cached messages.

Startup/smoothness:

1. Cold launch 10 times on iPhone 12; record p50/p95 first-interaction time.
2. Warm resume 10 times; measure time to interactive.
3. Open/close conversation repeatedly while receiving incoming messages; confirm no session freeze.
4. Scroll long requests and notifications lists while realtime updates arrive; confirm no stutter spikes.

Data integrity/security:

1. Confirm unauthorized users cannot access non-participant conversations.
2. Confirm claim/complete actions fail correctly under invalid actor conditions.
3. Verify RLS-sensitive flows still function for approved and pending users.
4. Confirm no privilege regressions for admin-only paths.
