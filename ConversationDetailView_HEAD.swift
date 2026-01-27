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
    
    // Image viewer state
    @State private var selectedImageUrl: URL?
    @State private var showImageViewer = false
    
    // Report state
    @State private var showReportSheet = false
    @State private var messageToReport: Message?
    
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
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Top anchor for infinite scrolling
                        Color.clear
                            .frame(height: 2)
                            .onAppear {
                                if viewModel.hasMoreMessages && !viewModel.messages.isEmpty && !viewModel.isLoadingMore {
                                    print("🔄 [ConversationDetail] Reached top, loading more messages")
                                    Task {
                                        await viewModel.loadMoreMessages()
                                    }
                                }
                            }

                        // No more messages indicator
                        if !viewModel.hasMoreMessages && !viewModel.messages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Beginning of Conversation")
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
                                Text("Start the conversation!")
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
                                
                                VStack(spacing: 0) {
                                    // Date separator
                                    if shouldShowDateSeparator {
                                        DateSeparatorView(date: message.createdAt)
                                            .padding(.vertical, 16)
                                    }
                                    
                                    createMessageBubble(
                                        message: message,
                                        isFirst: isFirst,
                                        isLast: isLast
                                    )
                                }
                                .onAppear {
                                    viewModel.trackMessageVisible(message)
                                }
                                .id(messageAnchorId(message.id))
                            }
                        }
                        
                        // Typing indicator (inline)
                        if !viewModel.typingUsers.isEmpty {
                            typingIndicatorInline
                                .padding(.horizontal)
                        }
                        
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
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
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
                        print("⬇️ [ConversationDetail] Auto-scroll to bottom")
                    } else if newCount > oldCount {
                        showScrollToBottom = true
                        print("⬆️ [ConversationDetail] New messages while scrolled up")
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
                    let textToSend = viewModel.messageText
                    viewModel.messageText = ""
                    Task {
                        viewModel.clearTypingStatusOnSend()
                        await viewModel.sendMessage(textOverride: textToSend, image: imageToSend, replyToId: replyingToMessage?.id)
                        imageToSend = nil
                        // Clear reply context after sending
                        withAnimation(.easeOut(duration: 0.2)) {
                            replyingToMessage = nil
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
                onAudioRecorded: { audioURL, duration in
                    Task {
                        await viewModel.sendAudioMessage(audioURL: audioURL, duration: duration, replyToId: replyingToMessage?.id)
                        withAnimation(.easeOut(duration: 0.2)) {
                            replyingToMessage = nil
                        }
                    }
                },
                onLocationShare: { latitude, longitude, name in
                    Task {
                        await viewModel.sendLocationMessage(latitude: latitude, longitude: longitude, locationName: name, replyToId: replyingToMessage?.id)
                        withAnimation(.easeOut(duration: 0.2)) {
                            replyingToMessage = nil
                        }
                    }
                }
            )
        }
        .id(threadAnchorId)
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
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .messageThreadDidDisappear,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }
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
            print("🔴 Error submitting report: \(error.localizedDescription)")
        }
    }
    
    private func isFromCurrentUser(_ message: Message) -> Bool {
        message.fromId == AuthService.shared.currentUserId
    }
    
    /// Check if this is a group conversation (more than 2 participants)
    private var isGroup: Bool {
        participantsViewModel.participants.count > 2
    }
    
    /// Create a message bubble with all handlers
    @ViewBuilder
    private func createMessageBubble(message: Message, isFirst: Bool, isLast: Bool) -> some View {
        let totalParticipants = max(
            participantsViewModel.participants.count,
            (conversationDetail?.otherParticipants.count ?? 0) + 1
        )
        
        MessageBubble(
            message: message,
            isFromCurrentUser: isFromCurrentUser(message),
            showAvatar: isGroup && !isFromCurrentUser(message),
            isFirstInSeries: isFirst,
            isLastInSeries: isLast,
            shouldAnimate: newMessageIds.contains(message.id),
            totalParticipants: totalParticipants,
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
            onImageTap: { imageUrl in
                selectedImageUrl = imageUrl
                showImageViewer = true
            },
            onReport: {
                messageToReport = message
                showReportSheet = true
            },
            onReplyPreviewTap: { replyId in
                scrollToMessage(replyId)
            },
            isHighlighted: highlightedMessageId == message.id
        )
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
        guard index > 0 else { return true }
        let currentMessage = viewModel.messages[index]
        let previousMessage = viewModel.messages[index - 1]
        
        // Different sender = first in new series
        if currentMessage.fromId != previousMessage.fromId {
            return true
        }
        
        // More than 5 minutes apart = new series
        let timeDiff = currentMessage.createdAt.timeIntervalSince(previousMessage.createdAt)
        if timeDiff > 300 { // 5 minutes
            return true
        }
        
        return false
    }
    
    /// Check if message is the last in a consecutive series from the same sender
    private func isLastInSeries(at index: Int) -> Bool {
        guard index < viewModel.messages.count - 1 else { return true }
        let currentMessage = viewModel.messages[index]
        let nextMessage = viewModel.messages[index + 1]
        
        // Different sender = last in current series
        if currentMessage.fromId != nextMessage.fromId {
            return true
        }
        
        // More than 5 minutes apart = end of series
        let timeDiff = nextMessage.createdAt.timeIntervalSince(currentMessage.createdAt)
        if timeDiff > 300 { // 5 minutes
            return true
        }
        
        return false
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
    
    private var typingIndicatorInline: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Simple avatar placeholder
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(typingText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color(.systemGray3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.systemGray5))
                )
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var typingText: String {
        let users = viewModel.typingUsers
        switch users.count {
        case 1:
            return "\(users[0].name) is typing..."
        case 2:
            return "\(users[0].name) and \(users[1].name) are typing..."
        default:
            return "\(users[0].name) and \(users.count - 1) others are typing..."
        }
    }
    
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
                        Text("Failed to load image")
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
                            .font(.system(size: 16, weight: .semibold))
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
            var profiles: [Profile] = []
            for userId in freshParticipantIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(.systemGray6))
                )
            
            VStack { Divider() }
        }
        .padding(.horizontal)
    }
}

