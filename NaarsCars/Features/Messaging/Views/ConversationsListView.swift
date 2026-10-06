//
//  ConversationsListView.swift
//  NaarsCars
//
//  View for displaying list of conversations (iMessage-style)
//

import SwiftUI

/// View for displaying list of conversations
struct ConversationsListView: View {
    @State private var viewModel = ConversationsListViewModel()
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @Environment(AppState.self) var appState
    @State private var showNewMessage = false
    @State private var selectedUserIds: Set<UUID> = []
    /// Set only by the picker's Done button. A swipe-down or Cancel leaves it false, so
    /// dismissing the new-message sheet never creates a conversation by itself.
    @State private var didConfirmNewMessage = false
    /// True between Done and navigation, while the conversation is found or created.
    @State private var isOpeningConversation = false
    @State private var errorBannerMessage: String?
    @State private var selectedConversationId: UUID?
    /// Set once the pending-intent handler's `initial: true` pass has run. That pass is tied to
    /// the list appearing, so it comes round again on Back from a thread and on return to the
    /// tab; it must replay a pre-set intent only the first time.
    @State private var didReplayInitialIntent = false
    /// The message a tapped search hit points at, so its thread opens on that message
    /// instead of at the newest one. Dropped when the thread closes.
    @State private var searchHitTarget: SearchHitTarget?
    @State private var conversationToDelete: ConversationWithDetails?
    @State private var showDeleteConfirmation = false
    @State private var pinnedConversations: Set<UUID> = []
    @State private var toastMessage: String? = nil
    @State private var conversationToMute: UUID?
    @State private var showMutePicker = false
    /// The push prompt to show, if any. `.openSettings` when notifications are already denied
    /// in iOS Settings: the system dialog cannot be shown again, so the button opens Settings.
    @State private var pushPrompt: PushPromptMode?

