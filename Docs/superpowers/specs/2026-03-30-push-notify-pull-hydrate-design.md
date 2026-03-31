# Push-Notify, Pull-Hydrate: Realtime Architecture Refactor

## Problem

The app maintains 7-8 always-on WebSocket subscriptions per active user (messages, rides, favors, notifications, town hall posts/comments/votes, plus per-conversation reactions). At 17 users, this generates 7.75M WAL polling calls consuming 87.5% of total database time. The architecture won't scale — adding 20 more users will approach the 60-connection Postgres ceiling, and notification queue processing is already showing 7.2s contention spikes.

Most production social apps use push notifications as the realtime signal and fetch fresh data on demand, reserving WebSockets only for active chat. This refactor adopts that model.

---

## Core Architecture Principles

1. **Push = invalidation signal, Pull = source of truth.** Push notifications tell the app data changed. REST fetches get the actual data.
2. **WebSockets only for active chat.** All other data uses pull-on-appear with push-triggered refresh.
3. **Centralized refresh orchestration.** A single `RefreshCoordinator` owns all refresh decisions, staleness tracking, and in-flight dedup.
4. **SwiftData is the render layer.** UI reads from SwiftData cache. Network refreshes write through SwiftData. Change detection prevents unnecessary writes.
5. **Targeted refresh over full reconciliation.** Push-triggered refreshes fetch single entities when possible. Full reconciliation only on staleness expiry or pull-to-refresh.

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Conversation list freshness | Push-triggered refresh, no WebSocket | Maximum connection savings; 1-2s delay acceptable |
| Active conversation | WebSocket for messages + reactions + typing | Chat requires true realtime |
| WebSocket scope | Conversation-scoped with 5-second grace period | Consistent list behavior; no inconsistent per-conversation live updates on list view |
| Dashboard/Town Hall freshness | Pull-on-appear with 30s staleness window | Prevents rapid tab-switch spam while keeping data current |
| Town Hall live votes | Pull-to-refresh gesture only | Simple, consistent with dashboard pattern |
| Badge count refresh | Push-triggered + 5-minute safety poll | Catches missed pushes without hammering RPC |
| Push-triggered refresh | Visible push triggers data refresh via coordinator | No dual push, no new edge functions |
| Refresh orchestration | Centralized RefreshCoordinator | Single source of truth for invalidation, staleness, in-flight dedup |
| SwiftData write strategy | Compare-before-write with conditional save | Prevents @Query thrash and phantom UI updates |
| Rollout | Big bang — all layers change together | No intermediate half-realtime state |

---

## Section 1: RefreshCoordinator

### Purpose

Single entry point for all data invalidation and refresh decisions. Replaces scattered refresh triggers across PushNotificationService, ViewModels, AppDelegate, and per-engine staleness logic. Engines become pure fetch-and-store; the coordinator decides when, whether, and what to refresh.

### Domains

```swift
enum Domain: String, CaseIterable {
    case dashboard      // rides + favors + notifications
    case townHall       // posts + comments
    case conversations  // conversation list metadata
    case badges         // badge counts (not in SwiftData)
}
```

### Freshness State Machine

```swift
enum FreshnessState {
    /// SwiftData has never been populated for this domain in this user session.
    /// UI shows loading skeleton. First fetch is blocking.
    case unhydrated

    /// SwiftData has usable data synced at `lastSync`.
    /// UI renders from cache. Background refresh if past staleness window.
    case hydrated(lastSync: Date)

    /// Push or action explicitly invalidated this domain. Cache still usable.
    /// Eager background refresh on next access or immediately if visible.
    case invalidated(lastSync: Date)

    /// Fetch in-flight. `hasCache` determines UI behavior.
    case refreshing(task: Task<Void, Never>, hasCache: Bool)

    /// Last fetch failed. Cached data may or may not exist.
    case failed(retryAfter: Date, hasCache: Bool)
}
```

**Transitions:**

```
unhydrated ──(startSync)───────→ refreshing(hasCache: false) ──(success)→ hydrated(now)
                                                              ──(failure)→ failed(hasCache: false)

hydrated ──(staleness expires)──→ [stays hydrated; stale on next access]
hydrated ──(push received)──────→ invalidated(lastSync)
hydrated ──(tab appear, stale)──→ refreshing(hasCache: true) ──(success)→ hydrated(now)

invalidated ──(tab appear)──────→ refreshing(hasCache: true) ──(success)→ hydrated(now)
invalidated ──(already refreshing)→ no-op (join in-flight)

failed(hasCache: true) ──(backoff expires)→ hydrated(lastSync) [re-enters staleness check]
failed(hasCache: false) ──(backoff expires)→ unhydrated [retry from scratch]

refreshing ──(another request)──→ no-op (join existing task; NEVER cancel running fetch)
```

