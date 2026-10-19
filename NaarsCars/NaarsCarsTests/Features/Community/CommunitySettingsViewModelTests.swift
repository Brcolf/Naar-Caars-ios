//
//  CommunitySettingsViewModelTests.swift
//  NaarsCarsTests
//
//  Community settings: fields from the server, who may edit and archive (mirroring
//  update_community and archive_community), only edited fields sent, one save at a time, and an
//  archive that forgets the membership and refreshes the dashboard
//

import XCTest
@testable import NaarsCars

@MainActor
final class CommunitySettingsViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CommunitySettingsViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func settings(
        name: String = "Ballard Neighbors",
        description: String? = "Ballard rides and favors.",
        joinPolicy: String = "approve",
        membersCanInvite: Bool = true,
        isDefault: Bool = false
    ) -> CommunitySettings {
        CommunitySettings(
            id: CommunityFixtures.communityA, name: name, description: description, joinPolicy: joinPolicy,
            membersCanInvite: membersCanInvite, isPublic: false, isDefault: isDefault, timezone: "America/Los_Angeles"
        )
    }

    /// A context restored for `userA`, loaded with A in `role` (none when nil) and B as a member.
    private func makeContext(
        role: CommunityRole?,
        platformAdmin: Bool = false
    ) async -> (CommunityContext, StubCommunityService) {
        var rows = [CommunityFixtures.membership(CommunityFixtures.communityB, name: "Community B")]
        if let role {
            rows.insert(CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: role), at: 0)
        }
        let stub = StubCommunityService(result: .success(rows))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { platformAdmin })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        return (context, stub)
    }

    private func makeViewModel(
        context: CommunityContext,
        admin: StubCommunityAdminService,
        dashboardTriggers: ((String) -> Void)? = nil
    ) -> CommunitySettingsViewModel {
        CommunitySettingsViewModel(
            communityId: CommunityFixtures.communityA,
            adminService: admin,
            communityContext: context,
            refreshDashboard: { dashboardTriggers?($0) }
        )
    }

    // MARK: - Tests

    func testLoad_FillsFieldsFromSettings() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunitySettingsResult = .success(settings(
            name: "Fremont", description: "Fremont rides.", joinPolicy: "invite", membersCanInvite: false
        ))
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()

        XCTAssertEqual(vm.access, .allowed)
        XCTAssertEqual(admin.fetchCommunitySettingsCalls, [CommunityFixtures.communityA])
        XCTAssertEqual(vm.name, "Fremont")
        XCTAssertEqual(vm.description, "Fremont rides.")
        XCTAssertFalse(vm.requiresApproval)
        XCTAssertFalse(vm.membersCanInvite)
        XCTAssertTrue(vm.change.isEmpty)
        XCTAssertFalse(vm.canSave)

        admin.fetchCommunitySettingsResult = .success(settings(description: nil, joinPolicy: "approve"))
        await vm.load()
        XCTAssertTrue(vm.requiresApproval)
        XCTAssertEqual(vm.description, "")
    }

    func testLoad_PlainMemberGetsNotAdminWithoutFetching() async {
        let (context, _) = await makeContext(role: .member)
        let admin = StubCommunityAdminService()
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()

        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertTrue(admin.fetchCommunitySettingsCalls.isEmpty)
    }

    func testCanEdit_OwnerOrPlatformAdminOnly() async {
        let (ownerContext, _) = await makeContext(role: .owner)
        let owner = makeViewModel(context: ownerContext, admin: StubCommunityAdminService())
        await owner.load()
        XCTAssertTrue(owner.canEdit)

        let (adminContext, _) = await makeContext(role: .admin)
        let plainAdmin = makeViewModel(context: adminContext, admin: StubCommunityAdminService())
        await plainAdmin.load()
        XCTAssertEqual(plainAdmin.access, .allowed)
        XCTAssertFalse(plainAdmin.canEdit)
        XCTAssertFalse(plainAdmin.canArchive)
        plainAdmin.name = "Renamed"
        XCTAssertFalse(plainAdmin.canSave)

        let (platformContext, _) = await makeContext(role: nil, platformAdmin: true)
        let platform = makeViewModel(context: platformContext, admin: StubCommunityAdminService())
        await platform.load()
        XCTAssertEqual(platform.access, .allowed)
        XCTAssertTrue(platform.canEdit)
        XCTAssertTrue(platform.canArchive)
    }

    func testChange_ContainsOnlyEditedFields() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunitySettingsResult = .success(settings())
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        vm.name = "New  "
        XCTAssertEqual(vm.change, CommunitySettingsChange(name: "New"))

        vm.name = "  Ballard Neighbors "
        vm.description = "Ballard rides and favors. "
        XCTAssertTrue(vm.change.isEmpty)

        vm.description = "   "
        vm.requiresApproval = false
        vm.membersCanInvite = false
        XCTAssertEqual(vm.change, CommunitySettingsChange(description: "", joinPolicy: .invite, membersCanInvite: false))
    }

    func testSave_IgnoresSecondCallWhileSaving() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()
        vm.name = "New"

        var resume: CheckedContinuation<Void, Never>?
        admin.actionGate = { await withCheckedContinuation { resume = $0 } }
        let first = Task { await vm.save() }
        for _ in 0..<200 where admin.updateCommunityCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(admin.updateCommunityCalls.count, 1)
        XCTAssertTrue(vm.isSaving)

        let second = await vm.save()
        XCTAssertFalse(second)
        resume?.resume()
        let firstResult = await first.value

        XCTAssertTrue(firstResult)
        XCTAssertEqual(admin.updateCommunityCalls.count, 1)
        XCTAssertEqual(admin.updateCommunityCalls[0].change, CommunitySettingsChange(name: "New"))
        XCTAssertNotNil(vm.toastMessage)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isSaving)
    }

    func testSave_KeepsSavedValuesWhenReloadFails() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()
        vm.name = "New"

        admin.fetchCommunitySettingsResult = .failure(URLError(.notConnectedToInternet))
        let saved = await vm.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(vm.settings?.name, "New")
        XCTAssertEqual(vm.name, "New")
        XCTAssertTrue(vm.change.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func testCanSave_ValidatesNameAndDescription() async {
        let (context, _) = await makeContext(role: .owner)
        let vm = makeViewModel(context: context, admin: StubCommunityAdminService())
        await vm.load()

        vm.name = "A"
        XCTAssertFalse(vm.canSave)
        vm.name = "Ab"
        XCTAssertTrue(vm.canSave)
        vm.name = String(repeating: "x", count: 61)
        XCTAssertFalse(vm.canSave)

        vm.name = "Ballard Neighbors"
        vm.description = String(repeating: "d", count: 301)
        XCTAssertFalse(vm.canSave)
        vm.description = String(repeating: "d", count: 300)
        XCTAssertTrue(vm.canSave)
    }

    func testArchive_ForgetsMembershipAndRefreshesDashboard() async {
        let (context, contextStub) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        var triggers: [String] = []
        let vm = makeViewModel(context: context, admin: admin, dashboardTriggers: { triggers.append($0) })
        await vm.load()
        XCTAssertTrue(vm.canArchive)

        // The server no longer lists the archived community.
        contextStub.result = .success([CommunityFixtures.membership(CommunityFixtures.communityB, name: "Community B")])
        let archived = await vm.archive()

        XCTAssertTrue(archived)
        XCTAssertTrue(vm.didArchive)
        XCTAssertEqual(admin.archiveCommunityCalls, [CommunityFixtures.communityA])
        XCTAssertNil(context.membership(for: CommunityFixtures.communityA))
        XCTAssertNotNil(context.membership(for: CommunityFixtures.communityB))
        XCTAssertEqual(triggers, ["archivedCommunity"])
        XCTAssertNotNil(vm.toastMessage)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isArchiving)
    }

    func testArchive_ForgetsMembershipWhenRefreshFails() async {
        let (context, contextStub) = await makeContext(role: .owner)
        let vm = makeViewModel(context: context, admin: StubCommunityAdminService())
        await vm.load()

        contextStub.result = .failure(URLError(.notConnectedToInternet))
        let archived = await vm.archive()

        XCTAssertTrue(archived)
        XCTAssertNil(context.membership(for: CommunityFixtures.communityA))
    }

    func testCanArchive_NeverForTheDefaultCommunity() async {
        let (context, _) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        admin.fetchCommunitySettingsResult = .success(settings(isDefault: true))
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        XCTAssertTrue(vm.canEdit)
        XCTAssertFalse(vm.canArchive)
        let archived = await vm.archive()
        XCTAssertFalse(archived)
        XCTAssertTrue(admin.archiveCommunityCalls.isEmpty)

        let (platformContext, _) = await makeContext(role: nil, platformAdmin: true)
        let platform = makeViewModel(context: platformContext, admin: admin)
        await platform.load()
        XCTAssertFalse(platform.canArchive)
    }

    func testSave_RefusalWithoutCodeShowsNotAllowedAndReloads() async {
        let (context, contextStub) = await makeContext(role: .owner)
        let admin = StubCommunityAdminService()
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()
        vm.name = "New"

        // The owner was demoted meanwhile.
        contextStub.result = .success([CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: .member)])
        admin.updateCommunityResult = .failure(CommunityRPCError(code: nil, serverMessage: "Only the owner can change this community"))
        let saved = await vm.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(vm.errorMessage, "community_member_action_not_allowed".localized)
        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertNil(vm.toastMessage)
    }
}
