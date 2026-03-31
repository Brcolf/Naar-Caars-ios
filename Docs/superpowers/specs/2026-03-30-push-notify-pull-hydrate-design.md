# Push-Notify, Pull-Hydrate: Realtime Architecture Refactor

## Problem

The app maintains 7-8 always-on WebSocket subscriptions per active user (messages, rides, favors, notifications, town hall posts/comments/votes, plus per-conversation reactions). At 17 users, this generates 7.75M WAL polling calls consuming 87.5% of total database time. The architecture won't scale — adding 20 more users will approach the 60-connection Postgres ceiling, and notification queue processing is already showing 7.2s contention spikes.

Most production social apps use push notifications as the realtime signal and fetch fresh data on demand, reserving WebSockets only for active chat. This refactor adopts that model.

## Design Decisions (from brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Conversation list freshness | Push-triggered refresh, no WebSocket | Maximum connection savings; 1-2s delay is acceptable |
| Active conversation | WebSocket for messages + reactions | Chat requires true realtime |
| WebSocket teardown scope | Messaging tab — keep alive on tab, tear down on tab switch | Keeps messaging snappy while browsing conversations |
| Dashboard/Town Hall freshness | Pull-on-appear with 30s staleness window | Prevents rapid tab-switch spam while keeping data current |
| Town Hall live votes | Pull-to-refresh gesture, no live updates | Simple, consistent with dashboard pattern |
| Badge count polling | 5-minute safety net poll (down from 30s) | Catches missed pushes without hammering RPC |
| Push-triggered refresh mechanism | Visible push triggers data refresh based on type | No dual push, no new edge functions, ~20 lines of new code |
| Rollout strategy | Big bang — all layers change together | No intermediate half-realtime state to maintain |

---

## Section 1: Realtime Subscription Model

### Current State

Every active user holds 7-8 WebSocket subscriptions:
- `messages:sync` — global messages table
- `rides:sync` — global rides table
- `favors:sync` — global favors table
- `notifications:sync` — user-filtered notifications
- `town-hall-posts` — global town hall posts
- `town-hall-comments` — global town hall comments
- `town-hall-votes` — global town hall votes
- `reactions:{conversationId}` — per-conversation (lazy, on conversation open)

### New State

| User location | WebSocket subscriptions | Data freshness source |
|---|---|---|
| App closed/backgrounded | 0 | APNs push |
| Dashboard tab | 0 | Pull-on-appear (30s staleness), push-triggered refresh |
| Town Hall tab | 0 | Pull-on-appear (30s staleness), pull-to-refresh |
| Messaging tab, conversation list | 0 | Push-triggered refresh |
| Messaging tab, inside conversation | 3 (messages + reactions + typing for that conversation) | Live WebSocket |
| Any tab, app foregrounded | 0 | Badge refresh on foreground + 5-min safety poll |

### RealtimeManager Changes

- Remove `startSync()`-triggered always-on subscriptions for rides, favors, notifications, town hall
- Keep the `subscribe()`/`unsubscribe()` API — still used for conversation-scoped subscriptions
- Remove 3-tier staggered reconnection logic (no longer reconnecting 7+ channels on foreground)
- Keep background auto-unsubscribe behavior (tear down conversation WebSocket after 30s in background)
- Simplify protected-channel and 30-channel limit logic (max concurrent drops to ~3: messages, reactions, typing for one conversation)

---

## Section 2: Sync Engine Changes

### DashboardSyncEngine — Realtime-Driven to Pull-Driven

- Remove all three realtime subscriptions (rides, favors, notifications) from `startSync()`
- Add `refreshIfStale()` — checks `lastFetchedAt` timestamp via `StalenessTracker`. If >30s stale, fetch fresh data via REST and sync to SwiftData via `BackgroundSyncActor`. If within window, no-op.
- Add `forceRefresh()` — no staleness check, for push-triggered refresh and pull-to-refresh
- Called on: tab appear, push-triggered refresh, app foreground
- Keep existing `syncAll()` parallel fetch logic (rides + favors + notifications) as implementation
- Remove realtime payload parsing, incremental upsert from realtime, and debounced full-sync fallback
- Keep `BackgroundSyncActor` batch writes
- Keep `.ridesDidSync`, `.favorsDidSync`, `.notificationsDidSync` notifications

### TownHallSyncEngine — Same Pattern

