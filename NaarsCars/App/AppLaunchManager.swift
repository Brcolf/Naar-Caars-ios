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
             (.checkingAuth, .checkingAuth),
             (.ready, .ready),
             (.failed, .failed):
            return true
        default:
            return false
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
    
    private init() {}
    
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
            
            let response: ProfileApproval = try await supabase
                .from("profiles")
                .select("approved")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            return response.approved
        } catch {
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

