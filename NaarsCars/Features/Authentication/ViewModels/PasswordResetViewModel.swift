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
    
    private let authService = AuthService.shared
    private let rateLimiter = RateLimiter.shared
    
    func sendPasswordReset() async {
        // Validate email
        guard !email.isEmpty, email.contains("@") else {
            error = AppError.invalidInput("Valid email is required")
            return
        }
        
        // Check rate limit: 30 seconds between password reset requests
        let canProceed = await rateLimiter.checkAndRecord(
            action: "password_reset_\(email)",
            minimumInterval: 30.0
        )
        
        guard canProceed else {
            error = AppError.rateLimited
            return
        }
        
        isLoading = true
        error = nil
        successMessage = nil
        
        do {
            try await authService.sendPasswordReset(email: email)
            // ALWAYS show same success message regardless of email existence (prevent enumeration)
            successMessage = "If an account exists with this email, you'll receive a password reset link."
        } catch {
            // Catch and ignore errors - never reveal if email exists
            // Still show success message to prevent enumeration
            successMessage = "If an account exists with this email, you'll receive a password reset link."
        }
        
        isLoading = false
    }
}


