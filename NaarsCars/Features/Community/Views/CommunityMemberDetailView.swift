//
//  CommunityMemberDetailView.swift
//  NaarsCars
//
//  One member of a community, with the actions the caller may take on them
//

import SwiftUI

/// One member, for a community's owners and admins. Pushed from `CommunityMembersView`.
struct CommunityMemberDetailView: View {
    let member: CommunityMember
    @ObservedObject var viewModel: CommunityMembersViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The action waiting for its confirmation alert (every action but Remove, which has a sheet).
    @State private var pendingAction: CommunityMemberAction?
    @State private var showsRemoveSheet = false
    @State private var popsAfterSheet = false
    /// Set before a Remove or Let back in that closes this screen: its toast is then left to the
    /// Members list (shown when it reappears), and the buttons stay off until the screen is gone.
    @State private var isLeaving = false

    init(member: CommunityMember, viewModel: CommunityMembersViewModel) {
        self.member = member
        self.viewModel = viewModel
    }

    /// The row as the list now has it (a role change replaces it), else the row that was opened.
    private var current: CommunityMember {
        viewModel.members.first { $0.id == member.id } ?? member
    }

    private var isActing: Bool { viewModel.actingOnUserId != nil || isLeaving }

    /// Role and ownership toasts show here, where the action happened. While this screen is closing
    /// it shows none: clearing it on the way out would drop the Members list's confirmation.
    private var toastMessage: Binding<String?> {
        Binding(
            get: { isLeaving ? nil : viewModel.toastMessage },
            set: { viewModel.toastMessage = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                header
                if viewModel.access != .notAdmin {
                    details
                }
                actionButtons
            }
            .padding()
        }
        .background(Color.naarsBackground)
        .navigationTitle(current.membersDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            alertTitle,
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            presenting: pendingAction
        ) { action in
            Button("common_cancel".localized, role: .cancel) {}
            Button(Self.label(for: action)) {
                let target = current
                let closesScreen = action == .readmit
                if closesScreen { isLeaving = true }
                Task {
                    let succeeded = await viewModel.perform(action, on: target)
                    if closesScreen {
                        if succeeded { dismiss() } else { isLeaving = false }
                    }
                }
            }
        } message: { action in
            Text(Self.body(for: action))
        }
        .sheet(isPresented: $showsRemoveSheet, onDismiss: {
            if popsAfterSheet { dismiss() }
        }) {
            RemoveMemberSheet(
                memberName: current.membersDisplayName,
                isActing: viewModel.actingOnUserId == member.id || isLeaving,
                errorMessage: $viewModel.actionErrorMessage
            ) { note in
                let target = current
                isLeaving = true
                let succeeded = await viewModel.perform(.remove, on: target, reason: note)
                if succeeded {
                    popsAfterSheet = true
                    showsRemoveSheet = false
                } else {
                    isLeaving = false
                }
            }
        }
        .toast(message: toastMessage)
        .errorBanner(message: $viewModel.actionErrorMessage)
        .accessibilityIdentifier("community.member.detail")
    }

    // MARK: - Sections

