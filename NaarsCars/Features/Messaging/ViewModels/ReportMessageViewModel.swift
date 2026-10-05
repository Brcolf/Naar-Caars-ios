//
//  ReportMessageViewModel.swift
//  NaarsCars
//
//  View model for the message report sheet (block-from-report action)
//

import Foundation
internal import Combine

/// Blocks the sender of a reported message on behalf of ReportMessageSheet
@MainActor
final class ReportMessageViewModel: ObservableObject {
    @Published var blockError: String?

    private let messageService: any MessageServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.messageService = messageService
        self.authService = authService
    }

    /// Block `userId`. Sets `blockError` (localized) on failure or when not signed in.
    func blockUser(_ userId: UUID) async {
        guard let currentUserId = authService.currentUserId else {
            blockError = "messaging_must_be_signed_in_to_block".localized
            return
        }
        do {
            try await messageService.blockUser(
                blockerId: currentUserId,
                blockedId: userId,
                reason: "Blocked from message report"
            )
        } catch {
            blockError = "messaging_unable_to_block_user".localized
        }
    }
}
