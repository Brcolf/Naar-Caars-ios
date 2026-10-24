//
//  CommunityAccessView.swift
//  NaarsCars
//
//  The owner's access screen: listed or hidden, how people join, and the service area. Always
//  pushed from community Settings (no NavigationStack of its own).
//

import SwiftUI

struct CommunityAccessView: View {
    let communityId: UUID
    @StateObject private var viewModel: CommunityAccessViewModel
    @State private var viewedCommunityId: UUID?

    init(
        communityId: UUID,
        viewModel: @autoclosure @escaping () -> CommunityAccessViewModel? = nil
    ) {
        self.communityId = communityId
        _viewModel = StateObject(wrappedValue: viewModel() ?? CommunityAccessViewModel(communityId: communityId))
    }

    var body: some View {
        Group {
            if viewModel.settings != nil {
                form
            } else if let loadError = viewModel.loadError {
                ErrorView(error: loadError) {
                    Task { await viewModel.load() }
                }
            } else {
                skeleton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.naarsBackground)
        .navigationTitle("community_access_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isOwner && viewModel.settings != nil {
                ToolbarItem(placement: .confirmationAction) {
                    CommunityAccessSaveButton(viewModel: viewModel, areaDraft: viewModel.areaDraft)
                }
            }
        }
        .task {
            // A screen that already holds its settings (a preview, a return to it) keeps them.
            if viewModel.settings == nil { await viewModel.load() }
        }
        .navigationDestination(item: $viewedCommunityId) { id in
            CommunityPageView(communityId: id)
        }
        .toast(message: $viewModel.toastMessage)
        .errorBanner(message: $viewModel.errorMessage)
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                Toggle("community_access_listed".localized, isOn: $viewModel.isListed)
                    .disabled(!viewModel.isOwner || viewModel.isDefaultCommunity || viewModel.isSaving)
                    .accessibilityIdentifier("community.access.listed")
            } footer: {
                Text(listedFooter)
            }

            Section {
                ForEach(viewModel.policyChoices, id: \.self) { policy in
                    policyRow(policy)
                }
            } footer: {
                Text(viewModel.isOwner
                     ? "community_access_members_told".localized
                     : "community_access_owner_only".localized)
                    .accessibilityIdentifier(viewModel.isOwner ? "community.access.membersTold" : "community.access.ownerOnly")
            }

            if viewModel.isListed {
                areaSections
                if viewModel.needsNearbyCheck {
                    NearbyCheckSection(model: viewModel.areaDraft, onView: { viewedCommunityId = $0 })
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var listedFooter: String {
        if viewModel.isDefaultCommunity { return "community_access_default_footer".localized }
        return viewModel.isListed
            ? "community_create_listed_footer".localized
            : "community_create_hidden_footer".localized
    }

    // MARK: - Join policy

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
        .disabled(!viewModel.isOwner || viewModel.isSaving)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(policy.chipText)
        .accessibilityValue(policy.ruleSentence)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("community.access.policy.\(policy.rawValue)")
    }

    // MARK: - Service area

    @ViewBuilder
    private var areaSections: some View {
        if let stored = viewModel.settings?.area, !viewModel.isChangingArea {
            Section {
                ServiceAreaMap(area: stored)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("community_access_area_header".localized)
            }
            if viewModel.isOwner {
                Section {
                    Button("community_access_change_area".localized) {
                        viewModel.isChangingArea = true
                    }
                    .disabled(viewModel.isSaving)
                    .accessibilityIdentifier("community.access.changeArea")
                }
            }
        } else {
            ServiceAreaPicker(model: viewModel.areaDraft)
            if viewModel.hasStoredArea {
                Section {
                    Button("common_cancel".localized) {
                        viewModel.isChangingArea = false
                    }
                    .accessibilityIdentifier("community.access.keepArea")
                }
            }
        }
    }

    // MARK: - States

    private var skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                        SkeletonRectangle(width: 120, height: 14)
                        SkeletonRectangle(height: 20)
                    }
                    .cardStyle()
                }
            }
            .padding()
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}

/// Save. A subview observing both objects: the screen's view model, and the area draft, whose
/// changes (a resolved place, a finished nearby check, a reason) do not redraw a view that
/// observes only the view model.
private struct CommunityAccessSaveButton: View {
    @ObservedObject var viewModel: CommunityAccessViewModel
    @ObservedObject var areaDraft: ServiceAreaDraftModel

    var body: some View {
        if viewModel.isSaving {
            ProgressView()
        } else {
            Button("community_settings_save".localized) {
                Task { await viewModel.save() }
            }
            .disabled(!viewModel.canSave)
            .accessibilityLabel("community_settings_save".localized)
            .accessibilityIdentifier("community.access.save")
        }
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum CommunityAccessPreview {
    /// Ballard with the caller as owner. `listed` previews a listed community with a stored area;
    /// otherwise a hidden one with none.
    static func viewModel(listed: Bool, isDefault: Bool = false) -> CommunityAccessViewModel {
        let service = PreviewCommunityService()
        let ballard = PreviewCommunityService.sampleMemberships[1]
        let sample = PreviewCommunityService.sampleSettings
        service.settings = CommunitySettings(
            id: ballard.communityId,
            name: isDefault ? "Naar's Cars Seattle" : sample.name,
            description: sample.description,
            joinPolicy: sample.joinPolicy,
            membersCanInvite: sample.membersCanInvite,
            isPublic: listed,
            isDefault: isDefault,
            timezone: sample.timezone,
            area: listed ? ServiceArea(
                name: "Ballard",
                center: GeoPoint(latitude: 47.668, longitude: -122.384),
                radiusMiles: 2
            ) : nil
        )
        service.overlappingCommunities = Array(PreviewCommunityService.sampleSearchResults.prefix(2))
        let context = CommunityContext(
            service: service,
            defaults: UserDefaults(suiteName: "preview")!,
            platformAdminProvider: { false }
        )
        let row = CommunityMembership(
            communityId: ballard.communityId, name: service.settings.name, description: ballard.description,
            role: .owner, status: .active, isPrimary: ballard.isPrimary, joinPolicy: ballard.joinPolicy,
            isPublic: listed, isDefault: isDefault, membersCanInvite: ballard.membersCanInvite,
            timezone: ballard.timezone, canInvite: ballard.canInvite, memberCount: ballard.memberCount,
            pendingCount: ballard.pendingCount, notificationsMuted: ballard.notificationsMuted,
            mutedUntil: ballard.mutedUntil, joinedAt: ballard.joinedAt, activatedAt: ballard.activatedAt
        )
        context.debugSetMemberships([row])
        return CommunityAccessViewModel(
            communityId: ballard.communityId,
            adminService: service,
            service: service,
            geocoder: PreviewPlaceGeocoder(),
            communityContext: context
        )
    }
}

#Preview("Listed owner") {
    let vm = CommunityAccessPreview.viewModel(listed: true)
    return NavigationStack {
        CommunityAccessView(communityId: vm.communityId, viewModel: vm)
    }
}

#Preview("Hidden to listed, with overlaps") {
    let vm = CommunityAccessPreview.viewModel(listed: false)
    Task {
        await vm.load()
        vm.isListed = true
        vm.areaDraft.placeQuery = "Seattle"
        await vm.areaDraft.resolvePlace()
        await vm.areaDraft.checkNearby()
    }
    return NavigationStack {
        CommunityAccessView(communityId: vm.communityId, viewModel: vm)
    }
}
#endif
