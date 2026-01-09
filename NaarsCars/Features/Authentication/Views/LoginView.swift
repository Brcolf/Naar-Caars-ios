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
                // Logo/Title
                VStack(spacing: 8) {
                    Text("Naar's Cars")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Sign in to continue")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Form
                VStack(spacing: 16) {
                    // Email field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter your email", text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your password", text: $viewModel.password)
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
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
                    
                    // Forgot password
                    Button("Forgot Password?") {
                        showPasswordReset = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("or")
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
                    Text("Don't have an account?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    NavigationLink("Sign Up") {
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
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.error?.localizedDescription ?? "An error occurred")
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}




