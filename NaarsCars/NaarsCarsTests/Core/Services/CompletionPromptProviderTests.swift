import XCTest
@testable import NaarsCars

@MainActor
final class CompletionPromptProviderTests: XCTestCase {
    func testFetchDueCompletionPrompts_DoesNotThrow() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        let provider = CompletionPromptProvider()
        let prompts = try await provider.fetchDueCompletionPrompts(userId: userId)
        XCTAssertNotNil(prompts)
    }
}
