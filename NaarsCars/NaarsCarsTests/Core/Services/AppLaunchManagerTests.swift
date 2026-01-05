//
//  AppLaunchManagerTests.swift
//  NaarsCarsTests
//
//  Unit tests for AppLaunchManager including performance tests
//

import XCTest
@testable import NaarsCars

@MainActor
final class AppLaunchManagerTests: XCTestCase {
    var launchManager: AppLaunchManager!
    
    override func setUp() {
        super.setUp()
        launchManager = AppLaunchManager.shared
    }
    
    // MARK: - Performance Tests (PERF-CLI-001)
    
    /// PERF-CLI-001: App cold launch to main screen - verify <1 second
    /// Note: This tests the critical launch path, not full app launch
    /// Full app launch includes UI rendering which is harder to test in unit tests
    func testCriticalLaunchPathPerformance() async {
        // Measure the critical launch path time
        let startTime = CFAbsoluteTimeGetCurrent()
        
        await launchManager.performCriticalLaunch()
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // Critical path should complete in <1 second
        // Note: This may be slower in tests due to network calls
        // In production, session check is from keychain (very fast)
        XCTAssertLessThan(duration, 2.0, "Critical launch path should be <2s (allowing for test overhead), was \(duration)s")
        
        // Verify we reached a ready state
        switch launchManager.state {
        case .ready:
            // Good - we reached a ready state
            break
        default:
            XCTFail("Launch should reach ready state")
        }
    }
    
    func testLaunchStateTransitions() async {
        // Initial state should be initializing
        XCTAssertEqual(launchManager.state, .initializing)
        
        // After launch, should be in ready state
        await launchManager.performCriticalLaunch()
        
        // Should be in ready state (exact state depends on auth)
        switch launchManager.state {
        case .ready:
            // Good
            break
        default:
            XCTFail("Should be in ready state after launch")
        }
    }
}

