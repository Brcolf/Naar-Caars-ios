//
//  AuthService.swift
//  NaarsCars
//
//  Authentication service for managing user sessions and authentication state
//

import Foundation
import Supabase
import OSLog
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
                    await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)
                    return .pendingApproval
                } else {
                    await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)
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
            AppLogger.auth.error("Error checking auth status: \(error.localizedDescription)")
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
        
        // Log action for crash context
        CrashReportingService.shared.logAction("sign_in_attempt")
        
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
            
            await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)
            
            // Set crash reporting user ID and context
            CrashReportingService.shared.setUserId(userId.uuidString)
            if let profile = profile {
                CrashReportingService.shared.updateAppStateContext(
                    isAuthenticated: true,
                    isApproved: profile.approved,
                    isAdmin: profile.isAdmin
                )
                AppLogger.auth.info("Sign in successful for user: \(email), approved: \(profile.approved)")
            } else {
                AppLogger.auth.warning("Sign in successful but profile not found for user: \(email)")
            }

            restartRealtimeSyncEngines()
            
            CrashReportingService.shared.logAction("sign_in_success")
        } catch {
            // Record non-fatal error for sign-in failures
            CrashReportingService.shared.recordError(
                domain: CrashDomain.auth,
                code: CrashErrorCode.authInvalidCredentials,
                message: "Sign in failed",
                userInfo: ["error_type": String(describing: type(of: error))]
            )
            
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
            // Poll for profile with exponential backoff instead of a fixed delay
            let profile = try await pollForNewProfile(maxAttempts: 5, initialDelayMs: 100)
            
            // Update currentUserId and currentProfile
            currentUserId = userId
            currentProfile = profile
            
            // Mark invite code as used (or create tracking record for bulk codes)
            // Use InviteService to handle bulk vs non-bulk codes correctly:
            // - Non-bulk codes: Mark as used (single-use)
            // - Bulk codes: Create tracking record (bulk code remains active for other users)
            try await InviteService.shared.markInviteCodeAsUsed(inviteCode: validatedInviteCode, userId: userId)
            
            AppLogger.auth.info("Sign up successful for user: \(email)")
            restartRealtimeSyncEngines()
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
            
            guard let userId = UUID(uuidString: userIdString) else {
                throw AppError.unknown("Invalid user ID format")
            }
            
            // 3. Create or update profile using RPC function
            // This handles both new signups AND re-signups after rejection
            // Uses SECURITY DEFINER to bypass RLS permission issues
            // Note: Using [String: String?] dictionary to avoid MainActor isolation issues with Sendable
            let params: [String: String?] = [
                "p_user_id": userIdString,
                "p_email": email,
                "p_name": name,
                "p_invited_by": inviteCode.createdBy.uuidString,
                "p_car": car?.isEmpty == false ? car : nil
            ]
            
            struct SignupProfileResponse: Decodable {
                let success: Bool
                let error: String?
                let userId: UUID?
                let message: String?
                
                enum CodingKeys: String, CodingKey {
                    case success
                    case error
                    case userId = "user_id"
                    case message
                }
            }
            
            let response: SignupProfileResponse = try await supabase.client
                .rpc("create_signup_profile", params: params)
                .execute()
                .value
            
            if response.success {
                AppLogger.auth.info("Created/updated profile for user: \(userId)")
            } else {
                let errorMsg = response.error ?? "Unknown error"
                AppLogger.auth.error("Failed to create profile: \(errorMsg)")
                throw AppError.unknown("Profile creation failed: \(errorMsg)")
            }
            
            // 4. Mark invite code as used (or create tracking record for bulk codes)
            // Uses RPC function with SECURITY DEFINER to bypass RLS
            // (auth.uid() may not be set immediately after signup)
            var inviteParams: [String: String?] = [
                "p_invite_code_id": inviteCode.id.uuidString,
                "p_user_id": userIdString,
                "p_is_bulk": inviteCode.isBulk ? "true" : "false"
            ]
            if let bulkCodeId = inviteCode.bulkCodeId {
                inviteParams["p_bulk_code_id"] = bulkCodeId.uuidString
            }
            
            struct MarkInviteResponse: Decodable {
                let success: Bool
                let error: String?
                let message: String?
            }
            
            let inviteResponse: MarkInviteResponse = try await supabase.client
                .rpc("mark_invite_code_used", params: inviteParams)
                .execute()
                .value
            
            if !inviteResponse.success {
                let errorMsg = inviteResponse.error ?? "Unknown error"
                AppLogger.auth.warning("Failed to mark invite code as used: \(errorMsg)")
                // Don't throw - profile was created successfully, this is non-critical
            } else {
                AppLogger.auth.info("Invite code marked as used: \(inviteResponse.message ?? "")")
            }
            
            // 5. Fetch the created profile and update local state
            if let profile = try? await fetchCurrentProfile() {
                currentProfile = profile
                currentUserId = userId
            } else {
                // Profile should exist, but set userId for state
                currentUserId = userId
            }
            
            await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)
            
            AppLogger.auth.info("User signed up successfully: \(email)")
            
        } catch {
            // Log detailed error for debugging
            AppLogger.auth.error("Signup failed for \(email): \(error.localizedDescription)")
            if let nsError = error as NSError? {
                AppLogger.auth.debug("Error domain: \(nsError.domain), code: \(nsError.code)")
                AppLogger.auth.debug("Error userInfo: \(nsError.userInfo)")
            }
            
            // Handle specific Supabase errors
            if let supabaseError = error as NSError? {
                let errorMessage = supabaseError.localizedDescription.lowercased()
                
                if errorMessage.contains("already registered") || errorMessage.contains("already exists") || errorMessage.contains("user already") {
                    throw AppError.emailAlreadyExists
                }
                
                // Check for RLS policy errors
                if errorMessage.contains("row-level security") || errorMessage.contains("policy") {
                    AppLogger.auth.error("RLS policy error detected - check database policies")
                    throw AppError.unknown("Account creation failed - please contact support")
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
            
            AppLogger.auth.info("User signed out successfully")
        } catch {
            // Even if sign out fails, clear local state and post notification
            AppLogger.auth.warning("Error during sign out: \(error.localizedDescription)")
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
            AppLogger.auth.info("Password reset email sent (or would be sent if email exists)")
        } catch {
            // Catch and ignore errors - never reveal if email exists
            // This prevents email enumeration attacks
            AppLogger.auth.debug("Password reset requested for: \(email) (error hidden for security)")
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
            minimumInterval: Constants.RateLimits.authAction
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
            AppLogger.auth.debug("Validating invite code: \(normalized)")
            let response = try await supabase.client
                .from("invite_codes")
                .select()
                .eq("code", value: normalized)
                .is("used_by", value: nil)
                .single()
                .execute()
            
            AppLogger.auth.debug("Found invite code in database")
            
            // Log raw JSON for debugging (only in DEBUG mode)
            #if DEBUG
            if let jsonString = String(data: response.data, encoding: .utf8) {
                AppLogger.auth.debug("Raw JSON response: \(jsonString.prefix(500))")
            }
            #endif
            
            // 5. Decode InviteCode - use custom decoder with date handling for Supabase ISO8601 format
            let decoder = createInviteCodeDecoder()
            let inviteCode: InviteCode
            do {
                inviteCode = try decoder.decode(InviteCode.self, from: response.data)
            } catch let decodingError as DecodingError {
                #if DEBUG
                AppLogger.auth.error("Decoding error details:")
                switch decodingError {
                case .typeMismatch(let type, let context):
                    AppLogger.auth.error("Type mismatch: Expected \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    AppLogger.auth.error("Value not found: \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .keyNotFound(let key, let context):
                    AppLogger.auth.error("Key not found: \(key.stringValue), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    AppLogger.auth.error("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    AppLogger.auth.error("Unknown decoding error: \(decodingError)")
                }
                #endif
                throw decodingError
            }
            
            AppLogger.auth.debug("Decoded invite code: code=\(inviteCode.code), isBulk=\(inviteCode.isBulk)")
            
            // 6. Check expiration
            // Non-bulk codes (expiresAt == nil): Never expire - only check if used (already filtered by used_by IS NULL)
            // Bulk codes (expiresAt != nil): Check if expired (48 hours from creation)
            if inviteCode.isExpired {
                // Code is expired (only bulk codes can expire) - return same error (prevent enumeration)
                AppLogger.auth.debug("Invite code expired: \(normalized)")
                throw AppError.invalidInviteCode
            }
            
            // 7. Additional validation: Non-bulk codes should never expire
            // This is a data consistency check
            if !inviteCode.isBulk && inviteCode.expiresAt != nil {
                AppLogger.auth.warning("Non-bulk code has expiresAt set - treating as valid (data inconsistency)")
            }
            
            // 8. Validate that the code is actually active (additional safety check)
            // isActive checks: !isUsed && !isExpired
            // We've already filtered by used_by IS NULL, so isUsed should be false
            // We've already checked expiration above
            if !inviteCode.isActive {
                AppLogger.auth.debug("Invite code not active: \(normalized)")
                throw AppError.invalidInviteCode
            }
            
            // 9. Return valid invite code
            AppLogger.auth.info("Invite code validated successfully: \(normalized)")
            return inviteCode
            
        } catch {
            // 10. Return same error for "not found", "already used", "expired", and decode errors (prevent enumeration)
            // This prevents attackers from discovering which codes exist
            AppLogger.auth.debug("Invite code validation failed for: \(normalized)")
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
            
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            let formatterStandard = ISO8601DateFormatter()
            formatterStandard.formatOptions = [.withInternetDateTime]
            
            // Try with fractional seconds first (Supabase format)
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }
            
            // Fallback to standard ISO8601
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
        AppLogger.auth.debug("handleSignOut() started")
        let userIdToRemove = currentUserId
        
        // Log action for crash context
        CrashReportingService.shared.logAction("sign_out")
        
        // Clear crash reporting user ID
        CrashReportingService.shared.setUserId(nil)
        CrashReportingService.shared.updateAppStateContext(
            isAuthenticated: false,
            isApproved: false,
            isAdmin: false
        )
        
        // Clear local state on main actor
        await MainActor.run {
            currentUserId = nil
            currentProfile = nil
        }
        AppLogger.auth.debug("Local state cleared")

        // Post notification early so UI can redirect immediately
        await MainActor.run {
            AppLogger.auth.debug("Posting userDidSignOut notification (early)")
            let notificationName = NSNotification.Name("userDidSignOut")
            NotificationCenter.default.post(name: notificationName, object: nil, userInfo: nil)
        }

        if let userId = userIdToRemove {
            try? await PushNotificationService.shared.removeDeviceToken(userId: userId)
        }
        PushNotificationService.shared.clearRegisteredTokenState()
        
        // Clear caches
        await CacheManager.shared.clearAll()
        AppLogger.cache.debug("Cache cleared on sign out")
        
        // Unsubscribe from all realtime channels (best-effort)
        await RealtimeManager.shared.unsubscribeAll()
        AppLogger.realtime.debug("Realtime unsubscribed on sign out")

        // Ensure sync engines release subscriptions and reset lifecycle state.
        await SyncEngineOrchestrator.shared.teardownAll()
        
        AppLogger.auth.info("Sign out cleanup completed")
    }

    func restartRealtimeSyncEngines() {
        SyncEngineOrchestrator.shared.startAll()
    }
    
    /// Poll for profile creation after signup with exponential backoff
    /// The database trigger (handle_new_user) creates the profile asynchronously,
    /// so we poll instead of using a fixed delay.
    /// - Parameters:
    ///   - maxAttempts: Maximum number of poll attempts
    ///   - initialDelayMs: Initial delay between attempts in milliseconds (doubles each attempt)
    /// - Returns: Profile if found within the timeout
    /// - Throws: AppError if profile is not created within the polling window
    private func pollForNewProfile(maxAttempts: Int, initialDelayMs: UInt64) async throws -> Profile? {
        var delayMs = initialDelayMs
        for attempt in 1...maxAttempts {
            if let profile = try await fetchCurrentProfile() {
                if attempt > 1 {
                    AppLogger.auth.info("Profile found on poll attempt \(attempt)")
                }
                return profile
            }
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                delayMs = min(delayMs * 2, 1600) // cap at 1.6s per interval
            }
        }
        AppLogger.auth.warning("Profile not found after \(maxAttempts) poll attempts")
        return nil
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
            AppLogger.auth.debug("Error fetching profile: \(error.localizedDescription)")
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

extension AuthService: AuthServiceProtocol {}
