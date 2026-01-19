//
//  ConversationsListView.swift
//  NaarsCars
//
//  View for displaying list of conversations (iMessage-style)
//

import SwiftUI
import Supabase
import PostgREST

/// View for displaying list of conversations
struct ConversationsListView: View {
    @StateObject private var viewModel = ConversationsListViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @EnvironmentObject var appState: AppState
    @State private var showNewMessage = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var navigateToConversation: UUID?
    @State private var conversationToDelete: ConversationWithDetails?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    // Skeleton loading
                    List {
                        ForEach(0..<5) { _ in
                            SkeletonConversationRow()
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                } else if let error = viewModel.error {
                    ErrorView(
                        error: error.localizedDescription,
                        retryAction: { Task { await viewModel.loadConversations() } }
                    )
                } else if viewModel.conversations.isEmpty {
                    EmptyStateView(
                        icon: "message.fill",
                        title: "No Conversations Yet",
                        message: "Start a conversation by claiming a request or messaging a user.",
                        actionTitle: "New Message",
                        action: {
                            showNewMessage = true
                        },
                        customImage: "naars_messages_icon"
                    )
                } else {
                    List {
                        ForEach(viewModel.conversations) { conversationDetail in
                            NavigationLink {
                                ConversationDetailView(conversationId: conversationDetail.conversation.id)
                            } label: {
                                ConversationRow(conversationDetail: conversationDetail)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    conversationToDelete = conversationDetail
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    // Archive conversation (placeholder - implement if needed)
                                    print("Archive conversation: \(conversationDetail.conversation.id)")
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.blue)
                            }
                        }
                        
                        // Load more button at bottom
                        if viewModel.hasMoreConversations {
                            Button {
                                Task {
                                    await viewModel.loadMoreConversations()
                                }
                            } label: {
                                HStack {
                                    if viewModel.isLoadingMore {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text(viewModel.isLoadingMore ? "Loading..." : "Load More")
                                        .font(.naarsBody)
                                        .foregroundColor(.naarsPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                            .disabled(viewModel.isLoadingMore)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.refreshConversations()
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewMessage = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showNewMessage) {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: [],
                    onDismiss: {
                        // Don't dismiss immediately - wait for navigation
                    }
                )
            }
            .onChange(of: showNewMessage) { _, isShowing in
                if !isShowing && !selectedUserIds.isEmpty {
                    // Sheet was dismissed with selections - create/navigate to conversation
                    Task {
                        await createOrNavigateToConversation(with: Array(selectedUserIds))
                        selectedUserIds = []
                    }
                } else if !isShowing {
                    // Sheet dismissed without selections
                    selectedUserIds = []
                }
            }
            .navigationDestination(item: $navigateToConversation) { conversationId in
                ConversationDetailView(conversationId: conversationId)
            }
            .onChange(of: navigationCoordinator.navigateToConversation) { _, conversationId in
                if let conversationId = conversationId {
                    navigateToConversation = conversationId
                    // Reset coordinator after navigation is triggered
                    navigationCoordinator.navigateToConversation = nil
                }
            }
            .alert("Delete Conversation", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    conversationToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let conversation = conversationToDelete {
                        Task {
                            await deleteConversation(conversation)
                        }
                    }
                    conversationToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this conversation? This action cannot be undone.")
            }
            .task {
                await viewModel.loadConversations()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("conversationUpdated"))) { _ in
                Task {
                    await viewModel.refreshConversations()
                }
            }
            .trackScreen("ConversationsList")
        }
    }
    
    /// Create or navigate to existing conversation with selected users
    /// - If existing conversation found: Navigate to it
    /// - If 1 user selected: Creates/finds direct message (2 participants)
    /// - If 2+ users selected: Creates group conversation or finds existing (3+ participants)
    private func createOrNavigateToConversation(with userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        guard !userIds.isEmpty else { return }
        
        print("🔍 [ConversationsListView] Looking for existing conversation with \(userIds.count) user(s)")
        
        do {
            let conversation: Conversation
            
            if userIds.count == 1 {
                // Direct message: getOrCreateDirectConversation already checks for existing
                print("📱 [ConversationsListView] Creating/finding direct message")
                conversation = try await MessageService.shared.getOrCreateDirectConversation(
                    userId: currentUserId,
                    otherUserId: userIds[0]
                )
            } else {
                // Group conversation: Check if one exists with exactly these participants
                let allParticipantIds = Set([currentUserId] + userIds)
                
                print("👥 [ConversationsListView] Looking for group with participants: \(allParticipantIds.count) total")
                
                if let existingConversation = try await findExistingGroupConversation(participantIds: allParticipantIds) {
                    print("✅ [ConversationsListView] Found existing group conversation: \(existingConversation.id)")
                    conversation = existingConversation
                } else {
                    // Create new group conversation
                    print("➕ [ConversationsListView] Creating new group conversation")
                    conversation = try await MessageService.shared.createConversationWithUsers(
                        userIds: Array(allParticipantIds),
                        createdBy: currentUserId,
                        title: nil // User can set group name later
                    )
                }
            }
            
            print("✅ [ConversationsListView] Navigating to conversation: \(conversation.id)")
            navigateToConversation = conversation.id
            
            // Reload conversations to show the new/updated one
            await viewModel.loadConversations()
        } catch {
            print("🔴 [ConversationsListView] Error creating/navigating to conversation: \(error.localizedDescription)")
        }
    }
    
    /// Find existing group conversation with exact participant match
    private func findExistingGroupConversation(participantIds: Set<UUID>) async throws -> Conversation? {
        guard let currentUserId = AuthService.shared.currentUserId else { return nil }
        
        // Get all user's conversations
        let conversations = try await MessageService.shared.fetchConversations(userId: currentUserId, limit: 100, offset: 0)
        
        // Check each conversation for exact participant match
        for convDetail in conversations {
            // Get all participants for this conversation
            let response = try? await SupabaseService.shared.client
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: convDetail.conversation.id.uuidString)
                .execute()
            
            if let data = response?.data {
                struct ParticipantRow: Codable {
                    let userId: UUID
                    enum CodingKeys: String, CodingKey {
                        case userId = "user_id"
                    }
                }
                
                let rows = try? JSONDecoder().decode([ParticipantRow].self, from: data)
                let conversationParticipantIds = Set(rows?.map { $0.userId } ?? [])
                
                // Check for exact match
                if conversationParticipantIds == participantIds {
                    return convDetail.conversation
                }
            }
        }
        
        return nil
    }
    
    private func deleteConversation(_ conversation: ConversationWithDetails) async {
        // TODO: Implement conversation deletion in MessageService
        // For now, just reload conversations to remove deleted one
        await viewModel.refreshConversations()
    }
}

/// Conversation row component (iMessage-style)
struct ConversationRow: View {
    let conversationDetail: ConversationWithDetails
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar on left
            ConversationAvatar(conversationDetail: conversationDetail)
                .frame(width: 50, height: 50)
            
