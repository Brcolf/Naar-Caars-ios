//
//  MessageDetailsPopup.swift
//  NaarsCars
//
//  Popup for editing conversation details (title, participants, and group image)
//

import SwiftUI
import Supabase
import PhotosUI

/// Popup for editing conversation details
struct MessageDetailsPopup: View {
    @Environment(\.dismiss) private var dismiss
    
    let conversationId: UUID
    let currentTitle: String?
    let currentGroupImageUrl: String?
    let initialParticipants: [Profile]
    
    @State private var participants: [Profile]
    @State private var editedTitle: String
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var isSaving = false
    @State private var isLoadingParticipants = false
    @State private var isRemovingParticipant = false
    @State private var error: String?
    
    // Group image states
    @State private var showImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var groupImage: UIImage?
    @State private var isUploadingImage = false
    
    // Leave/Remove confirmation
    @State private var showLeaveConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var participantToRemove: Profile?
    
    init(conversationId: UUID, currentTitle: String?, currentGroupImageUrl: String? = nil, participants: [Profile]) {
        self.conversationId = conversationId
        self.currentTitle = currentTitle
        self.currentGroupImageUrl = currentGroupImageUrl
        self.initialParticipants = participants
        _participants = State(initialValue: participants)
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
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 80, height: 80)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(Circle())
                                    case .failure:
                                        defaultGroupAvatar
                                    @unknown default:
                                        defaultGroupAvatar
                                    }
                                }
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
                Section("Conversation Name") {
                    TextField("Group Name", text: $editedTitle)
                        .textInputAutocapitalization(.words)
                }
                
                // Participants Section
                Section("Participants (\(participants.count))") {
                    if isLoadingParticipants {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    }
                    
                    ForEach(participants) { participant in
                        HStack {
                            AvatarView(
                                imageUrl: participant.avatarUrl,
                                name: participant.name,
                                size: 40
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
                            
                            Spacer()
                            
                            // Remove button (only for non-current user)
                            if participant.id != AuthService.shared.currentUserId {
                                Button(role: .destructive) {
                                    participantToRemove = participant
                                    showRemoveConfirmation = true
                                } label: {
                                    if isRemovingParticipant && participantToRemove?.id == participant.id {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                                .disabled(isRemovingParticipant)
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
                }
                
                // Leave Group Section
                Section {
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
                
                // Error Display
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.naarsCaption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Conversation Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("messaging_cancel".localized) {
                        dismiss()
                    }
                    .disabled(isSaving || isUploadingImage)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving || isUploadingImage {
                        ProgressView()
                    } else {
                        Button("messaging_save".localized) {
                            Task {
                                await saveChanges()
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
                    excludeUserIds: participants.map { $0.id },
                    actionButtonTitle: "Add",
                    onDismiss: {
                        AppLogger.info("messaging", "[MessageDetailsPopup] UserSearchView dismissed with \(selectedUserIds.count) selected user(s)")
                        let idsToAdd = Array(selectedUserIds)
                        showAddParticipants = false
                        selectedUserIds = []
                        
                        if !idsToAdd.isEmpty {
                            AppLogger.info("messaging", "[MessageDetailsPopup] Will add user IDs: \(idsToAdd)")
                            Task {
                                await addParticipants(idsToAdd)
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
                        await leaveConversation()
                    }
                }
            } message: {
                Text("messaging_leave_conversation_confirmation".localized)
            }
            .alert("messaging_remove_participant".localized, isPresented: $showRemoveConfirmation) {
                Button("messaging_cancel".localized, role: .cancel) {
                    participantToRemove = nil
                }
                Button("Remove", role: .destructive) {
                    if let participant = participantToRemove {
                        Task {
                            await removeParticipant(userId: participant.id)
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
    
    // MARK: - Private Methods
    
    private func saveChanges() async {
        isSaving = true
        error = nil
        
        guard let userId = AuthService.shared.currentUserId else {
            error = "messaging_not_authenticated".localized
            isSaving = false
            return
        }
        
        do {
            // Upload new group image if selected
            if let newImage = groupImage, let imageData = newImage.jpegData(compressionQuality: 0.8) {
                isUploadingImage = true
                let imageUrl = try await ConversationService.shared.uploadGroupImage(
                    imageData: imageData,
                    conversationId: conversationId
                )
                try await ConversationService.shared.updateGroupImage(
                    conversationId: conversationId,
                    imageUrl: imageUrl,
                    userId: userId
                )
                isUploadingImage = false
            }
            
            // Update title if changed
            let titleToSave = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = titleToSave.isEmpty ? nil : titleToSave
            
            if finalTitle != currentTitle {
                try await ConversationService.shared.updateConversationTitle(
                    conversationId: conversationId,
                    title: finalTitle,
                    userId: userId
                )
            }
            
            // Post notification to refresh conversations list
            NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: conversationId)
            
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        
        isSaving = false
        isUploadingImage = false
    }
    
    private func addParticipants(_ userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            AppLogger.info("messaging", "[MessageDetailsPopup] Adding \(userIds.count) participant(s) to conversation \(conversationId)")
            
            try await ConversationParticipantService.shared.addParticipantsToConversation(
                conversationId: conversationId,
                userIds: userIds,
                addedBy: currentUserId,
                createAnnouncement: true
            )
            
            AppLogger.info("messaging", "[MessageDetailsPopup] Successfully added participants, reloading list")
            await loadParticipants()
        } catch {
            AppLogger.error("messaging", "[MessageDetailsPopup] Failed to add participants: \(error.localizedDescription)")
            self.error = "\("messaging_failed_to_add_participants".localized): \(error.localizedDescription)"
        }
    }
    
    private func loadParticipants() async {
        isLoadingParticipants = true
        defer { isLoadingParticipants = false }
        
        do {
            // Fetch participant user IDs (only active participants - not left)
            let response = try await SupabaseService.shared.client
                .from("conversation_participants")
                .select("user_id, left_at")
                .eq("conversation_id", value: conversationId.uuidString)
                .is("left_at", value: nil) // Only active participants
                .execute()
            
            struct ParticipantRow: Codable {
                let userId: UUID
                let leftAt: Date?
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case leftAt = "left_at"
                }
            }
            
            let decoder = JSONDecoder()
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
                dateFormatter.formatOptions = [.withInternetDateTime]
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            
            let rows = try decoder.decode([ParticipantRow].self, from: response.data)
            
            // Fetch profiles for each participant
            var profiles: [Profile] = []
            for row in rows {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: row.userId) {
                    profiles.append(profile)
                }
            }
            
            self.participants = profiles
            AppLogger.info("messaging", "[MessageDetailsPopup] Reloaded \(profiles.count) active participants")
        } catch {
            AppLogger.error("messaging", "[MessageDetailsPopup] Error loading participants: \(error.localizedDescription)")
        }
    }
    
    private func removeParticipant(userId: UUID) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        isRemovingParticipant = true
        defer { 
            isRemovingParticipant = false
            participantToRemove = nil
        }
        
        do {
            try await ConversationParticipantService.shared.removeParticipantFromConversation(
                conversationId: conversationId,
                userId: userId,
                removedBy: currentUserId,
                createAnnouncement: true
            )
            
            // Remove from local list
            participants.removeAll { $0.id == userId }
            
            AppLogger.info("messaging", "[MessageDetailsPopup] Successfully removed participant")
        } catch {
            AppLogger.error("messaging", "[MessageDetailsPopup] Failed to remove participant: \(error.localizedDescription)")
            self.error = "\("messaging_failed_to_remove_participant".localized): \(error.localizedDescription)"
        }
    }
    
    private func leaveConversation() async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await ConversationParticipantService.shared.leaveConversation(
                conversationId: conversationId,
                userId: currentUserId,
                createAnnouncement: true
            )
            
            // Post notification to refresh conversations list
            NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: conversationId)
            
            dismiss()
        } catch {
            self.error = "\("messaging_failed_to_leave_conversation".localized): \(error.localizedDescription)"
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
