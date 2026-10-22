//
//  CreateCommunityViewModelTests.swift
//  NaarsCarsTests
//
//  Create a community and the invite code view model
//

import XCTest
@testable import NaarsCars

@MainActor
final class CreateCommunityViewModelTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Chicago")!

    private func makeViewModel(
        stub: StubCommunityService = StubCommunityService(result: .success([])),
        geocoder: StubPlaceGeocoder = StubPlaceGeocoder()
    ) -> CreateCommunityViewModel {
        let zone = self.zone
        return CreateCommunityViewModel(service: stub, geocoder: geocoder, deviceTimeZone: { zone })
    }

    /// A listed draft named "Harbor Riders" taken to the nearby step: Seattle, 10 miles, one overlap.
    private func makeListedAtNearby(
        stub: StubCommunityService,
        overlaps: [CommunitySearchResult] = [CommunityFixtures.searchResult(CommunityFixtures.communityA, name: "Community A")]
    ) async -> CreateCommunityViewModel {
        let geocoder = StubPlaceGeocoder()
        geocoder.forwardResults["Seattle"] = GeocodedPlace(
            label: "Seattle", point: GeoPoint(latitude: 47.6062, longitude: -122.3321)
        )
        stub.checkCommunityAreaResult = .success(overlaps)
        let vm = makeViewModel(stub: stub, geocoder: geocoder)
        vm.name = "Harbor Riders"
        vm.joinPolicy = .approve
        await vm.next()
        await vm.next()
        XCTAssertEqual(vm.step, .area)
        vm.areaDraft.placeQuery = "Seattle"
        await vm.areaDraft.resolvePlace()
        vm.areaDraft.radiusMiles = 10
        await vm.next()
        return vm
    }

    func testSubmit_IgnoresSecondCallWhileSubmitting() async {
        let stub = StubCommunityService(result: .success([]))
        var resume: CheckedContinuation<Void, Never>?
        stub.actionGate = { await withCheckedContinuation { resume = $0 } }
        let vm = CreateCommunityViewModel(service: stub)
        vm.name = "Ballard Neighbors"
        vm.isListed = false

        let first = Task { await vm.submit() }
        for _ in 0..<200 where stub.createCommunityCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(stub.createCommunityCalls.count, 1)
        _ = await vm.submit()
        resume?.resume()
        _ = await first.value

        XCTAssertEqual(stub.createCommunityCalls.count, 1)
        XCTAssertEqual(stub.createCommunityCalls[0].joinPolicy, .approve)
    }

    func testCreate_SendsTheDeviceTimeZone() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = CreateCommunityViewModel(
            service: stub,
            deviceTimeZone: { TimeZone(identifier: "America/Chicago")! }
        )
        vm.name = "Ballard Neighbors"
        vm.isListed = false

        let created = await vm.submit()

        XCTAssertNotNil(created)
        XCTAssertEqual(stub.createCommunityCalls.count, 1)
        XCTAssertEqual(stub.createCommunityCalls.last?.timezone, "America/Chicago")
        XCTAssertNil(stub.createCommunityCalls.last?.area, "a hidden community sends no area")
        XCTAssertNil(stub.createCommunityCalls.last?.reason)
    }

    func testSubmit_ListedWithoutAnAreaIsRefused() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = makeViewModel(stub: stub)
        vm.name = "Ballard Neighbors"
        XCTAssertTrue(vm.isListed, "listed is the default")

        let created = await vm.submit()

        XCTAssertNil(created)
        XCTAssertTrue(stub.createCommunityCalls.isEmpty)
    }

    func testHiddenCommunity_SkipsAreaAndNearbyAndSendsNoArea() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = makeViewModel(stub: stub)
        vm.name = "Harbor Riders"
        vm.isListed = false

        XCTAssertEqual(vm.step, .basics)
        XCTAssertFalse(vm.isFinalStep)
        await vm.next()
        XCTAssertEqual(vm.step, .access)
        XCTAssertTrue(vm.isFinalStep)
        XCTAssertEqual(vm.totalSteps, 3)
        await vm.next()
        XCTAssertEqual(vm.step, .access, "the final step does not advance; Create submits")

        let created = await vm.submit()

        XCTAssertNotNil(created)
        XCTAssertTrue(stub.checkCommunityAreaCalls.isEmpty)
        XCTAssertEqual(stub.createCommunityCalls.count, 1)
        XCTAssertNil(stub.createCommunityCalls.last?.area)
        XCTAssertNil(stub.createCommunityCalls.last?.reason)
    }

    func testListedCommunity_GoesThroughAreaAndNearbyAndSendsAreaAndReason() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = await makeListedAtNearby(stub: stub)

        XCTAssertEqual(stub.checkCommunityAreaCalls.count, 1)
        XCTAssertEqual(stub.checkCommunityAreaCalls.first?.area, CommunityFixtures.seattleArea)
        XCTAssertNil(stub.checkCommunityAreaCalls.first?.excluding)
        XCTAssertEqual(vm.step, .nearby)
        XCTAssertTrue(vm.isFinalStep)
        XCTAssertEqual(vm.totalSteps, 5)
        XCTAssertEqual(vm.areaDraft.overlaps.map(\.id), [CommunityFixtures.communityA])

        vm.areaDraft.reason = "  Parents of one school "
        XCTAssertTrue(vm.canAdvance)
        let created = await vm.submit()

        XCTAssertNotNil(created)
        XCTAssertEqual(stub.createCommunityCalls.last, NewCommunityDraft(
            name: "Harbor Riders",
            description: nil,
            joinPolicy: .approve,
            timezone: zone.identifier,
            area: CommunityFixtures.seattleArea,
            reason: "Parents of one school"
        ))
    }

    func testNearby_WithOverlapsCannotCreateWithoutAReason() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = await makeListedAtNearby(stub: stub)

        XCTAssertTrue(vm.areaDraft.needsReason)
        XCTAssertFalse(vm.canAdvance)
        vm.areaDraft.reason = "   "
        XCTAssertFalse(vm.canAdvance)
        let created = await vm.submit()
        XCTAssertNil(created)
        XCTAssertTrue(stub.createCommunityCalls.isEmpty)

        vm.areaDraft.reason = "Parents of one school"
        XCTAssertTrue(vm.canAdvance)
    }

    func testPolicyChoices_DoNotOfferOpen() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.policyChoices, [.approve, .invite])
        XCTAssertEqual(vm.joinPolicy, .approve)
    }

    func testReasonRequiredRefusal_ReturnsToNearbyAndRechecks() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = await makeListedAtNearby(stub: stub, overlaps: [])
        XCTAssertTrue(vm.canAdvance, "no overlap, so no reason is needed")
        stub.createCommunityResult = .failure(CommunityRPCError(code: .reasonRequired))
        stub.checkCommunityAreaResult = .success([
            CommunityFixtures.searchResult(CommunityFixtures.communityA, name: "Community A")
        ])

        let created = await vm.submit()

        XCTAssertNil(created)
        XCTAssertEqual(vm.lastRefusal?.code, .reasonRequired)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.step, .nearby)
        XCTAssertEqual(stub.checkCommunityAreaCalls.count, 2)
        XCTAssertTrue(vm.areaDraft.needsReason)
        XCTAssertFalse(vm.canAdvance)
    }

    func testInvalidAreaRefusal_ReturnsToTheAreaStep() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = await makeListedAtNearby(stub: stub, overlaps: [])
        stub.createCommunityResult = .failure(CommunityRPCError(code: .invalidArea))

        let created = await vm.submit()

        XCTAssertNil(created)
        XCTAssertEqual(vm.step, .area)
        XCTAssertEqual(stub.checkCommunityAreaCalls.count, 2, "the check runs again for the area shown")
    }

    func testBack_ReturnsThroughTheSteps() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = await makeListedAtNearby(stub: stub)

        vm.back()
        XCTAssertEqual(vm.step, .area)
        vm.back()
        XCTAssertEqual(vm.step, .access)
        vm.back()
        XCTAssertEqual(vm.step, .basics)
        vm.back()
        XCTAssertEqual(vm.step, .basics)
    }

    func testStepLine_CountsFiveListedThreeHidden() {
        let vm = makeViewModel()
        vm.name = "Harbor Riders"
        XCTAssertEqual(vm.totalSteps, 5)
        XCTAssertEqual(
            vm.stepLine,
            String(format: "community_create_step".localized, 1, 5, "community_create_step_basics".localized)
        )
        vm.isListed = false
        XCTAssertEqual(vm.totalSteps, 3)
        XCTAssertEqual(
            vm.stepLine,
            String(format: "community_create_step".localized, 1, 3, "community_create_step_basics".localized)
        )
    }
}

