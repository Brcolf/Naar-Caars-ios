//
//  ConversationsListView.swift
//  NaarsCars
//
//  View for displaying list of conversations (iMessage-style)
//

import SwiftUI

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
                        }
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
                        if !selectedUserIds.isEmpty, let userId = selectedUserIds.first {
                            Task {
                                await createDirectConversation(with: userId)
                            }
                        }
                        showNewMessage = false
                        selectedUserIds = []
                    }
                )
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
        }
    }
    
    private func createDirectConversation(with userId: UUID) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            let conversation = try await MessageService.shared.getOrCreateDirectConversation(
                userId: currentUserId,
                otherUserId: userId
            )
            navigateToConversation = conversation.id
            // Reload conversations to show the new one
            await viewModel.loadConversations()
        } catch {
            print("🔴 Error creating direct conversation: \(error.localizedDescription)")
        }
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
                    FadingTitleText(
                        text: conversationTitle,
                        maxWidth: .infinity
                    )
                    .font(.body)
                    .fontWeight(conversationDetail.unreadCount > 0 ? .semibold : .regular)
                    .foregroundColor(.primary)
                    
                    Spacer()
                    
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
        // Priority 1: Request title (if activity-based)
        if let requestTitle = conversationDetail.requestTitle, !requestTitle.isEmpty {
            return requestTitle
        }
        
        // Priority 2: Group name (if conversation has a title)
        // Note: Conversation model doesn't currently have title field, so this is placeholder
        // if let title = conversationDetail.conversation.title, !title.isEmpty {
        //     return title
        // }
        
        // Priority 3: Participant names (comma-separated)
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
struct FadingTitleText: View {
    let text: String
    let maxWidth: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Fade gradient overlay (mask) on the right side
                if geometry.size.width > 0 {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.7),
                            .init(color: Color(.systemBackground), location: 1.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 20) // Fixed height for single line text
        .frame(maxWidth: maxWidth)
    }
}

#Preview {
    ConversationsListView()
        .environmentObject(AppState())
}
