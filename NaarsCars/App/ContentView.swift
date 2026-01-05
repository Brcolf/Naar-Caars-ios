//
//  ContentView.swift
//  NaarsCars
//
//  Root view handling authentication states and navigation
//

import SwiftUI

/// Root content view that handles authentication states
/// Matches FR-039 from prd-foundation-architecture.md
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            switch appState.authState {
            case .loading:
                LoadingView(message: "Loading...")
                
            case .unauthenticated:
                // Placeholder for login/signup view
                VStack(spacing: 20) {
                    Text("Naar's Cars")
                        .font(.largeTitle)
                    
                    Text("Login View")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                }
                
            case .pendingApproval:
                PendingApprovalView()
                
            case .authenticated:
                MainTabView()
            }
        }
        .task {
            // Check authentication status on appear
            await appState.checkAuthStatus()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
