# Performance Remediation Plan — Latency, Hitching & Freezing

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate main-thread latency, hitching, and freezing caused by cascading renders, N+1 SwiftData queries, expensive view-body computations, and unnecessary MainActor contention.

**Architecture:** The app is local-first with SwiftData, Supabase Realtime, and a singleton-heavy service layer — all pinned to `@MainActor`. This plan incrementally reduces MainActor pressure across 4 tiers, ordered by risk/reward. Each tier is independently shippable and verifiable.

**Tech Stack:** Swift, SwiftUI, SwiftData, Supabase (Realtime + REST + RPC), Combine, iOS 17+

**Important:** Every tier MUST be verified with a manual smoke test on-device (or Simulator) before moving to the next. The hitching is a UX issue — only real render timings prove the fix works.

---

## Tier 0 — Surgical Fixes (Zero Risk, Immediate Effect)

These are pure wins with no behavioral changes. Each is a 1-file edit.

---

### Task 0.1: Remove Double-Wrapped Badge Dispatch

The `didBecomeActiveNotification` handler in BadgeCountManager wraps a `Task { @MainActor in }` inside `DispatchQueue.main.async`. Since BadgeCountManager is already `@MainActor`, the outer dispatch is redundant and adds a frame of latency on every app foreground.

**Files:**
- Modify: `NaarsCars/Core/Services/BadgeCountManager.swift`

**Step 1: Read the current code**

Read `BadgeCountManager.swift` and locate `setupNotificationListeners()`. Confirm the double-wrapped pattern around line 113:
```swift
DispatchQueue.main.async {
    Task { @MainActor [weak self] in
        await self?.refreshAllBadges(reason: "didBecomeActive")
        self?.updatePollingInterval(reason: "didBecomeActive")
    }
}
```

**Step 2: Replace with single Task dispatch**

Replace the double-wrapped block with:
```swift
Task { [weak self] in
    // Yield once so the first frame after foreground isn't blocked
    await Task.yield()
    await self?.refreshAllBadges(reason: "didBecomeActive")
    self?.updatePollingInterval(reason: "didBecomeActive")
}
```

The `Task.yield()` preserves the original intent (deferring past the first frame) without the unnecessary `DispatchQueue.main.async` hop.

**Step 3: Run existing tests**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests 2>&1 | tail -20`

Expected: All tests pass. No test currently covers this code path directly — the change is behavior-preserving.

**Step 4: Commit**

```
fix: remove double-wrapped DispatchQueue.main.async in BadgeCountManager

The didBecomeActive handler unnecessarily wrapped Task { @MainActor }
inside DispatchQueue.main.async. Since BadgeCountManager is already
@MainActor, this added a redundant frame of latency. Replaced with
Task.yield() to preserve the single-frame defer without the extra hop.
```

---

### Task 0.2: Coalesce Badge Property Updates with withTransaction

BadgeCountManager updates 8 `@Published` properties sequentially in `refreshAllBadges()`. Each update triggers a separate `objectWillChange.send()`, causing MainTabView to re-evaluate its body 8 times per badge refresh (every 30 seconds).

**Files:**
- Modify: `NaarsCars/Core/Services/BadgeCountManager.swift`

**Step 1: Read the current code**

Read `BadgeCountManager.swift` and locate `refreshAllBadges()`. Confirm the sequential updates pattern — 8 separate @Published property assignments.

**Step 2: Wrap property updates in a manual objectWillChange batch**

Replace the sequential updates with a pattern that sends `objectWillChange` once:

```swift
// Before: 8 separate objectWillChange emissions
// After: manual single emission

// Suppress auto-publishing by updating backing storage directly
// Since we can't easily suppress @Published, we'll use a struct to batch:
```

The cleanest approach: introduce a `BadgeCounts` struct to hold all badge values as a single `@Published` property.

Find the 8 individual `@Published` badge properties and replace them with:

```swift
struct BadgeCounts: Equatable {
    var requests: Int = 0
    var messages: Int = 0
    var community: Int = 0
    var profile: Int = 0
    var adminPanel: Int = 0
    var bell: Int = 0
    var totalUnread: Int = 0
}

