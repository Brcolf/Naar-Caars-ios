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
}