@MainActor
final class CommunityInviteViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeViewModel(
        isAdmin: Bool,
        stub: StubCommunityService,
        inviteLinksEnabled: Bool = false
    ) -> CommunityInviteViewModel {
        CommunityInviteViewModel(
            communityId: CommunityFixtures.communityA,
            communityName: "Community A",
            isAdmin: isAdmin,
            inviteLinksEnabled: inviteLinksEnabled,
            service: stub,
            now: { self.now }
        )
    }

    func testUsesText_OneAndMany() {
        let vm = makeViewModel(isAdmin: true, stub: StubCommunityService(result: .success([])))
        XCTAssertEqual(vm.usesText(1), "community_invite_uses_one".localized)
        XCTAssertTrue(vm.usesText(5).contains("5"))
    }

    private func makeViewModelWithCode(inviteLinksEnabled: Bool) async -> CommunityInviteViewModel {
        let stub = StubCommunityService(result: .success([]))
        let vm = makeViewModel(isAdmin: false, stub: stub, inviteLinksEnabled: inviteLinksEnabled)
        await vm.createCode()
        return vm
    }

    func testShareMessage_WithoutInviteLinksHasNoJoinLink() async throws {
        let vm = await makeViewModelWithCode(inviteLinksEnabled: false)
        let message = try XCTUnwrap(vm.shareMessage)
        XCTAssertFalse(message.contains("naarscars.com/join"))
        XCTAssertTrue(message.contains(Constants.URLs.appStore))
    }

    func testShareMessage_WithInviteLinksCarriesTheJoinLink() async throws {
        let vm = await makeViewModelWithCode(inviteLinksEnabled: true)
        let code = try XCTUnwrap(vm.displayedCode)
        let message = try XCTUnwrap(vm.shareMessage)
        XCTAssertTrue(message.contains(Constants.URLs.joinLink(code: code)))
    }

    func testQRPayload_WithInviteLinksIsTheBareJoinLink() async throws {
        let vm = await makeViewModelWithCode(inviteLinksEnabled: true)
        let code = try XCTUnwrap(vm.displayedCode)
        XCTAssertEqual(vm.qrPayload, Constants.URLs.joinLink(code: code))
    }

    func testQRPayload_WithoutInviteLinksIsTheShareMessage() async throws {
        let vm = await makeViewModelWithCode(inviteLinksEnabled: false)
        XCTAssertNotNil(vm.qrPayload)
        XCTAssertEqual(vm.qrPayload, vm.shareMessage)
    }

    func testCreateCode_MemberSendsSevenDayExpiry() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = makeViewModel(isAdmin: false, stub: stub)
        await vm.createCode()
        XCTAssertEqual(stub.createInviteCalls.count, 1)
        XCTAssertEqual(stub.createInviteCalls[0].communityId, CommunityFixtures.communityA)
        XCTAssertNil(stub.createInviteCalls[0].maxUses)
        XCTAssertEqual(stub.createInviteCalls[0].expiresAt, now.addingTimeInterval(7 * 86_400))
    }

    func testCreateCode_AdminSendsUsesAndChosenExpiry() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = makeViewModel(isAdmin: true, stub: stub)
        vm.maxUses = 25
        vm.expiryDays = 90
        await vm.createCode()
        XCTAssertEqual(stub.createInviteCalls.count, 1)
        XCTAssertEqual(stub.createInviteCalls[0].maxUses, 25)
        XCTAssertEqual(stub.createInviteCalls[0].expiresAt, now.addingTimeInterval(90 * 86_400 - 300))
    }
}
