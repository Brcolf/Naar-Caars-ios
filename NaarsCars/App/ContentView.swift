//
//  ContentView.swift
//  NaarsCars
//
//  Root view handling authentication states and navigation
//

import SwiftUI

/// Root content view that handles authentication states
/// Uses AppLaunchManager for critical-path launch management (FR-051)
/// Matches FR-039 from prd-foundation-architecture.md
struct ContentView: View {
    @StateObject private var launchManager = AppLaunchManager.shared
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            switch launchManager.state {
            case .initializing, .checkingAuth:
                LoadingView(message: "Loading...")
                
            case .ready(let authState):
                switch authState {
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
                
            case .failed(let error):
                VStack(spacing: 16) {
                    Text("Error: \(error.localizedDescription)")
                    Button("Retry") {
                        Task {
                            await launchManager.performCriticalLaunch()
                        }
                    }
                }
            }
        }
        .task {
            // Perform critical launch on appear
            await launchManager.performCriticalLaunch()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
