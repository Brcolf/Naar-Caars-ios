//
//  AuthService+AppleSignIn.swift
//  NaarsCars
//
//  Extension for Apple Sign-In authentication methods
//

import Foundation
import Security
import Supabase
import PostgREST
import AuthenticationServices
import OSLog

// MARK: - Apple User Identifier Keychain Storage

/// Stores Apple user identifier in Keychain instead of UserDefaults for security.
private enum AppleUserKeychain {
    private static let service = "com.naarscars.apple"
    private static let account = "appleUserIdentifier"

    static func save(_ identifier: String) {
        guard let data = identifier.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension AuthService {
    
    /// Handle Apple Sign-In for new users (public signup — no invite code required)
    /// Captures Apple-provided name and email immediately on first authorization.
    /// - Parameters:
    ///   - credential: Apple ID credential from ASAuthorization
    ///   - rawNonce: The raw nonce used for the request
    /// - Throws: AppError if signup fails
    func signUpWithApple(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String? = nil
    ) async throws {
        isLoading = true
        defer { isLoading = false }

        // 1. Get identity token
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }

        // 2. Get user info from Apple credential (only available on first authorization)
        // Apple SIWA compliance: persist these immediately — Apple will not return them again
        let email = credential.email
        let fullName = [
            credential.fullName?.givenName,
            credential.fullName?.familyName
        ].compactMap { $0 }.joined(separator: " ")

        // 3. Sign in with Supabase using Apple token
        // Supabase will create the auth user if they don't exist
        let session = try await SupabaseService.shared.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identityToken,
                nonce: rawNonce
            )
        )

        let userIdString = session.user.id.uuidString
        guard let userId = UUID(uuidString: userIdString) else {
            throw AppError.unknown("Failed to create user account")
        }

        // 4. Create or update profile (no invite code required)
        try await createOrUpdateAppleProfile(
            userId: userId,
            userIdString: userIdString,
            email: email,
            name: fullName
        )

