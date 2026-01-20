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
    /// Checks every 30 seconds to detect when user is approved
    private func startPeriodicApprovalCheck() async {
        // Initial check after 10 seconds (give server time to process approval)
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        
        // Then check every 30 seconds (reduced frequency to avoid loops)
        while !Task.isCancelled {
            // Check approval status directly without triggering full launch flow
            // This prevents state oscillation and request storms
            let isApproved = await checkApprovalDirectly()
            
            if isApproved {
                // User is now approved - transition to authenticated state
                launchManager.state = .ready(.authenticated)
                return // Exit the loop
            }
            
            // Wait 30 seconds before next check
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
        }
    }
    
    /// Check approval status directly without triggering full launch flow
    private func checkApprovalDirectly() async -> Bool {
        // Use AppLaunchManager's lightweight check (doesn't change state)
        return await launchManager.checkApprovalStatusOnly()
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
