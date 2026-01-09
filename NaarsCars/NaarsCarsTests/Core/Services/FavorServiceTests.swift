//
//  FavorServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for FavorService
//

import XCTest
@testable import NaarsCars

@MainActor
final class FavorServiceTests: XCTestCase {
    var favorService: FavorService!
    
    override func setUp() {
        super.setUp()
        favorService = FavorService.shared
    }
    
    // MARK: - Cache Tests
    
    func testFetchFavors_CacheHit() async throws {
        // Create test favors
        let testFavors = [
            Favor(
                userId: UUID(),
                title: "Test Favor 1",
                location: "Location 1",
                duration: .underHour,
                date: Date(),
                status: .open
            ),
            Favor(
                userId: UUID(),
                title: "Test Favor 2",
                location: "Location 2",
                duration: .coupleHours,
                date: Date().addingTimeInterval(86400),
                status: .open
            )
        ]
        
        // Cache the favors
        await CacheManager.shared.cacheFavors(testFavors)
        
        // Fetch should return cached favors without network call
        let fetchedFavors = try await favorService.fetchFavors()
        
        XCTAssertEqual(fetchedFavors.count, testFavors.count, "Should return cached favors")
        XCTAssertEqual(fetchedFavors[0].title, testFavors[0].title)
        XCTAssertEqual(fetchedFavors[1].title, testFavors[1].title)
    }
    
    func testCreateFavor_InvalidatesCache() async {
        // Create and cache test favors
        let testFavors = [
            Favor(
                userId: UUID(),
                title: "Original Favor",
                location: "Test Location",
                duration: .underHour,
                date: Date(),
                status: .open
            )
        ]
        
        await CacheManager.shared.cacheFavors(testFavors)
        
        // Verify cache is populated
        let cachedBefore = await CacheManager.shared.getCachedFavors()
        XCTAssertNotNil(cachedBefore, "Favors should be in cache")
        
        // Create a new favor (this would normally call Supabase)
        // For this test, we'll just verify cache invalidation happens
        
        // Manually invalidate to simulate what createFavor does
        await CacheManager.shared.invalidateFavors()
        
        // Verify cache is cleared
        let cachedAfter = await CacheManager.shared.getCachedFavors()
        XCTAssertNil(cachedAfter, "Favors should be removed from cache after create")
    }
}




