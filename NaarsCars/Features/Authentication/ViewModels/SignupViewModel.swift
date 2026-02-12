//
//  SignupViewModel.swift
//
//  View model for signup flow with validation logic
//

import Foundation
import SwiftUI
internal import Combine

/// View model for signup flow
/// Handles validation and submission for user registration
@MainActor
final class SignupViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Invite code entered by user
    @Published var inviteCode: String = ""
    
    /// User's name
    @Published var name: String = ""
    
    /// User's email address
    @Published var email: String = ""
    
    /// User's password
    @Published var password: String = ""
    
    /// User's car (optional)
    @Published var car: String = ""
    
    /// Loading state
    @Published var isLoading: Bool = false
    
    /// Current error message
    @Published var errorMessage: String?
    
    /// Validated invite code (set after validation)
    @Published var validatedInviteCode: InviteCode?
    
    // MARK: - Validation Errors
    
    /// Name validation error
    @Published var nameError: String?
    
    /// Email validation error
    @Published var emailError: String?
    
    /// Password validation error
    @Published var passwordError: String?
    
    /// Invite code validation error
    @Published var inviteCodeError: String?
    
    // MARK: - Private Properties
    
    /// Auth service reference
    private let authService: any AuthServiceProtocol

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
    // MARK: - Validation Methods
    
    /// Validate invite code format and check with server
    func validateInviteCode() async -> Bool {
        inviteCodeError = nil
        
        // Normalize and check format
        let normalized = InviteCodeGenerator.normalize(inviteCode)
        
        guard InviteCodeGenerator.isValidFormat(normalized) else {
            inviteCodeError = "signup_error_invalid_code_format".localized
            return false
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let code = try await authService.validateInviteCode(normalized)
            validatedInviteCode = code
            inviteCodeError = nil
            return true
        } catch {
            if let appError = error as? AppError {
                switch appError {
                case .rateLimited:
                    inviteCodeError = "signup_error_rate_limited".localized
                case .invalidInviteCode:
                    inviteCodeError = "signup_error_invalid_or_expired_code".localized
                default:
                    inviteCodeError = appError.errorDescription ?? "signup_error_validation_failed".localized
                }
            } else {
                inviteCodeError = "signup_error_validation_failed_retry".localized
            }
            return false
        }
    }
    
    /// Validate name field
    func validateName() -> Bool {
        nameError = nil
        
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            nameError = "signup_error_name_required".localized
            return false
        }
        
        guard trimmed.count >= 2 else {
            nameError = "signup_error_name_too_short".localized
            return false
        }
        
        return true
    }
    
    /// Validate email field
    func validateEmail() -> Bool {
        emailError = nil
        
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !trimmed.isEmpty else {
            emailError = "signup_error_email_required".localized
            return false
        }
        
        guard Validators.isValidEmail(trimmed) else {
            emailError = "signup_error_email_invalid".localized
            return false
        }
        
        return true
    }
    
    /// Validate password field
    func validatePassword() -> Bool {
        passwordError = nil
        
        guard !password.isEmpty else {
            passwordError = "signup_error_password_required".localized
            return false
        }
        
        guard password.count >= 8 else {
            passwordError = "signup_error_password_too_short".localized
            return false
        }
        
        guard Validators.isValidPassword(password) else {
            passwordError = "signup_error_password_weak".localized
            return false
        }
        
        return true
    }
    
    /// Validate all fields
    func validateAll() -> Bool {
        let nameValid = validateName()
        let emailValid = validateEmail()
        let passwordValid = validatePassword()
        
        return nameValid && emailValid && passwordValid
    }
    
    // MARK: - Signup Method
    
    /// Perform signup with validated data
    func signUp() async throws {
        AppLogger.info("auth", "signUp() called")
        AppLogger.info("auth", "validatedInviteCode: \(validatedInviteCode?.code ?? "nil")")
        
        guard let inviteCode = validatedInviteCode else {
            AppLogger.error("auth", "No validated invite code")
            errorMessage = "signup_error_no_invite_code".localized
            throw AppError.invalidInviteCode
        }
        
        AppLogger.info("auth", "Validating all fields...")
        let isValid = validateAll()
        AppLogger.info("auth", "Validation result: \(isValid)")
        AppLogger.info("auth", "Field errors - name: \(nameError ?? "nil"), email: \(emailError ?? "nil"), password: \(passwordError ?? "nil")")
        
        guard isValid else {
            AppLogger.error("auth", "Validation failed")
            errorMessage = "signup_error_fields_invalid".localized
            throw AppError.requiredFieldMissing
        }
        
        AppLogger.info("auth", "Starting signup process...")
        isLoading = true
        errorMessage = nil
        defer { 
            isLoading = false
            AppLogger.info("auth", "Signup process completed, isLoading set to false")
        }
        
        do {
            try await authService.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                car: car.isEmpty ? nil : car.trimmingCharacters(in: .whitespacesAndNewlines),
                inviteCodeId: inviteCode.id
            )
            HapticManager.success()
        } catch {
            if let appError = error as? AppError {
                switch appError {
                case .emailAlreadyExists:
                    emailError = "signup_error_email_exists".localized
                    errorMessage = appError.errorDescription
                default:
                    errorMessage = appError.errorDescription ?? "signup_error_failed".localized
                }
            } else {
                errorMessage = "signup_error_failed".localized
            }
            throw error
        }
    }
}
