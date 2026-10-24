//
//  RefreshCoordinator.swift
//  NaarsCars
//

import Foundation
import SwiftData

/// Centralized refresh orchestration. Single source of truth for data invalidation,
/// staleness tracking, and in-flight deduplication across all data domains.
///
/// INVARIANTS:
/// - At most ONE refresh Task per domain at any time (enforced by isInFlight guard + assert)
/// - Tasks are cancelled ONLY during reset() (sign-out), which waits (bounded) for them to finish
/// - All engine calls happen in executeFullSync/executeTargetedSync (nowhere else)
/// - State transitions: .refreshing never transitions to .refreshing
@MainActor
final class RefreshCoordinator {

    // MARK: - Types

    typealias Domain = RefreshDomain

    enum FreshnessState {
        case unhydrated
        case hydrated(lastSync: Date)
        case invalidated(lastSync: Date)
        case refreshing(task: Task<Void, Never>, hasCache: Bool)
        case failed(retryAfter: Date, hasCache: Bool)
    }

    private enum RefreshMode {
        case full
        case targeted(UUID)
    }

    // MARK: - Singleton

    static let shared = RefreshCoordinator()

    // MARK: - State

    private var states: [Domain: FreshnessState] = [:]
    private var failureCounts: [Domain: Int] = [:]
    private var lastTriggers: [Domain: String] = [:]
    private var lastResults: [Domain: RefreshResult] = [:]
    /// When the last full sync that completed had started, per domain. A targeted sync never counts.
    private var lastFullSyncAt: [Domain: Date] = [:]
    /// The last moment the server may have written rows that no full sync has fetched yet: a push
    /// (every `performTargetedRefresh` caller is a push path), an app foreground (a push delivered
    /// while the app was suspended) or a session start. Read by `fullSyncIsCurrent(_:)`.
    private var lastServerSignalAt: Date = .distantPast
    private var safetyPollTimer: Timer?

    private(set) var visibleDomain: Domain?
    private(set) var activeConversationId: UUID?

    /// Staleness window — see Constants.Timing.refreshStalenessWindow (30s)
    let stalenessWindow: TimeInterval = Constants.Timing.refreshStalenessWindow
    /// Safety poll interval — see Constants.Timing.refreshSafetyPollInterval (5 minutes)
    let safetyPollInterval: TimeInterval = Constants.Timing.refreshSafetyPollInterval

    // MARK: - Initialization

    func initializeStates(modelContext: ModelContext? = nil) {
        // A session starts: a full sync from before it (a guest's fetches no bell rows) is not current.
        lastServerSignalAt = Date()
        for domain in Domain.allCases {
            states[domain] = determineInitialState(domain, modelContext: modelContext)
        }
    }

    private func determineInitialState(_ domain: Domain, modelContext: ModelContext?) -> FreshnessState {
        if let timestamp = lastSyncTimestamp(domain) {
            return .hydrated(lastSync: timestamp)
        }
        if let ctx = modelContext, swiftDataHasRecords(domain, context: ctx) {
            return .hydrated(lastSync: .distantPast)
        }
        return .unhydrated
    }

    // MARK: - Public API: Visibility

    /// Called by MainTabView.onChange(of: selectedTab). Sole staleness trigger.
    func setVisibleDomain(_ domain: Domain?) {
        let previous = visibleDomain
        visibleDomain = domain
        if let domain, domain != previous {
            refreshIfNeeded(domain, trigger: "tabAppear")
        }
    }

    /// Active conversation excluded from background sync.
    func setActiveConversation(_ id: UUID?) {
        activeConversationId = id
    }

    // MARK: - Public API: Refresh Triggers

    /// Staleness-gated refresh. Used by tab appear, safety poll, app foreground.
    /// Fire-and-forget. If domain is already refreshing, this is a no-op.
    func refreshIfNeeded(_ domain: Domain, trigger: String) {
        guard shouldRefresh(domain) else {
            let reason = skipReason(for: domain)
            logDecision(domain: domain, trigger: trigger, decision: "skipped:\(reason.rawValue)")
            lastResults[domain] = .skipped(reason)
            return
        }
        guard !isInFlight(domain) else {
            logDecision(domain: domain, trigger: trigger, decision: "joined")
            lastResults[domain] = .joined(inFlightTrigger: lastTriggers[domain] ?? "unknown")
            return
        }
        startRefreshTask(domain: domain, trigger: trigger, mode: .full)
    }

