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

    override func tearDown() {
        coordinator.reset()
        coordinator = nil
        super.tearDown()
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

    func testResetClearsAllState() {
        coordinator.markSyncedForTesting(.dashboard)
        coordinator.markSyncedForTesting(.townHall)
        coordinator.reset()

        for domain in RefreshDomain.allCases {
            let state = coordinator.stateDescription(for: domain)
            XCTAssertTrue(state == "nil", "Domain \(domain) should be nil after reset, got: \(state)")
        }
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
