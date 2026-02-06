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
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
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
    @State private var showReactionDetails = false
    @State private var reactionDetailsMessage: Message?
    @State private var reactionProfiles: [String: [Profile]] = [:]
    @State private var highlightedMessageId: UUID?
    
    // Scroll-to-bottom state
    @State private var showScrollToBottom = false
    @State private var newMessageIds: Set<UUID> = []
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isAtBottom = true
    
    // Reply state
    @State private var replyingToMessage: ReplyContext?
    
    // Thread view state
    @State private var activeThreadParent: ThreadParent?
    
    // Image viewer state
    @State private var selectedImageUrl: URL?
    @State private var showImageViewer = false
    
    // Report state
    @State private var showReportSheet = false
    @State private var messageToReport: Message?
    
    // Unsend confirmation state
    @State private var showUnsendConfirmation = false
    @State private var messageToUnsend: Message?
    
    // Toast state
    @State private var toastMessage: String? = nil
    
    
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

    private var threadAnchorId: String {
        "messages.thread(\(conversationId))"
    }

    private var threadBottomAnchorId: String {
        "messages.thread.bottom"
    }

    private func messageAnchorId(_ messageId: UUID) -> String {
        "messages.thread.message(\(messageId))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // In-conversation search bar
            if viewModel.isSearchActive {
                ConversationSearchBar(viewModel: viewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            messagesListView

            // Typing indicator
            if !viewModel.typingUsers.isEmpty {
                TypingIndicatorView(typingUsers: viewModel.typingUsers)
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.typingUsers.count)
            }

            // Input bar
            MessageInputBar(
                text: $viewModel.messageText,
                imageToSend: $imageToSend,
                onSend: {
                    if viewModel.editingMessage != nil {
                        // Submit edit
                        let editedText = viewModel.messageText
                        Task {
                            await viewModel.editMessage(newContent: editedText)
                            if viewModel.error == nil {
                                toastMessage = "toast_message_edited".localized
                            }
                        }
                    } else {
                        // Normal send
                        let textToSend = viewModel.messageText
                        viewModel.messageText = ""
                        viewModel.clearOwnTypingStatus()
                        Task {
                            await viewModel.sendMessage(textOverride: textToSend, image: imageToSend, replyToId: replyingToMessage?.id)
                            imageToSend = nil
                            // Clear reply context after sending
                            withAnimation(.easeOut(duration: 0.2)) {
                                replyingToMessage = nil
                            }
                        }
                    }
                },
                onImagePickerTapped: {
                    showImagePicker = true
                },
                isDisabled: viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageToSend == nil,
                replyingTo: replyingToMessage,
                onCancelReply: {
                    replyingToMessage = nil
                },
                editingMessage: viewModel.editingMessage,
                onCancelEdit: {
                    viewModel.cancelEdit()
                },
                onAudioRecorded: { audioURL, duration in
                    viewModel.clearOwnTypingStatus()
                    Task {
                        await viewModel.sendAudioMessage(audioURL: audioURL, duration: duration, replyToId: replyingToMessage?.id)
                        withAnimation(.easeOut(duration: 0.2)) {
                            replyingToMessage = nil
                        }
                    }
                },
                onLocationShare: { latitude, longitude, name in
                    viewModel.clearOwnTypingStatus()
                    Task {
                        await viewModel.sendLocationMessage(latitude: latitude, longitude: longitude, locationName: name, replyToId: replyingToMessage?.id)
                        withAnimation(.easeOut(duration: 0.2)) {
                            replyingToMessage = nil
                        }
                    }
                },
                onTypingChanged: {
                    viewModel.userDidType()
                }
            )
        }
        .id(threadAnchorId)
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Media gallery button
                NavigationLink {
                    ConversationMediaGalleryView(conversationId: conversationId)
                } label: {
                    Image(systemName: "photo.on.rectangle")
                }
                .accessibilityLabel("Media")
                
                // Search button
                Button {
                    viewModel.toggleSearch()
                } label: {
                    Image(systemName: viewModel.isSearchActive ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(viewModel.isSearchActive ? "Close search" : "Search messages")
                
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
                currentGroupImageUrl: conversationDetail?.conversation.groupImageUrl,
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
        .fullScreenCover(item: $activeThreadParent) { parent in
            MessageThreadView(
                conversationId: conversationId,
                parentMessageId: parent.id,
                conversationViewModel: viewModel,
                isGroup: isGroup,
                totalParticipants: totalParticipantsCount
            )
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
            NotificationCenter.default.post(
                name: .messageThreadDidAppear,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
            // Mark as read and update last_seen when view appears
            // This prevents push notifications when user is actively viewing
            Task {
                if let userId = AuthService.shared.currentUserId {
                    // Update last_seen first to mark user as actively viewing
                    try? await MessageService.shared.updateLastSeen(conversationId: conversationId, userId: userId)
                }
            }
            // Start observing typing indicators
            viewModel.startTypingObservation()
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .messageThreadDidDisappear,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
            // Stop observing typing indicators
            viewModel.stopTypingObservation()
        }
        .onChange(of: viewModel.currentSearchResultId) { _, resultId in
            if let messageId = resultId {
                scrollToMessage(messageId)
            }
        }
        .toast(message: $toastMessage)
        .trackScreen("ConversationDetail")
        .fullScreenCover(isPresented: $showImageViewer) {
            if let imageUrl = selectedImageUrl {
                fullscreenImageViewer(imageUrl: imageUrl)
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let message = messageToReport {
                ReportMessageSheet(
                    message: message,
                    onSubmit: { reportType, description in
                        Task {
                            await submitReport(message: message, type: reportType, description: description)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showReactionDetails) {
            if let message = reactionDetailsMessage, let reactions = message.reactions {
                ReactionDetailsSheet(
                    message: message,
                    reactions: reactions,
                    profilesByReaction: reactionProfiles,
                    onRemoveReaction: { reaction in
                        Task {
                            await viewModel.removeReaction(messageId: message.id)
                            await refreshReactionProfiles(for: message)
                        }
                    }
                )
            }
        }
        .alert("Unsend Message", isPresented: $showUnsendConfirmation) {
            Button("Cancel", role: .cancel) {
                messageToUnsend = nil
            }
            Button("Unsend", role: .destructive) {
                if let message = messageToUnsend {
                    Task {
                        await viewModel.unsendMessage(id: message.id)
                        if viewModel.error == nil {
                            toastMessage = "toast_message_unsent".localized
                        }
                    }
                    messageToUnsend = nil
                }
            }
        } message: {
            Text("messaging_unsend_confirmation_message".localized)
        }
    }
    
    /// Submit a report for a message
    private func submitReport(message: Message, type: MessageService.ReportType, description: String?) async {
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            try await MessageService.shared.reportMessage(
                reporterId: userId,
                messageId: message.id,
                type: type,
                description: description
            )
            
            messageToReport = nil
        } catch {
            AppLogger.error("messaging", "Error submitting report: \(error.localizedDescription)")
        }
    }
    
    private func isFromCurrentUser(_ message: Message) -> Bool {
        message.fromId == AuthService.shared.currentUserId
    }
    
    /// Check if this is a group conversation (more than 2 participants)
    private var isGroup: Bool {
        participantsViewModel.participants.count > 2
    }

    private var totalParticipantsCount: Int {
        max(
            participantsViewModel.participants.count,
            (conversationDetail?.otherParticipants.count ?? 0) + 1
        )
    }
    
    /// Create a message bubble with all handlers
    @ViewBuilder
    private func createMessageBubble(
        message: Message,
        isFirst: Bool,
        isLast: Bool,
        replyChain: ReplyChainContext? = nil
    ) -> some View {
        MessageBubble(
            message: message,
            isFromCurrentUser: isFromCurrentUser(message),
            showAvatar: isGroup && !isFromCurrentUser(message),
            isFirstInSeries: isFirst,
            isLastInSeries: isLast,
            shouldAnimate: newMessageIds.contains(message.id),
            totalParticipants: totalParticipantsCount,
            replySpine: replyChain.map { (showTop: $0.hasPrevious, showBottom: $0.hasNext) },
            isFailed: viewModel.failedMessageIds.contains(message.id),
            onLongPress: {
                reactionPickerMessageId = message.id
                showReactionPicker = true
            },
            onReactionTap: { reaction in
                showReactionDetails(for: message)
            },
            onReply: {
                withAnimation(.easeOut(duration: 0.2)) {
                    replyingToMessage = ReplyContext(from: message)
                }
            },
            onEdit: isFromCurrentUser(message) ? {
                withAnimation(.easeOut(duration: 0.2)) {
                    replyingToMessage = nil // Clear reply if active
                    viewModel.startEditing(message)
                }
            } : nil,
            onUnsend: isFromCurrentUser(message) && message.canUnsend ? {
                showUnsendConfirmation = true
                messageToUnsend = message
            } : nil,
            onImageTap: { imageUrl in
                selectedImageUrl = imageUrl
                showImageViewer = true
            },
            onReport: {
                messageToReport = message
                showReportSheet = true
            },
            onReplyPreviewTap: { replyId in
                activeThreadParent = ThreadParent(id: replyId)
            },
            onRetry: {
                Task {
                    await viewModel.retryMessage(id: message.id)
                }
            },
            isHighlighted: highlightedMessageId == message.id
        )
    }
    

    private var messagesListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    messagesHeaderView
                    messagesBodyView
                    messagesBottomSpacerView
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .accessibilityIdentifier("messages.thread.scroll")
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: isInputFocused) { _, isFocused in
                if isFocused {
                    // Scroll to bottom when keyboard appears
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // Reduced delay for snappier feel
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(threadBottomAnchorId, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                // Track new messages for animation
                if newCount > oldCount {
                    let newMessages = viewModel.messages.suffix(newCount - oldCount)
                    for message in newMessages {
                        newMessageIds.insert(message.id)
                    }
                    // Clear animation flags after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        newMessageIds.removeAll()
                    }
                }

                // Always scroll to bottom when a new message is sent by current user
                let lastMessageIsFromMe = viewModel.messages.last.map { $0.fromId == AuthService.shared.currentUserId } ?? false

                if (isAtBottom || lastMessageIsFromMe) && !viewModel.isLoadingMore {
                    if let lastMessage = viewModel.messages.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(messageAnchorId(lastMessage.id), anchor: .bottom)
                        }
                    }
                    showScrollToBottom = false
                    AppLogger.info("messaging", "[ConversationDetail] Auto-scroll to bottom")
                } else if newCount > oldCount {
                    showScrollToBottom = true
                    AppLogger.info("messaging", "[ConversationDetail] New messages while scrolled up")
                }

                // Update last_seen when new messages arrive while viewing
                Task {
                    if let userId = AuthService.shared.currentUserId {
                        try? await MessageService.shared.updateLastSeen(conversationId: conversationId, userId: userId)
                    }
                }

                handleConversationScrollTarget(with: proxy)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Scroll to bottom button
            if showScrollToBottom {
                ScrollToBottomButton(
                    unreadCount: viewModel.unreadCount,
                    action: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            scrollProxy?.scrollTo(threadBottomAnchorId, anchor: .bottom)
                        }
                        showScrollToBottom = false
                    }
                )
                .id("messages.thread.scrollToBottomButton")
                .padding(.trailing, 16)
                .padding(.bottom, 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            // Reaction picker overlay (centered on screen)
            if showReactionPicker {
                VStack {
                    Spacer()
                    ReactionPicker(
                        onReactionSelected: { reaction in
                            HapticManager.selectionChanged()
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
    }

    @ViewBuilder
    private var messagesHeaderView: some View {
        // Top anchor for infinite scrolling
        Color.clear
            .frame(height: 2)
            .onAppear {
                if viewModel.hasMoreMessages && !viewModel.messages.isEmpty && !viewModel.isLoadingMore {
                    AppLogger.info("messaging", "[ConversationDetail] Reached top, loading more messages")
                    Task {
                        await viewModel.loadMoreMessages()
                    }
                }
            }

        // No more messages indicator
        if !viewModel.hasMoreMessages && !viewModel.messages.isEmpty {
            VStack(spacing: Constants.Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                Text("messaging_beginning_of_conversation".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }

        if viewModel.isLoadingMore {
            ProgressView()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var messagesBodyView: some View {
        if viewModel.isLoading && viewModel.messages.isEmpty {
            ProgressView()
                .padding()
        } else if viewModel.messages.isEmpty {
            VStack(spacing: Constants.Spacing.md) {
                Image(systemName: "message.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                Text("messaging_no_messages_yet".localized)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                Text("messaging_start_the_conversation".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                let isFirst = isFirstInSeries(at: index)
                let isLast = isLastInSeries(at: index)
                let shouldShowDateSeparator = shouldShowDateSeparator(at: index)
                let replyChain = replyChainContext(at: index)

                VStack(spacing: 0) {
                    // Date separator
                    if shouldShowDateSeparator {
                        DateSeparatorView(date: message.createdAt)
                            .padding(.vertical, 16)
                    }

                    createMessageBubble(
                        message: message,
                        isFirst: isFirst,
                        isLast: isLast,
                        replyChain: replyChain
                    )
                }
                .id(messageAnchorId(message.id))
            }
        }
    }

    

    private var messagesBottomSpacerView: some View {
        // Invisible spacer at bottom for scroll detection
        Color.clear
            .frame(height: 1)
            .id(threadBottomAnchorId)
            .onAppear {
                isAtBottom = true
                showScrollToBottom = false
            }
            .onDisappear {
                isAtBottom = false
            }
    }

    private func showReactionDetails(for message: Message) {
        reactionDetailsMessage = message
        showReactionDetails = true
        Task {
            await refreshReactionProfiles(for: message)
        }
    }
    
    private func refreshReactionProfiles(for message: Message) async {
        guard let reactions = message.reactions else {
            reactionProfiles = [:]
            return
        }
        
        let userIds = Array(reactions.allUserIds)
        let profiles = await withTaskGroup(of: Profile?.self) { group in
            for userId in userIds {
                group.addTask {
                    try? await ProfileService.shared.fetchProfile(userId: userId)
                }
            }
            var results: [Profile] = []
            for await profile in group {
                if let profile = profile {
                    results.append(profile)
                }
            }
            return results
        }
        
        let profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        var mapped: [String: [Profile]] = [:]
        for (reaction, userIds) in reactions.reactions {
            mapped[reaction] = userIds.compactMap { profilesById[$0] }
        }
        reactionProfiles = mapped
    }
    
    private func scrollToMessage(_ messageId: UUID) {
        guard viewModel.messages.contains(where: { $0.id == messageId }) else { return }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollProxy?.scrollTo(messageAnchorId(messageId), anchor: .center)
        }
        highlightedMessageId = messageId
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if highlightedMessageId == messageId {
                highlightedMessageId = nil
            }
        }
    }

    private func handleConversationScrollTarget(with proxy: ScrollViewProxy) {
        guard let target = navigationCoordinator.conversationScrollTarget,
              target.conversationId == conversationId else {
            return
        }

        navigationCoordinator.conversationScrollTarget = nil
        showScrollToBottom = false
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(threadBottomAnchorId, anchor: .bottom)
        }
    }
    
    /// Check if message is the first in a consecutive series from the same sender
    private func isFirstInSeries(at index: Int) -> Bool {
        MessageSeriesHelper.isFirstInSeries(messages: viewModel.messages, at: index)
    }
    
    /// Check if message is the last in a consecutive series from the same sender
    private func isLastInSeries(at index: Int) -> Bool {
        MessageSeriesHelper.isLastInSeries(messages: viewModel.messages, at: index)
    }

    private struct ReplyChainContext {
        let hasPrevious: Bool
        let hasNext: Bool
    }

    private func replyChainContext(at index: Int) -> ReplyChainContext? {
        let currentMessage = viewModel.messages[index]
        guard let replyToId = currentMessage.replyToId else { return nil }

        let hasPrevious = index > 0 && viewModel.messages[index - 1].replyToId == replyToId
        let hasNext = index < viewModel.messages.count - 1 && viewModel.messages[index + 1].replyToId == replyToId

        return ReplyChainContext(hasPrevious: hasPrevious, hasNext: hasNext)
    }
    
    /// Check if we should show a date separator before this message
    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true } // Always show for first message
        
        let currentMessage = viewModel.messages[index]
        let previousMessage = viewModel.messages[index - 1]
        
        // Check if different day
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: currentMessage.createdAt)
        let previousDay = calendar.startOfDay(for: previousMessage.createdAt)
        
        return currentDay != previousDay
    }
    
    // MARK: - Inline Typing Indicator
    
    // MARK: - Inline Image Viewer
    
    @ViewBuilder
    private func fullscreenImageViewer(imageUrl: URL) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        Text("messaging_failed_to_load_image".localized)
                            .foregroundColor(.white.opacity(0.6))
                    }
                default:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    ShareLink(item: imageUrl) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.naarsCallout).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: {
                        showImageViewer = false
                        selectedImageUrl = nil
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
    
    private func addParticipants(_ userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            try await ConversationParticipantService.shared.addParticipantsToConversation(
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
            AppLogger.error("messaging", "Error adding participants: \(error.localizedDescription)")
        }
    }
    
    private func loadConversationDetails() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            let conversations = try await ConversationService.shared.fetchConversations(userId: userId, limit: 100, offset: 0)
            if let detail = conversations.first(where: { $0.conversation.id == conversationId }) {
                conversationDetail = detail
            }
        } catch {
            AppLogger.error("messaging", "Error loading conversation details: \(error.localizedDescription)")
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
            // 1. First try to load from local SwiftData for instant UI
            if let sdConv = try? await MessagingRepository.shared.fetchSDConversation(id: conversationId) {
                var localProfiles: [Profile] = []
                for userId in sdConv.participantIds {
                    if let profile = await CacheManager.shared.getCachedProfile(id: userId) {
                        localProfiles.append(profile)
                    }
                }
                
                if !localProfiles.isEmpty {
                    self.participants = localProfiles
                }
            }

            // 2. Fetch fresh participant user IDs from network
            let response = try await SupabaseService.shared.client
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .is("left_at", value: nil) // ONLY active participants
                .execute()
            
            struct ParticipantRow: Codable {
                let userId: UUID
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                }
            }
            
            let rows = try JSONDecoder().decode([ParticipantRow].self, from: response.data)
            let freshParticipantIds = rows.map { $0.userId }

            // 3. Update local SwiftData participant list
            if let sdConv = try? await MessagingRepository.shared.fetchSDConversation(id: conversationId) {
                sdConv.participantIds = freshParticipantIds
                try? await MessagingRepository.shared.save()
            }
            
            // 4. Fetch profiles for each participant
            let existingParticipants = participants
            var profiles: [Profile] = []
            for userId in freshParticipantIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                    profiles.append(profile)
                } else if let existing = existingParticipants.first(where: { $0.id == userId }) {
                    profiles.append(existing)
                }
            }

            if !profiles.isEmpty || freshParticipantIds.isEmpty {
                self.participants = profiles
            }
        } catch {
            self.error = AppError.processingError("Failed to load participants: \(error.localizedDescription)")
            AppLogger.error("messaging", "Error loading participants: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}

// MARK: - Date Separator View

/// Shows a date separator between messages from different days
struct DateSeparatorView: View {
    let date: Date
    
    private var dateText: String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            // Same week - show day name
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            // Same year
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: date)
        } else {
            // Different year
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        HStack {
            VStack { Divider() }
            
            Text(dateText)
                .font(.naarsFootnote).fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.naarsCardBackground)
                )
            
            VStack { Divider() }
        }
        .padding(.horizontal)
    }
}

// MARK: - Reply Thread Spine

struct ReplyThreadSpineView: View {
    let showTop: Bool
    let showBottom: Bool

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let topInset = showTop ? 0 : height * 0.35
            let bottomInset = showBottom ? height : height * 0.65

            Path { path in
                let x = geometry.size.width / 2
                path.move(to: CGPoint(x: x, y: topInset))
                path.addLine(to: CGPoint(x: x, y: bottomInset))
            }
            .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}


// MARK: - Thread View

private struct ThreadParent: Identifiable {
    let id: UUID
}

@MainActor
final class MessageThreadViewModel: ObservableObject {
    @Published var parentMessage: Message?
    @Published var replies: [Message] = []
    @Published var isLoading = false
    @Published var error: AppError?

    private let conversationId: UUID
    private let parentMessageId: UUID
    private let messageService = MessageService.shared

    init(conversationId: UUID, parentMessageId: UUID) {
        self.conversationId = conversationId
        self.parentMessageId = parentMessageId
    }

    func loadThread(seedMessages: [Message] = []) async {
        isLoading = true
        error = nil

        if let seedParent = seedMessages.first(where: { $0.id == parentMessageId }) {
            parentMessage = seedParent
        }

        if replies.isEmpty {
            replies = seedMessages.filter { $0.replyToId == parentMessageId }
        }

        do {
            parentMessage = try await messageService.fetchMessageById(parentMessageId)
            replies = try await messageService.fetchReplies(
                conversationId: conversationId,
                replyToId: parentMessageId
            )
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
        }

        isLoading = false
    }

    func mergeReplies(from messages: [Message]) {
        if let parent = messages.first(where: { $0.id == parentMessageId }) {
            parentMessage = parent
        }

        let matching = messages.filter { $0.replyToId == parentMessageId }
        guard !matching.isEmpty else { return }

        var merged = replies
        let existingIds = Set(merged.map { $0.id })
        for message in matching where !existingIds.contains(message.id) {
            merged.append(message)
        }
        merged.sort { $0.createdAt < $1.createdAt }
        replies = merged
    }
}

struct MessageThreadView: View {
    let conversationId: UUID
    let parentMessageId: UUID
    @ObservedObject var conversationViewModel: ConversationDetailViewModel
    let isGroup: Bool
    let totalParticipants: Int

    @StateObject private var viewModel: MessageThreadViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @State private var imageToSend: UIImage?
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?

    init(
        conversationId: UUID,
        parentMessageId: UUID,
        conversationViewModel: ConversationDetailViewModel,
        isGroup: Bool,
        totalParticipants: Int
    ) {
        self.conversationId = conversationId
        self.parentMessageId = parentMessageId
        self.conversationViewModel = conversationViewModel
        self.isGroup = isGroup
        self.totalParticipants = totalParticipants
        _viewModel = StateObject(wrappedValue: MessageThreadViewModel(
            conversationId: conversationId,
            parentMessageId: parentMessageId
        ))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                threadHeader
                Divider()
                threadContent
                Divider()
                MessageInputBar(
                    text: $messageText,
                    imageToSend: $imageToSend,
                    onSend: {
                        let textToSend = messageText
                        let image = imageToSend
                        messageText = ""
                        imageToSend = nil
                        Task {
                            await conversationViewModel.sendMessage(
                                textOverride: textToSend,
                                image: image,
                                replyToId: parentMessageId
                            )
                        }
                    },
                    onImagePickerTapped: {
                        showImagePicker = true
                    },
                    isDisabled: !hasParentMessage || (messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageToSend == nil),
                    replyingTo: nil,
                    onCancelReply: nil,
                    onAudioRecorded: { audioURL, duration in
                        Task {
                            await conversationViewModel.sendAudioMessage(
                                audioURL: audioURL,
                                duration: duration,
                                replyToId: parentMessageId
                            )
                        }
                    },
                    onLocationShare: { latitude, longitude, name in
                        Task {
                            await conversationViewModel.sendLocationMessage(
                                latitude: latitude,
                                longitude: longitude,
                                locationName: name,
                                replyToId: parentMessageId
                            )
                        }
                    }
                )
            }
            .background(.ultraThinMaterial)
        }
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedImage,
            matching: .images
        )
        .onChange(of: selectedImage) { _, newValue in
            Task {
                if let item = newValue, let data = try? await item.loadTransferable(type: Data.self) {
                    imageToSend = UIImage(data: data)
                } else {
                    imageToSend = nil
                }
            }
        }
        .task {
            await viewModel.loadThread(seedMessages: conversationViewModel.messages)
        }
        .onReceive(conversationViewModel.$messages) { messages in
            viewModel.mergeReplies(from: messages)
        }
    }

    private var hasParentMessage: Bool {
        viewModel.parentMessage != nil
    }

    private var threadHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.naarsCallout).fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            Spacer()
            Text("messaging_thread".localized)
                .font(.naarsBody)
                .fontWeight(.semibold)
            Spacer()
            Color.clear.frame(width: 24)
        }
        .padding()
    }

    private var threadContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    parentMessageView

                    if !viewModel.replies.isEmpty {
                        ForEach(Array(viewModel.replies.enumerated()), id: \.element.id) { index, message in
                            let isFirst = isFirstInSeries(messages: viewModel.replies, index: index)
                            let isLast = isLastInSeries(messages: viewModel.replies, index: index)

                            MessageBubble(
                                message: message,
                                isFromCurrentUser: isFromCurrentUser(message),
                                showAvatar: isGroup && !isFromCurrentUser(message),
                                isFirstInSeries: isFirst,
                                isLastInSeries: isLast,
                                totalParticipants: totalParticipants,
                                showReplyPreview: false
                            )
                            .padding(.vertical, 2)
                        }
                    } else if !viewModel.isLoading {
                        Text("messaging_no_replies_yet".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 16)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("thread.bottom")
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .onChange(of: viewModel.replies.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("thread.bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var parentMessageView: some View {
        if let parentMessage = viewModel.parentMessage {
            MessageBubble(
                message: parentMessage,
                isFromCurrentUser: isFromCurrentUser(parentMessage),
                showAvatar: isGroup && !isFromCurrentUser(parentMessage),
                isFirstInSeries: true,
                isLastInSeries: true,
                totalParticipants: totalParticipants
            )
            .padding(.vertical, 6)
        } else if viewModel.isLoading {
            ProgressView()
                .padding(.vertical, 16)
        } else if let error = viewModel.error {
            ErrorView(
                error: error.localizedDescription,
                retryAction: {
                    Task { await viewModel.loadThread(seedMessages: conversationViewModel.messages) }
                }
            )
            .padding(.vertical, 16)
        } else {
            Text("messaging_original_message_unavailable".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .padding(.vertical, 16)
        }
    }

    private func isFromCurrentUser(_ message: Message) -> Bool {
        message.fromId == AuthService.shared.currentUserId
    }

    private func isFirstInSeries(messages: [Message], index: Int) -> Bool {
        MessageSeriesHelper.isFirstInSeries(messages: messages, at: index)
    }

    private func isLastInSeries(messages: [Message], index: Int) -> Bool {
        MessageSeriesHelper.isLastInSeries(messages: messages, at: index)
    }
}

#Preview {
    NavigationStack {
        ConversationDetailView(conversationId: UUID())
    }
}

#Preview("Date Separator") {
    VStack(spacing: 20) {
        DateSeparatorView(date: Date())
        DateSeparatorView(date: Date().addingTimeInterval(-86400)) // Yesterday
        DateSeparatorView(date: Date().addingTimeInterval(-86400 * 3)) // 3 days ago
    }
    .padding()
}

