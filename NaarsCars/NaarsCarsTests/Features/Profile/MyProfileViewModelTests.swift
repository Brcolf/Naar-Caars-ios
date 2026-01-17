//
//  MyProfileViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for MyProfileViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class MyProfileViewModelTests: XCTestCase {
    var viewModel: MyProfileViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = MyProfileViewModel()
    }
    
    func testLoadProfile_Success_SetsAllProperties() async {
        // This test requires a real Supabase connection or mocked service
        // For now, we'll test the structure
        
        let testUserId = UUID()
        
        // Load profile (will attempt network call)
        await viewModel.loadProfile(userId: testUserId)
        
        // Verify loading state changes
        // In a successful case, isLoading should be false after loading
        // Note: This test may need mocking for reliable results
        
        // Verify properties are accessible
        XCTAssertNotNil(viewModel.profile)
        XCTAssertNotNil(viewModel.reviews)
        XCTAssertNotNil(viewModel.inviteCodes)
    }
    
    func testGenerateInviteCode_RateLimited_ThrowsError() async {
        let testUserId = UUID()
        
        // Generate first code (should succeed)
        await viewModel.generateInviteCode(userId: testUserId)
        
        // Immediately try to generate another (should be rate limited)
        await viewModel.generateInviteCode(userId: testUserId)
        
        // Verify error is set
        // Note: Rate limiter uses 10 second interval, so second call should fail
        // In a real test, you'd verify the error type
        XCTAssertNotNil(viewModel.error, "Rate limited generation should set error")
    }
}

