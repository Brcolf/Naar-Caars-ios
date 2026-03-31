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
/// - Tasks are cancelled ONLY during reset() (sign-out)
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
    private var safetyPollTimer: Timer?

    private(set) var visibleDomain: Domain?
    private(set) var activeConversationId: UUID?

    /// Staleness window — 30 seconds
    let stalenessWindow: TimeInterval = 30.0
    /// Safety poll interval — 5 minutes
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

    /// Invalidate domains (push without entity ID). Marks stale for next access.
    func invalidate(_ domains: Set<Domain>) {
        for domain in domains {
            invalidateDomain(domain)
        }
    }

    // MARK: - Public API: Lifecycle

    func handleAppForegrounded() {
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

    /// Sign-out teardown. Cancels all in-flight tasks, clears all state.
    func reset() {
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
            return false
        case .failed(let retryAfter, _):
            return Date() >= retryAfter
        }
    }

    // MARK: - Single Task Creation Point

    /// ALL refresh execution goes through this method.
    /// INVARIANT: Must never be called if domain is already .refreshing.
    private func startRefreshTask(domain: Domain, trigger: String, mode: RefreshMode) {
        assert(!isInFlight(domain), "startRefreshTask called while \(domain) is in-flight. This is a bug.")

        let hasCache = lastSyncTimestamp(domain) != nil
        lastTriggers[domain] = trigger
        logDecision(domain: domain, trigger: trigger, decision: "started(\(mode))")

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
        switch domain {
        case .dashboard:
            return try await DashboardSyncEngine.shared.performFullSync()
        case .townHall:
            return try await TownHallSyncEngine.shared.performFullSync()
        case .conversations:
            return try await MessagingSyncEngine.shared.refreshConversationList()
        case .badges:
            await BadgeCountManager.shared.refreshAllBadges(reason: "coordinator")
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
        let backoff = min(pow(2.0, Double(count - 1)) * 5.0, 120.0)
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
    func markSyncedForTesting(_ domain: Domain, at date: Date = Date()) {
        states[domain] = .hydrated(lastSync: date)
        UserDefaults.standard.set(date, forKey: "refresh.lastSync.\(domain.rawValue)")
    }

    func stateForTesting(_ domain: Domain) -> FreshnessState? {
        states[domain]
    }
    #endif
}
