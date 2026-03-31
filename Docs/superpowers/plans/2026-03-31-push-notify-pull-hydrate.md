# Push-Notify, Pull-Hydrate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace always-on WebSocket subscriptions with a push-notify, pull-hydrate architecture using a centralized RefreshCoordinator, reducing WAL polling by ~70-80% and connection usage from 7-8 per user to 0-3.

**Architecture:** Centralized `RefreshCoordinator` owns all refresh decisions via a freshness state machine. SyncEngines become pure fetch-and-store with two tiers: targeted (single entity by ID) and full reconciliation. SwiftData writes use compare-before-write to prevent @Query thrash. WebSockets are scoped to the active conversation with a 5-second grace period and subscribe-then-fetch for message consistency.

**Tech Stack:** Swift 5.9+, iOS 17+, SwiftData, Supabase (REST + Realtime), APNs via Supabase Edge Functions

**Spec:** `Docs/superpowers/specs/2026-03-30-push-notify-pull-hydrate-design.md`

---

## Phase 1: Foundation (RefreshCoordinator + Change Detection)

These tasks build the new infrastructure that everything else depends on. No existing behavior is changed yet.

### Task 1: RefreshMetrics and Result Types

**Files:**
- Create: `NaarsCars/NaarsCars/Core/Models/RefreshMetrics.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/RefreshMetricsTests.swift`

- [ ] **Step 1: Create RefreshMetrics, RefreshResult, SkipReason types**

```swift
//
//  RefreshMetrics.swift
//  NaarsCars
//

import Foundation

/// Metrics collected during a refresh operation.
struct RefreshMetrics: Equatable {
    let recordsEvaluated: Int
    let recordsMutated: Int
    let recordsInserted: Int
    let recordsDeleted: Int
    let savedToStore: Bool
    let durationMs: Int

    static let empty = RefreshMetrics(
        recordsEvaluated: 0, recordsMutated: 0, recordsInserted: 0,
        recordsDeleted: 0, savedToStore: false, durationMs: 0
    )

    static let badgeOnly = RefreshMetrics(
        recordsEvaluated: 0, recordsMutated: 0, recordsInserted: 0,
        recordsDeleted: 0, savedToStore: false, durationMs: 0
    )
}

/// Result of a refresh operation, for observability.
enum RefreshResult {
    case completed(RefreshMetrics)
    case skipped(SkipReason)
    case joined(inFlightTrigger: String)
    case failed(Error, partial: RefreshMetrics?)
}

/// Reason a refresh was skipped.
enum SkipReason: String {
    case fresh
    case backoff
    case guestMode
    case domainNotStarted
}

/// Refresh domain — defined here so NotificationType can reference it before RefreshCoordinator exists.
/// RefreshCoordinator.Domain is a typealias to this.
enum RefreshDomain: String, CaseIterable, Hashable {
    case dashboard      // rides + favors + notifications
    case townHall       // posts + comments
    case conversations  // conversation list metadata
    case badges         // badge counts (not in SwiftData)
}

/// Diagnostic snapshot for a single domain.
struct DomainSnapshot {
    let domain: RefreshDomain
    let stateDescription: String
    let lastSync: Date?
    let hasLocalData: Bool
    let isInFlight: Bool
    let lastTrigger: String?
    let lastResultDescription: String?
}

/// Full diagnostic snapshot of the refresh system.
struct RefreshDiagnostics {
    let timestamp: Date
    let domains: [DomainSnapshot]
    let activeConversation: UUID?
    let visibleDomain: RefreshCoordinator.Domain?
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Models/RefreshMetrics.swift
git commit -m "feat: add RefreshMetrics, RefreshResult, and diagnostic types"
```

---

### Task 2: NotificationType Domain Mapping

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Models/AppNotification.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/NotificationTypeDomainMappingTests.swift`

- [ ] **Step 1: Write test for domain mapping coverage**

```swift
//
//  NotificationTypeDomainMappingTests.swift
//  NaarsCars
//

import XCTest
@testable import NaarsCars

final class NotificationTypeDomainMappingTests: XCTestCase {

    func testEveryNotificationTypeHasAffectedDomains() {
        // Ensures the switch is exhaustive and no type returns an unexpected empty set
        // (except .other which is explicitly empty)
        for type in NotificationType.allCases {
            let domains = type.affectedDomains
            if type == .other {
                XCTAssertTrue(domains.isEmpty, "\(type) should have no affected domains")
            }
            // All types should be handled — this test ensures the switch compiles exhaustively
        }
    }

    func testMessageTypesMapToConversations() {
        XCTAssertEqual(NotificationType.message.affectedDomains, [.conversations])
        XCTAssertEqual(NotificationType.addedToConversation.affectedDomains, [.conversations])
    }

    func testRideTypesMapToDashboard() {
        let rideTypes: [NotificationType] = [.newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted]
        for type in rideTypes {
            XCTAssertEqual(type.affectedDomains, [.dashboard], "\(type) should map to dashboard")
        }
    }

    func testFavorTypesMapToDashboard() {
        let favorTypes: [NotificationType] = [.newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted]
        for type in favorTypes {
            XCTAssertEqual(type.affectedDomains, [.dashboard], "\(type) should map to dashboard")
        }
    }

    func testTownHallTypesMapToTownHall() {
        let thTypes: [NotificationType] = [.townHallPost, .townHallComment, .townHallReaction, .announcement, .adminAnnouncement, .broadcast]
        for type in thTypes {
            XCTAssertEqual(type.affectedDomains, [.townHall], "\(type) should map to townHall")
        }
    }

