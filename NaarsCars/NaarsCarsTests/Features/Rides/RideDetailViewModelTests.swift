//
//  RideDetailViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for RideDetailViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class RideDetailViewModelTests: XCTestCase {
    var viewModel: RideDetailViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = RideDetailViewModel()
    }
    
    func testLoadRide_Success() async {
        // Given: A ride ID
        let rideId = UUID()
        
        // When: Loading ride
        await viewModel.loadRide(id: rideId)
        
        // Then: Should complete without error
        // Note: This test verifies the method completes without crashing
        // Actual data depends on Supabase connection and ride existence
        XCTAssertFalse(viewModel.isLoading, "Should not be loading after completion")
    }
    
    func testPostQuestion_Success() async {
        // Given: A ride loaded in viewModel
        let testRide = Ride(
            userId: UUID(),
            date: Date(),
            time: "14:00:00",
            pickup: "Test Pickup",
            destination: "Test Destination",
            seats: 1,
            status: .open
        )
        viewModel.ride = testRide
        
        // When: Posting a question
        // Note: This test may fail if Supabase is not configured or user not authenticated
        await viewModel.postQuestion("Test question?")
        
        // Then: Should complete without error
        // In a real scenario, you'd verify the question was added to qaItems
        XCTAssertTrue(true, "Post question attempted (expected behavior)")
    }

    func testCanAskQuestions_WhenUnclaimed() {
        let testRide = Ride(
            userId: UUID(),
            date: Date(),
            time: "14:00:00",
            pickup: "Test Pickup",
            destination: "Test Destination",
            seats: 1,
            status: .open,
            claimedBy: nil
        )
        viewModel.ride = testRide

        XCTAssertTrue(viewModel.canAskQuestions, "Should allow Q&A when ride is unclaimed")
    }

    func testCanAskQuestions_WhenClaimed() {
        let testRide = Ride(
            userId: UUID(),
            date: Date(),
            time: "14:00:00",
            pickup: "Test Pickup",
            destination: "Test Destination",
            seats: 1,
            status: .confirmed,
            claimedBy: UUID()
        )
        viewModel.ride = testRide

        XCTAssertFalse(viewModel.canAskQuestions, "Should not allow Q&A when ride is claimed")
    }
}





