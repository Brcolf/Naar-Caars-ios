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
    @Environment(AppState.self) var appState
    @Environment(\.scenePhase) var scenePhase

    private var lockManager = AppLockManager.shared

    private var isAuthenticated: Bool {
        if case .ready(let authState) = launchManager.state {
            return authState == .authenticated || authState == .pendingApproval || authState == .needsApplication
        }
        return false
    }

    var body: some View {
        ZStack {
            Group {
                switch launchManager.state {
            case .initializing, .checkingAuth:
                LoadingView(message: "common_loading".localized)

                case .ready(let authState):
                    switch authState {
                    case .loading:
                        LoadingView(message: "app_loading".localized)

                    case .unauthenticated:
                        NavigationStack {
                            WelcomeView()
                        }

                    case .needsApplication:
                        NavigationStack {
                            ApplicationFieldsView()
                        }

                    case .pendingApproval:
                        PendingApprovalView()

                    case .banned:
                        BannedAccountView()

                    case .authenticated:
                        MainTabView()
                    }

                case .failed(let error):
                    VStack(spacing: 16) {
                        Text(String(format: "app_error_format".localized, error.localizedDescription))
                        Button("app_retry".localized) {
                            Task {
                                await launchManager.performCriticalLaunch()
                            }
                        }
                    }
                }
            }
            .blur(radius: lockManager.state != .unlocked ? 20 : 0)
            .disabled(lockManager.state != .unlocked)

            // Lock screen overlay
            if lockManager.state != .unlocked {
                AppLockView(lockManager: lockManager)
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
        // Note: Removed .id() modifier that was causing view recreation loops
        // The view will update naturally when launchManager.state changes
        .animation(.easeInOut(duration: 0.3), value: launchManager.state.id)
        .animation(.easeInOut(duration: 0.3), value: lockManager.state)
        .task(id: "initial_launch") {
            let launchTaskStart = Date()
            // Only perform critical launch once on initial appear
            // Subsequent state changes are handled by specific actions (login, signup, etc.)
            guard case .initializing = launchManager.state else { return }
            await launchManager.performCriticalLaunch()

            // Check if biometric unlock is needed on launch
            lockManager.checkOnLaunch(isAuthenticated: isAuthenticated)
            await PerformanceMonitor.shared.record(
                operation: "launch.initialContentTask",
                duration: Date().timeIntervalSince(launchTaskStart),
                metadata: ["state": launchManager.state.id]
            )
        }
        .onChange(of: launchManager.state.id) { oldId, newId in
            // React to state ID changes (e.g., sign out triggers state change)
            AppLogger.info("app", "Launch state ID changed from '\(oldId)' to '\(newId)'")
            if newId.contains("unauthenticated") {
                AppLogger.info("app", "Switching to login view")
                lockManager.forceUnlock()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            AppLogger.info("lock", "scenePhase: \(oldPhase) → \(newPhase), lockState=\(lockManager.state)")
            if newPhase == .active, isAuthenticated {
                Task { await AuthService.shared.restartRealtimeSyncEngines() }
                Task { await launchManager.recheckBanStatus() }
            }
            lockManager.handleScenePhase(newPhase, isAuthenticated: isAuthenticated)
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
            // AppLaunchManager already handles state change on sign out notification
            // Just log for debugging - don't call performCriticalLaunch again
            AppLogger.info("app", "Received userDidSignOut notification - AppLaunchManager will update state")
            lockManager.forceUnlock()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
