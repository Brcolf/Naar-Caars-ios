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
}

@MainActor
final class CommunityInviteViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeViewModel(isAdmin: Bool, stub: StubCommunityService) -> CommunityInviteViewModel {
        CommunityInviteViewModel(
            communityId: CommunityFixtures.communityA,
            communityName: "Community A",
            isAdmin: isAdmin,
            service: stub,
            now: { self.now }
        )
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
