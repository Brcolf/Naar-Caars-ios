//
//  AuthService.swift
//  NaarsCars
//
//  Authentication service for managing user sessions and authentication state
//

import Foundation
import Supabase
import OSLog
import UserNotifications
internal import Combine

/// Service for managing user authentication and session state
/// Handles sign in, sign up, sign out, password reset, and session lifecycle
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
                
                await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)

                // Check account lifecycle: ban → approval → authenticated
                if profile.isBanned {
                    return .banned
                } else if profile.approved {
                    return .authenticated
                } else if !profile.applicationComplete {
                    return .needsApplication
                } else {
                    return .pendingApproval
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

            // Sync engines are started by AppLaunchManager.performDeferredLoading()
            // after performCriticalLaunch() completes. Starting them here too
            // caused duplicate realtime channel subscriptions.

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
    
    /// Sign up with email and password (public signup — no invite code required)
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - name: User's full name
    ///   - car: User's car (optional)
    /// - Throws: AppError if sign up fails
    func signUp(email: String, password: String, name: String, car: String?) async throws {
        isLoading = true
        defer { isLoading = false }

        // Track whether auth user was created so we can clean up on failure
        var createdAuthUserId: String?

        // Nothing identifying in these sign-up lines (5b gate G5: the address was logged).
        AppLogger.auth.info("Sign-up started")
        do {
            // 1. Create auth user with Supabase
            let authResponse = try await supabase.client.auth.signUp(
                email: email,
                password: password
            )

            let user = authResponse.user
            let userIdString = user.id.uuidString
            createdAuthUserId = userIdString

            guard let userId = UUID(uuidString: userIdString) else {
                throw AppError.unknown("Invalid user ID format")
            }

            // 2. Create profile using RPC function
            // Uses SECURITY DEFINER to bypass RLS permission issues
            let params: [String: String?] = [
                "p_user_id": userIdString,
                "p_email": email,
                "p_name": name,
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
                AppLogger.auth.info("Created profile for user: \(userId)")
            } else {
                let errorMsg = response.error ?? "Unknown error"
                AppLogger.auth.error("Failed to create profile: \(errorMsg)")
                throw AppError.unknown("Profile creation failed: \(errorMsg)")
            }

            // 3. Fetch the created profile and update local state
            if let profile = try? await fetchCurrentProfile() {
                currentProfile = profile
                currentUserId = userId
            } else {
                currentUserId = userId
            }

            await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)

            // Signup fully succeeded — clear the tracking variable so cleanup doesn't fire
            createdAuthUserId = nil

            AppLogger.auth.info("Sign-up succeeded")

        } catch {
            AppLogger.auth.error("Sign-up failed: \(error.localizedDescription)")

            // Clean up orphaned auth user if one was created before the failure
            if let orphanedId = createdAuthUserId {
                await cleanupOrphanedAuthUser(userIdString: orphanedId)
            }

            let errorMessage = error.localizedDescription.lowercased()

            if errorMessage.contains("already registered") || errorMessage.contains("already exists") || errorMessage.contains("user already") {
                throw AppError.emailAlreadyExists
            }

            if errorMessage.contains("row-level security") || errorMessage.contains("policy") {
                AppLogger.auth.error("RLS policy error detected - check database policies")
                throw AppError.unknown("Account creation failed - please contact support")
            }

            if error is AppError {
                throw error
            }

            throw AppError.unknown(error.localizedDescription)
        }
    }

    /// Clean up an orphaned auth user that was created during a failed signup
    /// Best-effort — failures are logged but don't propagate
    func cleanupOrphanedAuthUser(userIdString: String) async {
        AppLogger.auth.info("Cleaning up orphaned auth user: \(userIdString)")

        struct CleanupResponse: Decodable {
            let success: Bool
            let error: String?
            let message: String?
        }

        do {
            let response: CleanupResponse = try await supabase.client
                .rpc("cleanup_orphaned_auth_user", params: ["p_user_id": userIdString])
                .execute()
                .value

            if response.success {
                AppLogger.auth.info("Orphaned auth user cleaned up: \(response.message ?? "")")
            } else {
                AppLogger.auth.warning("Cleanup returned failure: \(response.error ?? "unknown")")
            }
        } catch {
            // Best-effort — don't let cleanup failure mask the original error
            AppLogger.auth.warning("Failed to cleanup orphaned auth user: \(error.localizedDescription)")
        }
    }
    
    /// Sign out current user
    /// Clears session, profile, and cache
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Remove this device's push token while the session is still valid. The push_tokens
        // DELETE policy needs auth.uid(); doing this after auth.signOut() matched zero rows and
        // a signed-out device kept receiving the previous user's pushes (2026-10-05).
        if let userId = currentUserId {
            try? await PushNotificationService.shared.removeDeviceToken(userId: userId)
        }
        
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
    
    // MARK: - Helper Methods
    
    /// Handle sign out with complete cleanup.
    /// Critical data wipe and teardown happen BEFORE the UI transition notification
    /// to prevent cross-user data leakage when a new user signs in quickly.
    /// The `isSigningOut` flag acts as a safety barrier: SyncEngineOrchestrator and
    /// RealtimeManager check it to reject late work during teardown.
    private(set) var isSigningOut = false

    private func handleSignOut() async {
        // Reentrancy guard — prevent multiple concurrent teardowns
        guard !isSigningOut else {
            AppLogger.auth.debug("handleSignOut() skipped — already in progress")
            return
        }
        isSigningOut = true

        AppLogger.auth.info("handleSignOut() started — barrier active")

        // Log action for crash context
        CrashReportingService.shared.logAction("sign_out")

        // Clear crash reporting user ID
        CrashReportingService.shared.setUserId(nil)
        CrashReportingService.shared.updateAppStateContext(
            isAuthenticated: false,
            isApproved: false,
            isAdmin: false
        )

        // --- Phase 1: Clear auth state ---

        // Captured before it is cleared so per-account keys can be removed by user id below.
        // It may already be nil when the session ended first.
        let signingOutUserId = currentUserId
        currentUserId = nil
        currentProfile = nil
        AppLogger.auth.debug("User ID cleared")

        // --- Phase 2: Fast wipe (MUST complete before UI transition) ---
        // Cancel in-flight refresh tasks (no network)
        await RefreshCoordinator.shared.reset()

        // Clear realtime session state — prevents stale channel restoration
        await MessagingSyncEngine.shared.clearSessionState()
        RealtimeManager.shared.clearAllState()

        // Wipe SwiftData cache (prevents cross-user data leakage)
        do {
            try await SyncEngineOrchestrator.shared.wipeSwiftDataCache()
            AppLogger.auth.info("SwiftData cache cleared on sign-out")
        } catch {
            AppLogger.error("auth", "SwiftData wipe failed: \(error)")
        }

        // Reset in-memory publisher caches so new session starts clean
        await MessagingRepository.shared.resetPublishers()

        // Per-account state kept outside SwiftData. It used to outlive sign-out, so a guest or
        // the next account on this device saw the previous member's recent addresses, pinned
        // threads, delivered notifications and badge counts. Local only; cannot hang.
        await clearPerAccountLocalState(userId: signingOutUserId)

        // --- Phase 3: Post notification for immediate UI transition ---
        // This MUST fire before the potentially-hanging teardown below.
        // The barrier (isSigningOut) remains true to block startAll() and late subscriptions.
        AppLogger.auth.debug("Posting userDidSignOut notification")
        NotificationCenter.default.post(name: .userDidSignOut, object: nil, userInfo: nil)

        // Reset the reentrancy guard BEFORE the teardown awaits.
        // teardownAll() and unsubscribeAll() can hang indefinitely (observed in production).
        // If the guard stays true, every subsequent sign-out is permanently skipped.
        // The barrier served its purpose: SwiftData is wiped, publishers are reset,
        // and the UI has transitioned. Teardown calls below are idempotent.
        isSigningOut = false
        AppLogger.auth.info("Sign-out barrier released — beginning async teardown")

        // --- Phase 4: Async teardown (best-effort, can hang) ---

        // Stop sync engines (cancels subscriptions, stops workers)
        await SyncEngineOrchestrator.shared.teardownAll()

        // Unsubscribe from all realtime channels
        await RealtimeManager.shared.unsubscribeAll()
        AppLogger.realtime.debug("Realtime unsubscribed on sign out")

        // Clear caches
        await CacheManager.shared.clearAll()
        AppLogger.cache.debug("Cache cleared on sign out")

        // The push token row is deleted in signOut() before the session ends (the DELETE policy
        // needs auth.uid()); only the local registration state is cleared here.
        PushNotificationService.shared.clearRegisteredTokenState()

        AppLogger.auth.info("Sign out cleanup completed")
    }
    
    /// Local-only part of the sign-out wipe: no network, safe before the UI transition.
    /// - Parameter userId: the account signing out, or nil when the session had already ended.
    private func clearPerAccountLocalState(userId: UUID?) async {
        // Keys owned by ConversationsListView (pinned threads), RecentReactionsStore,
        // CalendarOfferTracker and PushNotificationService (last push payload).
        let defaults = UserDefaults.standard
        for key in ["pinnedConversations", "com.naarscars.recentReactions", "calendarOfferState", "apns_last_push_payload"] {
            defaults.removeObject(forKey: key)
        }

        // Attachments of sends that were still pending; their queue rows went with SwiftData.
        LocalAttachmentStorage.deleteAll()

        // Banners and local reminders that belong to the account that just left.
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()

        await MainActor.run {
            LocationService.shared.forgetRecentLocations()
            BadgeCountManager.shared.resetForSignOut()
            // Memberships in memory and the community.* keys of this account (and of the
            // account CommunityContext restored, when that differs).
            CommunityContext.shared.resetForSignOut(userId: userId)
            // A confirmation waiting for the next launch root never crosses accounts.
            RootNotice.pending = nil
        }
        // An invite code kept on this device for a sign-up (spec §5 Sign-out row).
        PendingInviteStore().clear()
        // The community a guest looked at before signing up, offered on Get started.
        ViewedCommunityStore().clear()
        // Signed storage URLs were issued under this account's access; the next account signs its own.
        await StorageURLSigner.shared.reset()
        // Both caches below are account-scoped: the photos this account could read (with the
        // image buckets private, the files on disk are the only copy outside the server), and
        // REST responses with its content. A guest or the next account on this device was served
        // from them (5b gate G4). Local file removal only; cannot hang.
        PersistentImageService.shared.clearCache()   // disk and memory
        URLCache.shared.removeAllCachedResponses()
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
enum AuthState: Equatable {
    case loading
    case unauthenticated
    case guest
    case needsApplication
    case pendingApproval
    case banned
    case authenticated
}

extension AuthService: AuthServiceProtocol {}
