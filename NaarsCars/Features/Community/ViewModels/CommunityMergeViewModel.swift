//
//  CommunityMergeViewModel.swift
//  NaarsCars
//
//  Merge under Manage: the owner finds another community, proposes making the two one, and the
//  other owner accepts or declines; either side withdraws a proposal it sent. The server decides
//  every rule (20261021_0022); this only chooses what to show.
//

internal import Combine
import Foundation

/// The alert shown before a merge is proposed or accepted. Both say it cannot be undone.
struct MergeConfirmation: Equatable {
    let title: String
    let message: String
    /// Set only when exactly one of the two communities is open (who can see whom changes).
    let extraWarning: String?
}

@MainActor
final class CommunityMergeViewModel: ObservableObject {
    enum Mode: Equatable {
        case loading
        case notOwner
        case proposal(CommunityMergeProposal)
        case compose
        case failed
    }

    @Published private(set) var mode: Mode = .loading
    @Published var query = ""
    @Published private(set) var targets: [MergeTarget] = []
    @Published private(set) var isSearching = false
    @Published var selectedTarget: MergeTarget?
    /// True: the other community merges into this one. False: this one merges into the other.
    @Published var keepsThisCommunity = true
    @Published var note = ""
    @Published private(set) var isWorking = false
    /// Shown in the error banner.
    @Published var errorMessage: String?
    /// Shown as a toast; after a merge that folded this community away, handed to the presenter.
    @Published var completion: String?
    /// True once this community was merged into the other one: the screen and the panel close.
    @Published private(set) var didMergeAway = false

    let communityId: UUID

    private let fallbackName: String
    private let service: any CommunityMergeServiceProtocol
    private let communityContext: CommunityContext
    private let refreshDashboard: @MainActor (String) async -> Void
    /// Only the newest load and the newest search write their result.
    private var loadGeneration = 0
    private var searchGeneration = 0

