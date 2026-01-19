//
//  SignupInviteCodeView.swift
//  NaarsCars
//
//  First step of signup - invite code entry
//

import SwiftUI

/// First step of signup flow - invite code validation
/// Supports deep links with embedded codes: https://naarscars.com/signup?code=CODE
struct SignupInviteCodeView: View {
    @StateObject private var viewModel = SignupViewModel()
    @StateObject private var appleSignInViewModel = AppleSignInViewModel()
    @EnvironmentObject var appState: AppState
    @State private var inviteCode: String = ""
    @State private var isValidating = false
    @State private var validationError: AppError?
    @State private var validatedCode: InviteCode?
    @State private var showMethodChoice = false
    @State private var showError = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Full Logo with Red Car
                VStack(spacing: 12) {
                    Image("NaarsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 160)
                        .accessibilityLabel("Naar's Cars - Community Ride Sharing")
                    
                    Text("Enter your invite code to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Invite code field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isValidating)
                }
                .padding(.horizontal)
                
                // Error message
                if let error = validationError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // Next button
                Button(action: {
                    Task {
                        await validateCode()
                    }
                }) {
                    if isValidating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Next")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isValidating || inviteCode.isEmpty)
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Sign Up")
        .navigationDestination(isPresented: $showMethodChoice) {
            if let code = validatedCode {
                SignupMethodChoiceView(inviteCode: code)
                    .environmentObject(appState)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.error?.localizedDescription ?? "An error occurred")
        }
        .onOpenURL { url in
            // Handle deep link: https://naarscars.com/signup?code=CODE
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("handleInviteCodeDeepLink"))) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                handleDeepLink(url)
            }
        }
        .trackScreen("SignupInviteCode")
    }
    
    /// Handle deep link URL with embedded invite code
    private func handleDeepLink(_ url: URL) {
        // Parse URL: https://naarscars.com/signup?code=CODE
        guard url.host == "naarscars.com" || url.host == "www.naarscars.com" else { return }
        guard url.path == "/signup" else { return }
        
        // Extract code from query parameters
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            // Pre-populate the invite code field
            inviteCode = code.uppercased()
            
            // Automatically validate if code is provided
            Task {
                await validateCode()
            }
        }
    }
    
    
    private func validateCode() async {
        isValidating = true
        validationError = nil
        
        do {
            let code = try await AuthService.shared.validateInviteCode(inviteCode)
            validatedCode = code
            // Show method choice after validation
            showMethodChoice = true
        } catch let appError as AppError {
            validationError = appError
        } catch {
            validationError = AppError.processingError(error.localizedDescription)
        }
        
        isValidating = false
    }
}

#Preview {
    NavigationStack {
        SignupInviteCodeView()
    }
}




