//
//  PendingApprovalView.swift
//  NaarsCars
//
//  View shown when user is waiting for admin approval
//

import SwiftUI

/// View displayed when user account is pending admin approval
struct PendingApprovalView: View {
    @StateObject private var launchManager = AppLaunchManager.shared
    @State private var isSigningOut = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "hourglass")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            // Title
            Text("Your Account is Pending Approval")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            // Description
            VStack(spacing: 16) {
                Text("Thank you for creating your account!")
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Your account is pending approval from the board. You'll be notified once your account has been approved.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Return to Login button
            Button(action: {
                signOutAndReturnToLogin()
            }) {
                HStack {
                    if isSigningOut {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isSigningOut ? "Signing Out..." : "Return to Login")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isSigningOut)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            // Periodically check approval status (every 15 seconds)
            // This allows users to be automatically transitioned to the main app when approved
            await startPeriodicApprovalCheck()
        }
    }
    
    /// Start periodic checks for approval status
    /// Checks every 15 seconds to detect when user is approved
    private func startPeriodicApprovalCheck() async {
        // Initial check after 5 seconds (give server time to process approval)
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Then check every 15 seconds
        while true {
            // Check approval status by triggering launch manager
            // This will update the state if user is approved, causing ContentView to transition
            await launchManager.performCriticalLaunch()
            
            // Wait 15 seconds before next check
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
        }
    }
    
    /// Sign out and return to login screen
    private func signOutAndReturnToLogin() {
        Task {
            isSigningOut = true
            do {
                try await AuthService.shared.signOut()
                // Trigger launch manager to re-check auth state
                await launchManager.performCriticalLaunch()
            } catch {
                print("⚠️ Error signing out: \(error.localizedDescription)")
                // Still try to update launch state to unauthenticated
                launchManager.state = .ready(.unauthenticated)
            }
            isSigningOut = false
        }
    }
}

#Preview {
    PendingApprovalView()
}
