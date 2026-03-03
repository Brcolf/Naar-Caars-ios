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
    @State private var showSuccess = false
    @FocusState private var isEmailFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
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
                        accessibilityId: "passwordReset.email"
                    )
                    .focused($isEmailFocused)
                    .padding(.horizontal)
                    
                    // Error message
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsError)
                            .padding(.horizontal)
                    }
                    
                    // Success message
                    if showSuccess {
                        Text("password_reset_success_message".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.green)
                            .padding(.horizontal)
                    }
                    
                    // Send button
                    Button(action: {
                        Task {
                            await viewModel.sendPasswordReset()
                            if viewModel.successMessage != nil {
                                showSuccess = true
                                HapticManager.success()
                                try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
                                dismiss()
                            }
                        }
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
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty)
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("password_reset_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common_cancel".localized) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common_done".localized) { isEmailFocused = false }
                }
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
}

#Preview {
    PasswordResetView()
}





