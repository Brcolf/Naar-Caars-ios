//
//  LeaveReviewViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for LeaveReviewViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class LeaveReviewViewModelTests: XCTestCase {
    func testNavigateToReviewPost_UsesFetchedPostId() async {
        let reviewId = UUID()
        let postId = UUID()
        var navigatedPostId: UUID?

        let viewModel = LeaveReviewViewModel(
            dependencies: makeDependencies(
                fetchReviewPostId: { id in
                    XCTAssertEqual(id, reviewId)
                    return postId
                },
                navigateToTownHall: { id in
                    navigatedPostId = id
                }
            )
        )

        await viewModel.navigateToReviewPost(reviewId: reviewId)

        XCTAssertEqual(navigatedPostId, postId)
    }

    func testNavigateToReviewPost_DoesNotNavigateWhenPostMissing() async {
        let reviewId = UUID()
        var didNavigate = false

        let viewModel = LeaveReviewViewModel(
            dependencies: makeDependencies(
                fetchReviewPostId: { _ in nil },
                navigateToTownHall: { _ in
                    didNavigate = true
                }
            )
        )

        await viewModel.navigateToReviewPost(reviewId: reviewId)

        XCTAssertFalse(didNavigate)
    }

    private func makeDependencies(
        fetchReviewPostId: @escaping (UUID) async -> UUID?,
        navigateToTownHall: @escaping (UUID) -> Void
    ) -> LeaveReviewDependencies {
        LeaveReviewDependencies(
            currentUserId: { UUID() },
            createReview: { requestType, requestId, fulfillerId, reviewerId, rating, comment, _ in
                Review(
                    reviewerId: reviewerId,
                    fulfillerId: fulfillerId,
                    rideId: requestType == "ride" ? requestId : nil,
                    favorId: requestType == "favor" ? requestId : nil,
                    rating: rating,
                    comment: comment
                )
            },
            skipReview: { _, _ in },
            refreshBadges: { _ in },
            fetchReviewPostId: fetchReviewPostId,
            navigateToTownHall: navigateToTownHall
        )
    }
}
