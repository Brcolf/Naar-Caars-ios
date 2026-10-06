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
import CoreLocation

private let messageThreadReportRequestedNotification = Notification.Name("messaging.thread.reportRequested")

/// View for displaying conversation detail (chat screen)
struct ConversationDetailView: View {
    let conversationId: UUID
    @State private var viewModel: ConversationDetailViewModel
    @StateObject private var participantsViewModel: ConversationParticipantsViewModel
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @StateObject private var debugFrameDropMonitor: DebugFrameDropMonitor
    @State private var showMessageDetails = false
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var imageToSend: UIImage?
    // Overlay state removed — UIKit MessageOverlayController handles overlay presentation directly
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

    /// True while a cover or sheet (reply thread, image viewer, details, report, location picker,
    /// photo picker) is on top of the conversation. Set when one is requested and re-evaluated
    /// from its onDismiss, so the composer (a keyboard accessory that would otherwise float over
    /// the presentation) returns only after the dismissal animation has finished.
    @State private var isComposerCovered = false

    private var isAnyCoverPresented: Bool {
        activeThreadParent != nil
            || showImageViewer
            || showMessageDetails
            || messageToReport != nil
            || showLocationPicker
            || showImagePicker
    }

    /// One presentation can hand over to another (the thread cover closes into the report
    /// sheet), so a dismissal only brings the composer back when nothing else is up.
    private func coverDismissed() {
        isComposerCovered = isAnyCoverPresented
    }
    
    // Image viewer state
    @State private var selectedImageUrl: URL?
    @State private var showImageViewer = false
    
    // Report state
    @State private var messageToReport: Message?
    @State private var reportErrorMessage: String?
    
    // Unsend confirmation state
    @State private var showUnsendConfirmation = false
    @State private var messageToUnsend: Message?
    
    // Toast state
    @State private var toastMessage: String? = nil

    /// Failure of the last send / edit / unsend / reaction, shown in the error banner.
    @State private var actionErrorMessage: String?

    /// The same for actions taken inside the reply-thread cover, which hides that banner;
    /// shown as a warning toast on the cover.
    @State private var threadActionErrorMessage: String?

    /// Text and photo of a send that was refused before a bubble existed, handed back to
    /// the composer (it clears itself as soon as Send is tapped).
    @State private var rejectedDraft: ComposerDraft?

    /// Set when the user leaves the group from the details sheet, so the thread is read-only
    /// at once instead of showing a live composer until the server check comes back.
    @State private var didLeaveFromDetails = false

    /// The user is no longer a member: the composer is replaced by the read-only banner.
    private var isConversationFrozen: Bool {
        viewModel.hasLeftConversation || didLeaveFromDetails
    }

    // Location picker state (presented when UIKit input bar requests location)
    @State private var showLocationPicker = false


    /// Name the caller already shows for this conversation (the list row's title). Used as the
    /// header until the participants load, so the title does not flash a generic placeholder.
    private let initialTitle: String?

    /// The message to land on when the thread is opened from a search hit in the Messages
    /// list. Honoured once, after the first load.
    private let initialMessageId: UUID?
    @State private var didHandleInitialMessageTarget = false

    /// Paging back to a message that is older than the loaded pages (a search hit, a reply's
    /// original). `locatingMessageId` is set while that runs and drives the search bar's spinner.
    @State private var locateMessageTask: Task<Void, Never>?
    @State private var locatingMessageId: UUID?

    /// Bounds for `loadOlderMessages(toReveal:)`: how many load attempts it makes, how many in
    /// a row may add nothing before it gives up, and how long it waits for a page to show up.
    private static let locateMessageMaxPasses = 40
    private static let locateMessageMaxStalledPasses = 3
    private static let locateMessageSettleNanoseconds: UInt64 = 150_000_000

