//
//  BannedAccountViewModel.swift
//  NaarsCars
//
//  View model for the restricted (banned) account screen
//

import Foundation
import Supabase
internal import Combine

/// Loads the ban reason and performs the only actions a banned user may take:
/// delete the account or sign out.
/// The application and pending-review screens use the same two actions: those users cannot
/// reach Settings either, and account deletion has to be available to them (Guideline 5.1.1(v)).
@MainActor
final class BannedAccountViewModel: ObservableObject {
    @Published var banReason: String?
    @Published var isLoadingReason = true
    @Published var isSigningOut = false
    @Published var isDeletingAccount = false

    private let profileService: any ProfileServiceProtocol
    private let authService: any AuthServiceProtocol
    private let launchManager = AppLaunchManager.shared
    // Starts the path monitor as soon as the application, pending-review or restricted screen
    // appears. Nothing else creates NetworkMonitor.shared before the main tabs, and
    // `isConnected` reads true until its first path update, so the first Refresh Status or
    // failed deletion while offline was reported as if the device were online.
    private let networkMonitor = NetworkMonitor.shared

    /// False while the device has no network path
    var isOnline: Bool { networkMonitor.isConnected }

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
            guard let userId = await SignedInUser.resolveId(authService: authService) else {
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
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        guard let userId = await SignedInUser.resolveId(authService: authService) else { return false }
        do {
            try await profileService.deleteAccount(userId: userId)
            return true
        } catch {
            AppLogger.error("auth", "Error deleting account: \(error.localizedDescription)")
            throw error
        }
    }

    /// Friendly, localized text for a failed deletion. Never the raw system description.
    func deletionFailureMessage(for error: Error) -> String {
        if AuthErrorMessage.isConnectivityFailure(error) {
            return "auth_error_offline".localized
        }
        // The one failure the user can fix alone: they dismissed the Apple confirmation sheet
        let appleConfirmationNeeded = "auth_apple_deletion_requires_signin".localized
        if let appError = error as? AppError,
           case .processingError(let message) = appError,
           message == appleConfirmationNeeded {
            return appleConfirmationNeeded
        }
        return "profile_deletion_failed_message".localized
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

// MARK: - Signed-in user id

/// Resolves the signed-in user's id for the screens shown before the main app
/// (application, pending review, restricted).
enum SignedInUser {
    /// `AuthService.currentUserId` is filled by an in-session sign-in or sign-up and by the
    /// approved-user launch path only. After a cold launch straight into one of these screens
    /// it is nil, so fall back to the stored session; without that, Submit and Delete Account
    /// did nothing after the app was reopened.
    @MainActor
    static func resolveId(authService: any AuthServiceProtocol) async -> UUID? {
        if let userId = authService.currentUserId {
            return userId
        }
        return try? await SupabaseService.shared.client.auth.session.user.id
    }
}
