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

                // Primary sign-in options
                VStack(spacing: 16) {
                    // Apple Sign-In (primary — handles both sign-in and sign-up)
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

                    // Log in with Email (primary)
                    Button(action: {
                        navigateToLogin = true
                    }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("welcome_login_with_email".localized)
                            Spacer()
                        }
                        .font(.naarsBody)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsBackgroundSecondary)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.naarsBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("welcome.emailLogin")

                    if appleSignInViewModel.isLoading {
                        ProgressView()
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.naarsDivider)
                    Text("auth_or_continue_with".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.naarsTextSecondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.naarsDivider)
                }
                .padding(.horizontal)

                // Secondary options — sign up with email + guest
                VStack(spacing: 12) {
                    SecondaryButton(title: "welcome_signup_with_email".localized) {
                        navigateToEmailSignup = true
                    }
                    .accessibilityIdentifier("welcome.emailSignup")

                    Button {
                        appState.isGuestMode = true
                        AppLaunchManager.shared.enterGuestMode()
                    } label: {
                        Text("welcome_continue_as_guest".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.naarsTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .accessibilityIdentifier("welcome.continueAsGuest")
                }
                .padding(.horizontal)

                // Footer — public positioning copy
                Text("welcome_footer".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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
