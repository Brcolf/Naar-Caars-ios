//
//  MessageDetailsPopup.swift
//  NaarsCars
//
//  Popup for editing conversation details (title, participants, and group image)
//

import SwiftUI
import PhotosUI
import OSLog

/// Popup for editing conversation details
struct MessageDetailsPopup: View {
    @Environment(\.dismiss) private var dismiss
    
    let conversationId: UUID
    let currentTitle: String?
    let currentGroupImageUrl: String?
    let initialParticipants: [Profile]
    /// The conversation's creator, when the caller has loaded it.
    let createdBy: UUID?
    /// Called after the user has left the group, before the sheet closes.
    let onLeftConversation: (() -> Void)?

    @StateObject private var viewModel: MessageDetailsViewModel
    @State private var editedTitle: String
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    
    // Group image states
    @State private var showImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var groupImage: UIImage?

    // Leave/Remove confirmation
    @State private var showLeaveConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var participantToRemove: Profile?

    // Report / block: the other member of a one-to-one thread (its own section), or a group
    // member picked from that member's row menu
    @State private var userToReport: Profile?
    @State private var userToBlock: Profile?
    @State private var showBlockConfirmation = false
    @State private var toastMessage: String?

    /// Group management (photo, name, add/remove, leave) applies to threads of three or more;
    /// a one-to-one thread shows the participants, the mute control and report / block.
    /// Same rule as `ConversationDetailView.isGroup`.
    private var isGroup: Bool { initialParticipants.count > 2 }

    /// Only the creator's insert passes the participants INSERT policy, so only the creator
    /// is offered Add Participants. `nil` means the caller has not loaded the conversation
    /// yet: the row stays available and a rejected add is explained by the view model.
    private var canAddParticipants: Bool {
        guard let createdBy else { return true }
        return createdBy == AuthService.shared.currentUserId
    }

    /// Someone who can be reported or blocked: another member whose account still exists.
    private func isReportable(_ participant: Profile) -> Bool {
        participant.id != AuthService.shared.currentUserId
            && !participant.name.isEmpty
            && participant.name != "messaging_deleted_user".localized
    }

    /// The other member of a one-to-one thread (nil for groups and for a deleted account).
    private var otherParticipant: Profile? {
        guard !isGroup else { return nil }
        return viewModel.participants.first { isReportable($0) }
    }

