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
    @State private var lastRefreshTime = Date.distantPast
    
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
                        // Removed verbose logging
                        
                        // Capture the selected IDs before clearing
                        let selectedIds = Array(selectedUserIds)
                        
                        // Clear state immediately
                        showNewMessage = false
                        selectedUserIds = []
                        
                        // Use captured IDs in async task
                        if !selectedIds.isEmpty {
                            Task {
                                if selectedIds.count == 1 {
                                    // Direct message (1-on-1)
                                    await createDirectConversation(with: selectedIds.first!)
                                } else {
                                    // Group conversation (2+ selected users)
                                    await createGroupConversation(with: selectedIds)
                                }
                            }
                        }
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
                // Initial load when view is first created
                // Removed verbose logging
                await refreshConversationsIfNeeded(force: false)
            }
            .onAppear {
                // Do NOT refresh on appear - .task{} already handles initial load
                // Removed verbose logging
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("conversationUpdated"))) { notification in
                Task {
                    // Removed verbose logging
                    await refreshConversationsIfNeeded(force: true)
                }
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
            
            // Post notification to refresh conversations list
            NotificationCenter.default.post(
                name: NSNotification.Name("conversationUpdated"),
                object: conversation.id
            )
            
            navigateToConversation = conversation.id
            
            // Reload conversations to show the new one
            await refreshConversationsIfNeeded(force: true)
        } catch {
            print("🔴 Error creating direct conversation: \(error.localizedDescription)")
        }
    }
    
    private func createGroupConversation(with userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId else {
            print("🔴 [ConversationsListView] No current user ID")
            return
        }
        
        do {
            // Include current user in the conversation
            var allUserIds = userIds
            if !allUserIds.contains(currentUserId) {
                allUserIds.append(currentUserId)
            }
            
            // Create group conversation without a title (users can add one later)
            let conversation = try await MessageService.shared.createConversationWithUsers(
                userIds: allUserIds,
                createdBy: currentUserId,
                title: nil
            )
            
            // Post notification to refresh conversations list
            NotificationCenter.default.post(
                name: NSNotification.Name("conversationUpdated"),
                object: conversation.id
            )
            
            navigateToConversation = conversation.id
            
            // Reload conversations to show the new one
            await refreshConversationsIfNeeded(force: true)
            
        } catch {
            print("🔴 [ConversationsListView] Error creating group conversation: \(error.localizedDescription)")
            // TODO: Show error alert to user
        }
    }
    
    private func deleteConversation(_ conversation: ConversationWithDetails) async {
        // Clean up display name cache
        await ConversationDisplayNameCache.shared.removeDisplayName(for: conversation.id)
        
        // TODO: Implement conversation deletion in MessageService
        // For now, just reload conversations to remove deleted one
        await refreshConversationsIfNeeded(force: true)
    }
    
    /// Smart refresh with debouncing to avoid duplicate loads
    /// - Parameter force: If true, always refresh. If false, debounce within 2 seconds.
    private func refreshConversationsIfNeeded(force: Bool) async {
        let now = Date()
        let timeSinceLastRefresh = now.timeIntervalSince(lastRefreshTime)
        
        // If less than 2 seconds since last refresh and not forced, skip
        guard force || timeSinceLastRefresh > 2.0 else {
            // Removed verbose logging - only log for debugging when needed
            return
        }
        
        // Removed verbose logging
        lastRefreshTime = now
        
        // No cache invalidation needed - conversations are always fetched fresh
        await viewModel.loadConversations()
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
                    FadingTitleText(text: conversationTitle)
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
        // Priority 1: Use cached display name (local-first, instant)
        if let cachedName = conversationDetail.conversation.cachedDisplayName, !cachedName.isEmpty {
            return cachedName
        }
        
        // Priority 2: Compute from current data if available
        if let title = conversationDetail.conversation.title, !title.isEmpty {
            return title
        }
        
        if !conversationDetail.otherParticipants.isEmpty {
            let names = conversationDetail.otherParticipants.map { $0.name }
            return ListFormatter.localizedString(byJoining: names)
        }
        
        // Priority 3: Show "Loading..." if name is being computed
        return "Loading..."
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
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Full text - let it take available width, truncate with fade
            Text(text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Overlay gradient for fade effect (only on right side)
            HStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemBackground).opacity(0), location: 0.0),
                        .init(color: Color(.systemBackground).opacity(0.3), location: 0.5),
                        .init(color: Color(.systemBackground), location: 1.0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 40)
            }
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    ConversationsListView()
        .environmentObject(AppState())
}
