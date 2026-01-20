//
//  MessageDetailsPopup.swift
//  NaarsCars
//
//  Popup for editing conversation details (title and participants)
//

import SwiftUI
import Supabase

/// Popup for editing conversation details
struct MessageDetailsPopup: View {
    @Environment(\.dismiss) private var dismiss
    
    let conversationId: UUID
    let currentTitle: String?
    let initialParticipants: [Profile]
    
    @State private var participants: [Profile]
    @State private var editedTitle: String
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var isSaving = false
    @State private var isLoadingParticipants = false
    @State private var error: String?
    
    init(conversationId: UUID, currentTitle: String?, participants: [Profile]) {
        self.conversationId = conversationId
        self.currentTitle = currentTitle
        self.initialParticipants = participants
        _participants = State(initialValue: participants)
        _editedTitle = State(initialValue: currentTitle ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Title Section
                Section("Conversation Name") {
                    TextField("Group Name", text: $editedTitle)
                        .textInputAutocapitalization(.words)
                }
                
                // Participants Section
                Section("Participants") {
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
                                    Text("You")
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            // Remove button (only for non-current user)
                            if participant.id != AuthService.shared.currentUserId {
                                Button(role: .destructive) {
                                    Task {
                                        await removeParticipant(userId: participant.id)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    // Add Participants Button
                    Button {
                        showAddParticipants = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Add Participants")
                        }
                    }
                }
                
                // Error Display
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Conversation Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showAddParticipants) {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: participants.map { $0.id },
                    actionButtonTitle: "Add",
                    onDismiss: {
                        print("🔍 [MessageDetailsPopup] UserSearchView dismissed with \(selectedUserIds.count) selected user(s)")
                        // Capture the selected IDs BEFORE clearing to avoid race condition
                        let idsToAdd = Array(selectedUserIds)
                        showAddParticipants = false
                        selectedUserIds = []
                        
                        if !idsToAdd.isEmpty {
                            print("🔍 [MessageDetailsPopup] Will add user IDs: \(idsToAdd)")
                            Task {
                                await addParticipants(idsToAdd)
                            }
                        } else {
                            print("ℹ️ [MessageDetailsPopup] No users selected, skipping participant addition")
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func saveChanges() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        
        guard let userId = AuthService.shared.currentUserId else {
            error = "Not authenticated"
            return
        }
        
        do {
            // Update title if changed
            let titleToSave = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = titleToSave.isEmpty ? nil : titleToSave
            
            if finalTitle != currentTitle {
                try await MessageService.shared.updateConversationTitle(
                    conversationId: conversationId,
                    title: finalTitle,
                    userId: userId
                )
            }
            
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func addParticipants(_ userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            print("✅ [MessageDetailsPopup] Adding \(userIds.count) participant(s) to conversation \(conversationId)")
            
            try await MessageService.shared.addParticipantsToConversation(
                conversationId: conversationId,
                userIds: userIds,
                addedBy: currentUserId,
                createAnnouncement: true
            )
            
            print("✅ [MessageDetailsPopup] Successfully added participants, reloading list")
            // Reload participants immediately so the list updates
            await loadParticipants()
        } catch {
            print("🔴 [MessageDetailsPopup] Failed to add participants: \(error.localizedDescription)")
            self.error = "Failed to add participants: \(error.localizedDescription)"
        }
    }
    
    private func loadParticipants() async {
        isLoadingParticipants = true
        defer { isLoadingParticipants = false }
        
        do {
            // Fetch participant user IDs
            let response = try await SupabaseService.shared.client
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .execute()
            
            struct ParticipantRow: Codable {
                let userId: UUID
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                }
            }
            
            let rows = try JSONDecoder().decode([ParticipantRow].self, from: response.data)
            
            // Fetch profiles for each participant
            var profiles: [Profile] = []
            for row in rows {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: row.userId) {
                    profiles.append(profile)
                }
            }
            
            self.participants = profiles
            print("✅ [MessageDetailsPopup] Reloaded \(profiles.count) participants")
        } catch {
            print("🔴 [MessageDetailsPopup] Error loading participants: \(error.localizedDescription)")
        }
    }
    
    private func removeParticipant(userId: UUID) async {
        // Note: Removing participants would require a new method in MessageService
        // For now, we'll skip this functionality - users can leave conversations themselves
        // In the future, we could add MessageService.removeParticipant()
    }
}

#Preview {
    MessageDetailsPopup(
        conversationId: UUID(),
        currentTitle: "Group Chat",
        participants: [
            Profile(id: UUID(), name: "John Doe", email: "john@example.com"),
            Profile(id: UUID(), name: "Jane Smith", email: "jane@example.com")
        ]
    )
}

