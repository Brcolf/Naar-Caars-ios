//
//  SignupViewModel.swift
//  NaarsCars
//
//  ViewModel for signup flow
//

import Foundation
internal import Combine

/// ViewModel for signup flow
@MainActor
final class SignupViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var car: String = ""
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    private let authService = AuthService.shared
    
    var isFormValid: Bool {
        !name.isEmpty && !email.isEmpty && !password.isEmpty && password.count >= 6
    }
    
    func signUp(inviteCode: String) async {
        // Validate name
        guard !name.isEmpty else {
            error = AppError.invalidInput("Name is required")
            return
        }
        
        // Validate email
        guard !email.isEmpty, email.contains("@") else {
            error = AppError.invalidInput("Valid email is required")
            return
        }
        
        // Validate password
        guard !password.isEmpty, password.count >= 6 else {
            error = AppError.invalidInput("Password must be at least 6 characters")
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await authService.signUp(email: email, password: password, inviteCode: inviteCode)
            // Navigation will be handled by ContentView based on auth state (pending approval)
        } catch let appError as AppError {
            self.error = appError
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
        }
        
        isLoading = false
    }
}