    /// Whether the user is actively searching messages
    private var isMessageSearchActive: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .scrollContentBackground(.hidden)
            .background(Color.naarsBackground)
            .accessibilityLabel("messaging_loading_conversations_accessibility".localized)
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
                actionTitle: "messaging_new_message".localized,
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
        @Bindable var viewModel = viewModel
        List {
            // Show matching conversations first (by name)
            if !viewModel.filteredConversations.isEmpty {
                Section {
                    ForEach(viewModel.filteredConversations) { conversationDetail in
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
                    .accessibilityLabel("messaging_searching_messages".localized)
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
                            searchHitTarget = SearchHitTarget(
                                conversationId: result.conversationId,
                                messageId: result.message.id
                            )
                            selectedConversationId = result.conversationId
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
            } else if !viewModel.searchText.isEmpty && viewModel.filteredConversations.isEmpty {
                // No results at all
                VStack(spacing: Constants.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("messaging_search_no_results".localized(with: viewModel.searchText))
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
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
        .searchable(text: $viewModel.searchText, prompt: "messaging_search_prompt".localized)
    }

    @ViewBuilder
    private var conversationsList: some View {
        @Bindable var viewModel = viewModel
        let sorted = sortedConversations
        let pinnedRows = sorted.filter { pinnedConversations.contains($0.conversation.id) }
        let unpinnedRows = sorted.filter { !pinnedConversations.contains($0.conversation.id) }
        List {
            // Pinned section (only when a pinned conversation is actually visible — a blocked or
            // hidden pinned conversation must not leave an empty label behind)
            if !pinnedRows.isEmpty {
                Section {
                    sectionLabel("messaging_pinned")
                    ForEach(pinnedRows) { conversationDetail in
                        conversationRow(for: conversationDetail)
                    }
                }
            }

            // Main conversations section
            Section {
                // Only when both groups are on screen; a lone "All Messages" label is noise.
                if !pinnedRows.isEmpty && !unpinnedRows.isEmpty {
                    sectionLabel("messaging_all_messages")
                }
                ForEach(unpinnedRows) { conversationDetail in
                    conversationRow(for: conversationDetail)
                }
                
                // Bottom anchor for infinite scrolling. Invisible on purpose: the list simply ends
                // after the last conversation, as in iMessage (it used to show a paging spinner
                // and then a permanent "No more conversations" caption on every load).
                if viewModel.hasMoreConversations {
                    Color.clear
                        .frame(height: 1)
                        .accessibilityHidden(true)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .onAppear {
                            if !viewModel.isLoadingMore {
                                AppLogger.info("messaging", "[ConversationsList] Reached bottom, loading more conversations")
                                Task {
                                    await viewModel.loadMoreConversations()
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
        .searchable(text: $viewModel.searchText, prompt: "messaging_search_prompt".localized)
        .refreshable {
            await viewModel.refreshConversations()
        }
    }
    
    /// Sort conversations: pinned first, then by last update
    private var sortedConversations: [ConversationWithDetails] {
        viewModel.filteredConversations.sorted { a, b in
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
                        navigationCoordinator.pendingIntent = .notifications
                        AppLogger.info("messaging", "[ConversationsListView] Bell tapped")
                    }

                    if isOpeningConversation {
                        // Between Done and navigation the conversation is being found or created.
                        ProgressView()
                            .accessibilityLabel("common_loading".localized)
                    } else {
                        Button {
                            showNewMessage = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .id("messages.conversationsList.newMessageComposer")
                        .accessibilityLabel("messaging_new_message".localized)
                        .accessibilityIdentifier("messages.newMessage")
                    }
                }
            }
            .sheet(isPresented: $showNewMessage) {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    // Never offer the current user as a recipient: the participant insert
                    // fails and leaves an empty conversation behind.
                    excludeUserIds: [AuthService.shared.currentUserId].compactMap { $0 },
                    showExistingParticipants: false,
                    onDismiss: {
                        // Called by Done, and by Cancel after it has cleared the selection.
                        // A swipe-down calls neither, so it can only ever cancel.
                        didConfirmNewMessage = !selectedUserIds.isEmpty
                    }
                )
            }
            .onChange(of: showNewMessage) { _, isShowing in
                guard !isShowing else {
                    didConfirmNewMessage = false
                    return
                }
                // Only Done commits. Any other dismissal discards the selection.
                let recipientIds = didConfirmNewMessage ? Array(selectedUserIds) : []
                didConfirmNewMessage = false
                selectedUserIds = []
                guard !recipientIds.isEmpty else { return }
                Task {
                    isOpeningConversation = true
                    let openedId = await viewModel.createOrFindConversation(with: recipientIds)
                    isOpeningConversation = false
                    if let conversationId = openedId {
                        selectedConversationId = conversationId
                        // Reload conversations to show the new/updated one
                        await viewModel.loadConversations()
                    } else {
                        errorBannerMessage = "messaging_error_create_conversation".localized
                    }
                }
            }
            .navigationDestination(item: $selectedConversationId) { conversationId in
                ConversationDetailView(
                    conversationId: conversationId,
                    initialTitle: initialTitle(for: conversationId),
                    initialMessageId: searchHitTarget?.conversationId == conversationId ? searchHitTarget?.messageId : nil
                )
            }
            .onChange(of: selectedConversationId) { _, openConversationId in
                // Back on the list: the next open of that thread starts at the newest message.
                if openConversationId == nil {
                    searchHitTarget = nil
                }
            }
            // initial: true also opens a thread whose intent was set before this list existed (a
            // push tapped while the app was not running, or a push / toast tap before the Messages
            // tab was first opened); onChange alone never fires for a value that is already there.
            .onChange(of: navigationCoordinator.pendingIntent, initial: true) { oldIntent, intent in
                // Old and new are the same value only on the pass that initial: true adds.
                // Honoured once per view lifetime: an intent still waiting for its thread (the
                // scroll target is consumed only once messages have loaded) would otherwise
                // reopen that thread each time the list came back on screen.
                let isInitialPass = oldIntent == intent
                if isInitialPass {
                    guard !didReplayInitialIntent else { return }
                    didReplayInitialIntent = true
                }
                guard case .conversation(let conversationId, let scrollTarget) = intent else { return }
                if isInitialPass {
                    // One main-actor turn later: a push requested in the same update as the
                    // stack's first render can be dropped. Skipped if the intent was consumed or
                    // replaced meanwhile, so it is never applied twice. Same clearing rule as below.
                    Task { @MainActor in
                        guard navigationCoordinator.pendingIntent == intent else { return }
                        selectedConversationId = conversationId
                        if scrollTarget == nil {
                            navigationCoordinator.pendingIntent = nil
                        }
                    }
                    return
                }
                selectedConversationId = conversationId
                if scrollTarget == nil {
                    navigationCoordinator.pendingIntent = nil
                }
            }
            .alert("messaging_delete_conversation_title".localized, isPresented: $showDeleteConfirmation) {
                Button("common_cancel".localized, role: .cancel) {
                    conversationToDelete = nil
                }
                Button("common_delete".localized, role: .destructive) {
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
            .confirmationDialog("messaging_mute_notifications".localized, isPresented: $showMutePicker, titleVisibility: .visible) {
                ForEach(ConversationMuteService.MuteDuration.allCases, id: \.self) { duration in
                    Button(duration.displayName) {
                        guard let conversationId = conversationToMute else { return }
                        Task {
                            await viewModel.muteConversation(id: conversationId, duration: duration)
                            toastMessage = "messaging_toast_muted".localized
                        }
                    }
                }
                Button("common_cancel".localized, role: .cancel) {}
            }
            .task {
                viewModel.start()
                loadSavedPreferences()
                await viewModel.loadMutedConversations()
                await viewModel.loadConversations()
                // Check push status and show banner / start moderate poll if disabled
                await checkPushStatusAndStartPollIfNeeded()
            }
            .onDisappear { viewModel.stop() }
            .sheet(item: $pushPrompt) { mode in
                PushPermissionPromptView(
                    onAllow: {
                        Task {
                            let granted = await PushNotificationService.shared.requestPermission()
                            if granted {
                                viewModel.stopPushOffPoll()
                            }
                        }
                    },
                    onNotNow: {
                        // User declined — moderate poll continues as fallback
                    },
                    isPermissionDenied: mode == .openSettings
                )
            }
            .toast(message: $toastMessage)
            .errorBanner(message: $errorBannerMessage)
            .trackScreen("ConversationsList")
        }
    }
    
    // NOTE: Conversation deletion is implemented as a soft-delete.
    // The conversation is hidden from the user's list via UserDefaults,
    // but messages remain on the server for the other participants.
    // Deletion is handled by viewModel.deleteConversation(_:).
    
    /// Section label drawn as an ordinary row. A plain List pins `Section` headers to the top
    /// with no background, so "All Messages" floated over the avatars of the rows scrolling
    /// underneath it. As a row it scrolls away with the content.
    private func sectionLabel(_ key: String) -> some View {
        Text(key.localized)
            .font(.naarsCaption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    /// The name the list row already shows for a conversation, handed to the thread view so its
    /// header does not flash a generic title while the participants load.
    private func initialTitle(for conversationId: UUID) -> String? {
        guard let detail = viewModel.conversations.first(where: { $0.conversation.id == conversationId }) else {
            return nil
        }
        if let title = detail.conversation.title, !title.isEmpty {
            return title
        }
        let names = detail.otherParticipants.map { $0.name }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// Build a conversation row with swipe actions
    @ViewBuilder
    private func conversationRow(for conversationDetail: ConversationWithDetails) -> some View {
        let isPinned = pinnedConversations.contains(conversationDetail.conversation.id)
        let isMuted = viewModel.mutedConversations.contains(conversationDetail.conversation.id)
        
        Button {
            selectedConversationId = conversationDetail.conversation.id
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
                Label("common_delete".localized, systemImage: "trash")
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
                toastMessage = wasPinned ? "messaging_toast_unpinned".localized : "messaging_toast_pinned".localized
            } label: {
                Label(isPinned ? "messaging_unpin".localized : "messaging_pin".localized, systemImage: isPinned ? "pin.slash" : "pin")
            }
            .tint(.naarsWarning)
            
            // Mute/Unmute button
            Button {
                HapticManager.selectionChanged()
                if isMuted {
                    Task {
                        await viewModel.unmuteConversation(id: conversationDetail.conversation.id)
                        toastMessage = "messaging_toast_unmuted".localized
                    }
                } else {
                    conversationToMute = conversationDetail.conversation.id
                    showMutePicker = true
                }
            } label: {
                Label(isMuted ? "messaging_unmute".localized : "messaging_mute".localized, systemImage: isMuted ? "bell" : "bell.slash")
            }
            .tint(.gray)
        }
    }
    
    /// Save pinned conversations to UserDefaults
    private func savePinnedConversations() {
        let ids = pinnedConversations.map { $0.uuidString }
        UserDefaults.standard.set(ids, forKey: "pinnedConversations")
    }
    
    /// Load saved preferences
    private func loadSavedPreferences() {
        if let pinnedIds = UserDefaults.standard.array(forKey: "pinnedConversations") as? [String] {
            pinnedConversations = Set(pinnedIds.compactMap { UUID(uuidString: $0) })
        }
    }

    /// Check push notification status. If disabled, show a prompt (once per install)
    /// and start the conversations-only fallback poll, which the ViewModel owns and
    /// routes through RefreshCoordinator.
    private func checkPushStatusAndStartPollIfNeeded() async {
        let status = await PushNotificationService.shared.checkAuthorizationStatus()
        // The list's `.task` is cancelled when the user opens a thread while this is suspended.
        // Stop here so the prompt's one showing is not spent on top of that thread and the
        // poll is not started after `viewModel.stop()`; the next visit to the list runs it again.
        guard !Task.isCancelled else { return }
        let isEnabled = status == .authorized || status == .provisional

        guard !isEnabled else { return }

        // Show the prompt once per install. The flag is written when the prompt is shown, not
        // only on "Not Now": Enable followed by "Don't Allow" on the system dialog, or a
        // swipe-down, used to leave it unset and the sheet came back on every visit.
        let alreadyShown = UserDefaults.standard.bool(forKey: "pushPromptDismissedOnMessagesList")
        if !alreadyShown {
            UserDefaults.standard.set(true, forKey: "pushPromptDismissedOnMessagesList")
            pushPrompt = status == .denied ? .openSettings : .request
        }

        // Fallback poll while push is off and the user is on the messages tab
        viewModel.startPushOffPoll()
    }
}

/// What the push prompt on the Messages list offers: the system permission dialog, or, once
/// that has been declined, a link to the app's notification settings.
private enum PushPromptMode: String, Identifiable {
    case request
    case openSettings

    var id: String { rawValue }
}

/// A message found by the list's search, with the conversation it belongs to.
private struct SearchHitTarget {
    let conversationId: UUID
    let messageId: UUID
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
                .cardShadow()
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ConversationsListView()
        .environment(AppState())
}
