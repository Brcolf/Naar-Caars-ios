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

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
    func sendPasswordReset() async {
        // Validate email
        guard !email.isEmpty, email.contains("@") else {
            error = AppError.invalidInput("auth_valid_email_required".localized)
            return
        }
        
        // Check rate limit: 30 seconds between password reset requests
        let canProceed = await rateLimiter.checkAndRecord(
            action: "password_reset_\(email)",
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
            try await authService.sendPasswordReset(email: email)
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