- Remove all three realtime subscriptions (posts, comments, votes)
- Add `refreshIfStale()` with 30s window, `forceRefresh()` for pull-to-refresh
- Remove realtime payload handling, incremental upsert, 600ms debounced refresh logic
- Resolves known audit deviation — MainActor writes replaced by proper `BackgroundSyncActor` writes via pull-based refresh path
- Keep `.townHallPostsDidSync` etc. notifications

### MessagingSyncEngine — Scoped to Active Conversation

- Remove global `messages:sync` subscription from `startSync()`
- Add `subscribeToConversation(conversationId:)` — opens WebSocket for messages and reactions for that conversation
- Add `unsubscribeFromConversation()` — tears down WebSocket, called when user leaves messaging tab
- Add `switchConversation(conversationId:)` — atomic unsubscribe old + subscribe new
- Track `activeConversationId` internally — same-ID subscribe is a no-op
- On subscribe, immediately REST fetch recent messages BEFORE WebSocket is live (covers the connection window gap)
- Message handling logic unchanged (dedup, ordering, incremental upsert, media pre-caching, conversation unhiding)
- Reaction handling unchanged (already per-conversation)
- `MessageSendWorker` orchestration unchanged
- Add `refreshConversationList()` for push-triggered refresh of conversation list
- `refreshConversationList()` operates on conversation-level metadata (last message preview, unread counts) and does NOT interfere with the active conversation's WebSocket message stream — they write to different SwiftData entities

### TypingIndicatorManager — Lifecycle Alignment

`TypingIndicatorManager` independently subscribes to a `typing:{conversationId}` channel via `RealtimeManager`. It is NOT managed by `MessagingSyncEngine` — it has its own lifecycle owned by the conversation detail ViewModel. This refactor does not change its behavior, but:
- Its subscription must be torn down when the user leaves the messaging tab (alongside the messages/reactions teardown)
- The conversation detail ViewModel's `onDisappear` / tab-switch handler must call both `MessagingSyncEngine.unsubscribeFromConversation()` AND `TypingIndicatorManager.stopObserving()`
- On sign-out teardown, `TypingIndicatorManager` must also be stopped (it may already be — verify during implementation)

### New Shared Utility — StalenessTracker

Small utility used by DashboardSyncEngine and TownHallSyncEngine:
- Tracks `lastFetchedAt` per data type
- `isStale(key:window:) -> Bool`
- `markFresh(key:)`
- `reset()` — clears all timestamps (for teardown)
- Thread-safe (used from MainActor context)

---

## Section 3: Badge Count Manager Changes

### Current State

Polls `get_badge_counts` RPC every 30s (connected) / 90s (disconnected). Refreshes on `didBecomeActive`. ~43K calls in observation period.

### New State

- Remove 30s/90s polling timers
- Remove `RealtimeManager.$isConnected` listener
- Add 5-minute safety net poll timer (while app is foregrounded)

### Badge Refresh Triggers

| Trigger | Method | Notes |
|---|---|---|
| App foregrounds | `refreshBadgeCounts()` | Existing, keep as-is |
| Push notification received (any type) | `refreshBadgeCounts()` | New — from PushNotificationService |
| User action (send message, claim ride, mark read) | `refreshBadgeCounts()` | Existing via clear methods |
| 5-minute safety poll | `refreshBadgeCounts()` | New — replaces 30s/90s timers |

- Tighten debounce guard from 30s to 5s (prevents push bursts, but responsive enough)
- Keep failure handling (exponential backoff, stale fallback with `isBadgeStale`)
- Keep `clearMessagesBadge(conversationId:)` optimistic local clear
- Keep app icon badge update

**Expected impact:** ~43K calls → ~5-8K calls (~80% reduction).

---

## Section 4: Push-Triggered Data Refresh

### Current State

`PushNotificationService` handles push taps and notification actions. It does not trigger data refreshes on push receipt.

### New Behavior

Add `handlePushReceived(userInfo:)` method that maps notification type to data domain and triggers appropriate sync engine refresh.

### Notification Type → Refresh Mapping

| Push type contains | Refresh action |
|---|---|
| `ride`, `favor`, `request`, `claim`, `completion` | `DashboardSyncEngine.forceRefresh()` |
| `message`, `conversation` | `MessagingSyncEngine.refreshConversationList()` |
| `town_hall`, `announcement` | `TownHallSyncEngine.forceRefresh()` |
| `approval`, `admin`, `account` | `DashboardSyncEngine.forceRefresh()` |
| Any push | `BadgeCountManager.refreshBadgeCounts()` |

