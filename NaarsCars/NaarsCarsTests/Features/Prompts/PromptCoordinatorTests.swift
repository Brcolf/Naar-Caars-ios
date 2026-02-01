import XCTest
@testable import NaarsCars

@MainActor
final class PromptCoordinatorTests: XCTestCase {
    func testCheckForPendingPromptsShowsOldest() async {
        let completion = CompletionPrompt(
            id: UUID(), reminderId: UUID(), requestType: .ride,
            requestId: UUID(), requestTitle: "Ride", dueAt: Date(timeIntervalSince1970: 100)
        )
        let review = ReviewPrompt(
            id: UUID(), requestType: .favor, requestId: UUID(),
            requestTitle: "Favor", fulfillerId: UUID(), fulfillerName: "Sam",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let coordinator = PromptCoordinator(
            completionProvider: StubCompletionProvider(prompts: [completion]),
            reviewProvider: StubReviewProvider(prompts: [review]),
            sideEffects: StubPromptSideEffects()
        )

        await coordinator.checkForPendingPrompts(userId: UUID())
        XCTAssertEqual(coordinator.activePrompt, .completion(completion))
    }

    func testReviewPromptMarksNotificationsOnShow() async {
        let review = ReviewPrompt(
            id: UUID(), requestType: .ride, requestId: UUID(),
            requestTitle: "Ride", fulfillerId: UUID(), fulfillerName: "Sam",
            createdAt: Date()
        )
        let sideEffects = StubPromptSideEffects()
        let coordinator = PromptCoordinator(
            completionProvider: StubCompletionProvider(prompts: []),
            reviewProvider: StubReviewProvider(prompts: [review]),
            sideEffects: sideEffects
        )

        await coordinator.checkForPendingPrompts(userId: UUID())
        XCTAssertEqual(sideEffects.reviewReads.count, 1)
    }

    func testCompletionPromptMarksNotificationsAfterAction() async throws {
        let completion = CompletionPrompt(
            id: UUID(), reminderId: UUID(), requestType: .ride,
            requestId: UUID(), requestTitle: "Ride", dueAt: Date()
        )
        let sideEffects = StubPromptSideEffects()
        let coordinator = PromptCoordinator(
            completionProvider: StubCompletionProvider(prompts: [completion]),
            reviewProvider: StubReviewProvider(prompts: []),
            sideEffects: sideEffects
        )

        await coordinator.checkForPendingPrompts(userId: UUID())
        XCTAssertEqual(sideEffects.completionReads.count, 0)
        try await coordinator.handleCompletionResponse(completed: true)
        XCTAssertEqual(sideEffects.completionReads.count, 1)
    }

    func testCheckForPendingPromptsDoesNotRequeueActivePrompt() async throws {
        let completion = CompletionPrompt(
            id: UUID(), reminderId: UUID(), requestType: .ride,
            requestId: UUID(), requestTitle: "Ride", dueAt: Date()
        )
        let sideEffects = StubPromptSideEffects()
        let coordinator = PromptCoordinator(
            completionProvider: StubCompletionProvider(prompts: [completion]),
            reviewProvider: StubReviewProvider(prompts: []),
            sideEffects: sideEffects
        )

        await coordinator.checkForPendingPrompts(userId: UUID())
        // Refresh while active prompt is showing
        await coordinator.checkForPendingPrompts(userId: UUID())
        // Completing should not re-show the same prompt
        try await coordinator.handleCompletionResponse(completed: true)
        XCTAssertNil(coordinator.activePrompt)
    }
}

private final class StubCompletionProvider: CompletionPromptProviding {
    let prompts: [CompletionPrompt]
    init(prompts: [CompletionPrompt]) { self.prompts = prompts }
    func fetchDueCompletionPrompts(userId: UUID) async throws -> [CompletionPrompt] { prompts }
    func fetchCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> CompletionPrompt? {
        prompts.first { $0.requestId == requestId }
    }
}

private final class StubReviewProvider: ReviewPromptProviding {
    let prompts: [ReviewPrompt]
    init(prompts: [ReviewPrompt]) { self.prompts = prompts }
    func fetchPendingReviewPrompts(userId: UUID) async throws -> [ReviewPrompt] { prompts }
    func fetchReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> ReviewPrompt? {
        prompts.first { $0.requestId == requestId }
    }
}

@MainActor
private final class StubPromptSideEffects: PromptSideEffects {
    var reviewReads: [(RequestType, UUID)] = []
    var completionReads: [(RequestType, UUID)] = []
    func markReviewNotificationsRead(requestType: RequestType, requestId: UUID) async {
        reviewReads.append((requestType, requestId))
    }
    func markCompletionNotificationsRead(requestType: RequestType, requestId: UUID) async {
        completionReads.append((requestType, requestId))
    }
    func refreshBadges(reason: String) async {}
    func sendCompletionResponse(reminderId: UUID, completed: Bool) async throws {}
}
