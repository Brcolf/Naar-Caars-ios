//
//  FavorsDashboardViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for FavorsDashboardViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class FavorsDashboardViewModelTests: XCTestCase {
    var viewModel: FavorsDashboardViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = FavorsDashboardViewModel()
    }
    
    func testLoadFavors_Success() async {
        // Given: ViewModel is initialized
        XCTAssertEqual(viewModel.favors.count, 0, "Initial favors should be empty")
        XCTAssertFalse(viewModel.isLoading, "Should not be loading initially")
        
        // When: Loading favors
        await viewModel.loadFavors()
        
        // Then: Should complete without error (may have 0 favors if no data)
        // Note: This test verifies the method completes without crashing
        // Actual data depends on Supabase connection
        XCTAssertFalse(viewModel.isLoading, "Should not be loading after completion")
    }
}





