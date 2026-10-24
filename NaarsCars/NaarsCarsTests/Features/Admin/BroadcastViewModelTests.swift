//
//  BroadcastViewModelTests.swift
//  NaarsCarsTests
//
//  Announcements to one community: the community RPC with trimmed fields, the daily limit and
//  "not an admin" messages with the draft kept, one send per tap, and the form cleared on success
//

import XCTest
@testable import NaarsCars

@MainActor
final class BroadcastViewModelTests: XCTestCase {
    private let communityName = "Ballard Neighbors"

    private func makeViewModel(admin: StubAdminService) -> BroadcastViewModel {
        BroadcastViewModel(
            communityId: CommunityFixtures.communityA,
            communityName: communityName,
            adminService: admin
        )
    }

    func testSend_CallsCommunityBroadcastWithTrimmedFields() async {
        let admin = StubAdminService()
        admin.sendBroadcastResult = .success(4)
        let vm = makeViewModel(admin: admin)
        vm.title = "  Title \n"
        vm.message = "\n Body  "
        vm.pinToNotifications = true

        await vm.sendBroadcast()

        XCTAssertEqual(admin.sendBroadcastCalls.count, 1)
        let call = admin.sendBroadcastCalls[0]
        XCTAssertEqual(call.communityId, CommunityFixtures.communityA)
        XCTAssertEqual(call.title, "Title")
        XCTAssertEqual(call.message, "Body")
        XCTAssertTrue(call.pinToNotifications)
        XCTAssertNil(vm.errorMessage)
    }

    func testSend_DailyLimitShowsLocalizedMessageAndKeepsDraft() async {
        let admin = StubAdminService()
        admin.sendBroadcastResult = .failure(AdminServiceError.broadcastDailyLimit)
        let vm = makeViewModel(admin: admin)
        vm.title = "Title"
        vm.message = "Body"
        vm.pinToNotifications = false

        await vm.sendBroadcast()

        XCTAssertEqual(vm.errorMessage, "admin_broadcast_daily_limit".localized(with: communityName))
        XCTAssertTrue(vm.errorMessage?.contains(communityName) ?? false)
        XCTAssertEqual(vm.title, "Title")
        XCTAssertEqual(vm.message, "Body")
        XCTAssertFalse(vm.pinToNotifications)
        XCTAssertNil(vm.successMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func testSend_NotAdminShowsNotAdminMessage() async {
        let admin = StubAdminService()
        admin.sendBroadcastResult = .failure(AdminServiceError.notCommunityAdmin)
        let vm = makeViewModel(admin: admin)
        vm.title = "Title"
        vm.message = "Body"

        await vm.sendBroadcast()

        XCTAssertEqual(vm.errorMessage, "community_pending_not_admin".localized)
        XCTAssertEqual(vm.title, "Title")
        XCTAssertEqual(vm.message, "Body")
        XCTAssertNil(vm.successMessage)
    }

    func testSend_IgnoresSecondCallWhileSending() async {
        let admin = StubAdminService()
        admin.sendBroadcastResult = .success(3)
        let vm = makeViewModel(admin: admin)
        vm.title = "Title"
        vm.message = "Body"

        var resume: CheckedContinuation<Void, Never>?
        admin.actionGate = { await withCheckedContinuation { resume = $0 } }
        let firstTask = Task { await vm.sendBroadcast() }
        for _ in 0..<200 where admin.sendBroadcastCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(admin.sendBroadcastCalls.count, 1)
        XCTAssertTrue(vm.isLoading)

        await vm.sendBroadcast()
        XCTAssertEqual(admin.sendBroadcastCalls.count, 1)

        for _ in 0..<200 where resume == nil { await Task.yield() }
        resume?.resume()
        await firstTask.value

        XCTAssertEqual(admin.sendBroadcastCalls.count, 1)
        XCTAssertFalse(vm.isLoading)
    }

    func testSend_SuccessClearsTheForm() async {
        let admin = StubAdminService()
        admin.sendBroadcastResult = .success(7)
        let vm = makeViewModel(admin: admin)
        vm.title = "Title"
        vm.message = "Body"
        vm.pinToNotifications = false

        await vm.sendBroadcast()

        XCTAssertEqual(vm.title, "")
        XCTAssertEqual(vm.message, "")
        XCTAssertTrue(vm.pinToNotifications)
        XCTAssertEqual(vm.successMessage, "admin_broadcast_success".localized)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }
}
