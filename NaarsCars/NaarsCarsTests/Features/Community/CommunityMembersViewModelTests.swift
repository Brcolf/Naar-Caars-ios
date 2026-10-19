//
//  CommunityMembersViewModelTests.swift
//  NaarsCarsTests
//
//  Members and member detail: the action table that mirrors the server, the inline not-admin
//  state, one action at a time, and a removal that sticks when the follow-up reload fails
//

import AuthenticationServices
import XCTest
@testable import NaarsCars

/// Answers only `currentUserId`; every other method is unused here.
private final class StubMembersAuthService: AuthServiceProtocol {
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
final class CommunityMembersViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let caller = CommunityFixtures.userA

    private func member(
        _ id: String,
        name: String,
        role: CommunityRole = .member,
        status: MembershipStatus = .active
    ) -> CommunityMember {
        CommunityMember(
            id: UUID(uuidString: id)!, name: name, avatarUrl: nil, car: nil,
            role: role, status: status, joinedAt: Date(timeIntervalSince1970: 1_790_100_000),
            activatedAt: Date(timeIntervalSince1970: 1_790_100_100),
            heardAbout: nil, joinReason: nil, invitedByName: nil, removalReason: nil
        )
    }

    private lazy var plainMember = member("DDDDDDDD-0000-4000-8000-000000000004", name: "Dana Rivera")
    private lazy var otherMember = member("EEEEEEEE-0000-4000-8000-000000000005", name: "Lee Park")
    private lazy var adminMember = member("FFFFFFFF-0000-4000-8000-000000000006", name: "Pat Quinn", role: .admin)
    private lazy var ownerMember = member("12121212-0000-4000-8000-000000000007", name: "Sam Neighbor", role: .owner)
    private lazy var removedMember = member("13131313-0000-4000-8000-000000000008", name: "Jordan Lee", status: .removed)

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CommunityMembersViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    /// A context restored for `userA` and loaded with one membership of community A in `role`.
    private func makeContext(
        role: CommunityRole,
        platformAdmin: Bool = false
    ) async -> (CommunityContext, StubCommunityService) {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: role)
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { platformAdmin })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        return (context, stub)
    }

    private func makeViewModel(
        context: CommunityContext,
        admin: StubCommunityAdminService,
        dashboardTriggers: ((String) -> Void)? = nil
    ) -> CommunityMembersViewModel {
        CommunityMembersViewModel(
            communityId: CommunityFixtures.communityA,
            communityName: "Community A",
            adminService: admin,
            communityContext: context,
            authService: StubMembersAuthService(currentUserId: CommunityFixtures.userA),
            refreshDashboard: { dashboardTriggers?($0) }
        )
    }

    private func actions(_ target: CommunityMember, role: CommunityRole?, platformAdmin: Bool = false) -> [CommunityMemberAction] {
        CommunityMemberActions.available(for: target, callerId: caller, callerRole: role, isPlatformAdmin: platformAdmin)
    }

    // MARK: - Action table

    func testActions_PlainMemberCallerGetsNothing() {
        for target in [plainMember, adminMember, ownerMember, removedMember] {
            XCTAssertEqual(actions(target, role: .member), [], "target \(target.name)")
        }
    }

    func testActions_AdminCanRemoveMembersButNotAdminsOrOwners() {
        XCTAssertEqual(actions(plainMember, role: .admin), [.remove])
        XCTAssertEqual(actions(adminMember, role: .admin), [])
        XCTAssertEqual(actions(ownerMember, role: .admin), [])
    }

    func testActions_OwnerGetsRoleAndTransferActions() {
        XCTAssertEqual(actions(plainMember, role: .owner), [.transferOwnership, .makeAdmin, .remove])
        XCTAssertEqual(actions(adminMember, role: .owner), [.transferOwnership, .makeMember, .remove])
        XCTAssertEqual(actions(ownerMember, role: .owner), [.makeAdmin, .remove])
    }

    func testActions_PlatformAdminWhoIsNotOwnerCannotTransfer() {
        XCTAssertEqual(actions(plainMember, role: nil, platformAdmin: true), [.makeAdmin, .remove])
        XCTAssertEqual(actions(adminMember, role: .admin, platformAdmin: true), [.makeMember, .remove])
    }

    func testActions_NeverOnSelf() {
        let me = member(caller.uuidString, name: "Me", role: .member)
        XCTAssertEqual(actions(me, role: .owner), [])
        XCTAssertEqual(actions(me, role: nil, platformAdmin: true), [])
        let removedMe = member(caller.uuidString, name: "Me", status: .removed)
        XCTAssertEqual(actions(removedMe, role: .admin), [])
    }

    func testActions_RemovedMemberOffersReadmitToAdminsOnly() {
        XCTAssertEqual(actions(removedMember, role: .owner), [.readmit])
        XCTAssertEqual(actions(removedMember, role: .admin), [.readmit])
        XCTAssertEqual(actions(removedMember, role: nil, platformAdmin: true), [.readmit])
        XCTAssertEqual(actions(removedMember, role: .member), [])
        XCTAssertEqual(actions(removedMember, role: nil), [])
        let pending = member("14141414-0000-4000-8000-000000000009", name: "Pending", status: .pending)
        XCTAssertEqual(actions(pending, role: .owner), [])
    }

    // MARK: - Load

    func testLoad_NotAdminShowsInlineStateWithoutFetching() async {
        let (context, _) = await makeContext(role: .member)
        let admin = StubCommunityAdminService()
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()

        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertTrue(admin.fetchCommunityMembersCalls.isEmpty)
        XCTAssertNil(vm.loadError)
    }

    /// The context still says member (the change was made elsewhere and no refresh ran); the failed
    /// role check refreshes once and the screen opens as the owner the server now reports.
    func testLoad_StaleMemberRoleRefreshesOnceBeforeShowingNotAdmin() async {
        let (context, stub) = await makeContext(role: .member)
        XCTAssertEqual(stub.fetchCount, 1)
        stub.result = .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: .owner)
        ])
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([plainMember])
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()

        XCTAssertEqual(vm.access, .allowed)
        XCTAssertEqual(stub.fetchCount, 2)
        XCTAssertEqual(admin.fetchCommunityMembersCalls.count, 1)
        XCTAssertEqual(vm.actions(for: plainMember), [.transferOwnership, .makeAdmin, .remove])
    }

    /// A real member: one refresh for the failed check, none on a later load.
    func testLoad_RealMemberRefreshesOnlyOnce() async {
        let (context, stub) = await makeContext(role: .member)
        let admin = StubCommunityAdminService()
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()
        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertEqual(stub.fetchCount, 2)

        await vm.load()
        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertEqual(stub.fetchCount, 2)
        XCTAssertTrue(admin.fetchCommunityMembersCalls.isEmpty)
    }

    /// Opened from a `membership_update` push: the context says admin (the check would pass), but
    /// the first load refreshes anyway and picks up the ownership, so owner actions are offered.
    func testLoad_RefreshesRoleFirstPicksUpANewOwnerOverAStaleAdmin() async {
        let (context, stub) = await makeContext(role: .admin)
        stub.result = .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: .owner)
        ])
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([adminMember])
        let vm = CommunityMembersViewModel(
            communityId: CommunityFixtures.communityA,
            communityName: "Community A",
            adminService: admin,
            communityContext: context,
            authService: StubMembersAuthService(currentUserId: CommunityFixtures.userA),
            refreshDashboard: { _ in },
            refreshesRoleFirst: true
        )

        await vm.load()

        XCTAssertEqual(vm.access, .allowed)
        XCTAssertEqual(stub.fetchCount, 2)
        let offered = vm.actions(for: adminMember)
        XCTAssertTrue(offered.contains(.transferOwnership))
        XCTAssertTrue(offered.contains(.makeMember))

        await vm.load()
        XCTAssertEqual(stub.fetchCount, 2)
    }

    // MARK: - Perform

    func testPerform_IgnoresSecondCallWhileActing() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([plainMember, otherMember])
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()
        XCTAssertEqual(vm.access, .allowed)
        XCTAssertEqual(admin.fetchCommunityMembersCalls.first?.status, .active)

        var resume: CheckedContinuation<Void, Never>?
        admin.actionGate = { await withCheckedContinuation { resume = $0 } }
        let first = Task { await vm.perform(.remove, on: plainMember) }
        for _ in 0..<200 where admin.removeMemberCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(admin.removeMemberCalls.count, 1)

        let second = await vm.perform(.remove, on: otherMember)
        XCTAssertFalse(second)
        resume?.resume()
        let firstResult = await first.value

        XCTAssertTrue(firstResult)
        XCTAssertEqual(admin.removeMemberCalls.count, 1)
        XCTAssertEqual(admin.removeMemberCalls[0].userId, plainMember.id)
    }

    func testPerform_HoldsGateThroughFollowUpRefresh() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([plainMember, otherMember])
        var resume: CheckedContinuation<Void, Never>?
        var dashboardEntered = false
        let vm = CommunityMembersViewModel(
            communityId: CommunityFixtures.communityA,
            communityName: "Community A",
            adminService: admin,
            communityContext: context,
            authService: StubMembersAuthService(currentUserId: CommunityFixtures.userA),
            refreshDashboard: { _ in
                dashboardEntered = true
                await withCheckedContinuation { resume = $0 }
            }
        )
        await vm.load()

        let first = Task { await vm.perform(.remove, on: plainMember) }
        for _ in 0..<200 where !dashboardEntered { await Task.yield() }
        XCTAssertTrue(dashboardEntered)
        XCTAssertEqual(admin.removeMemberCalls.count, 1)

        // The RPC has returned and the row is gone, but the follow-up refresh is still running:
        // the detail screen still holds the original row, so a second tap must do nothing.
        XCTAssertEqual(vm.actingOnUserId, plainMember.id)
        let second = await vm.perform(.remove, on: plainMember)
        XCTAssertFalse(second)
        XCTAssertEqual(admin.removeMemberCalls.count, 1)

        resume?.resume()
        let firstResult = await first.value
        XCTAssertTrue(firstResult)
        XCTAssertNil(vm.actingOnUserId)
        XCTAssertNil(vm.actionErrorMessage)
    }

    func testRemove_DropsRowRefreshesDashboardAndStaysGoneWhenReloadFails() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([plainMember, otherMember])
        var triggers: [String] = []
        let vm = makeViewModel(context: context, admin: admin, dashboardTriggers: { triggers.append($0) })
        await vm.load()

        admin.fetchCommunityMembersResult = .failure(URLError(.notConnectedToInternet))
        let fetchesBefore = admin.fetchCommunityMembersCalls.count
        let ok = await vm.perform(.remove, on: plainMember)

        XCTAssertTrue(ok)
        XCTAssertFalse(vm.members.contains { $0.id == plainMember.id })
        XCTAssertEqual(vm.members.map(\.id), [otherMember.id])
        XCTAssertEqual(triggers, ["removedMember"])
        XCTAssertEqual(admin.fetchCommunityMembersCalls.count, fetchesBefore + 1)
        XCTAssertNil(vm.actionErrorMessage)
        XCTAssertNil(vm.loadError)
        XCTAssertNotNil(vm.toastMessage)
        XCTAssertNil(vm.actingOnUserId)
    }

    func testRemove_SendsTrimmedReasonOrNil() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([plainMember, otherMember])
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        await vm.perform(.remove, on: plainMember, reason: "  Spam  ")
        await vm.perform(.remove, on: otherMember, reason: "   ")

        XCTAssertEqual(admin.removeMemberCalls.count, 2)
        XCTAssertEqual(admin.removeMemberCalls[0].reason, "Spam")
        XCTAssertNil(admin.removeMemberCalls[1].reason)
    }

    func testRefusalWithoutCode_ShowsNotAllowedAndReloads() async {
        let (context, stub) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([plainMember])
        admin.setMemberRoleResult = .failure(CommunityRPCError(code: nil, serverMessage: "Only the owner can change roles"))
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()
        XCTAssertEqual(vm.access, .allowed)

        // Demoted by another owner while the screen was open.
        stub.result = .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: .member)
        ])
        let fetchesBefore = stub.fetchCount
        let ok = await vm.perform(.makeAdmin, on: plainMember)

        XCTAssertFalse(ok)
        XCTAssertEqual(admin.setMemberRoleCalls.count, 1)
        XCTAssertEqual(vm.actionErrorMessage, "community_member_action_not_allowed".localized)
        XCTAssertEqual(stub.fetchCount, fetchesBefore + 1)
        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertEqual(vm.actions(for: plainMember), [])
    }

    func testLastOwnerRefusal_ShowsLocalizedMessage() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([ownerMember])
        admin.removeMemberResult = .failure(CommunityRPCError(code: .lastOwner, serverMessage: "Make someone else owner"))
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        let ok = await vm.perform(.remove, on: ownerMember)

        XCTAssertFalse(ok)
        XCTAssertEqual(vm.actionErrorMessage, "community_error_last_owner".localized)
        XCTAssertEqual(vm.members.map(\.id), [ownerMember.id])
    }

    // MARK: - Search

    func testFilteredMembers_MatchesNameIgnoringCaseAndDiacritics() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        let jose = member("15151515-0000-4000-8000-00000000000A", name: "José Ruiz")
        admin.fetchCommunityMembersResult = .success([jose, plainMember])
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        vm.query = "jose"
        XCTAssertEqual(vm.filteredMembers.map(\.id), [jose.id])
        vm.query = "  "
        XCTAssertEqual(vm.filteredMembers.count, 2)
    }
}
