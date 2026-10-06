//
//  PasswordResetView.swift
//  NaarsCars
//
//  Password reset flow
//

import SwiftUI

/// Password reset view
struct PasswordResetView: View {
    @StateObject private var viewModel = PasswordResetViewModel()
    @Environment(\.dismiss) var dismiss
    @FocusState private var isEmailFocused: Bool

    /// The request went out. The form is replaced by a confirmation that stays until the user
    /// closes it; it used to flash for 1.5 seconds under a dimming overlay and vanish.
    private var didSend: Bool {
        viewModel.successMessage != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if didSend {
                    sentConfirmation
                } else {
                    requestForm
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("password_reset_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(didSend ? "common_close".localized : "common_cancel".localized) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common_done".localized) { isEmailFocused = false }
                }
            }
        }
    }

    // MARK: - Request form

    private var requestForm: some View {
        VStack(spacing: 24) {
            Text("password_reset_subtitle".localized)
                .font(.naarsSubheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Email field
            NaarsTextField(
                placeholder: "password_reset_email_placeholder".localized,
                text: $viewModel.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                isFocused: isEmailFocused,
                accessibilityId: "passwordReset.email"
            )
            .focused($isEmailFocused)
            .submitLabel(.send)
            .onSubmit { sendReset() }
            .onChange(of: viewModel.email) { _, _ in
                if viewModel.error != nil { viewModel.error = nil }
            }
            .padding(.horizontal)

            // Error message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityLabel("app_error_format".localized(with: errorMessage))
            }

            // Send button
            Button(action: {
                sendReset()
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("password_reset_send_button".localized)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(viewModel.isLoading || viewModel.email.isEmpty)
            .padding(.horizontal)
            .accessibilityIdentifier("passwordReset.send")
        }
        .padding()
    }

    // MARK: - Confirmation

    private var sentConfirmation: some View {
        VStack(spacing: Constants.Spacing.lg) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 56))
                .foregroundColor(.naarsPrimary)
                .accessibilityHidden(true)

            Text("password_reset_sent_title".localized)
                .font(.naarsTitle2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            // Deliberately the same sentence whether or not the address has an account
            Text("password_reset_success_message".localized)
                .font(.naarsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("password_reset_sent_hint".localized)
                .font(.naarsFootnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            PrimaryButton(title: "common_done".localized, action: { dismiss() })
                .accessibilityIdentifier("passwordReset.done")
        }
        .padding(.horizontal, Constants.Spacing.lg)
        .padding(.top, Constants.Spacing.xl)
        .padding(.bottom, Constants.Spacing.lg)
    }

    /// Shared by the Send button and the Send key on the keyboard
    private func sendReset() {
        guard !viewModel.isLoading, !viewModel.email.isEmpty else { return }
        Task {
            await viewModel.sendPasswordReset()
            if viewModel.successMessage != nil {
                isEmailFocused = false
                HapticManager.success()
            }
        }
    }
}

#Preview {
    PasswordResetView()
}





