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
    
    private init() {
        print("🔧 [AppLaunchManager] Initializing - setting up notification listener")
        
        // Use direct NotificationCenter observer instead of Combine for reliability
        let notificationName = NSNotification.Name("userDidSignOut")
        print("🔧 [AppLaunchManager] Setting up observer for notification: '\(notificationName.rawValue)'")
        
        signOutObserver = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("📬 [AppLaunchManager] Received userDidSignOut notification!")
            print("📬 [AppLaunchManager] Notification name: \(notification.name.rawValue)")
            print("📬 [AppLaunchManager] Notification object: \(String(describing: notification.object))")
            
            guard let self = self else {
                print("⚠️ [AppLaunchManager] Self is nil, cannot update state")
                return
            }
            
            // Immediately set state to unauthenticated when sign out happens
            // Since AppLaunchManager is @MainActor, this is safe to do synchronously
            print("🔄 [AppLaunchManager] Setting state to unauthenticated immediately")
            print("🔄 [AppLaunchManager] Current state before update: \(self.state.id)")
            self.state = .ready(.unauthenticated)
            print("✅ [AppLaunchManager] State updated to: \(self.state.id)")
        }
        
        print("✅ [AppLaunchManager] Notification listener set up successfully")
        print("✅ [AppLaunchManager] Observer stored: \(signOutObserver != nil ? "YES" : "NO")")
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
        state = .checkingAuth
        
        do {
            // Step 1: Check for existing session (fast - reads from keychain)
            let session = try await supabase.auth.session
            
            // Extract user ID from session
            let userIdString = session.user.id.uuidString
            guard let userId = UUID(uuidString: userIdString) else {
                // No valid user ID - ready for login
                state = .ready(.unauthenticated)
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
            Task.detached(priority: .userInitiated) { [userId] in
                await self.performDeferredLoading(userId: userId)
            }
            
        } catch {
            // Session check failed - treat as unauthenticated
            state = .ready(.unauthenticated)
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
            print("⚠️ [AppLaunchManager] Lightweight approval check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// Check approval status with minimal query (only 'approved' field)
    /// - Parameter userId: User ID to check
    /// - Returns: true if user is approved, false otherwise
    private func checkApprovalStatus(userId: UUID) async -> Bool {
        do {
            // Minimal query - only fetch the 'approved' field
            struct ProfileApproval: Codable {
                let approved: Bool
            }
            
            print("🔍 [AppLaunchManager] Checking approval status for user: \(userId)")
            
            let response: ProfileApproval = try await supabase
                .from("profiles")
                .select("approved")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            print("✅ [AppLaunchManager] Approval status for user \(userId): \(response.approved)")
            return response.approved
        } catch {
            // Log error for debugging
            print("⚠️ [AppLaunchManager] Failed to check approval status for user \(userId): \(error.localizedDescription)")
            print("⚠️ [AppLaunchManager] Error details: \(error)")
            // If query fails, assume not approved (safer default)
            return false
        }
    }
    
    /// Perform deferred loading of non-critical data in background
    /// - Parameter userId: Authenticated user ID
    private func performDeferredLoading(userId: UUID) async {
        // This will be called after critical path completes
        // Load profile, rides, favors, etc. in background
        
        // Update AuthService with full profile
        try? await authService.checkAuthStatus()
        
        // Note: Additional background loading (rides, favors, etc.)
        // will be handled by respective ViewModels when views appear
    }
}

