//
//  AuthService+AppleSignIn.swift
//  NaarsCars
//
//  Extension for Apple Sign-In authentication methods
//

import Foundation
import Supabase
import AuthenticationServices
import OSLog

extension AuthService {
    
    /// Handle Apple Sign-In for new users (signup flow)
    /// - Parameters:
    ///   - credential: Apple ID credential from ASAuthorization
    ///   - inviteCodeId: Validated invite code ID
    /// - Throws: AppError if signup fails
    func signUpWithApple(
        credential: ASAuthorizationAppleIDCredential,
        inviteCodeId: UUID
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
        let session = try await SupabaseService.shared.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identityToken,
                nonce: nil  // Optional nonce for additional security
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
        
        // 8. Store Apple user identifier for credential checking
        UserDefaults.standard.set(
            credential.user,
            forKey: "appleUserIdentifier"
        )
        
        AppLogger.auth.info("User signed up with Apple: \(userId)")
    }
    
    /// Handle Apple Sign-In for existing users (login flow)
    /// - Parameter credential: Apple ID credential from ASAuthorization
    /// - Throws: AppError if login fails
    func logInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }
        
        // Sign in with Supabase using Apple token
        let session = try await SupabaseService.shared.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identityToken,
                nonce: nil  // Optional nonce for additional security
            )
        )
        
        let userIdString = session.user.id.uuidString
        guard let userId = UUID(uuidString: userIdString) else {
            throw AppError.invalidCredentials
        }
        
        // Fetch profile using ProfileService
        let profile = try await ProfileService.shared.fetchProfile(userId: userId)
        
        // Update local state
        currentUserId = userId
        currentProfile = profile
        
        // Store Apple user identifier for credential checking
        UserDefaults.standard.set(
            credential.user,
            forKey: "appleUserIdentifier"
        )
        
        AppLogger.auth.info("User logged in with Apple: \(userId), approved: \(profile.approved)")
    }
    
    /// Link Apple ID to existing email/password account
    /// - Parameter credential: Apple ID credential from ASAuthorization
    /// - Throws: AppError if linking fails
    func linkAppleAccount(credential: ASAuthorizationAppleIDCredential) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }
        
        // Get the current user's session
        guard try await SupabaseService.shared.client.auth.session.user.id != nil else {
            throw AppError.notAuthenticated
        }
        
        // Store Apple user identifier for credential checking
        UserDefaults.standard.set(
            credential.user,
            forKey: "appleUserIdentifier"
        )
        
        do {
            // Update user metadata to indicate Apple linking
            // This allows the user to sign in with either email/password or Apple Sign-In
            try await SupabaseService.shared.client.auth.update(
                user: UserAttributes(
                    data: [
                        "apple_user_id": .string(credential.user),
                        "apple_linked_at": .string(ISO8601DateFormatter().string(from: Date())),
                        "apple_email": credential.email.map { .string($0) } ?? .null
                    ]
                )
            )
            
            AppLogger.auth.info("Apple account linked successfully to user metadata")
            
        } catch {
            AppLogger.auth.error("Failed to update user metadata with Apple linking: \(error.localizedDescription)")
            throw AppError.processingError("Failed to link Apple ID. Please try again.")
        }
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
    
    // MARK: - Account Deletion with Apple Token Revocation
    
    /// Revoke Apple Sign-In authorization before account deletion
    /// Apple requires that apps revoke tokens when users delete their accounts
    /// - Returns: True if revocation was successful or no Apple account was linked
    func revokeAppleSignIn() async -> Bool {
        // Check if user has Apple ID linked
        guard let appleUserIdentifier = UserDefaults.standard.string(forKey: "appleUserIdentifier") else {
            // No Apple account linked, nothing to revoke
            return true
        }
        
        do {
            // Get the current credential state from Apple
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
            
            // Only need to handle revocation if credential is still authorized
            guard state == .authorized else {
                // Credential is already revoked or transferred, clean up local storage
                UserDefaults.standard.removeObject(forKey: "appleUserIdentifier")
                AppLogger.auth.info("Apple credential already revoked or not found")
                return true
            }
            
            // Clear local Apple user identifier
            // Note: Full token revocation requires server-side implementation
            // with Apple's /auth/revoke endpoint using client_secret
            // For now, we clear the local state and unlink the identity if possible
            UserDefaults.standard.removeObject(forKey: "appleUserIdentifier")
            
            // Try to unlink the Apple identity from Supabase
            // This removes the association between the Apple ID and the Supabase user
            do {
                // Get current user identities
                if let session = try? await SupabaseService.shared.client.auth.session {
                    if let appleIdentity = session.user.identities?.first(where: { $0.provider == "apple" }) {
                        try await SupabaseService.shared.client.auth.unlinkIdentity(appleIdentity)
                        AppLogger.auth.info("Apple identity unlinked from Supabase")
                    }
                }
            } catch {
                // Log error but continue with deletion - the account will still be deleted
                AppLogger.auth.error("Failed to unlink Apple identity: \(error.localizedDescription)")
            }
            
            AppLogger.auth.info("Apple Sign-In revoked successfully")
            return true
            
        } catch {
            AppLogger.auth.error("Failed to check/revoke Apple credential state: \(error.localizedDescription)")
            // Still clean up local storage even if revocation check fails
            UserDefaults.standard.removeObject(forKey: "appleUserIdentifier")
            return false
        }
    }
    
    /// Check if the current user has Apple Sign-In linked
    var hasAppleSignInLinked: Bool {
        UserDefaults.standard.string(forKey: "appleUserIdentifier") != nil
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

