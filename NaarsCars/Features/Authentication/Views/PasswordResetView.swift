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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Title
                    Text("Reset Password")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 40)
                    
                    Text("Enter your email address and we'll send you a password reset link.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
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
                    .padding(.horizontal)
                    
                    // Error message
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    // Success message
                    if showSuccess {
                        Text("If an account exists with this email, you'll receive a password reset link.")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal)
                    }
                    
                    // Send button
                    Button(action: {
                        Task {
                            await viewModel.sendPasswordReset()
                            if viewModel.successMessage != nil {
                                showSuccess = true
                                // Auto-dismiss after 3 seconds
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                dismiss()
                            }
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Send Reset Link")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty)
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    PasswordResetView()
}





