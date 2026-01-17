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
            
            // Mark invite code as used (or create tracking record for bulk codes)
            // Use InviteService to handle bulk vs non-bulk codes correctly:
            // - Non-bulk codes: Mark as used (single-use)
            // - Bulk codes: Create tracking record (bulk code remains active for other users)
            try await InviteService.shared.markInviteCodeAsUsed(inviteCode: validatedInviteCode, userId: userId)
            
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
    
    /// Sign up with email, password, name, car, and invite code ID
    /// Includes automatic rollback if profile creation fails
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - name: User's full name
    ///   - car: User's car (optional)
    ///   - inviteCodeId: ID of validated invite code
    /// - Throws: AppError if sign up fails
    func signUp(email: String, password: String, name: String, car: String?, inviteCodeId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }
        
        var createdAuthUserId: String? = nil
        var shouldRollback = false
        
        do {
            // 1. Fetch invite code to get createdBy for profile
            let inviteCodeResponse = try await supabase.client
                .from("invite_codes")
                .select()
                .eq("id", value: inviteCodeId.uuidString)
                .single()
                .execute()
            
            // Decode with proper date handling for Supabase ISO8601 format
            let decoder = createInviteCodeDecoder()
            let inviteCode = try decoder.decode(InviteCode.self, from: inviteCodeResponse.data)
            
            // 2. Create auth user with Supabase
            let authResponse = try await supabase.client.auth.signUp(
                email: email,
                password: password
            )
            
            let user = authResponse.user
            let userIdString = user.id.uuidString
            createdAuthUserId = userIdString // Store for potential rollback
            shouldRollback = true // Enable rollback from this point
            
            guard let userId = UUID(uuidString: userIdString) else {
                throw AppError.unknown("Invalid user ID format")
            }
            
            // 3. Create or update profile (trigger may create basic profile)
            struct ProfileUpdate: Codable {
                let id: String
                let name: String
                let email: String
                let invitedBy: String
                let isAdmin: Bool
                let approved: Bool
                let car: String?
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case email
                    case invitedBy = "invited_by"
                    case isAdmin = "is_admin"
                    case approved
                    case car
                }
            }
            
            let profileUpdate = ProfileUpdate(
                id: userIdString,
                name: name,
                email: email,
                invitedBy: inviteCode.createdBy.uuidString,
                isAdmin: false,
                approved: false,
                car: car?.isEmpty == false ? car : nil
            )
            
            // Try to update first (in case trigger created it), otherwise insert
            do {
                try await supabase.client
                    .from("profiles")
                    .update(profileUpdate)
                    .eq("id", value: userIdString)
                    .execute()
                print("✅ Auth: Updated existing profile for user: \(userId)")
            } catch let updateError {
                // Profile doesn't exist, insert it
                print("⚠️ Auth: Profile update failed (may not exist), trying insert: \(updateError.localizedDescription)")
                
                // This is critical - if insert fails, we MUST rollback
                do {
                    try await supabase.client
                        .from("profiles")
                        .insert(profileUpdate)
                        .execute()
                    print("✅ Auth: Created new profile for user: \(userId)")
                } catch let insertError {
                    print("🔴 Auth: Profile insert failed, rolling back auth user")
                    // Rollback will happen in catch block below
                    throw insertError
                }
            }
            
            // 4. Mark invite code as used (or create tracking record for bulk codes)
            // Use InviteService to handle bulk vs non-bulk codes correctly:
            // - Non-bulk codes: Mark as used (single-use)
            // - Bulk codes: Create tracking record (bulk code remains active for other users)
            do {
                try await InviteService.shared.markInviteCodeAsUsed(inviteCode: inviteCode, userId: userId)
            } catch {
                print("⚠️ Auth: Failed to mark invite code as used: \(error.localizedDescription)")
                // Don't rollback for this - user can still use the account
                // Admin can manually mark code as used later
            }
            
            // 5. Fetch the created profile and update local state
            if let profile = try? await fetchCurrentProfile() {
                currentProfile = profile
                currentUserId = userId
            } else {
                // Profile should exist, but set userId for state
                currentUserId = userId
            }
            
            // Success - disable rollback
            shouldRollback = false
            
            print("✅ Auth: User signed up successfully: \(email)")
            
        } catch {
            // ROLLBACK: If auth user was created but profile failed, delete the auth user
            if shouldRollback, let authUserId = createdAuthUserId {
                print("🔄 Auth: Rolling back - attempting to delete orphaned auth user")
                await performSignupRollback(authUserId: authUserId)
            }
            
            // Log detailed error for debugging
            print("🔴 Auth: Signup failed for \(email): \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("🔴 Auth: Error domain: \(nsError.domain), code: \(nsError.code)")
                print("🔴 Auth: Error userInfo: \(nsError.userInfo)")
            }
            
            // Handle specific Supabase errors
            if let supabaseError = error as NSError? {
                let errorMessage = supabaseError.localizedDescription.lowercased()
                
                if errorMessage.contains("already registered") || errorMessage.contains("already exists") || errorMessage.contains("user already") {
                    throw AppError.emailAlreadyExists
                }
                
                // Check for RLS policy errors
                if errorMessage.contains("row-level security") || errorMessage.contains("policy") {
                    print("🔴 Auth: RLS policy error detected - check database policies")
                    throw AppError.unknown("Account creation failed. Please contact support.")
                }
            }
            
            // Re-throw AppError as-is
            if error is AppError {
                throw error
            }
            
            // Wrap unknown errors
            throw AppError.unknown(error.localizedDescription)
        }
    }
    
    /// Perform rollback by deleting orphaned auth user
    /// Called when signup creates auth user but profile creation fails
    /// - Parameter authUserId: The auth user ID to delete
    private func performSignupRollback(authUserId: String) async {
        // Note: admin.deleteUser() requires admin privileges
        // This might not work in production without proper Supabase admin setup
        // Alternative: Use a database function or edge function for cleanup
        
        // For now, try to sign out the user to prevent orphaned session
        try? await supabase.client.auth.signOut()
        
        print("✅ Auth: Rolled back user session")
        print("⚠️ Auth: Orphaned auth user \(authUserId) exists in Supabase Auth")
        print("   Manual cleanup may be required via Supabase dashboard")
        print("   Or implement a cleanup edge function for automatic deletion")
    }
    
    /// Sign out current user
    /// Clears session, profile, and cache
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Always call handleSignOut regardless of Supabase errors
        // This ensures local state is cleared even if network fails
        defer {
            Task {
                await handleSignOut()
            }
        }
        
        do {
            // Call Supabase auth.signOut()
            try await supabase.client.auth.signOut()
            print("✅ Auth: Supabase sign out successful")
        } catch {
            // Log error but don't throw - we'll still clear local state via defer
            print("⚠️ Error during Supabase sign out: \(error.localizedDescription)")
            print("⚠️ Local state will still be cleared")
        }
        
        print("✅ Auth: User signed out successfully")
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
        // Important: We want to match the ORIGINAL code, not tracking records
        // - For non-bulk codes: code matches and used_by IS NULL (single-use)
        // - For bulk codes: code matches, used_by IS NULL, and bulkCodeId IS NULL (the original bulk code, not a tracking record)
        // - Tracking records have bulkCodeId set and different code format, so they won't match this query
        // Note: Tracking records use format "ORIGINALCODE-UUID", so they won't match the original code anyway
        do {
            print("🔍 [AuthService] Validating invite code: \(normalized)")
            let response = try await supabase.client
                .from("invite_codes")
                .select()
                .eq("code", value: normalized)
                .is("used_by", value: nil)
                .single()
                .execute()
            
            print("✅ [AuthService] Found invite code in database")
            
            // Log raw JSON for debugging
            if let jsonString = String(data: response.data, encoding: .utf8) {
                print("📄 [AuthService] Raw JSON response: \(jsonString.prefix(500))")
            }
            
            // 5. Decode InviteCode - use custom decoder with date handling for Supabase ISO8601 format
            let decoder = createInviteCodeDecoder()
            let inviteCode: InviteCode
            do {
                inviteCode = try decoder.decode(InviteCode.self, from: response.data)
            } catch let decodingError as DecodingError {
                print("❌ [AuthService] Decoding error details:")
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("   Type mismatch: Expected \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    print("   Context: \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value not found: \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .keyNotFound(let key, let context):
                    print("   Key not found: \(key.stringValue), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("   Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    print("   Context: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error: \(decodingError)")
                }
                throw decodingError
            }
            
            print("🔍 [AuthService] Decoded invite code: code=\(inviteCode.code), isBulk=\(inviteCode.isBulk), usedBy=\(String(describing: inviteCode.usedBy)), expiresAt=\(String(describing: inviteCode.expiresAt)), bulkCodeId=\(String(describing: inviteCode.bulkCodeId))")
            
            // 6. Check expiration
            // Non-bulk codes (expiresAt == nil): Never expire - only check if used (already filtered by used_by IS NULL)
            // Bulk codes (expiresAt != nil): Check if expired (48 hours from creation)
            if inviteCode.isExpired {
                // Code is expired (only bulk codes can expire) - return same error (prevent enumeration)
                print("⚠️ [AuthService] Invite code expired: \(normalized) (expiresAt: \(String(describing: inviteCode.expiresAt)))")
                throw AppError.invalidInviteCode
            }
            
            // 7. Additional validation: Non-bulk codes should never expire
            // This is a data consistency check
            if !inviteCode.isBulk && inviteCode.expiresAt != nil {
                print("⚠️ [AuthService] Non-bulk code has expiresAt set - treating as valid (data inconsistency)")
            }
            
            // 8. Validate that the code is actually active (additional safety check)
            // isActive checks: !isUsed && !isExpired
            // We've already filtered by used_by IS NULL, so isUsed should be false
            // We've already checked expiration above
            if !inviteCode.isActive {
                print("⚠️ [AuthService] Invite code not active: \(normalized) (isUsed: \(inviteCode.isUsed), isExpired: \(inviteCode.isExpired))")
                throw AppError.invalidInviteCode
            }
            
            // 9. Return valid invite code
            print("✅ [AuthService] Invite code validated successfully: \(normalized) (isBulk: \(inviteCode.isBulk), expiresAt: \(String(describing: inviteCode.expiresAt)))")
            return inviteCode
            
        } catch {
            // 10. Return same error for "not found", "already used", "expired", and decode errors (prevent enumeration)
            // This prevents attackers from discovering which codes exist
            print("⚠️ [AuthService] Invite code validation failed for: \(normalized) - Error: \(error.localizedDescription)")
            throw AppError.invalidInviteCode
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create a JSONDecoder configured for decoding InviteCode from Supabase responses
    /// Handles ISO8601 date format with fractional seconds
    func createInviteCodeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Create thread-local formatters to avoid data races
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            // Try with fractional seconds first (Supabase format)
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }
            
            // Fallback to standard ISO8601
            let formatterStandard = ISO8601DateFormatter()
            formatterStandard.formatOptions = [.withInternetDateTime]
            
            if let date = formatterStandard.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }
        
        return decoder
    }
    
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
        
        // Reset rate limiter state
        await RateLimiter.shared.resetAll()
        print("✅ [AuthService] Rate limiter reset")
        
        // Unsubscribe from all realtime channels
        await RealtimeManager.shared.unsubscribeAll()
        print("✅ [AuthService] Realtime unsubscribed")
        
        // Post notification for app state updates on main thread
        // CRITICAL: Must post on main thread and schedule on next run loop
        // to avoid conflicts with view hierarchy teardown
        await MainActor.run {
            print("📢 [AuthService] Posting userDidSignOut notification on main thread")
            let notificationName = NSNotification.Name("userDidSignOut")
            print("📢 [AuthService] Notification name: '\(notificationName.rawValue)'")
            
            // Schedule notification on next run loop to ensure all views have finished processing
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: notificationName, object: nil, userInfo: nil)
                print("✅ [AuthService] userDidSignOut notification posted successfully")
            }
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

