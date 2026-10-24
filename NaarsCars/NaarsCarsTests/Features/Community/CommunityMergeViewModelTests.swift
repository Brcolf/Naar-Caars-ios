//
//  CommunityMergeViewModelTests.swift
//  NaarsCarsTests
//
//  Merge under Manage: only the owner, the open proposal shown, a search for a target, a proposal
//  with its survivor and note, accept (the one "mergedCommunity" refresh), a proposal that closed
//  meanwhile, decline and withdraw, and the confirmation text
//

import XCTest
@testable import NaarsCars

@MainActor
final class CommunityMergeViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let fremont = CommunityFixtures.fremontPorchClub
    private let harbor = CommunityFixtures.harborRiders

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CommunityMergeViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A context for `userA`, loaded with Fremont Porch Club in `role`. The same stub answers the
    /// memberships and the merge calls.
    private func makeContext(role: CommunityRole) async -> (CommunityContext, StubCommunityService) {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(fremont, name: "Fremont Porch Club", role: role, joinPolicy: "approve")
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        return (context, stub)
    }

    private func makeViewModel(
        context: CommunityContext,
        stub: StubCommunityService,
        triggers: ((String) -> Void)? = nil
    ) -> CommunityMergeViewModel {
        CommunityMergeViewModel(
            communityId: fremont,
            communityName: "Fremont Porch Club",
            service: stub,
            communityContext: context,
            refreshDashboard: { triggers?($0) }
        )
    }

    private var harborTarget: MergeTarget {
        MergeTarget(id: harbor, name: "Harbor Riders", joinPolicy: "invite", isPublic: false, memberCount: 14, areaName: nil)
    }

    // MARK: - Load

    func testLoad_NonOwnerIsNotOwnerWithoutACall() async {
        let (context, stub) = await makeContext(role: .admin)
        let vm = makeViewModel(context: context, stub: stub)

        await vm.load()

        XCTAssertEqual(vm.mode, .notOwner)
        XCTAssertTrue(stub.fetchMergeProposalCalls.isEmpty)
        await vm.searchTargets()
        XCTAssertTrue(stub.searchMergeTargetsCalls.isEmpty)
    }

    func testLoad_IncomingProposalShowsIt() async {
        let (context, stub) = await makeContext(role: .owner)
        let proposal = CommunityFixtures.mergeProposal(direction: .incoming)
        stub.fetchMergeProposalResult = .success(proposal)
        let vm = makeViewModel(context: context, stub: stub)

        await vm.load()

        XCTAssertEqual(vm.mode, .proposal(proposal))
        XCTAssertEqual(stub.fetchMergeProposalCalls, [fremont])
        // Harbor Riders is folded into Fremont Porch Club.
        XCTAssertEqual(
            vm.acceptConfirmation?.title,
            String(format: "community_merge_confirm_title".localized, "Harbor Riders", "Fremont Porch Club")
        )
    }

    // MARK: - Compose

    func testCompose_SearchSendsQueryAndThisCommunity() async {
        let (context, stub) = await makeContext(role: .owner)
        stub.searchMergeTargetsResult = .success([harborTarget])
        let vm = makeViewModel(context: context, stub: stub)
        await vm.load()
        XCTAssertEqual(vm.mode, .compose)

        vm.query = "H"
        await vm.searchTargets()
        XCTAssertTrue(stub.searchMergeTargetsCalls.isEmpty, "a query under the minimum is not sent")
        XCTAssertTrue(vm.targets.isEmpty)

        vm.query = "  Harbor "
        await vm.searchTargets()

        XCTAssertEqual(stub.searchMergeTargetsCalls.count, 1)
        XCTAssertEqual(stub.searchMergeTargetsCalls.first?.communityId, fremont)
        XCTAssertEqual(stub.searchMergeTargetsCalls.first?.query, "Harbor")
        XCTAssertEqual(vm.targets, [harborTarget])
    }

    func testPropose_SendsSurvivorAndNote() async {
        let (context, stub) = await makeContext(role: .owner)
        let vm = makeViewModel(context: context, stub: stub)
        await vm.load()
        vm.selectedTarget = harborTarget
        vm.keepsThisCommunity = false
        vm.note = "  One place to ask. \n"

        // Fremont is folded into Harbor Riders, which asks people to wait for an invite.
        XCTAssertEqual(
            vm.proposeConfirmation?.title,
            String(format: "community_merge_confirm_title".localized, "Fremont Porch Club", "Harbor Riders")
        )

        let outgoing = CommunityFixtures.mergeProposal(direction: .outgoing)
        stub.fetchMergeProposalResult = .success(outgoing)
        let sent = await vm.propose()

        XCTAssertTrue(sent)
        XCTAssertEqual(stub.proposeMergeCalls.count, 1)
        let call = stub.proposeMergeCalls[0]
        XCTAssertEqual(call.communityId, fremont)
        XCTAssertEqual(call.otherId, harbor)
        XCTAssertEqual(call.survivorId, harbor)
        XCTAssertEqual(call.note, "One place to ask.")
        XCTAssertEqual(vm.completion, String(format: "community_merge_proposed_toast".localized, "Harbor Riders"))
        XCTAssertEqual(vm.mode, .proposal(outgoing), "the screen reloads into the outgoing proposal")
    }

    // MARK: - Accept

    func testAccept_RefreshesDashboardWithMergedCommunityTrigger() async {
        let (context, stub) = await makeContext(role: .owner)
        stub.fetchMergeProposalResult = .success(CommunityFixtures.mergeProposal(direction: .incoming))
        var triggers: [String] = []
        let vm = makeViewModel(context: context, stub: stub, triggers: { triggers.append($0) })
        await vm.load()
        let membershipFetches = stub.fetchCount
        stub.respondToMergeResult = .success(CommunityMergeOutcome(survivorId: fremont, mergedId: harbor))
        stub.fetchMergeProposalResult = .success(nil)

        let accepted = await vm.accept()

        XCTAssertTrue(accepted)
        XCTAssertEqual(stub.respondToMergeCalls.count, 1)
        XCTAssertEqual(stub.respondToMergeCalls.first?.accept, true)
        XCTAssertEqual(triggers, ["mergedCommunity"])
        XCTAssertEqual(stub.fetchCount, membershipFetches + 1)
        XCTAssertEqual(
            vm.completion,
            String(format: "community_merge_done_toast".localized, "Harbor Riders", "Fremont Porch Club")
        )
        XCTAssertFalse(vm.didMergeAway, "Fremont survives")
        XCTAssertEqual(vm.mode, .compose)

        // Fremont is the one folded away this time: the panel closes.
        // The memberships refresh drops the archived community and the panel pops this screen in
        // that update, so the close must already be signalled when the refreshes start.
        var mergedAwayAtRefresh: Bool?
        var vm2: CommunityMergeViewModel!
        vm2 = makeViewModel(context: context, stub: stub, triggers: {
            triggers.append($0)
            mergedAwayAtRefresh = vm2.didMergeAway
        })
        stub.fetchMergeProposalResult = .success(CommunityFixtures.mergeProposal(direction: .incoming, survivorIsFrom: true))
        await vm2.load()
        stub.respondToMergeResult = .success(CommunityMergeOutcome(survivorId: harbor, mergedId: fremont))

        let accepted2 = await vm2.accept()

        XCTAssertTrue(accepted2)
        XCTAssertTrue(vm2.didMergeAway)
        XCTAssertEqual(mergedAwayAtRefresh, true, "didMergeAway is set before the refreshes")
        XCTAssertEqual(
            vm2.completion,
            String(format: "community_merge_done_toast".localized, "Fremont Porch Club", "Harbor Riders")
        )
        XCTAssertEqual(triggers, ["mergedCommunity", "mergedCommunity"])
    }

    func testAccept_ClosedProposalReloadsAndShowsMessage() async {
        let (context, stub) = await makeContext(role: .owner)
        stub.fetchMergeProposalResult = .success(CommunityFixtures.mergeProposal(direction: .incoming))
        var triggers: [String] = []
        let vm = makeViewModel(context: context, stub: stub, triggers: { triggers.append($0) })
        await vm.load()
        // Withdrawn meanwhile.
        stub.respondToMergeResult = .failure(CommunityRPCError(code: .proposalClosed))
        stub.fetchMergeProposalResult = .success(nil)

        let accepted = await vm.accept()

        XCTAssertFalse(accepted)
        XCTAssertEqual(vm.errorMessage, "community_error_proposal_closed".localized)
        XCTAssertEqual(stub.fetchMergeProposalCalls.count, 2, "the screen reloads")
        XCTAssertEqual(vm.mode, .compose)
        XCTAssertTrue(triggers.isEmpty)
        XCTAssertNil(vm.completion)
        XCTAssertFalse(vm.isWorking)
    }

    // MARK: - Cancellation

    /// A cancelled Supabase call throws `URLError(.cancelled)`: typing again cancels the search in
    /// flight, and a cancelled pull-to-refresh cancels the load. Neither is a failure.
    func testCancelledSearchAndLoad_AreNotFailures() async {
        let (context, stub) = await makeContext(role: .owner)
        let vm = makeViewModel(context: context, stub: stub)
        await vm.load()
        XCTAssertEqual(vm.mode, .compose)

        stub.searchMergeTargetsResult = .failure(URLError(.cancelled))
        vm.query = "Harbor"
        await vm.searchTargets()
        XCTAssertNil(vm.errorMessage)

        stub.searchMergeTargetsResult = .failure(CancellationError())
        await vm.searchTargets()
        XCTAssertNil(vm.errorMessage)

        let incoming = CommunityFixtures.mergeProposal(direction: .incoming)
        stub.fetchMergeProposalResult = .success(incoming)
        await vm.load()
        stub.fetchMergeProposalResult = .failure(URLError(.cancelled))
        await vm.load()
        XCTAssertEqual(vm.mode, .proposal(incoming), "the proposal card stays")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Confirmation

    func testConfirmation_ExtraWarningOnlyWhenOnePolicyIsOpen() {
        let closed = CommunityMergeViewModel.confirmation(
            mergedName: "Harbor Riders", survivorName: "Fremont Porch Club",
            survivorPolicy: .approve, otherPolicy: .invite
        )
        XCTAssertNil(closed.extraWarning)
        XCTAssertTrue(closed.message.contains(CommunityJoinPolicy.approve.chipText))
        XCTAssertEqual(
            closed.title,
            String(format: "community_merge_confirm_title".localized, "Harbor Riders", "Fremont Porch Club")
        )

        let oneOpen = CommunityMergeViewModel.confirmation(
            mergedName: "Harbor Riders", survivorName: "Fremont Porch Club",
            survivorPolicy: .open, otherPolicy: .approve
        )
        XCTAssertEqual(oneOpen.extraWarning, "community_merge_open_warning".localized)

        let bothOpen = CommunityMergeViewModel.confirmation(
            mergedName: "Harbor Riders", survivorName: "Fremont Porch Club",
            survivorPolicy: .open, otherPolicy: .open
        )
        XCTAssertNil(bothOpen.extraWarning)
    }

    // MARK: - Decline and withdraw

    func testDeclineAndWithdraw_ReturnToCompose() async {
        let (context, stub) = await makeContext(role: .owner)
        let incoming = CommunityFixtures.mergeProposal(direction: .incoming)
        stub.fetchMergeProposalResult = .success(incoming)
        let vm = makeViewModel(context: context, stub: stub)
        await vm.load()
        stub.fetchMergeProposalResult = .success(nil)

        let declined = await vm.decline()

        XCTAssertTrue(declined)
        XCTAssertEqual(stub.respondToMergeCalls.last?.accept, false)
        XCTAssertEqual(stub.respondToMergeCalls.last?.proposalId, incoming.id)
        XCTAssertEqual(vm.mode, .compose)
        XCTAssertEqual(vm.completion, "community_merge_declined_toast".localized)

        let outgoing = CommunityFixtures.mergeProposal(direction: .outgoing)
        stub.fetchMergeProposalResult = .success(outgoing)
        await vm.load()
        XCTAssertEqual(vm.mode, .proposal(outgoing))
        stub.fetchMergeProposalResult = .success(nil)

        let withdrawn = await vm.withdraw()

        XCTAssertTrue(withdrawn)
        XCTAssertEqual(stub.withdrawMergeCalls, [outgoing.id])
        XCTAssertEqual(vm.mode, .compose)
        XCTAssertEqual(vm.completion, "community_merge_withdrawn_toast".localized)
    }
}
