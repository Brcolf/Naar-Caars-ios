//
//  SignupDetailsView.swift
//  NaarsCars
//
//  Second step of signup: user details entry
//

import SwiftUI

/// Second step of signup flow: user details and account creation
struct SignupDetailsView: View {
    @ObservedObject var viewModel: SignupViewModel
    let validatedInviteCode: InviteCode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Create Your Account")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Fill in your details below")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            // Form fields
            ScrollView {
                VStack(spacing: 20) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Full Name *")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("John Doe", text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.name) { _, _ in
                                if viewModel.nameError != nil {
                                    viewModel.nameError = nil
                                }
                            }
                        
                        if let error = viewModel.nameError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email *")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("john@example.com", text: $viewModel.email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.email) { _, _ in
                                if viewModel.emailError != nil {
                                    viewModel.emailError = nil
                                }
                            }
                        
                        if let error = viewModel.emailError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password *")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        SecureField("Minimum 8 characters", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.password) { _, _ in
                                if viewModel.passwordError != nil {
                                    viewModel.passwordError = nil
                                }
                            }
                        
                        if let error = viewModel.passwordError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Must be at least 8 characters with letters and numbers")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Car field (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Car (Optional)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("e.g., 2020 Honda Civic", text: $viewModel.car)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                    }
                }
                .padding(.horizontal)
            }
            
            // Error message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
            
            // Terms and Privacy notice
            VStack(spacing: 4) {
                Text("By creating an account, you agree to our")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Link("Terms of Service", destination: URL(string: "https://stitch-hydrangea-9b8.notion.site/Naars-Cars-Terms-of-Service-2ee7d642e90c8005ae63d8731e3d50f5")!)
                        .font(.caption)
                    Text("and")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link("Privacy Policy", destination: URL(string: "https://stitch-hydrangea-9b8.notion.site/Naars-Cars-Privacy-Policy-2ee7d642e90c8021b971f71c9cd957fc")!)
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            
            // Sign up button
            VStack(spacing: 12) {
                PrimaryButton(
                    title: "Create Account",
                    action: {
                        Task {
                            do {
                                try await viewModel.signUp()
                                
                                // Success! Account was created.
                                // Directly set state to pendingApproval since new signups require approval.
                                // Don't use performCriticalLaunch() because:
                                // 1. If email confirmation is required, there won't be a valid session yet
                                // 2. The account definitely needs approval (it was just created)
                                AppLaunchManager.shared.state = .ready(.pendingApproval)
                                
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
                if viewModel.isLoading {
                    Text("Creating your account...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Ensure the ViewModel has the validated invite code set
            if viewModel.validatedInviteCode == nil {
                viewModel.validatedInviteCode = validatedInviteCode
            }
        }
    }
}

#Preview {
    NavigationStack {
        SignupDetailsView(
            viewModel: SignupViewModel(),
            validatedInviteCode: InviteCode(
                code: "NCABCD1234",
                createdBy: UUID()
            )
        )
        .environmentObject(AppState())
    }
}
