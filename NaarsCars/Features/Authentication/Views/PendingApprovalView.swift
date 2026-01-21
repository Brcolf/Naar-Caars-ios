//
//  PendingApprovalView.swift
//  NaarsCars
//
//  View shown when user is waiting for admin approval
//

import SwiftUI
import UserNotifications

/// View displayed when user account is pending admin approval
struct PendingApprovalView: View {
    @StateObject private var launchManager = AppLaunchManager.shared
    @State private var isSigningOut = false
    @State private var hasRequestedNotifications = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showNotificationPrompt = false
    
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
            
            // Notification permission prompt
            if notificationStatus == .notDetermined && !hasRequestedNotifications {
                notificationPromptCard
            } else if notificationStatus == .authorized {
                notificationEnabledBadge
            }
            
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
            // Check notification status on appear
            await checkNotificationStatus()
            
            // Show notification prompt after a short delay if not determined
            if notificationStatus == .notDetermined {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                showNotificationPrompt = true
            }
            
            // Periodically check approval status (every 15 seconds)
            // This allows users to be automatically transitioned to the main app when approved
            await startPeriodicApprovalCheck()
        }
    }
    
    // MARK: - Notification UI Components
    
    private var notificationPromptCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Notifications")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Get notified when your account is approved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: {
                Task {
                    await requestNotificationPermission()
                }
            }) {
                Text("Enable")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 32)
        .opacity(showNotificationPrompt ? 1 : 0)
        .animation(.easeIn(duration: 0.3), value: showNotificationPrompt)
    }
    
    private var notificationEnabledBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            Text("Notifications enabled - we'll let you know when approved!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Notification Methods
    
    private func checkNotificationStatus() async {
        let status = await PushNotificationService.shared.checkAuthorizationStatus()
        await MainActor.run {
            notificationStatus = status
        }
    }
    
    private func requestNotificationPermission() async {
        hasRequestedNotifications = true
        
        let granted = await PushNotificationService.shared.requestPermission()
        
        await MainActor.run {
            notificationStatus = granted ? .authorized : .denied
        }
        
        // If granted and we have a user ID, register for remote notifications
        if granted {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
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
