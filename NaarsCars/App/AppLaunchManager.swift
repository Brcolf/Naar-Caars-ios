//
//  AppLaunchManager.swift
//  NaarsCars
//
//  Critical-path launch management for fast app startup
//

import Foundation
import SwiftUI
import Supabase
internal import Combine

/// Launch state enum for app initialization
enum LaunchState: Equatable {
    case initializing
    case checkingAuth
    case ready(AuthState)
    case failed(Error)
    
    static func == (lhs: LaunchState, rhs: LaunchState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing),
             (.checkingAuth, .checkingAuth):
            return true
        case (.ready(let lhsState), .ready(let rhsState)):
            return lhsState == rhsState
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
    
    /// Unique identifier for the state to force view updates
    var id: String {
        switch self {
        case .initializing:
            return "initializing"
        case .checkingAuth:
            return "checkingAuth"
        case .ready(let authState):
            return "ready_\(authState)"
        case .failed(let error):
            return "failed_\(error.localizedDescription)"
        }
    }
}

/// Manages critical-path app launch to complete in <1 second
/// Performs minimal checks (auth session + approval) before showing UI
/// Defers non-critical loading (profile, rides, etc.) to background
@MainActor
final class AppLaunchManager: ObservableObject {
    
    /// Shared singleton instance
    static let shared = AppLaunchManager()
    
    /// Current launch state
    @Published var state: LaunchState = .initializing
    
    /// Supabase client reference
    private let supabase = SupabaseService.shared.client
    
    /// Auth service reference
    private let authService = AuthService.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var signOutObserver: NSObjectProtocol?
    private var deferredSyncStartedForUserId: UUID?
    
    private init() {
        AppLogger.info("launch", "Initializing - setting up notification listener")
        
        // Use direct NotificationCenter observer instead of Combine for reliability
        let notificationName: Notification.Name = .userDidSignOut
        AppLogger.info("launch", "Setting up observer for notification: '\(notificationName.rawValue)'")
        
        signOutObserver = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            AppLogger.info("launch", "Received userDidSignOut notification")
            AppLogger.info("launch", "Notification name: \(notification.name.rawValue)")
            AppLogger.info("launch", "Notification object: \(String(describing: notification.object))")
            
            guard let self = self else {
                AppLogger.warning("launch", "Self is nil, cannot update state")
                return
            }
            
            // Immediately set state to unauthenticated when sign out happens
            // Since AppLaunchManager is @MainActor, this is safe to do synchronously
            AppLogger.info("launch", "Setting state to unauthenticated immediately")
            AppLogger.info("launch", "Current state before update: \(self.state.id)")
            self.deferredSyncStartedForUserId = nil
            self.state = .ready(.unauthenticated)
            AppLogger.info("launch", "State updated to: \(self.state.id)")
        }
        
