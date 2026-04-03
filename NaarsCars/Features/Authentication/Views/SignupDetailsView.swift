//
//  SignupDetailsView.swift
//  NaarsCars
//
//  Second step of signup: user details entry
//

import SwiftUI

/// Second step of signup flow: user details and account creation
struct SignupDetailsView: View {
    enum SignupField: Hashable {
        case name, email, password, confirmPassword, car
    }

    @ObservedObject var viewModel: SignupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState
    @FocusState private var focusedField: SignupField?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("signup_create_account_title".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("signup_details_subtitle".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            // Form fields
            ScrollView {
                VStack(spacing: 20) {
                    // Name field
                    NaarsTextField(
                        placeholder: "signup_name_placeholder".localized,
                        text: $viewModel.name,
                        autocapitalization: .words,
                        errorMessage: viewModel.nameError,
                        isFocused: focusedField == .name,
                        accessibilityId: "signup.name"
                    )
                    .focused($focusedField, equals: .name)
                    .onChange(of: viewModel.name) { _, _ in
                        if viewModel.nameError != nil { viewModel.nameError = nil }
                    }

                    // Email field
                    NaarsTextField(
                        placeholder: "signup_email_placeholder".localized,
                        text: $viewModel.email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        errorMessage: viewModel.emailError,
                        isFocused: focusedField == .email,
                        accessibilityId: "signup.email"
                    )
                    .focused($focusedField, equals: .email)
                    .onChange(of: viewModel.email) { _, _ in
                        if viewModel.emailError != nil { viewModel.emailError = nil }
                    }

                    // Password field
                    VStack(alignment: .leading, spacing: 4) {
                        NaarsTextField(
                            placeholder: "signup_password_placeholder".localized,
                            text: $viewModel.password,
                            isSecure: true,
                            textContentType: .newPassword,
                            errorMessage: viewModel.passwordError,
                            isFocused: focusedField == .password,
                            accessibilityId: "signup.password"
                        )
                        .focused($focusedField, equals: .password)
                        .onChange(of: viewModel.password) { _, _ in
                            if viewModel.passwordError != nil { viewModel.passwordError = nil }
                            if viewModel.confirmPasswordError != nil { viewModel.confirmPasswordError = nil }
                        }

                        if viewModel.passwordError == nil {
                            Text("signup_password_hint".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }

                    // Confirm password field
                    NaarsTextField(
                        placeholder: "signup_confirm_password_placeholder".localized,
                        text: $viewModel.confirmPassword,
                        isSecure: true,
                        textContentType: .newPassword,
                        errorMessage: viewModel.confirmPasswordError,
                        isFocused: focusedField == .confirmPassword,
                        accessibilityId: "signup.confirmPassword"
                    )
                    .focused($focusedField, equals: .confirmPassword)
                    .onChange(of: viewModel.confirmPassword) { _, _ in
                        if viewModel.confirmPasswordError != nil { viewModel.confirmPasswordError = nil }
                    }

                    // Car field (optional)
                    NaarsTextField(
                        placeholder: "signup_car_placeholder".localized,
                        text: $viewModel.car,
                        autocapitalization: .words,
                        isFocused: focusedField == .car,
                        accessibilityId: "signup.car"
                    )
                    .focused($focusedField, equals: .car)
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Error message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsError)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
            
            // Terms and Privacy notice
            VStack(spacing: 4) {
                Text("signup_terms_agreement".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    if let tosURL = URL(string: Constants.URLs.termsOfService) {
                        Link("signup_terms_of_service".localized, destination: tosURL)
                            .font(.naarsCaption)
                    }
                    Text("signup_terms_and".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    if let privacyURL = URL(string: Constants.URLs.privacyPolicy) {
                        Link("signup_privacy_policy".localized, destination: privacyURL)
                            .font(.naarsCaption)
                    }
                }
            }
            .padding(.horizontal)
            
            // Sign up button
            VStack(spacing: 12) {
                PrimaryButton(
                    title: "signup_create_account_button".localized,
                    action: {
                        Task {
                            do {
                                try await viewModel.signUp()
                                
                                // Success! Account was created with application_complete = false.
                                // Route to application fields to collect heardAbout + joinReason.
                                AppLaunchManager.shared.state = .ready(.needsApplication)
                                
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            } catch {
                                // Error handled by viewModel.errorMessage
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.error)
                            }
                        }
                    },
                    isLoading: viewModel.isLoading,
                    isDisabled: viewModel.isLoading
                )
                .accessibilityIdentifier("signup.createAccount")
                if viewModel.isLoading {
                    Text("signup_creating_account".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("signup_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button { moveFocus(forward: false) } label: { Image(systemName: "chevron.up") }
                    .disabled(focusedField == .name)
                Button { moveFocus(forward: true) } label: { Image(systemName: "chevron.down") }
                    .disabled(focusedField == .car)
                Spacer()
                Button("common_done".localized) { focusedField = nil }
            }
        }
    }

    private func moveFocus(forward: Bool) {
        let fields: [SignupField] = [.name, .email, .password, .confirmPassword, .car]
        guard let current = focusedField, let index = fields.firstIndex(of: current) else { return }
        let next = forward ? fields.index(after: index) : fields.index(before: index)
        if fields.indices.contains(next) {
            focusedField = fields[next]
        }
    }
}

#Preview {
    NavigationStack {
        SignupDetailsView(viewModel: SignupViewModel())
            .environment(AppState())
    }
}
