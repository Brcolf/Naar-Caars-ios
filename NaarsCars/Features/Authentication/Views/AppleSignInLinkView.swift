//
//  AppleSignInLinkView.swift
//  NaarsCars
//
//  View for linking Apple ID to existing account
//

import SwiftUI
import AuthenticationServices

/// View for linking Apple ID to existing email/password account
struct AppleSignInLinkView: View {
    @StateObject private var viewModel = AppleSignInViewModel()
    @Environment(\.dismiss) private var dismiss
    
    let onCompletion: (ASAuthorizationAppleIDCredential) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title
                VStack(spacing: 8) {
                    Text("Link Apple ID")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Connect your Apple ID to sign in with Face ID/Touch ID")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Apple Sign-In button
                AppleSignInButton(
                    onRequest: { request in
                        viewModel.handleSignInRequest(request)
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                onCompletion(credential)
                            }
                        case .failure:
                            // Error handled by viewModel
                            break
                        }
                    }
                )
                .disabled(viewModel.isLoading)
                .padding(.horizontal)
                
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 8)
                }
                
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
    }
}

#Preview {
    NavigationStack {
        AppleSignInLinkView { credential in
            print("Linked Apple ID: \(credential.user)")
        }
    }
}

