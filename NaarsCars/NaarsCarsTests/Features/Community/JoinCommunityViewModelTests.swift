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
}
