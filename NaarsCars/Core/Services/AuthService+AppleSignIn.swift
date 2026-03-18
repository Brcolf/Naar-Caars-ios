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
    
    /// Handle Apple Sign-In for new users (signup flow)
    /// - Parameters:
    ///   - credential: Apple ID credential from ASAuthorization
    ///   - inviteCodeId: Validated invite code ID
    /// - Throws: AppError if signup fails
    func signUpWithApple(
        credential: ASAuthorizationAppleIDCredential,
        inviteCodeId: UUID,
        rawNonce: String? = nil
    ) async throws {
        isLoading = true
        defer { isLoading = false }

        // 1. Get identity token
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }

        // 2. Get user info (may be nil on subsequent logins)
        let email = credential.email
        let fullName = [
            credential.fullName?.givenName,
            credential.fullName?.familyName
        ].compactMap { $0 }.joined(separator: " ")

        // 3. Sign in with Supabase using Apple token
        // Note: Supabase will create the user if they don't exist
        // Use signInWithIdToken for native iOS Apple Sign-In
        // The rawNonce must match the SHA256 hash embedded in the id_token
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
        
        // 4. Fetch invite code to get createdBy for profile
        let inviteCodeResponse = try await SupabaseService.shared.client
            .from("invite_codes")
            .select()
            .eq("id", value: inviteCodeId.uuidString)
            .single()
            .execute()
        
        // Decode with proper date handling for Supabase ISO8601 format
        let decoder = createInviteCodeDecoder()
        let inviteCode = try decoder.decode(InviteCode.self, from: inviteCodeResponse.data)
        
        // 5. Create or update profile
        try await createOrUpdateAppleProfile(
            userId: userId,
            userIdString: userIdString,
            email: email,
            name: fullName,
            invitedBy: inviteCode.createdBy
        )
        
        // 6. Mark invite code as used (or create tracking record for bulk codes)
        // Use InviteService to handle bulk vs non-bulk codes correctly
        try await InviteService.shared.markInviteCodeAsUsed(inviteCode: inviteCode, userId: userId)
        
        // 7. Fetch profile and update local state
        // Use ProfileService to fetch profile since fetchCurrentProfile is private
        if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
            currentProfile = profile
            currentUserId = userId
        } else {
            currentUserId = userId
        }
        
        // Sync engines started by AppLaunchManager.performDeferredLoading()

        // 8. Store Apple user identifier for credential checking
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
    
    /// Unlink Apple ID from the current account
    /// Removes the Apple identity from auth.identities and clears local state
    /// - Throws: AppError if unlinking fails
    func unlinkAppleAccount() async throws {
        isLoading = true
        defer { isLoading = false }

        let session = try await SupabaseService.shared.client.auth.session
        let userId = session.user.id

        // Remove the Apple identity directly from auth.identities
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
            throw AppError.processingError("Failed to unlink Apple ID: \(errorMsg)")
        }

        // Refresh session so the cached identities array reflects the removal
        _ = try? await SupabaseService.shared.client.auth.refreshSession()

        // Clear local Apple user identifier
        AppleUserKeychain.delete()

        AppLogger.auth.info("Apple account unlinked successfully")
    }

    // MARK: - Private Helper Methods

    /// Create or update profile for Apple user
    /// - Parameters:
    ///   - userId: The user ID
    ///   - userIdString: The user ID as string
    ///   - email: User's email (may be nil for private relay)
    ///   - name: User's full name (may be empty)
    ///   - invitedBy: ID of user who created the invite code
    private func createOrUpdateAppleProfile(
        userId: UUID,
        userIdString: String,
        email: String?,
        name: String,
        invitedBy: UUID
    ) async throws {
        // Check if profile exists
        let existing = try? await SupabaseService.shared.client
            .from("profiles")
            .select()
            .eq("id", value: userIdString)
            .single()
            .execute()
        
        if existing != nil {
            // Profile exists - update if name was provided
            if !name.isEmpty {
                try await SupabaseService.shared.client
                    .from("profiles")
                    .update(["name": AnyCodable(name)])
                    .eq("id", value: userIdString)
                    .execute()
            }
        } else {
            // Create new profile
            let profileName = name.isEmpty ? "Apple User" : name
            // Use private relay email if email is nil (user chose "Hide My Email")
            let profileEmail = email ?? "\(userIdString)@privaterelay.appleid.com"
            
            struct ProfileInsert: Codable {
                let id: String
                let name: String
                let email: String
                let invitedBy: String
                let isAdmin: Bool
                let approved: Bool
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case email
                    case invitedBy = "invited_by"
                    case isAdmin = "is_admin"
                    case approved
                }
            }
            
            let profileInsert = ProfileInsert(
                id: userIdString,
                name: profileName,
                email: profileEmail,
                invitedBy: invitedBy.uuidString,
                isAdmin: false,
                approved: false
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

    // MARK: - Account Deletion with Apple Token Revocation

    /// Revoke Apple Sign-In authorization before account deletion.
    /// Apple requires that apps revoke tokens when users delete their accounts.
    /// This method obtains a fresh authorization code from the user (presenting
    /// the Apple Sign-In sheet), then calls the `revoke-apple-token` Edge Function
    /// to perform server-side token revocation with Apple's /auth/revoke endpoint.
    /// - Throws: AppError if revocation fails
    func revokeAppleSignIn() async throws {
        // Check if user has Apple ID linked
        guard let appleUserIdentifier = AppleUserKeychain.read() else {
            // No Apple account linked, nothing to revoke
            return
        }

        // Check credential state
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
            // Credential already revoked or transferred
            AppleUserKeychain.delete()
            AppLogger.auth.info("Apple credential already revoked or not found")
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
            AppLogger.auth.error("Edge function call failed: \(error.localizedDescription)")
            throw AppError.processingError("Failed to revoke Apple Sign-In token: \(error.localizedDescription)")
        }

        // Clean up local state
        AppleUserKeychain.delete()

        // Unlink identity from Supabase
        if let session = try? await SupabaseService.shared.client.auth.session,
           let appleIdentity = session.user.identities?.first(where: { $0.provider == "apple" }) {
            try? await SupabaseService.shared.client.auth.unlinkIdentity(appleIdentity)
            AppLogger.auth.info("Apple identity unlinked from Supabase")
        }

        AppLogger.auth.info("Apple Sign-In revoked successfully")
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
            cont.resume(throwing: AppError.processingError("Failed to obtain authorization code from Apple"))
            return
        }
        cont.resume(returning: code)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let cont = continuation else { return }
        continuation = nil

        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            cont.resume(throwing: AppError.processingError("Account deletion requires Apple Sign-In confirmation. Please try again."))
        } else {
            cont.resume(throwing: AppError.processingError("Apple Sign-In failed: \(error.localizedDescription)"))
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

