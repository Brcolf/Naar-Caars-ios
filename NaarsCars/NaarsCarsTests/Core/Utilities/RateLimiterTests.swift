//
//  RateLimiterTests.swift
//  NaarsCarsTests
//
//  Unit tests for RateLimiter
//

import XCTest
@testable import NaarsCars

@MainActor
final class RateLimiterTests: XCTestCase {
    var rateLimiter: RateLimiter!
    
    override func setUp() {
        super.setUp()
        rateLimiter = RateLimiter.shared
        // Reset all rate limits before each test
        Task {
            await rateLimiter.resetAll()
        }
    }
    
    func testCheckAndRecordReturnsFalseWhenTooFast() async {
        let action = "test_action"
        let interval: TimeInterval = 5.0
        
        // First action should be allowed
        let firstResult = await rateLimiter.checkAndRecord(action: action, minimumInterval: interval)
        XCTAssertTrue(firstResult, "First action should be allowed")
        
        // Second action immediately after should be rate limited
        let secondResult = await rateLimiter.checkAndRecord(action: action, minimumInterval: interval)
        XCTAssertFalse(secondResult, "Second action should be rate limited")
    }
    
    func testCheckAndRecordReturnsTrueAfterIntervalPasses() async {
        let action = "test_action"
        let interval: TimeInterval = 0.1 // Short interval for testing
        
        // First action
        let firstResult = await rateLimiter.checkAndRecord(action: action, minimumInterval: interval)
        XCTAssertTrue(firstResult, "First action should be allowed")
        
        // Wait for interval to pass
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000) + 50_000_000) // Add 50ms buffer
        
        // Second action after interval should be allowed
        let secondResult = await rateLimiter.checkAndRecord(action: action, minimumInterval: interval)
        XCTAssertTrue(secondResult, "Second action after interval should be allowed")
    }
    
    func testResetClearsTheRateLimit() async {
        let action = "test_action"
        let interval: TimeInterval = 5.0
        
        // First action
        let firstResult = await rateLimiter.checkAndRecord(action: action, minimumInterval: interval)
        XCTAssertTrue(firstResult, "First action should be allowed")
        
        // Second action should be rate limited
        let secondResult = await rateLimiter.checkAndRecord(action: action, minimumInterval: interval)
        XCTAssertFalse(secondResult, "Second action should be rate limited")
        
        // Reset the action
        await rateLimiter.reset(action: action)
        
        // After reset, action should be allowed again
        let thirdResult = await rateLimiter.checkAndRecord(action: action, minimumInterval: interval)
        XCTAssertTrue(thirdResult, "Action should be allowed after reset")
    }
    
    func testDifferentActionsAreIndependent() async {
        let action1 = "action_1"
        let action2 = "action_2"
        let interval: TimeInterval = 5.0
        
        // Perform action1
        let result1 = await rateLimiter.checkAndRecord(action: action1, minimumInterval: interval)
        XCTAssertTrue(result1, "First action1 should be allowed")
        
        // Immediately perform action2 (different action)
        let result2 = await rateLimiter.checkAndRecord(action: action2, minimumInterval: interval)
        XCTAssertTrue(result2, "Different action should be allowed immediately")
        
        // action1 should still be rate limited
        let result1Again = await rateLimiter.checkAndRecord(action: action1, minimumInterval: interval)
        XCTAssertFalse(result1Again, "Same action should still be rate limited")
    }
}