### Hydration Detection

Uses advisory UserDefaults timestamps with SwiftData count fallback:

- `lastSuccessfulSync` per domain stored in UserDefaults at `"refresh.lastSync.\(domain.rawValue)"`
- Timestamp written ONLY after `modelContext.save()` succeeds — never before
- On startup: if timestamp exists → `.hydrated(lastSync: timestamp)`. If nil but SwiftData has records (crash recovery) → `.hydrated(lastSync: .distantPast)`. If nil and empty → `.unhydrated`
- Cleared on sign-out alongside SwiftData wipe
- All inconsistent states self-heal on next access — no manual intervention needed

### Public API

```swift
@MainActor
final class RefreshCoordinator {
    /// Called by MainTabView.onChange(of: selectedTab). Sole staleness trigger.
    func setVisibleDomain(_ domain: Domain?)

    /// Called when push received or user action invalidates a domain.
    func invalidate(_ domains: Set<Domain>)

    /// Called for targeted single-entity refresh (push with entity ID).
    func performTargetedRefresh(_ domain: Domain, entityId: UUID)

    /// Called from background push handler. Budget-constrained.
    func handleBackgroundPush(type: NotificationType, entityId: UUID?,
                              completion: @escaping (UIBackgroundFetchResult) -> Void)

    /// Called on app foreground.
    func handleAppForegrounded()

    /// Active conversation exclusion for background sync.
    private(set) var activeConversationId: UUID?
    func setActiveConversation(_ id: UUID?)

    /// Teardown on sign-out.
    func reset()

    /// Diagnostics.
    func diagnosticSnapshot() -> RefreshDiagnostics
}
```

### Visibility Ownership

`RefreshCoordinator` owns `visibleDomain: Domain?`. Set by ONE call site:

```swift
// MainTabView:
.onChange(of: selectedTab) { _, newTab in
    RefreshCoordinator.shared.setVisibleDomain(newTab.refreshDomain)
}
```

`setVisibleDomain` calls `refreshIfNeeded` for the new domain. ViewModels do NOT call refresh methods. This eliminates double-fire from onAppear + tab change.

### Safety Poll

5-minute repeating timer while app is foregrounded and user is authenticated. Calls `refreshIfNeeded` for all domains. Catches missed pushes.

### Guest Mode

Coordinator initializes but: `BadgeCountManager` not started, `MessagingSyncEngine` not started, safety poll not started, no push-triggered refreshes. Only staleness-based pull-on-appear for public data (rides, favors, town hall).

---

## Section 2: Notification Type → Domain Mapping

Co-located on `NotificationType`, not in a distant handler:

```swift
extension NotificationType {
    var affectedDomains: Set<RefreshCoordinator.Domain> {
        switch self {
        case .message, .addedToConversation:
            return [.conversations]
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
             .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted,
             .completionReminder, .qaActivity, .qaQuestion, .qaAnswer,
             .review, .reviewReceived, .reviewReminder, .reviewRequest,
             .contentReported, .pendingApproval, .userApproved, .userRejected,
             .accountRestricted:
            return [.dashboard]
        case .townHallPost, .townHallComment, .townHallReaction,
             .announcement, .adminAnnouncement, .broadcast:
            return [.townHall]
        case .other:
            return []
        }
        // Badges always refreshed by coordinator (not per-type)
    }

    var entityIdKey: String? {
        switch self {
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted: return "ride_id"
        case .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted: return "favor_id"
        case .townHallPost, .townHallComment, .townHallReaction: return "post_id"
        case .message, .addedToConversation: return "conversation_id"
        default: return nil
        }
    }
}
```

Non-exhaustive switch produces a compiler warning — new types cannot be missed. `PushNotificationService` calls `coordinator.invalidate(type.affectedDomains)` — it does not import SyncEngines.

---

## Section 3: Two-Tier Refresh Strategy

### Tier 1: Targeted Refresh (push-triggered, cheap)

Fetches a single entity by ID from push payload. 1 REST call → 1 SwiftData upsert with change detection → conditional save.

```swift
func performTargetedRefresh(_ domain: Domain, entityId: UUID) async throws -> RefreshMetrics {
    switch domain {
    case .dashboard:
        // Determine entity type from context, fetch single item
        let ride = try await rideService.fetchRide(id: entityId)
        return try await backgroundActor.upsertRideWithChangeDetection(ride)
    case .townHall:
        let post = try await townHallService.fetchPost(id: entityId)
        return try await backgroundActor.upsertPostWithChangeDetection(post)
    case .conversations:
        // No single-conversation targeted refresh; mark invalidated instead
        return RefreshMetrics.skipped
    case .badges:
        await BadgeCountManager.shared.refreshAllBadges(reason: "push")
        return RefreshMetrics.badgeOnly
    }
}
```

