//
//  AuthServiceProtocol.swift
//  NaarsCars
//

import Foundation
import AuthenticationServices

@MainActor
protocol AuthServiceProtocol: AnyObject {
    var currentUserId: UUID? { get }
    var currentProfile: Profile? { get }

    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, name: String, car: String?, inviteCodeId: UUID) async throws
    func signOut() async throws
    func sendPasswordReset(email: String) async throws
    func validateInviteCode(_ code: String) async throws -> InviteCode
    func signUpWithApple(credential: ASAuthorizationAppleIDCredential, inviteCodeId: UUID) async throws
    func logInWithApple(credential: ASAuthorizationAppleIDCredential) async throws
}
