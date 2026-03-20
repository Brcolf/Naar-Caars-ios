//
//  WelcomeView.swift
//  NaarsCars
//
//  Public-facing welcome screen — entry point for new and returning users
//

import SwiftUI

/// Welcome screen shown to unauthenticated users.
/// Provides Apple Sign-In and email signup for new users,
/// plus a sign-in link for returning users.
struct WelcomeView: View {
    @StateObject private var appleSignInViewModel = AppleSignInViewModel()
    @Environment(AppState.self) var appState
    @State private var showError = false
    @State private var navigateToEmailSignup = false
    @State private var navigateToLogin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                // Logo
                VStack(spacing: 12) {
                    Image("NaarsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 160)
                        .accessibilityLabel("Naar's Cars")

                    Text("welcome_title".localized)
                        .font(.naarsTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("welcome_body".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Spacer()
                    .frame(height: 8)

                // Sign up buttons
                VStack(spacing: 16) {
                    // Apple Sign-In (primary — no gate, no invite code)
                    AppleSignInButton(
                        onRequest: { request in
                            appleSignInViewModel.handleSignInRequest(request)
                        },
                        onCompletion: { result in
                            Task {
                                await appleSignInViewModel.handleSignUpCompletion(result: result)

                                if appleSignInViewModel.error == nil {
                                    await AppLaunchManager.shared.performCriticalLaunch()
                                } else {
                                    showError = true
                                }
                            }
                        }
                    )
                    .disabled(appleSignInViewModel.isLoading)

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
                    .padding(.vertical, 4)

                    // Continue with Email
                    Button(action: {
                        navigateToEmailSignup = true
                    }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("signup_continue_with_email".localized)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsBackgroundSecondary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("welcome.emailSignup")

                    if appleSignInViewModel.isLoading {
                        ProgressView()
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                Spacer()
                    .frame(height: 8)

                // Footer — public positioning copy
                Text("welcome_footer".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Continue as Guest
                Button {
                    appState.isGuestMode = true
                    AppLaunchManager.shared.enterGuestMode()
                } label: {
                    Text("welcome_continue_as_guest".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                .accessibilityIdentifier("welcome.continueAsGuest")
                .padding(.top, 4)

                // Already have an account? Sign In
                HStack {
                    Text("welcome_already_have_account".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)

                    Button("auth_sign_in_button".localized) {
                        navigateToLogin = true
                    }
                    .font(.naarsCaption)
                    .foregroundColor(.naarsPrimary)
                    .accessibilityIdentifier("welcome.signIn")
                }
                .padding(.bottom, 32)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToEmailSignup) {
            SignupDetailsView(viewModel: SignupViewModel())
                .environment(appState)
        }
        .navigationDestination(isPresented: $navigateToLogin) {
            LoginView()
                .environment(appState)
        }
        .alert("common_error".localized, isPresented: $showError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.error?.localizedDescription ?? "common_error_occurred".localized)
        }
        .trackScreen("Welcome")
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
            .environment(AppState())
    }
}
