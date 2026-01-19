//
//  ConversationDetailView.swift
//  NaarsCars
//
//  View for displaying conversation detail (chat screen)
//

import SwiftUI
import PhotosUI
internal import Combine
import Supabase
import PostgREST

/// View for displaying conversation detail (chat screen)
struct ConversationDetailView: View {
    let conversationId: UUID
    @StateObject private var viewModel: ConversationDetailViewModel
    @StateObject private var participantsViewModel: ConversationParticipantsViewModel
    @FocusState private var isInputFocused: Bool
    @State private var showMessageDetails = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var conversationDetail: ConversationWithDetails?
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var imageToSend: UIImage?
    @State private var showReactionPicker = false
    @State private var reactionPickerMessageId: UUID?
    @State private var reactionPickerPosition: CGPoint = .zero
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        _viewModel = StateObject(wrappedValue: ConversationDetailViewModel(conversationId: conversationId))
        _participantsViewModel = StateObject(wrappedValue: ConversationParticipantsViewModel(conversationId: conversationId))
    }
    
    // Computed title based on conversation type
    private var conversationTitle: String {
        // If group conversation (3+ participants), show editable group name or participant names
        if participantsViewModel.participants.count > 2 {
            if let title = conversationDetail?.conversation.title, !title.isEmpty {
                return title
            }
            // Show participant names (excluding current user)
            let otherParticipants = participantsViewModel.participants.filter { $0.id != AuthService.shared.currentUserId }
            if !otherParticipants.isEmpty {
                let names = otherParticipants.map { $0.name }
                return names.joined(separator: ", ")
            }
        }
        
        // For direct message (2 participants), show other person's name
        if participantsViewModel.participants.count == 2 {
            let otherParticipant = participantsViewModel.participants.first { $0.id != AuthService.shared.currentUserId }
            return otherParticipant?.name ?? "Chat"
        }
        
        return "Chat"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Load more button at top (for pagination)
                        if viewModel.hasMoreMessages && !viewModel.messages.isEmpty {
                            Button {
                                Task {
                                    await viewModel.loadMoreMessages()
                                }
                            } label: {
                                HStack {
                                    if viewModel.isLoadingMore {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text(viewModel.isLoadingMore ? "Loading..." : "Load Older Messages")
                                        .font(.naarsCaption)
                                        .foregroundColor(.naarsPrimary)
                                }
                                .padding(.vertical, 8)
                            }
                            .disabled(viewModel.isLoadingMore)
                        }
                        
                        if viewModel.isLoading && viewModel.messages.isEmpty {
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
                                    isFromCurrentUser: isFromCurrentUser(message),
                                    onLongPress: {
                                        reactionPickerMessageId = message.id
                                        showReactionPicker = true
                                    },
                                    onReactionTap: { reaction in
                                        Task {
                                            if let userId = AuthService.shared.currentUserId,
                                               let reactions = message.reactions,
                                               let userIds = reactions.reactions[reaction],
                                               userIds.contains(userId) {
                                                // User already reacted with this, remove it
                                                await viewModel.removeReaction(messageId: message.id)
                                            } else {
                                                // Add reaction
                                                await viewModel.addReaction(messageId: message.id, reaction: reaction)
                                            }
                                        }
                                    }
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // Auto-scroll to bottom on new messages (only if not loading more)
                    if !viewModel.isLoadingMore, let lastMessage = viewModel.messages.last {
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
            .overlay(alignment: .center) {
                // Reaction picker overlay (centered on screen)
                if showReactionPicker {
                    VStack {
                        Spacer()
                        ReactionPicker(
                            onReactionSelected: { reaction in
                                if let messageId = reactionPickerMessageId {
                                    Task {
                                        await viewModel.addReaction(messageId: messageId, reaction: reaction)
                                    }
                                }
                                showReactionPicker = false
                                reactionPickerMessageId = nil
                            },
                            onDismiss: {
                                showReactionPicker = false
                                reactionPickerMessageId = nil
                            }
                        )
                        .padding(.bottom, 100) // Position above input bar
                        Spacer()
                    }
                    .background(Color.black.opacity(0.3))
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture {
                        showReactionPicker = false
                        reactionPickerMessageId = nil
                    }
                }
            }
            
            // Input bar
            MessageInputBar(
                text: $viewModel.messageText,
                imageToSend: $imageToSend,
                onSend: {
                    Task {
                        await viewModel.sendMessage(image: imageToSend)
                        imageToSend = nil
                    }
                },
                onImagePickerTapped: {
                    showImagePicker = true
                },
                isDisabled: viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageToSend == nil
            )
        }
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Edit button for group conversations (opens message details popup)
                if participantsViewModel.participants.count > 2 {
                    Button {
                        showMessageDetails = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showMessageDetails) {
            MessageDetailsPopup(
                conversationId: conversationId,
                currentTitle: conversationDetail?.conversation.title,
                participants: participantsViewModel.participants
            )
            .onDisappear {
                // Reload participants and conversation details after closing
                Task {
                    await participantsViewModel.loadParticipants()
                    await loadConversationDetails()
                }
            }
        }
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedImage,
            matching: .images
        )
        .onChange(of: selectedImage) { _, newValue in
            Task {
                if let item = newValue {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        imageToSend = UIImage(data: data)
                    }
                } else {
                    imageToSend = nil
                }
            }
        }
        .task {
            await viewModel.loadMessages()
            await participantsViewModel.loadParticipants()
            await loadConversationDetails()
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
        .trackScreen("ConversationDetail")
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
            // Reload conversation details to get updated participant list
            await loadConversationDetails()
            
            // Post notification to refresh conversations list
            NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: conversationId)
        } catch {
            print("🔴 Error adding participants: \(error.localizedDescription)")
        }
    }
    
    private func loadConversationDetails() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            let conversations = try await MessageService.shared.fetchConversations(userId: userId, limit: 100, offset: 0)
            if let detail = conversations.first(where: { $0.conversation.id == conversationId }) {
                conversationDetail = detail
            }
        } catch {
            print("🔴 Error loading conversation details: \(error.localizedDescription)")
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



