// NaarsCars/Features/Prompts/PromptCoordinator.swift
import Foundation
internal import Combine

protocol CompletionPromptProviding {
    func fetchDueCompletionPrompts(userId: UUID) async throws -> [CompletionPrompt]
    func fetchCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> CompletionPrompt?
}

protocol ReviewPromptProviding {
    func fetchPendingReviewPrompts(userId: UUID) async throws -> [ReviewPrompt]
    func fetchReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> ReviewPrompt?
}

@MainActor
protocol PromptSideEffects {
    func markReviewNotificationsRead(requestType: RequestType, requestId: UUID) async
    func markCompletionNotificationsRead(requestType: RequestType, requestId: UUID) async
    func refreshBadges(reason: String) async
    func sendCompletionResponse(reminderId: UUID, completed: Bool) async throws
}

@MainActor
final class PromptCoordinator: ObservableObject {
    static let shared = PromptCoordinator(
        completionProvider: CompletionPromptProvider(),
        reviewProvider: ReviewPromptProvider(),
        sideEffects: DefaultPromptSideEffects()
    )

    @Published var activePrompt: PromptItem?

    private var queue = PromptQueue()
    private let completionProvider: CompletionPromptProviding
    private let reviewProvider: ReviewPromptProviding
    private let sideEffects: PromptSideEffects

    init(
        completionProvider: CompletionPromptProviding,
        reviewProvider: ReviewPromptProviding,
        sideEffects: PromptSideEffects
    ) {
        self.completionProvider = completionProvider
        self.reviewProvider = reviewProvider
        self.sideEffects = sideEffects
    }

    func checkForPendingPrompts(userId: UUID) async {
        do {
            let activePromptId = activePrompt?.id
            let completion = try await completionProvider.fetchDueCompletionPrompts(userId: userId)
            let reviews = try await reviewProvider.fetchPendingReviewPrompts(userId: userId)
            queue = PromptQueue()
            completion.forEach { 
                if $0.id != activePromptId {
                    queue.enqueue(.completion($0))
                }
            }
            reviews.forEach { 
                if $0.id != activePromptId {
                    queue.enqueue(.review($0))
                }
            }
            await activateNextPromptIfNeeded()
        } catch {
            print("❌ [PromptCoordinator] Failed to load prompts: \(error.localizedDescription)")
        }
    }

    func enqueueCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async {
        if let prompt = try? await completionProvider.fetchCompletionPrompt(
            requestType: requestType, requestId: requestId, userId: userId
        ) {
            if activePrompt?.id == prompt.id {
                return
            }
            queue.enqueue(.completion(prompt))
            await activateNextPromptIfNeeded()
        }
    }

    func enqueueReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async {
        if let prompt = try? await reviewProvider.fetchReviewPrompt(
            requestType: requestType, requestId: requestId, userId: userId
        ) {
            if activePrompt?.id == prompt.id {
                return
            }
            queue.enqueue(.review(prompt))
            await activateNextPromptIfNeeded()
        }
    }

    func handleCompletionResponse(completed: Bool) async throws {
        guard case .completion(let prompt) = activePrompt else { return }
        try await sideEffects.sendCompletionResponse(reminderId: prompt.reminderId, completed: completed)
        await sideEffects.markCompletionNotificationsRead(requestType: prompt.requestType, requestId: prompt.requestId)
        await sideEffects.refreshBadges(reason: "completionPromptAction")
        activePrompt = nil
        await activateNextPromptIfNeeded()
    }

    func finishReviewPrompt() async {
        activePrompt = nil
        await activateNextPromptIfNeeded()
    }

    private func activateNextPromptIfNeeded() async {
        guard activePrompt == nil else { return }
        guard let next = queue.dequeue() else { return }
        activePrompt = next
        if case .review(let prompt) = next {
            await sideEffects.markReviewNotificationsRead(requestType: prompt.requestType, requestId: prompt.requestId)
            await sideEffects.refreshBadges(reason: "reviewPromptShown")
        }
    }
}
