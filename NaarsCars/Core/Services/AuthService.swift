//
//  AuthService.swift
//  NaarsCars
//
//  Authentication service for managing user sessions and authentication state
//

import Foundation
import Supabase
internal import Combine

/// Service for managing user authentication and session state
/// Handles sign in, sign up, sign out, password reset, and session lifecycle
@MainActor
final class AuthService: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared singleton instance
    static let shared = AuthService()
    
    // MARK: - Published Properties
    
    /// Current authenticated user ID, nil if not authenticated
    @Published var currentUserId: UUID?
    
    /// Current user's profile, nil if not authenticated or profile not loaded
    @Published var currentProfile: Profile?
    
    /// Loading state for authentication operations
    @Published var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    /// Supabase service reference
    private let supabase = SupabaseService.shared
    
    // MARK: - Initialization
    
    private init() {
        // Private initializer to enforce singleton pattern
    }
    
    // MARK: - Authentication Methods
    
    /// Check current authentication status and load user profile if authenticated
    /// - Returns: AuthState indicating current authentication status
    func checkAuthStatus() async throws -> AuthState {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get current Supabase session
            let session = try await supabase.client.auth.session
            
            // Session exists, fetch user profile
            guard let userId = UUID(uuidString: session.user.id.uuidString) else {
                currentUserId = nil
                currentProfile = nil
                return .unauthenticated
            }
            
            // Fetch profile from database
            let profile = try await fetchCurrentProfile()
            
            if let profile = profile {
                currentUserId = userId
                currentProfile = profile
                
                // Check approval status
                if !profile.approved {
                    return .pendingApproval
                } else {
                    return .authenticated
                }
            } else {
                // Session exists but profile doesn't (data inconsistency)
                // This shouldn't happen if database triggers are set up correctly
                currentUserId = userId
                currentProfile = nil
                return .unauthenticated
            }
        } catch {
            // Handle network failures and database errors
            print("🔴 Error checking auth status: \(error.localizedDescription)")
            currentUserId = nil
            currentProfile = nil
            return .unauthenticated
        }
    }
    
    /// Sign in with email and password
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    /// - Throws: AppError if authentication fails
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Call Supabase auth.signIn()
            let response = try await supabase.client.auth.signIn(
                email: email,
                password: password
            )
            
            guard let userId = UUID(uuidString: response.user.id.uuidString) else {
                throw AppError.processingError("Invalid user ID")
            }
            
            // Fetch user profile
            let profile = try await fetchCurrentProfile()
            
            // Update currentUserId and currentProfile
            currentUserId = userId
            currentProfile = profile
            
            if let profile = profile {
                print("✅ Sign in successful for user: \(email), approved: \(profile.approved)")
            } else {
                print("⚠️ Sign in successful but profile not found for user: \(email)")
            }
        } catch {
            // Handle errors with appropriate AppError types
            let errorMessage = error.localizedDescription.lowercased()
            
            if errorMessage.contains("invalid") && errorMessage.contains("credential") {
                throw AppError.invalidCredentials
            } else if errorMessage.contains("email") && errorMessage.contains("confirm") {
                throw AppError.processingError("Please confirm your email address")
            } else {
                throw AppError.processingError(error.localizedDescription)
            }
        }
    }
    
    /// Sign up with email, password, and invite code
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - inviteCode: Valid invite code
    /// - Throws: AppError if sign up fails
    func signUp(email: String, password: String, inviteCode: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Validate invite code first
            let validatedInviteCode = try await self.validateInviteCode(inviteCode)
            
            // Call Supabase auth.signUp()
            let response = try await supabase.client.auth.signUp(
                email: email,
                password: password
            )
            
            guard let userId = UUID(uuidString: response.user.id.uuidString) else {
                throw AppError.processingError("Invalid user ID")
            }
            
            // Profile creation is handled by database trigger (handle_new_user)
            // Wait a moment for trigger to complete, then fetch profile
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Fetch user profile
            let profile = try await fetchCurrentProfile()
            
            // Update currentUserId and currentProfile
            currentUserId = userId
            currentProfile = profile
            
            // Mark invite code as used
            try await supabase.client
                .from("invite_codes")
                .update(["used_by": userId.uuidString, "used_at": Date().ISO8601Format()])
                .eq("id", value: validatedInviteCode.id.uuidString)
                .execute()
            
            print("✅ Sign up successful for user: \(email)")
        } catch {
            // Handle errors with appropriate AppError types
            let errorMessage = error.localizedDescription.lowercased()
            
            if errorMessage.contains("already") && errorMessage.contains("registered") {
                throw AppError.emailAlreadyExists
            } else {
                throw AppError.processingError(error.localizedDescription)
            }
        }
    }
    
    /// Sign out current user
    /// Clears session, profile, and cache
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Call Supabase auth.signOut()
            // This will trigger .signedOut event in setupAuthStateListener
            // which will call handleSignOut() to post the notification
            try await supabase.client.auth.signOut()
            
            // Also call handleSignOut() directly to ensure cleanup happens
            // and notification is posted (in case auth state listener doesn't fire immediately)
            await handleSignOut()
            
            print("✅ Auth: User signed out successfully")
        } catch {
            // Even if sign out fails, clear local state and post notification
            print("⚠️ Error during sign out: \(error.localizedDescription)")
            await handleSignOut()
            throw AppError.processingError(error.localizedDescription)
        }
    }
    
    /// Send password reset email
    /// - Parameter email: User's email address
    /// - Throws: AppError if request fails
    func sendPasswordReset(email: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Call Supabase auth.resetPasswordForEmail()
            try await supabase.client.auth.resetPasswordForEmail(
                email,
                redirectTo: nil
            )
            
            // Always show success message regardless of email existence (prevent enumeration)
            print("✅ Password reset email sent (or would be sent if email exists)")
        } catch {
            // Catch and ignore errors - never reveal if email exists
            // This prevents email enumeration attacks
            print("⚠️ Password reset requested for: \(email) (error hidden for security)")
            // Don't throw error - always show success message to user
        }
    }
    
    /// Validate invite code
    /// - Parameter code: Invite code to validate
    /// - Returns: Validated InviteCode if successful
    /// - Throws: AppError if validation fails
    func validateInviteCode(_ code: String) async throws -> InviteCode {
        // 1. Normalize code (uppercase, trim whitespace)
        let normalized = InviteCodeGenerator.normalize(code)
        
        // 2. Validate format
        guard InviteCodeGenerator.isValidFormat(normalized) else {
            // Return same error for invalid format as for not found (prevent enumeration)
            throw AppError.invalidInviteCode
        }
        
        // 3. Rate limit check: 3 seconds between validation attempts
        let rateLimitAction = "validate_invite_code"
        let rateLimitAllowed = await RateLimiter.shared.checkAndRecord(
            action: rateLimitAction,
            minimumInterval: 3.0
        )
        
        guard rateLimitAllowed else {
            throw AppError.rateLimitExceeded("Please wait a moment before trying again.")
        }
        
        // 4. Query invite_codes table for matching code where used_by IS NULL
        do {
            let response = try await supabase.client
                .from("invite_codes")
                .select()
                .eq("code", value: normalized)
                .is("used_by", value: nil)
                .single()
                .execute()
            
            // 5. Decode and return InviteCode
            let inviteCode = try JSONDecoder().decode(InviteCode.self, from: response.data)
            
            // 6. Check expiration for bulk codes (48 hours)
            if inviteCode.isBulk {
                if let expiresAt = inviteCode.expiresAt, Date() > expiresAt {
                    throw AppError.invalidInviteCode // Expired bulk code
                }
            } else {
                // Regular codes: if already used, reject (single-use)
                if inviteCode.isUsed {
                    throw AppError.invalidInviteCode
                }
            }
            
            return inviteCode
            
        } catch {
            // 6. Return same error for "not found" and "already used" (prevent enumeration)
            // This prevents attackers from discovering which codes exist
            throw AppError.invalidInviteCode
        }
    }
    
    // MARK: - Helper Methods
    
    /// Handle sign out with complete cleanup
    /// Clears all local state, caches, and realtime subscriptions
    /// Posts notification to trigger app state change
    private func handleSignOut() async {
        print("🔄 [AuthService] handleSignOut() started")
        
        // Clear local state on main actor
        await MainActor.run {
            currentUserId = nil
            currentProfile = nil
        }
        print("✅ [AuthService] Local state cleared")
        
        // Clear caches
        await CacheManager.shared.clearAll()
        print("✅ [AuthService] Cache cleared")
        
        // Unsubscribe from all realtime channels
        await RealtimeManager.shared.unsubscribeAll()
        print("✅ [AuthService] Realtime unsubscribed")
        
        // Post notification for app state updates on main thread
        // CRITICAL: Must post on main thread for observer to receive it
        await MainActor.run {
            print("📢 [AuthService] Posting userDidSignOut notification on main thread")
            let notificationName = NSNotification.Name("userDidSignOut")
            print("📢 [AuthService] Notification name: '\(notificationName.rawValue)'")
            NotificationCenter.default.post(name: notificationName, object: nil, userInfo: nil)
            print("✅ [AuthService] userDidSignOut notification posted successfully")
        }
        
        print("✅ Auth: Sign out cleanup completed")
    }
    
    /// Fetch current user's profile from database
    /// - Returns: Profile if found, nil otherwise
    private func fetchCurrentProfile() async throws -> Profile? {
        // Get current user ID from Supabase session
        guard let session = try? await supabase.client.auth.session,
              let userId = UUID(uuidString: session.user.id.uuidString) else {
            return nil
        }
        
        do {
            // Query profiles table
            let profile: Profile = try await supabase.client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            return profile
        } catch {
            // Handle errors - profile might not exist yet
            print("⚠️ Error fetching profile: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Authentication state enum
enum AuthState {
    case loading
    case unauthenticated
    case pendingApproval
    case authenticated
}