    /// Push-triggered single-entity refresh. Fire-and-forget.
    /// Badges always refresh (exempt from in-flight dedup — no SwiftData conflict).
    ///
    /// **Collision policy:** If a full sync is already in-flight for this domain,
    /// the targeted refresh is skipped (logged as "joined:inFlight"). The in-flight
    /// full sync will fetch ALL entities including the one this push is about.
    /// The 30s staleness window guarantees the next full sync runs within 30s of
    /// the in-flight one completing, catching any subsequent changes.
    func performTargetedRefresh(_ domain: Domain, entityId: UUID, trigger: String) {
        // A push may have created rows a targeted sync does not fetch (bell rows), so no full sync
        // that started before now is current. Not keyed on the trigger text: the silent-push path
        // (AppDelegate) says "backgroundPush:", the foreground path "push:".
        lastServerSignalAt = Date()
        if domain == .badges {
            lastTriggers[domain] = trigger
            logDecision(domain: domain, trigger: trigger, decision: "started(badges)")
            Task {
                await BadgeCountManager.shared.refreshAllBadges(reason: trigger)
            }
            return
        }
        guard !isInFlight(domain) else {
            logDecision(domain: domain, trigger: trigger, decision: "joined:inFlight")
            lastResults[domain] = .joined(inFlightTrigger: lastTriggers[domain] ?? "unknown")
            return
        }
        startRefreshTask(domain: domain, trigger: trigger, mode: .targeted(entityId))
    }

    /// Force a full sync regardless of staleness. Used by pull-to-refresh.
    func forceFullRefresh(_ domain: Domain, trigger: String) {
        guard !isInFlight(domain) else {
            logDecision(domain: domain, trigger: trigger, decision: "joined:inFlight")
            lastResults[domain] = .joined(inFlightTrigger: lastTriggers[domain] ?? "unknown")
            return
        }
        startRefreshTask(domain: domain, trigger: trigger, mode: .full)
    }

    /// Awaitable variant of `forceFullRefresh(_:trigger:)` for pull-to-refresh and manual reloads
    /// driven from a ViewModel. Starts a full sync — or joins the one already in flight — and
    /// suspends until that task finishes, so a `.refreshable` spinner ends when the data has
    /// actually been persisted.
    ///
    /// INVARIANTS preserved: the task is never cancelled here (only `reset()` cancels), and the
    /// in-flight dedup is untouched (a second caller joins; it never duplicates).
    /// Returns the terminal result recorded for `domain` (`.completed` / `.failed`), or nil if the
    /// coordinator was reset (sign-out) while waiting.
    ///
    /// `unlessCurrent` (default false): skip, returning `.skipped(.fresh)`, when nothing is in flight
    /// and a full sync of `domain` completed within the staleness window and started after the last
    /// push, app foreground or session start (`fullSyncIsCurrent(_:)`). For a screen's open, which
    /// is not a reload; pull-to-refresh and Retry keep the default.
    func forceFullRefreshAndWait(_ domain: Domain, trigger: String, unlessCurrent: Bool = false) async -> RefreshResult? {
        if unlessCurrent, !isInFlight(domain), fullSyncIsCurrent(domain) {
            logDecision(domain: domain, trigger: trigger, decision: "skipped:current")
            lastResults[domain] = .skipped(.fresh)
            return .skipped(.fresh)
        }
        forceFullRefresh(domain, trigger: trigger)
        guard case .refreshing(let task, _) = states[domain] else {
            return lastResults[domain]
        }
        await task.value
        return lastResults[domain]
    }

    /// Invalidate domains (push without entity ID). Marks stale for next access.
    func invalidate(_ domains: Set<Domain>, reason: String = "push") {
        for domain in domains {
            logDecision(domain: domain, trigger: "invalidation", decision: "invalidated(reason=\(reason))")
            invalidateDomain(domain)
        }
    }

    // MARK: - Public API: Lifecycle

