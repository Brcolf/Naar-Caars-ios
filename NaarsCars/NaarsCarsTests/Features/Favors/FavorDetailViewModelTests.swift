//
//  FavorDetailViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for FavorDetailViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class FavorDetailViewModelTests: XCTestCase {
    var viewModel: FavorDetailViewModel!

    override func setUp() {
        super.setUp()
        viewModel = FavorDetailViewModel()
    }

    func testCanAskQuestions_WhenUnclaimed() {
        let testFavor = Favor(
            userId: UUID(),
            title: "Test Favor",
            description: "Need help",
            status: .open,
            claimedBy: nil
        )
        viewModel.favor = testFavor

        XCTAssertTrue(viewModel.canAskQuestions, "Should allow Q&A when favor is unclaimed")
    }

    func testCanAskQuestions_WhenClaimed() {
        let testFavor = Favor(
            userId: UUID(),
            title: "Test Favor",
            description: "Need help",
            status: .claimed,
            claimedBy: UUID()
        )
        viewModel.favor = testFavor

        XCTAssertFalse(viewModel.canAskQuestions, "Should not allow Q&A when favor is claimed")
    }
}
