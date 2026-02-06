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
                    Text("auth_link_apple_id_title".localized)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("auth_link_apple_id_subtitle".localized)
                        .font(.naarsSubheadline)
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
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
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
            AppLogger.info("auth", "Linked Apple ID: \(credential.user)")
        }
    }
}


