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
    @Environment(\.scenePhase) var scenePhase
    
    @State private var isLocked = false
    @State private var lastBackgroundDate: Date?
    
    private let lockTimeout: TimeInterval = 300  // 5 minutes
    private let biometricPreferences = BiometricPreferences.shared
    
    var body: some View {
        ZStack {
            Group {
                switch launchManager.state {
            case .initializing, .checkingAuth:
                LoadingView(message: "common_loading".localized)
                    
                case .ready(let authState):
                    switch authState {
                    case .loading:
                        LoadingView(message: "Loading...")
                        
                    case .unauthenticated:
                        NavigationStack {
                            LoginView()
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
            .blur(radius: isLocked ? 20 : 0)
            .disabled(isLocked)
            
            // Lock screen overlay
            if isLocked {
                AppLockView(
                    onUnlock: {
                        withAnimation {
                            isLocked = false
                        }
                    },
                    onCancel: nil
                )
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .id(launchManager.state.id) // Force view recreation when state changes
        .animation(.easeInOut(duration: 0.3), value: launchManager.state.id)
        .task {
            // Perform critical launch on appear
            await launchManager.performCriticalLaunch()
            
            // Check if biometric unlock is needed on launch
            await checkBiometricUnlockOnLaunch()
        }
        .onChange(of: launchManager.state.id) { oldId, newId in
            // React to state ID changes (e.g., sign out triggers state change)
            print("🔄 [ContentView] Launch state ID changed from '\(oldId)' to '\(newId)'")
            if newId.contains("unauthenticated") {
                print("✅ [ContentView] Switching to login view")
                // Clear lock state on sign out
                isLocked = false
                lastBackgroundDate = nil
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("userDidSignOut"))) { _ in
            // AppLaunchManager already handles state change on sign out notification
            // Just log for debugging - don't call performCriticalLaunch again
            print("🔄 [ContentView] Received userDidSignOut notification - AppLaunchManager will update state")
            // Clear lock state on sign out
            isLocked = false
            lastBackgroundDate = nil
        }
    }
    
    // MARK: - Private Methods
    
    /// Check if biometric unlock is needed on app launch
    private func checkBiometricUnlockOnLaunch() async {
        // Only check if user is authenticated or pending approval
        guard case .ready(let authState) = launchManager.state,
              authState == .authenticated || authState == .pendingApproval else {
            return
        }
        
        // Only check if biometrics are enabled and required on launch
        guard biometricPreferences.isBiometricsEnabled,
              biometricPreferences.requireBiometricsOnLaunch else {
            return
        }
        
        // Check if re-authentication is needed
        if biometricPreferences.needsReauthentication(timeout: lockTimeout) {
            await MainActor.run {
                withAnimation {
                    isLocked = true
                }
            }
        }
    }
    
    /// Handle scene phase changes (background/foreground)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        // Only handle if user is authenticated or pending approval
        guard case .ready(let authState) = launchManager.state,
              authState == .authenticated || authState == .pendingApproval else {
            return
        }
        
        // Only handle if biometrics are enabled and required on launch
        guard biometricPreferences.isBiometricsEnabled,
              biometricPreferences.requireBiometricsOnLaunch else {
            return
        }
        
        switch newPhase {
        case .background:
            // App went to background - record timestamp
            lastBackgroundDate = Date()
            
        case .active:
            // App became active - check if lock is needed
            if let lastBackground = lastBackgroundDate {
                let timeInBackground = Date().timeIntervalSince(lastBackground)
                if timeInBackground > lockTimeout {
                    // More than 5 minutes in background - require unlock
                    withAnimation {
                        isLocked = true
                    }
                }
            }
            
        case .inactive:
            // App is inactive (e.g., during transition) - do nothing
            break
            
        @unknown default:
            break
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
