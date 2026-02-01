import XCTest
@testable import NaarsCars

final class PromptModelsTests: XCTestCase {
    func testCompletionPromptSortDateUsesDueAt() {
        let dueAt = Date(timeIntervalSince1970: 123)
        let prompt = CompletionPrompt(
            id: UUID(), reminderId: UUID(), requestType: .ride,
            requestId: UUID(), requestTitle: "Ride", dueAt: dueAt
        )
        XCTAssertEqual(prompt.sortDate, dueAt)
    }

    func testReviewPromptSortDateUsesCreatedAt() {
        let createdAt = Date(timeIntervalSince1970: 456)
        let prompt = ReviewPrompt(
            id: UUID(), requestType: .favor, requestId: UUID(),
            requestTitle: "Favor", fulfillerId: UUID(),
            fulfillerName: "Alex", createdAt: createdAt
        )
        XCTAssertEqual(prompt.sortDate, createdAt)
    }
}