### Explicit Notification Type Mapping

Do NOT use substring matching. Use an explicit switch on `NotificationType` raw values:

| NotificationType | Refresh Action |
|---|---|
| `message`, `addedToConversation` | `MessagingSyncEngine.refreshConversationList()` |
| `newRide`, `rideUpdate`, `rideClaimed`, `rideUnclaimed`, `rideCompleted` | `DashboardSyncEngine.forceRefresh()` |
| `newFavor`, `favorUpdate`, `favorClaimed`, `favorUnclaimed`, `favorCompleted` | `DashboardSyncEngine.forceRefresh()` |
| `completionReminder` | `DashboardSyncEngine.forceRefresh()` |
| `qaActivity`, `qaQuestion`, `qaAnswer` | `DashboardSyncEngine.forceRefresh()` |
| `review`, `reviewReceived`, `reviewReminder`, `reviewRequest` | `DashboardSyncEngine.forceRefresh()` |
| `townHallPost`, `townHallComment`, `townHallReaction` | `TownHallSyncEngine.forceRefresh()` |
| `contentReported` | `DashboardSyncEngine.forceRefresh()` |
| `announcement`, `adminAnnouncement`, `broadcast` | `TownHallSyncEngine.forceRefresh()` |
| `pendingApproval`, `userApproved`, `userRejected` | `DashboardSyncEngine.forceRefresh()` |
| `accountRestricted` | `DashboardSyncEngine.forceRefresh()` |
| `other` | No domain-specific refresh |
| **All types** | `BadgeCountManager.refreshBadgeCounts()` (always) |

This mapping must be maintained as a single switch statement. Adding a new `NotificationType` without a refresh mapping must produce a compiler warning (non-exhaustive switch).

### Hook Points

- **App in foreground:** `userNotificationCenter(_:willPresent:)` — call `handlePushReceived(userInfo:)`, then apply existing smart suppression for banner display
- **App in background:** `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` — **this method does not currently exist in AppDelegate and must be implemented** (see Background Push Handler section below)
- **Push tap:** Existing `handleNotificationTap(userInfo:)` unchanged. Also call `handlePushReceived(userInfo:)` to ensure fresh data before navigation.

### Background Push Handler (New — AppDelegate)

`AppDelegate` does not currently implement `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`. This must be added.

**Implementation requirements:**
- iOS gives the app ~30 seconds of execution time when woken by a `content-available` push
- The handler MUST call `fetchCompletionHandler` with `.newData`, `.noData`, or `.failed` before the 30s deadline — failure to call it causes iOS to deprioritize future background wakes
- Call `PushNotificationService.handlePushReceived(userInfo:)` which triggers the appropriate sync engine refresh
- Await the refresh completion, then call `fetchCompletionHandler(.newData)` on success or `fetchCompletionHandler(.failed)` on error
- If no relevant data domain is identified, call `fetchCompletionHandler(.noData)`

**Info.plist:** Already has `UIBackgroundModes` with `remote-notification` and `fetch` — no change needed.

**Caveat:** `content-available` combined with visible alerts is best-effort. iOS may throttle or skip background wakes when: battery is low, app was force-quit by user, Low Power Mode is active, or system is under memory pressure. The 5-minute safety poll is the correctness backstop, not just an edge-case fallback.

### In-App Toast Notifications

`InAppToastManager` observes `.conversationUpdated` notifications posted by `MessagingSyncEngine.handleIncomingMessage()`. Under the new architecture, when the user is NOT on the messaging tab, there is no active messages WebSocket, so `.conversationUpdated` is never posted from the realtime path.

**Solution:** When a message-type push is received in the foreground via `willPresent`, and the user is NOT on the messaging tab:
- iOS will show the system notification banner (existing `willPresent` handler already allows this for non-active-conversation contexts)
- This replaces the custom in-app toast for non-messaging-tab contexts
- When the user IS on the messaging tab with an active conversation WebSocket, the existing flow continues: realtime event → `.conversationUpdated` → `InAppToastManager` shows custom toast (if the message is for a different conversation)
- Net effect: users see the same notification banners, just via the system banner path instead of the custom toast path when outside messaging

### Edge Function Changes

