//
//  CommunitySettingsView.swift
//  NaarsCars
//
//  One community's name, description, who joins, who invites, and archive
//

import SwiftUI

/// Community settings. No NavigationStack: always pushed (Admin panel).
struct CommunitySettingsView: View {
    let communityId: UUID
    /// Called once after an archive, with the confirmation text ("<name> was archived.") for the
    /// presenter to show: this screen dismisses itself right away, so its own toast cannot.
    private let onArchived: (_ confirmation: String) -> Void
    @StateObject private var viewModel: CommunitySettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showArchiveAlert = false

    init(
        communityId: UUID,
        onArchived: @escaping (_ confirmation: String) -> Void = { _ in },
        viewModel: @autoclosure @escaping () -> CommunitySettingsViewModel? = nil
    ) {
        self.communityId = communityId
        self.onArchived = onArchived
        _viewModel = StateObject(wrappedValue: viewModel() ?? CommunitySettingsViewModel(communityId: communityId))
    }

    var body: some View {
        Group {
            switch viewModel.access {
            case .notAdmin:
                notAdminState
            case .checking, .allowed:
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.naarsBackground)
        .navigationTitle("community_settings_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.access == .allowed && viewModel.canEdit {
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("community_settings_save".localized) {
                            Task { await viewModel.save() }
                        }
                        .disabled(!viewModel.canSave)
                        .accessibilityLabel("community_settings_save".localized)
                        .accessibilityIdentifier("community.settings.save")
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.didArchive) { _, archived in
            guard archived else { return }
            onArchived(viewModel.archiveConfirmation ?? "")
            dismiss()
        }
        .alert(
            String(format: "community_settings_archive_title".localized, viewModel.settings?.name ?? ""),
            isPresented: $showArchiveAlert
        ) {
            Button("community_settings_archive".localized, role: .destructive) {
                Task { await viewModel.archive() }
            }
            .accessibilityIdentifier("community.settings.archive.confirm")
            Button("common_cancel".localized, role: .cancel) {}
        } message: {
            Text("community_settings_archive_body".localized)
        }
        .toast(message: $viewModel.toastMessage)
        .errorBanner(message: $viewModel.errorMessage)
    }

    // MARK: - Form

    private var isBusy: Bool { viewModel.isSaving || viewModel.isArchiving || viewModel.didArchive }

    private var form: some View {
        Form {
            Section {
                if viewModel.canEdit {
                    TextField("community_settings_name".localized, text: $viewModel.name)
                        .disabled(isBusy)
                        .accessibilityLabel("community_settings_name".localized)
                        .accessibilityIdentifier("community.settings.name")
                } else {
                    readOnlyValue(
                        viewModel.name,
                        label: "community_settings_name".localized,
                        identifier: "community.settings.name"
                    )
                }
            } header: {
                Text("community_settings_name".localized)
            } footer: {
                Text("community_create_name_length".localized
                     + "  \(trimmedNameCount)/\(Constants.Community.nameLength.upperBound)")
            }

            Section {
                if viewModel.canEdit {
                    TextField("community_settings_description".localized, text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(isBusy)
                        .accessibilityLabel("community_settings_description".localized)
                        .accessibilityIdentifier("community.settings.description")
                } else {
                    readOnlyValue(
                        viewModel.description,
                        label: "community_settings_description".localized,
                        identifier: "community.settings.description"
                    )
                }
            } header: {
                Text("community_settings_description".localized)
            } footer: {
                Text("community_create_description_length".localized
                     + "  \(trimmedDescriptionCount)/\(Constants.Community.descriptionMaxLength)")
            }

            Section {
                Toggle("community_settings_requires_approval".localized, isOn: $viewModel.requiresApproval)
                    .disabled(!viewModel.canEdit || isBusy)
                    .accessibilityIdentifier("community.settings.requiresApproval")
            } footer: {
                Text("community_settings_requires_approval_footer".localized)
            }

            Section {
                Toggle("community_settings_members_can_invite".localized, isOn: $viewModel.membersCanInvite)
                    .disabled(!viewModel.canEdit || isBusy)
                    .accessibilityIdentifier("community.settings.membersCanInvite")
            } footer: {
                VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                    Text("community_settings_members_can_invite_footer".localized)
                    if !viewModel.canEdit {
                        Text("community_settings_owner_only".localized)
                            .accessibilityIdentifier("community.settings.ownerOnly")
                    }
                }
            }

            Section {
                if viewModel.canEdit {
                    TimeZonePicker(selectedTimezone: $viewModel.timezone)
                        .disabled(isBusy)
                        .accessibilityLabel("community_settings_timezone".localized)
                        .accessibilityIdentifier("community.settings.timezone")
                } else {
                    readOnlyValue(
                        TimeZonePicker.displayName(forIdentifier: viewModel.timezone),
                        label: "community_settings_timezone".localized,
                        identifier: "community.settings.timezone"
                    )
                }
            } header: {
                Text("community_settings_timezone".localized)
            } footer: {
                Text("community_settings_timezone_footer".localized)
            }

            if viewModel.canArchive {
                Section {
                    Button(role: .destructive) {
                        showArchiveAlert = true
                    } label: {
                        HStack {
                            Label("community_settings_archive".localized, systemImage: "archivebox")
                            if viewModel.isArchiving {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isBusy)
                    .accessibilityLabel("community_settings_archive".localized)
                    .accessibilityIdentifier("community.settings.archive")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }

    /// A value the caller cannot change (an admin who is not an owner): the section header is the
    /// title (secondary), the value is plain primary text on the screen's ground instead of a white
    /// field, so nothing on the row suggests it can be edited (a gray value in a white row read as
    /// an empty field's placeholder).
    private func readOnlyValue(_ value: String, label: String, identifier: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return Text(trimmed.isEmpty ? "—".localized : trimmed)
            .font(.naarsBody)
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.naarsBackground)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(trimmed.isEmpty ? "—".localized : trimmed)
            .accessibilityIdentifier(identifier)
    }

    private var trimmedNameCount: Int {
        viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var trimmedDescriptionCount: Int {
        viewModel.description.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    // MARK: - States

    private var notAdminState: some View {
        VStack(spacing: Constants.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("community_pending_not_admin".localized)
                .font(.naarsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("community.settings.notAdmin")
    }

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

// MARK: - Previews

#if DEBUG
@MainActor
enum CommunitySettingsPreview {
    /// Ballard with the caller in `role`; `isDefault` previews the default community (no Archive).
    static func viewModel(role: CommunityRole = .owner, isDefault: Bool = false) -> CommunitySettingsViewModel {
        let service = PreviewCommunityService()
        let ballard = PreviewCommunityService.sampleMemberships[1]
        let sample = PreviewCommunityService.sampleSettings
        service.settings = CommunitySettings(
            id: ballard.communityId,
            name: isDefault ? "Naar's Cars Seattle" : sample.name,
            description: sample.description,
            joinPolicy: sample.joinPolicy,
            membersCanInvite: sample.membersCanInvite,
            isPublic: isDefault,
            isDefault: isDefault,
            timezone: sample.timezone
        )
        let context = CommunityContext(
            service: service,
            defaults: UserDefaults(suiteName: "preview")!,
            platformAdminProvider: { false }
        )
        let row = CommunityMembership(
            communityId: ballard.communityId, name: service.settings.name, description: ballard.description,
            role: role, status: .active, isPrimary: ballard.isPrimary, joinPolicy: ballard.joinPolicy,
            isPublic: ballard.isPublic, isDefault: isDefault, membersCanInvite: ballard.membersCanInvite,
            timezone: ballard.timezone, canInvite: ballard.canInvite, memberCount: ballard.memberCount,
            pendingCount: ballard.pendingCount, notificationsMuted: ballard.notificationsMuted,
            mutedUntil: ballard.mutedUntil, joinedAt: ballard.joinedAt, activatedAt: ballard.activatedAt
        )
        context.debugSetMemberships([row])
        return CommunitySettingsViewModel(
            communityId: ballard.communityId,
            adminService: service,
            communityContext: context,
            refreshDashboard: { _ in }
        )
    }
}

#Preview("Owner") {
    let vm = CommunitySettingsPreview.viewModel()
    return NavigationStack {
        CommunitySettingsView(communityId: vm.communityId, viewModel: vm)
    }
}

#Preview("Admin, read only") {
    let vm = CommunitySettingsPreview.viewModel(role: .admin)
    return NavigationStack {
        CommunitySettingsView(communityId: vm.communityId, viewModel: vm)
    }
}

#Preview("Default community") {
    let vm = CommunitySettingsPreview.viewModel(isDefault: true)
    return NavigationStack {
        CommunitySettingsView(communityId: vm.communityId, viewModel: vm)
    }
}
#endif
