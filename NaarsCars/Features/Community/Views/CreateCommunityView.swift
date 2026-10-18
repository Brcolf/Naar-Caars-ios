//
//  CreateCommunityView.swift
//  NaarsCars
//
//  Create a community, then open its invite code
//

import SwiftUI

struct CreateCommunityView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CreateCommunityViewModel
    @State private var createdId: UUID?
    @State private var createdName = ""

    private let service: any CommunityServiceProtocol
    private let onCreated: (UUID) -> Void

    @MainActor init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        viewModel: @autoclosure @escaping @MainActor () -> CreateCommunityViewModel = CreateCommunityViewModel(),
        onCreated: @escaping (UUID) -> Void
    ) {
        self.service = service
        self.onCreated = onCreated
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Toggle("community_create_approval_toggle".localized, isOn: $viewModel.requiresApproval)
                        .accessibilityIdentifier("community.create.approval")
                } footer: {
                    Text("community_create_approval_footer".localized)
                }

                if viewModel.showsGuestToggle {
                    Section {
                        Toggle("community_create_guests_toggle".localized, isOn: $viewModel.allowGuests)
                            .accessibilityIdentifier("community.create.guests")
                    } footer: {
                        Text("community_create_guests_footer".localized)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.naarsBackground)
            .navigationTitle("community_create_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) { dismiss() }
                        .disabled(viewModel.isSubmitting)
                        .accessibilityIdentifier("community.create.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button("community_create_submit".localized) { submit() }
                            .disabled(!viewModel.canSubmit)
                            .accessibilityIdentifier("community.create.submit")
                    }
                }
            }
            .errorBanner(message: $viewModel.errorMessage)
            .interactiveDismissDisabled(viewModel.isSubmitting)
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

#if DEBUG
#Preview("Member") {
    let service = PreviewCommunityService()
    return CreateCommunityView(
        service: service,
        viewModel: CreateCommunityViewModel(service: service, adminService: service, isPlatformAdmin: false),
        onCreated: { _ in }
    )
}

#Preview("Platform admin") {
    let service = PreviewCommunityService()
    return CreateCommunityView(
        service: service,
        viewModel: CreateCommunityViewModel(service: service, adminService: service, isPlatformAdmin: true),
        onCreated: { _ in }
    )
}
#endif
