//
//  LoginView.swift
//  NaarsCars
//
//  Login screen for email/password authentication
//

import SwiftUI
#if DEBUG
import os
#endif

/// Login view for email/password authentication
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @StateObject private var appleSignInViewModel = AppleSignInViewModel()
    @Environment(AppState.self) var appState
    @State private var showPasswordReset = false
    @State private var showError = false
    @State private var showSuccess = false
    @State private var didRequestCreateAccount = false
    @State private var navigateToSignup = false

    enum LoginField: Hashable { case email, password }
    @FocusState private var focusedField: LoginField?

    @AppStorage("saveUsernameEnabled") private var saveUsernameEnabled = false
    @AppStorage("savedUsername") private var savedUsername = ""

#if DEBUG
    private static let _firstTapPerfLog = OSLog(subsystem: "com.naarscars.app", category: "FirstTapPerf")
#endif

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
                    NaarsTextField(
                        placeholder: "auth_email_placeholder".localized,
                        text: $viewModel.email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        isFocused: focusedField == .email,
                        accessibilityId: "login.email"
                    )
                    .focused($focusedField, equals: .email)

                    // Password field
                    NaarsTextField(
                        placeholder: "auth_password_placeholder".localized,
                        text: $viewModel.password,
                        isSecure: true,
                        textContentType: .password,
                        isFocused: focusedField == .password,
                        accessibilityId: "login.password"
                    )
                    .focused($focusedField, equals: .password)

                    // Error message
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsError)
                            .padding(.horizontal)
                    }

                    // Save Username toggle
                    Toggle("auth_save_username".localized, isOn: $saveUsernameEnabled)
                        .font(.naarsCaption)
                        .tint(.naarsPrimary)
                        .padding(.horizontal, 4)

                    // Login button
                    Button(action: {
                        Task {
                            await viewModel.login()
                            if viewModel.error == nil {
                                if saveUsernameEnabled { savedUsername = viewModel.email } else { savedUsername = "" }
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

                                if appleSignInViewModel.showNoAccountSheet {
                                    // Sheet presentation handled by binding — no action needed
                                } else if appleSignInViewModel.error == nil {
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
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button { if focusedField == .password { focusedField = .email } } label: { Image(systemName: "chevron.up") }
                    .disabled(focusedField == .email)
                Button { if focusedField == .email { focusedField = .password } } label: { Image(systemName: "chevron.down") }
                    .disabled(focusedField == .password)
                Spacer()
                Button("common_done".localized) { focusedField = nil }
            }
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
        }
        .sheet(isPresented: $appleSignInViewModel.showNoAccountSheet, onDismiss: {
            // Set navigateToSignup ONLY after the sheet animation completes.
            // This avoids the known SwiftUI race where setting navigation state
            // during a sheet dismiss causes the push to silently fail.
            if didRequestCreateAccount {
                didRequestCreateAccount = false
                navigateToSignup = true
            }
        }) {
            NoAccountFoundSheet(didRequestCreateAccount: $didRequestCreateAccount)
        }
        .navigationDestination(isPresented: $navigateToSignup) {
            SignupInviteCodeView()
        }
        .alert("common_error".localized, isPresented: $showError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.error?.localizedDescription ?? "common_error".localized)
        }
        .successCheckmark(isShowing: $showSuccess)
        .trackScreen("Login")
        .onAppear {
            if saveUsernameEnabled && !savedUsername.isEmpty {
                viewModel.email = savedUsername
            }
        }
        .onChange(of: saveUsernameEnabled) { _, enabled in
            if !enabled { savedUsername = "" }
        }
#if DEBUG
        .onChange(of: focusedField) { _, newValue in
            if newValue == .email {
                os_signpost(.event, log: Self._firstTapPerfLog, name: "LoginEmailFocus")
                FirstTapPerfLogger.logFocusDelivered(source: "login")
            }
        }
#endif
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}
