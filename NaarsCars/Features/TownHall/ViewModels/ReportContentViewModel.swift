//
//  ReportContentViewModel.swift
//  NaarsCars
//
//  View model for reporting user-generated content
//

import Foundation
internal import Combine

/// Submits content reports for ReportContentSheet
@MainActor
final class ReportContentViewModel: ObservableObject {
    @Published var isSubmitting = false
    @Published var submitError: String?
    @Published var isBlocking = false
    /// Set once the content's author was blocked from this sheet.
    @Published var blockedAuthorId: UUID?
    @Published var blockError: String?

    private let messageService: any MessageServiceProtocol
    private let authService: any AuthServiceProtocol
    /// Finds the Town Hall post that was generated for a review, if any.
    private let reviewPostLookup: (UUID) async -> UUID?

    init(
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        reviewPostLookup: @escaping (UUID) async -> UUID? = { reviewId in
            try? await TownHallService.shared.fetchPostIdForReview(reviewId: reviewId)
        }
    ) {
        self.messageService = messageService
        self.authService = authService
        self.reviewPostLookup = reviewPostLookup
    }

    /// The author of the reported content when the sheet should offer to block them: someone
    /// other than the signed-in user who is not blocked already. A reported profile has its own
    /// Block action on the profile screen.
    func blockableAuthorId(for context: ReportContext) -> UUID? {
        let authorId: UUID
        switch context {
        case .post(_, let id, _), .comment(_, let id, _), .ride(_, let id, _), .favor(_, let id, _), .review(_, let id, _):
            authorId = id
        case .user:
            return nil
        }
        guard authorId != authService.currentUserId else { return nil }
        // Keep the row after blocking from here so it can show the "blocked" state.
        guard blockedAuthorId == authorId || !messageService.isBlocked(authorId) else { return nil }
        return authorId
    }

    /// Block the author of the reported content. Sets `blockedAuthorId` on success and
    /// `blockError` (localized) on failure or when not signed in.
    func blockAuthor(_ authorId: UUID) async {
        guard let currentUserId = authService.currentUserId else {
            blockError = "messaging_must_be_signed_in_to_block".localized
            return
        }
        guard !isBlocking else { return }
        isBlocking = true
        defer { isBlocking = false }
        do {
            try await messageService.blockUser(
                blockerId: currentUserId,
                blockedId: authorId,
                reason: "Blocked from content report"
            )
            blockedAuthorId = authorId
            HapticManager.success()
        } catch {
            blockError = "messaging_unable_to_block_user".localized
        }
    }

    /// Submit a report. Returns true on success; on failure `submitError` is set and false is returned.
    /// `isSubmitting` stays true after success because the sheet is dismissed by the caller.
    func submitReport(context: ReportContext, type: MessageService.ReportType, description: String) async -> Bool {
        guard let currentUserId = authService.currentUserId else { return false }
        isSubmitting = true

        do {
            switch context {
            case .post(let id, let authorId, _):
                try await messageService.reportPost(
                    reporterId: currentUserId,
                    postId: id,
                    authorId: authorId,
                    type: type,
                    description: description.isEmpty ? nil : description
                )
            case .comment(let id, let authorId, _):
                try await messageService.reportComment(
                    reporterId: currentUserId,
                    commentId: id,
                    authorId: authorId,
                    type: type,
                    description: description.isEmpty ? nil : description
                )
            case .ride(let id, let authorId, _):
                try await messageService.reportRide(
                    reporterId: currentUserId,
                    rideId: id,
                    authorId: authorId,
                    type: type,
                    description: description.isEmpty ? nil : description
                )
            case .favor(let id, let authorId, _):
                try await messageService.reportFavor(
                    reporterId: currentUserId,
                    favorId: id,
                    authorId: authorId,
                    type: type,
                    description: description.isEmpty ? nil : description
                )
            case .user(let id, _):
                try await messageService.reportUser(
                    reporterId: currentUserId,
                    reportedUserId: id,
                    type: type,
                    description: description.isEmpty ? nil : description
                )
            case .review(let id, let authorId, let preview):
                // Reports have no review target yet. File against the Town Hall post that was
                // generated for the review, or against the reviewer when there is none, and put
                // the review in the description so a moderator can see what was reported.
                let details = ["Review \(id.uuidString): \(preview)", description]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                if let postId = await reviewPostLookup(id) {
                    try await messageService.reportPost(
                        reporterId: currentUserId,
                        postId: postId,
                        authorId: authorId,
                        type: type,
                        description: details
                    )
                } else {
                    try await messageService.reportUser(
                        reporterId: currentUserId,
                        reportedUserId: authorId,
                        type: type,
                        description: details
                    )
                }
            }
            return true
        } catch {
            submitError = error.localizedDescription
            isSubmitting = false
            return false
        }
    }
}
