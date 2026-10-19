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
    func testSubmit_IgnoresSecondCallWhileSubmitting() async {
        let stub = StubCommunityService(result: .success([]))
        let admin = StubCommunityAdminService()
        var resume: CheckedContinuation<Void, Never>?
        stub.actionGate = { await withCheckedContinuation { resume = $0 } }
        let vm = CreateCommunityViewModel(service: stub, adminService: admin, isPlatformAdmin: false)
        vm.name = "Ballard Neighbors"

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
            adminService: StubCommunityAdminService(),
            isPlatformAdmin: false,
            deviceTimeZone: { TimeZone(identifier: "America/Chicago")! }
        )
        vm.name = "Ballard Neighbors"

        let created = await vm.submit()

        XCTAssertNotNil(created)
        XCTAssertEqual(stub.createCommunityCalls.count, 1)
        XCTAssertEqual(stub.createCommunityCalls[0].timezone, "America/Chicago")
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
