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

    private let messageService: any MessageServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.messageService = messageService
        self.authService = authService
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
            }
            return true
        } catch {
            submitError = error.localizedDescription
            isSubmitting = false
            return false
        }
    }
}
