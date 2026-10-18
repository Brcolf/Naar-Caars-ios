//
//  MyCommunitiesViewModelTests.swift
//  NaarsCarsTests
//
//  My communities: the Leave counts follow the server's unwind rules, a leave refreshes the
//  dashboard with the leftCommunity trigger, and a left community disappears even when the
//  follow-up membership refresh fails
//

import XCTest
import SwiftData
@testable import NaarsCars

@MainActor
final class MyCommunitiesViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let me = CommunityFixtures.userA
    private let neighbor = UUID(uuidString: "0B000000-0000-4000-8000-0000000000B1")!
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "MyCommunitiesViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A context restored for `userA` and loaded with active memberships of A and B.
    private func makeContext() async -> (CommunityContext, StubCommunityService) {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", memberCount: 5),
            CommunityFixtures.membership(CommunityFixtures.communityB, name: "Community B", memberCount: 9)
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: me)
        await context.refreshMemberships()
        return (context, stub)
    }

    private func ride(_ index: Int, userId: UUID, claimedBy: UUID?, status: String, community: UUID) -> SDRide {
        SDRide(
            id: UUID(uuidString: String(format: "0E000000-0000-4000-8000-%012d", index))!,
            userId: userId, date: base, time: "12:00:00", pickup: "Pickup", destination: "Destination",
            status: status, claimedBy: claimedBy, createdAt: base, updatedAt: base, communityId: community
        )
    }

    private func favor(_ index: Int, userId: UUID, claimedBy: UUID?, status: String, community: UUID) -> SDFavor {
        SDFavor(
            id: UUID(uuidString: String(format: "0F000000-0000-4000-8000-%012d", index))!,
            userId: userId, title: "Favor", location: "Location", date: base,
            status: status, claimedBy: claimedBy, createdAt: base, updatedAt: base, communityId: community
        )
    }

    // MARK: - Tests

    func testEstimate_FollowsTheUnwindRulesInThatCommunityOnly() throws {
        let container = try ModelContainer(
            for: SDRide.self, SDFavor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let a = CommunityFixtures.communityA
        let b = CommunityFixtures.communityB

        // In A: a neighbor's ride I claimed (reopens), my open favor (removed),
        // my ride a neighbor claimed (cancelled), my completed favor (untouched).
        context.insert(ride(1, userId: neighbor, claimedBy: me, status: "confirmed", community: a))
        context.insert(favor(2, userId: me, claimedBy: nil, status: "open", community: a))
        context.insert(ride(3, userId: me, claimedBy: neighbor, status: "confirmed", community: a))
        context.insert(favor(4, userId: me, claimedBy: neighbor, status: "completed", community: a))
        // In B: my open ride (another community, not counted).
        context.insert(ride(5, userId: me, claimedBy: nil, status: "open", community: b))
        try context.save()

        let rides = try context.fetch(FetchDescriptor<SDRide>())
        let favors = try context.fetch(FetchDescriptor<SDFavor>())
        let consequences = LeaveConsequences.estimate(rides: rides, favors: favors, userId: me, communityId: a)

        XCTAssertEqual(consequences, LeaveConsequences(reopened: 1, removed: 1, cancelled: 1))
    }

    func testLeave_RefreshesDashboardWithLeftCommunityTrigger() async throws {
        let (context, stub) = await makeContext()
        var triggers: [String] = []
        let vm = MyCommunitiesViewModel(
            service: stub,
            communityContext: context,
            refreshDashboard: { triggers.append($0) }
        )
        let membershipA = try XCTUnwrap(vm.active.first { $0.communityId == CommunityFixtures.communityA })

        let left = await vm.leave(membershipA)

        XCTAssertTrue(left)
        XCTAssertEqual(stub.leaveCommunityCalls, [CommunityFixtures.communityA])
        XCTAssertEqual(triggers, ["leftCommunity"])
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.toastMessage)
        XCTAssertNil(vm.busyCommunityId)
    }

    func testLeave_HidesCommunityWhenRefreshFails() async throws {
        let (context, contextStub) = await makeContext()
        let service = StubCommunityService(result: .success([]))
        let vm = MyCommunitiesViewModel(
            service: service,
            communityContext: context,
            refreshDashboard: { _ in }
        )
        let membershipA = try XCTUnwrap(vm.active.first { $0.communityId == CommunityFixtures.communityA })

        // The leave succeeds, then the network drops before the membership refresh.
        contextStub.result = .failure(URLError(.notConnectedToInternet))
        let fetchesBefore = contextStub.fetchCount
        let left = await vm.leave(membershipA)

        XCTAssertTrue(left)
        XCTAssertEqual(contextStub.fetchCount, fetchesBefore + 1)
        XCTAssertFalse(vm.active.contains { $0.communityId == CommunityFixtures.communityA })
        XCTAssertTrue(vm.active.contains { $0.communityId == CommunityFixtures.communityB })
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Owned-community limit request

    func testLimitRequestRange_IsTotalAtAndAboveTheCeiling() async throws {
        XCTAssertEqual(OwnedLimitRequestViewModel(currentMax: 3, service: StubCommunityService(result: .success([]))).range, 4...20)
        XCTAssertEqual(OwnedLimitRequestViewModel(currentMax: 19, service: StubCommunityService(result: .success([]))).range, 20...20)
        let atCeiling = OwnedLimitRequestViewModel(currentMax: 20, service: StubCommunityService(result: .success([])))
        XCTAssertEqual(atCeiling.range, 20...20)
        XCTAssertFalse(OwnedLimitRequestViewModel.canRequestMore(currentMax: 20))
        atCeiling.reason = "More"
        XCTAssertFalse(atCeiling.canSubmit)
        XCTAssertEqual(OwnedLimitRequestViewModel(currentMax: 25, service: StubCommunityService(result: .success([]))).range, 20...20)

        let (context, stub) = await makeContext()
        stub.fetchMyCommunityLimitsResult = .success(
            CommunityLimits(maxOwned: 20, ownedCount: 20, nextCreateAt: nil, canCreate: false, latestRequest: nil)
        )
        let viewModel = MyCommunitiesViewModel(service: stub, communityContext: context, refreshDashboard: { _ in })
        await viewModel.load()
        XCTAssertNil(viewModel.limitOffer)
    }
}
