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
    
    func testLoadProfile_Success_SetsAllProperties() async throws {
        // loadProfile fetches through the live ProfileService (`profiles` / `public_profiles`
        // with `.single()`), so it can only succeed for a user that exists on the backend.
        // A random UUID always makes fetchProfile throw and leaves `profile` nil.
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing: loadProfile needs a live Supabase session and an existing profile row")
        }

        await viewModel.loadProfile(userId: userId)

        XCTAssertNil(viewModel.error, "loadProfile should not surface an error for the signed-in user")
        XCTAssertNotNil(viewModel.profile)
        XCTAssertEqual(viewModel.profile?.id, userId)
        XCTAssertFalse(viewModel.isLoading)
    }
}





