//
//  CreateCommunityView.swift
//  NaarsCars
//
//  Start a community in steps (basics, who can join, service area, nearby check), then open its
//  invite code
//

import SwiftUI

struct CreateCommunityView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CreateCommunityViewModel
    @State private var createdId: UUID?
    @State private var createdName = ""
    /// A community from the nearby check, opened inside this sheet's stack.
    @State private var viewedCommunityId: UUID?

    private let service: any CommunityServiceProtocol
    private let onCreated: (UUID) -> Void
    private let onRequestHigherLimit: (() -> Void)?

    @MainActor init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        viewModel: @autoclosure @escaping @MainActor () -> CreateCommunityViewModel = CreateCommunityViewModel(),
        onCreated: @escaping (UUID) -> Void,
        onRequestHigherLimit: (() -> Void)? = nil
    ) {
        self.service = service
        self.onCreated = onCreated
        self.onRequestHigherLimit = onRequestHigherLimit
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmptyView()
                } header: {
                    Text(viewModel.stepLine)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("community.create.stepLine")
                }

                stepContent
            }
            // Each step is its own form: a step change starts at the top.
            .id(viewModel.step)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.naarsBackground)
            .navigationTitle("community_create_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) { dismiss() }
                        .disabled(viewModel.isSubmitting)
                        .accessibilityIdentifier("community.create.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Constants.Spacing.sm) {
                    if let onRequestHigherLimit, let refusal = viewModel.lastRefusal, refusal.code == .ownedLimit,
                       OwnedLimitRequestViewModel.canRequestMore(currentMax: refusal.maxOwned ?? 0) {
                        SecondaryButton(title: "community_limit_request_button".localized) {
                            dismiss()
                            onRequestHigherLimit()
                        }
                        .accessibilityIdentifier("community.create.requestLimit")
                    }
                    CreateCommunityStepBar(
                        viewModel: viewModel,
                        areaDraft: viewModel.areaDraft,
                        onCreate: submit
                    )
                }
                .padding(.horizontal, Constants.Spacing.md)
                .padding(.vertical, Constants.Spacing.sm)
                .background(Color.naarsBackground)
            }
            .errorBanner(message: $viewModel.errorMessage)
            .interactiveDismissDisabled(viewModel.isSubmitting)
            .navigationDestination(item: $viewedCommunityId) { communityId in
                CommunityPageView(communityId: communityId)
            }
            .navigationDestination(item: $createdId) { communityId in
                // The creator is the community's owner, so the invite opens as an admin with a code
                // even though the memberships have not refreshed yet.
                CommunityInviteContent(
                    communityId: communityId,
                    communityName: createdName,
                    isAdmin: true,
                    service: service,
                    onDone: { dismiss() }
                )
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .basics:
            basicsSections
        case .access:
            accessSections
        case .area:
            ServiceAreaPicker(model: viewModel.areaDraft)
        case .nearby:
            NearbyCheckSection(model: viewModel.areaDraft, onView: { viewedCommunityId = $0 })
        }
    }

    // MARK: - Step 1: basics

    @ViewBuilder
    private var basicsSections: some View {
        Section {
            TextField("community_create_name_placeholder".localized, text: $viewModel.name)
                .accessibilityLabel("community_create_name_label".localized)
                .accessibilityIdentifier("community.create.name")
        } header: {
            Text("community_create_name_label".localized)
        } footer: {
            Text("community_create_name_length".localized + "  \(trimmedNameCount)/\(Constants.Community.nameLength.upperBound)")
        }

        Section {
            TextField(
                "community_create_description_label".localized,
                text: $viewModel.description,
                axis: .vertical
            )
            .lineLimit(3...6)
            .accessibilityLabel("community_create_description_label".localized)
            .accessibilityIdentifier("community.create.description")
        } footer: {
            Text("community_create_description_length".localized + "  \(viewModel.description.count)/\(Constants.Community.descriptionMaxLength)")
        }
    }

    // MARK: - Step 2: who can join

    @ViewBuilder
    private var accessSections: some View {
        Section {
            Toggle("community_create_listed_toggle".localized, isOn: $viewModel.isListed)
                .accessibilityIdentifier("community.create.listed")
        } footer: {
            Text(viewModel.isListed
                 ? "community_create_listed_footer".localized
                 : "community_create_hidden_footer".localized)
        }

        Section {
            ForEach(viewModel.policyChoices, id: \.self) { policy in
                policyRow(policy)
            }
        }
    }

    private func policyRow(_ policy: CommunityJoinPolicy) -> some View {
        let isSelected = viewModel.joinPolicy == policy
        return Button {
            viewModel.joinPolicy = policy
        } label: {
            HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    CommunityPolicyChip(policy: policy)
                    Text(policy.ruleSentence)
                        .font(.naarsSubheadline)
                        .foregroundStyle(Color.naarsTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(policy.chipText)
        .accessibilityValue(policy.ruleSentence)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("community.create.policy.\(policy.rawValue)")
    }

    private var trimmedNameCount: Int {
        viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private func submit() {
        let nameForInvite = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            guard let community = await viewModel.submit() else { return }
            createdName = nameForInvite
            onCreated(community.communityId)
            createdId = community.communityId
        }
    }
}

/// Back and Next (Create on the final step). It observes the area draft as well as the view model,
/// so a resolved place or a typed reason enables the button (a nested `ObservableObject` does not
/// redraw a view that observes only the outer one).
private struct CreateCommunityStepBar: View {
    @ObservedObject var viewModel: CreateCommunityViewModel
    @ObservedObject var areaDraft: ServiceAreaDraftModel
    let onCreate: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Constants.Spacing.xs) {
            if viewModel.needsReasonToCreate {
                Text("community_create_needs_reason".localized)
                    .font(.naarsFootnote)
                    .foregroundStyle(Color.naarsTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("community.create.needsReason")
            }
            // Stacked at accessibility sizes (Next first), so neither title is cut or broken.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Constants.Spacing.sm) {
                    nextButton
                    backButton
                }
            } else {
                HStack(spacing: Constants.Spacing.sm) {
                    backButton
                    nextButton
                }
            }
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if viewModel.step != .basics {
            SecondaryButton(
                title: "community_create_back".localized,
                action: { viewModel.back() },
                isDisabled: viewModel.isSubmitting || viewModel.isAdvancing
            )
            .accessibilityIdentifier("community.create.back")
        }
    }

    private var nextButton: some View {
        PrimaryButton(
            title: viewModel.isFinalStep ? "community_create_submit".localized : "community_create_next".localized,
            action: {
                if viewModel.isFinalStep {
                    onCreate()
                } else {
                    Task { await viewModel.next() }
                }
            },
            isLoading: viewModel.isSubmitting || viewModel.isAdvancing,
            isDisabled: !viewModel.canAdvance
        )
        .accessibilityHint(viewModel.needsReasonToCreate ? "community_create_needs_reason".localized : "")
        .accessibilityIdentifier(viewModel.isFinalStep ? "community.create.submit" : "community.create.next")
    }
}

