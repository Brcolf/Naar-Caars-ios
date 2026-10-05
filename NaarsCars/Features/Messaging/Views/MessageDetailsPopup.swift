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
    
    init(conversationId: UUID, currentTitle: String?, currentGroupImageUrl: String? = nil, participants: [Profile]) {
        self.conversationId = conversationId
        self.currentTitle = currentTitle
        self.currentGroupImageUrl = currentGroupImageUrl
        self.initialParticipants = participants
        _viewModel = StateObject(wrappedValue: MessageDetailsViewModel(conversationId: conversationId, participants: participants))
        _editedTitle = State(initialValue: currentTitle ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                        .foregroundColor(editedTitle.count >= 45 ? .orange : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                // Participants Section
                Section("messaging_participants_section_count".localized(with: viewModel.activeParticipantCount > 0 ? viewModel.activeParticipantCount : viewModel.participants.count)) {
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

                            // Remove button (only for non-current user)
                            if participant.id != AuthService.shared.currentUserId {
                                Button(role: .destructive) {
                                    participantToRemove = participant
                                    showRemoveConfirmation = true
                                } label: {
                                    if viewModel.isRemovingParticipant && participantToRemove?.id == participant.id {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                                .disabled(viewModel.isRemovingParticipant)
                            }
                        }
                    }
                    
                    // Add Participants Button
                    Button {
                        showAddParticipants = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("messaging_add_participants".localized)
                        }
                    }
                    .disabled(viewModel.activeParticipantCount >= 50)
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

                // Leave Group Section
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
                            .foregroundColor(.red)
                        }
                    }
                }
                
                // Error Display
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.naarsCaption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .task { await viewModel.loadInitialState() }
            .navigationTitle("messaging_conversation_details_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .sheet(isPresented: $showAddParticipants) {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: viewModel.participants.map { $0.id },
                    actionButtonTitle: "Add",
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
        }
    }
    
    // MARK: - Views
    
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

#Preview {
    MessageDetailsPopup(
        conversationId: UUID(),
        currentTitle: "Group Chat",
        currentGroupImageUrl: nil,
        participants: [
            Profile(id: UUID(), name: "John Doe", email: "john@example.com"),
            Profile(id: UUID(), name: "Jane Smith", email: "jane@example.com")
        ]
    )
}
