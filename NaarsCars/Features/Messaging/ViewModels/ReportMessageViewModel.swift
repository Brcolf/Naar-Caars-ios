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
    /// True once the sender is blocked (by this sheet, or already when it opened)
    @Published var didBlock = false
    @Published var isBlocking = false

    private let messageService: any MessageServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.messageService = messageService
        self.authService = authService
    }

    /// Seed `didBlock` from the locally cached blocked-user set
    func refreshBlockedStatus(userId: UUID) {
        didBlock = messageService.isBlocked(userId)
    }

    /// Block `userId`. Sets `didBlock` on success, `blockError` (localized) on failure or when not signed in.
    func blockUser(_ userId: UUID) async {
        guard let currentUserId = authService.currentUserId else {
            blockError = "messaging_must_be_signed_in_to_block".localized
            return
        }
        isBlocking = true
        defer { isBlocking = false }
        do {
            try await messageService.blockUser(
                blockerId: currentUserId,
                blockedId: userId,
                reason: "Blocked from message report"
            )
            didBlock = true
        } catch {
            blockError = "messaging_unable_to_block_user".localized
        }
    }
}
