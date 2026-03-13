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
    @StateObject private var debugFrameDropMonitor: DebugFrameDropMonitor
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
    @State private var anchorMessageId: UUID? // Used to preserve scroll position during pagination
    
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
        _debugFrameDropMonitor = StateObject(wrappedValue: DebugFrameDropMonitor(conversationId: conversationId))
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
            return otherParticipant?.name ?? "messaging_chat_fallback".localized
        }

        return "messaging_chat_fallback".localized
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
            threadRepresentable(for: parent)
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
            // Start lightweight presence heartbeat when the thread is visible.
            viewModel.conversationDidAppear()
            // Start observing typing indicators
            viewModel.startTypingObservation()
#if DEBUG
            debugFrameDropMonitor.start()
#endif
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .messageThreadDidDisappear,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
            // Tear down all subscriptions: typing, search, reactions, observers
            viewModel.stop()
#if DEBUG
            debugFrameDropMonitor.stop()
#endif
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
            reportSheetContent
        }
        .sheet(isPresented: $showReactionDetails) {
            reactionDetailsContent
        }
        .alert("messaging_unsend_title".localized, isPresented: $showUnsendConfirmation) {
            unsendAlertActions
        } message: {
            Text("messaging_unsend_confirmation_message".localized)
        }
    }

    @ViewBuilder
    private var reportSheetContent: some View {
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

    @ViewBuilder
    private var reactionDetailsContent: some View {
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

    @ViewBuilder
    private var unsendAlertActions: some View {
        Button("common_cancel".localized, role: .cancel) {
            messageToUnsend = nil
        }
        Button("messaging_unsend_action".localized, role: .destructive) {
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
    
    /// Cell configurations — use the ViewModel's incrementally-updated cache
    /// instead of recomputing O(3N) on every SwiftUI body evaluation.
    private var messageCellConfigurations: [UUID: MessageCellConfiguration] {
        viewModel.messageCellConfigurations
    }

    @State private var shouldScrollToBottom = false

    private var messagesListView: some View {
        VStack(spacing: 0) {
            ZStack {
                if viewModel.isLoading && viewModel.messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                } else {
                    MessagesCollectionView(
                        messages: viewModel.messages,
                        cellConfigurations: messageCellConfigurations,
                        participantProfiles: participantsViewModel.participants,
                        isGroupConversation: isGroup,
                        totalParticipants: totalParticipantsCount,
                        onLongPress: { message, frame, snapshot in
                            // Store for overlay presentation (Layer 4 will wire this)
                            reactionPickerMessageId = message.id
                            showReactionPicker = true
                        },
                        onSwipeReply: { message in
                            withAnimation(.easeOut(duration: 0.2)) {
                                replyingToMessage = ReplyContext(from: message)
                            }
                        },
                        onImageTap: { url in
                            selectedImageUrl = url
                            showImageViewer = true
                        },
                        onReplyPreviewTap: { replyToId in
                            highlightedMessageId = replyToId
                        },
                        onRetry: { message in
                            Task { await viewModel.retryMessage(id: message.id) }
                        },
                        onReactionTap: { message, reaction in
                            if reaction == "__details__" {
                                reactionDetailsMessage = message
                                showReactionDetails = true
                                Task { await refreshReactionProfiles(for: message) }
                            } else if let reaction {
                                Task { await viewModel.addReaction(messageId: message.id, reaction: reaction) }
                            } else {
                                Task { await viewModel.removeReaction(messageId: message.id) }
                            }
                        },
                        onLoadMore: {
                            if viewModel.hasMoreMessages && !viewModel.isLoadingMore {
                                Task {
                                    await viewModel.loadMoreMessages()
                                }
                            }
                        },
                        onScrolledToBottom: { atBottom in
                            isAtBottom = atBottom
                            if atBottom {
                                showScrollToBottom = false
                            }
                        },
                        scrollToMessageId: viewModel.currentSearchResultId ?? highlightedMessageId,
                        scrollToBottom: shouldScrollToBottom
                    )
                    .accessibilityIdentifier("messages.thread.scroll")
                    .onAppear {
                        if navigationCoordinator.consumeConversationScrollTarget(for: conversationId) != nil,
                           !viewModel.messages.isEmpty {
                            showScrollToBottom = false
                            shouldScrollToBottom = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                shouldScrollToBottom = false
                            }
                        }
                    }
                    .onChange(of: viewModel.messages.count) { oldCount, newCount in
                        if navigationCoordinator.consumeConversationScrollTarget(for: conversationId) != nil {
                            showScrollToBottom = false
                            shouldScrollToBottom = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                shouldScrollToBottom = false
                            }
                        }
                        if oldCount > 0, newCount > oldCount, !viewModel.isLoadingMore {
                            let newMessages = viewModel.messages.suffix(newCount - oldCount)
                            for message in newMessages {
                                newMessageIds.insert(message.id)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                newMessageIds.removeAll()
                            }
                        }
                        let lastMessageIsFromMe = viewModel.messages.last.map { $0.fromId == AuthService.shared.currentUserId } ?? false
                        if (isAtBottom || lastMessageIsFromMe) && !viewModel.isLoadingMore && oldCount > 0 {
                            shouldScrollToBottom = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                shouldScrollToBottom = false
                            }
                            showScrollToBottom = false
                        } else if newCount > oldCount && !viewModel.isLoadingMore {
                            showScrollToBottom = true
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollToBottom {
                    ScrollToBottomButton(
                        unreadCount: viewModel.unreadCount,
                        action: {
                            shouldScrollToBottom = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                shouldScrollToBottom = false
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
            .overlay { messageInteractionOverlayView }

            if !viewModel.typingUsers.isEmpty {
                TypingIndicatorView(typingUsers: viewModel.typingUsers)
                    .padding(.horizontal)
            }
            ConversationInputContainer(
                imageToSend: $imageToSend,
                editingMessage: viewModel.editingMessage,
                replyingTo: replyingToMessage,
                focusState: $isInputFocused,
                onSendEdit: { editedText in
                    await viewModel.editMessage(newContent: editedText)
                    if viewModel.error == nil {
                        toastMessage = "toast_message_edited".localized
                        return true
                    }
                    return false
                },
                onSendMessage: { textToSend, image, replyToId in
                    viewModel.clearOwnTypingStatus()
                    await viewModel.sendMessage(textOverride: textToSend, image: image, replyToId: replyToId)
                    imageToSend = nil
                    withAnimation(.easeOut(duration: 0.2)) {
                        replyingToMessage = nil
                    }
                },
                onImagePickerTapped: { showImagePicker = true },
                onCancelReply: { replyingToMessage = nil },
                onCancelEdit: {
                    viewModel.cancelEdit()
                },
                onSendAudio: { audioURL, duration, replyToId in
                    viewModel.clearOwnTypingStatus()
                    await viewModel.sendAudioMessage(audioURL: audioURL, duration: duration, replyToId: replyToId)
                    withAnimation(.easeOut(duration: 0.2)) {
                        replyingToMessage = nil
                    }
                },
                onSendLocation: { latitude, longitude, name, replyToId in
                    viewModel.clearOwnTypingStatus()
                    await viewModel.sendLocationMessage(
                        latitude: latitude,
                        longitude: longitude,
                        locationName: name,
                        replyToId: replyToId
                    )
                    withAnimation(.easeOut(duration: 0.2)) {
                        replyingToMessage = nil
                    }
                },
                onTypingChanged: { viewModel.userDidType() }
            )
            .id("conversation.input.\(conversationId.uuidString)")
        }
    }

    @ViewBuilder
    private var messagesHeaderView: some View {
        // Pagination trigger at top of conversation
        Color.clear
            .frame(height: 2)
            .onAppear {
                if viewModel.hasMoreMessages && !viewModel.messages.isEmpty && !viewModel.isLoadingMore {
                    // Save the first visible message ID so we can scroll back to it after loading
                    anchorMessageId = viewModel.messages.first?.id
                    AppLogger.info("messaging", "[ConversationDetail] Reached top, loading more messages")
                    Task {
                        await viewModel.loadMoreMessages()
                    }
                }
            }

        if viewModel.isLoadingMore {
            ProgressView()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
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
    }

    // messagesBodyView removed — replaced by native UIKit cells in MessagesCollectionView

    

    private var messagesBottomSpacerView: some View {
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

    // MARK: - Thread

    private func threadRepresentable(for parent: ThreadParent) -> some View {
        MessageThreadRepresentable(
            conversationId: conversationId,
            parentMessageId: parent.id,
            conversationViewModel: viewModel,
            isGroup: isGroup,
            totalParticipants: totalParticipantsCount,
            participantProfiles: participantsViewModel.participants
        )
    }

    // MARK: - Message Interaction Overlay

    @ViewBuilder
    private var messageInteractionOverlayView: some View {
        if showReactionPicker,
           let messageId = reactionPickerMessageId,
           let message = viewModel.messages.first(where: { $0.id == messageId }) {
            let isFromMe = message.fromId == AuthService.shared.currentUserId
            let currentReaction = message.reactions?.currentUserReaction(
                userId: AuthService.shared.currentUserId ?? UUID()
            )
            let canEdit = isFromMe && !message.text.isEmpty && !message.isAudioMessage && !message.isLocationMessage

            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            MessageInteractionOverlay(
                message: message,
                messageContent: AnyView(
                    MessageBubble(
                        message: message,
                        isFromCurrentUser: isFromMe,
                        showAvatar: false,
                        isFirstInSeries: true,
                        isLastInSeries: true,
                        totalParticipants: totalParticipantsCount
                    )
                ),
                isFromCurrentUser: isFromMe,
                currentUserReaction: currentReaction,
                onReact: { reaction in
                    HapticManager.selectionChanged()
                    handleOverlayAction(.react(reaction))
                },
                onReply: { handleOverlayAction(.reply) },
                onCopy: { handleOverlayAction(.copy) },
                onEdit: canEdit ? { handleOverlayAction(.edit) } : nil,
                onUnsend: isFromMe && message.canUnsend ? { handleOverlayAction(.unsend) } : nil,
                onDeleteForMe: { handleOverlayAction(.deleteForMe) },
                onReport: !isFromMe ? { handleOverlayAction(.report) } : nil,
                onDismiss: { dismissOverlay() }
            )
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func dismissOverlay() {
        showReactionPicker = false
        reactionPickerMessageId = nil
    }

    private func handleOverlayAction(_ action: OverlayAction) {
        switch action {
        case .react(let emoji):
            if let messageId = reactionPickerMessageId {
                Task { await viewModel.addReaction(messageId: messageId, reaction: emoji) }
            }
        case .removeReaction:
            if let messageId = reactionPickerMessageId {
                Task { await viewModel.removeReaction(messageId: messageId) }
            }
        case .reply:
            if let messageId = reactionPickerMessageId,
               let message = viewModel.messages.first(where: { $0.id == messageId }) {
                withAnimation(.easeOut(duration: 0.2)) {
                    replyingToMessage = ReplyContext(from: message)
                }
            }
        case .viewThread(let parentId):
            activeThreadParent = ThreadParent(id: parentId)
        case .copy:
            if let messageId = reactionPickerMessageId,
               let message = viewModel.messages.first(where: { $0.id == messageId }) {
                UIPasteboard.general.string = message.text
            }
        case .edit:
            if let messageId = reactionPickerMessageId,
               let message = viewModel.messages.first(where: { $0.id == messageId }) {
                withAnimation(.easeOut(duration: 0.2)) {
                    replyingToMessage = nil
                    viewModel.startEditing(message)
                }
            }
        case .unsend:
            if let messageId = reactionPickerMessageId,
               let message = viewModel.messages.first(where: { $0.id == messageId }) {
                showUnsendConfirmation = true
                messageToUnsend = message
            }
        case .deleteForMe:
            if let messageId = reactionPickerMessageId,
               let message = viewModel.messages.first(where: { $0.id == messageId }) {
                Task { await viewModel.deleteMessageForMe(message) }
            }
        case .report:
            if let messageId = reactionPickerMessageId,
               let message = viewModel.messages.first(where: { $0.id == messageId }) {
                messageToReport = message
                showReportSheet = true
            }
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
        guard navigationCoordinator.consumeConversationScrollTarget(for: conversationId) != nil else {
            return
        }

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
            if let detail = try await ConversationService.shared.fetchConversationWithDetails(
                conversationId: conversationId,
                userId: userId
            ) {
                conversationDetail = detail
            }
        } catch {
            AppLogger.error("messaging", "Error loading conversation details: \(error.localizedDescription)")
        }
    }
}

private struct ConversationInputContainer: View {
    @Binding var imageToSend: UIImage?
    let editingMessage: Message?
    let replyingTo: ReplyContext?
    let focusState: FocusState<Bool>.Binding
    let onSendEdit: (String) async -> Bool
    let onSendMessage: (String, UIImage?, UUID?) async -> Void
    let onImagePickerTapped: () -> Void
    let onCancelReply: () -> Void
    let onCancelEdit: () -> Void
    let onSendAudio: (URL, Double, UUID?) async -> Void
    let onSendLocation: (Double, Double, String?, UUID?) async -> Void
    let onTypingChanged: () -> Void

    @State private var draftText: String = ""

    var body: some View {
        MessageInputBar(
            text: $draftText,
            imageToSend: $imageToSend,
            onSend: handleSendTapped,
            onImagePickerTapped: onImagePickerTapped,
            isDisabled: draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageToSend == nil,
            focusState: focusState,
            replyingTo: replyingTo,
            onCancelReply: onCancelReply,
            editingMessage: editingMessage,
            onCancelEdit: {
                draftText = ""
                onCancelEdit()
            },
            onAudioRecorded: { audioURL, duration in
                Task {
                    await onSendAudio(audioURL, duration, replyingTo?.id)
                }
            },
            onLocationShare: { latitude, longitude, name in
                Task {
                    await onSendLocation(latitude, longitude, name, replyingTo?.id)
                }
            },
            onTypingChanged: onTypingChanged
        )
        .onChange(of: editingMessage?.id) { _, _ in
            draftText = editingMessage?.text ?? ""
        }
    }

    private func handleSendTapped() {
        if editingMessage != nil {
            let editedText = draftText
            guard !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            draftText = ""
            Task {
                let success = await onSendEdit(editedText)
                if !success {
                    draftText = editedText
                }
            }
            return
        }

        let textToSend = draftText
        let trimmed = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = imageToSend
        guard !trimmed.isEmpty || image != nil else { return }
        draftText = ""
        Task {
            await onSendMessage(textToSend, image, replyingTo?.id)
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
            if let sdConv = try? MessagingRepository.shared.fetchSDConversation(id: conversationId) {
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
            if let sdConv = try? MessagingRepository.shared.fetchSDConversation(id: conversationId) {
                sdConv.participantIds = freshParticipantIds
                try? MessagingRepository.shared.save(changedConversationIds: Set([conversationId]))
            }
            
            // 4. Fetch profiles for each participant
            let existingParticipants = participants
            let fetchedProfiles = (try? await ProfileService.shared.fetchProfiles(userIds: freshParticipantIds)) ?? []
            let fetchedById = Dictionary(uniqueKeysWithValues: fetchedProfiles.map { ($0.id, $0) })
            let profiles = freshParticipantIds.compactMap { userId in
                fetchedById[userId] ?? existingParticipants.first(where: { $0.id == userId })
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
private final class DebugFrameDropMonitor: NSObject, ObservableObject {
    private let conversationId: UUID
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var lastFlushTimestamp: CFTimeInterval = 0
    private var pendingDroppedFrames = 0
    private var pendingEvents = 0

    init(conversationId: UUID) {
        self.conversationId = conversationId
    }

    func start() {
#if DEBUG
        guard FeatureFlags.verbosePerformanceLogsEnabled else { return }
        guard displayLink == nil else { return }
        lastTimestamp = 0
        lastFlushTimestamp = 0
        pendingDroppedFrames = 0
        pendingEvents = 0
        let link = CADisplayLink(target: self, selector: #selector(handleFrameTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
#endif
    }

    func stop() {
        flushPendingIfNeeded(force: true)
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
        lastFlushTimestamp = 0
        pendingDroppedFrames = 0
        pendingEvents = 0
    }

    @objc private func handleFrameTick(_ link: CADisplayLink) {
#if DEBUG
        guard FeatureFlags.verbosePerformanceLogsEnabled else { return }
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        let expectedFrameDuration = link.duration > 0 ? link.duration : (1.0 / 60.0)
        let delta = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp

        guard delta > expectedFrameDuration * 1.5 else { return }
        let droppedFrames = max(Int((delta / expectedFrameDuration).rounded(.down)) - 1, 1)
        pendingEvents += 1
        pendingDroppedFrames += droppedFrames

        let shouldFlushNow =
            pendingEvents >= 6 ||
            pendingDroppedFrames >= 12 ||
            (lastFlushTimestamp == 0 || (link.timestamp - lastFlushTimestamp) >= 0.75)
        if shouldFlushNow {
            flushPendingIfNeeded(force: false, slowThreshold: expectedFrameDuration * 2)
            lastFlushTimestamp = link.timestamp
        }
#endif
    }

    private func flushPendingIfNeeded(force: Bool, slowThreshold: TimeInterval = 1.0 / 30.0) {
#if DEBUG
        guard force || pendingEvents > 0 else { return }
        let droppedFrames = pendingDroppedFrames
        let events = pendingEvents
        guard events > 0 else { return }

        pendingEvents = 0
        pendingDroppedFrames = 0

        Task {
            await PerformanceMonitor.shared.incrementDebugCounter("messaging.frameDrop.events", by: events)
            await PerformanceMonitor.shared.incrementDebugCounter("messaging.frameDrop.frames", by: droppedFrames)
            let estimatedDuration = TimeInterval(droppedFrames) * (1.0 / 60.0)
            await PerformanceMonitor.shared.record(
                operation: "messaging.frameDrop.delta",
                duration: estimatedDuration,
                metadata: [
                    "conversationId": conversationId.uuidString,
                    "droppedFrames": droppedFrames,
                    "events": events
                ],
                slowThreshold: slowThreshold
            )
        }
#endif
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
