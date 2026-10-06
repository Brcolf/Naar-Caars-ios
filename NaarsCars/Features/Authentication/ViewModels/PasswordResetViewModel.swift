//
//  PasswordResetViewModel.swift
//  NaarsCars
//
//  ViewModel for password reset
//

import Foundation
internal import Combine

/// ViewModel for password reset
@MainActor
final class PasswordResetViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var successMessage: String?
    
    private let authService: any AuthServiceProtocol
    private let rateLimiter = RateLimiter.shared
    // Created with the sheet, not at tap time: the monitor reports "connected" until its
    // first path update arrives (AppleSignInViewModel starts it earlier still).
    private let networkMonitor = NetworkMonitor.shared

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
    /// Friendly, localized text for `error`. Never the raw system description.
    var errorMessage: String? {
        guard let error else { return nil }
        return AuthErrorMessage.text(for: error, fallbackKey: "common_error_occurred")
    }

    func sendPasswordReset() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Validate email
        guard Validators.isValidEmail(trimmedEmail) else {
            error = AppError.invalidInput("auth_valid_email_required".localized)
            return
        }

        // Hiding whether an account exists must not hide a dead connection: the service
        // swallows every failure, so without this check an offline request still "succeeds"
        // and the user waits for an email that was never asked for.
        guard networkMonitor.isConnected else {
            error = AppError.networkUnavailable
            return
        }

        // Check rate limit: 30 seconds between password reset requests
        let canProceed = await rateLimiter.checkAndRecord(
            action: "password_reset_\(trimmedEmail)",
            minimumInterval: Constants.RateLimits.passwordReset
        )

        guard canProceed else {
            error = AppError.rateLimitExceeded("auth_reset_rate_limited".localized)
            return
        }

        isLoading = true
        error = nil
        successMessage = nil

        do {
            try await authService.sendPasswordReset(email: trimmedEmail)
            // ALWAYS show same success message regardless of email existence (prevent enumeration)
            successMessage = "auth_reset_success_message".localized
        } catch {
            // Catch and ignore errors - never reveal if email exists
            // Still show success message to prevent enumeration
            successMessage = "auth_reset_success_message".localized
        }

        isLoading = false
    }
}