### Tier 2: Full Reconciliation (staleness expiry, pull-to-refresh, initial sync)

Fetches all entities for a domain. Compare-before-write for each. Conditional save. Delete stale records.

```swift
func performFullSync() async throws -> RefreshMetrics {
    let (rides, favors, notifications) = try await fetchAllDashboard()
    return try await backgroundActor.syncAllWithChangeDetection(
        rides: rides, favors: favors, notifications: notifications,
        excludeMessagesForConversation: coordinator.activeConversationId
    )
}
```

### When Each Tier Is Used

| Trigger | Tier | Rationale |
|---|---|---|
| Push with entity ID | Targeted | 1 item, negligible cost |
| Push without entity ID | Mark invalidated → full on next access | No ID to target |
| Tab appear (stale) | Full reconciliation | Need complete, consistent data |
| Pull-to-refresh | Full reconciliation | User explicitly wants fresh data |
| Initial sync (startSync) | Full reconciliation | Baseline hydration |
| Safety poll | Full reconciliation | Catch-up for missed pushes |
| Background push w/ entity ID | Targeted | Budget-constrained |
| Background push w/o entity ID | Mark invalidated only | Defer to foreground |

---

## Section 4: SwiftData Write Strategy

### Change Detection (Mandatory)

All sync write paths use compare-before-write:

```swift
func updateSDRideIfChanged(_ existing: SDRide, with ride: Ride) -> Bool {
    var changed = false
    if existing.status != ride.status.rawValue { existing.status = ride.status.rawValue; changed = true }
    if existing.seats != ride.seats { existing.seats = ride.seats; changed = true }
    // ... all fields
    return changed
}
```

`modelContext.save()` called ONLY if at least one record was inserted, mutated, or deleted. This prevents phantom @Query re-evaluations.

### Write Paths

| Domain | Write Actor | Pattern |
|---|---|---|
| Dashboard (rides, favors, notifications) | `BackgroundSyncActor` | Full: batch fetch all → compare → upsert changed → delete stale → conditional save. Targeted: single fetch → compare → conditional save. |
| Town Hall (posts, comments) | `BackgroundSyncActor` (new — migrating from MainActor TownHallRepository) | Same as dashboard. Resolves known audit deviation. |
| Conversations | `BackgroundSyncActor.syncConversations()` | Returns changed IDs. Excludes messages for `activeConversationId`. Publisher refresh on MainActor after completion. |
| Messages (active conversation) | MainActor via `MessagingRepository` | Single-message upsert from WebSocket. `upsertMessageDetailed` returns `.noChange`/`.metadataOnly`/`.contentChanged`/`.inserted`. Only `.contentChanged`/`.inserted` trigger publisher refresh. |
| Messages (optimistic send) | MainActor via `MessagingRepository` | Insert `isPending=true` → immediate render → replace with server record on ack. |
| Badges | None — `@Published` properties | No SwiftData involvement. |

### NSNotification Contract

`.ridesDidSync`, `.favorsDidSync`, `.notificationsDidSync` posted ONLY after successful `modelContext.save()`. If save is skipped (no mutations), notification is NOT posted. Downstream handlers (`RequestRealtimeHandler`, `NotificationRealtimeHandler`) continue to observe these with existing debounced scheduling.

### Active Conversation Exclusion

`BackgroundSyncActor.syncConversations()` accepts `excludeMessagesForConversation: UUID?` parameter. Active conversation's messages are exclusively managed by the MainActor WebSocket path. Conversation metadata (title, participants, last message preview) is always synced. No concurrent writes to the same conversation's messages possible.

---

## Section 5: Observation Architecture

| Domain | Render Source | Why | Protection Against Churn |
|---|---|---|---|
| Rides | `@Query(sort: \SDRide.date)` | Low write frequency. Auto-updates. | Change detection prevents no-op saves. |
| Favors | `@Query(sort: \SDFavor.date)` | Same. | Same. |
| Notifications | `@Query(sort: \SDNotification.createdAt)` | Same. | Same. |
| Town Hall | Repository publisher | Existing pattern preserved. | Change detection on BackgroundSyncActor writes. |
| Conversations | `CurrentValueSubject<[ConversationWithDetails]>` | Needs manual control for metadata-only updates. | Publisher refresh only after explicit sync completion. |
| Messages | `CurrentValueSubject<[Message]>` per-conversation | High frequency. Needs metadata-only vs content distinction. | `.metadataOnly` → `saveContextOnly()`. `.noChange` → nothing. |
| Badges | `@Published` on BadgeCountManager | Not in SwiftData. | N/A. |

