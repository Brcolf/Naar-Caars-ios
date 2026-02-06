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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("signup_full_name_label".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.primary)
                        
                        TextField("signup_name_placeholder".localized, text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("signup.name")
                            .onChange(of: viewModel.name) { _, _ in
                                if viewModel.nameError != nil {
                                    viewModel.nameError = nil
                                }
                            }
                        
                        if let error = viewModel.nameError {
                            Text(error)
                                .font(.naarsCaption)
                                .foregroundColor(.naarsError)
                                .accessibilityLabel("Error: \(error)")
                        }
                    }
                    
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("signup_email_label".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.primary)
                        
                        TextField("signup_email_placeholder".localized, text: $viewModel.email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("signup.email")
                            .onChange(of: viewModel.email) { _, _ in
                                if viewModel.emailError != nil {
                                    viewModel.emailError = nil
                                }
                            }
                        
                        if let error = viewModel.emailError {
                            Text(error)
                                .font(.naarsCaption)
                                .foregroundColor(.naarsError)
                                .accessibilityLabel("Error: \(error)")
                        }
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("signup_password_label".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.primary)
                        
                        SecureField("signup_password_placeholder".localized, text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("signup.password")
                            .onChange(of: viewModel.password) { _, _ in
                                if viewModel.passwordError != nil {
                                    viewModel.passwordError = nil
                                }
                            }
                        
                        if let error = viewModel.passwordError {
                            Text(error)
                                .font(.naarsCaption)
                                .foregroundColor(.naarsError)
                                .accessibilityLabel("Error: \(error)")
                        } else {
                            Text("signup_password_hint".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Car field (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("signup_car_label".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.primary)
                        
                        TextField("signup_car_placeholder".localized, text: $viewModel.car)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("signup.car")
                    }
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
                    Link("signup_terms_of_service".localized, destination: URL(string: Constants.URLs.termsOfService)!)
                        .font(.naarsCaption)
                    Text("signup_terms_and".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    Link("signup_privacy_policy".localized, destination: URL(string: Constants.URLs.privacyPolicy)!)
                        .font(.naarsCaption)
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
