//
//  CommunityMergeView.swift
//  NaarsCars
//
//  Merge under Manage: the open proposal (accept, decline or withdraw) or, with none, the form
//  that proposes one. Always pushed from the admin panel (no NavigationStack of its own).
//

import SwiftUI

struct CommunityMergeView: View {
    @StateObject private var viewModel: CommunityMergeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showProposeAlert = false
    @State private var showAcceptAlert = false
    @State private var showDeclineAlert = false
    /// Receives "<merged> and <survivor> are now one community." when this community was the one
    /// merged away: the screen and the panel close, so the presenter shows it.
    private let onMergedAway: (_ confirmation: String) -> Void

    init(
        communityId: UUID,
        communityName: String,
        onMergedAway: @escaping (_ confirmation: String) -> Void = { _ in },
        viewModel: @autoclosure @escaping () -> CommunityMergeViewModel? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel()
            ?? CommunityMergeViewModel(communityId: communityId, communityName: communityName))
        self.onMergedAway = onMergedAway
    }

    var body: some View {
        Group {
            switch viewModel.mode {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notOwner:
                EmptyStateView(
                    icon: "lock.fill",
                    title: "community_merge_title".localized,
                    message: "community_merge_owner_only".localized
                )
            case .failed:
                ErrorView(error: "common_load_error".localized) {
                    Task { await viewModel.load() }
                }
            case .proposal(let proposal):
                proposalContent(proposal)
            case .compose:
                composeForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.naarsBackground)
        .navigationTitle("community_merge_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.mode == .loading else { return }
            await viewModel.load()
            // A query typed before the load finished (or a preview's) runs once the form shows.
            if !viewModel.query.isEmpty { await viewModel.searchTargets() }
        }
        .task(id: viewModel.query) {
            guard viewModel.mode == .compose else { return }
            try? await Task.sleep(for: Constants.Community.searchDebounce)
            guard !Task.isCancelled else { return }
            await viewModel.searchTargets()
        }
        .onChange(of: viewModel.didMergeAway) { _, mergedAway in
            guard mergedAway else { return }
            onMergedAway(viewModel.completion ?? "")
            dismiss()
        }
        .alert(
            viewModel.proposeConfirmation?.title ?? "",
            isPresented: $showProposeAlert,
            presenting: viewModel.proposeConfirmation
        ) { _ in
            Button("community_merge_propose".localized, role: .destructive) {
                Task { await viewModel.propose() }
            }
            Button("common_cancel".localized, role: .cancel) {}
        } message: { confirmation in
            Text(Self.alertMessage(confirmation))
        }
        .alert(
            viewModel.acceptConfirmation?.title ?? "",
            isPresented: $showAcceptAlert,
            presenting: viewModel.acceptConfirmation
        ) { _ in
            Button("community_merge_accept".localized, role: .destructive) {
                Task { await viewModel.accept() }
            }
            Button("common_cancel".localized, role: .cancel) {}
        } message: { confirmation in
            Text(Self.alertMessage(confirmation))
        }
        .alert("community_merge_decline".localized, isPresented: $showDeclineAlert) {
            Button("community_merge_decline".localized, role: .destructive) {
                Task { await viewModel.decline() }
            }
            Button("common_cancel".localized, role: .cancel) {}
        } message: {
            if case .proposal(let proposal) = viewModel.mode {
                Text(String(format: "community_merge_direction".localized, proposal.merged.name, proposal.survivor.name))
            }
        }
        .toast(message: $viewModel.completion)
        .errorBanner(message: $viewModel.errorMessage)
    }

    private static func alertMessage(_ confirmation: MergeConfirmation) -> String {
        [confirmation.message, confirmation.extraWarning].compactMap { $0 }.joined(separator: "\n\n")
    }

    // MARK: - Proposal

    private func proposalContent(_ proposal: CommunityMergeProposal) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                proposalCard(proposal)

                if proposal.direction == .incoming {
                    PrimaryButton(
                        title: "community_merge_accept".localized,
                        action: { showAcceptAlert = true },
                        isLoading: viewModel.isWorking,
                        isDisabled: viewModel.isWorking
                    )
                    .accessibilityIdentifier("community.merge.accept")
                    .accessibilityLabel("community_merge_accept".localized)

                    SecondaryButton(
                        title: "community_merge_decline".localized,
                        action: { showDeclineAlert = true },
                        isDisabled: viewModel.isWorking
                    )
                    .accessibilityIdentifier("community.merge.decline")
                    .accessibilityLabel("community_merge_decline".localized)
                } else {
                    SecondaryButton(
                        title: "community_merge_withdraw".localized,
                        action: { Task { await viewModel.withdraw() } },
                        isDisabled: viewModel.isWorking,
                        isDestructive: true
                    )
                    .accessibilityIdentifier("community.merge.withdraw")
                    .accessibilityLabel("community_merge_withdraw".localized)
                }
            }
            .padding()
        }
        .refreshable { await viewModel.load() }
    }

    private func proposalCard(_ proposal: CommunityMergeProposal) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text(proposal.direction == .incoming
                 ? String(format: "community_merge_incoming_title".localized, proposal.from.name)
                 : String(format: "community_merge_outgoing_title".localized, proposal.to.name))
                .font(.naarsHeadline)
                .foregroundStyle(Color.naarsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "community_merge_direction".localized, proposal.merged.name, proposal.survivor.name))
                .font(.naarsSubheadline)
                .foregroundStyle(Color.naarsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let policy = CommunityJoinPolicy(rawValue: proposal.survivor.joinPolicy) {
                CommunityPolicyChip(policy: policy)
            }

            if let note = proposal.note, !note.isEmpty {
                Text(note)
                    .font(.naarsBody)
                    .foregroundStyle(Color.naarsTextSecondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(String(format: "community_merge_expires".localized,
                        proposal.expiresAt.formatted(date: .abbreviated, time: .omitted)))
                .font(.naarsCaption)
                .foregroundStyle(Color.naarsTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Compose

    private var composeForm: some View {
        Form {
            Section {
                TextField("community_merge_search_placeholder".localized, text: $viewModel.query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await viewModel.searchTargets() } }
                    .accessibilityLabel("community_merge_search_placeholder".localized)
                    .accessibilityIdentifier("community.merge.search")
            } footer: {
                Text("community_merge_search_footer".localized)
            }

            if viewModel.isSearching && viewModel.targets.isEmpty {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else if !viewModel.targets.isEmpty {
                Section {
                    ForEach(viewModel.targets) { target in
                        targetRow(target)
                    }
                }
            }

            if viewModel.selectedTarget != nil {
                Section {
                    directionRow(keepsThis: true)
                    directionRow(keepsThis: false)
                }

                Section {
                    TextField("community_merge_note_label".localized, text: $viewModel.note, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: viewModel.note) { _, text in
                            if text.count > Constants.Community.mergeNoteMaxLength {
                                viewModel.note = String(text.prefix(Constants.Community.mergeNoteMaxLength))
                            }
                        }
                        .accessibilityLabel("community_merge_note_label".localized)
                        .accessibilityIdentifier("community.merge.note")
                }

                Section {
                    PrimaryButton(
                        title: "community_merge_propose".localized,
                        action: { showProposeAlert = true },
                        isLoading: viewModel.isWorking,
                        isDisabled: !viewModel.canPropose
                    )
                    .accessibilityIdentifier("community.merge.propose")
                    .accessibilityLabel("community_merge_propose".localized)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func targetRow(_ target: MergeTarget) -> some View {
        let isSelected = viewModel.selectedTarget?.id == target.id
        let members = String(
            format: (target.memberCount == 1 ? "community_member_count_one" : "community_member_count_other").localized,
            target.memberCount
        )
        let visibility = target.isPublic ? "community_access_listed".localized : "community_access_hidden".localized
        return Button {
            viewModel.selectedTarget = target
        } label: {
            HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(target.name)
                        .font(.naarsHeadline)
                        .foregroundStyle(Color.naarsTextPrimary)
                        .multilineTextAlignment(.leading)
                    if let policy = CommunityJoinPolicy(rawValue: target.joinPolicy) {
                        CommunityPolicyChip(policy: policy)
                    }
                    Text([members, visibility, target.areaName].compactMap { $0 }.joined(separator: " · "))
                        .font(.naarsCaption)
                        .foregroundStyle(Color.naarsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Constants.Spacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.naarsPrimary : Color.naarsTextSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(target.name)
        .accessibilityValue([CommunityJoinPolicy(rawValue: target.joinPolicy)?.chipText, members, visibility]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("community.merge.target")
    }

    private func directionRow(keepsThis: Bool) -> some View {
        let isSelected = viewModel.keepsThisCommunity == keepsThis
        let label = viewModel.directionLabel(keepsThis: keepsThis) ?? ""
        return Button {
            viewModel.keepsThisCommunity = keepsThis
        } label: {
            HStack(spacing: Constants.Spacing.sm) {
                Text(label)
                    .font(.naarsBody)
                    .foregroundStyle(Color.naarsTextPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Constants.Spacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.naarsPrimary : Color.naarsTextSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("community.merge.direction")
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum CommunityMergePreview {
    /// Ballard with the caller in `role`; `direction` sets an open proposal the service answers.
    static func viewModel(
        role: CommunityRole = .owner,
        direction: CommunityMergeProposal.Direction? = nil,
        withResults: Bool = false
    ) -> CommunityMergeViewModel {
        let service = PreviewCommunityService()
        let ballard = PreviewCommunityService.membership(name: "Ballard Neighbors", role: role, memberCount: 12)
        if let direction {
            service.mergeProposal = proposal(direction, thisId: ballard.communityId)
        }
        let context = CommunityContext(
            service: service,
            defaults: UserDefaults(suiteName: "preview")!,
            platformAdminProvider: { false }
        )
        context.debugSetMemberships([ballard])
        let vm = CommunityMergeViewModel(
            communityId: ballard.communityId,
            communityName: ballard.name,
            service: service,
            communityContext: context,
            refreshDashboard: { _ in }
        )
        if withResults {
            vm.query = "Fr"
            vm.selectedTarget = PreviewCommunityService.sampleMergeTargets[0]
        }
        return vm
    }

    static func proposal(_ direction: CommunityMergeProposal.Direction, thisId: UUID) -> CommunityMergeProposal {
        let other = CommunityMergeProposal.Side(id: UUID(), name: "Fremont Porch Club", joinPolicy: "open", memberCount: 31)
        let this = CommunityMergeProposal.Side(id: thisId, name: "Ballard Neighbors", joinPolicy: "approve", memberCount: 12)
        return CommunityMergeProposal(
            id: UUID(),
            direction: direction,
            from: direction == .incoming ? other : this,
            to: direction == .incoming ? this : other,
            survivorId: thisId,
            note: "Most of our members ride with yours already.",
            proposedByName: "Sam Neighbor",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(7 * 86_400)
        )
    }
}

#Preview("Compose with results") {
    let vm = CommunityMergePreview.viewModel(withResults: true)
    return NavigationStack {
        CommunityMergeView(communityId: vm.communityId, communityName: "Ballard Neighbors", viewModel: vm)
    }
}

#Preview("Incoming") {
    let vm = CommunityMergePreview.viewModel(direction: .incoming)
    return NavigationStack {
        CommunityMergeView(communityId: vm.communityId, communityName: "Ballard Neighbors", viewModel: vm)
    }
}

#Preview("Outgoing") {
    let vm = CommunityMergePreview.viewModel(direction: .outgoing)
    return NavigationStack {
        CommunityMergeView(communityId: vm.communityId, communityName: "Ballard Neighbors", viewModel: vm)
    }
}

#Preview("Not owner") {
    let vm = CommunityMergePreview.viewModel(role: .admin)
    return NavigationStack {
        CommunityMergeView(communityId: vm.communityId, communityName: "Ballard Neighbors", viewModel: vm)
    }
}
#endif
