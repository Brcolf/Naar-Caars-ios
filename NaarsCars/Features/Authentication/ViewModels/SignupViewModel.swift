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

    /// User's name
    @Published var name: String = ""

    /// User's email address
    @Published var email: String = ""

    /// User's password
    @Published var password: String = ""

    /// User's password confirmation
    @Published var confirmPassword: String = ""

    /// User's car (optional)
    @Published var car: String = ""

    /// Loading state
    @Published var isLoading: Bool = false

    /// Current error message
    @Published var errorMessage: String?

    // MARK: - Validation Errors

    /// Name validation error
    @Published var nameError: String?

    /// Email validation error
    @Published var emailError: String?

    /// Password validation error
    @Published var passwordError: String?

    /// Confirm password validation error
    @Published var confirmPasswordError: String?
    
    // MARK: - Private Properties
    
    /// Auth service reference
    private let authService: any AuthServiceProtocol

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
    // MARK: - Validation Methods

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

        guard trimmed.count <= 100 else {
            nameError = "signup_error_name_too_long".localized
            return false
        }

        guard Validators.isSafeUserInput(trimmed) else {
            nameError = "signup_error_name_invalid_characters".localized
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

    /// Validate confirm password matches password
    func validateConfirmPassword() -> Bool {
        confirmPasswordError = nil

        guard !confirmPassword.isEmpty else {
            confirmPasswordError = "signup_error_confirm_password_required".localized
            return false
        }

        guard confirmPassword == password else {
            confirmPasswordError = "signup_error_passwords_do_not_match".localized
            return false
        }

        return true
    }

    /// Validate all fields
    func validateAll() -> Bool {
        let nameValid = validateName()
        let emailValid = validateEmail()
        let passwordValid = validatePassword()
        let confirmValid = validateConfirmPassword()

        return nameValid && emailValid && passwordValid && confirmValid
    }
    
    // MARK: - Signup Method
    
    /// Perform signup with validated data (public signup — no invite code)
    func signUp() async throws {
        guard validateAll() else {
            errorMessage = "signup_error_fields_invalid".localized
            throw AppError.requiredFieldMissing
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password,
                name: Validators.sanitizeUserInput(name, maxLength: 100),
                car: car.isEmpty ? nil : Validators.sanitizeUserInput(car, maxLength: 100)
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
