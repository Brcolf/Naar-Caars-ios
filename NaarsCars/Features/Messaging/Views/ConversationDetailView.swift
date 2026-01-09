//
//  ConversationDetailView.swift
//  NaarsCars
//
//  View for displaying conversation detail (chat screen)
//

import SwiftUI
internal import Combine
import Supabase
import PostgREST

/// View for displaying conversation detail (chat screen)
struct ConversationDetailView: View {
    let conversationId: UUID
    @StateObject private var viewModel: ConversationDetailViewModel
    @StateObject private var participantsViewModel: ConversationParticipantsViewModel
    @FocusState private var isInputFocused: Bool
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        _viewModel = StateObject(wrappedValue: ConversationDetailViewModel(conversationId: conversationId))
        _participantsViewModel = StateObject(wrappedValue: ConversationParticipantsViewModel(conversationId: conversationId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.isLoading {
                            ProgressView()
                                .padding()
                        } else if viewModel.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("No messages yet")
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isFromCurrentUser: isFromCurrentUser(message)
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // Auto-scroll to bottom on new messages
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                    // Update last_seen when new messages arrive while viewing
                    // This ensures we don't get push notifications for messages we see in real-time
                    Task {
                        if let userId = AuthService.shared.currentUserId {
                            try? await MessageService.shared.updateLastSeen(conversationId: conversationId, userId: userId)
                        }
                    }
                }
            }
            
            // Input bar
            MessageInputBar(
                text: $viewModel.messageText,
                onSend: {
                    Task {
                        await viewModel.sendMessage()
                    }
                },
                isDisabled: viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddParticipants = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showAddParticipants) {
            UserSearchView(
                selectedUserIds: $selectedUserIds,
                excludeUserIds: participantsViewModel.participantIds,
                onDismiss: {
                    if !selectedUserIds.isEmpty {
                        Task {
                            await addParticipants(Array(selectedUserIds))
                        }
                    }
                    showAddParticipants = false
                    selectedUserIds = []
                }
            )
        }
        .task {
            await viewModel.loadMessages()
            await participantsViewModel.loadParticipants()
        }
        .onAppear {
            // Mark as read and update last_seen when view appears
            // This prevents push notifications when user is actively viewing
            Task {
                if let userId = AuthService.shared.currentUserId {
                    // Update last_seen first to mark user as actively viewing
                    try? await MessageService.shared.updateLastSeen(conversationId: conversationId, userId: userId)
                    // Then mark messages as read
                    try? await MessageService.shared.markAsRead(conversationId: conversationId, userId: userId)
                }
            }
        }
    }
    
    private func isFromCurrentUser(_ message: Message) -> Bool {
        message.fromId == AuthService.shared.currentUserId
    }
    
    private func addParticipants(_ userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            try await MessageService.shared.addParticipantsToConversation(
                conversationId: conversationId,
                userIds: userIds,
                addedBy: currentUserId,
                createAnnouncement: true
            )
            // Reload messages to show announcement
            await viewModel.loadMessages()
            // Reload participants
            await participantsViewModel.loadParticipants()
        } catch {
            print("🔴 Error adding participants: \(error.localizedDescription)")
        }
    }
}

/// ViewModel for managing conversation participants
@MainActor
final class ConversationParticipantsViewModel: ObservableObject {
    @Published var participants: [Profile] = []
    @Published var isLoading = false
    @Published var error: AppError?
    
    let conversationId: UUID
    private let messageService = MessageService.shared
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
    }
    
    var participantIds: [UUID] {
        participants.map { $0.id }
    }
    
    func loadParticipants() async {
        isLoading = true
        error = nil
        
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
        } catch {
            self.error = AppError.processingError("Failed to load participants: \(error.localizedDescription)")
            print("🔴 Error loading participants: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ConversationDetailView(conversationId: UUID())
    }
}



