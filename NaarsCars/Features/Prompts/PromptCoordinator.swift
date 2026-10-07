// NaarsCars/Features/Prompts/PromptCoordinator.swift
import Foundation
import Observation
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

/// Result of attempting to surface a completion prompt for a specific request.
/// Lets the caller decide on a UX fallback (e.g. navigate to the request detail
/// screen) when no due reminder exists for an otherwise-actionable notification.
enum CompletionPromptResult: Equatable {
    case queued            // prompt was enqueued and will be activated
    case alreadyActive     // an identical prompt is already on screen
    case stale             // no matching due reminder; notification cleared
    case failed            // the fetch threw; logged but not retried here
}

@MainActor
@Observable final class PromptCoordinator {
    static let shared = PromptCoordinator(
        completionProvider: CompletionPromptProvider(),
        reviewProvider: ReviewPromptProvider(),
        sideEffects: DefaultPromptSideEffects()
    )

    var activePrompt: PromptItem?

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
            AppLogger.error("prompts", "Failed to load prompts: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func enqueueCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async -> CompletionPromptResult {
        do {
            guard let prompt = try await completionProvider.fetchCompletionPrompt(
                requestType: requestType, requestId: requestId, userId: userId
            ) else {
                // No matching due reminder — the push is stale (already responded, expired,
                // or the request was unclaimed/deleted). Mark the notification read so the
                // bell stops re-firing the same intent. Caller may use `.stale` to navigate
                // the user to the request detail as an action-surface fallback.
                AppLogger.warning("prompts", "enqueueCompletionPrompt: no due reminder requestType=\(requestType) requestId=\(requestId)")
                await sideEffects.markCompletionNotificationsRead(requestType: requestType, requestId: requestId)
                await sideEffects.refreshBadges(reason: "completionPromptStale")
                return .stale
            }
            if activePrompt?.id == prompt.id {
                return .alreadyActive
            }
            queue.enqueue(.completion(prompt))
            AppLogger.info("prompts", "enqueueCompletionPrompt: queued promptId=\(prompt.id)")
            await activateNextPromptIfNeeded()
            return .queued
        } catch {
            AppLogger.error("prompts", "enqueueCompletionPrompt failed requestType=\(requestType) requestId=\(requestId) error=\(error.localizedDescription)")
            return .failed
        }
    }

    func enqueueReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async {
        do {
            guard let prompt = try await reviewProvider.fetchReviewPrompt(
                requestType: requestType, requestId: requestId, userId: userId
            ) else {
                AppLogger.warning("prompts", "enqueueReviewPrompt: no pending review requestType=\(requestType) requestId=\(requestId)")
                return
            }
            if activePrompt?.id == prompt.id {
                return
            }
            queue.enqueue(.review(prompt))
            await activateNextPromptIfNeeded()
        } catch {
            AppLogger.error("prompts", "enqueueReviewPrompt failed requestType=\(requestType) requestId=\(requestId) error=\(error.localizedDescription)")
        }
    }

    func handleCompletionResponse(completed: Bool) async throws {
        guard case .completion(let prompt) = activePrompt else { return }
        try await sideEffects.sendCompletionResponse(reminderId: prompt.reminderId, completed: completed)
        // The answer is stored, so close the cover now; mark-read and the badge refresh follow
        // without holding the screen for two more round trips. Clear only the prompt that was
        // answered, so a repeated call cannot discard a prompt activated in the meantime.
        if activePrompt?.id == prompt.id {
            activePrompt = nil
        }
        await sideEffects.markCompletionNotificationsRead(requestType: prompt.requestType, requestId: prompt.requestId)
        await sideEffects.refreshBadges(reason: "completionPromptAction")
        await activateNextPromptIfNeeded()
    }

    /// Close the completion prompt without answering it. Nothing is sent to the server, so the
    /// reminder stays open and the prompt comes back at the next launch or reminder push.
    /// This is the way out when the answer cannot be sent (no signal right after the ride):
    /// the prompt is a full-screen cover and used to stay up until the app was force-quit.
    /// The next queued prompt is deliberately not shown straight away.
    func dismissCompletionPromptWithoutAnswer() {
        guard case .completion(_) = activePrompt else { return }
        activePrompt = nil
    }

    func finishReviewPrompt() async {
        activePrompt = nil
        await activateNextPromptIfNeeded()
    }

    private func activateNextPromptIfNeeded() async {
        guard activePrompt == nil else { return }
        guard let next = queue.dequeue() else { return }
        activePrompt = next
        switch next {
        case .review(let prompt):
            await sideEffects.markReviewNotificationsRead(requestType: prompt.requestType, requestId: prompt.requestId)
            await sideEffects.refreshBadges(reason: "reviewPromptShown")
        case .completion(let prompt):
            // Mirror the review path so the bell badge clears as soon as the prompt is on
            // screen. The yes/no action separately calls handleCompletionResponse which
            // also marks read — that's idempotent.
            await sideEffects.markCompletionNotificationsRead(requestType: prompt.requestType, requestId: prompt.requestId)
            await sideEffects.refreshBadges(reason: "completionPromptShown")
        }
    }
}
