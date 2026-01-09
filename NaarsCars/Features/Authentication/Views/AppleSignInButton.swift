//
//  AppleSignInButton.swift
//  NaarsCars
//
//  Apple Sign-In button component using AuthenticationServices
//

import SwiftUI
import AuthenticationServices
import CryptoKit

/// Apple Sign-In button using official SignInWithAppleButton
struct AppleSignInButton: View {
    @Environment(\.colorScheme) var colorScheme
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    
    var body: some View {
        SignInWithAppleButton(
            onRequest: onRequest,
            onCompletion: onCompletion
        )
        .signInWithAppleButtonStyle(
            colorScheme == .dark ? .white : .black
        )
        .frame(height: 50)
        .cornerRadius(12)
    }
}

/// Utility functions for Apple Sign-In security (nonce generation)
enum AppleSignInHelper {
    /// Generate a random nonce string for security
    /// - Parameter length: Length of nonce string (default: 32)
    /// - Returns: Random nonce string
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce: \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }
    
    /// SHA256 hash of input string
    /// - Parameter input: String to hash
    /// - Returns: SHA256 hash as hex string
    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    VStack(spacing: 20) {
        AppleSignInButton(
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                // Handle result
            }
        )
    }
    .padding()
}

