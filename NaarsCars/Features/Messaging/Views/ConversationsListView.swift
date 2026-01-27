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
    @State private var searchText = ""
    @State private var pinnedConversations: Set<UUID> = []
    @State private var mutedConversations: Set<UUID> = []
    @State private var toastDismissTask: Task<Void, Never>?
    
    /// Filter conversations based on search
    private var filteredConversations: [ConversationWithDetails] {
        if searchText.isEmpty {
            return viewModel.conversations
        }
        return viewModel.conversations.filter { convo in
            // Search in conversation title
            if let title = convo.conversation.title?.lowercased(),
               title.contains(searchText.lowercased()) {
                return true
            }
            // Search in participant names
            let participantNames = convo.otherParticipants.map { $0.name.lowercased() }
            if participantNames.contains(where: { $0.contains(searchText.lowercased()) }) {
                return true
            }
            // Search in last message
            if let lastMessage = convo.lastMessage?.text.lowercased(),
               lastMessage.contains(searchText.lowercased()) {
                return true
            }
            return false
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var mainContent: some View {
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
            conversationsList
        }
    }
    
    @ViewBuilder
    private var conversationsList: some View {
        List {
            // Pinned section (if any)
            if !pinnedConversations.isEmpty && searchText.isEmpty {
                Section {
                    ForEach(sortedConversations.filter { pinnedConversations.contains($0.conversation.id) }) { conversationDetail in
                        conversationRow(for: conversationDetail)
                    }
                } header: {
                    Text("Pinned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Main conversations section
            Section {
                ForEach(sortedConversations.filter { searchText.isEmpty ? !pinnedConversations.contains($0.conversation.id) : true }) { conversationDetail in
                    conversationRow(for: conversationDetail)
                }
                
                // Bottom anchor for infinite scrolling
                if viewModel.hasMoreConversations && searchText.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.vertical, 16)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .onAppear {
                        if !viewModel.isLoadingMore {
                            print("🔄 [ConversationsList] Reached bottom, loading more conversations")
                            Task {
                                await viewModel.loadMoreConversations()
                            }
                        }
                    }
                } else if !viewModel.hasMoreConversations && !viewModel.conversations.isEmpty && searchText.isEmpty {
                    // End of conversations indicator
                    Text("No more conversations")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .listRowSeparator(.hidden)
                }
            } header: {
                if !pinnedConversations.isEmpty && searchText.isEmpty {
                    Text("All Messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search messages")
        .refreshable {
            await viewModel.refreshConversations()
        }
    }
    
    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = viewModel.latestToast {
            Button {
                print("🔗 [ConversationsListView] Toast tapped for \(toast.conversationId)")
                navigationCoordinator.conversationScrollTarget = .init(
                    conversationId: toast.conversationId,
                    messageId: toast.messageId
                )
                viewModel.latestToast = nil
                navigationCoordinator.navigate(to: .conversation(id: toast.conversationId))
            } label: {
                InAppMessageToastView(toast: toast)
            }
            .buttonStyle(.plain)
            .id("messages.conversationsList.inAppToast")
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    /// Sort conversations: pinned first, then by last update
    private var sortedConversations: [ConversationWithDetails] {
        filteredConversations.sorted { a, b in
            let aPinned = pinnedConversations.contains(a.conversation.id)
            let bPinned = pinnedConversations.contains(b.conversation.id)
            
            if aPinned && !bPinned { return true }
            if !aPinned && bPinned { return false }
            
            return a.conversation.updatedAt > b.conversation.updatedAt
        }
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .id("messages.conversationsList")
                .navigationTitle("Messages")
                .overlay(alignment: .top) {
                    toastOverlay
                }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    BellButton {
                        navigationCoordinator.navigateToNotifications = true
                        print("🔔 [ConversationsListView] Bell tapped")
                    }

                    Button {
                        showNewMessage = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .id("messages.conversationsList.newMessageComposer")
                    .accessibilityIdentifier("messages.newMessage")
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
                loadSavedPreferences()
                await viewModel.loadConversations()
            }
            .onAppear {
                viewModel.setMessagesTabActive(navigationCoordinator.selectedTab == .messages)
            }
            .onChange(of: navigationCoordinator.selectedTab) { _, newTab in
                viewModel.setMessagesTabActive(newTab == .messages)
            }
            .onChange(of: viewModel.latestToast) { _, newToast in
                toastDismissTask?.cancel()
                guard newToast != nil else { return }
                toastDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    await MainActor.run {
                        viewModel.latestToast = nil
                    }
                }
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
    
    /// Build a conversation row with swipe actions
    @ViewBuilder
    private func conversationRow(for conversationDetail: ConversationWithDetails) -> some View {
        let isPinned = pinnedConversations.contains(conversationDetail.conversation.id)
        let isMuted = mutedConversations.contains(conversationDetail.conversation.id)
        
        NavigationLink {
            ConversationDetailView(conversationId: conversationDetail.conversation.id)
        } label: {
            ConversationRow(
                conversationDetail: conversationDetail,
                isMuted: isMuted
            )
        }
        .accessibilityIdentifier("messages.conversation.row")
        .id("messages.conversationsList.row(\(conversationDetail.conversation.id))")
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Delete button
            Button(role: .destructive) {
                conversationToDelete = conversationDetail
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Pin/Unpin button
            Button {
                withAnimation {
                    if isPinned {
                        pinnedConversations.remove(conversationDetail.conversation.id)
                    } else {
                        pinnedConversations.insert(conversationDetail.conversation.id)
                    }
                }
                // Save to UserDefaults
                savePinnedConversations()
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
            
            // Mute/Unmute button
            Button {
                withAnimation {
                    if isMuted {
                        mutedConversations.remove(conversationDetail.conversation.id)
                    } else {
                        mutedConversations.insert(conversationDetail.conversation.id)
                    }
                }
                // Save to UserDefaults
                saveMutedConversations()
            } label: {
                Label(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "bell" : "bell.slash")
            }
            .tint(.gray)
        }
    }
    
    /// Save pinned conversations to UserDefaults
    private func savePinnedConversations() {
        let ids = pinnedConversations.map { $0.uuidString }
        UserDefaults.standard.set(ids, forKey: "pinnedConversations")
    }
    
    /// Save muted conversations to UserDefaults
    private func saveMutedConversations() {
        let ids = mutedConversations.map { $0.uuidString }
        UserDefaults.standard.set(ids, forKey: "mutedConversations")
    }
    
    /// Load saved preferences
    private func loadSavedPreferences() {
        if let pinnedIds = UserDefaults.standard.array(forKey: "pinnedConversations") as? [String] {
            pinnedConversations = Set(pinnedIds.compactMap { UUID(uuidString: $0) })
        }
        if let mutedIds = UserDefaults.standard.array(forKey: "mutedConversations") as? [String] {
            mutedConversations = Set(mutedIds.compactMap { UUID(uuidString: $0) })
        }
    }
}

/// Conversation row component (iMessage-style)
struct ConversationRow: View {
    let conversationDetail: ConversationWithDetails
    var isMuted: Bool = false
    
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
                        HStack(spacing: 4) {
                            FadingTitleText(
                                text: conversationTitle,
                                maxWidth: geometry.size.width - (isMuted ? 80 : 60) // Reserve space for mute icon
                            )
                            .font(.body)
                            .fontWeight(conversationDetail.unreadCount > 0 ? .semibold : .regular)
                            .foregroundColor(.primary)
                            
                            // Muted indicator
                            if isMuted {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
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
                    // Preview text with icon for media messages
                    if let lastMessage = conversationDetail.lastMessage {
                        HStack(spacing: 4) {
                            // Show icon for media messages
                            if lastMessage.isAudioMessage {
                                Image(systemName: "waveform")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else if lastMessage.isLocationMessage {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else if lastMessage.imageUrl != nil && lastMessage.text.isEmpty {
                                Image(systemName: "photo")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(messagePreviewText(lastMessage))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
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
                            .background(isMuted ? Color.secondary : Color.naarsPrimary)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Make entire row tappable
    }
    
    /// Generate preview text for the message
    private func messagePreviewText(_ message: Message) -> String {
        if message.isAudioMessage {
            return "Voice message"
        } else if message.isLocationMessage {
            return message.locationName ?? "Shared location"
        } else if message.imageUrl != nil && message.text.isEmpty {
            return "Photo"
        } else {
            return message.text
        }
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

struct InAppMessageToastView: View {
    let toast: InAppMessageToast

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                imageUrl: toast.senderAvatarUrl,
                name: toast.senderName,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.senderName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(toast.messagePreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
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
                // Group avatar
                groupAvatarView
            } else {
                // Default avatar
                AvatarView(imageUrl: nil, name: "Unknown", size: 50)
            }
        }
    }
    
    @ViewBuilder
    private var groupAvatarView: some View {
        // Check if group has a custom image
        if let groupImageUrl = conversationDetail.conversation.groupImageUrl,
           let url = URL(string: groupImageUrl) {
            // Show custom group image
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    defaultGroupAvatar
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                case .failure:
                    defaultGroupAvatar
                @unknown default:
                    defaultGroupAvatar
                }
            }
        } else if conversationDetail.otherParticipants.count >= 2 {
            // Show stacked avatars (2 participants)
            stackedAvatarsView
        } else {
            defaultGroupAvatar
        }
    }
    
    private var stackedAvatarsView: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
            
            // First participant (bottom-right)
            if let first = conversationDetail.otherParticipants.first {
                AvatarView(
                    imageUrl: first.avatarUrl,
                    name: first.name,
                    size: 30
                )
                .offset(x: 8, y: 8)
            }
            
            // Second participant (top-left)
            if conversationDetail.otherParticipants.count > 1 {
                let second = conversationDetail.otherParticipants[1]
                AvatarView(
                    imageUrl: second.avatarUrl,
                    name: second.name,
                    size: 30
                )
                .offset(x: -8, y: -8)
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                        .frame(width: 30, height: 30)
                        .offset(x: -8, y: -8)
                )
            }
            
            // Show +N badge if more than 2 other participants
            if conversationDetail.otherParticipants.count > 2 {
                Text("+\(conversationDetail.otherParticipants.count - 2)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.naarsPrimary)
                    .clipShape(Circle())
                    .offset(x: 16, y: -16)
            }
        }
        .frame(width: 50, height: 50)
    }
    
    private var defaultGroupAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.naarsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
            
            Image(systemName: "person.2.fill")
                .foregroundColor(.naarsPrimary)
                .font(.system(size: 20))
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
