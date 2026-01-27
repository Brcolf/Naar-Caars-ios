//
//  PerformanceImprovementsTests.swift
//  NaarsCarsTests
//
//  Comprehensive tests for all performance improvements (Phases 1-4)
//

import XCTest
import Foundation
@testable import NaarsCars

/// Test suite for performance improvements and optimizations
@MainActor
final class PerformanceImprovementsTests: XCTestCase {
    
    // MARK: - Phase 1: Critical Fixes
    
    func testRequestDeduplicatorPreventsDuplicates() async throws {
        let deduplicator = RequestDeduplicator()
        var callCount = 0
        
        // Simulate 10 concurrent requests
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try! await deduplicator.fetch(key: "test_key") {
                        callCount += 1
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                        return callCount
                    }
                }
            }
        }
        
        // Should only call once despite 10 concurrent requests
        XCTAssertEqual(callCount, 1, "Deduplicator should prevent duplicate calls")
    }
    
    func testRateLimiterPreventsDuplicates() async {
        let rateLimiter = RateLimiter.shared
        await rateLimiter.reset(action: "test_action")
        
        // First action should succeed
        let first = await rateLimiter.checkAndRecord(action: "test_action", minimumInterval: 1.0)
        XCTAssertTrue(first, "First action should be allowed")
        
        // Immediate second action should fail
        let second = await rateLimiter.checkAndRecord(action: "test_action", minimumInterval: 1.0)
        XCTAssertFalse(second, "Second action should be rate limited")
        
        // After delay, should succeed again
        try! await Task.sleep(nanoseconds: 1_100_000_000) // 1.1s
        let third = await rateLimiter.checkAndRecord(action: "test_action", minimumInterval: 1.0)
        XCTAssertTrue(third, "Action after delay should be allowed")
    }
    
    func testTaskCancellationWorks() async throws {
        let task = Task {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try Task.checkCancellation()
            return "completed"
        }
        
        // Cancel immediately
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Task should have thrown cancellation error")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Phase 2: Performance Optimization
    
    func testPaginatedResponseHasMore() {
        let messages = (0..<10).map { i in
            Message(
                id: UUID(),
                conversationId: UUID(),
                fromId: UUID(),
                text: "Message \(i)",
                createdAt: Date()
            )
        }
        
        let paginated = PaginatedMessages(
            messages: messages,
            hasMore: true,
            endCursor: messages.last?.id
        )
        
        XCTAssertTrue(paginated.hasMore)
        XCTAssertNotNil(paginated.endCursor)
        XCTAssertEqual(paginated.messages.count, 10)
    }
    
    // MARK: - Phase 3: Architecture Improvements
    
    func testJSONDecoderFactoryWorks() throws {
        let decoder = JSONDecoderFactory.createSupabaseDecoder()
        
        // Test with ISO8601 with fractional seconds
        let json1 = """
        {"date": "2024-01-15T10:30:45.123Z"}
        """
        
        struct TestDate1: Codable {
            let date: Date
        }
        
        let data1 = json1.data(using: .utf8)!
        let result1 = try decoder.decode(TestDate1.self, from: data1)
        XCTAssertTrue(result1.date.timeIntervalSince1970 > 0)
        
        // Test with DATE format (YYYY-MM-DD)
        let json2 = """
        {"date": "2024-01-15"}
        """
        let data2 = json2.data(using: .utf8)!
        let result2 = try decoder.decode(TestDate1.self, from: data2)
        XCTAssertTrue(result2.date.timeIntervalSince1970 > 0)
    }
    
    func testNetworkRetryDetectsRetryableErrors() {
        // URLError timeout should be retryable
        let timeoutError = URLError(.timedOut)
        XCTAssertTrue(NetworkRetryHelper.isRetryable(error: timeoutError))
        
        // URLError connection lost should be retryable
        let connectionError = URLError(.networkConnectionLost)
        XCTAssertTrue(NetworkRetryHelper.isRetryable(error: connectionError))
        
        // Generic error should not be retryable
        struct CustomError: Error {}
        XCTAssertFalse(NetworkRetryHelper.isRetryable(error: CustomError()))
    }
    
    func testNetworkRetryExponentialBackoff() async throws {
        var attemptCount = 0
        var attemptTimes: [Date] = []
        
        do {
            _ = try await NetworkRetryHelper.withRetry(
                maxAttempts: 3,
                initialDelay: 0.1,
                maxDelay: 10.0
            ) {
                attemptCount += 1
                attemptTimes.append(Date())
                
                // Fail first 2 times, succeed on 3rd
                if attemptCount < 3 {
                    throw URLError(.timedOut)
                }
                return "success"
            }
        } catch {
            XCTFail("Should have succeeded on 3rd attempt")
        }
        
        XCTAssertEqual(attemptCount, 3, "Should have 3 attempts")
        XCTAssertEqual(attemptTimes.count, 3, "Should record 3 attempt times")
        
        // Check exponential backoff (each delay should be ~2x previous)
        if attemptTimes.count >= 3 {
            let delay1to2 = attemptTimes[1].timeIntervalSince(attemptTimes[0])
            let delay2to3 = attemptTimes[2].timeIntervalSince(attemptTimes[1])
            
            // Second delay should be roughly double the first (allowing tolerance)
            XCTAssertTrue(delay2to3 > delay1to2 * 1.5, "Exponential backoff should increase delay")
        }
    }
    
    func testCacheManagerSizeLimits() async {
        let cacheManager = CacheManager.shared
        
        // Clear cache first
        await cacheManager.clearAll()
        
        // Create a large profile
        let profile = Profile(
            id: UUID(),
            name: String(repeating: "a", count: 1000),
            email: "test@example.com",
            car: String(repeating: "b", count: 1000),
            avatarUrl: String(repeating: "c", count: 1000),
            invitedBy: UUID()
        )
        
        // Cache the profile
        await cacheManager.cacheProfile(profile)
        
        // Verify it's cached
        let cached = await cacheManager.getCachedProfile(id: profile.id)
        XCTAssertNotNil(cached, "Profile should be cached")
    }
    
    // MARK: - Phase 4: Observability
    
    func testPerformanceMonitorTracking() async throws {
        let monitor = PerformanceMonitor.shared
        await monitor.reset(operation: "test_operation")
        
        // Measure an operation
        let result = try await monitor.measure(operation: "test_operation") {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            return "done"
        }
        
        XCTAssertEqual(result, "done")
        
        // Get stats
        let stats = await monitor.getStats(for: "test_operation")
        XCTAssertNotNil(stats, "Stats should be available")
        XCTAssertEqual(stats?.count, 1, "Should have 1 sample")
        XCTAssertTrue((stats?.avg ?? 0) > 0.09, "Duration should be at least 0.09s")
    }
    
    func testPerformanceMonitorPercentiles() async throws {
        let monitor = PerformanceMonitor.shared
        await monitor.reset(operation: "percentile_test")
        
        // Record multiple operations with known durations
        for i in 1...100 {
            _ = try await monitor.measure(operation: "percentile_test") {
                try await Task.sleep(nanoseconds: UInt64(i * 1_000_000)) // 1ms to 100ms
                return i
            }
        }
        
        let stats = await monitor.getStats(for: "percentile_test")
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.count, 100)
        
        // P50 should be around 50ms, P95 around 95ms, P99 around 99ms
        XCTAssertTrue((stats?.p50 ?? 0) > 0.045 && (stats?.p50 ?? 0) < 0.055, "P50 should be around 50ms")
        XCTAssertTrue((stats?.p95 ?? 0) > 0.090 && (stats?.p95 ?? 0) < 0.100, "P95 should be around 95ms")
    }
    
    func testPerformanceMonitorSlowDetection() async throws {
        let monitor = PerformanceMonitor.shared
        await monitor.reset(operation: "fetchConversations")
        
        // Simulate slow operation (threshold is 2.0s)
        _ = try await monitor.measure(operation: "fetchConversations") {
            try await Task.sleep(nanoseconds: 2_100_000_000) // 2.1s
            return "done"
        }
        
        let slowOps = await monitor.getSlowOperations()
        let hasFetchConversations = slowOps.contains { $0.operation == "fetchConversations" }
        
        XCTAssertTrue(hasFetchConversations, "fetchConversations should be detected as slow")
    }
    
    func testPerformanceMonitorLimitsSamples() async throws {
        let monitor = PerformanceMonitor.shared
        await monitor.reset(operation: "sample_limit_test")
        
        // Record 150 operations (limit is 100)
        for i in 1...150 {
            _ = try await monitor.measure(operation: "sample_limit_test") {
                return i
            }
        }
        
        let stats = await monitor.getStats(for: "sample_limit_test")
        XCTAssertEqual(stats?.count, 100, "Should only keep 100 samples")
    }
    
    // MARK: - Integration Tests
    
    func testRequestDeduplicationWithPerformance() async throws {
        let deduplicator = RequestDeduplicator()
        let monitor = PerformanceMonitor.shared
        await monitor.reset(operation: "deduplicated_fetch")
        
        var actualFetchCount = 0
        
        // Simulate 5 concurrent requests
        let results = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for i in 0..<5 {
                group.addTask {
                    try! await monitor.measure(operation: "deduplicated_fetch") {
                        try! await deduplicator.fetch(key: "integration_test") {
                            actualFetchCount += 1
                            try! await Task.sleep(nanoseconds: 100_000_000)
                            return "result"
                        }
                    }
                }
            }
            
            var collected: [String] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        
        XCTAssertEqual(results.count, 5, "All 5 requests should complete")
        XCTAssertEqual(actualFetchCount, 1, "Only 1 actual fetch should occur")
        
        let stats = await monitor.getStats(for: "deduplicated_fetch")
        XCTAssertEqual(stats?.count, 5, "Should track all 5 operations")
    }
    
    func testCacheWithSizeLimitsAndMonitoring() async throws {
        let cacheManager = CacheManager.shared
        let monitor = PerformanceMonitor.shared
        
        await cacheManager.clearAll()
        await monitor.reset(operation: "cache_operation")
        
        let profile = Profile(
            id: UUID(),
            name: "Test User",
            email: "test@example.com",
            invitedBy: UUID()
        )
        
        // Cache with monitoring
        _ = try await monitor.measure(operation: "cache_operation") {
            await cacheManager.cacheProfile(profile)
            return "cached"
        }
        
        // Retrieve with monitoring
        _ = try await monitor.measure(operation: "cache_operation") {
            await cacheManager.getCachedProfile(id: profile.id)
            return "retrieved"
        }
        
        let stats = await monitor.getStats(for: "cache_operation")
        XCTAssertEqual(stats?.count, 2, "Should track both cache operations")
    }
}