    private var header: some View {
        // At accessibility sizes the avatar sits above the text so the name keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Constants.Spacing.md))
        return layout {
            AvatarView(imageUrl: current.avatarUrl, name: current.membersDisplayName, size: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(current.membersDisplayName)
                    .font(.naarsTitle3)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let car = current.car, !car.isEmpty {
                    Label(car, systemImage: "car.fill")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                if current.status == .active, let role = communityMemberRoleText(current.role) {
                    NaarsChip(text: role)
                }
                Text(String(
                    format: "community_member_joined".localized,
                    current.joinedAt.formatted(date: .abbreviated, time: .omitted)
                ))
                .font(.naarsCaption)
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var details: some View {
        let answers: [(String, String)] = [
            ("admin_heard_about_label", current.heardAbout),
            ("admin_join_reason_label", current.joinReason)
        ].compactMap { key, text in
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (key, text)
        }
        let inviter = current.invitedByName.flatMap { $0.isEmpty ? nil : $0 }
        let removalNote = current.status == .removed
            ? current.removalReason.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            : nil
        if !answers.isEmpty || inviter != nil || removalNote != nil {
            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                if let removalNote {
                    Text(String(format: "community_member_removal_note".localized, removalNote))
                        .font(.naarsBody)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let inviter {
                    Text(String(format: "community_pending_invited_by".localized, inviter))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                ForEach(answers, id: \.0) { key, text in
                    VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                        Text(key.localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        Text(text)
                            .font(.naarsBody)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        let actions = viewModel.actions(for: current)
        if !actions.isEmpty {
            VStack(spacing: Constants.Spacing.sm) {
                ForEach(actions, id: \.self) { action in
                    actionButton(action)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: CommunityMemberAction) -> some View {
        let title = Self.label(for: action)
        switch action {
        case .readmit:
            PrimaryButton(
                title: title,
                action: { pendingAction = .readmit },
                isLoading: viewModel.actingOnUserId == member.id,
                isDisabled: isActing
            )
            .accessibilityLabel(title)
            .accessibilityIdentifier(Self.identifier(for: action))
        case .remove:
            SecondaryButton(
                title: title,
                action: { showsRemoveSheet = true },
                isDisabled: isActing,
                isDestructive: true
            )
            .accessibilityLabel(title)
            .accessibilityHint(String(format: "community_member_remove_title".localized, current.membersDisplayName))
            .accessibilityIdentifier(Self.identifier(for: action))
        case .makeAdmin, .makeMember, .transferOwnership:
            SecondaryButton(
                title: title,
                action: { pendingAction = action },
                isDisabled: isActing
            )
            .accessibilityLabel(title)
            .accessibilityIdentifier(Self.identifier(for: action))
        }
    }

    // MARK: - Copy

    private var alertTitle: String {
        guard let pendingAction else { return "" }
        return String(format: Self.titleKey(for: pendingAction).localized, current.membersDisplayName)
    }

    private static func label(for action: CommunityMemberAction) -> String {
        switch action {
        case .remove: return "community_member_action_remove".localized
        case .readmit: return "community_member_action_readmit".localized
        case .makeAdmin: return "community_member_action_make_admin".localized
        case .makeMember: return "community_member_action_make_member".localized
        case .transferOwnership: return "community_member_action_transfer".localized
        }
    }

    private static func titleKey(for action: CommunityMemberAction) -> String {
        switch action {
        case .remove: return "community_member_remove_title"
        case .readmit: return "community_member_readmit_title"
        case .makeAdmin: return "community_member_make_admin_title"
        case .makeMember: return "community_member_make_member_title"
        case .transferOwnership: return "community_member_transfer_title"
        }
    }

    private static func body(for action: CommunityMemberAction) -> String {
        switch action {
        case .remove: return "community_member_remove_body".localized
        case .readmit: return "community_member_readmit_body".localized
        case .makeAdmin: return "community_member_make_admin_body".localized
        case .makeMember: return "community_member_make_member_body".localized
        case .transferOwnership: return "community_member_transfer_body".localized
        }
    }

    private static func identifier(for action: CommunityMemberAction) -> String {
        switch action {
        case .remove: return "community.member.remove"
        case .readmit: return "community.member.readmit"
        case .makeAdmin: return "community.member.makeAdmin"
        case .makeMember: return "community.member.makeMember"
        case .transferOwnership: return "community.member.transfer"
        }
    }
}

// MARK: - Remove sheet

/// Confirms a removal and takes the optional note the removed member sees.
struct RemoveMemberSheet: View {
    let memberName: String
    let isActing: Bool
    @Binding var errorMessage: String?
    let onRemove: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    private let maxLength = Constants.Community.removalNoteMaxLength

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    Text("community_member_remove_body".localized)
                        .font(.naarsBody)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("community_member_remove_note_label".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        TextField("", text: $note, axis: .vertical)
                            .lineLimit(3...8)
                            .font(.naarsBody)
                            .padding(Constants.Spacing.sm)
                            .background(Color.naarsCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.sm, style: .continuous))
                            .disabled(isActing)
                            .accessibilityLabel("community_member_remove_note_label".localized)
                            .accessibilityIdentifier("community.member.removeNote")
                            .onChange(of: note) { _, newValue in
                                if newValue.count > maxLength { note = String(newValue.prefix(maxLength)) }
                            }
                        HStack(alignment: .firstTextBaseline) {
                            Text("community_member_remove_note_footer".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Constants.Spacing.sm)
                            Text("\(note.count)/\(maxLength)")
                                .font(.naarsCaption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }

                    SecondaryButton(
                        title: "community_member_remove_confirm".localized,
                        action: {
                            let text = note
                            Task { await onRemove(text) }
                        },
                        isDisabled: isActing,
                        isDestructive: true
                    )
                    .accessibilityLabel(String(format: "community_member_remove_title".localized, memberName))
                    .accessibilityIdentifier("community.member.removeConfirm")

                    if isActing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(Color.naarsBackground)
            .navigationTitle(String(format: "community_member_remove_title".localized, memberName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) { dismiss() }
                        .disabled(isActing)
                        .accessibilityIdentifier("community.member.removeCancel")
                }
            }
            .errorBanner(message: $errorMessage)
        }
        .interactiveDismissDisabled(isActing)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Owner looking at a member") {
    NavigationStack {
        CommunityMemberDetailView(
            member: PreviewCommunityService.sampleActiveMembers[2],
            viewModel: CommunityMembersPreview.viewModel()
        )
    }
}

#Preview("Admin looking at an admin") {
    NavigationStack {
        CommunityMemberDetailView(
            member: PreviewCommunityService.sampleActiveMembers[1],
            viewModel: CommunityMembersPreview.viewModel(role: .admin)
        )
    }
}

#Preview("Removed member") {
    NavigationStack {
        CommunityMemberDetailView(
            member: PreviewCommunityService.sampleRemovedMembers[0],
            viewModel: CommunityMembersPreview.viewModel(list: .removed)
        )
    }
}

#Preview("Remove sheet") {
    RemoveMemberSheet(memberName: "Dana Rivera", isActing: false, errorMessage: .constant(nil)) { _ in }
}
#endif