**Rules:** Never use `@Query` for messages or conversations (need granular update control). Never use manual publishers for rides/favors/notifications (@Query eliminates missed-refresh bugs). Do not mix patterns for the same model type.

---

## Section 6: Domain-by-Domain Policy Table

### Dashboard (SDRide, SDFavor, SDNotification)

| Aspect | Policy |
|---|---|
| Render source | `@Query` per entity type |
| Hydration | Persisted timestamp. Nil → `.unhydrated` → blocking full sync → skeleton. Non-nil → `.hydrated` → show cache. |
| Visible + push w/ entity ID | Targeted refresh (1 item) → change-detected upsert → conditional save |
| Visible + push w/o entity ID | Full reconciliation with change detection |
| Hidden + push w/ entity ID | Targeted refresh (1 item, negligible cost). Data fresh on tab switch. |
| Hidden + push w/o entity ID | Mark `.invalidated`. Full refresh on next tab appear. |
| Tab appear | Coordinator checks staleness (30s). Stale → background full reconciliation. Fresh → no-op. |
| Pull-to-refresh | Full reconciliation. Always fires. |
| Safety poll (5 min) | Full reconciliation with change detection. |
| Write path | `BackgroundSyncActor` only. Never MainActor. |
| Deletion | Full reconciliation: server IDs are truth, stale deleted. Targeted: never deletes. |
| Background push | Targeted only (≤8s, ≤2 REST, ≤20 mutations). No full reconciliation. |
| Empty state | After first sync with 0 results → empty state. Before first sync → skeleton. |
| Failure | `.failed(hasCache: true)` → show cached data. Backoff retry. |

### Town Hall (SDTownHallPost, SDTownHallComment)

| Aspect | Policy |
|---|---|
| Render source | Repository publisher |
| Hydration | Same as dashboard |
| Visible + push | Targeted if post ID available. Else full reconciliation. |
| Hidden + push | Targeted if post ID available. Else mark `.invalidated`. |
| Tab appear | Staleness check (30s). Background full reconciliation if stale. |
| Pull-to-refresh | Full reconciliation with change detection. |
| Write path | `BackgroundSyncActor` (new — migrating from MainActor). |
| Vote changes | No push. Pull-to-refresh only. |
| Background push | Targeted only. |

### Conversations (SDConversation)

| Aspect | Policy |
|---|---|
| Render source | `CurrentValueSubject<[ConversationWithDetails]>` |
| Hydration | Same — persisted timestamp |
| Visible + push | Background `refreshConversationList()` via BackgroundSyncActor |
| Hidden + push | Mark `.invalidated` only. No fetch. |
| Tab appear | Staleness check (30s). Background refresh. |
| Write path | `BackgroundSyncActor.syncConversations()` (existing). Excludes active conversation messages. |
| Background push | Mark invalidated. Defer to foreground. |

### Badges

| Aspect | Policy |
|---|---|
| Render source | `@Published` on BadgeCountManager |
| Storage | Not in SwiftData |
| Any push | Always refresh eagerly (1 RPC) |
| Safety poll | 5-minute timer |
| Background push | Always refresh (cheap) |

### Active Chat (SDMessage, per-conversation)

| Aspect | Policy |
|---|---|
| Render source | `CurrentValueSubject<[Message]>` per-conversation |
| Entry | Render from SwiftData cache → subscribe-then-fetch → reconcile |
| Live events | WebSocket → `upsertMessageDetailed()` on MainActor → conditional publisher refresh |
| Metadata-only | `readBy` changes → `saveContextOnly()` → metadata subject. No list rebuild. |
| Optimistic send | Insert `isPending=true` → immediate render → replace on ack |
| Coordinator integration | Not tracked. WebSocket is freshness mechanism. |

---

## Section 7: Realtime Subscription Model

### New State

| User location | WebSocket subscriptions | Data freshness source |
|---|---|---|
| App closed/backgrounded | 0 | APNs push |
| Dashboard tab | 0 | Pull-on-appear (30s staleness), push-triggered refresh |
| Town Hall tab | 0 | Pull-on-appear (30s staleness), pull-to-refresh |
| Messaging tab, conversation list | 0 | Push-triggered refresh |
| Messaging tab, inside conversation | 3 (messages + reactions + typing) | Live WebSocket |
| Any tab, app foregrounded | 0 | Badge refresh + 5-min safety poll |

### RealtimeManager Changes

- Remove `startSync()`-triggered always-on subscriptions for rides, favors, notifications, town hall
- Keep `subscribe()`/`unsubscribe()` API for conversation-scoped subscriptions
- Remove 3-tier staggered reconnection logic
- Keep background auto-unsubscribe (30s grace period)
- Simplify to max ~3 concurrent channels

---

## Section 8: Conversation WebSocket Lifecycle

### State Machine — Conversation-Scoped with Grace Period