    init(
        communityId: UUID,
        communityName: String,
        service: any CommunityMergeServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        refreshDashboard: @escaping @MainActor (String) async -> Void = {
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0)
        }
    ) {
        self.communityId = communityId
        self.fallbackName = communityName
        self.service = service
        self.communityContext = communityContext ?? .shared
        self.refreshDashboard = refreshDashboard
    }

    // MARK: - Derived

    /// This community's current name (a rename made elsewhere shows).
    var communityName: String {
        communityContext.name(for: communityId) ?? fallbackName
    }

    private var isOwner: Bool {
        guard let row = communityContext.membership(for: communityId), row.status == .active else { return false }
        return row.role == .owner
    }

    private var thisPolicy: CommunityJoinPolicy? {
        communityContext.membership(for: communityId).flatMap { CommunityJoinPolicy(rawValue: $0.joinPolicy) }
    }

    private var trimmedNote: String {
        String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Constants.Community.mergeNoteMaxLength))
    }

    var canPropose: Bool {
        mode == .compose && selectedTarget != nil && !isWorking
    }

    /// "Merge <other> into <this>" (kept) or "Merge <this> into <other>".
    func directionLabel(keepsThis: Bool) -> String? {
        guard let target = selectedTarget else { return nil }
        return keepsThis
            ? String(format: "community_merge_direction".localized, target.name, communityName)
            : String(format: "community_merge_direction".localized, communityName, target.name)
    }

    var proposeConfirmation: MergeConfirmation? {
        guard mode == .compose, let target = selectedTarget else { return nil }
        let targetPolicy = CommunityJoinPolicy(rawValue: target.joinPolicy)
        if keepsThisCommunity {
            return Self.confirmation(
                mergedName: target.name, survivorName: communityName,
                survivorPolicy: thisPolicy, otherPolicy: targetPolicy
            )
        }
        return Self.confirmation(
            mergedName: communityName, survivorName: target.name,
            survivorPolicy: targetPolicy, otherPolicy: thisPolicy
        )
    }

    var acceptConfirmation: MergeConfirmation? {
        guard case .proposal(let proposal) = mode, proposal.direction == .incoming else { return nil }
        return Self.confirmation(
            mergedName: proposal.merged.name,
            survivorName: proposal.survivor.name,
            survivorPolicy: CommunityJoinPolicy(rawValue: proposal.survivor.joinPolicy),
            otherPolicy: CommunityJoinPolicy(rawValue: proposal.merged.joinPolicy)
        )
    }

    /// The text both owners confirm. An unknown survivor policy reads as "Ask to join", the
    /// server's default.
    static func confirmation(
        mergedName: String,
        survivorName: String,
        survivorPolicy: CommunityJoinPolicy?,
        otherPolicy: CommunityJoinPolicy?
    ) -> MergeConfirmation {
        let rules = (survivorPolicy ?? .approve).chipText
        let oneIsOpen = (survivorPolicy == .open) != (otherPolicy == .open)
        return MergeConfirmation(
            title: String(format: "community_merge_confirm_title".localized, mergedName, survivorName),
            message: String(format: "community_merge_confirm_message".localized, mergedName, survivorName, rules),
            extraWarning: oneIsOpen ? "community_merge_open_warning".localized : nil
        )
    }

    // MARK: - Load

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        if communityContext.isAwaitingMemberships {
            await communityContext.refreshMemberships()
        }
        guard isOwner else {
            guard generation == loadGeneration else { return }
            mode = .notOwner
            return
        }
        // A shown proposal or form stays while it reloads; a failed or owner-only screen shows loading.
        if mode == .failed || mode == .notOwner { mode = .loading }
        do {
            let proposal = try await service.fetchMergeProposal(communityId: communityId)
            guard generation == loadGeneration else { return }
            mode = proposal.map { .proposal($0) } ?? .compose
        } catch is CancellationError {
            return
        } catch {
            AppLogger.error("community", "fetchMergeProposal failed: \(error)")
            guard generation == loadGeneration else { return }
            mode = .failed
        }
    }

    // MARK: - Compose

    /// Searches with the current query. A query under the minimum clears the results without a call.
    func searchTargets() async {
        guard mode == .compose else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Constants.Community.searchMaxLength))
        guard text.count >= Constants.Community.searchMinLength else {
            targets = []
            isSearching = false
            return
        }
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            let found = try await service.searchMergeTargets(communityId: communityId, query: text)
            guard generation == searchGeneration else { return }
            targets = found
            if let selected = selectedTarget, !found.contains(where: { $0.id == selected.id }) {
                selectedTarget = nil
            }
        } catch is CancellationError {
            return
        } catch {
            AppLogger.error("community", "searchMergeTargets failed: \(error)")
            guard generation == searchGeneration else { return }
            errorMessage = "common_load_error".localized
        }
    }

    /// Sends the proposal. One at a time; a success reloads into the outgoing proposal.
    @discardableResult
    func propose() async -> Bool {
        guard canPropose, let target = selectedTarget else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        let survivorId = keepsThisCommunity ? communityId : target.id
        let note = trimmedNote
        do {
            _ = try await service.proposeMerge(
                communityId: communityId,
                otherId: target.id,
                survivorId: survivorId,
                note: note.isEmpty ? nil : note
            )
        } catch {
            await handle(error, action: "proposeMerge")
            return false
        }
        HapticManager.success()
        completion = String(format: "community_merge_proposed_toast".localized, target.name)
        resetCompose()
        await load()
        return true
    }

    // MARK: - Respond

    /// Accepts an incoming proposal. A success refreshes the dashboard ("mergedCommunity") and the
    /// memberships; when this community was the one folded away, `didMergeAway` closes the screen.
    @discardableResult
    func accept() async -> Bool {
        guard !isWorking, case .proposal(let proposal) = mode, proposal.direction == .incoming else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            _ = try await service.respondToMerge(proposalId: proposal.id, accept: true)
        } catch {
            await handle(error, action: "respondToMerge")
            return false
        }
        HapticManager.success()
        let mergedAway = proposal.merged.id == communityId
        completion = String(format: "community_merge_done_toast".localized, proposal.merged.name, proposal.survivor.name)
        await refreshDashboard("mergedCommunity")
        await communityContext.refreshMemberships()
        if mergedAway {
            didMergeAway = true
        } else {
            await load()
        }
        return true
    }

    @discardableResult
    func decline() async -> Bool {
        guard !isWorking, case .proposal(let proposal) = mode, proposal.direction == .incoming else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            _ = try await service.respondToMerge(proposalId: proposal.id, accept: false)
        } catch {
            await handle(error, action: "respondToMerge")
            return false
        }
        completion = "community_merge_declined_toast".localized
        await load()
        return true
    }

    @discardableResult
    func withdraw() async -> Bool {
        guard !isWorking, case .proposal(let proposal) = mode else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await service.withdrawMerge(proposalId: proposal.id)
        } catch {
            await handle(error, action: "withdrawMerge")
            return false
        }
        completion = "community_merge_withdrawn_toast".localized
        await load()
        return true
    }

    // MARK: - Private

    private func resetCompose() {
        query = ""
        targets = []
        selectedTarget = nil
        keepsThisCommunity = true
        note = ""
    }

    /// A proposal that closed meanwhile (withdrawn, expired, declined, the other side archived):
    /// its message and a reload. A lost owner role: the message and a reload into "owner only".
    /// `invalid` ("choose another community") has no text of its own and reads as the generic one.
    private func handle(_ error: Error, action: String) async {
        guard let refusal = error as? CommunityRPCError else {
            AppLogger.error("community", "\(action) failed: \(error)")
            errorMessage = "community_error_generic".localized
            return
        }
        switch refusal.code {
        case .proposalClosed:
            errorMessage = refusal.localizedMessage
            await load()
        case .notOwner:
            errorMessage = refusal.localizedMessage
            await communityContext.refreshMemberships()
            await load()
        case .invalid:
            errorMessage = "community_error_generic".localized
        default:
            errorMessage = refusal.localizedMessage
        }
    }
}
