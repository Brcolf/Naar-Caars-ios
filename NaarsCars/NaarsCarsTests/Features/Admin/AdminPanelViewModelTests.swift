//
//  AdminPanelViewModelTests.swift
//  NaarsCarsTests
//
//  The admin panel per community: which scope opens, which communities the title menu offers,
//  who is denied, figures that belong to the shown community, the announcement's community, and
//  the Admin → Communities entry point
//

import XCTest
@testable import NaarsCars

@MainActor
final class AdminPanelViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let communityD = UUID(uuidString: "DDDDDDDD-0000-4000-8000-0000000000D4")!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AdminPanelViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeContext(
        _ rows: [CommunityMembership],
        platformAdmin: Bool = false
    ) async -> CommunityContext {
        let stub = StubCommunityService(result: .success(rows))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { platformAdmin })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        return context
    }

    private func makeViewModel(
        scope: AdminPanelScope,
        communityName: String? = nil,
        context: CommunityContext,
        admin: StubAdminService = StubAdminService(),
        communityAdmin: StubCommunityAdminService = StubCommunityAdminService(),
        merge: StubCommunityService = StubCommunityService(result: .success([])),
        verify: @escaping @MainActor () async throws -> Void = {}
    ) -> AdminPanelViewModel {
        AdminPanelViewModel(
            initialScope: scope,
            communityName: communityName,
            adminService: admin,
            communityAdminService: communityAdmin,
            mergeService: merge,
            communityContext: context,
            verifyPlatformAdmin: verify
        )
    }

    private func stats(_ fulfilled: Int) -> AdminDashboardStats {
        AdminDashboardStats(fulfilledCount: fulfilled, totalSavings: Double(fulfilled) * 10, activeRidesCount: fulfilled + 1)
    }

    private func platformCommunity(pendingCount: Int = 0, isDefault: Bool = false, archived: Bool = false) -> PlatformCommunity {
        PlatformCommunity(
            id: UUID(), name: "Ballard Neighbors", description: nil, createdBy: nil, creatorName: "Sam Neighbor",
            createdAt: Date(timeIntervalSince1970: 1_790_000_000), isPublic: isDefault, isDefault: isDefault,
            joinPolicy: "approve", archivedAt: archived ? Date(timeIntervalSince1970: 1_790_100_000) : nil,
            archivedBy: nil, memberCount: 4, pendingCount: pendingCount, ownerCount: 1, openReportCount: 0
        )
    }

    // MARK: - Initial scope

    func testInitialScope_PlatformAdminAllCommunityAdminFirstOtherwiseNil() {
        let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB
        let administered = [
            CommunityFixtures.membership(a, name: "A", role: .admin),
            CommunityFixtures.membership(b, name: "B", role: .owner)
        ]
        XCTAssertEqual(AdminPanelScope.initial(isPlatformAdmin: true, administered: administered), .all)
        XCTAssertEqual(AdminPanelScope.initial(isPlatformAdmin: true, administered: []), .all)
        XCTAssertEqual(AdminPanelScope.initial(isPlatformAdmin: false, administered: administered), .community(a))
        XCTAssertNil(AdminPanelScope.initial(isPlatformAdmin: false, administered: []))
        XCTAssertNil(AdminPanelScope.all.communityId)
        XCTAssertEqual(AdminPanelScope.community(b).communityId, b)
    }

    // MARK: - Rename

    /// Phase 3 gate follow-up: the panel opened from My communities kept the old name after a
    /// rename in Settings. The view calls `refreshCommunityName()` when it reappears.
    func testRefreshCommunityName_PicksUpARename() async {
        let b = CommunityFixtures.communityB
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(b, name: "Ballard Neighbors", role: .owner)
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        let vm = makeViewModel(scope: .community(b), communityName: "Ballard Neighbors", context: context)
        await vm.verifyAdminAccess()
        XCTAssertEqual(vm.title, "Ballard Neighbors")
        XCTAssertEqual(vm.broadcastTarget?.communityName, "Ballard Neighbors")

        // Settings saved a new name and refreshed the memberships.
        stub.result = .success([CommunityFixtures.membership(b, name: "Ballard Riders", role: .owner)])
        await context.refreshMemberships()
        XCTAssertEqual(vm.title, "Ballard Neighbors", "the stored name wins until the panel reappears")

        vm.refreshCommunityName()

        XCTAssertEqual(vm.title, "Ballard Riders")
        XCTAssertEqual(vm.communityName, "Ballard Riders")
        XCTAssertEqual(vm.broadcastTarget, BroadcastTarget(communityId: b, communityName: "Ballard Riders"))
        XCTAssertTrue(vm.menuEntries.contains(AdminPanelMenuEntry(scope: .community(b), title: "Ballard Riders")))

        // `.all` has no community name to refresh.
        let all = makeViewModel(scope: .all, context: context)
        all.refreshCommunityName()
        XCTAssertNil(all.communityName)
        XCTAssertEqual(all.title, "admin_panel_title".localized)
    }

    // MARK: - Title menu

    func testMenuEntries_PlatformAdminGetsAllPlusMemberships() async {
        let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB, c = CommunityFixtures.communityC
        let context = await makeContext([
            CommunityFixtures.membership(a, name: "Naar's Cars Seattle", isDefault: true),
            CommunityFixtures.membership(b, name: "Ballard Neighbors", role: .owner),
            CommunityFixtures.membership(c, name: "Fremont Families", status: .pending)
        ], platformAdmin: true)
        let vm = makeViewModel(scope: .all, context: context)

        XCTAssertEqual(vm.menuEntries.map(\.scope), [.all, .community(a), .community(b)])
        XCTAssertEqual(vm.menuEntries.map(\.title), [
            "admin_panel_all_communities".localized, "Naar's Cars Seattle", "Ballard Neighbors"
        ])
        XCTAssertEqual(vm.title, "admin_panel_title".localized)

        // A community the platform admin does not belong to (opened from Admin → Communities) is in the menu.
        let other = makeViewModel(scope: .community(communityD), communityName: "Wallingford", context: context)
        XCTAssertEqual(other.menuEntries.map(\.scope), [.all, .community(a), .community(b), .community(communityD)])
        XCTAssertEqual(other.title, "Wallingford")
    }

    func testMenuEntries_CommunityAdminGetsOnlyAdministered() async {
        let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB, c = CommunityFixtures.communityC
        let context = await makeContext([
            CommunityFixtures.membership(a, name: "Naar's Cars Seattle", isDefault: true),
            CommunityFixtures.membership(b, name: "Ballard Neighbors", role: .admin),
            CommunityFixtures.membership(c, name: "Fremont Families", role: .owner),
            CommunityFixtures.membership(communityD, name: "Wallingford", status: .pending, role: .owner)
        ])
        let vm = makeViewModel(scope: .community(b), context: context)

        XCTAssertEqual(vm.menuEntries.map(\.scope), [.community(b), .community(c)])
        XCTAssertFalse(vm.menuEntries.contains { $0.scope == .all })
        XCTAssertEqual(vm.title, "Ballard Neighbors")
    }

    // MARK: - Access

    func testAllScope_NonPlatformAdminIsDenied() async {
        let context = await makeContext([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "A", role: .owner)
        ])
        let admin = StubAdminService()
        let vm = makeViewModel(scope: .all, context: context, admin: admin, verify: { throw AppError.unauthorized })

        await vm.verifyAdminAccess()

        XCTAssertFalse(vm.isAdmin)
        XCTAssertFalse(vm.isVerifyingAdmin)
        XCTAssertNil(vm.verificationErrorMessage)
        XCTAssertTrue(admin.fetchDashboardStatsCalls.isEmpty)
        XCTAssertNil(vm.broadcastTarget)
    }

    func testCommunityScope_NotAdminIsDeniedWithoutFetchingStats() async {
        let a = CommunityFixtures.communityA
        let context = await makeContext([CommunityFixtures.membership(a, name: "A", role: .member)])
        let admin = StubAdminService()
        var platformChecks = 0
        let vm = makeViewModel(scope: .community(a), context: context, admin: admin, verify: { platformChecks += 1 })

        await vm.verifyAdminAccess()

        XCTAssertFalse(vm.isAdmin)
        XCTAssertFalse(vm.isVerifyingAdmin)
        XCTAssertNil(vm.verificationErrorMessage)
        XCTAssertTrue(admin.fetchDashboardStatsCalls.isEmpty)
        XCTAssertEqual(platformChecks, 0)
    }

    func testCommunityScope_LoadsStatsForThatCommunity() async {
        let a = CommunityFixtures.communityA
        let context = await makeContext([CommunityFixtures.membership(a, name: "Ballard Neighbors", role: .admin, pendingCount: 3)])
        let admin = StubAdminService()
        admin.fetchDashboardStatsResult = .success(stats(9))
        let vm = makeViewModel(scope: .community(a), context: context, admin: admin)

        await vm.verifyAdminAccess()

        XCTAssertTrue(vm.isAdmin)
        XCTAssertEqual(admin.fetchDashboardStatsCalls, [a])
        XCTAssertEqual(vm.fulfilledCount, 9)
        XCTAssertEqual(vm.activeRidesCount, 10)
        XCTAssertTrue(vm.hasLoadedStats)
        XCTAssertEqual(vm.pendingCount, 3)
        XCTAssertEqual(vm.broadcastTarget, BroadcastTarget(communityId: a, communityName: "Ballard Neighbors"))
    }

    // MARK: - Switching (Review Focus 4)

    func testSelectScope_DropsStaleStats() async {
        let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB
        let context = await makeContext([
            CommunityFixtures.membership(a, name: "Ballard Neighbors", role: .owner),
            CommunityFixtures.membership(b, name: "Fremont Families", role: .admin)
        ])
        let admin = StubAdminService()
        var resume: CheckedContinuation<Void, Never>?
        var gatedCalls = 0
        admin.actionGate = {
            gatedCalls += 1
            if gatedCalls == 1 { await withCheckedContinuation { resume = $0 } }
        }
        let vm = makeViewModel(scope: .community(a), context: context, admin: admin)

        let first = Task { await vm.verifyAdminAccess() }
        for _ in 0..<200 where admin.fetchDashboardStatsCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(admin.fetchDashboardStatsCalls, [a])

        admin.fetchDashboardStatsResult = .success(stats(3))
        await vm.select(.community(b))
        XCTAssertEqual(vm.scope, .community(b))
        XCTAssertEqual(vm.fulfilledCount, 3)

        // A's answer arrives late; it must not replace B's figures.
        admin.fetchDashboardStatsResult = .success(stats(7))
        resume?.resume()
        await first.value

        XCTAssertEqual(admin.fetchDashboardStatsCalls, [a, b])
        XCTAssertEqual(vm.scope, .community(b))
        XCTAssertEqual(vm.title, "Fremont Families")
        XCTAssertEqual(vm.fulfilledCount, 3)
        XCTAssertTrue(vm.hasLoadedStats)
        XCTAssertEqual(vm.broadcastTarget, BroadcastTarget(communityId: b, communityName: "Fremont Families"))
    }

    // MARK: - Announcement target

    func testBroadcastTarget_AllScopeResolvesTheDefaultCommunity() async {
        let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB, c = CommunityFixtures.communityC

        let withDefault = await makeContext([
            CommunityFixtures.membership(b, name: "Ballard Neighbors", role: .owner),
            CommunityFixtures.membership(a, name: "Naar's Cars Seattle", isDefault: true)
        ], platformAdmin: true)
        let communityAdmin = StubCommunityAdminService()
        let vm = makeViewModel(scope: .all, context: withDefault, communityAdmin: communityAdmin)
        await vm.verifyAdminAccess()

        XCTAssertTrue(vm.isAdmin)
        XCTAssertEqual(vm.broadcastTarget, BroadcastTarget(communityId: a, communityName: "Naar's Cars Seattle"))
        XCTAssertEqual(communityAdmin.fetchDefaultCommunityIdCalls, 0)

        let withoutDefault = await makeContext([
            CommunityFixtures.membership(b, name: "Ballard Neighbors", role: .owner)
        ], platformAdmin: true)
        let lookup = StubCommunityAdminService()
        lookup.fetchDefaultCommunityIdResult = .success(c)
        lookup.fetchCommunitySettingsResult = .success(CommunitySettings(
            id: c, name: "Naar's Cars Seattle", description: nil, joinPolicy: "approve",
            membersCanInvite: true, isPublic: true, isDefault: true, timezone: "America/Los_Angeles"
        ))
        let fetched = makeViewModel(scope: .all, context: withoutDefault, communityAdmin: lookup)
        await fetched.verifyAdminAccess()

        XCTAssertEqual(lookup.fetchDefaultCommunityIdCalls, 1)
        XCTAssertEqual(lookup.fetchCommunitySettingsCalls, [c])
        XCTAssertEqual(fetched.broadcastTarget, BroadcastTarget(communityId: c, communityName: "Naar's Cars Seattle"))

        let failing = StubCommunityAdminService()
        failing.fetchDefaultCommunityIdResult = .failure(URLError(.notConnectedToInternet))
        let offline = makeViewModel(scope: .all, context: withoutDefault, communityAdmin: failing)
        await offline.verifyAdminAccess()

        XCTAssertTrue(offline.isAdmin)
        XCTAssertNil(offline.broadcastTarget)
    }

    // MARK: - Admin → Communities

    func testCommunitiesAdminActions_OpenAdminPanelOnlyForLiveCommunities() {
        XCTAssertTrue(CommunitiesAdminViewModel.actions(for: platformCommunity()).contains(.openAdminPanel))
        XCTAssertTrue(CommunitiesAdminViewModel.actions(for: platformCommunity(pendingCount: 2)).contains(.openAdminPanel))
        XCTAssertTrue(CommunitiesAdminViewModel.actions(for: platformCommunity(isDefault: true)).contains(.openAdminPanel))
        XCTAssertFalse(CommunitiesAdminViewModel.actions(for: platformCommunity(archived: true)).contains(.openAdminPanel))
        XCTAssertEqual(CommunitiesAdminViewModel.actions(for: platformCommunity(archived: true)), [.restore])
    }

    // MARK: - Merge

    func testCommunityScope_OwnerLoadsTheIncomingMergeCount() async {
        let b = CommunityFixtures.communityB
        let context = await makeContext([CommunityFixtures.membership(b, name: "Ballard Neighbors", role: .owner)])
        let merge = StubCommunityService(result: .success([]))
        merge.fetchMergeProposalResult = .success(CommunityFixtures.mergeProposal(direction: .incoming))
        let vm = makeViewModel(scope: .community(b), context: context, merge: merge)

        await vm.verifyAdminAccess()

        XCTAssertEqual(merge.fetchMergeProposalCalls, [b])
        XCTAssertEqual(vm.incomingMergeCount, 1)
        XCTAssertTrue(vm.isOwnerOfScope)

        // An outgoing proposal is not waiting for this owner; a failure leaves 0.
        merge.fetchMergeProposalResult = .success(CommunityFixtures.mergeProposal(direction: .outgoing))
        await vm.loadIncomingMergeCount()
        XCTAssertEqual(vm.incomingMergeCount, 0)
        merge.fetchMergeProposalResult = .failure(URLError(.notConnectedToInternet))
        await vm.loadIncomingMergeCount()
        XCTAssertEqual(vm.incomingMergeCount, 0)
    }

    func testCommunityScope_AdminDoesNotLoadMerge() async {
        let b = CommunityFixtures.communityB
        let context = await makeContext([CommunityFixtures.membership(b, name: "Ballard Neighbors", role: .admin)])
        let merge = StubCommunityService(result: .success([]))
        merge.fetchMergeProposalResult = .success(CommunityFixtures.mergeProposal(direction: .incoming))
        let vm = makeViewModel(scope: .community(b), context: context, merge: merge)

        await vm.verifyAdminAccess()

        XCTAssertTrue(vm.isAdmin)
        XCTAssertTrue(merge.fetchMergeProposalCalls.isEmpty)
        XCTAssertEqual(vm.incomingMergeCount, 0)
        XCTAssertFalse(vm.isOwnerOfScope)
    }
}