```
User enters messaging tab
  → no WebSocket (list shows cached/pulled data)

User opens conversation
  → subscribeToConversation(id) — messages + reactions channels
  → TypingIndicatorManager.startObserving(id) — typing channel
  → coordinator.setActiveConversation(id)
  → Subscribe-then-fetch sequence (see below)

User taps back to conversation list
  → start 5-second grace timer
  → If re-enters SAME conversation within 5s → cancel timer, no-op
  → If 5s expires → unsubscribe all 3 channels, clear activeConversationId
  → If enters DIFFERENT conversation → cancel timer, unsubscribe old, subscribe new

User leaves messaging tab
  → immediate unsubscribe (no grace period)
  → TypingIndicatorManager.stopObserving()
  → coordinator.setActiveConversation(nil)

App backgrounds
  → immediate unsubscribe (no grace period)
```

### Subscribe-Then-Fetch (Message Consistency)

```
1. Subscribe to messages + reactions + typing channels
   → Events begin buffering in Supabase client

2. Wait for subscription confirmation (max 3s timeout)

3. REST fetch recent messages (last 50 or since last known timestamp)
   → Returns server truth as of ~now

4. Upsert fetched messages to SwiftData via MessagingRepository
   → Dedup by message UUID against cache
   → Compare-before-write for existing messages

5. Process buffered WebSocket events
   → Same upsert path → dedup handles overlap with REST results

6. WebSocket is now live — all future events processed normally
```

**Why subscribe before fetch:** Closes the race window between REST fetch (returns data as of T0) and WebSocket connection (delivers events from T2). Events arriving between T0 and T2 are buffered by the Supabase client and processed in step 5. Dedup prevents duplicates.

### Quick Reply from Push

Quick-reply sends via `MessageService.shared.sendMessage()` directly. Message won't appear in local state until user navigates to messaging tab. Acceptable — conversation opens with REST fetch that includes the sent message. `handlePushReceived()` called after quick-reply to refresh conversation list metadata.

---

## Section 9: Push-Triggered Data Refresh

### Foreground Push Receipt

```
Push arrives (willPresent)
  → PushNotificationService extracts NotificationType
  → type.affectedDomains → coordinator.invalidate(domains)
  → If entity ID available → coordinator.performTargetedRefresh(domain, entityId)
  → coordinator.invalidate([.badges]) (always)
  → Smart suppression decides whether to show banner
```

### Background Push Receipt

```
Push arrives (didReceiveRemoteNotification:fetchCompletionHandler:)
  → Start 25s deadline timer (guarantees completion handler is called)
  → Extract NotificationType and entity ID
  → If entity ID: targeted refresh (≤8s budget, ≤2 REST, ≤20 mutations)
  → If no entity ID: mark invalidated only (defer to foreground)
  → Badge refresh (always, cheap)
  → Cancel deadline, call completionHandler
```

`AppDelegate` does NOT currently implement `didReceiveRemoteNotification:fetchCompletionHandler:`. Must be added. Info.plist already has `UIBackgroundModes` with `remote-notification` and `fetch`.

**Caveat:** `content-available` combined with visible alerts is best-effort. iOS may throttle background wakes. The 5-minute safety poll is the correctness backstop.

### Edge Function Changes

Add `"content-available": 1` to `aps` payload in both `send-message-push/index.ts` and `send-notification/index.ts`. Update `send-message-push` TypeScript `APNsPayload` interface to include the field.

### In-App Toast Behavior

When user is NOT on messaging tab: system notification banner via `willPresent` (existing behavior). When user IS on messaging tab with active WebSocket: existing flow — realtime event → `.conversationUpdated` → `InAppToastManager` shows custom toast.

---

## Section 10: SyncEngine Protocol

### Updated Contract

```swift
protocol SyncEngine {
    func setup(modelContext: ModelContext)
    func setupBackgroundActor(container: ModelContainer)
    func performFullSync() async throws -> RefreshMetrics
    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics
    func teardown()
}
```

Engines are pure fetch-and-store. They do NOT own staleness tracking, in-flight dedup, or refresh decisions — the coordinator does.

`startSync()` on the coordinator triggers `performFullSync()` for each domain. `pauseSync()`/`resumeSync()` become coordinator concerns (cancel/restart safety poll timer). `refreshIfStale()`/`forceRefresh()` are replaced by the coordinator's state machine.

For `MessagingSyncEngine`, additional methods remain outside the protocol:
- `subscribeToConversation(id:)` / `unsubscribeFromConversation()` / `switchConversation(id:)` / `beginGracePeriod()`
- `refreshConversationList()` (conversation list metadata refresh)

---

## Section 11: Badge Count Manager

### Changes