    func handleAppForegrounded() {
        // A push delivered while the app was suspended reaches no handler; a foreground implies it.
        lastServerSignalAt = Date()
        startSafetyPoll()
        // Badges always refresh eagerly
        Task {
            await BadgeCountManager.shared.refreshAllBadges(reason: "appForeground")
        }
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

    /// Sign-out teardown. Cancels all in-flight tasks, waits for them to finish, clears all state.
    ///
    /// The wait closes a sign-out race: a sync job that has entered `BackgroundSyncActor` does not
    /// check cancellation and runs to its `save()`, and the caller wipes SwiftData right after this
    /// returns, so returning first let the job's rows outlive sign-out. An engine checks
    /// `Task.isCancelled` before entering the actor, so a cancelled task that has not entered it
    /// ends at once. While waiting, the cancelled domains stay `.refreshing`, so a trigger in that
    /// window joins instead of starting a new sync. The wait ends after `drainTimeout` regardless.
    func reset(drainTimeout: TimeInterval = Constants.Timing.refreshResetDrainTimeout) async {
        stopSafetyPoll()
        var cancelledTasks: [Task<Void, Never>] = []
        for (_, state) in states {
            if case .refreshing(let task, _) = state {
                task.cancel()
                cancelledTasks.append(task)
            }
        }
        // A forceFullRefreshAndWait caller resumed by a cancelled task reads nil, as documented.
        lastResults.removeAll()
        if !cancelledTasks.isEmpty {
            let finished = await Self.waitForCompletion(of: cancelledTasks, timeout: drainTimeout)
            if !finished {
                AppLogger.warning("refresh", "reset: cancelled refreshes still running after \(drainTimeout)s")
            }
        }
        // A refresh started for another domain while waiting is cancelled too (not awaited), so
        // it cannot mark its domain hydrated after the state below is cleared.
        for (_, state) in states {
            if case .refreshing(let task, _) = state {
                task.cancel()
            }
        }
        states.removeAll()
        failureCounts.removeAll()
        lastTriggers.removeAll()
        lastResults.removeAll()
        lastFullSyncAt.removeAll()
        lastServerSignalAt = .distantPast
        visibleDomain = nil
        activeConversationId = nil
        clearAllSyncTimestamps()
    }

    /// Waits until every task in `tasks` has finished or `timeout` seconds have passed, and
    /// returns false on timeout. `Task.value` keeps waiting when its waiter is cancelled, so a task
    /// group cannot bound it (the group waits for every child); the two waits race through a stream.
    private static func waitForCompletion(of tasks: [Task<Void, Never>], timeout: TimeInterval) async -> Bool {
        let (outcomes, continuation) = AsyncStream.makeStream(of: Bool.self)
        let waiter = Task {
            for task in tasks { await task.value }
            continuation.yield(true)
        }
        let timer = Task {
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            continuation.yield(false)
        }
        var finished = false
        for await outcome in outcomes {
            finished = outcome
            break
        }
        timer.cancel()
        waiter.cancel()
        continuation.finish()
        return finished
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
            return false
        case .failed(let retryAfter, _):
            return Date() >= retryAfter
        }
    }

    /// True when the domain is hydrated by a full sync that started after `lastServerSignalAt` (the
    /// last push, app foreground or session start) and is still within the staleness window. A
    /// targeted sync marks the domain hydrated too, but it runs only for a push, which sets
    /// `lastServerSignalAt`.
    private func fullSyncIsCurrent(_ domain: Domain) -> Bool {
        guard case .hydrated = states[domain], let at = lastFullSyncAt[domain] else { return false }
        return at > lastServerSignalAt && Date().timeIntervalSince(at) < stalenessWindow
    }

    // MARK: - Single Task Creation Point

    /// ALL refresh execution goes through this method.
    /// INVARIANT: Must never be called if domain is already .refreshing.
    private func startRefreshTask(domain: Domain, trigger: String, mode: RefreshMode) {
        assert(!isInFlight(domain), "startRefreshTask called while \(domain) is in-flight. This is a bug.")

        let hasCache = lastSyncTimestamp(domain) != nil
        lastTriggers[domain] = trigger
        logDecision(domain: domain, trigger: trigger, decision: "started(\(mode))")
        // The start, not the end: a push that lands while the fetch runs may not be in it.
        let startedAt = Date()

        let task = Task { [weak self] in
            do {
                let metrics: RefreshMetrics
                switch mode {
                case .full:
                    metrics = try await self?.executeFullSync(domain) ?? .empty
                case .targeted(let entityId):
                    metrics = try await self?.executeTargetedSync(domain, entityId: entityId) ?? .empty
                }
                guard !Task.isCancelled else { return }
                if case .full = mode { self?.lastFullSyncAt[domain] = startedAt }
                self?.markSyncCompleted(domain, metrics: metrics)
            } catch is CancellationError {
                // sign-out cancelled this task — no state update
            } catch {
                guard !Task.isCancelled else { return }
                self?.markSyncFailed(domain, error: error, partial: nil)
            }
        }

        states[domain] = .refreshing(task: task, hasCache: hasCache)
    }

    // MARK: - Engine Dispatch (ONLY place engines are called)