        AppLogger.info("launch", "Notification listener set up successfully")
        AppLogger.info("launch", "Observer stored: \(signOutObserver != nil ? "YES" : "NO")")
    }
    
    deinit {
        // Remove observer when deallocated
        if let observer = signOutObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Critical Launch Path
    
    /// Perform critical launch operations (auth session + approval check only)
    /// Target: Complete in <1 second per FR-051
    func performCriticalLaunch() async {
        let launchStart = Date()
        state = .checkingAuth
        
        do {
            // Step 1: Check for existing session (fast - reads from keychain)
            let session = try await supabase.auth.session
            
            // Extract user ID from session
            let userIdString = session.user.id.uuidString
            guard let userId = UUID(uuidString: userIdString) else {
                // No valid user ID - ready for login
                state = .ready(.unauthenticated)
                await recordLaunchDuration(
                    start: launchStart,
                    result: "invalid_user_id",
                    metadata: ["state": state.id]
                )
                return
            }
            
            // Step 2: Check account lifecycle (approved + application_complete)
            let authState = await checkAccountStatus(userId: userId)
            state = .ready(authState)

            // Step 3: Start deferred loading in background (non-blocking)
            if authState == .authenticated {
                Task(priority: .userInitiated) { [weak self, userId] in
                    guard let self else { return }
                    await self.performDeferredLoading(userId: userId)
                }
            }
            await recordLaunchDuration(
                start: launchStart,
                result: "success",
                metadata: [
                    "state": state.id,
                    "authState": "\(authState)",
                    "hasSession": true
                ]
            )
            
        } catch {
            // Session check failed - treat as unauthenticated
            state = .ready(.unauthenticated)
            await recordLaunchDuration(
                start: launchStart,
                result: "session_missing_or_invalid",
                metadata: [
                    "state": state.id,
                    "error": error.localizedDescription
                ]
            )
        }
    }
    
    // MARK: - Public Methods
    
    /// Lightweight approval check for use by PendingApprovalView
    /// Does NOT change state to checkingAuth (prevents state loops)
    /// - Returns: true if current user is approved, false otherwise
    func checkApprovalStatusOnly() async -> Bool {
        do {
            let session = try await supabase.auth.session
            let userIdString = session.user.id.uuidString
            guard let userId = UUID(uuidString: userIdString) else {
                return false
            }
            let status = await checkAccountStatus(userId: userId)
            return status == .authenticated
        } catch {
            AppLogger.warning("launch", "Lightweight approval check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Lightweight ban re-check for use on app foreground.
    /// If user is now banned, transitions state to .banned.
    func recheckBanStatus() async {
        guard case .ready(.authenticated) = state else { return }
        do {
            let session = try await supabase.auth.session
            guard let userId = UUID(uuidString: session.user.id.uuidString) else { return }
            let status = await checkAccountStatus(userId: userId)
            if status == .banned {
                state = .ready(.banned)
            }
        } catch {
            AppLogger.warning("launch", "Ban re-check failed: \(error.localizedDescription)")
        }
    }

    /// Enter guest browsing mode without creating a Supabase session.
    /// Callers must also set `appState.isGuestMode = true` before calling this.
    /// No session, no profile, no deferred loading, no sync engines.
    func enterGuestMode() {
        state = .ready(.guest)
    }

    /// Exit guest mode and return to the unauthenticated welcome screen.
    /// Callers must also set `appState.isGuestMode = false` before calling this.
    func exitGuestMode() {
        state = .ready(.unauthenticated)
    }

    // MARK: - Private Methods
    
    /// Check account status with minimal query (approved + application_complete)
    /// - Parameter userId: User ID to check
    /// - Returns: The appropriate AuthState for the user
    private func checkAccountStatus(userId: UUID) async -> AuthState {
        let start = Date()
        do {
            struct ProfileStatus: Codable {
                let isBanned: Bool
                let approved: Bool
                let applicationComplete: Bool

                enum CodingKeys: String, CodingKey {
                    case isBanned = "is_banned"
                    case approved
                    case applicationComplete = "application_complete"
                }
            }

            AppLogger.info("launch", "Checking account status for user: \(userId)")

            let response: ProfileStatus = try await supabase
                .from("profiles")
                .select("is_banned, approved, application_complete")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            AppLogger.info("launch", "Account status for user \(userId): isBanned=\(response.isBanned), approved=\(response.approved), applicationComplete=\(response.applicationComplete)")
            await PerformanceMonitor.shared.record(
                operation: "launch.approvalCheck",
                duration: Date().timeIntervalSince(start),
                metadata: ["isBanned": response.isBanned, "approved": response.approved, "applicationComplete": response.applicationComplete],
                slowThreshold: 0.5
            )

            if response.isBanned {
                return .banned
            } else if response.approved {
                return .authenticated
            } else if !response.applicationComplete {
                return .needsApplication
            } else {
                return .pendingApproval
            }
        } catch {
            AppLogger.warning("launch", "Failed to check account status for user \(userId): \(error.localizedDescription)")
            await PerformanceMonitor.shared.record(
                operation: "launch.approvalCheck",
                duration: Date().timeIntervalSince(start),
                metadata: ["error": error.localizedDescription],
                slowThreshold: 0.5
            )
            // If query fails, assume needs application (safer default)
            return .needsApplication
        }
    }
    
    /// Perform deferred loading of non-critical data in background
    /// - Parameter userId: Authenticated user ID
    private func performDeferredLoading(userId: UUID) async {
        let start = Date()

        // Ensure AuthService has the userId before sync engines start.
        // performCriticalLaunch() reads the userId from the JWT session but
        // doesn't set it on AuthService — sync engines check
        // authService.currentUserId for user-specific subscriptions and data
        // fetches, so it must be populated first.
        if authService.currentUserId == nil {
            authService.currentUserId = userId
        }

        startDeferredSyncEnginesIfNeeded(for: userId)

        // Refresh blocked users cache for content filtering
        await MessageService.shared.refreshBlockedUsers()

        // Update AuthService with full profile
        try? await authService.checkAuthStatus()
        
        // Note: Additional background loading (rides, favors, etc.)
        // will be handled by respective ViewModels when views appear
        await PerformanceMonitor.shared.record(
            operation: "launch.deferredLoading",
            duration: Date().timeIntervalSince(start),
            metadata: ["userId": userId.uuidString]
        )
    }

    private func startDeferredSyncEnginesIfNeeded(for userId: UUID) {
        guard deferredSyncStartedForUserId != userId else { return }
        deferredSyncStartedForUserId = userId
        SyncEngineOrchestrator.shared.startAll()
    }

    private func recordLaunchDuration(start: Date, result: String, metadata: [String: Any] = [:]) async {
        var payload = metadata
        payload["result"] = result
        await PerformanceMonitor.shared.record(
            operation: "launch.performCriticalLaunch",
            duration: Date().timeIntervalSince(start),
            metadata: payload,
            slowThreshold: Constants.Performance.launchCriticalPathSlowThreshold
        )
    }
}
