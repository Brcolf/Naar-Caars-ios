//
//  CommunityAccessViewModelTests.swift
//  NaarsCarsTests
//
//  The owner's access screen: only the owner saves, a listed-to-hidden switch sends no area, a
//  hidden-to-listed switch needs an area and the nearby check, a policy-only change keeps the
//  listing and the area, a moved area is checked without this community, and the default community
//  cannot be hidden
//

internal import Combine
import XCTest
@testable import NaarsCars

@MainActor
final class CommunityAccessViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let communityId = CommunityFixtures.communityA

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CommunityAccessViewModelTests.\(UUID().uuidString)"
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
        isListed: Bool,
        joinPolicy: String = "approve",
        isDefault: Bool = false,
        area: ServiceArea? = nil
    ) -> CommunitySettings {
        CommunitySettings(
            id: communityId, name: "Ballard Neighbors", description: nil, joinPolicy: joinPolicy,
            membersCanInvite: true, isPublic: isListed, isDefault: isDefault,
            timezone: "America/Los_Angeles", area: area
        )
    }

    private struct Harness {
        let viewModel: CommunityAccessViewModel
        let admin: StubCommunityAdminService
        let service: StubCommunityService
        let geocoder: StubPlaceGeocoder
    }

    private func makeHarness(
        role: CommunityRole = .owner,
        settings: CommunitySettings
    ) async -> Harness {
        let rows = [
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: role),
            CommunityFixtures.membership(CommunityFixtures.communityB, name: "Community B")
        ]
        let service = StubCommunityService(result: .success(rows))
        let context = CommunityContext(service: service, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()

        let admin = StubCommunityAdminService()
        admin.fetchCommunitySettingsResult = .success(settings)
        let geocoder = StubPlaceGeocoder()
        let viewModel = CommunityAccessViewModel(
            communityId: communityId,
            adminService: admin,
            service: service,
            geocoder: geocoder,
            communityContext: context
        )
        await viewModel.load()
        return Harness(viewModel: viewModel, admin: admin, service: service, geocoder: geocoder)
    }

    // MARK: - Tests

    func testNonOwner_CannotSave() async {
        let h = await makeHarness(role: .admin, settings: settings(isListed: true, area: CommunityFixtures.seattleArea))

        XCTAssertFalse(h.viewModel.isOwner)
        h.viewModel.joinPolicy = .invite
        XCTAssertFalse(h.viewModel.canSave)
        let saved = await h.viewModel.save()

        XCTAssertFalse(saved)
        XCTAssertTrue(h.admin.updateCommunityAccessCalls.isEmpty)
    }

    func testListedToHidden_SendsNoArea() async {
        let h = await makeHarness(settings: settings(isListed: true, area: CommunityFixtures.seattleArea))
        XCTAssertFalse(h.viewModel.canSave)

        h.viewModel.isListed = false
        XCTAssertFalse(h.viewModel.needsNearbyCheck)
        XCTAssertTrue(h.viewModel.canSave)
        let saved = await h.viewModel.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(h.admin.updateCommunityAccessCalls.count, 1)
        XCTAssertEqual(h.admin.updateCommunityAccessCalls.last?.communityId, communityId)
        XCTAssertEqual(
            h.admin.updateCommunityAccessCalls.last?.change,
            CommunityAccessChange(isListed: false, joinPolicy: .approve, newArea: nil, reason: nil)
        )
        XCTAssertFalse(h.viewModel.canSave)
    }

    func testHiddenToListed_RequiresAreaAndNearbyCheck() async {
        let h = await makeHarness(settings: settings(isListed: false))
        h.geocoder.forwardResults = [
            "Seattle": GeocodedPlace(label: "Seattle", point: GeoPoint(latitude: 47.6062, longitude: -122.3321))
        ]

        h.viewModel.isListed = true
        XCTAssertTrue(h.viewModel.isChangingArea, "a community with no stored area must choose one")
        XCTAssertTrue(h.viewModel.needsNearbyCheck)
        XCTAssertFalse(h.viewModel.canSave)

        h.viewModel.areaDraft.placeQuery = "Seattle"
        h.viewModel.areaDraft.radiusMiles = 10
        await h.viewModel.areaDraft.resolvePlace()
        XCTAssertFalse(h.viewModel.canSave, "the nearby check has not run")
        await h.viewModel.areaDraft.checkNearby()
        XCTAssertTrue(h.viewModel.canSave)

        let saved = await h.viewModel.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(
            h.admin.updateCommunityAccessCalls.last?.change,
            CommunityAccessChange(isListed: true, joinPolicy: .approve, newArea: CommunityFixtures.seattleArea, reason: nil)
        )
    }

    func testPolicyChangeOnly_KeepsListingAndArea() async {
        let h = await makeHarness(settings: settings(isListed: true, area: CommunityFixtures.seattleArea))

        h.viewModel.joinPolicy = .invite
        XCTAssertFalse(h.viewModel.needsNearbyCheck)
        XCTAssertTrue(h.viewModel.canSave)
        let saved = await h.viewModel.save()

        XCTAssertTrue(saved)
        XCTAssertTrue(h.service.checkCommunityAreaCalls.isEmpty)
        XCTAssertEqual(
            h.admin.updateCommunityAccessCalls.last?.change,
            CommunityAccessChange(isListed: true, joinPolicy: .invite, newArea: nil, reason: nil)
        )
    }

    func testMoveArea_RunsNearbyCheckExcludingThisCommunity() async {
        let h = await makeHarness(settings: settings(isListed: true, area: CommunityFixtures.seattleArea))
        h.geocoder.forwardResults = [
            "Fremont": GeocodedPlace(label: "Fremont", point: GeoPoint(latitude: 47.65, longitude: -122.35))
        ]

        h.viewModel.isChangingArea = true
        XCTAssertTrue(h.viewModel.needsNearbyCheck)
        h.viewModel.areaDraft.placeQuery = "Fremont"
        h.viewModel.areaDraft.radiusMiles = 5
        await h.viewModel.areaDraft.resolvePlace()
        XCTAssertFalse(h.viewModel.canSave)
        await h.viewModel.areaDraft.checkNearby()

        XCTAssertEqual(h.service.checkCommunityAreaCalls.last?.excluding, communityId)
        XCTAssertTrue(h.viewModel.canSave)
        let saved = await h.viewModel.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(
            h.admin.updateCommunityAccessCalls.last?.change,
            CommunityAccessChange(
                isListed: true,
                joinPolicy: .approve,
                newArea: ServiceArea(name: "Fremont", center: GeoPoint(latitude: 47.65, longitude: -122.35), radiusMiles: 5),
                reason: nil
            )
        )
    }

    func testDefaultCommunity_CannotBeHidden() async {
        let h = await makeHarness(settings: settings(isListed: true, isDefault: true, area: CommunityFixtures.seattleArea))

        h.viewModel.isListed = false

        XCTAssertFalse(h.viewModel.canSave)
        let saved = await h.viewModel.save()
        XCTAssertFalse(saved)
        XCTAssertTrue(h.admin.updateCommunityAccessCalls.isEmpty)
    }

    func testOverlapReason_IsSentWithTheArea() async {
        let h = await makeHarness(settings: settings(isListed: false, area: CommunityFixtures.seattleArea))
        h.service.checkCommunityAreaResult = .success([CommunityFixtures.searchResult(CommunityFixtures.communityB, name: "Harbor Riders")])

        h.viewModel.isListed = true
        XCTAssertFalse(h.viewModel.isChangingArea, "a stored area is kept unless the owner changes it")
        XCTAssertTrue(h.viewModel.needsNearbyCheck)
        await h.viewModel.areaDraft.checkNearby()
        XCTAssertFalse(h.viewModel.canSave, "an overlap needs a reason")
        h.viewModel.areaDraft.reason = "  Parents of one school "
        XCTAssertTrue(h.viewModel.canSave)
        let saved = await h.viewModel.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(
            h.admin.updateCommunityAccessCalls.last?.change,
            CommunityAccessChange(isListed: true, joinPolicy: .approve, newArea: nil, reason: "Parents of one school")
        )
    }

    func testSave_ReasonRequiredRefusalRechecksNearby() async {
        let h = await makeHarness(settings: settings(isListed: false, area: CommunityFixtures.seattleArea))
        h.viewModel.isListed = true
        await h.viewModel.areaDraft.checkNearby()
        XCTAssertEqual(h.service.checkCommunityAreaCalls.count, 1)
        h.admin.updateCommunityAccessResult = .failure(CommunityRPCError(code: .reasonRequired))
        h.service.checkCommunityAreaResult = .success([CommunityFixtures.searchResult(CommunityFixtures.communityB, name: "Harbor Riders")])

        let saved = await h.viewModel.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(h.service.checkCommunityAreaCalls.count, 2)
        XCTAssertTrue(h.viewModel.areaDraft.needsReason)
        XCTAssertEqual(h.viewModel.errorMessage, CommunityRPCError(code: .reasonRequired).localizedMessage)
    }
}
