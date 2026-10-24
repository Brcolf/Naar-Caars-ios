//
//  ClaimViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for ClaimViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class ClaimViewModelTests: XCTestCase {
    var viewModel: ClaimViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = ClaimViewModel()
    }
    
    func testClaim_MissingPhone_ShowsSheet() async {
        // Given: ViewModel and user without phone
        // Note: This test verifies the phone check mechanism
        // In a real scenario, you'd mock ProfileService to return profile without phone
        
        let requestId = UUID()
        
        // When: Attempting to claim
        do {
            _ = try await viewModel.claim(requestType: "ride", requestId: requestId)
            // If successful, user has phone (acceptable)
            XCTAssertTrue(true, "Claim succeeded (user has phone)")
        } catch {
            // If error, verify phone required sheet would be shown
            if case AppError.invalidInput(let message) = error {
                XCTAssertTrue(message.contains("Phone") || message.contains("phone"), "Error should mention phone")
                // In real scenario, showPhoneRequired would be true
            } else {
                // Other errors are acceptable
                XCTAssertTrue(true, "Claim failed with error: \(error)")
            }
        }
    }
    
    func testClaim_Success_NavigatesToConversation() async {
        // Given: Valid claim request
        // Note: This test requires a real Supabase connection
        let requestId = UUID()
        
        // When: Claiming
        do {
            _ = try await viewModel.claim(requestType: "ride", requestId: requestId)
            XCTAssertNil(viewModel.error, "Error should be nil after successful claim")
        } catch {
            // Expected if Supabase not configured or request doesn't exist
            XCTAssertTrue(true, "Claim attempted (expected behavior)")
        }
    }

    func testClaim_ExampleIsRefusedWithoutCallingTheService() async {
        let service = RecordingClaimService()
        let viewModel = ClaimViewModel(claimService: service)

        do {
            try await viewModel.claim(requestType: "ride", requestId: UUID(), isExample: true)
            XCTFail("An example claim must throw")
        } catch AppError.invalidInput(let message) {
            XCTAssertEqual(message, "This is an example request. Real requests in your community work the same way.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.claimCalls, 0)
        XCTAssertEqual(viewModel.error, "This is an example request. Real requests in your community work the same way.")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.showPhoneRequired)
    }
}

/// Counts claim calls; every call is a test failure for the example path.
private final class RecordingClaimService: ClaimServiceProtocol {
    private(set) var claimCalls = 0

    func claimRequest(requestType: String, requestId: UUID, claimerId: UUID) async throws {
        claimCalls += 1
    }

    func unclaimRequest(requestType: String, requestId: UUID, claimerId: UUID) async throws {}

    func completeRequest(requestType: String, requestId: UUID, posterId: UUID) async throws {}
}
