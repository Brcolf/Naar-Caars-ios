import XCTest
@testable import NaarsCars

@MainActor
final class ReviewPromptProviderTests: XCTestCase {
    func testFetchPendingReviewPrompts_DoesNotThrow() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        let provider = ReviewPromptProvider()
        let prompts = try await provider.fetchPendingReviewPrompts(userId: userId)
        XCTAssertNotNil(prompts)
    }

    func testExpiredReviewNotificationIsMarkedRead() async throws {
        let userId = UUID()
        let rideId = UUID()
        let fulfillerId = UUID()

        var marked: [(String, UUID)] = []
        var refreshed: [String] = []

        let dependencies = ReviewPromptDependencies(
            fetchNotifications: { _, _ in
                [AppNotification(userId: userId, type: .reviewRequest, title: "Review", rideId: rideId)]
            },
            markReviewRequestAsRead: { requestType, requestId in
                marked.append((requestType, requestId))
            },
            refreshBadges: { reason in
                refreshed.append(reason)
            },
            fetchRide: { _ in
                Ride(
                    userId: userId,
                    date: Date(),
                    time: "9:00",
                    pickup: "A",
                    destination: "B",
                    claimedBy: fulfillerId
                )
            },
            fetchFavor: { _ in
                Favor(
                    userId: userId,
                    title: "Favor",
                    location: "Somewhere",
                    date: Date()
                )
            },
            fetchProfile: { _ in
                Profile(id: fulfillerId, name: "Sam", email: "sam@example.com")
            },
            canStillReview: { _, _ in false }
        )

        let provider = ReviewPromptProvider(dependencies: dependencies)
        let prompts = try await provider.fetchPendingReviewPrompts(userId: userId)

        XCTAssertTrue(prompts.isEmpty)
        XCTAssertEqual(marked.count, 1)
        XCTAssertEqual(marked.first?.0, RequestType.ride.rawValue)
        XCTAssertEqual(marked.first?.1, rideId)
        XCTAssertEqual(refreshed.count, 1)
    }
}