@Published private(set) var counts = BadgeCounts()
@Published var isBadgeStale: Bool = false
```

Then update `refreshAllBadges()` to build the struct and assign once:

```swift
var newCounts = BadgeCounts()
newCounts.requests = serverCounts.requestsTotal
newCounts.messages = serverCounts.messagesTotal
newCounts.community = serverCounts.communityTotal
newCounts.profile = profileBadge
newCounts.adminPanel = profileBadge
newCounts.bell = serverCounts.bellTotal
newCounts.totalUnread = serverCounts.requestsTotal + serverCounts.messagesTotal + serverCounts.communityTotal
counts = newCounts  // ONE objectWillChange emission
```

**Step 3: Update all call sites**

Search for all references to the old property names and update:
- `MainTabView.swift` — `badgeManager.requestsBadgeCount` → `badgeManager.counts.requests`, etc.
- Any ViewModel that reads badge counts.

Use compiler errors to find them all: build, fix each error, repeat.

**Step 4: Run tests**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests 2>&1 | tail -20`

**Step 5: Commit**

```
perf: coalesce 8 badge property updates into single @Published struct

BadgeCountManager previously updated 8 @Published properties
sequentially, causing 8 objectWillChange emissions per refresh.
Consolidated into a single BadgeCounts struct so MainTabView
re-evaluates once per badge refresh instead of 8 times.
```

---

## Tier 1 — Eliminate Redundant Renders (Low Risk, High Impact)

These changes fix the render-multiplier problem caused by `objectWillChange` forwarding from child managers.

---

### Task 1.1: Remove objectWillChange Forwarding in RequestsDashboardViewModel

**Problem:** 3 child managers (filterManager, summaryManager, realtimeHandler) each forward `objectWillChange` to the parent ViewModel. Any child update causes a full view re-render, even if the parent's own state hasn't changed.

**Strategy:** Since iOS 17+ is the deployment target, convert child managers to use `@Observable` (Observation framework). Views that need child state will observe it directly, with fine-grained tracking.

**Files:**
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift`
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestNotificationSummaryManager.swift`
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestRealtimeHandler.swift`
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift`

**Step 1: Convert RequestFilterManager to @Observable**

Read `RequestFilterManager.swift`. Replace:
```swift
class RequestFilterManager: ObservableObject {
    @Published var someProperty: ...
```
With:
```swift
@Observable
class RequestFilterManager {
    var someProperty: ...
```

Remove all `@Published` property wrappers — `@Observable` tracks access automatically.

**Step 2: Convert RequestNotificationSummaryManager to @Observable**

Same pattern as Step 1.

**Step 3: Convert RequestRealtimeHandler to @Observable**

Same pattern as Step 1.

**Step 4: Remove objectWillChange forwarding from RequestsDashboardViewModel**

In `RequestsDashboardViewModel.swift`, remove the 3 Combine sinks:
```swift
// DELETE these lines:
filterManager.objectWillChange
    .sink { [weak self] _ in self?.objectWillChange.send() }
    .store(in: &managerCancellables)
summaryManager.objectWillChange
    .sink { [weak self] _ in self?.objectWillChange.send() }
    .store(in: &managerCancellables)
realtimeHandler.objectWillChange
    .sink { [weak self] _ in self?.objectWillChange.send() }
    .store(in: &managerCancellables)
```

Also remove `private var managerCancellables` if it's no longer used.

**Step 5: Update RequestsDashboardView to observe child managers directly**

If the view accesses child manager state through the parent ViewModel (e.g., `viewModel.filterManager.filteredRequests`), it will now track those accesses automatically via `@Observable`. No view changes needed if the ViewModel exposes child managers as public properties.

If the ViewModel re-exposes child state as its own computed properties (e.g., `var filteredRequests: [RequestItem] { filterManager.filteredRequests }`), those will still work — `@Observable` tracks the read through the computed property.

Verify by building the project and checking for compilation errors.

**Step 6: Run tests**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests 2>&1 | tail -20`

**Step 7: Commit**

```
perf: convert Request child managers to @Observable, remove forwarding

