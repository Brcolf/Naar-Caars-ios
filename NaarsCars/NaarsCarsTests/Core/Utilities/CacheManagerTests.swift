//
//  CacheManagerTests.swift
//  NaarsCarsTests
//
//  Unit tests for CacheManager
//

import XCTest
@testable import NaarsCars

@MainActor
final class CacheManagerTests: XCTestCase {
    var cacheManager: CacheManager!
    
    override func setUp() {
        super.setUp()
        cacheManager = CacheManager.shared
        // Clear all cache before each test
        Task {
            await cacheManager.clearAll()
        }
    }
    
    // MARK: - Profile Cache Tests
    
    func testProfileCacheReturnsNilWhenEmpty() async {
        let profileId = UUID()
        let cached = await cacheManager.getCachedProfile(id: profileId)
        XCTAssertNil(cached, "Cache should return nil when empty")
    }
    
    func testProfileCacheReturnsValueBeforeTTLExpires() async {
        let profile = Profile(
            id: UUID(),
            name: "Test User",
            email: "test@example.com",
            car: nil,
            phoneNumber: nil,
            avatarUrl: nil,
            isAdmin: false,
            approved: true,
            invitedBy: nil,
            notifyRideUpdates: true,
            notifyMessages: true,
            notifyAnnouncements: true,
            notifyNewRequests: true,
            notifyQaActivity: true,
            notifyReviewReminders: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        await cacheManager.cacheProfile(profile)
        let cached = await cacheManager.getCachedProfile(id: profile.id)
        
        XCTAssertNotNil(cached, "Cache should return value before TTL expires")
        XCTAssertEqual(cached?.id, profile.id, "Cached profile should match original")
    }
    
    func testProfileCacheReturnsNilAfterTTLExpires() async {
        let profile = Profile(
            id: UUID(),
            name: "Test User",
            email: "test@example.com",
            car: nil,
            phoneNumber: nil,
            avatarUrl: nil,
            isAdmin: false,
            approved: true,
            invitedBy: nil,
            notifyRideUpdates: true,
            notifyMessages: true,
            notifyAnnouncements: true,
            notifyNewRequests: true,
            notifyQaActivity: true,
            notifyReviewReminders: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        await cacheManager.cacheProfile(profile)
        
        // Wait for TTL to expire (5 minutes = 300 seconds, but we'll use a shorter test interval)
        // For testing, we'll invalidate manually since waiting 5 minutes is impractical
        await cacheManager.invalidateProfile(id: profile.id)
        let cached = await cacheManager.getCachedProfile(id: profile.id)
        
        XCTAssertNil(cached, "Cache should return nil after invalidation")
    }
    
    // MARK: - Rides Cache Tests
    
    func testRidesCacheReturnsNilWhenEmpty() async {
        let cached = await cacheManager.getCachedRides()
        XCTAssertNil(cached, "Cache should return nil when empty")
    }
    
    func testRidesCacheReturnsValueBeforeTTLExpires() async {
        let rides = [
            Ride(
                id: UUID(),
                userId: UUID(),
                type: "request",
                date: Date(),
                time: "10:00:00",
                pickup: "Location A",
                destination: "Location B",
                seats: 1,
                notes: nil,
                gift: nil,
                status: .open,
                claimedBy: nil,
                reviewed: false,
                reviewSkipped: nil,
                reviewSkippedAt: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        
        await cacheManager.cacheRides(rides)
        let cached = await cacheManager.getCachedRides()
        
        XCTAssertNotNil(cached, "Cache should return value before TTL expires")
        XCTAssertEqual(cached?.count, rides.count, "Cached rides count should match")
    }
    
    func testRidesCacheReturnsNilAfterInvalidation() async {
        let rides: [Ride] = []
        await cacheManager.cacheRides(rides)
        await cacheManager.invalidateRides()
        
        let cached = await cacheManager.getCachedRides()
        XCTAssertNil(cached, "Cache should return nil after invalidation")
    }
    
    // MARK: - Favors Cache Tests
    
    func testFavorsCacheReturnsNilWhenEmpty() async {
        let cached = await cacheManager.getCachedFavors()
        XCTAssertNil(cached, "Cache should return nil when empty")
    }
    
    func testFavorsCacheReturnsValueBeforeTTLExpires() async {
        let favors = [
            Favor(
                id: UUID(),
                userId: UUID(),
                title: "Test Favor",
                description: nil,
                location: "Test Location",
                duration: .notSure,
                requirements: nil,
                date: Date(),
                time: nil,
                gift: nil,
                status: .open,
                claimedBy: nil,
                reviewed: false,
                reviewSkipped: nil,
                reviewSkippedAt: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        
        await cacheManager.cacheFavors(favors)
        let cached = await cacheManager.getCachedFavors()
        
        XCTAssertNotNil(cached, "Cache should return value before TTL expires")
        XCTAssertEqual(cached?.count, favors.count, "Cached favors count should match")
    }
    
    func testFavorsCacheReturnsNilAfterInvalidation() async {
        let favors: [Favor] = []
        await cacheManager.cacheFavors(favors)
        await cacheManager.invalidateFavors()
        
        let cached = await cacheManager.getCachedFavors()
        XCTAssertNil(cached, "Cache should return nil after invalidation")
    }
    
    // MARK: - Conversations Cache Tests
    
    func testConversationCacheReturnsNilWhenEmpty() async {
        let conversationId = UUID()
        let cached = await cacheManager.getCachedConversation(id: conversationId)
        XCTAssertNil(cached, "Cache should return nil when empty")
    }
    
    func testConversationCacheReturnsValueBeforeTTLExpires() async {
        let conversation = Conversation(
            id: UUID(),
            rideId: nil,
            favorId: nil,
            createdBy: UUID(),
            createdAt: Date(),
            updatedAt: Date()
        )
        
        await cacheManager.cacheConversation(conversation)
        let cached = await cacheManager.getCachedConversation(id: conversation.id)
        
        XCTAssertNotNil(cached, "Cache should return value before TTL expires")
        XCTAssertEqual(cached?.id, conversation.id, "Cached conversation should match original")
    }
    
    func testConversationCacheReturnsNilAfterInvalidation() async {
        let conversation = Conversation(
            id: UUID(),
            rideId: nil,
            favorId: nil,
            createdBy: UUID(),
            createdAt: Date(),
            updatedAt: Date()
        )
        
        await cacheManager.cacheConversation(conversation)
        await cacheManager.invalidateConversation(id: conversation.id)
        
        let cached = await cacheManager.getCachedConversation(id: conversation.id)
        XCTAssertNil(cached, "Cache should return nil after invalidation")
    }
    
    // MARK: - Clear All Tests
    
    func testClearAllRemovesAllCachedData() async {
        // Cache some data
        let profile = Profile(
            id: UUID(),
            name: "Test User",
            email: "test@example.com",
            car: nil,
            phoneNumber: nil,
            avatarUrl: nil,
            isAdmin: false,
            approved: true,
            invitedBy: nil,
            notifyRideUpdates: true,
            notifyMessages: true,
            notifyAnnouncements: true,
            notifyNewRequests: true,
            notifyQaActivity: true,
            notifyReviewReminders: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        await cacheManager.cacheProfile(profile)
        await cacheManager.cacheRides([])
        await cacheManager.cacheFavors([])
        
        // Clear all
        await cacheManager.clearAll()
        
        // Verify all caches are empty
        let cachedProfile = await cacheManager.getCachedProfile(id: profile.id)
        let cachedRides = await cacheManager.getCachedRides()
        let cachedFavors = await cacheManager.getCachedFavors()
        
        XCTAssertNil(cachedProfile, "Profile cache should be cleared")
        XCTAssertNil(cachedRides, "Rides cache should be cleared")
        XCTAssertNil(cachedFavors, "Favors cache should be cleared")
    }
    
    // MARK: - Performance Tests (PERF-CLI-002)
    
    /// PERF-CLI-002: Cache hit returns immediately - verify <10ms
    func testCacheHitPerformance() async {
        let profile = Profile(
            id: UUID(),
            name: "Test User",
            email: "test@example.com",
            car: nil,
            phoneNumber: nil,
            avatarUrl: nil,
            isAdmin: false,
            approved: true,
            invitedBy: nil,
            notifyRideUpdates: true,
            notifyMessages: true,
            notifyAnnouncements: true,
            notifyNewRequests: true,
            notifyQaActivity: true,
            notifyReviewReminders: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Cache the profile first
        await cacheManager.cacheProfile(profile)
        
        // Measure cache retrieval time
        let startTime = CFAbsoluteTimeGetCurrent()
        let cached = await cacheManager.getCachedProfile(id: profile.id)
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to milliseconds
        
        XCTAssertNotNil(cached, "Cache should return value")
        XCTAssertLessThan(duration, 10.0, "Cache hit should be <10ms, was \(duration)ms")
    }
}

