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
    private let authService = AuthService.shared
    
    // MARK: - Validation Methods
    
    /// Validate invite code format and check with server
    func validateInviteCode() async -> Bool {
        inviteCodeError = nil
        
        // Normalize and check format
        let normalized = InviteCodeGenerator.normalize(inviteCode)
        
        guard InviteCodeGenerator.isValidFormat(normalized) else {
            inviteCodeError = "Invalid invite code format"
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
                    inviteCodeError = "Please wait a moment"
                case .invalidInviteCode:
                    inviteCodeError = "Invalid or expired invite code"
                default:
                    inviteCodeError = appError.errorDescription ?? "Validation failed"
                }
            } else {
                inviteCodeError = "Validation failed. Please try again."
            }
            return false
        }
    }
    
    /// Validate name field
    func validateName() -> Bool {
        nameError = nil
        
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            nameError = "Name is required"
            return false
        }
        
        guard trimmed.count >= 2 else {
            nameError = "Name must be at least 2 characters"
            return false
        }
        
        return true
    }
    
    /// Validate email field
    func validateEmail() -> Bool {
        emailError = nil
        
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !trimmed.isEmpty else {
            emailError = "Email is required"
            return false
        }
        
        guard Validators.isValidEmail(trimmed) else {
            emailError = "Please enter a valid email address"
            return false
        }
        
        return true
    }
    
    /// Validate password field
    func validatePassword() -> Bool {
        passwordError = nil
        
        guard !password.isEmpty else {
            passwordError = "Password is required"
            return false
        }
        
        guard password.count >= 8 else {
            passwordError = "Password must be at least 8 characters"
            return false
        }
        
        guard Validators.isValidPassword(password) else {
            passwordError = "Password must contain at least one letter and one number"
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
        print("🔍 [SignupViewModel] signUp() called")
        print("🔍 [SignupViewModel] validatedInviteCode: \(validatedInviteCode?.code ?? "nil")")
        
        guard let inviteCode = validatedInviteCode else {
            print("🔴 [SignupViewModel] No validated invite code")
            errorMessage = "Invalid invite code. Please go back and validate your invite code."
            throw AppError.invalidInviteCode
        }
        
        print("🔍 [SignupViewModel] Validating all fields...")
        let isValid = validateAll()
        print("🔍 [SignupViewModel] Validation result: \(isValid)")
        print("🔍 [SignupViewModel] Field errors - name: \(nameError ?? "nil"), email: \(emailError ?? "nil"), password: \(passwordError ?? "nil")")
        
        guard isValid else {
            print("🔴 [SignupViewModel] Validation failed")
            errorMessage = "Please fill in all required fields correctly."
            throw AppError.requiredFieldMissing
        }
        
        print("🔍 [SignupViewModel] Starting signup process...")
        isLoading = true
        errorMessage = nil
        defer { 
            isLoading = false
            print("🔍 [SignupViewModel] Signup process completed, isLoading set to false")
        }
        
        do {
            try await authService.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                car: car.isEmpty ? nil : car.trimmingCharacters(in: .whitespacesAndNewlines),
                inviteCodeId: inviteCode.id
            )
        } catch {
            if let appError = error as? AppError {
                switch appError {
                case .emailAlreadyExists:
                    emailError = "This email is already registered"
                    errorMessage = appError.errorDescription
                default:
                    errorMessage = appError.errorDescription ?? "Signup failed. Please try again."
                }
            } else {
                errorMessage = "Signup failed. Please try again."
            }
            throw error
        }
    }
}