RequestFilterManager, RequestNotificationSummaryManager, and
RequestRealtimeHandler converted from ObservableObject to @Observable.
Removed 3 objectWillChange forwarding sinks from
RequestsDashboardViewModel. SwiftUI now tracks property access
per-view instead of re-rendering on any child change.
```

---

### Task 1.2: Remove objectWillChange Forwarding in ConversationDetailViewModel

**Same pattern as 1.1** but for the messaging feature.

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationSearchManager.swift`
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationTypingManager.swift` (find this file)
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationPaginationManager.swift` (find this file)
- Modify: `NaarsCars/Features/Messaging/ViewModels/MessageSendManager.swift` (find this file)
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Step 1: Convert all 4 child managers to @Observable**

For each: replace `class Foo: ObservableObject` with `@Observable class Foo`, remove `@Published` wrappers.

**Step 2: Remove the 4 objectWillChange forwarding sinks**

In `ConversationDetailViewModel.setupManagerObservation()`, delete:
```swift
searchManager.objectWillChange
    .sink { [weak self] in self?.objectWillChange.send() }
    .store(in: &cancellables)
// ... repeat for typingManager, paginationManager, sendManager
```

**Step 3: Build and fix compiler errors**

**Step 4: Run tests**

Run messaging tests specifically: `xcodebuild test ... -only-testing:NaarsCarsTests/MessageServiceTests`

**Step 5: Commit**

```
perf: convert Conversation child managers to @Observable, remove forwarding

ConversationSearchManager, TypingManager, PaginationManager, and
SendManager converted to @Observable. Removed 4 objectWillChange
forwarding sinks from ConversationDetailViewModel.
```

---

### Task 1.3: Remove objectWillChange Forwarding in NotificationsListViewModel

**Same pattern as 1.1** but for the notifications feature.

**Files:**
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationGroupingManager.swift` (find this file)
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationRealtimeHandler.swift`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift`

**Steps:** Follow the same pattern as Tasks 1.1 and 1.2.

**Commit:**
```
perf: convert Notification child managers to @Observable, remove forwarding
```

---

### Task 1.4: Verify Render Reduction

**This is a verification-only task — no code changes.**

**Step 1: Add temporary render counting**

In `RequestsDashboardView.swift`, add to the body:
```swift
let _ = Self._printChanges()
```

Do the same in `ConversationDetailView.swift` and `NotificationsListView.swift`.

**Step 2: Run in Simulator, trigger a realtime event**

Create or update a ride from another device/session. Count how many times `_printChanges()` fires for RequestsDashboardView. Before this tier, it would fire 3+ times per event. After, it should fire once (or not at all if the view's tracked properties didn't change).

**Step 3: Remove the `_printChanges()` calls**

**Step 4: Commit**

```
chore: verify render count reduction after @Observable migration
```

---

## Tier 2 — Eliminate Expensive View Body Computations (Medium Risk, High Impact)

These changes move O(n) work out of SwiftUI view body evaluation and into ViewModel state that updates only when source data changes.

---

### Task 2.1: Move Notification Grouping Out of View Body

**Problem:** `NotificationsListView.notificationsList()` computes `filter`, `Dictionary(grouping:)`, `Calendar.current.startOfDay()`, and `sorted(by:)` inline in the view body — on every render.

**Files:**
- Modify: `NaarsCars/Features/Notifications/Views/NotificationsListView.swift`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift` (or the groupingManager)

**Step 1: Read the current view body code**

Read `NotificationsListView.swift` lines 93-129. Confirm the inline grouping:
```swift
let pinned = groups.filter { $0.isPinned }
let regular = groups.filter { !$0.isPinned }
let grouped = Dictionary(grouping: regular) { ... }
let sortedKeys = grouped.keys.sorted(by: >)
```

**Step 2: Create a precomputed struct**

In the ViewModel (or groupingManager), add:

```swift
struct GroupedNotifications {
    let pinned: [NotificationGroup]
    let sections: [(date: Date, groups: [NotificationGroup])]
}

// In the manager that produces NotificationGroups:
var groupedNotifications: GroupedNotifications {
    // Only recomputed when source data changes (via @Observable tracking)
    let allGroups = getNotificationGroups(sdNotifications)
    let pinned = allGroups.filter { $0.isPinned }
    let regular = allGroups.filter { !$0.isPinned }
    let dict = Dictionary(grouping: regular) { group in
        Calendar.current.startOfDay(for: group.primaryNotification.createdAt)
    }
    let sorted = dict.keys.sorted(by: >).map { date in
        (date: date, groups: dict[date] ?? [])
    }
    return GroupedNotifications(pinned: pinned, sections: sorted)
}
```

