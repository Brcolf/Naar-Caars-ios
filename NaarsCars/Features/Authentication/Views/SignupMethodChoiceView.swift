//
//  SignupMethodChoiceView.swift
//  NaarsCars
//
//  View for choosing signup method after invite code validation
//

import SwiftUI

/// View for choosing signup method (Apple Sign-In or Email) after invite code validation
struct SignupMethodChoiceView: View {
    let inviteCode: InviteCode
    @StateObject private var appleSignInViewModel = AppleSignInViewModel()
    @EnvironmentObject var appState: AppState
    
    @State private var showError = false
    @State private var navigateToEmailSignup = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title
                VStack(spacing: 8) {
                    Text("signup_create_account_title".localized)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("signup_method_subtitle".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Apple Sign-In button
                AppleSignInButton(
                    onRequest: { request in
                        appleSignInViewModel.handleSignInRequest(request)
                    },
                    onCompletion: { result in
                        Task {
                            await appleSignInViewModel.handleSignInCompletion(
                                result: result,
                                inviteCodeId: inviteCode.id,
                                isNewUser: true
                            )
                            
                            if appleSignInViewModel.error == nil {
                                // Success - trigger AppLaunchManager to check auth state
                                await AppLaunchManager.shared.performCriticalLaunch()
                                // Navigation will be handled by ContentView based on auth state
                            } else {
                                showError = true
                            }
                        }
                    }
                )
                .disabled(appleSignInViewModel.isLoading)
                .padding(.horizontal)
                
                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("signup_or_divider".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .padding(.vertical, 8)
                
                // Continue with Email button
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
                .padding(.horizontal)
                .accessibilityIdentifier("signup.method.email")
                
                if appleSignInViewModel.isLoading {
                    ProgressView()
                        .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle("signup_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToEmailSignup) {
            SignupDetailsView(
                viewModel: SignupViewModel(),
                validatedInviteCode: inviteCode
            )
        }
        .alert("common_error".localized, isPresented: $showError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.error?.localizedDescription ?? "common_error_occurred".localized)
        }
    }
}

#Preview {
    NavigationStack {
        SignupMethodChoiceView(
            inviteCode: InviteCode(
                id: UUID(),
                code: "NC12345678",
                createdBy: UUID(),
                usedBy: nil,
                usedAt: nil,
                createdAt: Date()
            )
        )
    }
}

