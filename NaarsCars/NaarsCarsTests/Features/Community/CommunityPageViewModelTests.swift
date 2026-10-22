//
//  CommunityPageViewModelTests.swift
//  NaarsCarsTests
//
//  The community page: a member or pending row decides the mode without a request, anyone else
//  reads the listed preview (and a refusal or a failure has its own state), the visitor action
//  follows the join policy, and a member sees the community's open requests and recent posts
//  from the local store
//

import XCTest
@testable import NaarsCars

@MainActor
final class CommunityPageViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let me = CommunityFixtures.userA
    private let poster = UUID(uuidString: "5B000000-0000-4000-8000-000000000001")!
    private let otherPoster = UUID(uuidString: "5B000000-0000-4000-8000-000000000002")!
    /// A Wednesday at noon, UTC; the calendar below is fixed to UTC so the day maths is exact.
    private let now = Date(timeIntervalSince1970: 1_792_065_600)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CommunityPageViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A context restored for `userA` and loaded with the given rows (an active A and B by default).
    private func makeContext(
        _ rows: [CommunityMembership]? = nil
    ) async -> (CommunityContext, StubCommunityService) {
        let stub = StubCommunityService(result: .success(rows ?? [
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", memberCount: 5),
            CommunityFixtures.membership(CommunityFixtures.communityB, name: "Community B", memberCount: 9)
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: me)
        await context.refreshMemberships()
        return (context, stub)
    }

    private func makeViewModel(
        _ communityId: UUID,
        stub: StubCommunityService,
        context: CommunityContext,
        isGuest: Bool = false
    ) -> CommunityPageViewModel {
        CommunityPageViewModel(
            communityId: communityId,
            service: stub,
            communityContext: context,
            isGuest: { isGuest }
        )
    }

    private func ride(
        _ index: Int,
        community: UUID? = CommunityFixtures.communityA,
        userId: UUID? = nil,
        status: String = "open",
        claimedBy: UUID? = nil,
        hidden: Bool = false,
        date: Date? = nil,
        time: String = "09:30:00",
        posterName: String? = "Sam Neighbor"
    ) -> SDRide {
        SDRide(
            id: UUID(uuidString: String(format: "0E000000-0000-4000-8000-%012d", index))!,
            userId: userId ?? poster,
            date: date ?? now,
            time: time,
            pickup: "Pickup",
            destination: "Destination",
            status: status,
            claimedBy: claimedBy,
            hiddenAt: hidden ? now : nil,
            posterName: posterName,
            communityId: community
        )
    }

    private func favor(
        _ index: Int,
        community: UUID? = CommunityFixtures.communityA,
        userId: UUID? = nil,
        status: String = "open",
        claimedBy: UUID? = nil,
        date: Date? = nil,
        time: String? = nil
    ) -> SDFavor {
        SDFavor(
            id: UUID(uuidString: String(format: "0F000000-0000-4000-8000-%012d", index))!,
            userId: userId ?? poster,
            title: "Favor \(index)",
            location: "Location",
            date: date ?? now,
            time: time,
            status: status,
            claimedBy: claimedBy,
            posterName: "Sam Neighbor",
            communityId: community
        )
    }

    private func post(
        _ index: Int,
        community: UUID? = CommunityFixtures.communityA,
        userId: UUID? = nil,
        hidden: Bool = false,
        createdAt: Date? = nil
    ) -> SDTownHallPost {
        SDTownHallPost(
            id: UUID(uuidString: String(format: "0D000000-0000-4000-8000-%012d", index))!,
            userId: userId ?? poster,
            content: "Post \(index)",
            hiddenAt: hidden ? now : nil,
            createdAt: createdAt ?? now.addingTimeInterval(TimeInterval(index)),
            authorName: "Sam Neighbor",
            commentCount: index,
            communityId: community
        )
    }

    // MARK: - Mode

    func testMemberMode_ComesFromTheActiveMembershipWithoutARequest() async throws {
        let (context, stub) = await makeContext()
        let vm = makeViewModel(CommunityFixtures.communityA, stub: stub, context: context)
        let row = try XCTUnwrap(context.membership(for: CommunityFixtures.communityA))

        await vm.load()

        XCTAssertEqual(vm.mode, .member(row))
        XCTAssertTrue(stub.fetchCommunityPreviewCalls.isEmpty)
        XCTAssertNil(vm.visitorAction)
    }

    func testPendingMode_ComesFromThePendingMembershipAndWaits() async throws {
        let (context, stub) = await makeContext([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A"),
            CommunityFixtures.membership(CommunityFixtures.communityC, name: "Community C", status: .pending)
        ])
        let vm = makeViewModel(CommunityFixtures.communityC, stub: stub, context: context)
        let row = try XCTUnwrap(context.membership(for: CommunityFixtures.communityC))

        await vm.load()

        XCTAssertEqual(vm.mode, .pending(row))
        XCTAssertEqual(vm.visitorAction, .waitingForApproval)
        XCTAssertTrue(stub.fetchCommunityPreviewCalls.isEmpty)
    }

    func testVisitorMode_LoadsThePreviewForANonMember() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        let preview = CommunityFixtures.preview(id, name: "Test Public A")
        stub.fetchCommunityPreviewResult = .success(preview)
        let vm = makeViewModel(id, stub: stub, context: context)

        await vm.load()

        XCTAssertEqual(stub.fetchCommunityPreviewCalls, [id])
        XCTAssertEqual(vm.mode, .visitor(preview))
        XCTAssertEqual(
            vm.visitorAction,
            .askToJoin(PublicCommunity(id: id, name: "Test Public A", description: nil, joinPolicy: "approve", isDefault: false))
        )
        XCTAssertEqual(vm.policy, .approve)
    }

    func testVisitor_InviteOnlyOffersTheInviteCode() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        stub.fetchCommunityPreviewResult = .success(CommunityFixtures.preview(id, name: "Invite Only", policy: "invite"))
        let vm = makeViewModel(id, stub: stub, context: context)

        await vm.load()

        XCTAssertEqual(vm.visitorAction, .enterInviteCode)
        XCTAssertEqual(vm.policy, .invite)
    }

    func testVisitor_OpenAndUnknownPoliciesAskToJoin() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        let vm = makeViewModel(id, stub: stub, context: context)

        // The server decides what an open or unknown policy needs; the page offers the request.
        for policy in ["open", "some_future_policy"] {
            stub.fetchCommunityPreviewResult = .success(CommunityFixtures.preview(id, name: "Test Public A", policy: policy))
            await vm.load()
            XCTAssertEqual(
                vm.visitorAction,
                .askToJoin(PublicCommunity(id: id, name: "Test Public A", description: nil, joinPolicy: policy, isDefault: false)),
                policy
            )
        }
    }

    func testGuest_VisitorActionIsSignUp() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        stub.fetchCommunityPreviewResult = .success(CommunityFixtures.preview(id, name: "Test Public A", policy: "invite"))
        let vm = makeViewModel(id, stub: stub, context: context, isGuest: true)

        await vm.load()

        XCTAssertEqual(vm.visitorAction, .signUp)
    }

    func testVisitor_NotListedRefusalShowsUnavailable() async {
        let (context, stub) = await makeContext()
        stub.fetchCommunityPreviewResult = .failure(CommunityRPCError(code: .notListed))
        let vm = makeViewModel(CommunityFixtures.communityC, stub: stub, context: context)

        await vm.load()

        XCTAssertEqual(vm.mode, .unavailable)
        XCTAssertNil(vm.visitorAction)
    }

    func testVisitor_NetworkFailureShowsFailedAndRetryLoads() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        let preview = CommunityFixtures.preview(id, name: "Test Public A")
        stub.fetchCommunityPreviewResult = .failure(URLError(.notConnectedToInternet))
        let vm = makeViewModel(id, stub: stub, context: context)

        await vm.load()
        XCTAssertEqual(vm.mode, .failed)

        stub.fetchCommunityPreviewResult = .success(preview)
        await vm.load()

        XCTAssertEqual(vm.mode, .visitor(preview))
        XCTAssertEqual(stub.fetchCommunityPreviewCalls, [id, id])
    }

    func testVisitor_CancelledLoadIsNotAFailure() async {
        let (context, stub) = await makeContext()
        stub.fetchCommunityPreviewResult = .failure(CancellationError())
        let vm = makeViewModel(CommunityFixtures.communityC, stub: stub, context: context)

        await vm.load()

        XCTAssertEqual(vm.mode, .loading)
        XCTAssertNil(vm.bannerMessage)
    }

    func testVisitor_RefreshFailureKeepsThePreviewAndShowsABanner() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        let preview = CommunityFixtures.preview(id, name: "Test Public A")
        stub.fetchCommunityPreviewResult = .success(preview)
        let vm = makeViewModel(id, stub: stub, context: context)
        await vm.load()

        stub.fetchCommunityPreviewResult = .failure(URLError(.notConnectedToInternet))
        await vm.load()

        XCTAssertEqual(vm.mode, .visitor(preview))
        XCTAssertNotNil(vm.bannerMessage)
    }

    func testLoadIfStale_ReadsAVisitorsPreviewOnceWithinTheStalenessWindow() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        stub.fetchCommunityPreviewResult = .success(CommunityFixtures.preview(id, name: "Test Public A"))
        let vm = makeViewModel(id, stub: stub, context: context)

        await vm.loadIfStale()
        await vm.loadIfStale()
        XCTAssertEqual(stub.fetchCommunityPreviewCalls, [id])

        // An explicit reload (pull-to-refresh, Retry) always reads.
        await vm.load()
        XCTAssertEqual(stub.fetchCommunityPreviewCalls, [id, id])
    }

    func testLoadIfStale_LoadsAgainOnceThePersonHasAMembership() async {
        let id = CommunityFixtures.communityC
        let stub = StubCommunityService(result: .success([]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: me)
        await context.refreshMemberships()
        stub.fetchCommunityPreviewResult = .success(CommunityFixtures.preview(id, name: "Test Public A"))
        let vm = makeViewModel(id, stub: stub, context: context)
        await vm.loadIfStale()
        XCTAssertEqual(vm.mode, .visitor(CommunityFixtures.preview(id, name: "Test Public A")))

        // A join request that was recorded: the row decides the mode, no matter how fresh the preview.
        stub.result = .success([CommunityFixtures.membership(id, name: "Test Public A", status: .pending)])
        await context.refreshMemberships()
        await vm.loadIfStale()

        guard case .pending = vm.mode else { return XCTFail("expected pending mode, got \(vm.mode)") }
        XCTAssertEqual(stub.fetchCommunityPreviewCalls, [id])
    }

    func testLeavingAListedCommunity_ReloadsAsVisitor() async throws {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityA
        let row = try XCTUnwrap(context.membership(for: id))
        let preview = CommunityFixtures.preview(id, name: "Community A")
        stub.fetchCommunityPreviewResult = .success(preview)
        let vm = makeViewModel(id, stub: stub, context: context)
        await vm.load()
        XCTAssertEqual(vm.mode, .member(row))

        await context.forgetMembership(id)
        await vm.load()

        XCTAssertEqual(vm.mode, .visitor(preview))
        XCTAssertEqual(stub.fetchCommunityPreviewCalls, [id])
    }

    // MARK: - Pull-to-refresh

    func testRefresh_PendingPageBecomesAMemberPageAfterApproval() async throws {
        let id = CommunityFixtures.communityC
        let (context, stub) = await makeContext([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A"),
            CommunityFixtures.membership(id, name: "Community C", status: .pending)
        ])
        let vm = makeViewModel(id, stub: stub, context: context)
        await vm.load()
        guard case .pending = vm.mode else { return XCTFail("expected pending mode, got \(vm.mode)") }
        let fetchesBefore = stub.fetchCount

        // An admin approved the request while the page was open.
        stub.result = .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A"),
            CommunityFixtures.membership(id, name: "Community C")
        ])
        await vm.refresh()

        let row = try XCTUnwrap(context.membership(for: id))
        XCTAssertEqual(row.status, .active)
        XCTAssertEqual(vm.mode, .member(row))
        XCTAssertEqual(stub.fetchCount, fetchesBefore + 1)
        XCTAssertTrue(stub.fetchCommunityPreviewCalls.isEmpty)
    }

    func testRefresh_MemberPageReadsNoMemberships() async throws {
        let (context, stub) = await makeContext()
        let vm = makeViewModel(CommunityFixtures.communityA, stub: stub, context: context)
        await vm.load()
        let fetchesBefore = stub.fetchCount

        await vm.refresh()

        XCTAssertEqual(vm.mode, .member(try XCTUnwrap(context.membership(for: CommunityFixtures.communityA))))
        XCTAssertEqual(stub.fetchCount, fetchesBefore)
    }

    func testRefresh_GuestReadsNoMemberships() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityC
        stub.fetchCommunityPreviewResult = .success(CommunityFixtures.preview(id, name: "Test Public A"))
        let vm = makeViewModel(id, stub: stub, context: context, isGuest: true)
        let fetchesBefore = stub.fetchCount

        await vm.refresh()

        XCTAssertEqual(stub.fetchCount, fetchesBefore)
        XCTAssertEqual(stub.fetchCommunityPreviewCalls, [id])
    }

    // MARK: - Town Hall posts (member mode)

    func testTownHallPosts_ShownFromTheStoreOnlyForTheTownHallCommunity() async {
        let (context, stub) = await makeContext()
        XCTAssertEqual(context.communityTabId, CommunityFixtures.communityA)
        let townHallPage = makeViewModel(CommunityFixtures.communityA, stub: stub, context: context)
        let otherPage = makeViewModel(CommunityFixtures.communityB, stub: stub, context: context)
        await townHallPage.load()
        await otherPage.load()

        // The store holds only the Town Hall community's posts: B's page must not read as "no posts".
        XCTAssertTrue(townHallPage.showsLocalTownHallPosts)
        XCTAssertFalse(otherPage.showsLocalTownHallPosts)
    }

    func testOpenTownHall_SwitchesTheTownHallCommunityThenSelectsTheTab() async {
        let (context, stub) = await makeContext()
        var tabIdWhenSelected: UUID?
        var selected: [NavigationCoordinator.Tab] = []
        let vm = CommunityPageViewModel(
            communityId: CommunityFixtures.communityB,
            service: stub,
            communityContext: context,
            isGuest: { false },
            selectTab: { tab in
                tabIdWhenSelected = context.communityTabId
                selected.append(tab)
            }
        )
        await vm.load()

        vm.openTownHall()

        XCTAssertEqual(context.communityTabId, CommunityFixtures.communityB)
        XCTAssertEqual(tabIdWhenSelected, CommunityFixtures.communityB)
        XCTAssertEqual(selected, [.townHall])
        XCTAssertTrue(vm.showsLocalTownHallPosts)
    }

    func testOpenTownHall_DoesNothingWithoutAnActiveMembership() async {
        let id = CommunityFixtures.communityC
        let (context, stub) = await makeContext([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A"),
            CommunityFixtures.membership(id, name: "Community C", status: .pending)
        ])
        var selected: [NavigationCoordinator.Tab] = []
        let vm = CommunityPageViewModel(
            communityId: id, service: stub, communityContext: context, isGuest: { false },
            selectTab: { selected.append($0) }
        )

        vm.openTownHall()

        XCTAssertEqual(context.communityTabId, CommunityFixtures.communityA)
        XCTAssertTrue(selected.isEmpty)
    }

    func testLeavingAHiddenCommunity_ShowsUnavailable() async {
        let (context, stub) = await makeContext()
        let id = CommunityFixtures.communityA
        stub.fetchCommunityPreviewResult = .failure(CommunityRPCError(code: .notListed))
        let vm = makeViewModel(id, stub: stub, context: context)
        await vm.load()
        guard case .member = vm.mode else { return XCTFail("expected member mode, got \(vm.mode)") }

        await context.forgetMembership(id)
        await vm.load()

        XCTAssertEqual(vm.mode, .unavailable)
    }

    // MARK: - Local store (member mode)

    func testLocalRequests_KeepsOnlyTheCommunitysOpenUnclaimedVisibleRequestsFromToday() {
        let yesterday = now.addingTimeInterval(-86_400)
        let rides = [
            ride(1),
            ride(2, community: CommunityFixtures.communityB),
            ride(3, community: nil),
            ride(4, status: "confirmed", claimedBy: otherPoster),
            ride(5, status: "completed"),
            ride(6, hidden: true),
            ride(7, date: yesterday)
        ]
        let favors = [
            favor(1),
            favor(2, community: CommunityFixtures.communityB),
            favor(3, claimedBy: otherPoster),
            favor(4, date: yesterday)
        ]

        let rows = CommunityPageViewModel.localRequests(
            rides: rides, favors: favors, communityId: CommunityFixtures.communityA,
            now: now, calendar: calendar, isBlocked: { _ in false }
        )

        XCTAssertEqual(rows.map(\.id), [rides[0].id, favors[0].id])
        XCTAssertEqual(rows.map(\.isRide), [true, false])
    }

    func testLocalRequests_CarryThePosterAndTheFavorTitleAndNeverAnAddress() throws {
        let rows = CommunityPageViewModel.localRequests(
            rides: [ride(1, posterName: nil)], favors: [favor(1)], communityId: CommunityFixtures.communityA,
            now: now, calendar: calendar, isBlocked: { _ in false }
        )

        let rideRow = try XCTUnwrap(rows.first { $0.isRide })
        let favorRow = try XCTUnwrap(rows.first { !$0.isRide })
        XCTAssertNil(rideRow.title)
        XCTAssertEqual(rideRow.posterId, poster)
        XCTAssertEqual(rideRow.posterName, "community_former_member".localized)
        XCTAssertEqual(rideRow.time, "09:30:00")
        XCTAssertEqual(favorRow.title, "Favor 1")
        XCTAssertEqual(favorRow.posterName, "Sam Neighbor")
        XCTAssertNil(favorRow.time)
    }

    func testLocalRequests_AreOrderedByDayThenTimeAndCappedAtTheListLimit() {
        let tomorrow = now.addingTimeInterval(86_400)
        // Nine rides today (07:00 to 15:00), a favor today with no time, and tomorrow's earliest ride.
        let todays = (1...9).map { ride($0, time: String(format: "%02d:00:00", $0 + 6)) }
        let timeless = favor(1)
        let tomorrows = ride(10, date: tomorrow, time: "05:00:00")

        let rows = CommunityPageViewModel.localRequests(
            rides: [tomorrows] + todays.reversed(), favors: [timeless], communityId: CommunityFixtures.communityA,
            now: now, calendar: calendar, isBlocked: { _ in false }
        )

        // Today by time, the request without a time last on its day; tomorrow's is past the cap.
        XCTAssertEqual(Constants.Community.pagePreviewRequests, 10)
        XCTAssertEqual(rows.map(\.id), todays.map(\.id) + [timeless.id])
    }

    func testLocalRequests_LeaveOutBlockedPosters() {
        let rows = CommunityPageViewModel.localRequests(
            rides: [ride(1), ride(2, userId: otherPoster)], favors: [], communityId: CommunityFixtures.communityA,
            now: now, calendar: calendar, isBlocked: { $0 == self.otherPoster }
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.posterId, poster)
    }

    func testLocalPosts_AreTheNewestVisiblePostsOfThatCommunity() {
        let posts = [
            post(1),
            post(2, community: CommunityFixtures.communityB),
            post(3, hidden: true),
            post(4, userId: otherPoster),
            post(5),
            post(6), post(7), post(8), post(9)
        ]

        let rows = CommunityPageViewModel.localPosts(
            posts, communityId: CommunityFixtures.communityA, isBlocked: { $0 == self.otherPoster }
        )

        XCTAssertEqual(rows.count, Constants.Community.pagePreviewPosts)
        XCTAssertEqual(rows.map(\.id), [posts[8].id, posts[7].id, posts[6].id, posts[5].id, posts[4].id])
        XCTAssertEqual(rows.first?.commentCount, 9)
        XCTAssertEqual(rows.first?.authorName, "Sam Neighbor")
    }

    // MARK: - Day and time

    func testWhenText_ReadsTheDayAndOnlyAddsATimeWhenThereIsOne() {
        let day = now
        XCTAssertEqual(
            CommunityPageViewModel.whenText(date: day, time: nil),
            DateFormatters.monthDayFormatter.string(from: day)
        )
        let withTime = CommunityPageViewModel.whenText(date: day, time: "09:30:00")
        XCTAssertTrue(withTime.contains("30"), withTime)
        XCTAssertNotEqual(withTime, DateFormatters.monthDayFormatter.string(from: day))
    }
}
