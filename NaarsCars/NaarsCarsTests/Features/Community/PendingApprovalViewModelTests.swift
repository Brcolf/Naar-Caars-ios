//
//  PendingApprovalViewModelTests.swift
//  NaarsCarsTests
//
//  The waiting screen's relaunch decisions: one relaunch per screen, never a relaunch while the
//  account route still reads `.pendingApproval`, and today's approval check when the list fails
//

import XCTest
@testable import NaarsCars

@MainActor
final class PendingApprovalViewModelTests: XCTestCase {
    private struct RouteFailure: Error {}

    private var route: Result<AuthState, Error> = .success(.pendingApproval)
    private var routeCalls = 0
    private var approved = false
    private var approvalCalls = 0

    override func setUp() async throws {
        try await super.setUp()
        route = .success(.pendingApproval)
        routeCalls = 0
        approved = false
        approvalCalls = 0
    }

    private func makeViewModel(_ service: StubCommunityService) -> PendingApprovalViewModel {
        PendingApprovalViewModel(
            service: service,
            accountRoute: { [unowned self] in
                self.routeCalls += 1
                return try self.route.get()
            },
            approvalCheck: { [unowned self] in
                self.approvalCalls += 1
                return self.approved
            }
        )
    }

    func testPoll_ActiveMembershipRelaunches() async {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Seattle", status: .active)
        ]))
        let viewModel = makeViewModel(stub)

        let outcome = await viewModel.poll()

        XCTAssertEqual(outcome, .relaunch)
        XCTAssertEqual(routeCalls, 0)
        XCTAssertEqual(approvalCalls, 0)
    }

    func testPoll_PendingOnlyListsNamesAndWaits() async {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(CommunityFixtures.communityB, name: "Ballard", status: .pending)
        ]))
        let viewModel = makeViewModel(stub)

        let outcome = await viewModel.poll()

        XCTAssertEqual(outcome, .waiting)
        XCTAssertEqual(viewModel.pendingCommunityNames, ["Ballard"])
        XCTAssertEqual(viewModel.membershipIds, [CommunityFixtures.communityB])
        // Join another community's search labels this community "Waiting" from the same rows.
        XCTAssertEqual(viewModel.membership(for: CommunityFixtures.communityB)?.status, .pending)
        XCTAssertNil(viewModel.membership(for: CommunityFixtures.communityA))
        XCTAssertEqual(routeCalls, 0, "a pending row is enough to wait")
    }

    func testPoll_NoMembershipAndRouteNeedsApplicationRelaunches() async {
        route = .success(.needsApplication)
        let viewModel = makeViewModel(StubCommunityService(result: .success([])))

        let outcome = await viewModel.poll()

        XCTAssertEqual(outcome, .relaunch)
        XCTAssertEqual(routeCalls, 1)
        XCTAssertEqual(viewModel.pendingCommunityNames, [])
    }

    func testPoll_NoMembershipRouteStillPendingWaits() async {
        route = .success(.pendingApproval)
        let viewModel = makeViewModel(StubCommunityService(result: .success([])))

        let outcome = await viewModel.poll()
        XCTAssertEqual(outcome, .waiting, "relaunching would land on this same screen, in a loop")

        // A failed route read never relaunches either.
        route = .failure(RouteFailure())
        let second = await viewModel.poll()
        XCTAssertEqual(second, .waiting)
        XCTAssertEqual(routeCalls, 2)
    }

    func testPoll_FetchFailureFallsBackToApprovalCheck() async {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(CommunityFixtures.communityB, name: "Ballard", status: .pending)
        ]))
        let viewModel = makeViewModel(stub)
        _ = await viewModel.poll()

        stub.result = .failure(URLError(.notConnectedToInternet))
        approved = false
        let waiting = await viewModel.poll()
        XCTAssertEqual(waiting, .waiting)
        XCTAssertEqual(viewModel.pendingCommunityNames, ["Ballard"], "a failed call keeps the names")
        XCTAssertEqual(approvalCalls, 1)

        approved = true
        let relaunch = await viewModel.poll()
        XCTAssertEqual(relaunch, .relaunch)
        XCTAssertEqual(approvalCalls, 2)
        XCTAssertEqual(routeCalls, 0)
    }

    func testPoll_AfterRelaunchDecisionDoesNotFetchAgain() async {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Seattle", status: .active)
        ]))
        let viewModel = makeViewModel(stub)

        let first = await viewModel.poll()
        let second = await viewModel.poll()

        XCTAssertEqual(first, .relaunch)
        XCTAssertEqual(second, .relaunch)
        XCTAssertEqual(stub.fetchCount, 1)
    }

    // MARK: - Root notice

    /// An archive of the last active community lands here when a request is still waiting
    /// elsewhere (the application is complete): this root consumes the notice, and onboarding,
    /// if it follows, does not show it again.
    func testTakeRootNotice_WaitingScreenConsumesTheArchiveNotice() {
        RootNotice.pending = "Ballard Neighbors was archived."
        defer { RootNotice.pending = nil }
        let viewModel = makeViewModel(StubCommunityService(result: .success([])))

        XCTAssertEqual(viewModel.takeRootNotice(), "Ballard Neighbors was archived.")
        XCTAssertNil(viewModel.takeRootNotice())
        let onboarding = CommunityOnboardingViewModel(loadStoredName: { "Sam" }, updateName: { _ in }, relaunch: {})
        XCTAssertNil(onboarding.takeRootNotice())
    }
}
