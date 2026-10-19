//
//  JoinCommunityViewModelTests.swift
//  NaarsCarsTests
//
//  Joining a community with a code or by asking a public one
//

import XCTest
@testable import NaarsCars

@MainActor
final class JoinCommunityViewModelTests: XCTestCase {
    private let publicCommunity = PublicCommunity(
        id: CommunityFixtures.communityB,
        name: "Community B",
        description: nil,
        joinPolicy: CommunityJoinPolicy.approve.rawValue,
        isDefault: false
    )

    func testValidate_SendsNormalizedCode() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = JoinCommunityViewModel(target: .code(prefilled: nil), service: stub)
        vm.code = "nc7k · 2pq9-xa"
        await vm.validate()
        XCTAssertEqual(stub.validateInviteCalls, ["NC7K2PQ9XA"])
        XCTAssertNotNil(vm.preview)
    }

    func testEditingCheckedCode_DropsPreviewAndBlocksSubmit() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = JoinCommunityViewModel(target: .code(prefilled: "NC7K2PQ9XA"), service: stub)
        await vm.validate()
        XCTAssertNotNil(vm.preview)
        XCTAssertEqual(vm.checkedCode, "NC7K2PQ9XA")

        vm.code = "nc7k-2pq9xa"
        XCTAssertNotNil(vm.preview, "A change that normalizes to the checked code keeps the preview")

        vm.code = "NC7K2PQ9XB"
        vm.heardAbout = "A neighbor"
        vm.joinReason = "Share rides"
        XCTAssertNil(vm.preview)
        XCTAssertNil(vm.checkedCode)
        XCTAssertFalse(vm.canSubmit)
        await vm.submit()
        XCTAssertTrue(stub.redeemInviteCalls.isEmpty)
    }

    func testValidate_MalformedCodeIsNotSent() async {
        let stub = StubCommunityService(result: .success([]))
        let vm = JoinCommunityViewModel(target: .code(prefilled: nil), service: stub)
        vm.code = "NC12"
        await vm.validate()
        XCTAssertTrue(stub.validateInviteCalls.isEmpty)
        XCTAssertEqual(vm.errorMessage, "community_join_code_malformed".localized)
    }

    func testSubmit_IgnoresSecondCallWhileSubmitting() async {
        let stub = StubCommunityService(result: .success([]))
        var resume: CheckedContinuation<Void, Never>?
        stub.actionGate = { await withCheckedContinuation { resume = $0 } }
        let vm = JoinCommunityViewModel(target: .publicCommunity(publicCommunity), service: stub)
        vm.heardAbout = "A neighbor"
        vm.joinReason = "Share rides"

        let first = Task { await vm.submit() }
        for _ in 0..<200 where stub.requestToJoinCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(stub.requestToJoinCalls.count, 1)
        await vm.submit()
        resume?.resume()
        _ = await first.value

        XCTAssertEqual(stub.requestToJoinCalls.count, 1)
        XCTAssertEqual(stub.requestToJoinCalls[0].communityId, CommunityFixtures.communityB)
    }

    func testSubmit_ReportsResultAsSoonAsItIsSet() async {
        let stub = StubCommunityService(result: .success([]))
        stub.requestToJoinResult = .success(JoinResult(communityId: CommunityFixtures.communityB, status: .pending))
        var recorded: [JoinResult] = []
        let vm = JoinCommunityViewModel(
            target: .publicCommunity(publicCommunity),
            service: stub,
            onResult: { recorded.append($0) }
        )
        vm.heardAbout = "A neighbor"
        vm.joinReason = "Share rides"

        await vm.submit()
        XCTAssertEqual(recorded, [JoinResult(communityId: CommunityFixtures.communityB, status: .pending)])

        await vm.submit()
        XCTAssertEqual(stub.requestToJoinCalls.count, 1)
        XCTAssertEqual(recorded.count, 1)
    }

    // MARK: - Stored invite code (PendingInviteStore)

    private func makeStore() -> (PendingInviteStore, UserDefaults, String) {
        let suiteName = "JoinCommunityViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PendingInviteStore(defaults: defaults)
        store.save("NC7K2PQ9XA")
        return (store, defaults, suiteName)
    }

    func testRedeem_ClearsTheMatchingStoredCode() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let stub = StubCommunityService(result: .success([]))
        let vm = JoinCommunityViewModel(target: .code(prefilled: "NC7K2PQ9XA"), service: stub, pendingInviteStore: store)

        await vm.validate()
        XCTAssertEqual(store.peek(), "NC7K2PQ9XA")
        await vm.submit()

        XCTAssertEqual(stub.redeemInviteCalls.count, 1)
        XCTAssertNil(store.peek())
    }

    func testRedeemRateLimited_KeepsTheStoredCode() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let stub = StubCommunityService(result: .success([]))
        stub.redeemInviteResult = .failure(CommunityRPCError(code: .rateLimited))
        let vm = JoinCommunityViewModel(target: .code(prefilled: "NC7K2PQ9XA"), service: stub, pendingInviteStore: store)

        await vm.validate()
        await vm.submit()

        XCTAssertEqual(stub.redeemInviteCalls.count, 1)
        XCTAssertEqual(vm.errorMessage, CommunityRPCError(code: .rateLimited).localizedMessage)
        XCTAssertEqual(store.peek(), "NC7K2PQ9XA")
    }

    func testValidateInvalid_ClearsTheMatchingStoredCode() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let stub = StubCommunityService(result: .success([]))
        stub.validateInviteResult = .success(
            InvitePreview(valid: false, expired: false, requiresApproval: nil, communityName: nil, alreadyMember: nil, memberCount: nil)
        )
        let vm = JoinCommunityViewModel(target: .code(prefilled: "NC7K2PQ9XA"), service: stub, pendingInviteStore: store)

        await vm.validate()

        XCTAssertEqual(vm.errorMessage, "community_error_invalid".localized)
        XCTAssertNil(store.peek())
    }
}
