//
//  AppleSignInViewModel.swift
//  NaarsCars
//
//  ViewModel for Apple Sign-In flow
//

import Foundation
import AuthenticationServices
import CryptoKit
internal import Combine

/// ViewModel for handling Apple Sign-In flow
@MainActor
final class AppleSignInViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: AppError?
    @Published var showNoAccountSheet = false
    
    private(set) var currentNonce: String?
    private let authService: any AuthServiceProtocol

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
    /// Configure the Apple Sign-In request with nonce for security
    /// - Parameter request: The ASAuthorizationAppleIDRequest to configure
    func handleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        
        // Generate nonce for security
        guard let nonce = AppleSignInHelper.randomNonceString() else {
            error = .unknown("Unable to generate secure nonce. Please try again.")
            return
        }
        currentNonce = nonce
        request.nonce = AppleSignInHelper.sha256(nonce)
    }
    
    /// Handle Apple Sign-In completion for new user signup
    /// Creates account without invite code (public signup)
    func handleSignUpCompletion(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        error = nil

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                error = .unknown("Invalid credential type")
                isLoading = false
                return
            }

            do {
                try await authService.signUpWithApple(
                    credential: credential,
                    rawNonce: currentNonce
                )
            } catch let authError {
                self.error = authError as? AppError ?? .unknown(authError.localizedDescription)
                isLoading = false
                return
            }

            isLoading = false

        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                isLoading = false
                return
            } else {
                self.error = .unknown(error.localizedDescription)
            }
            isLoading = false
        }
    }

    /// Handle Apple Sign-In completion for existing user login
    func handleSignInCompletion(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        error = nil
        showNoAccountSheet = false

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                error = .unknown("Invalid credential type")
                isLoading = false
                return
            }

            do {
                let loginResult = try await authService.logInWithApple(
                    credential: credential,
                    rawNonce: currentNonce
                )
                if loginResult == .noAccountFound {
                    showNoAccountSheet = true
                    isLoading = false
                    return
                }
            } catch let authError {
                self.error = authError as? AppError ?? .unknown(authError.localizedDescription)
                isLoading = false
                return
            }

            isLoading = false

        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                isLoading = false
                return
            } else {
                self.error = .unknown(error.localizedDescription)
            }
            isLoading = false
        }
    }
}