// MARK: - Scroll to Bottom Button

/// Floating button to scroll to the bottom of the conversation
struct ScrollToBottomButton: View {
    let unreadCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .overlay(
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.naarsPrimary)
                    )
                
                // Unread badge
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.naarsPrimary)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Reaction Details Sheet

struct ReactionDetailsSheet: View {
    let message: Message
    let reactions: MessageReactions
    let profilesByReaction: [String: [Profile]]
    let onRemoveReaction: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedReactions, id: \.reaction) { reactionData in
                    Section(header: Text("\(reactionData.reaction) \(reactionData.count)")) {
                        ForEach(profilesByReaction[reactionData.reaction] ?? [], id: \.id) { profile in
                            HStack(spacing: 12) {
                                AvatarView(
                                    imageUrl: profile.avatarUrl,
                                    name: profile.name,
                                    size: 32
                                )
                                Text(profile.name)
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                if let currentUserId = AuthService.shared.currentUserId {
                    let myReactions = reactions.reactions.filter { $0.value.contains(currentUserId) }
                    if !myReactions.isEmpty {
                        Section {
                            ForEach(myReactions.keys.sorted(), id: \.self) { reaction in
                                Button(role: .destructive) {
                                    onRemoveReaction(reaction)
                                } label: {
                                    Text("Remove \(reaction)")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var sortedReactions: [(reaction: String, count: Int, userIds: [UUID])] {
        reactions.sortedReactions.sorted {
            if $0.count == $1.count {
                return $0.reaction < $1.reaction
            }
            return $0.count > $1.count
        }
    }
}

// MARK: - Report Message Sheet

/// Sheet for reporting a message
struct ReportMessageSheet: View {
    let message: Message
    let onSubmit: (MessageService.ReportType, String?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReportType: MessageService.ReportType = .other
    @State private var description = ""
    @State private var isSubmitting = false
    
    private let reportTypes: [(type: MessageService.ReportType, title: String, icon: String)] = [
        (.spam, "Spam", "exclamationmark.bubble"),
        (.harassment, "Harassment", "person.crop.circle.badge.exclamationmark"),
        (.inappropriateContent, "Inappropriate Content", "eye.slash"),
        (.scam, "Scam", "exclamationmark.shield"),
        (.other, "Other", "ellipsis.circle")
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                // Message preview
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report this message")
                                .font(.headline)
                            
                            Text(message.text.isEmpty ? "Media message" : message.text)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Message")
                }
                
                // Report type selection
                Section {
                    ForEach(reportTypes, id: \.type.rawValue) { reportType in
                        Button {
                            selectedReportType = reportType.type
                        } label: {
                            HStack {
                                Image(systemName: reportType.icon)
                                    .foregroundColor(.naarsPrimary)
                                    .frame(width: 24)
                                
                                Text(reportType.title)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedReportType == reportType.type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.naarsPrimary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Reason")
                }
                
                // Additional details
                Section {
                    TextField("Additional details (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Provide any additional context that may help us review this report.")
                }
                
                // Block user option
                Section {
                    Button {
                        // TODO: Implement block user from report flow
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .foregroundColor(.red)
                            Text("Block this user")
                                .foregroundColor(.red)
                        }
                    }
                } footer: {
                    Text("You won't see messages from this user anymore.")
                }
            }
            .navigationTitle("Report Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        isSubmitting = true
                        onSubmit(selectedReportType, description.isEmpty ? nil : description)
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
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

#Preview("Scroll Button") {
    VStack(spacing: 20) {
        ScrollToBottomButton(unreadCount: 0, action: {})
        ScrollToBottomButton(unreadCount: 5, action: {})
        ScrollToBottomButton(unreadCount: 150, action: {})
    }
    .padding()
    .background(Color(.systemGray5))
}

