//
//  LoginViewModel.swift
//  NaarsCars
//
//  ViewModel for login view
//

import Foundation
internal import Combine

/// ViewModel for login view
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    private let authService = AuthService.shared
    private let rateLimiter = RateLimiter.shared
    
    func login() async {
        // Validate email
        guard !email.isEmpty else {
            error = AppError.invalidInput("Email is required")
            return
        }
        
        // Validate password
        guard !password.isEmpty else {
            error = AppError.invalidInput("Password is required")
            return
        }
        
        // Check rate limit: 2 seconds between login attempts
        let canProceed = await rateLimiter.checkAndRecord(
            action: "login_attempt",
            minimumInterval: 2.0
        )
        
        guard canProceed else {
            error = AppError.rateLimited("Please wait a moment before trying again")
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await authService.signIn(email: email, password: password)
            // Trigger AppLaunchManager to re-check auth state after successful login
            await AppLaunchManager.shared.performCriticalLaunch()
            // Navigation will be handled by ContentView based on auth state
        } catch let appError as AppError {
            self.error = appError
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
        }
        
        isLoading = false
    }
}



