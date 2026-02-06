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
    @State private var pinnedConversations: Set<UUID> = []
    @State private var mutedConversations: Set<UUID> = []
    @State private var toastMessage: String? = nil
    
    /// Whether the user is actively searching messages
    private var isMessageSearchActive: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Filter conversations based on search (local name/title filtering)
    private var filteredConversations: [ConversationWithDetails] {
        if viewModel.searchText.isEmpty {
            return viewModel.conversations
        }
        let query = viewModel.searchText.lowercased()
        return viewModel.conversations.filter { convo in
            // Search in conversation title
            if let title = convo.conversation.title?.lowercased(),
               title.contains(query) {
                return true
            }
            // Search in participant names
            let participantNames = convo.otherParticipants.map { $0.name.lowercased() }
            if participantNames.contains(where: { $0.contains(query) }) {
                return true
            }
            // Search in last message
            if let lastMessage = convo.lastMessage?.text.lowercased(),
               lastMessage.contains(query) {
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
                title: "messaging_no_messages_yet".localized,
                message: "messaging_start_conversation_hint".localized,
                actionTitle: "New Message",
                action: {
                    showNewMessage = true
                },
                customImage: "naars_messages_icon"
            )
        } else if isMessageSearchActive {
            searchResultsList
        } else {
            conversationsList
        }
    }
    
    // MARK: - Search Results
    
    @ViewBuilder
    private var searchResultsList: some View {
        List {
            // Show matching conversations first (by name)
            if !filteredConversations.isEmpty {
                Section {
                    ForEach(filteredConversations) { conversationDetail in
                        conversationRow(for: conversationDetail)
                    }
                } header: {
                    Text("messaging_conversations".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Show message search results
            if viewModel.isSearching {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("messaging_searching_messages".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("messaging_messages".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            } else if !viewModel.searchResults.isEmpty {
                Section {
                    ForEach(viewModel.searchResults) { result in
                        Button {
                            navigateToConversation = result.conversationId
                        } label: {
                            MessageSearchResultRow(
                                result: result,
                                searchQuery: viewModel.searchText
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } header: {
                    Text("messaging_messages".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            } else if !viewModel.searchText.isEmpty && filteredConversations.isEmpty {
                // No results at all
                VStack(spacing: Constants.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("No results for \"\(viewModel.searchText)\"")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: "Search messages")
    }
    
    @ViewBuilder
    private var conversationsList: some View {
        List {
            // Pinned section (if any)
            if !pinnedConversations.isEmpty {
                Section {
                    ForEach(sortedConversations.filter { pinnedConversations.contains($0.conversation.id) }) { conversationDetail in
                        conversationRow(for: conversationDetail)
                    }
                } header: {
                    Text("messaging_pinned".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Main conversations section
            Section {
                ForEach(sortedConversations.filter { !pinnedConversations.contains($0.conversation.id) }) { conversationDetail in
                    conversationRow(for: conversationDetail)
                }
                
                // Bottom anchor for infinite scrolling
                if viewModel.hasMoreConversations {
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
                            AppLogger.info("messaging", "[ConversationsList] Reached bottom, loading more conversations")
                            Task {
                                await viewModel.loadMoreConversations()
                            }
                        }
                    }
                } else if !viewModel.hasMoreConversations && !viewModel.conversations.isEmpty {
                    // End of conversations indicator
                    Text("messaging_no_more_conversations".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .listRowSeparator(.hidden)
                }
            } header: {
                if !pinnedConversations.isEmpty {
                    Text("messaging_all_messages".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: "Search messages")
        .refreshable {
            await viewModel.refreshConversations()
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
                .navigationTitle("messaging_messages".localized)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    BellButton {
                        navigationCoordinator.navigateToNotifications = true
                        AppLogger.info("messaging", "[ConversationsListView] Bell tapped")
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
                    if let detail = conversationToDelete {
                        Task {
                            await viewModel.deleteConversation(detail.conversation)
                            toastMessage = "toast_conversation_hidden".localized
                        }
                    }
                    conversationToDelete = nil
                }
            } message: {
                Text("messaging_delete_conversation_message".localized)
            }
            .task {
                loadSavedPreferences()
                await viewModel.loadConversations()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("conversationUpdated"))) { _ in
                Task {
                    await viewModel.refreshConversations()
                }
            }
            .toast(message: $toastMessage)
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
        
        AppLogger.info("messaging", "[ConversationsListView] Looking for existing conversation with \(userIds.count) user(s)")
        
        do {
            let conversation: Conversation
            
            if userIds.count == 1 {
                // Direct message: getOrCreateDirectConversation already checks for existing
                AppLogger.info("messaging", "[ConversationsListView] Creating/finding direct message")
                conversation = try await ConversationService.shared.getOrCreateDirectConversation(
                    userId: currentUserId,
                    otherUserId: userIds[0]
                )
            } else {
                // Group conversation: Check if one exists with exactly these participants
                let allParticipantIds = Set([currentUserId] + userIds)
                
                AppLogger.info("messaging", "[ConversationsListView] Looking for group with participants: \(allParticipantIds.count) total")
                
                if let existingConversation = try await findExistingGroupConversation(participantIds: allParticipantIds) {
                    AppLogger.info("messaging", "[ConversationsListView] Found existing group conversation: \(existingConversation.id)")
                    conversation = existingConversation
                } else {
                    // Create new group conversation
                    AppLogger.info("messaging", "[ConversationsListView] Creating new group conversation")
                    conversation = try await ConversationService.shared.createConversationWithUsers(
                        userIds: Array(allParticipantIds),
                        createdBy: currentUserId,
                        title: nil // User can set group name later
                    )
                }
            }
            
            AppLogger.info("messaging", "[ConversationsListView] Navigating to conversation: \(conversation.id)")
            navigateToConversation = conversation.id
            
            // Reload conversations to show the new/updated one
            await viewModel.loadConversations()
        } catch {
            AppLogger.error("messaging", "[ConversationsListView] Error creating/navigating to conversation: \(error.localizedDescription)")
        }
    }
    
    /// Find existing group conversation with exact participant match
    private func findExistingGroupConversation(participantIds: Set<UUID>) async throws -> Conversation? {
        guard let currentUserId = AuthService.shared.currentUserId else { return nil }
        
        // Get all user's conversations
        let conversations = try await ConversationService.shared.fetchConversations(userId: currentUserId, limit: 100, offset: 0)
        
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
    
    // NOTE: Conversation deletion is implemented as a soft-delete.
    // The conversation is hidden from the user's list via UserDefaults,
    // but messages remain on the server for the other participants.
    // Deletion is handled by viewModel.deleteConversation(_:).
    
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
                HapticManager.selectionChanged()
                let wasPinned = isPinned
                withAnimation {
                    if wasPinned {
                        pinnedConversations.remove(conversationDetail.conversation.id)
                    } else {
                        pinnedConversations.insert(conversationDetail.conversation.id)
                    }
                }
                // Save to UserDefaults
                savePinnedConversations()
                toastMessage = wasPinned ? "Conversation unpinned" : "Conversation pinned"
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
            
            // Mute/Unmute button
            Button {
                HapticManager.selectionChanged()
                let wasMuted = isMuted
                withAnimation {
                    if wasMuted {
                        mutedConversations.remove(conversationDetail.conversation.id)
                    } else {
                        mutedConversations.insert(conversationDetail.conversation.id)
                    }
                }
                // Save to UserDefaults
                saveMutedConversations()
                toastMessage = wasMuted ? "Conversation unmuted" : "Conversation muted"
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
                    .font(.naarsSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(toast.messagePreview)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.naarsBackgroundSecondary)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ConversationsListView()
        .environmentObject(AppState())
}
