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
    @State private var showSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // NaarsCars Title Logo
                VStack(spacing: 12) {
                    Image("NaarsTextLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 120)
                        .accessibilityLabel("Naar's Cars - Community Ride Sharing")
                    
                    Text("auth_login_title".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Form
                VStack(spacing: 16) {
                    // Email field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("auth_email_label".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        
                        TextField("auth_email_placeholder".localized, text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("login.email")
                            .accessibilityLabel("Email address")
                            .accessibilityHint("Enter your email to sign in")
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("auth_password_label".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        
                        SecureField("auth_password_placeholder".localized, text: $viewModel.password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("login.password")
                            .accessibilityLabel("Password")
                            .accessibilityHint("Enter your password")
                    }
                    
                    // Error message
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsError)
                            .padding(.horizontal)
                    }
                    
                    // Login button
                    Button(action: {
                        Task {
                            await viewModel.login()
                            if viewModel.error == nil {
                                showSuccess = true
                            }
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
                .accessibilityIdentifier("login.submit")
                    
                    // Forgot password
                    Button("auth_forgot_password".localized) {
                        showPasswordReset = true
                    }
                    .font(.naarsCaption)
                    .foregroundColor(.naarsPrimary)
                .accessibilityIdentifier("login.forgot")
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("auth_or_continue_with".localized)
                            .font(.naarsCaption)
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
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    
                    NavigationLink("auth_sign_up".localized) {
                        SignupInviteCodeView()
                    }
                    .font(.naarsCaption)
                    .foregroundColor(.naarsPrimary)
                    .accessibilityIdentifier("login.signup")
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
        .successCheckmark(isShowing: $showSuccess)
        .trackScreen("Login")
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}




