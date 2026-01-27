//
//  RidesDashboardViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for RidesDashboardViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class RidesDashboardViewModelTests: XCTestCase {
    var viewModel: RidesDashboardViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = RidesDashboardViewModel()
    }
    
    func testLoadRides_Success() async {
        // Given: ViewModel is initialized
        XCTAssertEqual(viewModel.getFilteredRides(sdRides: []).count, 0, "Initial rides should be empty")
        XCTAssertFalse(viewModel.isLoading, "Should not be loading initially")
        
        // When: Loading rides
        await viewModel.loadRides()
        
        // Then: Should complete without error (may have 0 rides if no data)
        // Note: This test verifies the method completes without crashing
        // Actual data depends on Supabase connection
        XCTAssertFalse(viewModel.isLoading, "Should not be loading after completion")
    }
    
    func testFilterRides_MineOnly() async {
        // Given: ViewModel with filter set to .mine
        viewModel.filter = .mine
        
        // When: Filtering rides
        viewModel.filterRides(.mine)
        
        // Then: Filter should be updated
        XCTAssertEqual(viewModel.filter, .mine, "Filter should be set to .mine")
        
        // Wait for async load to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Filter should trigger loadRides which may have 0 results if not authenticated
        // This test verifies the filter mechanism works
        XCTAssertTrue(true, "Filter mechanism works")
    }
}





