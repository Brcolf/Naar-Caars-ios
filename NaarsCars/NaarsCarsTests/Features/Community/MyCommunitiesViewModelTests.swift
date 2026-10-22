//
//  MyCommunitiesViewModelTests.swift
//  NaarsCarsTests
//
//  My communities: the Leave counts follow the server's unwind rules, a leave refreshes the
//  dashboard with the leftCommunity trigger, and a left community disappears even when the
//  follow-up membership refresh fails
//

import AuthenticationServices
import XCTest
import SwiftData
@testable import NaarsCars

/// Answers only `currentUserId`; every other method is unused here.
private final class StubExploreAuthService: AuthServiceProtocol {
    var currentUserId: UUID?
    var currentProfile: Profile? { nil }

    init(currentUserId: UUID?) { self.currentUserId = currentUserId }

    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String, name: String, car: String?) async throws {}
    func signOut() async throws {}
    func sendPasswordReset(email: String) async throws {}
    func signUpWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws {}
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult { .success }
}

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

    func testLeave_LastOwnerRefusalOffersTransfer() async throws {
        let (context, _) = await makeContext()
        let service = StubCommunityService(result: .success([]))
        service.leaveCommunityResult = .failure(CommunityRPCError(code: .lastOwner, serverMessage: "A community needs an owner"))
        var triggers: [String] = []
        let vm = MyCommunitiesViewModel(
            service: service,
            communityContext: context,
            refreshDashboard: { triggers.append($0) }
        )
        let membershipA = try XCTUnwrap(vm.active.first { $0.communityId == CommunityFixtures.communityA })

        let left = await vm.leave(membershipA)

        XCTAssertFalse(left)
        XCTAssertEqual(vm.newOwnerNeededFor, membershipA)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.toastMessage)
        XCTAssertEqual(triggers, [])
        XCTAssertTrue(vm.active.contains { $0.communityId == CommunityFixtures.communityA })
        XCTAssertNil(vm.busyCommunityId)

        // Any other refusal still shows its message.
        service.leaveCommunityResult = .failure(CommunityRPCError(code: .notMember))
        vm.newOwnerNeededFor = nil
        _ = await vm.leave(membershipA)
        XCTAssertNil(vm.newOwnerNeededFor)
        XCTAssertEqual(vm.errorMessage, CommunityRPCError(code: .notMember).localizedMessage)
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
        let viewModel = MyCommunitiesViewModel(service: stub, communityContext: context, refreshDashboard: { _ in }, isGuest: { false })
        await viewModel.load()
        XCTAssertNil(viewModel.limitOffer)
    }

    // MARK: - Explore: listed communities

    private func listed(_ id: UUID, name: String, policy: String = "approve") -> PublicCommunity {
        PublicCommunity(id: id, name: name, description: nil, joinPolicy: policy, isDefault: false)
    }

    func testListedToShow_LeavesOutActiveAndPendingMemberships() async {
        let a = CommunityFixtures.communityA
        let b = CommunityFixtures.communityB
        let c = CommunityFixtures.communityC
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(a, name: "Community A"),
            CommunityFixtures.membership(b, name: "Community B", status: .pending)
        ]))
        stub.fetchPublicCommunitiesResult = .success([
            listed(a, name: "Community A"), listed(b, name: "Community B"), listed(c, name: "Community C")
        ])
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: me)
        let vm = MyCommunitiesViewModel(service: stub, communityContext: context, refreshDashboard: { _ in }, isGuest: { false })

        await vm.load()

        XCTAssertEqual(vm.listedToShow.map(\.id), [c])
        XCTAssertFalse(vm.listedLoadFailed)
    }

    func testLoad_GuestLoadsListedOnlyWithoutMembershipOrLimitCalls() async {
        let stub = StubCommunityService(result: .success([CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A")]))
        stub.fetchPublicCommunitiesResult = .success([listed(CommunityFixtures.communityC, name: "Community C")])
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        let vm = MyCommunitiesViewModel(service: stub, communityContext: context, refreshDashboard: { _ in }, isGuest: { true })

        await vm.load()

        XCTAssertEqual(stub.fetchCount, 0)
        XCTAssertEqual(stub.fetchMyCommunityLimitsCalls, 0)
        XCTAssertEqual(stub.fetchPublicCommunitiesCalls, 1)
        XCTAssertEqual(vm.listedToShow.map(\.id), [CommunityFixtures.communityC])
        XCTAssertFalse(vm.hasLoadedMemberships)
        XCTAssertNil(vm.limits)
    }

    func testLoadIfStale_SkipsWithinTheStalenessWindow() async {
        let stub = StubCommunityService(result: .success([CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A")]))
        stub.fetchPublicCommunitiesResult = .success([listed(CommunityFixtures.communityC, name: "Community C")])
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: me)
        var clock = base
        let vm = MyCommunitiesViewModel(
            service: stub, communityContext: context, refreshDashboard: { _ in },
            isGuest: { false }, now: { clock }
        )

        await vm.loadIfStale()
        XCTAssertEqual(stub.fetchCount, 1)
        XCTAssertEqual(stub.fetchMyCommunityLimitsCalls, 1)
        XCTAssertEqual(stub.fetchPublicCommunitiesCalls, 1)

        clock = base.addingTimeInterval(10)
        await vm.loadIfStale()
        XCTAssertEqual(stub.fetchCount, 1)
        XCTAssertEqual(stub.fetchMyCommunityLimitsCalls, 1)
        XCTAssertEqual(stub.fetchPublicCommunitiesCalls, 1)

        clock = base.addingTimeInterval(31)
        await vm.loadIfStale()
        XCTAssertEqual(stub.fetchCount, 2)
        XCTAssertEqual(stub.fetchMyCommunityLimitsCalls, 2)
        XCTAssertEqual(stub.fetchPublicCommunitiesCalls, 2)

        // Pull-to-refresh and Retry call load() and always read.
        await vm.load()
        XCTAssertEqual(stub.fetchPublicCommunitiesCalls, 3)
    }

    func testLoadIfStale_ReadsAgainAfterAFailedListedLoad() async {
        let stub = StubCommunityService(result: .success([]))
        stub.fetchPublicCommunitiesResult = .failure(URLError(.notConnectedToInternet))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        var clock = base
        let vm = MyCommunitiesViewModel(
            service: stub, communityContext: context, refreshDashboard: { _ in },
            isGuest: { true }, now: { clock }
        )

        await vm.loadIfStale()
        clock = base.addingTimeInterval(5)
        await vm.loadIfStale()

        XCTAssertEqual(stub.fetchPublicCommunitiesCalls, 2)
    }

    func testLoadIfStale_ReadsAgainWhenAMembersMembershipsNeverLoaded() async {
        let stub = StubCommunityService(result: .failure(URLError(.notConnectedToInternet)))
        stub.fetchPublicCommunitiesResult = .success([listed(CommunityFixtures.communityC, name: "Community C")])
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: me)
        var clock = base
        let vm = MyCommunitiesViewModel(
            service: stub, communityContext: context, refreshDashboard: { _ in },
            isGuest: { false }, now: { clock }
        )

        await vm.loadIfStale()
        XCTAssertFalse(vm.hasLoadedMemberships)

        // The listed rows loaded, but there is no membership state to show: the next appearance reads again.
        clock = base.addingTimeInterval(5)
        stub.result = .success([CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A")])
        await vm.loadIfStale()

        XCTAssertEqual(stub.fetchCount, 2)
        XCTAssertTrue(vm.hasLoadedMemberships)

        // Loaded now: within the window it stays quiet.
        clock = base.addingTimeInterval(10)
        await vm.loadIfStale()
        XCTAssertEqual(stub.fetchCount, 2)
    }

    func testListedLoadFailure_SetsTheFlagAndKeepsTheRows() async {
        let c = CommunityFixtures.communityC
        let stub = StubCommunityService(result: .success([]))
        stub.fetchPublicCommunitiesResult = .success([listed(c, name: "Community C")])
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: me)
        let vm = MyCommunitiesViewModel(service: stub, communityContext: context, refreshDashboard: { _ in }, isGuest: { false })

        await vm.load()
        XCTAssertFalse(vm.listedLoadFailed)
        XCTAssertEqual(vm.listedToShow.map(\.id), [c])

        stub.fetchPublicCommunitiesResult = .failure(URLError(.notConnectedToInternet))
        await vm.load()
        XCTAssertTrue(vm.listedLoadFailed)
        XCTAssertEqual(vm.listedToShow.map(\.id), [c])

        // A cancelled pull-to-refresh is not a result: the flag stays as it was.
        stub.fetchPublicCommunitiesResult = .failure(URLError(.cancelled))
        await vm.load()
        XCTAssertTrue(vm.listedLoadFailed)

        stub.fetchPublicCommunitiesResult = .success([listed(c, name: "Community C")])
        await vm.load()
        XCTAssertFalse(vm.listedLoadFailed)

        stub.fetchPublicCommunitiesResult = .failure(CancellationError())
        await vm.load()
        XCTAssertFalse(vm.listedLoadFailed)
    }

    func testIsGuest_DefaultFollowsTheInjectedAuthService() {
        let stub = StubCommunityService(result: .success([]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        let signedOut = MyCommunitiesViewModel(service: stub, communityContext: context, authService: StubExploreAuthService(currentUserId: nil))
        let signedIn = MyCommunitiesViewModel(service: stub, communityContext: context, authService: StubExploreAuthService(currentUserId: me))
        XCTAssertTrue(signedOut.isGuest)
        XCTAssertFalse(signedIn.isGuest)
    }

    // MARK: - Explore: the saved invite code opens Join by itself only for a member

    func testStoredCodeAutoOpens_OnlyForAMemberOnTheRootWithNothingElseOpening() {
        let code = "NC7K2PQ9XA"
        func decide(
            stored: String? = code, isGuest: Bool = false, hasSheet: Bool = false, hasScreenOnTop: Bool = false,
            intent: NavigationIntent? = nil, decided: Bool = false
        ) -> String? {
            MyCommunitiesView.joinCodeToOpenOnAppear(
                storedCode: stored, isGuest: isGuest, hasSheet: hasSheet, hasScreenOnTop: hasScreenOnTop,
                pendingIntent: intent, alreadyDecided: decided
            )
        }

        XCTAssertEqual(decide(), code)
        // A join link's intent is the root, so Join opens.
        XCTAssertEqual(decide(intent: .joinCommunity), code)
        // An intent for another tab leaves Explore's rule alone.
        XCTAssertEqual(decide(intent: .dashboard), code)

        // A guest never gets Join by itself.
        XCTAssertNil(decide(isGuest: true))
        // Once per view lifetime, not over a sheet, not with nothing saved.
        XCTAssertNil(decide(decided: true))
        XCTAssertNil(decide(hasSheet: true))
        XCTAssertNil(decide(stored: nil))
        // A screen already pushed (a community admin's push replayed first) wins.
        XCTAssertNil(decide(hasScreenOnTop: true))
        // So does an intent that is about to push one.
        XCTAssertNil(decide(intent: .communityReports(CommunityFixtures.communityA)))
        XCTAssertNil(decide(intent: .pendingMembers(CommunityFixtures.communityA)))
        XCTAssertNil(decide(intent: .communityMembers(CommunityFixtures.communityA)))
    }

    func testStoreChangeAndNextAppearRules_NeverOpenJoinForAGuest() {
        let code = "NC7K2PQ9XA"
        XCTAssertEqual(
            MyCommunitiesView.joinCodeToOpenOnStoreChange(storedCode: code, hasSheet: false, isVisible: true, isGuest: false),
            code
        )
        XCTAssertNil(MyCommunitiesView.joinCodeToOpenOnStoreChange(storedCode: code, hasSheet: false, isVisible: true, isGuest: true))
        XCTAssertTrue(MyCommunitiesView.opensJoinOnNextAppear(storedCode: code, isVisible: false, screenPushedOnTop: false, isGuest: false))
        XCTAssertFalse(MyCommunitiesView.opensJoinOnNextAppear(storedCode: code, isVisible: false, screenPushedOnTop: false, isGuest: true))
    }

    func testRowDetail_JoinsThePolicyChipTextAndTheMemberCount() {
        let count = String(format: "community_member_count_other".localized, 12)
        let detail = MyCommunitiesView.rowDetail(joinPolicy: CommunityJoinPolicy.approve.rawValue, memberCount: 12)
        XCTAssertTrue(detail.contains(CommunityJoinPolicy.approve.chipText))
        XCTAssertTrue(detail.hasSuffix(count))
        XCTAssertTrue(detail.contains("·"))

        let one = MyCommunitiesView.rowDetail(joinPolicy: CommunityJoinPolicy.open.rawValue, memberCount: 1)
        XCTAssertTrue(one.hasSuffix(String(format: "community_member_count_one".localized, 1)))

        // A policy this build does not know shows the count alone, with no stray separator.
        XCTAssertEqual(MyCommunitiesView.rowDetail(joinPolicy: "future_policy", memberCount: 12), count)
    }

    // MARK: - Routes on Explore

    func testExploreRoute_CommunityAdminIntentsMapToTheirScreens() {
        let a = CommunityFixtures.communityA
        XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .pendingMembers(a)), .pendingMembers(.community(a, name: nil)))
        XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .communityReports(a)), .communityReports(a))
        XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .communityMembers(a)), .communityMembers(a))
        XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .myCommunities), .root)
        XCTAssertEqual(MyCommunitiesView.exploreRoute(for: .joinCommunity), .root)
        XCTAssertNil(MyCommunitiesView.exploreRoute(for: .pendingUsers)); XCTAssertNil(MyCommunitiesView.exploreRoute(for: .ride(UUID())))
    }
}