    func testEntityIdKeyPresent() {
        XCTAssertEqual(NotificationType.rideClaimed.entityIdKey, "ride_id")
        XCTAssertEqual(NotificationType.favorUpdate.entityIdKey, "favor_id")
        XCTAssertEqual(NotificationType.townHallPost.entityIdKey, "post_id")
        XCTAssertEqual(NotificationType.message.entityIdKey, "conversation_id")
        XCTAssertNil(NotificationType.completionReminder.entityIdKey)
        XCTAssertNil(NotificationType.other.entityIdKey)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (properties don't exist yet)

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/NotificationTypeDomainMappingTests 2>&1 | tail -10`
Expected: Compilation failure — `affectedDomains` and `entityIdKey` not defined.

- [ ] **Step 3: Add `affectedDomains` and `entityIdKey` to NotificationType**

Add to `AppNotification.swift` after the existing `icon` computed property. The `RefreshCoordinator.Domain` reference requires a forward declaration — use a nested enum or reference the coordinator type (it will be created in Task 3). For now, define the domain enum directly in this extension since the coordinator doesn't exist yet:

```swift
// MARK: - Refresh Domain Mapping

extension NotificationType {
    /// Domains that should be refreshed when this notification type is received as a push.
    var affectedDomains: Set<RefreshDomain> {
        switch self {
        case .message, .addedToConversation:
            return [.conversations]
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
             .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted,
             .completionReminder,
             .qaActivity, .qaQuestion, .qaAnswer,
             .review, .reviewReceived, .reviewReminder, .reviewRequest,
             .contentReported,
             .pendingApproval, .userApproved, .userRejected,
             .accountRestricted:
            return [.dashboard]
        case .townHallPost, .townHallComment, .townHallReaction,
             .announcement, .adminAnnouncement, .broadcast:
            return [.townHall]
        case .other:
            return []
        }
    }

    /// Key in push userInfo that contains the affected entity ID, if available.
    var entityIdKey: String? {
        switch self {
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted:
            return "ride_id"
        case .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted:
            return "favor_id"
        case .townHallPost, .townHallComment, .townHallReaction:
            return "post_id"
        case .message, .addedToConversation:
            return "conversation_id"
        default:
            return nil
        }
    }
}
```

NOTE: `RefreshDomain` was defined in Task 1 (`RefreshMetrics.swift`), so this compiles immediately. `RefreshCoordinator.Domain` will be a typealias to `RefreshDomain` when the coordinator is created in Task 3.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/NotificationTypeDomainMappingTests 2>&1 | tail -10`

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Models/AppNotification.swift NaarsCars/NaarsCarsTests/Core/NotificationTypeDomainMappingTests.swift
git commit -m "feat: add NotificationType.affectedDomains and entityIdKey mapping"
```

---

### Task 3: RefreshCoordinator — Core State Machine

**Files:**
- Create: `NaarsCars/NaarsCars/Core/Services/RefreshCoordinator.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/RefreshCoordinatorTests.swift`

- [ ] **Step 1: Write tests for the state machine transitions**

```swift
//
//  RefreshCoordinatorTests.swift
//  NaarsCars
//

import XCTest
@testable import NaarsCars

@MainActor
final class RefreshCoordinatorTests: XCTestCase {

    func testInitialStateIsUnhydratedWhenNoTimestamp() {
        // Clear any existing timestamp
        UserDefaults.standard.removeObject(forKey: "refresh.lastSync.dashboard")

        let coordinator = RefreshCoordinator()
        let state = coordinator.stateDescription(for: .dashboard)
        XCTAssertTrue(state.contains("unhydrated"))
    }

    func testInvalidateSetsInvalidatedState() {
        let coordinator = RefreshCoordinator()
        // Manually set to hydrated first
        coordinator.markSyncedForTesting(.dashboard)

        coordinator.invalidate([.dashboard])
        let state = coordinator.stateDescription(for: .dashboard)
        XCTAssertTrue(state.contains("invalidated"))
    }

    func testRefreshSkippedWhenFresh() {
        let coordinator = RefreshCoordinator()
        coordinator.markSyncedForTesting(.dashboard)

        let result = coordinator.shouldRefresh(.dashboard)
        XCTAssertFalse(result, "Should not refresh when freshly synced")
    }

    func testRefreshAllowedWhenStale() {
        let coordinator = RefreshCoordinator()
        // Set timestamp to 60 seconds ago (past 30s staleness window)
        coordinator.markSyncedForTesting(.dashboard, at: Date().addingTimeInterval(-60))

        let result = coordinator.shouldRefresh(.dashboard)
        XCTAssertTrue(result, "Should refresh when past staleness window")
    }

    func testResetClearsAllState() {
        let coordinator = RefreshCoordinator()
        coordinator.markSyncedForTesting(.dashboard)
        coordinator.markSyncedForTesting(.townHall)

        coordinator.reset()

        for domain in RefreshCoordinator.Domain.allCases {
            let state = coordinator.stateDescription(for: domain)
            // After reset, state should be nil/uninitialized
            XCTAssertTrue(state.contains("nil") || state.contains("unhydrated"),
                         "Domain \(domain) should be reset")
        }
    }
}
```

- [ ] **Step 2: Implement RefreshCoordinator**

Create `NaarsCars/NaarsCars/Core/Services/RefreshCoordinator.swift`:

```swift
//
//  RefreshCoordinator.swift
//  NaarsCars
//

import Foundation
import SwiftData

/// Centralized refresh orchestration. Single source of truth for data invalidation,
/// staleness tracking, and in-flight deduplication across all data domains.
@MainActor
final class RefreshCoordinator {

    // MARK: - Domain

    typealias Domain = RefreshDomain

    // MARK: - Freshness State

    enum FreshnessState {
        case unhydrated
        case hydrated(lastSync: Date)
        case invalidated(lastSync: Date)
        case refreshing(task: Task<Void, Never>, hasCache: Bool)
        case failed(retryAfter: Date, hasCache: Bool)
    }

    // MARK: - Properties

    static let shared = RefreshCoordinator()

    private var states: [Domain: FreshnessState] = [:]
    private var failureCounts: [Domain: Int] = [:]
    private var lastTriggers: [Domain: String] = [:]
    private var lastResults: [Domain: RefreshResult] = [:]
    private var safetyPollTimer: Timer?

    /// Currently visible domain. Set by MainTabView.onChange(of: selectedTab).
    private(set) var visibleDomain: Domain?

    /// Active conversation excluded from background sync.
    private(set) var activeConversationId: UUID?

    /// Staleness window in seconds. Default 30s.
    let stalenessWindow: TimeInterval = 30.0

    /// Safety poll interval in seconds. Default 5 minutes.
    let safetyPollInterval: TimeInterval = 300.0

    // MARK: - Initialization

    func initializeStates(modelContext: ModelContext? = nil) {
        for domain in Domain.allCases {
            states[domain] = determineInitialState(domain, modelContext: modelContext)
        }
    }

    private func determineInitialState(_ domain: Domain, modelContext: ModelContext?) -> FreshnessState {
        if let timestamp = lastSyncTimestamp(domain) {
            return .hydrated(lastSync: timestamp)
        }
        // Fallback: check if SwiftData has residual data (crash recovery)
        if let ctx = modelContext, swiftDataHasRecords(domain, context: ctx) {
            return .hydrated(lastSync: .distantPast)
        }
        return .unhydrated
    }

    // MARK: - Public API

    func setVisibleDomain(_ domain: Domain?) {
        let previous = visibleDomain
        visibleDomain = domain
        if let domain, domain != previous {
            refreshIfNeeded(domain, trigger: "tabAppear")
        }
    }

    func setActiveConversation(_ id: UUID?) {
        activeConversationId = id
    }

    func invalidate(_ domains: Set<Domain>) {
        for domain in domains {
            invalidateDomain(domain)
        }
    }

    func handleAppForegrounded() {
        invalidateDomain(.badges)
        if let visible = visibleDomain {
            refreshIfNeeded(visible, trigger: "appForeground")
        }
    }

    func startSafetyPoll() {
        safetyPollTimer?.invalidate()
        safetyPollTimer = Timer.scheduledTimer(
            withTimeInterval: safetyPollInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.safetyPollFired()
            }
        }
    }

    func stopSafetyPoll() {
        safetyPollTimer?.invalidate()
        safetyPollTimer = nil
    }

    func reset() {
        // Cancel all in-flight tasks
        for (_, state) in states {
            if case .refreshing(let task, _) = state {
                task.cancel()
            }
        }
        states.removeAll()
        failureCounts.removeAll()
        lastTriggers.removeAll()
        lastResults.removeAll()
        stopSafetyPoll()
        visibleDomain = nil
        activeConversationId = nil
        clearAllSyncTimestamps()
    }

    // MARK: - Refresh Decision Logic

    func shouldRefresh(_ domain: Domain) -> Bool {
        guard let state = states[domain] else { return true }
        switch state {
        case .unhydrated:
            return true
        case .hydrated(let lastSync):
            return Date().timeIntervalSince(lastSync) > stalenessWindow
        case .invalidated:
            return true
        case .refreshing:
            return false // join in-flight
        case .failed(let retryAfter, _):
            return Date() >= retryAfter
        }
    }

    // MARK: - Internal

    private func refreshIfNeeded(_ domain: Domain, trigger: String) {
        guard shouldRefresh(domain) else {
            logDecision(domain: domain, trigger: trigger, decision: "skipped:fresh")
            return
        }

        guard !isInFlight(domain) else {
            logDecision(domain: domain, trigger: trigger, decision: "joined")
            return
        }

        lastTriggers[domain] = trigger
        // Actual refresh execution will be wired in later tasks
        logDecision(domain: domain, trigger: trigger, decision: "started")
    }

    private func invalidateDomain(_ domain: Domain) {
        guard !isInFlight(domain) else {
            logDecision(domain: domain, trigger: "invalidation", decision: "skipped:inFlight")
            return
        }
        switch states[domain] {
        case .hydrated(let lastSync):
            states[domain] = .invalidated(lastSync: lastSync)
        case .failed(_, let hasCache) where hasCache:
            states[domain] = .invalidated(lastSync: lastSyncTimestamp(domain) ?? .distantPast)
        default:
            break
        }
    }

    private func isInFlight(_ domain: Domain) -> Bool {
        if case .refreshing = states[domain] { return true }
        return false
    }

    private func safetyPollFired() {
        for domain in Domain.allCases {
            refreshIfNeeded(domain, trigger: "safetyPoll")
        }
    }

    // MARK: - State Completion (called by engines after sync)

    func markSyncCompleted(_ domain: Domain, metrics: RefreshMetrics) {
        states[domain] = .hydrated(lastSync: Date())
        failureCounts[domain] = 0
        lastResults[domain] = .completed(metrics)
        markSyncTimestamp(domain)
        logDecision(domain: domain, trigger: lastTriggers[domain] ?? "unknown",
                    decision: "completed(\(metrics.recordsMutated) mutated, saved=\(metrics.savedToStore))")
    }

    func markSyncFailed(_ domain: Domain, error: Error, partial: RefreshMetrics?) {
        let count = (failureCounts[domain] ?? 0) + 1
        failureCounts[domain] = count
        let backoff = min(pow(2.0, Double(count - 1)) * 5.0, 120.0)
        let hasCache = lastSyncTimestamp(domain) != nil
        states[domain] = .failed(retryAfter: Date().addingTimeInterval(backoff), hasCache: hasCache)
        lastResults[domain] = .failed(error, partial: partial)
    }

    // MARK: - Timestamp Persistence (UserDefaults — advisory)

    private func lastSyncTimestamp(_ domain: Domain) -> Date? {
        UserDefaults.standard.object(forKey: "refresh.lastSync.\(domain.rawValue)") as? Date
    }

    private func markSyncTimestamp(_ domain: Domain) {
        UserDefaults.standard.set(Date(), forKey: "refresh.lastSync.\(domain.rawValue)")
    }

    private func clearAllSyncTimestamps() {
        for domain in Domain.allCases {
            UserDefaults.standard.removeObject(forKey: "refresh.lastSync.\(domain.rawValue)")
        }
    }

    // MARK: - SwiftData Hydration Check

    private func swiftDataHasRecords(_ domain: Domain, context: ModelContext) -> Bool {
        switch domain {
        case .dashboard:
            return (try? context.fetchCount(FetchDescriptor<SDRide>())) ?? 0 > 0
        case .townHall:
            return (try? context.fetchCount(FetchDescriptor<SDTownHallPost>())) ?? 0 > 0
        case .conversations:
            return (try? context.fetchCount(FetchDescriptor<SDConversation>())) ?? 0 > 0
        case .badges:
            return false
        }
    }

    // MARK: - Observability

    func stateDescription(for domain: Domain) -> String {
        guard let state = states[domain] else { return "nil" }
        switch state {
        case .unhydrated: return "unhydrated"
        case .hydrated(let d): return "hydrated(\(Int(Date().timeIntervalSince(d)))s ago)"
        case .invalidated(let d): return "invalidated(synced \(Int(Date().timeIntervalSince(d)))s ago)"
        case .refreshing(_, let c): return "refreshing(hasCache=\(c))"
        case .failed(let r, let c): return "failed(retryIn=\(Int(r.timeIntervalSinceNow))s, hasCache=\(c))"
        }
    }

    func diagnosticSnapshot() -> RefreshDiagnostics {
        RefreshDiagnostics(
            timestamp: Date(),
            domains: Domain.allCases.map { domain in
                DomainSnapshot(
                    domain: domain,
                    stateDescription: stateDescription(for: domain),
                    lastSync: lastSyncTimestamp(domain),
                    hasLocalData: false, // Would need ModelContext to check
                    isInFlight: isInFlight(domain),
                    lastTrigger: lastTriggers[domain],
                    lastResultDescription: lastResults[domain].map { "\($0)" }
                )
            },
            activeConversation: activeConversationId,
            visibleDomain: visibleDomain
        )
    }

    private func logDecision(domain: Domain, trigger: String, decision: String) {
        AppLogger.info("refresh", "[\(domain.rawValue)] \(decision) | trigger=\(trigger) | state=\(stateDescription(for: domain))")
    }

    // MARK: - Testing Helpers

    #if DEBUG
    func markSyncedForTesting(_ domain: Domain, at date: Date = Date()) {
        states[domain] = .hydrated(lastSync: date)
        UserDefaults.standard.set(date, forKey: "refresh.lastSync.\(domain.rawValue)")
    }
    #endif
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/RefreshCoordinatorTests 2>&1 | tail -10`

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Services/RefreshCoordinator.swift NaarsCars/NaarsCarsTests/Core/RefreshCoordinatorTests.swift
git commit -m "feat: add RefreshCoordinator with freshness state machine"
```

---

### Task 4: BackgroundSyncActor — Change Detection

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Storage/BackgroundSyncActor.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/ChangeDetectionTests.swift`

- [ ] **Step 1: Write test for change detection on rides**

```swift
//
//  ChangeDetectionTests.swift
//  NaarsCars
//

import XCTest
import SwiftData
@testable import NaarsCars

final class ChangeDetectionTests: XCTestCase {

    func testUpdateSDRideIfChanged_noChange_returnsFalse() {
        // Create an SDRide and a Ride with identical values
        // Call updateSDRideIfChanged — expect false
        // This verifies that identical data does not trigger a mutation
    }

    func testUpdateSDRideIfChanged_statusChanged_returnsTrue() {
        // Create an SDRide with status "open"
        // Create a Ride with status "claimed"
        // Call updateSDRideIfChanged — expect true
    }

    func testSyncAllWithChangeDetection_noChanges_doesNotSave() {
        // Sync identical data twice
        // Second sync should report savedToStore=false
    }
}
```

NOTE: Exact test implementations depend on the existing `Ride` model initializer and `SDRide` constructor. The implementer should follow existing test patterns in `NaarsCarsTests/` for SwiftData model creation.

- [ ] **Step 2: Add `updateSDRideIfChanged`, `updateSDFavorIfChanged` to BackgroundSyncActor**

Add to `BackgroundSyncActor.swift`. These are private methods that compare each field before writing:

```swift
/// Returns true if any field was actually modified.
private func updateSDRideIfChanged(_ existing: SDRide, with ride: Ride) -> Bool {
    var changed = false
    if existing.status != ride.status.rawValue { existing.status = ride.status.rawValue; changed = true }
    if existing.seats != ride.seats { existing.seats = ride.seats; changed = true }
    if existing.pickup != ride.pickup { existing.pickup = ride.pickup; changed = true }
    if existing.destination != ride.destination { existing.destination = ride.destination; changed = true }
    if existing.notes != ride.notes { existing.notes = ride.notes; changed = true }
    if existing.gift != ride.gift { existing.gift = ride.gift; changed = true }
    if existing.claimedBy != ride.claimedBy { existing.claimedBy = ride.claimedBy; changed = true }
    // ... continue for ALL fields on SDRide that come from the Ride domain model
    // Preserve joined fields (posterName, posterAvatarUrl, etc.) that are NOT in the Ride model
    return changed
}
```

Repeat the same pattern for `updateSDFavorIfChanged`, `updateSDNotificationIfChanged`, `updateSDPostIfChanged`, `updateSDCommentIfChanged`.

- [ ] **Step 3: Add `syncAllWithChangeDetection` returning RefreshMetrics**

```swift
func syncAllWithChangeDetection(
    rides: [Ride], favors: [Favor], notifications: [AppNotification],
    excludeMessagesForConversation: UUID? = nil
) throws -> RefreshMetrics {
    let start = Date()
    var evaluated = 0, mutated = 0, inserted = 0, deleted = 0

    // Rides
    let allLocalRides = (try? modelContext.fetch(FetchDescriptor<SDRide>())) ?? []
    let existingRidesById = Dictionary(uniqueKeysWithValues: allLocalRides.map { ($0.id, $0) })
    let serverRideIds = Set(rides.map { $0.id })
    evaluated += rides.count

    for ride in rides {
        if let existing = existingRidesById[ride.id] {
            if updateSDRideIfChanged(existing, with: ride) { mutated += 1 }
        } else {
            modelContext.insert(/* new SDRide from ride */)
            inserted += 1
        }
    }
    for local in allLocalRides where !serverRideIds.contains(local.id) {
        modelContext.delete(local)
        deleted += 1
    }

    // Repeat for favors, notifications...

    let didMutate = mutated > 0 || inserted > 0 || deleted > 0
    if didMutate { try modelContext.save() }

    return RefreshMetrics(
        recordsEvaluated: evaluated, recordsMutated: mutated,
        recordsInserted: inserted, recordsDeleted: deleted,
        savedToStore: didMutate,
        durationMs: Int(Date().timeIntervalSince(start) * 1000)
    )
}
```

- [ ] **Step 4: Add targeted upsert methods returning RefreshMetrics**

```swift
func upsertRideWithChangeDetection(_ ride: Ride) throws -> RefreshMetrics {
    let start = Date()
    let descriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == ride.id })
    let existing = try? modelContext.fetch(descriptor).first

    var mutated = 0, inserted = 0
    if let existing {
        if updateSDRideIfChanged(existing, with: ride) { mutated = 1 }
    } else {
        modelContext.insert(/* new SDRide */)
        inserted = 1
    }

    let didMutate = mutated > 0 || inserted > 0
    if didMutate { try modelContext.save() }

    return RefreshMetrics(
        recordsEvaluated: 1, recordsMutated: mutated,
        recordsInserted: inserted, recordsDeleted: 0,
        savedToStore: didMutate,
        durationMs: Int(Date().timeIntervalSince(start) * 1000)
    )
}
```

Repeat for `upsertFavorWithChangeDetection`, `upsertPostWithChangeDetection`, `upsertCommentWithChangeDetection`.

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/ChangeDetectionTests 2>&1 | tail -10`

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Storage/BackgroundSyncActor.swift NaarsCars/NaarsCarsTests/Core/ChangeDetectionTests.swift
git commit -m "feat: add change detection to BackgroundSyncActor, prevent no-op SwiftData saves"
```

---

### Task 5: Add TownHall Sync to BackgroundSyncActor

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Storage/BackgroundSyncActor.swift`

- [ ] **Step 1: Add TownHall batch sync methods**

Add `syncPostsWithChangeDetection(_:)`, `syncCommentsWithChangeDetection(_:forPostId:)`, `upsertPostWithChangeDetection(_:)`, `upsertCommentWithChangeDetection(_:)` following the same pattern as rides/favors. These are new — TownHall previously wrote through `TownHallRepository` on MainActor.

- [ ] **Step 2: Verify compile**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Storage/BackgroundSyncActor.swift
git commit -m "feat: add TownHall sync methods to BackgroundSyncActor"
```

---

### Task 6: Add Constants for New Timing Values

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Utilities/Constants.swift`

- [ ] **Step 1: Add new timing constants**

Add to the `Timing` enum:

```swift
/// Staleness window for pull-on-appear refresh (30s)
static let refreshStalenessWindow: TimeInterval = 30.0
/// Safety poll interval (5 minutes)
static let refreshSafetyPollInterval: TimeInterval = 300.0
/// Badge refresh debounce (5s)
static let badgeRefreshDebounce: TimeInterval = 5.0
/// Conversation WebSocket grace period before teardown (5s)
static let conversationGracePeriod: TimeInterval = 5.0
/// Subscribe-then-fetch confirmation timeout (3s)
static let subscriptionConfirmationTimeout: TimeInterval = 3.0
/// Background push execution budget (8s)
static let backgroundPushBudget: TimeInterval = 8.0
/// Background push deadline timer (25s — leaves 5s margin of 30s iOS limit)
static let backgroundPushDeadline: TimeInterval = 25.0
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Utilities/Constants.swift
git commit -m "feat: add timing constants for push-notify pull-hydrate architecture"
```

---

### Task 6b: SyncEngineProtocol Update

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Storage/SyncEngineProtocol.swift`

- [ ] **Step 1: Update protocol to match new engine contract**

Replace `startSync()`, `pauseSync()`, `resumeSync()` with new methods:

```swift
protocol SyncEngineProtocol {
    func setup(modelContext: ModelContext)
    func setupBackgroundActor(container: ModelContainer)
    func performFullSync() async throws -> RefreshMetrics
    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics
    func teardown()
}
```

Add default no-op implementation for `performTargetedSync` via extension (not all engines support it):

```swift
extension SyncEngineProtocol {
    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics { .empty }
}
```

Keep `startSync()` as a legacy method on engines that need startup logic (e.g., MessagingSyncEngine starting the send worker) but remove it from the protocol.

- [ ] **Step 2: Verify compile**

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Storage/SyncEngineProtocol.swift
git commit -m "refactor: update SyncEngineProtocol for pull-based architecture"
```

---

### Task 6c: Add TownHallService.fetchPost(id:)

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Services/TownHallService.swift` (and its protocol if one exists)

- [ ] **Step 1: Add single-post fetch method**

```swift
func fetchPost(id: UUID) async throws -> TownHallPost {
    let response: TownHallPost = try await supabase.client
        .from("town_hall_posts")
        .select()
        .eq("id", value: id.uuidString)
        .single()
        .execute()
        .value
    return response
}
```

Also add to the service protocol if one exists (check `Core/Protocols/`).

- [ ] **Step 2: Verify compile**

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Services/TownHallService.swift
git commit -m "feat: add TownHallService.fetchPost(id:) for targeted refresh"
```

---

## Phase 2: Engine Refactoring

Remove realtime subscriptions from sync engines. Wire engines to the coordinator. Each engine becomes pull-based.

> **WARNING:** After Phase 2 is complete but before Phase 3, the app will have degraded data freshness — only initial `startSync()` works. Tab switching and push receipt will NOT trigger refreshes until Phase 3 wires the coordinator. Do not test freshness behavior or ship until Phase 3 is complete.

### Task 7: DashboardSyncEngine — Remove Realtime, Add Pull-Based Methods

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Storage/DashboardSyncEngine.swift`

- [ ] **Step 1: Remove realtime subscriptions from startSync()**

Remove all `realtimeManager.subscribe()` calls for rides, favors, and notifications channels. Remove `handleRideUpsert`, `handleRideDelete`, `handleFavorUpsert`, `handleFavorDelete`, `handleNotificationUpsert`, `handleNotificationDelete` handlers. Remove `triggerRidesSync`, `triggerFavorsSync`, `triggerNotificationsSync` debounced methods and their associated `Task` properties.

- [ ] **Step 2: Add `performFullSync()` returning RefreshMetrics**

Replace the existing `syncAll()` internals with the change-detection version:

```swift
func performFullSync() async throws -> RefreshMetrics {
    guard let userId = authService.currentUserId else {
        return .empty
    }
    async let ridesTask = rideService.fetchRides()
    async let favorsTask = favorService.fetchFavors()
    async let notificationsTask = notificationService.fetchNotifications(userId: userId, forceRefresh: true)

    let (rides, favors, notifications) = try await (ridesTask, favorsTask, notificationsTask)

    guard let backgroundActor else { return .empty }
    let metrics = try await backgroundActor.syncAllWithChangeDetection(
        rides: rides, favors: favors, notifications: notifications
    )

    if metrics.savedToStore {
        NotificationCenter.default.post(name: .ridesDidSync, object: nil)
        NotificationCenter.default.post(name: .favorsDidSync, object: nil)
        NotificationCenter.default.post(name: .notificationsDidSync, object: nil)
    }

    return metrics
}
```

- [ ] **Step 3: Add `performTargetedSync(entityId:)` returning RefreshMetrics**

```swift
func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics {
    guard let backgroundActor else { return .empty }
    // Try ride first, then favor — we don't know which entity type from the ID alone
    // The coordinator could pass entity type hint in future; for now try both
    if let ride = try? await rideService.fetchRide(id: entityId) {
        let metrics = try await backgroundActor.upsertRideWithChangeDetection(ride)
        if metrics.savedToStore { NotificationCenter.default.post(name: .ridesDidSync, object: nil) }
        return metrics
    }
    if let favor = try? await favorService.fetchFavor(id: entityId) {
        let metrics = try await backgroundActor.upsertFavorWithChangeDetection(favor)
        if metrics.savedToStore { NotificationCenter.default.post(name: .favorsDidSync, object: nil) }
        return metrics
    }
    return .empty
}
```

NOTE: The implementer should check whether `rideService.fetchRide(id:)` and `favorService.fetchFavor(id:)` exist. If not, they need to be added as single-item fetch methods on the respective services. These are simple Supabase queries: `supabase.from("rides").select().eq("id", value: id).single().execute()`.

- [ ] **Step 4: Update `startSync()` to call performFullSync**

```swift
func startSync() {
    Task {
        do {
            let metrics = try await performFullSync()
            RefreshCoordinator.shared.markSyncCompleted(.dashboard, metrics: metrics)
        } catch {
            RefreshCoordinator.shared.markSyncFailed(.dashboard, error: error, partial: nil)
        }
    }
}
```

- [ ] **Step 5: Simplify `pauseSync()` and `resumeSync()`**

Remove realtime unsubscribe/resubscribe calls. `pauseSync()` cancels in-flight fetch tasks. `resumeSync()` is a no-op (coordinator handles refresh on foreground).

- [ ] **Step 6: Verify compile and run existing tests**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

- [ ] **Step 7: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Storage/DashboardSyncEngine.swift
git commit -m "refactor: DashboardSyncEngine from realtime to pull-based with change detection"
```

---

### Task 8: TownHallSyncEngine — Remove Realtime, Add Pull-Based, Migrate to BackgroundSyncActor

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Storage/TownHallSyncEngine.swift`

- [ ] **Step 1: Remove all realtime subscriptions and handlers**

Remove `subscribe()` calls for posts, comments, votes channels. Remove all `handlePostUpsert`, `handleCommentUpsert`, `handleVoteChange` handlers. Remove `triggerPostsRefresh`, `triggerCommentsRefresh` debounced methods. Remove `TownHallPayloadMapper` private enum.

- [ ] **Step 2: Add BackgroundSyncActor integration**

Add a `backgroundActor: BackgroundSyncActor?` property (matching DashboardSyncEngine pattern). Add `setupBackgroundActor(container:)`.

- [ ] **Step 3: Add `performFullSync()` and `performTargetedSync(entityId:)`**

Follow the same pattern as DashboardSyncEngine. `performFullSync()` fetches all posts and comments via `townHallService`, syncs through `BackgroundSyncActor`, posts `.townHallPostsDidSync` notification only if saved. `performTargetedSync(entityId:)` fetches a single post by ID.

- [ ] **Step 4: Update `startSync()` to use coordinator**

Same pattern as DashboardSyncEngine step 4.

- [ ] **Step 5: Verify compile**

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Storage/TownHallSyncEngine.swift
git commit -m "refactor: TownHallSyncEngine from realtime to pull-based, migrate to BackgroundSyncActor"
```

---

### Task 9: MessagingSyncEngine — Scope to Active Conversation

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Storage/MessagingSyncEngine.swift`

- [ ] **Step 1: Remove global `messages:sync` subscription**

Remove `setupMessagesSubscription()` call from `startSync()`. Keep the method body (it will be repurposed for conversation-scoped subscription).

- [ ] **Step 2: Add conversation-scoped subscription methods**

```swift
private var activeConversationId: UUID?
private var gracePeriodTimer: Timer?

func subscribeToConversation(_ conversationId: UUID) {
    // Cancel grace period if re-entering same conversation
    gracePeriodTimer?.invalidate()
    gracePeriodTimer = nil

    guard activeConversationId != conversationId else { return } // no-op

    if activeConversationId != nil {
        unsubscribeFromActiveConversation()
    }

    activeConversationId = conversationId
    RefreshCoordinator.shared.setActiveConversation(conversationId)

    // Subscribe to messages for this conversation
    Task {
        await realtimeManager.subscribe(
            channelName: "messages:\(conversationId.uuidString)",
            table: "messages",
            filter: "conversation_id=eq.\(conversationId.uuidString)",
            onInsert: { [weak self] event in self?.handleIncomingMessage(event) },
            onUpdate: { [weak self] event in self?.handleIncomingMessage(event) },
            onDelete: { [weak self] event in self?.handleMessageDelete(event) }
        )
        // Reactions subscription (already per-conversation pattern)
        await realtimeManager.subscribe(
            channelName: "reactions:\(conversationId.uuidString)",
            table: "message_reactions",
            filter: "conversation_id=eq.\(conversationId.uuidString)",
            onInsert: { [weak self] event in self?.handleReactionChange(event, type: .insert) },
            onDelete: { [weak self] event in self?.handleReactionChange(event, type: .delete) }
        )

        // Subscribe-then-fetch: REST hydration after subscription confirmation
        await hydrateConversation(conversationId)
    }
}

func beginGracePeriod() {
    gracePeriodTimer?.invalidate()
    gracePeriodTimer = Timer.scheduledTimer(
        withTimeInterval: Constants.Timing.conversationGracePeriod,
        repeats: false
    ) { [weak self] _ in
        Task { @MainActor [weak self] in
            self?.unsubscribeFromActiveConversation()
        }
    }
}

func cancelGracePeriodAndUnsubscribe() {
    gracePeriodTimer?.invalidate()
    gracePeriodTimer = nil
    unsubscribeFromActiveConversation()
}

private func unsubscribeFromActiveConversation() {
    guard let id = activeConversationId else { return }
    Task {
        await realtimeManager.unsubscribe(channelName: "messages:\(id.uuidString)")
        await realtimeManager.unsubscribe(channelName: "reactions:\(id.uuidString)")
    }
    activeConversationId = nil
    RefreshCoordinator.shared.setActiveConversation(nil)
}

private func hydrateConversation(_ conversationId: UUID) async {
    // REST fetch recent messages for this conversation
    // Upsert to SwiftData via repository
    // Dedup by message UUID handles overlap with buffered WebSocket events
}
```

- [ ] **Step 3: Add `refreshConversationList()` method**

```swift
func refreshConversationList() async throws -> RefreshMetrics {
    guard let userId = authService.currentUserId else { return .empty }
    let remoteConversations = try await conversationService.fetchConversations(userId: userId)

    guard let backgroundActor else { return .empty }
    let payloads = remoteConversations.map { ConversationSyncPayload(from: $0, currentUserId: userId) }
    let changedIds = try await backgroundActor.syncConversations(
        payloads, currentUserId: userId,
        excludeMessagesForConversation: RefreshCoordinator.shared.activeConversationId
    )
    repository.refreshPublishersAfterBackgroundSync(changedConversationIds: changedIds)

    return RefreshMetrics(
        recordsEvaluated: remoteConversations.count,
        recordsMutated: changedIds.count,
        recordsInserted: 0, recordsDeleted: 0,
        savedToStore: !changedIds.isEmpty, durationMs: 0
    )
}
```

NOTE: `BackgroundSyncActor.syncConversations` needs the new `excludeMessagesForConversation` parameter added. The implementer should add this parameter with a default of `nil` to maintain backward compatibility.

- [ ] **Step 4: Update teardown**

```swift
func teardown() {
    cancelGracePeriodAndUnsubscribe()
    // existing: stop send worker, clear state
}
```

- [ ] **Step 5: Verify compile**

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Storage/MessagingSyncEngine.swift
git commit -m "refactor: MessagingSyncEngine scoped to active conversation with grace period"
```

---

### Task 10: BadgeCountManager — Remove Polling, Wire to Coordinator

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Services/BadgeCountManager.swift`

- [ ] **Step 1: Remove 30s/90s polling timers**

Remove the `Timer.scheduledTimer` calls for badge polling. Remove the `updatePollingInterval()` method. Remove `realtimeManager.$isConnected` Combine listener. Remove `isRefreshing` and `lastRefreshTime` guards (coordinator handles dedup).

- [ ] **Step 2: Update `refreshAllBadges` to use 5s debounce only**

Keep the existing debounce logic but simplify to a fixed 5s minimum interval (replace `minRefreshInterval` constant reference with `Constants.Timing.badgeRefreshDebounce`).

- [ ] **Step 3: Verify compile and existing badge tests pass**

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Services/BadgeCountManager.swift
git commit -m "refactor: BadgeCountManager remove polling timers, coordinator will drive refresh"
```

---

## Phase 3: Push Handler + Coordinator Wiring

### Task 11: PushNotificationService — Add Push-Received Handler

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Services/PushNotificationService.swift`

- [ ] **Step 1: Add `handlePushReceived(userInfo:)` method**

```swift
/// Called when any push is received (foreground or background).
/// Routes to RefreshCoordinator based on notification type.
func handlePushReceived(userInfo: [AnyHashable: Any]) {
    guard let typeString = userInfo["type"] as? String,
          let type = NotificationType(rawValue: typeString) else {
        // Unknown type — just refresh badges
        RefreshCoordinator.shared.invalidate([.badges])
        return
    }

    let domains = type.affectedDomains
    let entityId: UUID? = {
        guard let key = type.entityIdKey,
              let idString = userInfo[key] as? String else { return nil }
        return UUID(uuidString: idString)
    }()

    // Targeted refresh if entity ID available, else invalidate
    for domain in domains {
        if let entityId {
            Task {
                await performTargetedRefreshViaCoordinator(domain: domain, entityId: entityId)
            }
        } else {
            RefreshCoordinator.shared.invalidate([domain])
        }
    }

    // Badges always refresh
    RefreshCoordinator.shared.invalidate([.badges])
    Task {
        await BadgeCountManager.shared.refreshAllBadges(reason: "push:\(typeString)")
    }
}

private func performTargetedRefreshViaCoordinator(domain: RefreshCoordinator.Domain, entityId: UUID) async {
    do {
        let metrics: RefreshMetrics
        switch domain {
        case .dashboard:
            metrics = try await DashboardSyncEngine.shared.performTargetedSync(entityId: entityId)
        case .townHall:
            metrics = try await TownHallSyncEngine.shared.performTargetedSync(entityId: entityId)
        case .conversations:
            metrics = try await MessagingSyncEngine.shared.refreshConversationList()
        case .badges:
            return // handled separately
        }
        RefreshCoordinator.shared.markSyncCompleted(domain, metrics: metrics)
    } catch {
        RefreshCoordinator.shared.markSyncFailed(domain, error: error, partial: nil)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Services/PushNotificationService.swift
git commit -m "feat: add push-received handler routing to RefreshCoordinator"
```

---

### Task 12: AppDelegate — Wire Push Handlers + Background Handler

**Files:**
- Modify: `NaarsCars/NaarsCars/App/AppDelegate.swift`

- [ ] **Step 1: Add `handlePushReceived` call to foreground push handler**

In the existing `userNotificationCenter(_:willPresent:withCompletionHandler:)`, add before the completion handler:

```swift
PushNotificationService.shared.handlePushReceived(userInfo: userInfo)
```

- [ ] **Step 2: Add `didReceiveRemoteNotification:fetchCompletionHandler:`**

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    // Deadline timer — guarantees completion handler is always called
    let deadline = Task {
        try? await Task.sleep(for: .seconds(Constants.Timing.backgroundPushDeadline))
        completionHandler(.failed)
    }

    Task { @MainActor in
        guard let typeString = userInfo["type"] as? String,
              let type = NotificationType(rawValue: typeString) else {
            deadline.cancel()
            completionHandler(.noData)
            return
        }

        let entityId: UUID? = {
            guard let key = type.entityIdKey,
                  let idString = userInfo[key] as? String else { return nil }
            return UUID(uuidString: idString)
        }()

        if let entityId {
            // Targeted refresh — within budget
            for domain in type.affectedDomains {
                do {
                    switch domain {
                    case .dashboard:
                        _ = try await DashboardSyncEngine.shared.performTargetedSync(entityId: entityId)
                    case .townHall:
                        _ = try await TownHallSyncEngine.shared.performTargetedSync(entityId: entityId)
                    case .conversations, .badges:
                        break // defer conversations to foreground; badges below
                    }
                } catch {
                    // Non-fatal — foreground will catch up
                }
            }
            await BadgeCountManager.shared.refreshAllBadges(reason: "backgroundPush")
            deadline.cancel()
            completionHandler(.newData)
        } else {
            // No entity ID — mark invalidated, defer to foreground
            RefreshCoordinator.shared.invalidate(type.affectedDomains)
            await BadgeCountManager.shared.refreshAllBadges(reason: "backgroundPush")
            deadline.cancel()
            completionHandler(.noData)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/NaarsCars/App/AppDelegate.swift
git commit -m "feat: wire push-received handler and add background push support"
```

---

### Task 13: MainTabView — Wire Coordinator Visibility

**Files:**
- Modify: `NaarsCars/NaarsCars/App/MainTabView.swift`

- [ ] **Step 1: Add tab→domain mapping and coordinator call**

In the existing `.onChange(of: selectedTab)` handler (around line 100), add the coordinator call:

```swift
.onChange(of: selectedTab) { oldValue, newTab in
    // Existing: update coordinator tab
    if let tab = NavigationCoordinator.Tab(rawValue: newTab) {
        navigationCoordinator.selectedTab = tab
    }

    // NEW: notify RefreshCoordinator of visible domain
    let domain: RefreshDomain? = {
        switch newTab {
        case 0: return .dashboard
        case 1: return .conversations
        case 2: return .townHall
        case 3: return nil  // profile — no refresh domain
        default: return nil
        }
    }()
    RefreshCoordinator.shared.setVisibleDomain(domain)

    // Existing badge clearing logic below...
}
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/NaarsCars/App/MainTabView.swift
git commit -m "feat: wire MainTabView tab changes to RefreshCoordinator visibility"
```

---

### Task 14: Wire Coordinator into App Lifecycle

**Files:**
- Modify: `NaarsCars/NaarsCars/App/AppLaunchManager.swift`
- Modify: `NaarsCars/NaarsCars/Core/Services/AuthService.swift`

- [ ] **Step 1: Initialize coordinator in AppLaunchManager**

In `startDeferredSyncEnginesIfNeeded(for:)`, add before `SyncEngineOrchestrator.shared.startAll()`:

```swift
RefreshCoordinator.shared.initializeStates()
RefreshCoordinator.shared.startSafetyPoll()
```

- [ ] **Step 2: Add SwiftData wipe and coordinator reset to sign-out**

In `AuthService.handleSignOut()`, add after `SyncEngineOrchestrator.shared.teardownAll()`:

```swift
// Reset coordinator
RefreshCoordinator.shared.reset()

// Wipe SwiftData
if let modelContext = /* obtain MainActor model context */ {
    try? modelContext.delete(model: SDRide.self)
    try? modelContext.delete(model: SDFavor.self)
    try? modelContext.delete(model: SDNotification.self)
    try? modelContext.delete(model: SDConversation.self)
    try? modelContext.delete(model: SDMessage.self)
    try? modelContext.delete(model: SDDeletedMessage.self)
    try? modelContext.delete(model: SDTownHallPost.self)
    try? modelContext.delete(model: SDTownHallComment.self)
    try? modelContext.save()
}
```

NOTE: The implementer needs to determine how to access the MainActor `ModelContext` from `AuthService`. This likely means passing it in or accessing it via a shared reference. Check existing patterns in the codebase.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/NaarsCars/App/AppLaunchManager.swift NaarsCars/NaarsCars/Core/Services/AuthService.swift
git commit -m "feat: wire RefreshCoordinator into app lifecycle and sign-out SwiftData wipe"
```

---

### Task 14b: Wire Conversation Detail ViewModel + TypingIndicator

**Files:**
- Modify: The conversation detail ViewModel (find via `grep -r "ConversationDetail" --include="*.swift" -l` — likely `Features/Messaging/ViewModels/ConversationDetailViewModel.swift` or similar)
- Modify: `NaarsCars/NaarsCars/Features/Messaging/ViewModels/TypingIndicatorManager.swift`

- [ ] **Step 1: Add subscribeToConversation call on conversation open**

In the conversation detail ViewModel's `onAppear` / `loadConversation` method, add:

```swift
MessagingSyncEngine.shared.subscribeToConversation(conversationId)
TypingIndicatorManager.shared.startTypingObservation(for: conversationId)
```

- [ ] **Step 2: Add grace period on conversation close**

In the conversation detail ViewModel's `onDisappear`, add:

```swift
MessagingSyncEngine.shared.beginGracePeriod()
// TypingIndicator is torn down by MessagingSyncEngine.unsubscribeFromActiveConversation()
```

- [ ] **Step 3: Wire TypingIndicator teardown into MessagingSyncEngine**

In `MessagingSyncEngine.unsubscribeFromActiveConversation()` (created in Task 9), add:

```swift
TypingIndicatorManager.shared.stopTypingObservation()
```

Also add it to `cancelGracePeriodAndUnsubscribe()`.

- [ ] **Step 4: Wire tab-switch teardown**

In MainTabView's `onChange(of: selectedTab)`, when leaving the messaging tab (tab 1):

```swift
if oldValue == 1 && newTab != 1 {
    MessagingSyncEngine.shared.cancelGracePeriodAndUnsubscribe()
}
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: wire conversation WebSocket lifecycle to detail view and tab switching"
```

---

### Task 14c: ContentView Foreground Handler + Safety Poll Restart

**Files:**
- Modify: `NaarsCars/NaarsCars/App/ContentView.swift` (or wherever `scenePhase` is handled)

- [ ] **Step 1: Replace restartRealtimeSyncEngines with coordinator foreground handling**

Find the `.onChange(of: scenePhase)` handler that calls `AuthService.shared.restartRealtimeSyncEngines()` on `.active`. Replace with:

```swift
case .active:
    RefreshCoordinator.shared.handleAppForegrounded()
    RefreshCoordinator.shared.startSafetyPoll()
```

- [ ] **Step 2: Add safety poll stop on background**

In the `.background` case:

```swift
case .background:
    RefreshCoordinator.shared.stopSafetyPoll()
```

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/NaarsCars/App/ContentView.swift
git commit -m "feat: wire app foreground/background to RefreshCoordinator"
```

---

### Task 14d: Migrate SyncEngineOrchestrator Call Sites

**Files:**
- Modify: `NaarsCars/NaarsCars/App/AppLaunchManager.swift`
- Modify: `NaarsCars/NaarsCars/Core/Services/AuthService.swift`
- Modify: `NaarsCars/NaarsCars/App/NaarsCarsApp.swift` (if it references orchestrator)
- Modify: `NaarsCars/NaarsCars/App/ContentView.swift`

- [ ] **Step 1: Grep for all SyncEngineOrchestrator call sites**

```bash
grep -rn "SyncEngineOrchestrator" --include="*.swift" NaarsCars/
```

- [ ] **Step 2: Replace each call site**

- `setupAll(modelContext:)` → keep as-is (engines still need model context setup), but call it from `RefreshCoordinator.initializeStates()`
- `startAll()` → `RefreshCoordinator.shared.initializeStates()` + `startSafetyPoll()` + trigger initial full sync per domain
- `pauseAll()` → `RefreshCoordinator.shared.stopSafetyPoll()`
- `resumeAll()` → `RefreshCoordinator.shared.handleAppForegrounded()` + `startSafetyPoll()`
- `teardownAll()` → `RefreshCoordinator.shared.reset()` (which cancels tasks) + call `teardown()` on each engine

- [ ] **Step 3: Either delete SyncEngineOrchestrator or reduce to thin wrapper**

If all call sites are migrated, delete `SyncEngineOrchestrator.swift`. If some legacy paths remain, keep as thin delegation wrapper to avoid breaking obscure call sites.

- [ ] **Step 4: Verify compile and all tests pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: replace SyncEngineOrchestrator with RefreshCoordinator"
```

---

### Task 14e: Add RefreshCoordinator.handleAppForegrounded Safety Poll Restart

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Services/RefreshCoordinator.swift`

- [ ] **Step 1: Add startSafetyPoll call in handleAppForegrounded**

```swift
func handleAppForegrounded() {
    startSafetyPoll()  // restart safety poll (may have been stopped on background)
    invalidateDomain(.badges)
    if let visible = visibleDomain {
        refreshIfNeeded(visible, trigger: "appForeground")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Services/RefreshCoordinator.swift
git commit -m "fix: restart safety poll on app foreground"
```

---

## Phase 4: RealtimeManager Simplification + Edge Functions

> **IMPORTANT:** Task 16 (edge function deployment) MUST be deployed AFTER Task 12 (AppDelegate background handler) is merged and in production. Deploying `content-available: 1` without the handler causes iOS to penalize the app for not calling the completion handler.

### Task 15: RealtimeManager — Remove Always-On Subscriptions

**Files:**
- Modify: `NaarsCars/NaarsCars/Core/Services/RealtimeManager.swift`

- [ ] **Step 1: Remove staggered reconnection logic**

Remove the 3-tier reconnection code that reconnects 7+ channels on app foreground. The only channels that need reconnection are the active conversation's 3 channels (messages, reactions, typing).

- [ ] **Step 2: Simplify protected channel and max-channel logic**

Reduce max concurrent subscriptions from 30 to ~5 (3 conversation channels + margin). Remove the priority eviction system.

- [ ] **Step 3: Keep subscribe/unsubscribe API intact**

The API is still used by `MessagingSyncEngine` and `TypingIndicatorManager`. No signature changes needed.

- [ ] **Step 4: Verify compile**

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/NaarsCars/Core/Services/RealtimeManager.swift
git commit -m "refactor: simplify RealtimeManager, remove staggered reconnection and channel priority"
```

---

### Task 16: Edge Functions — Add content-available

**Files:**
- Modify: `supabase/functions/send-message-push/index.ts`
- Modify: `supabase/functions/send-notification/index.ts`

- [ ] **Step 1: Update send-message-push APNs payload**

Add `"content-available": 1` to the `aps` object in the payload construction. Also update the `APNsPayload` TypeScript interface to include `"content-available"?: number`.

- [ ] **Step 2: Update send-notification APNs payload**

Add `"content-available": 1` to the `aps` object. The interface already supports it.

- [ ] **Step 3: Deploy edge functions**

Use Supabase MCP: `deploy_edge_function` for both functions.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/send-message-push/index.ts supabase/functions/send-notification/index.ts
git commit -m "feat: add content-available to push payloads for background refresh"
```

---

## Phase 5: Code Cleanup

### Task 16b: Wire Pull-to-Refresh Through Coordinator

**Files:**
- Modify: Dashboard views (e.g., `RequestsDashboardView.swift`, `TownHallView.swift`, `ConversationsListView.swift`)

- [ ] **Step 1: Find all .refreshable closures**

```bash
grep -rn "\.refreshable" --include="*.swift" NaarsCars/NaarsCars/Features/
```

- [ ] **Step 2: Update each to route through coordinator or engine**

For dashboard views, the `.refreshable` closure should call the engine's `performFullSync()` and report to coordinator:

```swift
.refreshable {
    do {
        let metrics = try await DashboardSyncEngine.shared.performFullSync()
        RefreshCoordinator.shared.markSyncCompleted(.dashboard, metrics: metrics)
    } catch {
        RefreshCoordinator.shared.markSyncFailed(.dashboard, error: error, partial: nil)
    }
}
```

Apply same pattern for town hall and conversation list views.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: wire pull-to-refresh through RefreshCoordinator"
```

---

### Task 17: Remove Dead Code

**Files:**
- Delete or modify: `NaarsCars/NaarsCars/Core/Storage/DashboardPayloadMapper.swift`
- Delete or modify: `NaarsCars/NaarsCars/Core/Storage/NotificationPayloadMapper.swift`
- Modify: `NaarsCars/NaarsCarsTests/Core/Decoding/RealtimePayloadDecodingTests.swift`

- [ ] **Step 1: Check if DashboardPayloadMapper and NotificationPayloadMapper are used outside realtime**

Grep for usages. If only used in now-removed realtime handlers, delete the files. If used elsewhere (e.g., REST response parsing), keep them.

- [ ] **Step 2: Remove or update associated tests**

- [ ] **Step 3: Remove stale constants from Constants.swift**

Remove timing constants that are no longer used (e.g., `badgePollConnected`, `badgePollDisconnected` if no longer referenced). Keep `badgeRefreshMinInterval` if still used by BadgeCountManager's internal debounce.

- [ ] **Step 4: Verify compile and all tests pass**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove dead realtime payload mappers and stale constants"
```

---

## Phase 6: Documentation Updates

### Task 18: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Current State of the Codebase**

Replace the realtime-focused description with push-notify/pull-hydrate architecture description. Note that realtime is now scoped to active conversation only. Note `RefreshCoordinator` as the centralized refresh orchestrator.

- [ ] **Step 2: Update Fragile Systems sections**

- §1 (Realtime Pipeline): Update data flow — realtime path only for active conversation messages/reactions. Add new data flow: push → coordinator → engine → SwiftData → @Query/publisher → UI.
- §6 (Sync Engine Lifecycle): Replace with new lifecycle: `setup → performFullSync/performTargetedSync → teardown`. Note coordinator owns staleness and in-flight dedup.
- §7 (Badge Count): Update to push-triggered + 5-min safety poll via coordinator.

- [ ] **Step 3: Update Realtime Rules**

Note realtime is conversation-scoped only. Reduce scope of rules to messaging context.

- [ ] **Step 4: Update Cross-Layer Synchronization Rules**

Add `RefreshCoordinator` and push-received handler as high-blast-radius seams.

- [ ] **Step 5: Update Audit Notes**

Remove TownHallSyncEngine MainActor deviation (resolved). Add RefreshCoordinator to high-risk files. Update file list.

- [ ] **Step 6: Update Quick Reference — Critical Invariants**

Add: RefreshCoordinator state machine, push-triggered refresh, change detection, active conversation exclusion.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for push-notify pull-hydrate architecture"
```

---

### Task 19: Update AGENTS.md and Cursor Rules

**Files:**
- Modify: `AGENTS.md`
- Modify: `.cursor/rules/01-impact-seam-analysis.mdc` (or similar name)
- Modify: `.cursor/rules/03-centralized-realtime-payload-parsing.mdc` (or similar name)
- Modify: `.cursor/rules/naars-cars-project.mdc`

- [ ] **Step 1: Update AGENTS.md with architectural changes**
- [ ] **Step 2: Update cursor rule 01 to include RefreshCoordinator as a seam**
- [ ] **Step 3: Update cursor rule 03 to scope realtime parsing to messages/reactions only**
- [ ] **Step 4: Update master project rule**
- [ ] **Step 5: Commit**

```bash
git add AGENTS.md .cursor/rules/
git commit -m "docs: update AGENTS.md and cursor rules for new architecture"
```

---

## Phase 7: Integration Testing

### Task 20: Manual Testing Pass

**No files changed — testing only.**

- [ ] **Step 1: Test dashboard freshness**

Open app → navigate to dashboard → verify rides load. Switch to messages tab → wait 35 seconds → switch back to dashboard → verify a background refresh fires (check logs for `[dashboard] started | trigger=tabAppear`).

- [ ] **Step 2: Test push-triggered refresh**

Have another user (or use Supabase dashboard to INSERT a ride). Verify push arrives → dashboard updates → badge updates. Check logs for `[dashboard] completed | trigger=push:newRide`.

- [ ] **Step 3: Test conversation WebSocket**

Open a conversation → verify messages appear live. Tap back to list → wait 3 seconds → tap same conversation → verify no reconnection delay (grace period). Wait 6 seconds on list → tap conversation → verify reconnection (brief delay).

- [ ] **Step 4: Test sign-out/sign-in**

Sign out → verify no crash. Sign in as same or different user → verify fresh data loads, no stale data visible.

- [ ] **Step 5: Test background push**

Background the app → send a push (via another user or Supabase trigger) → open app via push tap → verify navigation lands correctly with fresh data.

- [ ] **Step 6: Test guest mode**

Browse as guest → verify rides/favors/town hall load via pull-on-appear. Verify no crashes from missing push/badge infrastructure.

- [ ] **Step 7: Document any issues found**

Create a list of bugs/regressions discovered during testing for immediate fix.

---

## Task Dependency Graph

```
Phase 1 (Foundation):
  Task 1 (types + Domain enum) → Task 2 (mapping) → Task 3 (coordinator)
  Task 3 → Task 4 (change detection) → Task 5 (TH sync actor)
  Task 3 → Task 6 (constants)
  Task 3 → Task 6b (protocol update)
  Task 3 → Task 6c (TH fetchPost)

Phase 2 (Engines): depends on Phase 1
  Task 7 (dashboard) ──┐
  Task 8 (town hall) ──┼── can run in parallel (all depend on Tasks 4-5)
  Task 9 (messaging) ──┤  (Task 9 only depends on Task 3, not 4-5)
  Task 10 (badges) ────┘

Phase 3 (Wiring): depends on Phase 2
  Task 11 (push handler) → Task 12 (AppDelegate) → Task 13 (tab wiring) → Task 14 (lifecycle)
  Task 14 → Task 14b (conversation detail + typing)
  Task 14 → Task 14c (ContentView foreground)
  Task 14 → Task 14d (orchestrator migration)
  Task 14 → Task 14e (safety poll restart)

Phase 4 (RealtimeManager + Edge Functions): depends on Phase 2
  Task 15 (RealtimeManager)
  Task 16 (edge functions) — MUST deploy AFTER Task 12 is in production
  Task 16b (pull-to-refresh wiring)

Phase 5 (Dead code): depends on Phases 2-4
  Task 17

Phase 6 (Docs): depends on all above
  Task 18 → Task 19

Phase 7 (Testing): depends on all above
  Task 20
```

Tasks 7-10 can be implemented in parallel (with the caveat that 7 and 8 depend on Tasks 4-5 while 9 and 10 only depend on Task 3). Tasks 15, 16b, and 17 can run in parallel with Phase 3 (but Task 16 deployment must wait for Task 12).