**Step 3: Update the view to consume precomputed data**

Replace the inline computation in `notificationsList(groups:)` with:
```swift
private func notificationsList() -> some View {
    let data = viewModel.groupedNotifications
    List {
        if !data.pinned.isEmpty {
            Section {
                ForEach(data.pinned) { group in
                    notificationRow(for: group)
                }
            }
        }
        ForEach(data.sections, id: \.date) { section in
            Section(header: Text(dayString(section.date))) {
                ForEach(section.groups) { group in
                    notificationRow(for: group)
                }
            }
        }
        // ... archived hint section
    }
}
```

**Step 4: Run tests and build**

**Step 5: Commit**

```
perf: precompute notification grouping in ViewModel instead of view body

Moved filter/Dictionary(grouping:)/sort operations out of
NotificationsListView body into ViewModel. View now consumes
precomputed GroupedNotifications struct.
```

---

### Task 2.2: Cache messageCellConfigurations in ConversationDetailViewModel

**Problem:** `ConversationDetailView.messageCellConfigurations` is a computed property that iterates ALL messages and calls 3 helper functions per message. It runs on every view body evaluation.

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Step 1: Read the current computed property**

Read `ConversationDetailView.swift` lines 374-386.

**Step 2: Move to ViewModel as cached @Published**

In `ConversationDetailViewModel`, add:

```swift
@Published private(set) var messageCellConfigurations: [UUID: MessageCellConfiguration] = [:]

private func recomputeCellConfigurations() {
    var configs: [UUID: MessageCellConfiguration] = [:]
    for (index, message) in messages.enumerated() {
        configs[message.id] = MessageCellConfiguration(
            messageId: message.id,
            isFirstInSeries: isFirstInSeries(at: index),
            isLastInSeries: isLastInSeries(at: index),
            showDateSeparator: shouldShowDateSeparator(at: index)
        )
    }
    messageCellConfigurations = configs
}
```

Move the `isFirstInSeries`, `isLastInSeries`, `shouldShowDateSeparator` helper functions from the View to the ViewModel.

**Step 3: Call recomputeCellConfigurations() when messages change**

Add a `didSet` on the `messages` property, or call it at the end of every method that mutates `messages`:
```swift
@Published var messages: [Message] = [] {
    didSet { recomputeCellConfigurations() }
}
```

**Step 4: Remove the computed property from the View**

In `ConversationDetailView.swift`, remove the `messageCellConfigurations` computed property and all its helper functions. Replace usages with `viewModel.messageCellConfigurations`.

**Step 5: Run messaging tests**

**Step 6: Commit**

```
perf: cache messageCellConfigurations in ViewModel instead of View body

Moved O(n) cell configuration computation from ConversationDetailView
computed property to ConversationDetailViewModel. Now recalculated
only when messages array changes, not on every view body evaluation.
```

---

### Task 2.3: Make unreadCount a Stored Property

**Problem:** `ConversationDetailViewModel.unreadCount` filters the entire messages array on every access. It's accessed from the view body, so it runs on every render.

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Step 1: Read the computed property**

Confirm at lines 46-51:
```swift
var unreadCount: Int {
    guard let userId = authService.currentUserId else { return 0 }
    return messages.filter { ... }.count
}
```

**Step 2: Convert to stored @Published with didSet update**

```swift
@Published private(set) var unreadCount: Int = 0

private func recomputeUnreadCount() {
    guard let userId = authService.currentUserId else {
        unreadCount = 0
        return
    }
    unreadCount = messages.filter { message in
        message.fromId != userId && !message.readBy.contains(userId)
    }.count
}
```

**Step 3: Call recomputeUnreadCount() in all mutation paths**

This must be called whenever `messages` changes. Since Task 2.2 already adds a `didSet` on `messages`, extend it:
```swift
@Published var messages: [Message] = [] {
    didSet {
        recomputeCellConfigurations()
        recomputeUnreadCount()
    }
}
```

