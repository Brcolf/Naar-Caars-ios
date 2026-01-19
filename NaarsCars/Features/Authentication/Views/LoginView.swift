//
//  LoginView.swift
//  NaarsCars
//
//  Login screen for email/password authentication
//

import SwiftUI

/// Login view for email/password authentication
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @StateObject private var appleSignInViewModel = AppleSignInViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showPasswordReset = false
    @State private var showError = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Full Logo with Red Car
                VStack(spacing: 12) {
                    Image("NaarsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 200)
                        .accessibilityLabel("Naar's Cars - Community Ride Sharing")
                    
                    Text("auth_login_title".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Form
                VStack(spacing: 16) {
                    // Email field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("auth_email_label".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("auth_email_placeholder".localized, text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("auth_password_label".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("auth_password_placeholder".localized, text: $viewModel.password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Error message
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    // Login button
                    Button(action: {
                        Task {
                            await viewModel.login()
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("auth_sign_in_button".localized)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
                    
                    // Forgot password
                    Button("auth_forgot_password".localized) {
                        showPasswordReset = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("auth_or_continue_with".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .padding(.vertical, 8)
                    
                    // Apple Sign-In button
                    AppleSignInButton(
                        onRequest: { request in
                            appleSignInViewModel.handleSignInRequest(request)
                        },
                        onCompletion: { result in
                            Task {
                                await appleSignInViewModel.handleSignInCompletion(
                                    result: result,
                                    inviteCodeId: nil,
                                    isNewUser: false
                                )
                                
                                // If successful, trigger AppLaunchManager to re-check auth state
                                if appleSignInViewModel.error == nil {
                                    await AppLaunchManager.shared.performCriticalLaunch()
                                } else {
                                    showError = true
                                }
                            }
                        }
                    )
                    .disabled(viewModel.isLoading || appleSignInViewModel.isLoading)
                }
                .padding(.horizontal)
                
                // Sign up link
                HStack {
                    Text("auth_no_account".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    NavigationLink("auth_sign_up".localized) {
                        SignupInviteCodeView()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(.top)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
        }
        .alert("common_error".localized, isPresented: $showError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.error?.localizedDescription ?? "common_error".localized)
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}