    init(conversationId: UUID, initialTitle: String? = nil, initialMessageId: UUID? = nil) {
        self.conversationId = conversationId
        self.initialTitle = initialTitle
        self.initialMessageId = initialMessageId
        _viewModel = State(initialValue: ConversationDetailViewModel(conversationId: conversationId))
        _participantsViewModel = StateObject(wrappedValue: ConversationParticipantsViewModel(conversationId: conversationId))
        _debugFrameDropMonitor = StateObject(wrappedValue: DebugFrameDropMonitor(conversationId: conversationId))
    }
    
    // Computed title based on conversation type
    private var conversationTitle: String {
        // If group conversation (3+ participants), show editable group name or participant names
        if participantsViewModel.participants.count > 2 {
            if let title = participantsViewModel.conversationDetail?.conversation.title, !title.isEmpty {
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
            return otherParticipant?.name ?? initialTitle ?? "messaging_chat_fallback".localized
        }

        return initialTitle ?? "messaging_chat_fallback".localized
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
                ConversationSearchBar(viewModel: viewModel, isLocatingResult: locatingMessageId != nil)
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
                .accessibilityLabel("messaging_media_title".localized)
                
                // Search button
                Button {
                    viewModel.toggleSearch()
                } label: {
                    Image(systemName: viewModel.isSearchActive ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(viewModel.isSearchActive ? "messaging_search_close_accessibility".localized : "messaging_search_open_accessibility".localized)
                
                // Details button: mute for every thread, group management for 3+. One-to-one
                // threads used to have no way into this sheet, so muting was only reachable
                // from the list row's swipe action.
                if participantsViewModel.participants.count >= 2 {
                    Button {
                        showMessageDetails = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("messaging_conversation_details_title".localized)
                    .accessibilityIdentifier("messages.thread.details")
                }
            }
        }
        .sheet(isPresented: $showMessageDetails, onDismiss: coverDismissed) {
            MessageDetailsPopup(
                conversationId: conversationId,
                currentTitle: participantsViewModel.conversationDetail?.conversation.title,
                currentGroupImageUrl: participantsViewModel.conversationDetail?.conversation.groupImageUrl,
                participants: participantsViewModel.participants,
                createdBy: participantsViewModel.conversationDetail?.conversation.createdBy,
                onLeftConversation: { didLeaveFromDetails = true }
            )
            .onDisappear {
                // Reload participants and conversation details after closing
                Task {
                    // Membership may have changed in the sheet (left the group, or was re-added).
                    await viewModel.checkLeftStatus()
                    await participantsViewModel.loadParticipants()
                    await participantsViewModel.loadConversationDetails()
                }
            }
        }
        .fullScreenCover(item: $activeThreadParent, onDismiss: coverDismissed) { parent in
            threadRepresentable(for: parent)
                // Failures of actions taken in the thread: this screen's banner is under the cover.
                .toast(message: $threadActionErrorMessage, style: .warning)
        }
        .onChange(of: isAnyCoverPresented) { _, isPresented in
            if isPresented { isComposerCovered = true }
        }
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedImage,
            matching: .images
        )
        .onChange(of: showImagePicker) { _, isShowing in
            // `photosPicker` has no onDismiss and its binding flips as the dismissal starts.
            // Wait for the picker to animate away, then let `coverDismissed` bring the
            // composer back as it does for the other sheets.
            guard !isShowing else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Animation.long) {
                coverDismissed()
            }
        }
        .onChange(of: selectedImage) { _, newValue in
            // The picker item is consumed and reset to nil so choosing the same photo again
            // (after sending or removing it) fires this handler. A nil value therefore no
            // longer clears the attachment; the bar's X button and the send path do that.
            guard let item = newValue else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    imageToSend = UIImage(data: data)
                }
                selectedImage = nil
            }
        }
        .task {
            viewModel.start()
            await viewModel.loadMessages()
            // Opened from a search hit in the Messages list: land on that message instead of
            // leaving the user at the newest one to scroll for it.
            if let target = initialMessageId, !didHandleInitialMessageTarget, !Task.isCancelled {
                didHandleInitialMessageTarget = true
                scrollToMessage(target)
            }
            await participantsViewModel.loadParticipants()
            await participantsViewModel.loadConversationDetails()
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
            // Ensure unread divider won't re-show if user re-opens this conversation
            viewModel.hasShownUnreadDivider = true
            // Tear down all subscriptions: typing, search, reactions, observers
            viewModel.stop()
            cancelLocatingMessage()
#if DEBUG
            debugFrameDropMonitor.stop()
#endif
        }
        .onChange(of: viewModel.currentSearchResultId) { _, resultId in
            if let messageId = resultId {
                scrollToMessage(messageId)
            } else {
                // Search was closed or cleared: stop paging back to a match nobody is waiting for.
                cancelLocatingMessage()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: messageThreadReportRequestedNotification)) { notification in
            guard let handoffConversationId = notification.userInfo?["conversationId"] as? UUID,
                  handoffConversationId == conversationId,
                  let message = notification.userInfo?["message"] as? Message,
                  message.conversationId == conversationId else { return }
            activeThreadParent = nil
            messageToReport = message
        }
        .toast(message: $toastMessage)
        .errorBanner(message: $actionErrorMessage)
        .trackScreen("ConversationDetail")
        .fullScreenCover(isPresented: $showImageViewer, onDismiss: coverDismissed) {
            if let imageUrl = selectedImageUrl {
                // Shared viewer loads via PersistentImageService, so the asset the
                // bubble already cached on disk is not downloaded a second time.
                ImageViewerView(imageUrl: imageUrl, onDismiss: {
                    showImageViewer = false
                    selectedImageUrl = nil
                })
            }
        }
        .sheet(item: $messageToReport, onDismiss: coverDismissed) { message in
            ReportMessageSheet(
                message: message,
                onSubmit: { reportType, description in
                    Task {
                        await submitReport(message: message, type: reportType, description: description)
                    }
                }
            )
        }
        .alert("messaging_unsend_title".localized, isPresented: $showUnsendConfirmation) {
            unsendAlertActions
        } message: {
            Text("messaging_unsend_confirmation_message".localized)
        }
        .alert("report_failed".localized, isPresented: Binding(
            get: { reportErrorMessage != nil },
            set: { if !$0 { reportErrorMessage = nil } }
        )) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(reportErrorMessage ?? "")
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
                    if await runMessageAction({ await viewModel.unsendMessage(id: message.id) }) == nil {
                        toastMessage = "toast_message_unsent".localized
                    }
                }
                messageToUnsend = nil
            }
        }
    }

    // MARK: - Action Failures

    /// Runs a view-model action and shows any failure it recorded in the error banner.
    /// `viewModel.error` is cleared before and after: nothing else resets it, so a rejected
    /// send (rate limit, over-long text, a conversation the user has left) was silent, and a
    /// stale value hid later failures and suppressed the "edited" / "unsent" toasts.
    /// - Parameter processingFailureText: shown instead of the raw service text when the
    ///   action fails with a plain `.processingError`
    /// - Returns: the failure the action recorded, or nil when it finished without one
    @discardableResult
    private func runMessageAction(
        processingFailureText: String? = nil,
        _ action: @MainActor () async -> Void
    ) async -> AppError? {
        viewModel.error = nil
        actionErrorMessage = nil
        await action()
        guard let error = viewModel.error else { return nil }
        viewModel.error = nil
        actionErrorMessage = error.messageActionText(processingFailureText: processingFailureText)
        return error
    }

    private func addReaction(_ reaction: String, to message: Message) async {
        await runMessageAction(processingFailureText: "messaging_error_reaction".localized) {
            await viewModel.addReaction(messageId: message.id, reaction: reaction)
        }
    }

    private func removeReaction(from message: Message) async {
        await runMessageAction(processingFailureText: "messaging_error_reaction".localized) {
            await viewModel.removeReaction(messageId: message.id)
        }
    }

    /// Submit a report for a message
    private func submitReport(message: Message, type: MessageService.ReportType, description: String?) async {
        reportErrorMessage = nil

        do {
            guard try await viewModel.reportMessage(messageId: message.id, type: type, description: description) else { return }

            reportErrorMessage = nil
            toastMessage = "messaging_report_submitted".localized
            messageToReport = nil
        } catch {
            AppLogger.error("messaging", "Error submitting report: \(error.localizedDescription)")
            reportErrorMessage = error.localizedDescription
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
            (participantsViewModel.conversationDetail?.otherParticipants.count ?? 0) + 1
        )
    }
    
    /// Cell configurations — use the ViewModel's incrementally-updated cache
    /// instead of recomputing O(3N) on every SwiftUI body evaluation.
    private var messageCellConfigurations: [UUID: MessageCellConfiguration] {
        viewModel.messageCellConfigurations
    }

    /// Reply banner context. Messages delivered over realtime or read from the local cache carry
    /// no joined `sender`, which made the banner read "Replying to Unknown"; resolve the name
    /// from the loaded participants (the same fallback the message cell uses).
    private func replyContext(for message: Message) -> ReplyContext {
        if message.sender != nil {
            return ReplyContext(from: message)
        }
        let name: String
        if message.fromId == AuthService.shared.currentUserId {
            name = "messaging_you".localized
        } else {
            name = participantsViewModel.participants.first(where: { $0.id == message.fromId })?.name
                ?? "messaging_deleted_user".localized
        }
        return ReplyContext(
            id: message.id,
            text: message.text,
            senderName: name,
            senderId: message.fromId,
            imageUrl: message.imageUrl
        )
    }

    @State private var shouldScrollToBottom = false

    private var messagesListView: some View {
        VStack(spacing: 0) {
            ZStack {
                // Always mounted. The composer is this controller's inputAccessoryView, so an
                // empty or still-loading conversation has to host it too; when it was mounted
                // only for non-empty threads, the first message of a new conversation could
                // not be typed (the "created by" system line was the only thing hiding that).
                Group {
                    MessagesViewControllerRepresentable(
                        messages: viewModel.messages,
                        messagesVersion: viewModel.messagesVersion,
                        cellConfigurations: messageCellConfigurations,
                        participantProfiles: participantsViewModel.participants,
                        isGroupConversation: isGroup,
                        totalParticipants: totalParticipantsCount,
                        onOverlayAction: { action, message in
                            handleOverlayAction(action, for: message)
                        },
                        onSwipeReply: { message in
                            withAnimation(.easeOut(duration: 0.2)) {
                                replyingToMessage = replyContext(for: message)
                            }
                        },
                        onImageTap: { url in
                            selectedImageUrl = url
                            showImageViewer = true
                        },
                        onReplyPreviewTap: { replyToId in
                            // scrollToMessage schedules the 1.5s highlight reset; a bare
                            // assignment left the id set and re-scrolled on every update.
                            scrollToMessage(replyToId)
                        },
                        onRetry: { message in
                            Task {
                                await runMessageAction(processingFailureText: "messaging_send_failed".localized) {
                                    await viewModel.retryMessage(id: message.id)
                                }
                            }
                        },
                        onReactionTap: { message, reaction in
                            if let reaction {
                                Task { await addReaction(reaction, to: message) }
                            } else {
                                Task { await removeReaction(from: message) }
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
                        scrollToBottom: shouldScrollToBottom,
                        firstUnreadMessageId: viewModel.firstUnreadMessageId,
                        unreadCount: viewModel.unreadCount,
                        showUnreadDivider: !viewModel.hasShownUnreadDivider && viewModel.firstUnreadMessageId != nil,
                        onUnreadDividerDismissed: {
                            viewModel.hasShownUnreadDivider = true
                        },
                        replyContext: replyingToMessage,
                        editingMessage: viewModel.editingMessage,
                        imageToSend: $imageToSend,
                        onSendMessage: { text in
                            viewModel.clearOwnTypingStatus()
                            Task {
                                // A failed send keeps its bubble (marked "Not sent", tap to
                                // retry); the banner says why, including sends that were
                                // rejected before a bubble existed.
                                let image = imageToSend
                                let failure = await runMessageAction(processingFailureText: "messaging_send_failed".localized) {
                                    await viewModel.sendMessage(textOverride: text, image: image, replyToId: replyingToMessage?.id)
                                }
                                // Refused before a bubble existed (rate limit, over-long
                                // text): the composer has already cleared itself, so hand the
                                // text back and keep the photo and the reply context.
                                if let failure, failure.isSendRefusedBeforeBubble {
                                    rejectedDraft = ComposerDraft(text: text, image: image)
                                    return
                                }
                                imageToSend = nil
                                withAnimation(.easeOut(duration: 0.2)) {
                                    replyingToMessage = nil
                                }
                            }
                        },
                        onSendEditedMessage: { editedText, _ in
                            Task {
                                if await runMessageAction({ await viewModel.editMessage(newContent: editedText) }) == nil {
                                    toastMessage = "toast_message_edited".localized
                                }
                            }
                        },
                        onImagePickerTapped: { showImagePicker = true },
                        onAudioRecorded: { audioURL, duration in
                            viewModel.clearOwnTypingStatus()
                            Task {
                                await runMessageAction {
                                    await viewModel.sendAudioMessage(audioURL: audioURL, duration: duration, replyToId: replyingToMessage?.id)
                                }
                                withAnimation(.easeOut(duration: 0.2)) {
                                    replyingToMessage = nil
                                }
                            }
                        },
                        onLocationRequested: {
                            showLocationPicker = true
                        },
                        onCancelReply: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                replyingToMessage = nil
                            }
                        },
                        onCancelEdit: {
                            viewModel.cancelEdit()
                        },
                        onTypingChanged: { viewModel.userDidType() },
                        replyCountMap: viewModel.replyCountMap,
                        onViewThread: { message in
                            activeThreadParent = ThreadParent(id: message.replyToId ?? message.id)
                        },
                        isConversationFrozen: isConversationFrozen,
                        typingUsers: viewModel.typingUsers,
                        // Also suppressed while the in-thread search field is up: that field
                        // takes first responder, and clearing the flag when search closes is
                        // what hands first responder (and so the composer) back to the
                        // controller. A conversation the user has left has no composer at all.
                        isComposerSuppressed: isComposerCovered || viewModel.isSearchActive || isConversationFrozen,
                        draftToRestore: rejectedDraft
                    )
                    .accessibilityIdentifier("messages.thread.scroll")
                    .onAppear {
                        // Messages may still be loading at mount time; leave the scroll target
                        // for the messages.count handler below in that case.
                        if !viewModel.messages.isEmpty,
                           navigationCoordinator.consumeConversationScrollTarget(for: conversationId) != nil {
                            showScrollToBottom = false
                            shouldScrollToBottom = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                shouldScrollToBottom = false
                            }
                        }
                    }
                    .onChange(of: TranscriptEdge(count: viewModel.messages.count, newestId: viewModel.messages.last?.id)) { oldEdge, newEdge in
                        // Runs when the number of messages changes, as before. The newest id
                        // is only there to tell older pages from new messages (see below).
                        let oldCount = oldEdge.count
                        let newCount = newEdge.count
                        guard newCount != oldCount else { return }
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
                        // Older messages added above the same newest message (pagination,
                        // hydration, paging back to a search hit): nothing new arrived, so do
                        // not follow to the bottom or offer the new-messages button.
                        // `isLoadingMore` no longer catches this, because a loaded page reaches
                        // `messages` one hop after that flag has cleared: in a thread whose last
                        // message is the user's own, every older page pulled the list back down.
                        guard !(newCount > oldCount && newEdge.newestId == oldEdge.newestId) else { return }
                        let lastMessageIsFromMe = viewModel.messages.last.map { $0.fromId == AuthService.shared.currentUserId } ?? false
                        if (isAtBottom || lastMessageIsFromMe) && !viewModel.isLoadingMore && oldCount > 0 {
                            shouldScrollToBottom = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                shouldScrollToBottom = false
                            }
                            showScrollToBottom = false
                        } else if oldCount > 0 && newCount > oldCount && !viewModel.isLoadingMore {
                            showScrollToBottom = true
                        }
                    }
                }

                if viewModel.isLoading && viewModel.messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
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
                    .allowsHitTesting(false)
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
            // Overlay handled by UIKit MessageOverlayController (presented from MessagesViewController)

            // Read-only state after leaving the group: the composer is suppressed above and
            // this banner takes its place, as the reply thread already does.
            if isConversationFrozen {
                FrozenConversationBanner()
                    .background(Color.naarsCardBackground.ignoresSafeArea(edges: .bottom))
            }
        }
        .onChange(of: viewModel.messages.last?.id) { previousNewestId, _ in
            // The user wrote in this thread (here or in the reply thread). If they had hidden
            // it with Delete it belongs in the Messages list again; it used to stay hidden
            // until someone else replied. A nil previous id is the first load, not a send.
            guard previousNewestId != nil,
                  let newest = viewModel.messages.last,
                  newest.messageType != .system,
                  isFromCurrentUser(newest) else { return }
            participantsViewModel.unhideConversation()
        }
        .sheet(isPresented: $showLocationPicker, onDismiss: coverDismissed) {
            LocationPickerSheet { coordinate, name in
                viewModel.clearOwnTypingStatus()
                Task {
                    await runMessageAction {
                        await viewModel.sendLocationMessage(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            locationName: name,
                            replyToId: replyingToMessage?.id
                        )
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        replyingToMessage = nil
                    }
                }
            }
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
            participantProfiles: participantsViewModel.participants,
            hasLeftConversation: isConversationFrozen,
            onActionFailure: { threadActionErrorMessage = $0 }
        )
    }

    // MARK: - Message Interaction Overlay

    // MARK: - Overlay Action Handler (routed from UIKit MessageOverlayController)

    private func handleOverlayAction(_ action: OverlayAction, for message: Message) {
        guard !message.isModerationHidden else { return }

        switch action {
        case .react(let emoji):
            Task { await addReaction(emoji, to: message) }
        case .removeReaction:
            Task { await removeReaction(from: message) }
        case .reply:
            withAnimation(.easeOut(duration: 0.2)) {
                replyingToMessage = replyContext(for: message)
            }
        case .viewThread(let parentId):
            activeThreadParent = ThreadParent(id: parentId)
        case .copy:
            UIPasteboard.general.string = message.text
        case .edit:
            withAnimation(.easeOut(duration: 0.2)) {
                replyingToMessage = nil
                viewModel.startEditing(message)
            }
        case .unsend:
            showUnsendConfirmation = true
            messageToUnsend = message
        case .deleteForMe:
            Task { await viewModel.deleteMessageForMe(message) }
        case .report:
            messageToReport = message
        }
    }

    private func scrollToMessage(_ messageId: UUID) {
        guard viewModel.messages.contains(where: { $0.id == messageId }) else {
            // Older than the loaded pages (a search hit, a reply's original): page back to it.
            loadOlderMessages(toReveal: messageId)
            return
        }
        cancelLocatingMessage()

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

    /// Pages older messages in until `messageId` is part of the transcript, then scrolls to it.
    /// The thread loads its newest messages only, while search covers the whole history and a
    /// reply can quote any message; for a target outside the loaded pages the search counter
    /// moved and nothing else happened. The messages controller scrolls to a pending search
    /// target itself as soon as it enters the snapshot. Bounded, and it stops when paging
    /// stops adding messages (the beginning of the conversation, a failed fetch).
    private func loadOlderMessages(toReveal messageId: UUID) {
        locateMessageTask?.cancel()
        guard viewModel.hasMoreMessages else {
            locatingMessageId = nil
            return
        }
        locatingMessageId = messageId
        locateMessageTask = Task {
            var passes = 0
            var stalledPasses = 0
            while !Task.isCancelled,
                  !viewModel.messages.contains(where: { $0.id == messageId }),
                  viewModel.hasMoreMessages,
                  passes < Self.locateMessageMaxPasses,
                  stalledPasses < Self.locateMessageMaxStalledPasses {
                passes += 1
                let countBefore = viewModel.messages.count
                if !viewModel.isLoadingMore {
                    await viewModel.loadMoreMessages()
                }
                // A loaded page reaches `viewModel.messages` through the repository publisher,
                // one main-actor hop after the fetch returns.
                try? await Task.sleep(nanoseconds: Self.locateMessageSettleNanoseconds)
                stalledPasses = viewModel.messages.count > countBefore ? 0 : stalledPasses + 1
            }
            // Cancelled: a newer target, a closed search or a closed thread owns the state now.
            guard !Task.isCancelled else { return }
            locatingMessageId = nil
            if viewModel.messages.contains(where: { $0.id == messageId }) {
                scrollToMessage(messageId)
            }
        }
    }

    private func cancelLocatingMessage() {
        locateMessageTask?.cancel()
        locateMessageTask = nil
        locatingMessageId = nil
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
}

/// ViewModel for managing conversation participants
@MainActor
final class ConversationParticipantsViewModel: ObservableObject {
    @Published var participants: [Profile] = []
    @Published var conversationDetail: ConversationWithDetails?
    @Published var isLoading = false
    @Published var error: AppError?
    
    let conversationId: UUID
    private let messageService = MessageService.shared
    private let conversationService: any ConversationServiceProtocol
    private let participantService = ConversationParticipantService.shared
    
    init(
        conversationId: UUID,
        conversationService: any ConversationServiceProtocol = ConversationService.shared
    ) {
        self.conversationId = conversationId
        self.conversationService = conversationService
    }
    
    func loadConversationDetails() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            if let detail = try await conversationService.fetchConversationWithDetails(
                conversationId: conversationId,
                userId: userId
            ) {
                conversationDetail = detail
            }
        } catch {
            AppLogger.error("messaging", "Error loading conversation details: \(error.localizedDescription)")
        }
    }
    
    var participantIds: [UUID] {
        participants.map { $0.id }
    }

    /// Bring this thread back into the Messages list if the user had hidden it with Delete.
    /// Called when they write in it. The hidden flag is a per-user UserDefaults entry, so
    /// this is local and a no-op for a thread that is not hidden.
    func unhideConversation() {
        guard let userId = AuthService.shared.currentUserId else { return }
        conversationService.unhideConversationForUser(conversationId: conversationId, userId: userId)
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
            let freshParticipantIds = try await participantService.fetchActiveParticipantIds(conversationId: conversationId)

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

// MARK: - Thread View

private struct ThreadParent: Identifiable {
    let id: UUID
}

/// What the auto-scroll logic watches: how many messages are loaded and which is newest.
/// With both, growth above an unchanged newest message (older pages) can be told from a new
/// message at the bottom.
private struct TranscriptEdge: Equatable {
    let count: Int
    let newestId: UUID?
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

// MARK: - Message Action Failures

extension AppError {
    /// Text shown when a message action (send, edit, unsend, reaction) fails: the main
    /// thread's error banner and the reply thread's toast. `errorDescription` wraps some
    /// cases in English ("Processing error: …"); the messages these actions attach are
    /// already localized, so they are shown as they are.
    /// - Parameter processingFailureText: shown instead of the raw service text for a plain
    ///   `.processingError`
    func messageActionText(processingFailureText: String?) -> String {
        switch self {
        case .conversationFrozen:
            return "messaging_left_conversation".localized
        case .rateLimitExceeded(let message), .invalidInput(let message):
            return message
        case .processingError(let message):
            return processingFailureText ?? message
        default:
            return localizedDescription
        }
    }

    /// True for a send refused before an optimistic bubble exists (rate limit, over-long
    /// text). The composer has already cleared itself by then, so the draft is handed back.
    var isSendRefusedBeforeBubble: Bool {
        switch self {
        case .rateLimitExceeded, .invalidInput:
            return true
        default:
            return false
        }
    }
}

#Preview {
    NavigationStack {
        ConversationDetailView(conversationId: UUID())
    }
}

