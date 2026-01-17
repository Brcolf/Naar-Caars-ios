//
//  MessageDetailsPopup.swift
//  NaarsCars
//
//  Popup for editing conversation details (title and participants)
//

import SwiftUI

/// Popup for editing conversation details
struct MessageDetailsPopup: View {
    @Environment(\.dismiss) private var dismiss
    
    let conversationId: UUID
    let currentTitle: String?
    let participants: [Profile]
    
    @State private var editedTitle: String
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var isSaving = false
    @State private var error: String?
    
    init(conversationId: UUID, currentTitle: String?, participants: [Profile]) {
        self.conversationId = conversationId
        self.currentTitle = currentTitle
        self.participants = participants
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
                    onDismiss: {
                        print("📋 [MessageDetailsPopup] Add participants dismissed with \(selectedUserIds.count) selected users")
                        
                        // Capture the selected IDs before clearing
                        let selectedIds = Array(selectedUserIds)
                        
                        // Clear state immediately
                        showAddParticipants = false
                        selectedUserIds = []
                        
                        // Use captured IDs in async task
                        if !selectedIds.isEmpty {
                            Task {
                                print("➕ [MessageDetailsPopup] Adding \(selectedIds.count) participants to conversation")
                                await addParticipants(selectedIds)
                            }
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
        guard let currentUserId = AuthService.shared.currentUserId else {
            print("🔴 [MessageDetailsPopup] No current user ID")
            return
        }
        
        print("🔄 [MessageDetailsPopup] Starting to add \(userIds.count) participants")
        print("   User IDs: \(userIds)")
        print("   Conversation ID: \(conversationId)")
        
        do {
            try await MessageService.shared.addParticipantsToConversation(
                conversationId: conversationId,
                userIds: userIds,
                addedBy: currentUserId,
                createAnnouncement: true
            )
            
            print("✅ [MessageDetailsPopup] Successfully added \(userIds.count) participants")
            
            // Post notification to refresh conversation
            NotificationCenter.default.post(
                name: NSNotification.Name("conversationUpdated"),
                object: conversationId
            )
            
            // Dismiss the popup so parent view reloads
            dismiss()
        } catch {
            print("🔴 [MessageDetailsPopup] Failed to add participants: \(error)")
            self.error = "Failed to add participants: \(error.localizedDescription)"
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