            // Main content: Title, preview, and time
            VStack(alignment: .leading, spacing: 4) {
                // Title and time row
                HStack(alignment: .top, spacing: 8) {
                    // Title with fade effect for long names
                    // Use geometry reader to calculate available width
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            FadingTitleText(
                                text: conversationTitle,
                                maxWidth: geometry.size.width - 60 // Reserve space for timestamp
                            )
                            .font(.body)
                            .fontWeight(conversationDetail.unreadCount > 0 ? .semibold : .regular)
                            .foregroundColor(.primary)
                            
                            Spacer(minLength: 8)
                        }
                    }
                    .frame(height: 20)
                    
                    // Time on right
                    if let lastMessage = conversationDetail.lastMessage {
                        Text(lastMessage.createdAt.timeAgoString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                // Message preview (up to 2 lines)
                HStack(alignment: .top, spacing: 8) {
                    // Preview text
                    if let lastMessage = conversationDetail.lastMessage {
                        Text(lastMessage.text)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Unread badge (if any)
                    if conversationDetail.unreadCount > 0 {
                        Text("\(conversationDetail.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.naarsPrimary)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Make entire row tappable
    }
    
    private var conversationTitle: String {
        // Priority 1: Group name (if conversation has a title)
        if let title = conversationDetail.conversation.title, !title.isEmpty {
            return title
        }
        
        // Priority 2: Participant names (comma-separated)
        if !conversationDetail.otherParticipants.isEmpty {
            let names = conversationDetail.otherParticipants.map { $0.name }
            return names.joined(separator: ", ")
        }
        
        // Fallback
        return "Unknown"
    }
}

/// Avatar view for conversations (single person or group)
struct ConversationAvatar: View {
    let conversationDetail: ConversationWithDetails
    
    var body: some View {
        Group {
            if conversationDetail.otherParticipants.count == 1, let participant = conversationDetail.otherParticipants.first {
                // Single person avatar
                AvatarView(
                    imageUrl: participant.avatarUrl,
                    name: participant.name,
                    size: 50
                )
            } else if conversationDetail.otherParticipants.count > 1 {
                // Group avatar (stacked or icon)
                ZStack {
                    Circle()
                        .fill(Color.naarsPrimary.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.naarsPrimary)
                        .font(.system(size: 20))
                }
            } else {
                // Default avatar
                AvatarView(imageUrl: nil, name: "Unknown", size: 50)
            }
        }
    }
}

/// Text view with fade effect for long content (iMessage-style)
/// Ensures text aligns left and fades to the right
struct FadingTitleText: View {
    let text: String
    let maxWidth: CGFloat
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Full text (starts from left, may overflow)
            Text(text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Overlay gradient for fade effect (on the right side)
            HStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemBackground).opacity(0), location: 0.0),
                        .init(color: Color(.systemBackground).opacity(0.5), location: 0.3),
                        .init(color: Color(.systemBackground), location: 0.8)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 40)
            }
            .allowsHitTesting(false)
        }
        .frame(width: maxWidth, alignment: .leading)
        .clipped()
    }
}

#Preview {
    ConversationsListView()
        .environmentObject(AppState())
}
