//
//  PendingMembersViewModelTests.swift
//  NaarsCarsTests
//
//  Requests to join: the inline not-admin state, one decision at a time, and the
//  platform-admin-only contact read
//

import XCTest
@testable import NaarsCars

@MainActor
final class PendingMembersViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let applicantA = CommunityMember(
        id: UUID(uuidString: "DDDDDDDD-0000-4000-8000-000000000004")!, name: "Dana Rivera", avatarUrl: nil, car: nil,
        role: .member, status: .pending, joinedAt: Date(timeIntervalSince1970: 1_790_100_000), activatedAt: nil,
        heardAbout: "A neighbor", joinReason: "Airport rides", invitedByName: nil, removalReason: nil
    )
    private let applicantB = CommunityMember(
        id: UUID(uuidString: "EEEEEEEE-0000-4000-8000-000000000005")!, name: "Lee Park", avatarUrl: nil, car: nil,
        role: .member, status: .pending, joinedAt: Date(timeIntervalSince1970: 1_790_200_000), activatedAt: nil,
        heardAbout: nil, joinReason: nil, invitedByName: nil, removalReason: nil
    )

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "PendingMembersViewModelTests.\(UUID().uuidString)"
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
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: role, pendingCount: 2)
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { platformAdmin })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        return (context, stub)
    }

    private func makeViewModel(
        context: CommunityContext,
        admin: StubCommunityAdminService,
        fetcher: StubApplicantContactFetcher = StubApplicantContactFetcher(),
        badgeRefreshes: (() -> Void)? = nil
    ) -> PendingMembersViewModel {
        PendingMembersViewModel(
            target: .community(CommunityFixtures.communityA, name: "Community A"),
            adminService: admin,
            communityContext: context,
            contactFetcher: fetcher,
            refreshBadges: { badgeRefreshes?() }
        )
    }

    func testLoad_NotAdminShowsInlineStateWithoutFetching() async {
        let (context, _) = await makeContext(role: .member)
        let admin = StubCommunityAdminService()
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()

        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertTrue(admin.fetchCommunityMembersCalls.isEmpty)
        XCTAssertNil(vm.loadError)
    }

    func testApprove_IgnoresSecondTapWhileActing() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([applicantA, applicantB])
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()
        XCTAssertEqual(vm.access, .allowed)
        XCTAssertEqual(admin.fetchCommunityMembersCalls.first?.status, .pending)

        var resume: CheckedContinuation<Void, Never>?
        admin.actionGate = { await withCheckedContinuation { resume = $0 } }
        let first = Task { await vm.approve(applicantA) }
        for _ in 0..<200 where admin.approveMemberCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(admin.approveMemberCalls.count, 1)

        await vm.approve(applicantB)
        await vm.reject(applicantB)
        resume?.resume()
        _ = await first.value

        XCTAssertEqual(admin.approveMemberCalls.count, 1)
        XCTAssertTrue(admin.rejectMemberCalls.isEmpty)
        XCTAssertEqual(admin.approveMemberCalls[0].userId, applicantA.id)
        XCTAssertEqual(vm.applicants.map(\.id), [applicantB.id])
    }

    func testApprove_RemovesRowEvenWhenRefreshFails() async {
        let (context, stub) = await makeContext(role: .admin)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([applicantA, applicantB])
        var badgeRefreshCount = 0
        let vm = makeViewModel(context: context, admin: admin, badgeRefreshes: { badgeRefreshCount += 1 })
        await vm.load()

        stub.result = .failure(URLError(.notConnectedToInternet))
        let fetchesBefore = stub.fetchCount
        await vm.approve(applicantA)

        XCTAssertFalse(vm.applicants.contains { $0.id == applicantA.id })
        XCTAssertNil(vm.actionErrorMessage)
        XCTAssertEqual(vm.access, .allowed)
        XCTAssertEqual(stub.fetchCount, fetchesBefore + 1)
        XCTAssertEqual(badgeRefreshCount, 1)
        XCTAssertNil(vm.actingOnUserId)
    }

    func testReject_RefusalWithoutCodeShowsNotAdminState() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunityMembersResult = .success([applicantA])
        admin.rejectMemberResult = .failure(CommunityRPCError(code: nil, serverMessage: "Not authorized"))
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        await vm.reject(applicantA)

        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertNil(vm.actionErrorMessage)
        XCTAssertEqual(admin.rejectMemberCalls.count, 1)
    }

    func testLoadContact_OnlyPlatformAdminsReadContact() async {
        let admin = StubCommunityAdminService()

        let (memberContext, _) = await makeContext(role: .owner, platformAdmin: false)
        let ownerFetcher = StubApplicantContactFetcher()
        let ownerVM = makeViewModel(context: memberContext, admin: admin, fetcher: ownerFetcher)
        await ownerVM.loadContact(for: applicantA)
        XCTAssertTrue(ownerFetcher.calls.isEmpty)
        XCTAssertNil(ownerVM.contacts[applicantA.id])

        let (platformContext, _) = await makeContext(role: .member, platformAdmin: true)
        let platformFetcher = StubApplicantContactFetcher()
        platformFetcher.result = .success(ApplicantContact(email: "dana@example.com", phoneNumber: "+12065550142"))
        let platformVM = makeViewModel(context: platformContext, admin: admin, fetcher: platformFetcher)
        await platformVM.loadContact(for: applicantA)
        await platformVM.loadContact(for: applicantA)

        XCTAssertEqual(platformFetcher.calls, [applicantA.id])
        XCTAssertEqual(platformVM.contacts[applicantA.id], ApplicantContact(email: "dana@example.com", phoneNumber: "+12065550142"))
    }
}