Also call `recomputeUnreadCount()` after any in-place readBy update (metadata-only updates that don't replace the array).

**Step 4: Run tests**

**Step 5: Commit**

```
perf: convert unreadCount from computed to stored @Published

Was filtering entire messages array on every view body evaluation.
Now recomputed only when messages array changes via didSet.
```

---

### Task 2.4: Move filteredConversations to ViewModel

**Problem:** `ConversationsListView.filteredConversations` runs `.lowercased()` and `.contains()` on every conversation on every render.

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationsListView.swift`
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`

**Step 1: Read the current computed property in the view**

**Step 2: Move to ViewModel**

In `ConversationsListViewModel`, add:
```swift
@Published private(set) var filteredConversations: [ConversationWithDetails] = []

private func recomputeFilteredConversations() {
    if searchText.isEmpty {
        filteredConversations = conversations
        return
    }
    let query = searchText.lowercased()
    filteredConversations = conversations.filter { convo in
        // ... same filtering logic as the view currently has
    }
}
```

Call `recomputeFilteredConversations()` from `didSet` on both `conversations` and `searchText`.

**Step 3: Update view to use `viewModel.filteredConversations`**

**Step 4: Run tests and commit**

```
perf: move filteredConversations to ViewModel, compute on data change only
```

---

## Tier 3 — Fix N+1 SwiftData Queries (Medium Risk, Medium-High Impact)

These changes fix the sync storm that occurs when realtime events trigger per-item SwiftData fetches.

---

### Task 3.1: Batch-Fetch in DashboardSyncEngine.syncRides

**Problem:** `syncRides()` executes a separate `FetchDescriptor` per ride in a loop. For 50 rides, that's 50 SwiftData queries.

**Files:**
- Modify: `NaarsCars/Core/Storage/DashboardSyncEngine.swift`

**Step 1: Write a failing test (if test infrastructure supports SwiftData)**

If the test target has SwiftData model container setup, write a test:
```swift
@MainActor
func testSyncRidesBatchFetch() async throws {
    // Setup: insert 50 SDRides
    // Action: call syncRides with 50 server rides (25 existing, 25 new)
    // Assert: all 50 SDRides exist with correct data
    // Assert: no extra SDRides from before
}
```

If no SwiftData test infrastructure exists, skip TDD for this task and verify manually.

**Step 2: Replace per-item fetch with batch fetch**

Replace:
```swift
private func syncRides(_ rides: [Ride], in context: ModelContext) {
    for ride in rides {
        let id = ride.id
        let fetchDescriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(fetchDescriptor).first {
            updateSDRide(existing, with: ride)
        } else {
            // ... insert new
        }
    }
    // ... delete stale
}
```

With:
```swift
private func syncRides(_ rides: [Ride], in context: ModelContext) {
    guard !rides.isEmpty else { return }

    // Single batch fetch: get all existing SDRides
    let serverIds = Set(rides.map { $0.id })
    let allLocalDescriptor = FetchDescriptor<SDRide>()
    let allLocal = (try? context.fetch(allLocalDescriptor)) ?? []
    let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

    // Upsert
    for ride in rides {
        if let existing = existingById[ride.id] {
            updateSDRide(existing, with: ride)
        } else {
            let sdRide = SDRide(
                id: ride.id,
                // ... same fields as current code
            )
            context.insert(sdRide)
        }
    }

    // Delete stale (already have allLocal)
    for local in allLocal where !serverIds.contains(local.id) {
        context.delete(local)
    }
}
```

This replaces N+1 queries with 1 query + dictionary lookup.

**Step 3: Apply same pattern to syncFavors**

Read `syncFavors()` — it follows the identical per-item pattern. Apply the same batch-fetch refactor.

**Step 4: Apply same pattern to syncNotifications**

Read `syncNotifications()` — same refactor.

**Step 5: Run tests**

**Step 6: Commit**

```
perf: batch SwiftData fetches in DashboardSyncEngine sync methods

Replaced N+1 FetchDescriptor queries (one per ride/favor/notification)
with single batch fetch + dictionary lookup. For 50 rides, this
reduces SwiftData queries from 51 to 1.
```

---

### Task 3.2: Coalesce computeFilterBadgeCounts Queries

**Problem:** `RequestFilterManager.computeFilterBadgeCounts()` runs 3 iterations of `RequestFilter.allCases`, each doing a separate SwiftData fetch for rides and favors (6 total queries + 3 map/reduce passes).

**Files:**
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift`

**Step 1: Read the current method**

Confirm at lines 158-173 — the 3-iteration loop.

**Step 2: Refactor to single-fetch with in-memory filtering**

```swift
func computeFilterBadgeCounts(
    in context: ModelContext,
    requestNotificationSummaries: [String: RequestNotificationSummary]
) -> [RequestFilter: Int] {
    // Single fetch of ALL rides and favors
    let allRides = (try? context.fetch(FetchDescriptor<SDRide>())) ?? []
    let allFavors = (try? context.fetch(FetchDescriptor<SDFavor>())) ?? []

    var counts: [RequestFilter: Int] = [:]
    for filterCase in RequestFilter.allCases {
        // Filter in memory instead of re-querying SwiftData
        let filteredRides = applyFilter(filterCase, to: allRides)
        let filteredFavors = applyFilter(filterCase, to: allFavors)
        let requests = getFilteredRequests(rides: filteredRides, favors: filteredFavors, filter: filterCase)
        let unreadTotal = requests.reduce(0) { total, request in
            total + (requestNotificationSummaries[request.notificationKey]?.unreadCount ?? 0)
        }
        counts[filterCase] = unreadTotal
    }
    return counts
}
```

The key change: fetch once, filter in memory 3 times. In-memory filtering is orders of magnitude faster than 6 separate SwiftData queries.

**Step 3: Extract applyFilter helper**

Create a private `applyFilter(_ filter: RequestFilter, to rides: [SDRide]) -> [SDRide]` that applies the same predicate logic currently in `fetchFilteredRides`.

**Step 4: Run tests and commit**

```
perf: coalesce computeFilterBadgeCounts from 6 queries to 2

Fetch all rides and favors once, then filter in memory per filter case.
Reduces SwiftData queries from 6 to 2 and eliminates redundant
predicate construction.
```

---

## Tier 4 — Reduce MainActor Contention (Higher Risk, Transformative Impact)

These changes reduce the amount of work that runs on the MainActor by moving decode and sync work to background contexts. This tier requires more careful testing.

---

### Task 4.1: Move JSON Decoding Off MainActor in RideService

**Problem:** `RideService.fetchRides()` decodes the full JSON response (potentially 50+ rides) on MainActor because it's awaited from @MainActor ViewModels.

**Strategy:** Make decode functions `nonisolated` so they run on the cooperative thread pool, not the MainActor.

**Files:**
- Modify: `NaarsCars/Core/Services/RideService.swift`

**Step 1: Read fetchRides()**

Locate the decode call: `try createDecoder().decode([Ride].self, from: response.data)`

**Step 2: Extract a nonisolated decode function**

```swift
// This runs on the cooperative thread pool, NOT MainActor
private nonisolated func decodeRides(from data: Data) throws -> [Ride] {
    let decoder = createDecoder()
    return try decoder.decode([Ride].self, from: data)
}
```

Update `fetchRides()` to call:
```swift
let response = try await supabase.from("rides").select(...).execute()
let rides = try decodeRides(from: response.data)  // Off MainActor
// ... enrichment continues on calling actor
```

Note: `RideService` is NOT `@MainActor`, so this should already work. But verify that `createDecoder()` doesn't access any MainActor-isolated state. If it does, make the decoder creation nonisolated too.

**Step 3: Apply same pattern to other decode hotspots**

- `MessageService.fetchMessages()` — same pattern
- `NotificationService.fetchNotifications()` — same pattern

**Step 4: Run tests and commit**

```
perf: move JSON decoding to nonisolated functions in service layer

Decode operations for rides, messages, and notifications now run
on the cooperative thread pool instead of inheriting the caller's
MainActor isolation.
```

---

### Task 4.2: Introduce BackgroundModelActor for DashboardSyncEngine

**Problem:** All SwiftData writes happen on MainActor because ModelContext is MainActor-isolated. This blocks the UI during sync.

**Strategy:** Create a `@ModelActor` that owns its own background ModelContext. The sync engines write to this context; `@Query` in views automatically picks up changes.

**This is the highest-risk, highest-reward change. It should be attempted only after Tiers 0-3 are verified.**

**Files:**
- Create: `NaarsCars/Core/Storage/BackgroundSyncActor.swift`
- Modify: `NaarsCars/Core/Storage/DashboardSyncEngine.swift`
- Modify: `NaarsCars/App/NaarsCarsApp.swift` (pass ModelContainer to actor)

**Step 1: Create BackgroundSyncActor**

```swift
import SwiftData

@ModelActor
actor BackgroundSyncActor {

    func syncRides(_ rides: [Ride]) throws {
        guard !rides.isEmpty else { return }

        let allLocal = try modelContext.fetch(FetchDescriptor<SDRide>())
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        let serverIds = Set(rides.map { $0.id })

        for ride in rides {
            if let existing = existingById[ride.id] {
                // ... update existing
            } else {
                let sdRide = SDRide(/* ... */)
                modelContext.insert(sdRide)
            }
        }

        for local in allLocal where !serverIds.contains(local.id) {
            modelContext.delete(local)
        }

        try modelContext.save()
    }

    func syncFavors(_ favors: [Favor]) throws {
        // Same pattern
    }

    func syncNotifications(_ notifications: [AppNotification]) throws {
        // Same pattern
    }
}
```

**Step 2: Update DashboardSyncEngine to use BackgroundSyncActor**

```swift
@MainActor
final class DashboardSyncEngine: SyncEngineProtocol {
    private var backgroundActor: BackgroundSyncActor?

    func setup(modelContainer: ModelContainer) {
        self.backgroundActor = BackgroundSyncActor(modelContainer: modelContainer)
    }

    private func performRidesSync() async {
        let rides = try await rideService.fetchRides(...)
        try await backgroundActor?.syncRides(rides)
        // @Query in views auto-updates — no notification needed for data
        // But still post notification for badge/summary refresh:
        NotificationCenter.default.post(name: .ridesDidSync, object: nil)
    }
}
```

**Step 3: Update SyncEngineOrchestrator to pass ModelContainer instead of ModelContext**

Change `setup(modelContext:)` to `setup(modelContainer:)` so engines can create their own contexts.

**Step 4: Verify @Query auto-updates**

SwiftData's `@Query` property wrapper in views observes the ModelContainer's persistent store, not a specific ModelContext. Writes from BackgroundSyncActor should be visible to views automatically. Verify this works by:
1. Writing a ride from BackgroundSyncActor
2. Confirming RequestsDashboardView's `@Query` reflects the change

**Step 5: Extensive testing**

This change affects the core data pipeline. Test:
- App launch → sync → data appears in views
- Realtime update → sync → data updates in views
- Pull-to-refresh → sync → data refreshes
- Sign out → teardown → no crashes
- Background → foreground → reconnect → sync works

**Step 6: Commit**

```
perf: introduce BackgroundSyncActor for off-MainActor SwiftData writes

DashboardSyncEngine now writes to SwiftData via a @ModelActor on a
background thread. View @Query properties auto-update via SwiftData's
persistent store observation. Eliminates MainActor blocking during
sync operations.
```

---

### Task 4.3: Move MessagingSyncEngine to BackgroundSyncActor

**Same pattern as 4.2** but for the messaging sync engine. Higher complexity because of the per-message upsert logic and Combine publishers.

**Files:**
- Modify: `NaarsCars/Core/Storage/BackgroundSyncActor.swift` (add message sync methods)
- Modify: `NaarsCars/Core/Storage/MessagingSyncEngine.swift`
- Modify: `NaarsCars/Core/Storage/MessagingRepository.swift`

**Key difference:** MessagingRepository uses Combine publishers (CurrentValueSubject) to push updates to ViewModels. With a background context, the repository can still bridge updates to the main actor via:
```swift
// In BackgroundSyncActor:
func upsertMessage(_ message: Message) throws -> UpsertResult {
    // ... SwiftData work on background ...
    return result
}

// In MessagingSyncEngine (still @MainActor):
let result = try await backgroundActor.upsertMessage(message)
switch result {
case .contentChanged, .inserted:
    // Refresh publishers on MainActor (lightweight — just reads from @Query cache)
    repository.refreshPublishers(for: message.conversationId)
case .metadataOnly:
    repository.emitMetadataUpdate(message)
case .noChange:
    break
}
```

**This task is the most complex in the plan.** It requires careful handling of the publisher bridge and should be tested thoroughly with realtime message delivery.

**Commit:**
```
perf: move MessagingSyncEngine writes to BackgroundSyncActor
```

---

## Tier 5 — Reduce App Foreground Storm (Low-Medium Risk, Medium Impact)

These changes reduce the burst of work that happens when the app returns from background.

---

### Task 5.1: Stagger Realtime Reconnection

**Problem:** When app foregrounds, RealtimeManager reconnects ALL channels simultaneously. Each reconnection may deliver buffered events, triggering parallel sync chains.

**Files:**
- Modify: `NaarsCars/Core/Services/RealtimeManager.swift`

**Step 1: Read the foreground handler**

Locate the `willEnterForegroundNotification` observer and the resubscribe logic.

**Step 2: Add prioritized, staggered reconnection**

```swift
private func restoreSubscriptions() async {
    // Priority 1: User-facing channels (messages, typing)
    await resubscribe(channelsMatching: ["messages:", "typing:"])

    // Yield to let UI settle
    try? await Task.sleep(for: .milliseconds(200))

    // Priority 2: Dashboard channels
    await resubscribe(channelsMatching: ["rides:sync", "favors:sync"])

    try? await Task.sleep(for: .milliseconds(200))

    // Priority 3: Everything else
    await resubscribe(channelsMatching: nil)  // remaining channels
}
```

**Step 3: Run tests and commit**

```
perf: stagger realtime channel reconnection on app foreground

Reconnects user-facing channels (messages) first, then dashboard
channels, then remaining. Prevents all channels from reconnecting
simultaneously and flooding the MainActor with sync events.
```

---

### Task 5.2: Skip Badge Refresh If Recently Refreshed

**Problem:** `didBecomeActiveNotification` always triggers `refreshAllBadges()`, even if badges were refreshed 2 seconds ago (e.g., from a push notification tap).

**Files:**
- Modify: `NaarsCars/Core/Services/BadgeCountManager.swift`

**Step 1: Add a last-refresh timestamp check**

```swift
private var lastBadgeRefresh: Date = .distantPast

func refreshAllBadges(reason: String) async {
    // Skip if refreshed within badgeRefreshMinInterval (2 seconds)
    guard Date().timeIntervalSince(lastBadgeRefresh) >= Constants.Timing.badgeRefreshMinInterval else {
        AppLogger.debug("badges", "Skipping badge refresh (\(reason)), refreshed \(Date().timeIntervalSince(lastBadgeRefresh))s ago")
        return
    }
    lastBadgeRefresh = Date()
    // ... rest of method
}
```

Check if this guard already exists — the Constants file has `badgeRefreshMinInterval: 2.0`. If it does, verify it's working correctly.

**Step 2: Commit**

```
perf: skip badge refresh if called within 2s of last refresh
```

---

## Verification & Monitoring

After completing each tier, perform these checks:

### Smoke Test Checklist

1. **Cold launch** → first tab renders within 1 second
2. **Tap ride card** → detail view appears within 300ms (no visible stall)
3. **Switch tabs** → tab content visible immediately (no flash)
4. **Receive message** (from another device) → toast appears, no hitch in current view
5. **Pull to refresh** on requests dashboard → spinner dismisses cleanly
6. **Background → foreground** → no frozen frame on return
7. **Open notification sheet** → grouped list appears without delay

### Instruments Profiling (Optional but Recommended)

After Tier 2:
- Time Profiler: verify MainActor time per render is <16ms
- SwiftUI Instruments: verify render counts match expectations

After Tier 4:
- System Trace: verify SwiftData writes no longer appear on MainActor

---

## Summary

| Tier | Tasks | Risk | Render Reduction | Files Changed |
|------|-------|------|-----------------|---------------|
| **0** | 0.1, 0.2 | Zero | ~8x fewer badge renders | 1-2 files + call sites |
| **1** | 1.1-1.4 | Low | ~3x fewer cascading renders per feature | ~12 files |
| **2** | 2.1-2.4 | Low-Med | Eliminates O(n) per-render work | ~8 files |
| **3** | 3.1-3.2 | Medium | Eliminates N+1 SwiftData queries | 2 files |
| **4** | 4.1-4.3 | High | Moves sync off MainActor entirely | 5+ files |
| **5** | 5.1-5.2 | Low-Med | Reduces foreground storm | 2 files |

**Recommended execution order:** Tier 0 → Tier 1 → Tier 2 → Tier 3 → (verify + ship) → Tier 4 → Tier 5

Tiers 0-3 are safe to ship together as one release. Tier 4 is a separate release with more testing. Tier 5 can ship with either.