        // 5. Fetch profile and update local state
        if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
            currentProfile = profile
            currentUserId = userId
        } else {
            currentUserId = userId
        }

        // Sync engines started by AppLaunchManager.performDeferredLoading()

        // 6. Store Apple user identifier for credential checking
        AppleUserKeychain.save(credential.user)

        AppLogger.auth.info("User signed up with Apple: \(userId)")
    }
    
    /// Handle Apple Sign-In for existing users (login flow)
    /// - Parameter credential: Apple ID credential from ASAuthorization
    /// - Returns: `.success` if profile found, `.noAccountFound` if no profile exists
    /// - Throws: AppError for real failures (network, token, server errors)
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String? = nil) async throws -> AppleLoginResult {
        isLoading = true
        defer { isLoading = false }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }

        // signInWithIdToken creates a Supabase session (and possibly a new auth
        // user). If no profile exists, we must clean up BOTH the server-side
        // auth user AND the local session before returning .noAccountFound.
        let session = try await SupabaseService.shared.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identityToken,
                nonce: rawNonce
            )
        )

        let userIdString = session.user.id.uuidString
        guard let userId = UUID(uuidString: userIdString) else {
            throw AppError.invalidCredentials
        }

        // Fetch profile — may not exist if Apple created a new auth user
        // that isn't linked to the existing email/password account
        do {
            let profile = try await ProfileService.shared.fetchProfile(userId: userId)

            // Update local state
            currentUserId = userId
            currentProfile = profile
            // Sync engines started by AppLaunchManager.performDeferredLoading()

            // Store Apple user identifier for credential checking
            AppleUserKeychain.save(credential.user)

            AppLogger.auth.info("User logged in with Apple: \(userId), approved: \(profile.approved)")
            return .success
        } catch {
            // Distinguish "no profile exists" from transient failures.
            // Only PostgREST "no rows" errors are treated as .noAccountFound.
            // All other errors (network, decode, server 500) are re-thrown
            // so the existing error alert fires in the UI.
            guard isProfileNotFoundError(error) else {
                throw error
            }

            AppLogger.auth.warning("Apple login: no profile for user \(userId). Cleaning up.")

            // 1. Delete the orphaned server-side auth user (idempotent, never throws)
            await cleanupOrphanedAuthUser(userIdString: userIdString)

            // 2. Clear the local Supabase session that signInWithIdToken created.
            //    Use the raw Supabase client — NOT AuthService.signOut() — to avoid
            //    firing .userDidSignOut notifications or tearing down sync engines
            //    for a login that never completed.
            try? await SupabaseService.shared.client.auth.signOut()

            return .noAccountFound
        }
    }
    
    /// Link Apple ID to existing email/password account.
    /// Decodes the Apple JWT to extract the subject ID, then inserts directly
    /// into auth.identities via a database function. This avoids signInWithIdToken
    /// which creates a new user instead of linking.
    /// - Parameters:
    ///   - credential: Apple ID credential from ASAuthorization
    ///   - rawNonce: The raw nonce used when requesting the Apple credential (unused but kept for API consistency)
    /// - Throws: AppError if linking fails
    func linkAppleAccount(credential: ASAuthorizationAppleIDCredential, rawNonce: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }

        // Verify user is authenticated and get their ID
        let session = try await SupabaseService.shared.client.auth.session
        let userId = session.user.id

        // Decode the Apple JWT to extract sub (Apple user identifier) and email
        guard let claims = decodeAppleJWTPayload(identityToken) else {
            throw AppError.unknown("Failed to decode Apple identity token")
        }

        guard let appleSub = claims["sub"] as? String else {
            throw AppError.unknown("Apple identity token missing subject")
        }

        let appleEmail = claims["email"] as? String ?? credential.email ?? ""

        // Call database function to insert into auth.identities
        struct LinkResponse: Decodable {
            let success: Bool
            let error: String?
            let message: String?
        }

        let params: [String: String] = [
            "p_user_id": userId.uuidString,
            "p_apple_sub": appleSub,
            "p_apple_email": appleEmail
        ]

        let response: LinkResponse = try await SupabaseService.shared.client
            .rpc("link_apple_identity", params: params)
            .execute()
            .value

        if response.success {
            AppLogger.auth.info("Apple identity linked: \(response.message ?? "")")

            // Store Apple user identifier for credential state checking
            AppleUserKeychain.save(credential.user)

            // Refresh session so identities cache reflects the new link
            _ = try? await SupabaseService.shared.client.auth.refreshSession()
        } else {
            let errorMsg = response.error ?? "Unknown error"
            AppLogger.auth.error("Failed to link Apple identity: \(errorMsg)")
            throw AppError.processingError(errorMsg)
        }
    }

    /// Decode the payload of an Apple JWT (identity token) without signature verification.
    /// The token has already been verified by ASAuthorization.
    /// - Parameter jwt: The JWT string
    /// - Returns: Dictionary of claims, or nil if decoding fails
    private func decodeAppleJWTPayload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return nil }

        // The payload is the second segment, Base64URL-encoded
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }
    
    /// Unlink Apple ID from the current account.
    /// Revokes Apple authorization first (Apple compliance), then removes the
    /// identity row from Supabase. Refuses to proceed if Apple is the only
    /// sign-in method — the user must add a password first.
    /// - Throws: AppError if unlinking fails or if Apple is the only auth method
    func unlinkAppleAccount() async throws {
        isLoading = true
        defer { isLoading = false }

        let session = try await SupabaseService.shared.client.auth.session
        let userId = session.user.id

        // Guard: verify another auth method exists before allowing unlink
        let identities = session.user.identities ?? []
        let hasNonAppleIdentity = identities.contains { $0.provider != "apple" }
        guard hasNonAppleIdentity else {
            AppLogger.auth.warning("Unlink blocked: Apple is the only identity for user \(userId)")
            throw AppError.processingError("auth_apple_unlink_only_method".localized)
        }

        // Revoke Apple authorization with Apple's servers (shared helper)
        try await revokeAppleAuthorization()

        // Remove the Apple identity from auth.identities
        struct UnlinkResponse: Decodable {
            let success: Bool
            let error: String?
        }

        let response: UnlinkResponse = try await SupabaseService.shared.client
            .rpc("unlink_apple_identity", params: ["p_user_id": userId.uuidString])
            .execute()
            .value

        guard response.success else {
            let errorMsg = response.error ?? "Unknown error"
            AppLogger.auth.error("Server unlink failed: \(errorMsg)")
            throw AppError.processingError(String(format: "auth_apple_unlink_failed".localized, errorMsg))
        }

        // Refresh session so the cached identities array reflects the removal
        _ = try? await SupabaseService.shared.client.auth.refreshSession()

        AppLogger.auth.info("Apple account unlinked successfully")
    }

    // MARK: - Private Helper Methods

    /// Create or update profile for Apple user (public signup — no invite code required)
    /// Apple SIWA compliance: name and email from Apple are persisted immediately.
    /// On subsequent sign-ins where Apple doesn't return these values, stored values are used.
    /// - Parameters:
    ///   - userId: The user ID
    ///   - userIdString: The user ID as string
    ///   - email: User's email (may be nil for private relay)
    ///   - name: User's full name (may be empty on subsequent sign-ins)
    private func createOrUpdateAppleProfile(
        userId: UUID,
        userIdString: String,
        email: String?,
        name: String
    ) async throws {
        // Check if profile exists
        let existing = try? await SupabaseService.shared.client
            .from("profiles")
            .select()
            .eq("id", value: userIdString)
            .single()
            .execute()

        if existing != nil {
            // Profile exists - update name only if Apple provided one this time
            if !name.isEmpty {
                try await SupabaseService.shared.client
                    .from("profiles")
                    .update(["name": AnyCodable(name)])
                    .eq("id", value: userIdString)
                    .execute()
            }
        } else {
            // Create new profile — persist Apple-provided name/email immediately
            let profileName = name.isEmpty ? "Apple User" : name
            let profileEmail = email ?? "\(userIdString)@privaterelay.appleid.com"

            struct ProfileInsert: Codable {
                let id: String
                let name: String
                let email: String
                let isAdmin: Bool
                let approved: Bool
                let applicationComplete: Bool

                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case email
                    case isAdmin = "is_admin"
                    case approved
                    case applicationComplete = "application_complete"
                }
            }

            let profileInsert = ProfileInsert(
                id: userIdString,
                name: profileName,
                email: profileEmail,
                isAdmin: false,
                approved: false,
                applicationComplete: false
            )

            try await SupabaseService.shared.client
                .from("profiles")
                .insert(profileInsert)
                .execute()
        }
    }
    
    /// Check if an error indicates "no rows returned" from a `.single()` query.
    /// Uses typed `PostgrestError` check, matching the pattern in `ConversationService`
    /// and `BadgeCountManager`. Only `PostgrestError` passes — `URLError`, `DecodingError`,
    /// and other failure types return `false` and get re-thrown as real errors.
    private func isProfileNotFoundError(_ error: Error) -> Bool {
        guard let pgError = error as? PostgrestError else {
            return false
        }
        // Primary: PostgREST error code for ".single() returned 0 rows"
        if pgError.code == "PGRST116" {
            return true
        }
        // Fallback: message matching for SDK/PostgREST version variance.
        // The .single() modifier produces "JSON object requested, multiple (or no)
        // rows returned" — check the structured message field, not localizedDescription.
        let msg = pgError.message.lowercased()
        return msg.contains("json object requested") || msg.contains("0 rows")
    }

    // MARK: - Apple Token Revocation

    /// Shared Apple revocation helper used by both Delete Account and Unlink Apple flows.
    /// Obtains a fresh authorization code (presenting the Apple Sign-In sheet),
    /// then calls the `revoke-apple-token` Edge Function to revoke the token with Apple.
    /// Clears the local Keychain entry on success.
    ///
    /// This method does NOT modify Supabase identities or auth.users —
    /// callers are responsible for their own backend cleanup after revocation.
    ///
    /// Returns silently if no Apple credential is linked or if Apple has already
    /// revoked/transferred the credential.
    ///
    /// - Throws: AppError if the user cancels the Apple sheet or if the Edge Function fails.
    func revokeAppleAuthorization() async throws {
        // Check if user has Apple ID linked
        guard let appleUserIdentifier = AppleUserKeychain.read() else {
            // No Apple account linked, nothing to revoke
            return
        }

        // Check credential state with Apple
        let state = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Error>) in
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            appleIDProvider.getCredentialState(forUserID: appleUserIdentifier) { state, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }

        guard state == .authorized else {
            // Credential already revoked or transferred — clean up keychain
            AppleUserKeychain.delete()
            AppLogger.auth.info("Apple credential already revoked or not found, keychain cleared")
            return
        }

        // Obtain a fresh authorization code by presenting Apple Sign-In
        let code = try await obtainFreshAppleAuthCode()

        // Call Edge Function to revoke the token server-side
        do {
            try await SupabaseService.shared.client.functions.invoke(
                "revoke-apple-token",
                options: .init(body: ["authorization_code": code])
            )
            AppLogger.auth.info("Apple token revoked via Edge Function")
        } catch {
            AppLogger.auth.error("Apple revocation edge function failed: \(error.localizedDescription)")
            throw AppError.processingError(String(format: "auth_apple_revoke_failed".localized, error.localizedDescription))
        }

        // Clean up local Keychain
        AppleUserKeychain.delete()
    }

    /// Revoke Apple Sign-In authorization before account deletion.
    /// Calls the shared revocation helper. The caller (ProfileService.deleteAccount)
    /// handles the actual account deletion via the delete_user_account RPC,
    /// which deletes auth.users and all associated data.
    /// - Throws: AppError if revocation fails
    func revokeAppleSignIn() async throws {
        try await revokeAppleAuthorization()
        AppLogger.auth.info("Apple Sign-In revoked for account deletion")
    }

    /// Presents the Apple Sign-In sheet to obtain a fresh authorization code
    /// needed for token revocation. The user sees a brief Apple ID confirmation.
    /// - Returns: The authorization code string
    /// - Throws: AppError if the user cancels or the request fails
    private func obtainFreshAppleAuthCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = AppleRevocationDelegate(continuation: continuation)
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            // No scopes needed — we just need a fresh auth code for revocation

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            // Hold a strong reference so the delegate stays alive
            objc_setAssociatedObject(controller, "revocationDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }
}

