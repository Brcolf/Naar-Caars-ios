//
//  PublicProfileViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for PublicProfileViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class PublicProfileViewModelTests: XCTestCase {
    var viewModel: PublicProfileViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = PublicProfileViewModel()
    }
    
    func testLoadProfile_UsesCacheWhenAvailable() async {
        // Create and cache a test profile
        let testProfile = Profile(
            id: UUID(),
            name: "Cached User",
            email: "cached@example.com"
        )
        
        await CacheManager.shared.cacheProfile(testProfile)
        
        // Load profile
        await viewModel.loadProfile(userId: testProfile.id)
        
        // Verify cached profile is used
        XCTAssertEqual(viewModel.profile?.id, testProfile.id)
        XCTAssertEqual(viewModel.profile?.name, testProfile.name)
    }
}