- Remove 30s/90s polling timers
- Remove `RealtimeManager.$isConnected` listener
- Safety poll timer moves to RefreshCoordinator
- Remove `isRefreshing` + `lastRefreshTime` internal guards — coordinator handles dedup
- Keep 5s debounce (prevents push bursts)
- Keep failure handling (exponential backoff, `isBadgeStale` fallback)
- Keep `clearMessagesBadge(conversationId:)` optimistic local clear
- Keep app icon badge update

**Expected impact:** ~43K calls → ~5-8K calls (~80% reduction).

---

## Section 12: Teardown and Sign-Out

### Sign-Out Sequence (Synchronous on MainActor)

```
1. RefreshCoordinator.reset()
   → cancel all in-flight tasks (await completion)
   → reset all domain states to nil
   → invalidate safety poll timer
   → visibleDomain = nil, activeConversationId = nil

2. MessagingSyncEngine.teardown()
   → cancelGracePeriodAndUnsubscribe()
   → TypingIndicatorManager.stopObserving()
   → stop MessageSendWorker
   → clear activeConversationId

3. DashboardSyncEngine.teardown()
   → cancel in-flight fetch tasks

4. TownHallSyncEngine.teardown()
   → cancel in-flight fetch tasks

5. BadgeCountManager.teardown()
   → cancel in-flight RPC
   → zero badge counts, reset app icon badge

6. RealtimeManager.teardown()
   → unsubscribe remaining channels, disconnect

7. PushNotificationService.removeDeviceToken()

8. SwiftData wipe
   → modelContext.delete(model:) for all 8 SD types
   → modelContext.save() ← blocks until store confirms

9. Clear sync timestamps
   → UserDefaults remove all "refresh.lastSync.*" keys

10. CacheManager.clearAll()
```

### App Foreground/Background

- **Background:** Immediate WebSocket teardown. Cancel safety poll timer.
- **Foreground:** `coordinator.handleAppForegrounded()` → refresh badges, check staleness for visible domain. If was in conversation, resubscribe. Restart safety poll timer.

---

## Section 13: Code Cleanup

### Stale Code to Remove

| File | Removals |
|---|---|
| `RealtimeManager` | 3-tier staggered reconnection. Protected channel priority. Simplify to max ~3 channels. |
| `DashboardSyncEngine` | All realtime subscriptions, payload parsing, incremental upsert from realtime, debounced full-sync fallback. Replace with `performFullSync()` / `performTargetedSync()`. |
| `TownHallSyncEngine` | All realtime subscriptions, payload parsing, 600ms debounce. MainActor write paths (migrating to BackgroundSyncActor). |
| `MessagingSyncEngine` | Global `messages:sync` subscription. Replace with conversation-scoped management. |
| `BadgeCountManager` | 30s/90s timers. `RealtimeManager.$isConnected` listener. `isRefreshing`/`lastRefreshTime` guards. |
| `RealtimePayloadAdapter` | Simplify to message/reaction shapes only. |
| `SyncEngineOrchestrator` | Replaced by RefreshCoordinator as lifecycle owner. |

### Dead Code Audit

- `DashboardPayloadMapper` — remove if only used for realtime parsing. Also remove tests in `RealtimePayloadDecodingTests.swift`.
- `NotificationPayloadMapper` — same.
- `TownHallPayloadMapper` (private in TownHallSyncEngine) — dead after realtime removal.
- `StalenessTracker` utility — NOT created. Staleness absorbed into coordinator.
- Verify `.ridesDidSync`, `.favorsDidSync`, `.notificationsDidSync` are still posted from `performFullSync()` path.

### Documentation Updates

**CLAUDE.md:** Update Current State, Fragile Systems §1/§5/§6/§7, Realtime Rules, Cross-Layer Sync Rules (add push-received handler + RefreshCoordinator as high-blast-radius seams), Audit Notes (remove TownHallSyncEngine MainActor deviation), Quick Reference.

**AGENTS.md:** Mirror architectural changes.

**Cursor rules:** Update rules `01`, `03`, master rule.

---

## Section 14: Observability

### RefreshResult

```swift
enum RefreshResult {
    case completed(RefreshMetrics)
    case skipped(SkipReason)
    case joined(inFlightTrigger: String)
    case failed(Error, partial: RefreshMetrics?)
}

struct RefreshMetrics {
    let recordsEvaluated: Int   // total items compared
    let recordsMutated: Int     // items with actual value changes
    let recordsInserted: Int    // new items
    let recordsDeleted: Int     // stale items removed
    let savedToStore: Bool      // whether save() was called
    let durationMs: Int
}

enum SkipReason: String {
    case fresh, backoff, guestMode, domainNotStarted
}
```

### Logging Contract

Every refresh decision is logged:

