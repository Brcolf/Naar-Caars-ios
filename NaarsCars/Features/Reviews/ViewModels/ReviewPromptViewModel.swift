//
//  ReviewPromptViewModel.swift
//  NaarsCars
//
//  View model for the post-completion review prompt sheet
//

import Foundation
internal import Combine

/// Skips a review on behalf of ReviewPromptSheet
@MainActor
final class ReviewPromptViewModel: ObservableObject {
    @Published var error: AppError?

    private let reviewService: any ReviewServiceProtocol

    init(reviewService: any ReviewServiceProtocol = ReviewService.shared) {
        self.reviewService = reviewService
    }

    /// Skip the review for a request. Returns true on success; failures are logged and mirrored into `error`.
    func skipReview(requestType: String, requestId: UUID) async -> Bool {
        do {
            try await reviewService.skipReview(
                requestType: requestType,
                requestId: requestId
            )
            return true
        } catch {
            AppLogger.error("reviews", "Error skipping review: \(error.localizedDescription)")
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
            return false
        }
    }
}
