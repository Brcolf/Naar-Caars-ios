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
    /// Set when the list could not be loaded, so the screen does not claim nobody is blocked
    @Published var error: String?
    /// A failed unblock, for the error banner
    @Published var unblockErrorMessage: String?

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

        // Show the spinner again on a retry; a reload with rows on screen stays quiet.
        if blockedUsers.isEmpty {
            isLoading = true
        }
        error = nil

        do {
            blockedUsers = try await messageService.getBlockedUsers(userId: userId)
            isLoading = false
        } catch {
            self.error = "settings_blocked_users_load_failed".localized
            isLoading = false
            AppLogger.error("profile", "Failed to load blocked users: \(error.localizedDescription)")
        }
    }

    func unblockUser(_ blockedUser: BlockedUser) async {
        guard let userId = authService.currentUserId else { return }
        unblockErrorMessage = nil

        do {
            try await messageService.unblockUser(blockerId: userId, blockedId: blockedUser.blockedId)

            // Remove from local list
            blockedUsers.removeAll { $0.blockedId == blockedUser.blockedId }
        } catch {
            // The row stays, so say why: this screen is the only place to unblock someone.
            unblockErrorMessage = "settings_unblock_failed".localized(with: blockedUser.blockedName)
            HapticManager.error()
            AppLogger.error("profile", "Failed to unblock user: \(error.localizedDescription)")
        }
    }
}