| Event | Fields |
|---|---|
| Refresh started | domain, trigger, hasCache |
| Refresh completed | domain, trigger, evaluated, mutated, inserted, deleted, saved, durationMs |
| Refresh joined | domain, trigger, inFlightTrigger |
| Refresh skipped | domain, trigger, skipReason, staleIn (if fresh) |
| Refresh failed | domain, trigger, error, partial metrics |
| Invalidation | domain, reason, previousState |
| Domain visible | domain, staleness, willRefresh |
| Sign-out wipe | all domains reset |

### Debug Diagnostics

```swift
struct RefreshDiagnostics {
    let timestamp: Date
    let domains: [DomainSnapshot]
    let activeConversation: UUID?
    let visibleDomain: Domain?
}

struct DomainSnapshot {
    let domain: Domain
    let state: String
    let lastSync: Date?
    let hasLocalData: Bool
    let isInFlight: Bool
    let lastTrigger: String?
    let lastResult: String?
}
```

Debug overlay (debug builds only): `RefreshDiagnosticsView` accessible via debug gesture, shows live state of all domains.

---

## Section 15: Risk Mitigation and Testing

### Risk Matrix

| Risk | Severity | Mitigation |
|---|---|---|
| Message loss during WebSocket lifecycle | High | Subscribe-then-fetch closes the gap. Dedup by UUID. |
| Push delivery failure | Medium | 5-min safety poll. 30s staleness on tab switch. |
| Badge divergence | Medium | Existing `isBadgeStale` + backoff. Always-eager badge refresh on push. |
| Write amplification from full reconciliation | High | Change detection prevents no-op writes. Conditional save. |
| @Query thrash | High | Change detection (INV-W1). No save = no @Query re-evaluation. |
| Cross-user cache leakage | Critical | SwiftData wipe on sign-out. Synchronous ordering (INV-S1). |
| Background execution timeout | Medium | ≤8s budget. Targeted only. Deadline timer guarantees completion handler. |
| Concurrent background/foreground writes | Medium | Active conversation exclusion (INV-C1). |
| Hydration timestamp drift | Low | Advisory timestamps + SwiftData count fallback. Self-healing. |

### Manual Testing Matrix

| Scenario | Verify |
|---|---|
| Open conversation, receive message | Live via WebSocket |
| On conversation list, receive message | Badge updates, list refreshes on tab appear |
| On dashboard, new ride push | Targeted refresh, tab badge updates |
| On town hall, pull to refresh | Fresh data loads |
| Switch tabs rapidly | No duplicate fetches, no crashes |
| Background 31+ seconds, return | WebSocket reconnects, badges refresh |
| Background, receive push, tap | Navigates correctly with fresh data |
| Sign out, sign in as different user | No stale data from previous session |
| Kill app, reopen | Fresh fetch, no stale subscriptions |
| Airplane mode on/off | Safety poll resumes |
| Send while WebSocket reconnecting | Optimistic send works, reconciles on reconnect |
| Quick-reply from banner | Sends, conversation list refreshes |
| Guest mode, browse tabs | Pull-on-appear works, no auth errors |
| Two devices, message on A | Device B receives push, refreshes |
| Force-quit, tap notification | Launches, navigates, data loads |
| In-app: dashboard, message push | System banner (not custom toast) |
| In-app: conversation A, message for B | Custom toast via `.conversationUpdated` |
| Push burst (5 pushes in 2s) | Coordinator deduplicates, ≤2 fetches |

### Automated Tests

| Test | Coverage |
|---|---|
| RefreshCoordinator state machine | All transitions, join semantics, staleness, backoff |
| Push → domain mapping | Every NotificationType maps to correct domains |
| Change detection (BackgroundSyncActor) | No-op write prevention, conditional save |
| DashboardSyncEngine full + targeted | Both tiers, metrics reporting |
| TownHallSyncEngine full + targeted | Same |
| MessagingSyncEngine conversation scoping | Subscribe/unsubscribe/switch/grace period |
| BadgeCountManager | 5-min interval, push trigger, debounce |
| Teardown completeness | All timers, states, SwiftData wiped |
| Hydration detection | Timestamp present, missing, crash recovery |

---

## Section 16: Authoritative Invariants

### Refresh

- **INV-R1:** At most ONE refresh task per domain at any time. Additional triggers join in-flight.
- **INV-R2:** `MainTabView.onChange(of: selectedTab)` is the sole staleness-based trigger. ViewModels do not call refresh.
- **INV-R3:** Push and tab-appear use same coordinator state machine. No duplicate concurrent fetches.
- **INV-R4:** Max staleness: 30s for visited domains, 5 min for unvisited, 30s for guests.

### SwiftData