#if DEBUG
// MARK: - Previews

private enum CreateCommunityPreviewData {
    /// A view model showing `step` with "Harbor Riders" filled in and, from the area step on, the
    /// sample area; the nearby section runs its check against `overlaps` communities by itself.
    @MainActor
    static func viewModel(
        at step: CreateCommunityStep,
        listed: Bool = true,
        overlaps: Int = 0
    ) -> (CreateCommunityViewModel, PreviewCommunityService) {
        let service = PreviewCommunityService()
        service.overlappingCommunities = Array(PreviewCommunityService.sampleSearchResults.prefix(overlaps))
        let viewModel = CreateCommunityViewModel(service: service, geocoder: PreviewPlaceGeocoder())
        guard step != .basics else { return (viewModel, service) }
        viewModel.name = "Harbor Riders"
        viewModel.isListed = listed
        if step.rawValue >= CreateCommunityStep.area.rawValue {
            viewModel.areaDraft.reset(to: PreviewCommunityService.sampleArea)
        }
        viewModel.debugShowStep(step)
        return (viewModel, service)
    }
}

#Preview("Basics") {
    let (viewModel, service) = CreateCommunityPreviewData.viewModel(at: .basics)
    return CreateCommunityView(service: service, viewModel: viewModel, onCreated: { _ in })
}

#Preview("Who can join, listed") {
    let (viewModel, service) = CreateCommunityPreviewData.viewModel(at: .access)
    return CreateCommunityView(service: service, viewModel: viewModel, onCreated: { _ in })
}

#Preview("Who can join, hidden") {
    let (viewModel, service) = CreateCommunityPreviewData.viewModel(at: .access, listed: false)
    return CreateCommunityView(service: service, viewModel: viewModel, onCreated: { _ in })
}

#Preview("Service area") {
    let (viewModel, service) = CreateCommunityPreviewData.viewModel(at: .area)
    return CreateCommunityView(service: service, viewModel: viewModel, onCreated: { _ in })
}

#Preview("Nearby check, no overlap") {
    let (viewModel, service) = CreateCommunityPreviewData.viewModel(at: .nearby)
    return CreateCommunityView(service: service, viewModel: viewModel, onCreated: { _ in })
}

#Preview("Nearby check, with overlaps") {
    let (viewModel, service) = CreateCommunityPreviewData.viewModel(at: .nearby, overlaps: 2)
    return CreateCommunityView(service: service, viewModel: viewModel, onCreated: { _ in })
}
#endif