Add `"content-available": 1` to the `aps` payload in both `send-message-push/index.ts` and `send-notification/index.ts`. The `send-message-push` TypeScript `APNsPayload` interface must also be updated to include `"content-available"` as an optional field (it already exists in `send-notification`'s interface). No logic changes beyond payload construction.

### Guest Mode

Guest users (anonymous, no account) can browse rides, favors, and town hall. They have no `userId`, no push token, and no server-side notification targeting.

**Implications for this refactor:**
- Guest users receive NO push notifications — the push-triggered refresh path is completely unavailable
- `refreshIfStale()` and `forceRefresh()` must work without a `userId` for public data (rides, favors, town hall). These REST endpoints already support anonymous reads via RLS anon policies.
- `BadgeCountManager` must NOT be started for guest users — there are no badges to track
- `MessagingSyncEngine` must NOT be started for guest users — messaging requires auth
- The staleness window (30s) and pull-on-appear are the sole freshness mechanisms for guests
- The 5-minute safety poll should not run for guests (no badge counts to refresh)
- No changes to guest mode gating logic — auth-required actions remain gated in UI and RLS

---

## Section 4b: SyncEngineProtocol Lifecycle Update

### Current Protocol Contract

`SyncEngineProtocol` defines: `setup → startSync → pauseSync → resumeSync → teardown`

### Updated Contract

`refreshIfStale()` and `forceRefresh()` are new public methods on `DashboardSyncEngine` and `TownHallSyncEngine`. The lifecycle contract becomes:

```
setup(modelContext:)          — store MainActor context
setupBackgroundActor(container:) — init BackgroundSyncActor
startSync()                   — perform initial data fetch (calls refreshIfStale internally)
                                 For MessagingSyncEngine: start send worker, NO global subscription
refreshIfStale()              — callable any time after startSync(), checks staleness window
forceRefresh()                — callable any time after startSync(), bypasses staleness
pauseSync()                   — cancel in-flight fetches (app backgrounding)
resumeSync()                  — restart safety mechanisms (app foregrounding)
teardown()                    — full cleanup: cancel tasks, reset staleness, invalidate timers
```

**Key changes:**
- `startSync()` no longer subscribes to realtime for dashboard/town hall — it performs an initial REST fetch
- `refreshIfStale()` and `forceRefresh()` can only be called after `startSync()` (calling before is a no-op with a logged warning)
- `pauseSync()` / `resumeSync()` no longer manage realtime subscriptions for dashboard/town hall — they manage in-flight fetch task cancellation and safety poll timers
- For `MessagingSyncEngine`, `startSync()` starts the send worker but does NOT subscribe to any channel. Conversation subscriptions are managed separately via `subscribeToConversation()`.

**Whether to update `SyncEngineProtocol`:** Add `refreshIfStale()` and `forceRefresh()` as protocol requirements with default no-op implementations (via extension). This keeps the protocol contract explicit while not forcing `MessagingSyncEngine` (which doesn't use staleness for its WebSocket-driven conversation) to implement them.

---

## Section 5: Conversation WebSocket Lifecycle

### State Machine

```
User enters messaging tab
  → no WebSocket (conversation list shows cached/pulled data)

User opens conversation
  → subscribeToConversation(conversationId:) — messages + reactions channels
  → TypingIndicatorManager.startObserving(conversationId:) — typing channel
  → REST fetch recent messages (immediate, covers connection gap)
  → 3 WebSocket channels connect (messages, reactions, typing)

User taps back to conversation list
  → WebSocket stays alive (same messaging tab)

User opens different conversation
  → switchConversation(newId) — unsubscribe old, subscribe new atomically

User leaves messaging tab (switches to rides, town hall, etc.)
  → unsubscribeFromConversation() — messages + reactions torn down
  → TypingIndicatorManager.stopObserving() — typing channel torn down

App backgrounds
  → 30s grace period (existing behavior) → tear down

App foregrounds on messaging tab with prior conversation
  → resubscribe to conversation
```

### Lifecycle Ownership

- Conversation detail ViewModel calls `subscribeToConversation(conversationId:)` on appear
- Conversation detail ViewModel calls `switchConversation(conversationId:)` for different conversation
- Messaging tab parent view / tab-change observer calls `unsubscribeFromConversation()` on tab switch
- `MessagingSyncEngine` tracks `activeConversationId` — same-ID subscribe is no-op

### Unchanged

- Message handling inside subscription (dedup, ordering, incremental upsert, media pre-caching)
- Reaction handling (already per-conversation)
- Optimistic send flow (MessageSendManager → MessageSendWorker → MessageService)
- Read receipt logic
- Typing indicators (lifecycle aligned to conversation view + tab, but internal behavior unchanged)

### Quick Reply from Push (Edge Case)

When a user sends a message via quick-reply from a notification action (`PushNotificationService.handleMessageReply`), this calls `MessageService.shared.sendMessage()` directly, bypassing `MessageSendManager`. With no global messages WebSocket, the sent message will not appear in local conversation state until the user navigates to the messaging tab. This is acceptable — the quick-reply UX dismisses the notification banner, and when the user later opens the conversation, the message will be visible via REST fetch. Additionally, `handlePushReceived()` should be called after a quick-reply send to refresh the conversation list.

### Conversation List Freshness

- Push-triggered refresh via `refreshConversationList()`
- 30s staleness window when returning to list from conversation
- Pull-to-refresh gesture

---

## Section 6: Teardown and Sign-Out

### Updated Sign-Out Sequence

```
1. MessagingSyncEngine.teardown()
   → unsubscribeFromConversation() (if any active)
   → TypingIndicatorManager.stopObserving() (if active)
   → stop MessageSendWorker
   → clear activeConversationId

2. DashboardSyncEngine.teardown()
   → cancel in-flight REST fetch tasks
   → reset StalenessTracker timestamps

3. TownHallSyncEngine.teardown()
   → cancel in-flight REST fetch tasks
   → reset StalenessTracker timestamps

4. BadgeCountManager.teardown()
   → invalidate 5-minute safety poll timer
   → cancel in-flight RPC task
   → zero out all badge counts
   → reset app icon badge to 0

5. RealtimeManager.teardown()
   → unsubscribe any remaining channels
   → disconnect from Supabase Realtime

6. PushNotificationService.removeDeviceToken()
   → existing behavior unchanged

7. SwiftData cache clear
   → existing behavior unchanged
```

### App Foreground/Background Cycle

- **Background:** 30s grace period on active conversation WebSocket, then tear down. Cancel safety poll timer.
- **Foreground:** Refresh badge counts. If user was in a conversation, resubscribe. If on dashboard/town hall, `refreshIfStale()`. Restart safety poll timer.

---

## Section 7: Code Cleanup

### Stale Code to Remove

| File | Removals |
|---|---|
| `RealtimeManager` | 3-tier staggered reconnection logic. Protected channel priority system. Simplify channel tracking (max ~2 concurrent). |
| `DashboardSyncEngine` | All realtime payload parsing/handling. `DashboardPayloadMapper` usage for realtime events (keep if used for REST). Debounced full-sync fallback. All `RealtimeManager.subscribe()` calls. |
| `TownHallSyncEngine` | All realtime payload parsing/handling. 600ms debounced refresh. All `RealtimeManager.subscribe()` calls. MainActor write deviation paths. |
| `MessagingSyncEngine` | Global `messages:sync` subscription. Replace with conversation-scoped management. |
| `BadgeCountManager` | 30s/90s polling timers. `RealtimeManager.$isConnected` listener. Connected/disconnected interval switching. |
| `RealtimePayloadAdapter` | Simplify to handle only message/reaction payload shapes (evaluate if unstructured fallback paths are still needed). |

### Dead Code Audit

Check if these become unused:
- `DashboardPayloadMapper` — remove if only used for realtime event parsing. If removed, also remove corresponding tests in `NaarsCarsTests/Core/Decoding/RealtimePayloadDecodingTests.swift`
- `NotificationPayloadMapper` — same check and test cleanup
- `TownHallPayloadMapper` (private enum inside `TownHallSyncEngine.swift`) — will become dead code when realtime subscriptions are removed, delete it
- `NSNotification.Name` constants only posted from realtime handlers — verify `.ridesDidSync`, `.favorsDidSync`, `.notificationsDidSync`, `.conversationUpdated` are still posted from the REST/pull paths. The sync notifications must continue to be posted from `syncAll()` / `forceRefresh()` so that `RequestRealtimeHandler` and `NotificationRealtimeHandler` continue to receive them.
- Staggered reconnection constants/tier definitions in `RealtimeManager`

### Downstream Handler Compatibility

`RequestRealtimeHandler` and `NotificationRealtimeHandler` observe `.ridesDidSync`, `.favorsDidSync`, and `.notificationsDidSync` with debounced scheduling. Under the new model, `forceRefresh()` → `syncAll()` may post all three notifications in rapid succession (previously they arrived one at a time from individual realtime events). This is safe — both handlers use coalescing debounce, so rapid-fire notifications will be batched into a single reload. Verify this during implementation but no code changes expected.

### Existing Background App Refresh

`AppDelegate.handleAppRefresh(task:)` already calls `DashboardSyncEngine.shared.syncAll()` on the OS-scheduled background refresh (earliest begin date: 15 minutes). This is complementary to the 5-minute safety poll and push-triggered refresh. No changes needed — it continues to work as an additional freshness mechanism for dashboard data.

### Documentation Updates

**CLAUDE.md:**
- Current State of the Codebase — reflect push-notify/pull-hydrate architecture, realtime scoped to active conversation only
- Fragile Systems §1 (Realtime Pipeline) — update data flow diagram, realtime path only for active conversation
- Fragile Systems §5 (Auth/Launch) — simplified sign-out teardown
- Fragile Systems §6 (Sync Engine Lifecycle) — add `refreshIfStale()` / `forceRefresh()` patterns
- Fragile Systems §7 (Badge Count) — push-triggered + 5-min safety poll
- Realtime Rules — realtime is conversation-scoped only
- Cross-Layer Synchronization Rules — add push-received handler as high-blast-radius seam
- Audit Notes — remove TownHallSyncEngine MainActor deviation (resolved), update high-risk files
- Quick Reference — update realtime pipeline invariant, add push-triggered refresh invariant

**AGENTS.md:**
- Mirror key architectural changes (realtime scoping, push-triggered refresh)

**Cursor Rules (`.cursor/rules/`):**
- Rule `03` (centralized realtime payload parsing) — scope narrower, only messages/reactions
- Rule `01` (impact seam analysis) — add push-received handler as seam
- Master project rule — reflect new architecture

---

## Section 8: Risk Mitigation and Testing

### Highest-Risk Areas

**Risk 1: Message loss during WebSocket lifecycle transitions**
Scenario: User opens conversation, WebSocket connecting, message arrives during ~0.5s window.
Mitigation: REST fetch recent messages immediately on `subscribeToConversation()` before WebSocket is live. Existing dedup logic prevents doubles.

**Risk 2: Push delivery failure leaves stale data**
Scenario: APNs drops a push, data stale until foreground or 5-min poll.
Mitigation: 5-minute safety poll. `refreshIfStale()` on every tab switch caps staleness at 30s for any visited screen.

**Risk 3: Badge count divergence**
Scenario: Push triggers badge refresh but RPC fails.
Mitigation: Existing `isBadgeStale` flag and exponential backoff retry preserved.

**Risk 4: Conversation list stale unread counts**
Scenario: On dashboard, receive 3 messages. Conversation list not refreshed until tab switch.
Mitigation: Tab badge updates immediately (push-triggered). List refreshes on appear with `refreshIfStale()`.

**Risk 5: Sign-out teardown misses new patterns**
Scenario: Staleness timestamps or safety poll survive sign-out.
Mitigation: Explicit teardown for each component per Section 6.

**Risk 6: Push tap navigates before data is local**
Scenario: User taps a "new ride" push within 500ms. `DashboardSyncEngine.forceRefresh()` fires but hasn't completed. Navigation lands on ride detail with no local data.
Mitigation: Ride/favor/post detail views already handle the "not in cache" case by fetching from the network (they show a loading state, then fetch by ID). The push-triggered refresh ensures the list is fresh, but individual detail views are self-sufficient. No new code needed — verify existing detail view behavior during testing.

**Risk 7: Guest mode data freshness**
Scenario: Guest user browses rides without any push mechanism. Data could become stale during a long session.
Mitigation: Pull-on-appear with 30s staleness window on every tab switch. Pull-to-refresh available on all list views. No push-triggered refresh is available, but the staleness window ensures data is refreshed frequently during active use.

### Manual Testing Matrix

| Scenario | Verify |
|---|---|
| Open conversation, receive message | Message appears live via WebSocket |
| On conversation list, receive message | Badge updates, list refreshes on appear |
| On dashboard, new ride posted | Push arrives, dashboard refreshes, tab badge updates |
| On town hall, pull to refresh | Fresh data loads |
| Switch tabs rapidly | No duplicate fetches within 30s window, no crashes |
| Background app 31+ seconds, return | Conversation WebSocket reconnects, badges refresh |
| Background app, receive push, open via tap | Navigates to correct destination with fresh data |
| Sign out and sign in as different user | No stale data from previous session |
| Kill app, reopen | Fresh fetch on launch, no stale subscriptions |
| Airplane mode on, then off | Safety poll resumes, badge refresh triggers |
| Send message while WebSocket reconnecting | Optimistic send works, appears locally, reconciles on reconnect |
| Quick-reply from notification banner | Message sends, conversation list refreshes |
| Guest mode, browse rides tab | Pull-on-appear works, pull-to-refresh works, no crashes from missing push/badge |
| Guest mode, switch tabs rapidly | No auth-related errors from staleness checks |
| Two devices same account, message on device A | Device B receives push, refreshes conversation list |
| Force-quit app, receive push, tap notification | App launches, navigates to correct destination, data loads |
| In-app toast: on dashboard, receive message push | System banner shows (not custom toast) |
| In-app toast: in conversation A, message arrives for conversation B | Custom toast shows via existing `.conversationUpdated` path |

### Automated Tests

| Test | Coverage |
|---|---|
| `StalenessTracker` unit tests | Window logic, reset, thread safety |
| Push-received → refresh mapping | Each notification type triggers correct sync engine |
| `DashboardSyncEngine` pull-based refresh | Staleness check, force refresh, concurrent call dedup |
| `TownHallSyncEngine` pull-based refresh | Same pattern |
| `MessagingSyncEngine` conversation scoping | Subscribe/unsubscribe/switch lifecycle, no-op on same ID |
| `BadgeCountManager` timer behavior | 5-min interval, foreground trigger, push trigger, debounce |
| Teardown completeness | All timers cancelled, all state reset on sign-out |

---

## Files Affected (Estimated)

### Client — Modified
| File | Change Type |
|---|---|
| `Core/Services/RealtimeManager.swift` | Major — remove always-on subscriptions, simplify |
| `Core/Storage/DashboardSyncEngine.swift` | Major — replace realtime with pull-based |
| `Core/Storage/TownHallSyncEngine.swift` | Major — replace realtime with pull-based |
| `Core/Storage/MessagingSyncEngine.swift` | Major — scope to active conversation |
| `Core/Storage/SyncEngineProtocol.swift` | Minor — add `refreshIfStale()` / `forceRefresh()` with default no-op |
| `Core/Services/BadgeCountManager.swift` | Medium — replace polling with push-triggered + safety poll |
| `Core/Services/PushNotificationService.swift` | Medium — add push-received refresh handler |
| `Core/Services/InAppToastManager.swift` | Minor — verify behavior; toasts outside messaging tab now handled by system banner |
| `Core/Storage/MessagingRepository.swift` | Minor — `refreshConversationList()` interacts with this repository |
| `App/AppDelegate.swift` | Medium — implement `didReceiveRemoteNotification:fetchCompletionHandler:` |
| `App/NavigationCoordinator.swift` | Minor — no structural changes expected |
| `Features/Messaging/ViewModels/TypingIndicatorManager.swift` | Minor — verify teardown alignment with tab-switch lifecycle |
| `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | Minor — verify NSNotification contract compatibility |
| `Features/Notifications/ViewModels/NotificationRealtimeHandler.swift` | Minor — verify NSNotification contract compatibility |
| Feature ViewModels (dashboard, town hall, messaging list) | Minor — call `refreshIfStale()` on appear |

### Client — New
| File | Purpose |
|---|---|
| `Core/Utilities/StalenessTracker.swift` | Shared staleness window utility |

### Client — Potentially Removed
| File | Condition |
|---|---|
| `DashboardPayloadMapper` | If only used for realtime parsing (also remove associated tests) |
| `NotificationPayloadMapper` | If only used for realtime parsing (also remove associated tests) |
| `TownHallPayloadMapper` (private in TownHallSyncEngine) | Dead code after realtime removal |
| `RealtimePayloadDecodingTests` (partial) | Tests for removed mappers |

### Backend — Modified
| File | Change |
|---|---|
| `supabase/functions/send-message-push/index.ts` | Add `content-available: 1` to aps payload + update TypeScript interface |
| `supabase/functions/send-notification/index.ts` | Add `content-available: 1` to aps payload |

### Documentation — Modified
| File | Change |
|---|---|
| `CLAUDE.md` | Multiple sections updated per Section 7 |
| `AGENTS.md` | Mirror architectural changes |
| `.cursor/rules/01`, `03`, master rule | Update for new architecture |
