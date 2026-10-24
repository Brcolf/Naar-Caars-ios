//
//  RefreshCoordinatorTests.swift
//  NaarsCars
//

import XCTest
@testable import NaarsCars

@MainActor
final class RefreshCoordinatorTests: XCTestCase {

    var coordinator: RefreshCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = RefreshCoordinator()
        // Clear any leftover timestamps from other tests
        for domain in RefreshDomain.allCases {
            UserDefaults.standard.removeObject(forKey: "refresh.lastSync.\(domain.rawValue)")
        }
    }

    override func tearDown() async throws {
        await coordinator.reset()
        coordinator = nil
        try await super.tearDown()
    }

    func testInitialStateIsUnhydratedWhenNoTimestamp() {
        coordinator.initializeStates()
        let state = coordinator.stateDescription(for: .dashboard)
        XCTAssertTrue(state.contains("unhydrated") || state.contains("nil"))
    }

    func testShouldRefreshWhenUnhydrated() {
        coordinator.initializeStates()
        XCTAssertTrue(coordinator.shouldRefresh(.dashboard))
    }

    func testShouldNotRefreshWhenFresh() {
        coordinator.markSyncedForTesting(.dashboard)
        XCTAssertFalse(coordinator.shouldRefresh(.dashboard))
    }

    func testShouldRefreshWhenStale() {
        coordinator.markSyncedForTesting(.dashboard, at: Date().addingTimeInterval(-60))
        XCTAssertTrue(coordinator.shouldRefresh(.dashboard))
    }

    func testInvalidateSetsInvalidatedState() {
        coordinator.markSyncedForTesting(.dashboard)
        coordinator.invalidate([.dashboard])
        let state = coordinator.stateDescription(for: .dashboard)
        XCTAssertTrue(state.contains("invalidated"))
    }

    func testInvalidateWhileRefreshingIsNoOp() {
        coordinator.markSyncedForTesting(.dashboard, at: Date().addingTimeInterval(-60))
        // Trigger a refresh to get into .refreshing state
        coordinator.refreshIfNeeded(.dashboard, trigger: "test")
        let stateBefore = coordinator.stateDescription(for: .dashboard)
        XCTAssertTrue(stateBefore.contains("refreshing"))

        // Invalidate while refreshing should be a no-op
        coordinator.invalidate([.dashboard])
        let stateAfter = coordinator.stateDescription(for: .dashboard)
        XCTAssertTrue(stateAfter.contains("refreshing"))
    }

    func testResetClearsAllState() async {
        coordinator.markSyncedForTesting(.dashboard)
        coordinator.markSyncedForTesting(.townHall)
        await coordinator.reset()

        for domain in RefreshDomain.allCases {
            let state = coordinator.stateDescription(for: domain)
            XCTAssertTrue(state == "nil", "Domain \(domain) should be nil after reset, got: \(state)")
        }
    }

    /// Sign-out race (performance pass 2026-10-20, open item 1): a sync job that has entered
    /// BackgroundSyncActor ignores cancellation and runs to its save. AuthService wipes SwiftData
    /// right after reset() returns, so reset() must not return before that save.
    func testResetWaitsForInFlightSyncWriteBeforeReturning() async {
        var events: [String] = []
        var started = false
        coordinator.fullSyncOverrideForTesting = { _ in
            started = true
            // The engines' shape: the actor job runs in a detached task, which the coordinator's
            // cancellation does not reach, and `.value` waits for it (100 ms here).
            _ = await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
            events.append(Task.isCancelled ? "write(cancelled)" : "write")
            return .empty
        }
        coordinator.forceFullRefresh(.dashboard, trigger: "test")
        for _ in 0..<200 where !started { await Task.yield() }
        XCTAssertTrue(started)

        await coordinator.reset()
        events.append("resetReturned")

        XCTAssertEqual(events, ["write(cancelled)", "resetReturned"])
        XCTAssertEqual(coordinator.stateDescription(for: .dashboard), "nil")
        XCTAssertNil(UserDefaults.standard.object(forKey: "refresh.lastSync.dashboard"))
    }

    /// The wait is bounded: a job that never finishes cannot hang sign-out.
    func testResetReturnsAfterDrainTimeoutWhenSyncNeverFinishes() async {
        var wrote = false
        var release: CheckedContinuation<Void, Never>?
        coordinator.fullSyncOverrideForTesting = { _ in
            await withCheckedContinuation { release = $0 }
            wrote = true
            return .empty
        }
        coordinator.forceFullRefresh(.townHall, trigger: "test")
        guard case .refreshing(let task, _)? = coordinator.stateForTesting(.townHall) else {
            return XCTFail("townHall should be refreshing")
        }
        for _ in 0..<200 where release == nil { await Task.yield() }
        XCTAssertNotNil(release)

        let start = ContinuousClock.now
        await coordinator.reset(drainTimeout: 0.3)
        let elapsed = ContinuousClock.now - start

        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(300))
        XCTAssertLessThan(elapsed, .seconds(2))
        XCTAssertFalse(wrote)
        XCTAssertEqual(coordinator.stateDescription(for: .townHall), "nil")

        // Let the job end so nothing outlives the test.
        release?.resume()
        await task.value
        XCTAssertTrue(wrote)
        XCTAssertEqual(coordinator.stateDescription(for: .townHall), "nil")
    }

    func testSetVisibleDomainTriggersRefreshIfStale() {
        coordinator.markSyncedForTesting(.dashboard, at: Date().addingTimeInterval(-60))
        coordinator.setVisibleDomain(.dashboard)
        // Should be refreshing now
        let state = coordinator.stateDescription(for: .dashboard)
        XCTAssertTrue(state.contains("refreshing"))
    }

    func testSetVisibleDomainSkipsIfFresh() {
        coordinator.markSyncedForTesting(.dashboard)
        coordinator.setVisibleDomain(.dashboard)
        let state = coordinator.stateDescription(for: .dashboard)
        // Should still be hydrated, not refreshing
        XCTAssertTrue(state.contains("hydrated"))
    }

    func testDiagnosticSnapshotReturnsAllDomains() {
        coordinator.initializeStates()
        let snapshot = coordinator.diagnosticSnapshot()
        XCTAssertEqual(snapshot.domains.count, RefreshDomain.allCases.count)
    }

    // MARK: - forceFullRefreshAndWait(unlessCurrent:) (performance pass, item 5: the bell's open)

    /// Counts the full syncs this coordinator runs (the engine is never reached).
    private func countFullSyncs() -> () -> Int {
        var calls = 0
        coordinator.fullSyncOverrideForTesting = { _ in
            calls += 1
            return .empty
        }
        return { calls }
    }

    func testForceFullRefreshAndWaitUnlessCurrent_SkipsRightAfterAFullSync() async {
        let calls = countFullSyncs()
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")

        let result = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "open", unlessCurrent: true)

        XCTAssertEqual(calls(), 1, "a full sync with no push since is current")
        guard case .skipped(.fresh)? = result else {
            return XCTFail("expected .skipped(.fresh), got \(String(describing: result))")
        }
    }

    /// A push may bring rows a targeted sync does not fetch (bell rows). Badges only here: with no
    /// session it makes no request, while a dashboard targeted refresh would reach the real engine.
    func testForceFullRefreshAndWaitUnlessCurrent_RunsAgainAfterAPush() async {
        let calls = countFullSyncs()
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")
        coordinator.performTargetedRefresh(.badges, entityId: UUID(), trigger: "push:new_ride")

        let result = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "open", unlessCurrent: true)

        XCTAssertEqual(calls(), 2)
        guard case .completed? = result else {
            return XCTFail("expected .completed, got \(String(describing: result))")
        }
    }

    /// A push that lands while a full sync runs may not be in it: the sync counts from its start.
    func testForceFullRefreshAndWaitUnlessCurrent_RunsAgainAfterAPushDuringTheSync() async {
        var calls = 0
        var release: CheckedContinuation<Void, Never>?
        coordinator.fullSyncOverrideForTesting = { _ in
            calls += 1
            if calls == 1 { await withCheckedContinuation { release = $0 } }
            return .empty
        }
        coordinator.forceFullRefresh(.dashboard, trigger: "test")
        guard case .refreshing(let task, _)? = coordinator.stateForTesting(.dashboard) else {
            return XCTFail("dashboard should be refreshing")
        }
        for _ in 0..<200 where release == nil { await Task.yield() }
        coordinator.performTargetedRefresh(.badges, entityId: UUID(), trigger: "push:new_ride")
        release?.resume()
        await task.value

        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "open", unlessCurrent: true)

        XCTAssertEqual(calls, 2)
    }

    /// A push delivered while the app was suspended reaches no handler; the foreground stands in for it.
    func testForceFullRefreshAndWaitUnlessCurrent_RunsAgainAfterAForeground() async {
        let calls = countFullSyncs()
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")
        coordinator.handleAppForegrounded()

        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "open", unlessCurrent: true)

        XCTAssertEqual(calls(), 2)
    }

    /// A full sync from before the session started (a guest's fetches no bell rows) is not current.
    func testForceFullRefreshAndWaitUnlessCurrent_RunsAgainAfterASessionStart() async {
        let calls = countFullSyncs()
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")
        coordinator.initializeStates()

        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "open", unlessCurrent: true)

        XCTAssertEqual(calls(), 2)
    }

    func testForceFullRefreshAndWaitUnlessCurrent_RunsWhenTheFullSyncIsOlderThanTheWindow() async {
        let calls = countFullSyncs()
        coordinator.markSyncedForTesting(.dashboard, at: Date().addingTimeInterval(-(coordinator.stalenessWindow + 1)))

        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "open", unlessCurrent: true)

        XCTAssertEqual(calls(), 1)
    }

    func testForceFullRefreshAndWait_DefaultStillForces() async {
        let calls = countFullSyncs()
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")

        XCTAssertEqual(calls(), 2, "pull-to-refresh and Retry keep forcing")
    }
}
