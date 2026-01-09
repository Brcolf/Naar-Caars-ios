//
//  AuthService+AppleSignIn.swift
//  NaarsCars
//
//  Extension for Apple Sign-In authentication methods
//

import Foundation
import Supabase
import AuthenticationServices

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
        
        guard let userIdString = session.user.id.uuidString,
              let userId = UUID(uuidString: userIdString) else {
            throw AppError.unknown("Failed to create user account")
        }
        
        // 4. Fetch invite code to get createdBy for profile
        let inviteCodeResponse = try await SupabaseService.shared.client
            .from("invite_codes")
            .select()
            .eq("id", value: inviteCodeId.uuidString)
            .single()
            .execute()
        
        let inviteCode = try JSONDecoder().decode(InviteCode.self, from: inviteCodeResponse.data)
        
        // 5. Create or update profile
        try await createOrUpdateAppleProfile(
            userId: userId,
            userIdString: userIdString,
            email: email,
            name: fullName,
            invitedBy: inviteCode.createdBy
        )
        
        // 6. Mark invite code as used
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        try await SupabaseService.shared.client
            .from("invite_codes")
            .update([
                "used_by": AnyCodable(userIdString),
                "used_at": AnyCodable(dateFormatter.string(from: Date()))
            ])
            .eq("id", value: inviteCodeId.uuidString)
            .execute()
        
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
        
        print("✅ Auth: User signed up with Apple: \(userId)")
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
        
        guard let userIdString = session.user.id.uuidString,
              let userId = UUID(uuidString: userIdString) else {
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
        
        if let profile = profile {
            print("✅ Auth: User logged in with Apple: \(userId), approved: \(profile.approved)")
        } else {
            print("⚠️ Auth: Logged in with Apple but profile not found: \(userId)")
        }
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
        
        // Link identity to existing user
        try await SupabaseService.shared.client.auth.linkIdentity(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identityToken,
                nonce: nil  // Optional nonce for additional security
            )
        )
        
        // Store Apple user identifier for credential checking
        UserDefaults.standard.set(
            credential.user,
            forKey: "appleUserIdentifier"
        )
        
        print("✅ Auth: Apple account linked successfully")
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