    /// Dispatches full sync to the appropriate engine.
    /// Later tasks will wire these to actual engine implementations.
    private func executeFullSync(_ domain: Domain) async throws -> RefreshMetrics {
        #if DEBUG
        if let fullSyncOverrideForTesting { return try await fullSyncOverrideForTesting(domain) }
        #endif
        switch domain {
        case .dashboard:
            return try await DashboardSyncEngine.shared.performFullSync()
        case .townHall:
            return try await TownHallSyncEngine.shared.performFullSync()
        case .conversations:
            return try await MessagingSyncEngine.shared.refreshConversationList()
        case .badges:
            await BadgeCountManager.shared.refreshAllBadges(reason: lastTriggers[.badges] ?? "coordinator")
            return .badgeOnly
        }
    }

    /// Dispatches targeted sync to the appropriate engine.
    private func executeTargetedSync(_ domain: Domain, entityId: UUID) async throws -> RefreshMetrics {
        switch domain {
        case .dashboard:
            return try await DashboardSyncEngine.shared.performTargetedSync(entityId: entityId)
        case .townHall:
            return try await TownHallSyncEngine.shared.performTargetedSync(entityId: entityId)
        case .conversations:
            return try await MessagingSyncEngine.shared.refreshConversationList()
        case .badges:
            await BadgeCountManager.shared.refreshAllBadges(reason: "coordinator")
            return .badgeOnly
        }
    }

    // MARK: - State Completion

    func markSyncCompleted(_ domain: Domain, metrics: RefreshMetrics) {
        states[domain] = .hydrated(lastSync: Date())
        failureCounts[domain] = 0
        lastResults[domain] = .completed(metrics)
        markSyncTimestamp(domain)
        logDecision(domain: domain, trigger: lastTriggers[domain] ?? "unknown",
                    decision: "completed(eval=\(metrics.recordsEvaluated) mut=\(metrics.recordsMutated) ins=\(metrics.recordsInserted) del=\(metrics.recordsDeleted) saved=\(metrics.savedToStore) \(metrics.durationMs)ms)")
    }

    func markSyncFailed(_ domain: Domain, error: Error, partial: RefreshMetrics?) {
        let count = (failureCounts[domain] ?? 0) + 1
        failureCounts[domain] = count
        let backoff = min(pow(2.0, Double(count - 1)) * Constants.Retry.refreshBackoffInitial, Constants.Retry.refreshBackoffMax)
        let hasCache = lastSyncTimestamp(domain) != nil
        states[domain] = .failed(retryAfter: Date().addingTimeInterval(backoff), hasCache: hasCache)
        lastResults[domain] = .failed(error, partial: partial)
        logDecision(domain: domain, trigger: lastTriggers[domain] ?? "unknown",
                    decision: "failed(\(error.localizedDescription))")
    }

    // MARK: - Internal Helpers

    private func invalidateDomain(_ domain: Domain) {
        switch states[domain] {
        case .refreshing:
            logDecision(domain: domain, trigger: "invalidation", decision: "skipped:inFlight")
            return
        case .hydrated(let lastSync):
            states[domain] = .invalidated(lastSync: lastSync)
        case .failed(_, let hasCache) where hasCache:
            states[domain] = .invalidated(lastSync: lastSyncTimestamp(domain) ?? .distantPast)
        case .unhydrated, .invalidated, .failed, .none:
            break
        }
    }

    private func isInFlight(_ domain: Domain) -> Bool {
        if case .refreshing = states[domain] { return true }
        return false
    }

    private func skipReason(for domain: Domain) -> SkipReason {
        guard let state = states[domain] else { return .domainNotStarted }
        switch state {
        case .refreshing: return .fresh
        case .failed(let r, _) where Date() < r: return .backoff
        default: return .fresh
        }
    }

    private func safetyPollFired() {
        for domain in Domain.allCases {
            refreshIfNeeded(domain, trigger: "safetyPoll")
        }
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
                    hasLocalData: false,
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
    /// Stands in for the engine of every full sync on this instance (tests only; never set on `shared`).
    var fullSyncOverrideForTesting: ((Domain) async throws -> RefreshMetrics)?

    func markSyncedForTesting(_ domain: Domain, at date: Date = Date()) {
        states[domain] = .hydrated(lastSync: date)
        lastFullSyncAt[domain] = date
        UserDefaults.standard.set(date, forKey: "refresh.lastSync.\(domain.rawValue)")
    }

    func stateForTesting(_ domain: Domain) -> FreshnessState? {
        states[domain]
    }
    #endif
}