- **INV-W1:** No save without mutation. Change detection mandatory. Conditional `modelContext.save()`.
- **INV-W2:** Batch sync via BackgroundSyncActor. Single-message via MainActor. Active conversation excluded from background sync.
- **INV-W3:** @Query fires only on actual data changes (guaranteed by INV-W1).
- **INV-W4:** NSNotifications posted only after successful save. No save = no notification.
- **INV-W5:** `lastSuccessfulSync` written only after `modelContext.save()` succeeds.

### Session

- **INV-S1:** Sign-out is synchronous on MainActor: teardown → wipe → save → clear timestamps.
- **INV-S2:** After sign-out: all domains nil, SwiftData empty, @Query returns [], badges zero.
- **INV-S3:** No cross-user data leakage. Wipe completes before new user UI mounts.

### Concurrency

- **INV-C1:** BackgroundSyncActor never writes messages for `activeConversationId`.
- **INV-C2:** RefreshCoordinator is `@MainActor`. No race conditions on state.

### WebSocket

- **INV-WS1:** At most one conversation has active channels at any time.
- **INV-WS2:** Subscribe → confirmation → REST fetch → upsert → process buffered events.
- **INV-WS3:** 5s grace period only on back-to-list. Tab switch and background = immediate teardown.
- **INV-WS4:** All WebSocket handlers marshal to `@MainActor`.

### Background

- **INV-B1:** ≤8s execution. **INV-B2:** ≤2 REST calls, ≤20 mutations. **INV-B3:** No full reconciliation. **INV-B4:** Completion handler always called.

### Observability

- **INV-O1:** Every refresh decision logged. **INV-O2:** Metrics on every completion. **INV-O3:** Diagnostic snapshot available.

---

## Files Affected

### Client — New
| File | Purpose |
|---|---|
| `Core/Services/RefreshCoordinator.swift` | Centralized refresh orchestration, state machine, staleness, dedup |
| `Core/Models/RefreshMetrics.swift` | Metrics and result types |

### Client — Major Changes
| File | Change |
|---|---|
| `Core/Services/RealtimeManager.swift` | Remove always-on subscriptions, simplify to ~3 channels |
| `Core/Storage/DashboardSyncEngine.swift` | Replace realtime with `performFullSync()`/`performTargetedSync()`, add change detection |
| `Core/Storage/TownHallSyncEngine.swift` | Same + migrate to BackgroundSyncActor writes |
| `Core/Storage/MessagingSyncEngine.swift` | Scope to active conversation, add grace period, subscribe-then-fetch |
| `Core/Storage/BackgroundSyncActor.swift` | Add change detection, `excludeMessagesForConversation`, targeted upsert methods, TownHall sync |
| `Core/Storage/SyncEngineProtocol.swift` | Simplify to `performFullSync`/`performTargetedSync`/`teardown` |

### Client — Medium Changes
| File | Change |
|---|---|
| `Core/Services/BadgeCountManager.swift` | Remove polling timers, remove `isConnected` listener |
| `Core/Services/PushNotificationService.swift` | Add `handlePushReceived` → coordinator delegation |
| `App/AppDelegate.swift` | Implement `didReceiveRemoteNotification:fetchCompletionHandler:` |
| `Core/Models/AppNotification.swift` | Add `affectedDomains` and `entityIdKey` to NotificationType |

### Client — Minor Changes
| File | Change |
|---|---|
| `App/MainTabView.swift` | Add `onChange(of: selectedTab)` → coordinator |
| `Core/Services/InAppToastManager.swift` | Verify behavior with system banner fallback |
| `Core/Storage/MessagingRepository.swift` | Verify `refreshConversationList` path |
| `Features/Messaging/ViewModels/TypingIndicatorManager.swift` | Verify teardown alignment |
| `Features/Requests/ViewModels/RequestRealtimeHandler.swift` | Verify NSNotification compatibility |
| `Features/Notifications/ViewModels/NotificationRealtimeHandler.swift` | Same |
| `App/AuthService.swift` | Add SwiftData wipe + timestamp clear to sign-out |

### Client — Removed
| File | Condition |
|---|---|
| `DashboardPayloadMapper` | If only used for realtime (+ tests) |
| `NotificationPayloadMapper` | Same |
| `TownHallPayloadMapper` (private) | Dead after realtime removal |
| `SyncEngineOrchestrator` | Replaced by RefreshCoordinator |

### Backend — Modified
| File | Change |
|---|---|
| `supabase/functions/send-message-push/index.ts` | Add `content-available: 1` + update interface |
| `supabase/functions/send-notification/index.ts` | Add `content-available: 1` |

### Documentation — Modified
| File | Change |
|---|---|
| `CLAUDE.md` | Multiple sections per Section 13 |
| `AGENTS.md` | Mirror changes |
| `.cursor/rules/01`, `03`, master | Update for new architecture |
