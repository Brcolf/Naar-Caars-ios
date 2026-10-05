//
//  BannedAccountViewModel.swift
//  NaarsCars
//
//  View model for the restricted (banned) account screen
//

import Foundation
internal import Combine

/// Loads the ban reason and performs the only actions a banned user may take:
/// delete the account or sign out.
@MainActor
final class BannedAccountViewModel: ObservableObject {
    @Published var banReason: String?
    @Published var isLoadingReason = true
    @Published var isSigningOut = false
    @Published var isDeletingAccount = false

    private let profileService: any ProfileServiceProtocol
    private let authService: any AuthServiceProtocol
    private let launchManager = AppLaunchManager.shared

    init(
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.profileService = profileService
        self.authService = authService
    }

    // MARK: - Data Loading

    func loadBanReason() async {
        isLoadingReason = true
        do {
            guard let userId = authService.currentUserId else {
                throw AppError.notAuthenticated
            }
            banReason = try await profileService.fetchBanReason(userId: userId)
        } catch {
            AppLogger.warning("auth", "Failed to load ban reason: \(error.localizedDescription)")
            banReason = nil
        }
        isLoadingReason = false
    }

    // MARK: - Actions

    /// - Returns: `false` when there is no signed-in user (nothing was attempted), `true` on success
    /// - Throws: Error from the deletion (caller shows the failure alert)
    @discardableResult
    func deleteAccount() async throws -> Bool {
        guard let userId = authService.currentUserId else { return false }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        try await profileService.deleteAccount(userId: userId)
        return true
    }

    func signOut() async {
        isSigningOut = true
        do {
            try await authService.signOut()
            await launchManager.performCriticalLaunch()
        } catch {
            AppLogger.warning("auth", "Error signing out: \(error.localizedDescription)")
            launchManager.state = .ready(.unauthenticated)
        }
        isSigningOut = false
    }
}