    init(
        conversationId: UUID,
        currentTitle: String?,
        currentGroupImageUrl: String? = nil,
        participants: [Profile],
        createdBy: UUID? = nil,
        onLeftConversation: (() -> Void)? = nil
    ) {
        self.conversationId = conversationId
        self.currentTitle = currentTitle
        self.currentGroupImageUrl = currentGroupImageUrl
        self.initialParticipants = participants
        self.createdBy = createdBy
        self.onLeftConversation = onLeftConversation
        _viewModel = StateObject(wrappedValue: MessageDetailsViewModel(conversationId: conversationId, participants: participants))
        _editedTitle = State(initialValue: currentTitle ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if isGroup {
                // Group Image Section
                Section {
                    HStack {
                        Spacer()
                        
                        // Group avatar with edit overlay
                        ZStack(alignment: .bottomTrailing) {
                            if let groupImage = groupImage {
                                // Show selected image
                                Image(uiImage: groupImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else if let imageUrl = currentGroupImageUrl, let url = URL(string: imageUrl) {
                                // Show existing group image
                                CachedAsyncImage(
                                    url: url,
                                    placeholder: {
                                        ProgressView()
                                            .frame(width: 80, height: 80)
                                    },
                                    errorView: { defaultGroupAvatar }
                                )
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                            } else {
                                // Default group avatar
                                defaultGroupAvatar
                            }
                            
                            // Edit button overlay
                            Button {
                                showImagePicker = true
                            } label: {
                                Image(systemName: "camera.fill")
                                    .font(.naarsFootnote)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.naarsPrimary)
                                    .clipShape(Circle())
                            }
                            .offset(x: 4, y: 4)
                            .accessibilityLabel("messaging_change_group_photo".localized)
                        }
                        
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                
                // Title Section
                Section("messaging_conversation_name_section".localized) {
                    TextField("messaging_group_name_placeholder".localized, text: $editedTitle)
                        .textInputAutocapitalization(.words)
                        .onChange(of: editedTitle) { _, newValue in
                            if newValue.count > 50 {
                                editedTitle = String(newValue.prefix(50))
                            }
                        }
                    Text("\(editedTitle.count)/50")
                        .font(.naarsCaption)
                        .foregroundColor(editedTitle.count >= 45 ? .naarsWarning : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                } // isGroup

                // Participants Section
                Section((isGroup ? "messaging_participants_section_count" : "messaging_participants_count").localized(with: viewModel.activeParticipantCount > 0 ? viewModel.activeParticipantCount : viewModel.participants.count)) {
                    if viewModel.isLoadingParticipants {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    }
                    
                    ForEach(viewModel.participants) { participant in
                        HStack {
                            if participant.name.isEmpty || participant.name == "messaging_deleted_user".localized {
                                AvatarView(
                                    imageUrl: nil,
                                    name: "messaging_deleted_user".localized,
                                    size: 40,
                                    userId: participant.id
                                )

                                Text("messaging_deleted_user".localized)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                            } else {
                                AvatarView(
                                    imageUrl: participant.avatarUrl,
                                    name: participant.name,
                                    size: 40,
                                    userId: participant.id
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(participant.name)
                                        .font(.naarsBody)

                                    if participant.id == AuthService.shared.currentUserId {
                                        Text("messaging_you".localized)
                                            .font(.naarsCaption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            // Report / block a group member. Without this, someone who has not
                            // sent a message yet could not be reported or blocked from Messages
                            // (a one-to-one thread has its own section below).
                            if isGroup && isReportable(participant) {
                                memberSafetyMenu(for: participant)
                            }

                            // Remove button (groups only, and never for the current user)
                            if isGroup && participant.id != AuthService.shared.currentUserId {
                                Button(role: .destructive) {
                                    participantToRemove = participant
                                    showRemoveConfirmation = true
                                } label: {
                                    Group {
                                        if viewModel.isRemovingParticipant && participantToRemove?.id == participant.id {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.naarsError)
                                        }
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                // Borderless: the row now holds two controls, and a Form row
                                // otherwise fires its default-style button for a tap anywhere.
                                .buttonStyle(.borderless)
                                .disabled(viewModel.isRemovingParticipant)
                                .accessibilityLabel("messaging_remove_participant_accessibility".localized(
                                    with: participant.name.isEmpty ? "messaging_deleted_user".localized : participant.name
                                ))
                            }
                        }
                    }

                    // Add Participants Button (the group's creator only; see canAddParticipants)
                    if isGroup {
                        if canAddParticipants {
                            Button {
                                showAddParticipants = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                    Text("messaging_add_participants".localized)
                                }
                            }
                            .disabled(viewModel.activeParticipantCount >= 50)
                        } else {
                            Text("messaging_add_participants_creator_only".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Notifications Section
                Section("messaging_notifications_section".localized) {
                    if viewModel.isConversationMuted {
                        Button {
                            Task { await viewModel.unmute() }
                        } label: {
                            HStack {
                                Image(systemName: "bell")
                                Text("messaging_unmute_notifications".localized)
                            }
                        }
                    } else {
                        Menu {
                            ForEach(ConversationMuteService.MuteDuration.allCases, id: \.self) { duration in
                                Button(duration.displayName) {
                                    Task { await viewModel.mute(duration: duration) }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.slash")
                                Text("messaging_mute_notifications".localized)
                            }
                        }
                    }

                    if isGroup {
                        Toggle(isOn: $viewModel.showReadReceiptsForConversation) {
                            HStack {
                                Image(systemName: "checkmark.message")
                                Text("messaging_show_read_receipts".localized)
                            }
                        }
                        .onChange(of: viewModel.showReadReceiptsForConversation) { _, newValue in
                            Task { await viewModel.updateShowReadReceipts(newValue) }
                        }
                    }
                }

                // Report / Block (one-to-one)
                if let other = otherParticipant {
                    safetySection(for: other)
                }

                // Leave Group Section
                if isGroup {
                Section {
                    if viewModel.activeParticipantCount > 0 && viewModel.activeParticipantCount <= 3 {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("messaging_leave_conversation".localized)
                                Text("messaging_leave_disabled_tooltip".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.secondary)
                    } else {
                        Button(role: .destructive) {
                            showLeaveConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("messaging_leave_conversation".localized)
                            }
                            .foregroundColor(.naarsError)
                        }
                    }
                }
                } // isGroup

                // Error Display
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundColor(.naarsError)
                            .font(.naarsCaption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                viewModel.refreshBlockedStatus()
                await viewModel.loadInitialState()
            }
            .navigationTitle("messaging_conversation_details_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isGroup {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("messaging_cancel".localized) {
                            dismiss()
                        }
                        .disabled(viewModel.isSaving || viewModel.isUploadingImage)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        if viewModel.isSaving || viewModel.isUploadingImage {
                            ProgressView()
                        } else {
                            Button("messaging_save".localized) {
                                Task {
                                    if await viewModel.saveChanges(groupImage: groupImage, editedTitle: editedTitle, currentTitle: currentTitle) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Nothing to save in a one-to-one thread: mute applies immediately.
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common_done".localized) {
                            dismiss()
                        }
                    }
                }
            }
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $selectedImageItem,
                matching: .images
            )
            .onChange(of: selectedImageItem) { _, newValue in
                Task {
                    if let item = newValue {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            groupImage = UIImage(data: data)
                        }
                    }
                }
            }
            // A swipe-down calls neither Cancel nor Add; drop the selection so it is not
            // still there the next time the picker opens.
            .sheet(isPresented: $showAddParticipants, onDismiss: { selectedUserIds = [] }) {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: viewModel.participants.map { $0.id },
                    actionButtonTitle: "messaging_add_action".localized,
                    onDismiss: {
                        AppLogger.info("messaging", "[MessageDetailsPopup] UserSearchView dismissed with \(selectedUserIds.count) selected user(s)")
                        let idsToAdd = Array(selectedUserIds)
                        showAddParticipants = false
                        selectedUserIds = []
                        
                        if !idsToAdd.isEmpty {
                            AppLogger.info("messaging", "[MessageDetailsPopup] Will add user IDs: \(idsToAdd)")
                            Task {
                                await viewModel.addParticipants(idsToAdd)
                            }
                        } else {
                            AppLogger.info("messaging", "[MessageDetailsPopup] No users selected, skipping participant addition")
                        }
                    }
                )
            }
            .alert("messaging_leave_conversation".localized, isPresented: $showLeaveConfirmation) {
                Button("messaging_cancel".localized, role: .cancel) { }
                Button("messaging_leave".localized, role: .destructive) {
                    Task {
                        if await viewModel.leaveConversation() {
                            onLeftConversation?()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("messaging_leave_conversation_confirmation".localized)
            }
            .alert("messaging_remove_participant".localized, isPresented: $showRemoveConfirmation) {
                Button("messaging_cancel".localized, role: .cancel) {
                    participantToRemove = nil
                }
                Button("common_remove".localized, role: .destructive) {
                    if let participant = participantToRemove {
                        Task {
                            await viewModel.removeParticipant(userId: participant.id)
                            participantToRemove = nil
                        }
                    }
                }
            } message: {
                if let participant = participantToRemove {
                    Text(String(format: "messaging_remove_participant_confirmation".localized, participant.name))
                } else {
                    Text("messaging_remove_participant_generic_confirmation".localized)
                }
            }
            .toast(message: $toastMessage)
        }
        .sheet(item: $userToReport) { user in
            ReportContentSheet(
                context: .user(id: user.id, name: user.name),
                onReported: { toastMessage = "messaging_report_submitted".localized },
                // The report sheet has its own "Block this user"; keep this sheet's rows in step.
                onBlocked: { viewModel.markBlocked($0) }
            )
        }
        .alert("profile_block_user".localized, isPresented: $showBlockConfirmation) {
            Button("profile_block_confirm".localized, role: .destructive) {
                guard let user = userToBlock else { return }
                Task {
                    if await viewModel.blockUser(user.id) {
                        toastMessage = "profile_user_blocked".localized
                    }
                }
            }
            Button("common_cancel".localized, role: .cancel) {}
        } message: {
            Text("profile_block_confirmation_message".localized)
        }
        .alert("messaging_block_failed".localized, isPresented: Binding(
            get: { viewModel.blockError != nil },
            set: { if !$0 { viewModel.blockError = nil } }
        )) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(viewModel.blockError ?? "")
        }
    }
    
    // MARK: - Views

    /// Report / Block rows for the other member of a one-to-one thread. Without them, someone
    /// who has not sent a message yet could not be reported or blocked from Messages at all.
    /// Both reuse existing flows: `ReportContentSheet` and the `block_user` RPC.
    private func safetySection(for other: Profile) -> some View {
        Section {
            Button {
                userToReport = other
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("profile_report_user".localized)
                }
            }

            if viewModel.blockedUserIds.contains(other.id) {
                HStack {
                    Image(systemName: "hand.raised.fill")
                    Text("profile_user_blocked".localized)
                }
                .foregroundColor(.secondary)
            } else {
                Button(role: .destructive) {
                    userToBlock = other
                    showBlockConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "hand.raised")
                        Text("profile_block_user".localized)
                    }
                    .foregroundColor(.naarsError)
                }
                .disabled(viewModel.isBlocking)
            }
        }
    }

    /// Report / Block for one member of a group, on that member's row. Same flows as the
    /// one-to-one section above.
    private func memberSafetyMenu(for participant: Profile) -> some View {
        Menu {
            Button {
                userToReport = participant
            } label: {
                Label("profile_report_user".localized, systemImage: "exclamationmark.triangle")
            }

            if viewModel.blockedUserIds.contains(participant.id) {
                // Already blocked: shown, not tappable.
                Button {} label: {
                    Label("profile_user_blocked".localized, systemImage: "hand.raised.fill")
                }
                .disabled(true)
            } else {
                Button(role: .destructive) {
                    userToBlock = participant
                    showBlockConfirmation = true
                } label: {
                    Label("profile_block_user".localized, systemImage: "hand.raised")
                }
                .disabled(viewModel.isBlocking)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.naarsPrimary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        // Borderless for the same reason as the remove button beside it.
        .buttonStyle(.borderless)
        .accessibilityLabel("messaging_member_options_accessibility".localized(with: participant.name))
    }

    private var defaultGroupAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.naarsPrimary.opacity(0.2))
                .frame(width: 80, height: 80)
            
            Image(systemName: "person.2.fill")
                .foregroundColor(.naarsPrimary)
                .font(.system(size: 30))
        }
    }
}

#Preview("One-to-one") {
    MessageDetailsPopup(
        conversationId: UUID(),
        currentTitle: nil,
        currentGroupImageUrl: nil,
        participants: [
            Profile(id: UUID(), name: "John Doe", email: "john@example.com"),
            Profile(id: UUID(), name: "Jane Smith", email: "jane@example.com")
        ]
    )
}

#Preview("Group") {
    MessageDetailsPopup(
        conversationId: UUID(),
        currentTitle: "Group Chat",
        currentGroupImageUrl: nil,
        participants: [
            Profile(id: UUID(), name: "John Doe", email: "john@example.com"),
            Profile(id: UUID(), name: "Jane Smith", email: "jane@example.com"),
            Profile(id: UUID(), name: "Sam Lee", email: "sam@example.com")
        ]
    )
}
