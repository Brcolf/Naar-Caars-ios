//
//  PendingApprovalView.swift
//  NaarsCars
//
//  View shown when user is waiting for admin approval
//

import SwiftUI

/// View displayed when user account is pending admin approval
struct PendingApprovalView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRefreshing = false
    @State private var refreshError: AppError?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "hourglass")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("Your Account is Pending Approval")
                    .font(.title)
                    .foregroundColor(.primary)
                
                Text("Your account is pending approval from an administrator. You'll be notified once your account has been approved.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Display user's email address for confirmation
                if let email = appState.currentUser?.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Error message
                if let error = refreshError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // Refresh Status button
                Button(action: {
                    Task {
                        await refreshStatus()
                    }
                }) {
                    if isRefreshing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Refresh Status")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
                .padding(.horizontal)
                
                // Log Out button
                Button(action: {
                    Task {
                        try? await AuthService.shared.signOut()
                    }
                }) {
                    Text("Log Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            .padding()
        }
        .refreshable {
            await refreshStatus()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
    }
    
    private func refreshStatus() async {
        isRefreshing = true
        refreshError = nil
        
        do {
            // Recheck auth status which will fetch current profile
            let authState = try await AuthService.shared.checkAuthStatus()
            
            // If approved, navigation will be handled by ContentView
            if authState == .authenticated {
                // Profile was approved, app state will update automatically
                print("✅ Account approved!")
            }
        } catch {
            refreshError = AppError.processingError(error.localizedDescription)
        }
        
        isRefreshing = false
    }
}

#Preview {
    PendingApprovalView()
        .environmentObject(AppState())
}