// MARK: - Apple Revocation Delegate

/// Lightweight delegate that bridges ASAuthorizationController delegate callbacks
/// into a CheckedContinuation for the revocation flow.
private final class AppleRevocationDelegate: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<String, Error>?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cont = continuation else { return }
        continuation = nil

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8) else {
            cont.resume(throwing: AppError.processingError("auth_apple_auth_code_failed".localized))
            return
        }
        cont.resume(returning: code)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let cont = continuation else { return }
        continuation = nil

        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            cont.resume(throwing: AppError.processingError("auth_apple_deletion_requires_signin".localized))
        } else {
            cont.resume(throwing: AppError.processingError(String(format: "auth_apple_signin_failed".localized, error.localizedDescription)))
        }
    }
}

// MARK: - Apple Sign-In State

extension AuthService {
    /// Check if the current user has Apple Sign-In linked
    var hasAppleSignInLinked: Bool {
        AppleUserKeychain.read() != nil
    }

    /// Check if the current user has an Apple identity in Supabase auth
    func checkAppleIdentityLinked() async -> Bool {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            return AppleUserKeychain.read() != nil
        }
        return session.user.identities?.contains(where: { $0.provider == "apple" }) ?? false
    }
}

// MARK: - Profile Extension for Apple Email

extension Profile {
    /// Check if email is an Apple private relay email
    var isApplePrivateRelay: Bool {
        email.contains("privaterelay.appleid.com")
    }
    
    /// Display email string (shows "Private Email (via Apple)" for relay emails)
    var displayEmail: String {
        if isApplePrivateRelay {
            return "Private Email (via Apple)"
        }
        return email
    }
}

