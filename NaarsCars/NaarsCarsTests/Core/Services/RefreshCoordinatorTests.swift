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
}
