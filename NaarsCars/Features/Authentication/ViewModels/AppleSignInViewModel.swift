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
    
    private var currentNonce: String?
    
    /// Configure the Apple Sign-In request with nonce for security
    /// - Parameter request: The ASAuthorizationAppleIDRequest to configure
    func handleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        
        // Generate nonce for security
        let nonce = AppleSignInHelper.randomNonceString()
        currentNonce = nonce
        request.nonce = AppleSignInHelper.sha256(nonce)
    }
    
    /// Handle Apple Sign-In completion
    /// - Parameters:
    ///   - result: Result from ASAuthorization
    ///   - inviteCodeId: Optional invite code ID (for new users)
    ///   - isNewUser: Whether this is a new user signup
    func handleSignInCompletion(
        result: Result<ASAuthorization, Error>,
        inviteCodeId: UUID?,
        isNewUser: Bool
    ) async {
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
                if isNewUser, let codeId = inviteCodeId {
                    // New user signup with Apple
                    try await AuthService.shared.signUpWithApple(
                        credential: credential,
                        inviteCodeId: codeId
                    )
                } else {
                    // Existing user login with Apple
                    try await AuthService.shared.logInWithApple(credential: credential)
                }
            } catch let authError {
                self.error = authError as? AppError ?? .unknown(authError.localizedDescription)
                isLoading = false
                return
            }
            
            isLoading = false
            
        case .failure(let error):
            // Handle user cancellation separately
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                // User canceled - not an error, just reset loading state
                isLoading = false
                return
            } else {
                self.error = .unknown(error.localizedDescription)
            }
            isLoading = false
        }
    }
}

