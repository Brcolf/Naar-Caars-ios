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
    @Environment(\.dismiss) private var dismiss
    @State private var showPasswordReset = false
    @State private var showError = false
    @State private var showSuccess = false
    @State private var didRequestCreateAccount = false

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
                        .accessibilityLabel("app_logo_tagline_accessibility".localized)

                    Text("auth_login_title".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Form
                VStack(spacing: 16) {
                    // Email field. `.username` (with `.password` below) is the pair Password
                    // AutoFill looks for; `.emailAddress` only offered contact addresses.
                    NaarsTextField(
                        placeholder: "auth_email_placeholder".localized,
                        text: $viewModel.email,
                        keyboardType: .emailAddress,
                        textContentType: .username,
                        isFocused: focusedField == .email,
                        accessibilityId: "login.email"
                    )
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .onChange(of: viewModel.email) { _, _ in
                        // A stale error should not sit under the field while it is corrected
                        if viewModel.error != nil { viewModel.error = nil }
                    }

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
                    .submitLabel(.go)
                    .onSubmit { submitLogin() }
                    .onChange(of: viewModel.password) { _, _ in
                        if viewModel.error != nil { viewModel.error = nil }
                    }

                    // Error message
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .accessibilityLabel("app_error_format".localized(with: errorMessage))
                    }

                    // Save Username toggle
                    Toggle("auth_save_username".localized, isOn: $saveUsernameEnabled)
                        .font(.naarsCaption)
                        .padding(.horizontal, 4)

                    // Login button
                    Button(action: {
                        submitLogin()
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
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
                    .accessibilityIdentifier("login.submit")

                    // Sign up link. Welcome is the sign-up screen and is already underneath
                    // this one, so go back to it; pushing a second copy stacked Welcome →
                    // Login → Welcome with no Back button.
                    HStack {
                        Text("auth_no_account".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)

                        Button {
                            returnToWelcome()
                        } label: {
                            // The frame sits inside the label so the whole 44-pt area is tappable
                            Text("auth_sign_up".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.naarsPrimary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("login.signup")
                    }

                    // Forgot password
                    Button {
                        showPasswordReset = true
                    } label: {
                        Text("auth_forgot_password".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
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

                    // Apple Sign-In button (existing user login)
                    AppleSignInButton(
                        onRequest: { request in
                            appleSignInViewModel.handleSignInRequest(request)
                        },
                        onCompletion: { result in
                            Task {
                                await appleSignInViewModel.handleSignInCompletion(result: result)

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
                    .accessibilityLabel("auth_keyboard_previous_field".localized)
                Button { if focusedField == .email { focusedField = .password } } label: { Image(systemName: "chevron.down") }
                    .disabled(focusedField == .password)
                    .accessibilityLabel("auth_keyboard_next_field".localized)
                Spacer()
                Button("common_done".localized) { focusedField = nil }
            }
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
        }
        .sheet(isPresented: $appleSignInViewModel.showNoAccountSheet, onDismiss: {
            // Leave for the sign-up screen ONLY after the sheet animation completes.
            // This avoids the known SwiftUI race where changing navigation state
            // during a sheet dismiss causes the transition to silently fail.
            if didRequestCreateAccount {
                didRequestCreateAccount = false
                returnToWelcome()
            }
        }) {
            NoAccountFoundSheet(didRequestCreateAccount: $didRequestCreateAccount)
        }
        .alert("common_error".localized, isPresented: $showError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.errorMessage ?? "common_error_occurred".localized)
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

    /// Shared by the Sign In button and the Go key on the password field
    private func submitLogin() {
        guard !viewModel.isLoading, !viewModel.email.isEmpty, !viewModel.password.isEmpty else { return }
        Task {
            await viewModel.login()
            if viewModel.error == nil {
                if saveUsernameEnabled {
                    savedUsername = viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    savedUsername = ""
                }
                showSuccess = true
            }
        }
    }

    /// Welcome is the sign-up screen, and Login is only ever pushed on top of it, so going
    /// to sign-up means popping back. Pushing a second Welcome hid the Back button and
    /// stacked the two screens on every round trip.
    private func returnToWelcome() {
        dismiss()
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}
