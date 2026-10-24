//
//  MyProfileViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for MyProfileViewModel
//

import AuthenticationServices
import XCTest
@testable import NaarsCars

/// Answers only `currentUserId` (the `StubMembersAuthService` pattern); every other method is unused here.
private final class StubProfileAuthService: AuthServiceProtocol {
    var currentUserId: UUID?
    var currentProfile: Profile? { nil }

    init(currentUserId: UUID?) { self.currentUserId = currentUserId }

    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String, name: String, car: String?) async throws {}
    func signOut() async throws {}
    func sendPasswordReset(email: String) async throws {}
    func signUpWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws {}
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult { .success }
}

@MainActor
final class MyProfileViewModelTests: XCTestCase {
    var viewModel: MyProfileViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = MyProfileViewModel()
    }
    
    func testLoadProfile_Success_SetsAllProperties() async throws {
        // loadProfile fetches through the live ProfileService (`profiles` / `public_profiles`
        // with `.single()`), so it can only succeed for a user that exists on the backend.
        // A random UUID always makes fetchProfile throw and leaves `profile` nil.
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing: loadProfile needs a live Supabase session and an existing profile row")
        }

        await viewModel.loadProfile(userId: userId)

        XCTAssertNil(viewModel.error, "loadProfile should not surface an error for the signed-in user")
        XCTAssertNotNil(viewModel.profile)
        XCTAssertEqual(viewModel.profile?.id, userId)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - A3 warning after an archive

    /// Phase 3 gate follow-up, by design: an archived community no longer closes on deletion, so the
    /// A3 warning does not name it. The archive path forgets the membership, and get_my_memberships
    /// leaves archived communities out (20261017_0005).
    func testCommunitiesClosedByDeletion_AnArchivedCommunityIsNotListed() async {
        let suiteName = "MyProfileViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let a = CommunityFixtures.communityA
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(a, name: "Community A", role: .owner)
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        // No other member: the account is the sole owner.
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([])
        let vm = MyProfileViewModel(
            authService: StubProfileAuthService(currentUserId: CommunityFixtures.userA),
            communityContext: context,
            communityAdminService: admin
        )

        let beforeArchive = await vm.communitiesClosedByDeletion()
        XCTAssertEqual(beforeArchive, ["Community A"], "control: a live, solely owned community is named")

        // The archive path (CommunitySettingsViewModel.archive).
        stub.result = .success([])
        await context.forgetMembership(a)

        let afterArchive = await vm.communitiesClosedByDeletion()
        XCTAssertEqual(afterArchive, [])
    }
}
