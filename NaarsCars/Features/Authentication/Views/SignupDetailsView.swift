//
//  SignupDetailsView.swift
//  NaarsCars
//
//  Second step of signup - user details
//

import SwiftUI

/// Second step of signup flow - user details entry
struct SignupDetailsView: View {
    let inviteCode: InviteCode
    @StateObject private var viewModel = SignupViewModel()
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title
                Text("Create Your Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                // Form
                VStack(spacing: 16) {
                    // Name field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter your name", text: $viewModel.name)
                            .textContentType(.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
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
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Create a password", text: $viewModel.password)
                            .textContentType(.newPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Car field (optional)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Car (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., 2020 Toyota Camry", text: $viewModel.car)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Error message
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    // Sign up button
                    Button(action: {
                        Task {
                            await viewModel.signUp(inviteCode: inviteCode.code)
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || !viewModel.isFormValid)
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SignupDetailsView(inviteCode: InviteCode(code: "NC12345678", createdBy: UUID()))
    }
}




