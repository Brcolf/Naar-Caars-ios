//
//  BlockedUsersViewModel.swift
//  NaarsCars
//
//  View model for the blocked users settings screen
//

import Foundation
internal import Combine

/// Loads and unblocks the current user's blocked users
@MainActor
final class BlockedUsersViewModel: ObservableObject {
    @Published var blockedUsers: [BlockedUser] = []
    @Published var isLoading = true
    @Published var error: String?

    private let messageService: any MessageServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.messageService = messageService
        self.authService = authService
    }

    func loadBlockedUsers() async {
        guard let userId = authService.currentUserId else {
            isLoading = false
            return
        }

        do {
            blockedUsers = try await messageService.getBlockedUsers(userId: userId)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func unblockUser(_ blockedUser: BlockedUser) async {
        guard let userId = authService.currentUserId else { return }

        do {
            try await messageService.unblockUser(blockerId: userId, blockedId: blockedUser.blockedId)

            // Remove from local list
            blockedUsers.removeAll { $0.blockedId == blockedUser.blockedId }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
