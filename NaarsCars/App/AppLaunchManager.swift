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
        let notificationName = NSNotification.Name("userDidSignOut")
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
            
            // Step 2: Minimal approval check (query only 'approved' field)
            let isApproved = await checkApprovalStatus(userId: userId)
            
            if isApproved {
                // User is approved - ready for main app
                state = .ready(.authenticated)
            } else {
                // User is pending approval
                state = .ready(.pendingApproval)
            }
            
            // Step 3: Start deferred loading in background (non-blocking)
            Task(priority: .userInitiated) { [weak self, userId] in
                guard let self else { return }
                await self.performDeferredLoading(userId: userId)
            }
            await recordLaunchDuration(
                start: launchStart,
                result: "success",
                metadata: [
                    "state": state.id,
                    "approved": isApproved,
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
            return await checkApprovalStatus(userId: userId)
        } catch {
            AppLogger.warning("launch", "Lightweight approval check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// Check approval status with minimal query (only 'approved' field)
    /// - Parameter userId: User ID to check
    /// - Returns: true if user is approved, false otherwise
    private func checkApprovalStatus(userId: UUID) async -> Bool {
        let start = Date()
        do {
            // Minimal query - only fetch the 'approved' field
            struct ProfileApproval: Codable {
                let approved: Bool
            }
            
            AppLogger.info("launch", "Checking approval status for user: \(userId)")
            
            let response: ProfileApproval = try await supabase
                .from("profiles")
                .select("approved")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            AppLogger.info("launch", "Approval status for user \(userId): \(response.approved)")
            await PerformanceMonitor.shared.record(
                operation: "launch.approvalCheck",
                duration: Date().timeIntervalSince(start),
                metadata: ["approved": response.approved],
                slowThreshold: 0.5
            )
            return response.approved
        } catch {
            // Log error for debugging
            AppLogger.warning("launch", "Failed to check approval status for user \(userId): \(error.localizedDescription)")
            AppLogger.warning("launch", "Error details: \(error)")
            await PerformanceMonitor.shared.record(
                operation: "launch.approvalCheck",
                duration: Date().timeIntervalSince(start),
                metadata: [
                    "approved": false,
                    "error": error.localizedDescription
                ],
                slowThreshold: 0.5
            )
            // If query fails, assume not approved (safer default)
            return false
        }
    }
    
    /// Perform deferred loading of non-critical data in background
    /// - Parameter userId: Authenticated user ID
    private func performDeferredLoading(userId: UUID) async {
        let start = Date()
        // This will be called after critical path completes
        // Load profile, rides, favors, etc. in background
        startDeferredSyncEnginesIfNeeded(for: userId)
        
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
