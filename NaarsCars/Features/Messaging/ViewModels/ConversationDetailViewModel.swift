//
//  ConversationDetailViewModel.swift
//  NaarsCars
//
//  ViewModel for conversation detail (chat)
//

import Foundation
import UIKit
import SwiftUI
internal import Combine

/// ViewModel for conversation detail
@MainActor
final class ConversationDetailViewModel: ObservableObject {
    @Published var messages: [Message] = [] {
        didSet {
            recomputeCellConfigurationsIncrementally(oldMessages: oldValue)
            recomputeUnreadCount()
        }
    }
    @Published private(set) var messageCellConfigurations: [UUID: MessageCellConfiguration] = [:]
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreMessages: Bool = true
    @Published var error: AppError?
    @Published var messageText: String = ""
    
    let searchManager: ConversationSearchManager
    let typingManager: TypingIndicatorManager
    let paginationManager: MessagePaginationManager
    let sendManager: MessageSendManager
    
    @Published private(set) var typingUsers: [TypingUser] = []
    var searchText: String {
        get { searchManager.searchText }
        set { searchManager.searchText = newValue }
    }
    var searchResults: [Message] { searchManager.searchResults }
    var currentSearchIndex: Int {
        get { searchManager.currentSearchIndex }
        set { searchManager.currentSearchIndex = newValue }
    }
    var isSearchActive: Bool {
        get { searchManager.isSearchActive }
        set { searchManager.isSearchActive = newValue }
    }
    var isSearchingMessages: Bool { searchManager.isSearchingMessages }
    var isLoadingOlderSearchResults: Bool { searchManager.isLoadingOlderSearchResults }
    var canLoadOlderSearchResults: Bool { searchManager.canLoadOlderSearchResults }
    @Published var editingMessage: Message? = nil
    @Published private(set) var unreadCount: Int = 0
    /// Set when the current user has left this conversation. The group messaging plan
    /// (Docs/plans/2026-03-07-group-messaging-enhancement-plan.md) specifies a frozen
    /// UI state, but the view layer does not yet read this property. See plan Task 18.
    @Published private(set) var hasLeftConversation: Bool = false

    /// Tracks whether the unread divider has been shown for this session.
    /// Once the user scrolls past it, this becomes `true` and the divider is not re-shown.
    @Published var hasShownUnreadDivider: Bool = false

    /// The first unread message ID from the initial load, forwarded from the pagination manager.
    var firstUnreadMessageId: UUID? {
        paginationManager.firstUnreadMessageId
    }

    let conversationId: UUID
    private let messageService: any MessageServiceProtocol
    private let authService: any AuthServiceProtocol
    private let repository = MessagingRepository.shared
    private let throttler = Throttler.shared
    private var cancellables = Set<AnyCancellable>()
    private var conversationUpdatedObserver: NSObjectProtocol?
    
    init(
        conversationId: UUID,
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.conversationId = conversationId
        self.messageService = messageService
        self.authService = authService
        self.searchManager = ConversationSearchManager(conversationId: conversationId)
        self.typingManager = TypingIndicatorManager(conversationId: conversationId)
        self.paginationManager = MessagePaginationManager()
        self.sendManager = MessageSendManager()
        setupLocalObservation()
        setupMetadataObservation()
        setupConversationUpdatedObserver()
        setupReactionChangedObserver()
        observeTypingUsers()
    }
    
    // MARK: - Cell Configuration Cache

    /// Recompute unread count from the current messages array.
    /// Called automatically via the `messages` didSet observer.
    private func recomputeUnreadCount() {
        guard let userId = authService.currentUserId else {
            unreadCount = 0
            return
        }
        unreadCount = messages.filter { message in
            message.fromId != userId && !message.readBy.contains(userId)
        }.count
    }

    /// Full recomputation — used only for initial load or major changes.
    private func recomputeAllCellConfigurations() {
        var configs: [UUID: MessageCellConfiguration] = [:]
        for (index, message) in messages.enumerated() {
            configs[message.id] = MessageCellConfiguration(
                messageId: message.id,
                isFirstInSeries: isFirstInSeries(at: index),
                isLastInSeries: isLastInSeries(at: index),
                showDateSeparator: shouldShowDateSeparator(at: index)
            )
        }
        messageCellConfigurations = configs
    }

    /// Incremental recomputation — only update configs for changed/new messages
    /// and their immediate neighbors whose series flags may have changed.
    private func recomputeCellConfigurationsIncrementally(oldMessages: [Message]) {
        // Fall back to full recompute if the change is complex
        let oldIds = oldMessages.map { $0.id }
        let newIds = messages.map { $0.id }

        // If more than a few messages changed, full recompute is simpler
        if abs(newIds.count - oldIds.count) > 3 || oldIds.isEmpty {
            recomputeAllCellConfigurations()
            return
        }

        // Find indices that need recomputation
        var indicesToRecompute = Set<Int>()

        // Find new message IDs not in old set
        let oldIdSet = Set(oldIds)
        for (index, id) in newIds.enumerated() {
            if !oldIdSet.contains(id) {
                // New message + neighbors
                indicesToRecompute.insert(index)
                if index > 0 { indicesToRecompute.insert(index - 1) }
                if index < newIds.count - 1 { indicesToRecompute.insert(index + 1) }
            }
        }

        // If no new messages but count/order changed, full recompute
        if indicesToRecompute.isEmpty && oldIds != newIds {
            recomputeAllCellConfigurations()
            return
        }

        // If truly nothing changed, skip entirely
        if indicesToRecompute.isEmpty { return }

        // Update only affected configs
        var configs = messageCellConfigurations
        for index in indicesToRecompute where index < messages.count {
            let message = messages[index]
            configs[message.id] = MessageCellConfiguration(
                messageId: message.id,
                isFirstInSeries: isFirstInSeries(at: index),
                isLastInSeries: isLastInSeries(at: index),
                showDateSeparator: shouldShowDateSeparator(at: index)
            )
        }

        // Remove configs for messages no longer present
        let newIdSet = Set(newIds)
        for id in configs.keys where !newIdSet.contains(id) {
            configs.removeValue(forKey: id)
        }

        messageCellConfigurations = configs
    }

    /// Check if message is the first in a consecutive series from the same sender
    private func isFirstInSeries(at index: Int) -> Bool {
        MessageSeriesHelper.isFirstInSeries(messages: messages, at: index)
    }

    /// Check if message is the last in a consecutive series from the same sender
    private func isLastInSeries(at index: Int) -> Bool {
        MessageSeriesHelper.isLastInSeries(messages: messages, at: index)
    }

    /// Check if we should show a date separator before this message
    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true } // Always show for first message

        let currentMessage = messages[index]
        let previousMessage = messages[index - 1]

        // Check if different day
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: currentMessage.createdAt)
        let previousDay = calendar.startOfDay(for: previousMessage.createdAt)

        return currentDay != previousDay
    }

    deinit {
        if let observer = conversationUpdatedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Call from view onDisappear to cancel in-flight work and observers so VM can tear down safely.
    func stop() {
        AppLogger.info("messaging", "[ConversationDetailVM] stop() called; removing conversation observer, stopping typing and search")
        if let observer = conversationUpdatedObserver {
            NotificationCenter.default.removeObserver(observer)
            conversationUpdatedObserver = nil
        }
        typingManager.stopTypingObservation()
        searchManager.stop()
        MessagingSyncEngine.shared.teardownReactionsSubscription(conversationId: conversationId)
    }

    private func setupLocalObservation() {
        repository.getMessagesPublisher(for: conversationId)
            .sink { [weak self] updatedMessages in
                guard let self = self, self.repository.isConfigured else { return }
                
                // Skip redundant updates — if IDs and count match, nothing changed
                let currentIds = self.messages.map { $0.id }
                let updatedIds = updatedMessages.map { $0.id }
                guard currentIds != updatedIds else { return }
                
                // All messages (including pending/failed) now come from SwiftData
                self.messages = updatedMessages
                self.scheduleReplyContextHydration()
            }
            .store(in: &cancellables)
    }
    
    /// Subscribe to metadata-only updates (readBy changes) to avoid full list re-renders
    private func setupMetadataObservation() {
        repository.getMessageMetadataPublisher(for: conversationId)
            .sink { [weak self] update in
                guard let self = self else { return }
                // Update the specific message's readBy in-place without replacing the entire array
                if let index = self.messages.firstIndex(where: { $0.id == update.messageId }) {
                    self.messages[index].readBy = update.readBy
                }
            }
            .store(in: &cancellables)
    }

    /// Subscribe to real-time reaction changes and refresh the affected message's reactions
    private func setupReactionChangedObserver() {
        NotificationCenter.default.publisher(for: .messageReactionChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let messageId = notification.userInfo?["messageId"] as? UUID,
                      let convId = notification.userInfo?["conversationId"] as? UUID,
                      convId == self.conversationId else { return }
                Task {
                    await self.refreshReactions(for: messageId)
                }
            }
            .store(in: &cancellables)
    }

    /// Bridge @Observable typing manager changes to @Published for ObservableObject consumers.
    /// Uses withObservationTracking to re-register after each change.
    private func observeTypingUsers() {
        withObservationTracking {
            let users = self.typingManager.typingUsers
            if users != self.typingUsers {
                self.typingUsers = users
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeTypingUsers()
            }
        }
    }

    private func refreshReactions(for messageId: UUID) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        do {
            let reactions = try await MessageReactionService.shared.fetchReactions(messageId: messageId)
            messages[index].reactions = reactions.reactions.isEmpty ? nil : reactions
        } catch {
            AppLogger.error("messaging", "Failed to refresh reactions: \(error)")
        }
    }
    
    func checkLeftStatus() async {
        guard let userId = authService.currentUserId else { return }
        let hasLeft = await ConversationParticipantService.shared.hasUserLeftConversation(
            conversationId: conversationId,
            userId: userId
        )
        self.hasLeftConversation = hasLeft
    }

    func loadMessages() async {
        await checkLeftStatus()
        error = nil
        await paginationManager.loadMessages(
            conversationId: conversationId,
            repository: repository,
            authService: authService
        ) { [weak self] userId in
            await self?.markConversationReadImmediately(userId: userId)
        } setMessages: { [weak self] updated in
            self?.messages = updated
        } getMessages: { [weak self] in
            self?.messages ?? []
        } setIsLoading: { [weak self] value in
            self?.isLoading = value
        } setHasMoreMessages: { [weak self] value in
            self?.hasMoreMessages = value
        }
        MessagingSyncEngine.shared.setupReactionsSubscription(conversationId: conversationId)

        // Hydrate reactions for loaded messages (reactions aren't included in the messages query)
        await loadReactionsForMessages()
    }

    /// Fetch reactions for all currently loaded messages.
    /// Results are collected first, then applied in a single batch mutation
    /// to avoid triggering N separate SwiftUI re-renders.
    private func loadReactionsForMessages() async {
        let messageIds = messages.map(\.id)
        guard !messageIds.isEmpty else { return }

        var results: [(UUID, MessageReactions?)] = []
        await withTaskGroup(of: (UUID, MessageReactions?).self) { group in
            for id in messageIds {
                group.addTask {
                    let reactions = try? await MessageReactionService.shared.fetchReactions(messageId: id)
                    return (id, reactions)
                }
            }
            for await result in group {
                results.append(result)
            }
        }

        // Single batch mutation — one re-render instead of N
        for (id, reactions) in results {
            if let index = messages.firstIndex(where: { $0.id == id }) {
                let hasReactions = reactions != nil && !(reactions!.reactions.isEmpty)
                messages[index].reactions = hasReactions ? reactions : nil
            }
        }
    }
    
    func loadMoreMessages() async {
        await paginationManager.loadMoreMessages(
            conversationId: conversationId,
            messageService: messageService,
            repository: repository,
            getMessages: { [weak self] in self?.messages ?? [] },
            getIsLoadingMore: { [weak self] in self?.isLoadingMore ?? false },
            setIsLoadingMore: { [weak self] value in self?.isLoadingMore = value },
            getHasMoreMessages: { [weak self] in self?.hasMoreMessages ?? false },
            setHasMoreMessages: { [weak self] value in self?.hasMoreMessages = value }
        ) { [weak self] in
            self?.scheduleReplyContextHydration()
        }
    }
    
    func sendMessage(textOverride: String? = nil, image: UIImage? = nil, replyToId: UUID? = nil) async {
        guard !hasLeftConversation else {
            AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
            error = .conversationFrozen
            return
        }
        let effectiveText = textOverride ?? messageText
        await sendManager.sendMessage(
            conversationId: conversationId,
            messageText: effectiveText,
            image: image,
            replyToId: replyToId
        ) { [weak self] updated in
            self?.messageText = updated
        } setError: { [weak self] appError in
            self?.error = appError
        }
    }
    
    private func setupConversationUpdatedObserver() {
        conversationUpdatedObserver = NotificationCenter.default.addObserver(
            forName: .conversationUpdated,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let userInfo = notification.userInfo as? [String: Any]
            let notifName = notification.name
            Task { @MainActor [weak self] in
                let safeNotification = Notification(name: notifName, userInfo: userInfo)
                self?.handleConversationUpdatedImmediate(safeNotification)
            }
        }
    }
    
    private func handleConversationUpdatedImmediate(_ notification: Notification) {
        guard let updatedId = notificationConversationId(notification),
              updatedId == conversationId else {
            return
        }
        
        if let message = notification.userInfo?["message"] as? Message {
            let event = notification.userInfo?["event"] as? String
            var shouldBackgroundSync = false
            switch event {
            case "update":
                handleMessageUpdate(message)
            case "delete":
                handleMessageDelete(message)
                shouldBackgroundSync = true
            default:
                handleNewMessage(message)
            }

            guard shouldBackgroundSync else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.throttler.run(
                    key: "messages.sync.\(self.conversationId.uuidString)",
                    minimumInterval: Constants.RateLimits.throttleLastSeen
                ) {
                    await self.refreshMessagesInBackground()
                }
            }
        }
    }

    private func notificationConversationId(_ notification: Notification) -> UUID? {
        if let uuid = notification.object as? UUID {
            return uuid
        }
        if let nsuuid = notification.object as? NSUUID {
            return nsuuid as UUID
        }
        return nil
    }
    
    private func refreshMessagesInBackground() async {
        do {
            try await repository.syncMessages(conversationId: conversationId)
        } catch {
            AppLogger.warning("messaging", "[ConversationDetailVM] Background sync failed: \(error.localizedDescription)")
        }
    }

    private func scheduleReplyContextHydration() {
        guard messages.contains(where: { $0.replyToId != nil && $0.replyToMessage == nil }) else { return }

        Task { [weak self] in
            guard let self = self else { return }
            await self.throttler.run(
                key: "messages.replyContext.\(self.conversationId.uuidString)",
                minimumInterval: Constants.RateLimits.throttleMarkRead
            ) {
                let snapshot = await MainActor.run { self.messages }
                guard snapshot.contains(where: { $0.replyToId != nil && $0.replyToMessage == nil }) else { return }

                let enriched = await self.paginationManager.hydrateReplyContexts(from: snapshot)
                await MainActor.run {
                    guard enriched != self.messages else { return }
                    self.messages = enriched
                }
            }
        }
    }
    
    // MARK: - Edit & Unsend Messages
    
    /// Start editing a message — populates the input bar with the message text
    func startEditing(_ message: Message) {
        editingMessage = message
        messageText = message.text
    }
    
    /// Cancel editing mode and clear the input bar
    func cancelEdit() {
        editingMessage = nil
        messageText = ""
    }
    
    /// Submit an edit for the currently-editing message
    func editMessage(newContent: String) async {
        guard !hasLeftConversation else {
            AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
            error = .conversationFrozen
            return
        }
        await sendManager.editMessage(
            newContent: newContent,
            editingMessage: editingMessage,
            getMessages: { [weak self] in self?.messages ?? [] },
            setMessages: { [weak self] updated in self?.messages = updated }
        ) { [weak self] appError in
            self?.error = appError
        }
        editingMessage = nil
        messageText = ""
    }
    
    /// Unsend a message (soft delete — clears content and sets deleted_at)
    func unsendMessage(id: UUID) async {
        guard !hasLeftConversation else {
            AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
            error = .conversationFrozen
            return
        }
        await sendManager.unsendMessage(
            id: id,
            getMessages: { [weak self] in self?.messages ?? [] },
            setMessages: { [weak self] updated in self?.messages = updated }
        ) { [weak self] appError in
            self?.error = appError
        }
    }
    
    // MARK: - Delete for Me

    /// Hide a message locally ("Delete for Me") — does NOT delete from server.
    func deleteMessageForMe(_ message: Message) async {
        repository.deleteMessageForMe(messageId: message.id, conversationId: conversationId)
        messages.removeAll { $0.id == message.id }
    }

    // MARK: - Audio Messages
    
    /// Send an audio message
    func sendAudioMessage(audioURL: URL, duration: Double, replyToId: UUID? = nil) async {
        guard !hasLeftConversation else {
            AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
            error = .conversationFrozen
            return
        }
        await sendManager.sendAudioMessage(
            conversationId: conversationId,
            audioURL: audioURL,
            duration: duration,
            replyToId: replyToId
        ) { [weak self] appError in
            self?.error = appError
        }
    }
    
    // MARK: - Location Messages
    
    /// Send a location message
    func sendLocationMessage(latitude: Double, longitude: Double, locationName: String?, replyToId: UUID? = nil) async {
        guard !hasLeftConversation else {
            AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
            error = .conversationFrozen
            return
        }
        await sendManager.sendLocationMessage(
            conversationId: conversationId,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            replyToId: replyToId
        ) { [weak self] appError in
            self?.error = appError
        }
    }
    
    
    // MARK: - Retry Failed Messages
    
    /// Retry sending a failed message by flipping its status back to .sending
    func retryMessage(id: UUID) async {
        await sendManager.retryMessage(
            id: id,
            conversationId: conversationId,
            messages: messages
        ) { [weak self] appError in
            self?.error = appError
        }
    }
    
    /// Dismiss a failed message (remove it from SwiftData and the list)
    func dismissFailedMessage(id: UUID) {
        sendManager.dismissFailedMessage(id: id, conversationId: conversationId)
        messages.removeAll { $0.id == id }
    }
    
    func addReaction(messageId: UUID, reaction: String) async {
        guard !hasLeftConversation else {
            AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
            error = .conversationFrozen
            return
        }
        await sendManager.addReaction(
            messageId: messageId,
            reaction: reaction,
            messages: messages
        ) { [weak self] updated in
            self?.messages = updated
        } setError: { [weak self] appError in
            self?.error = appError
        }
    }
    
    func removeReaction(messageId: UUID) async {
        guard !hasLeftConversation else {
            AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
            error = .conversationFrozen
            return
        }
        await sendManager.removeReaction(
            messageId: messageId,
            messages: messages
        ) { [weak self] updated in
            self?.messages = updated
        } setError: { [weak self] appError in
            self?.error = appError
        }
    }
    
    private func handleNewMessage(_ newMessage: Message) {
        // Only add if it's for this conversation and not already in list
        guard newMessage.conversationId == conversationId,
              !messages.contains(where: { $0.id == newMessage.id }) else {
            return
        }

        // Skip messages the user has locally deleted ("Delete for Me")
        let deletedIds = repository.fetchLocallyDeletedMessageIds(for: conversationId)
        guard !deletedIds.contains(newMessage.id) else { return }

        // Skip messages from blocked users
        if MessageService.shared.isBlocked(newMessage.fromId) { return }

        messages = paginationManager.insertNewMessage(newMessage, into: messages)
        scheduleReplyContextHydration()

        // Haptic feedback for incoming messages
        if newMessage.fromId != authService.currentUserId {
            HapticManager.lightImpact()
        }

        // Keep read receipts immediate for incoming messages while throttling last_seen writes.
        if let userId = authService.currentUserId,
           newMessage.fromId != userId {
            Task {
                await markConversationReadImmediately(userId: userId)
            }
        }
    }
    
    private func handleMessageUpdate(_ updatedMessage: Message) {
        guard updatedMessage.conversationId == conversationId else { return }
        
        messages = paginationManager.applyMessageUpdate(updatedMessage, in: messages)
        scheduleReplyContextHydration()
    }
    
    private func handleMessageDelete(_ deletedMessage: Message) {
        messages = paginationManager.applyMessageDelete(deletedMessage, from: messages)
    }

    private func markConversationReadImmediately(userId: UUID) async {
        await paginationManager.markConversationReadImmediately(
            conversationId: conversationId,
            messages: messages,
            userId: userId,
            messageService: messageService,
            throttler: throttler
        )
    }

    private func scheduleLastSeenHeartbeat(userId: UUID) async {
        await paginationManager.scheduleLastSeenHeartbeat(
            conversationId: conversationId,
            userId: userId,
            messageService: messageService,
            throttler: throttler
        )
    }

    func conversationDidAppear() {
        if conversationUpdatedObserver == nil {
            setupConversationUpdatedObserver()
        }
        guard let userId = authService.currentUserId else { return }
        Task {
            await scheduleLastSeenHeartbeat(userId: userId)
        }
    }

    func conversationMessageListDidChange() {
        guard let userId = authService.currentUserId else { return }
        Task {
            await scheduleLastSeenHeartbeat(userId: userId)
        }
    }
    
    // MARK: - Search Delegation
    
    /// Search for messages matching the search text within this conversation
    func searchInConversation() {
        searchManager.searchInConversation()
    }
    
    /// Navigate to the next search result (newer message)
    func nextSearchResult() {
        searchManager.nextSearchResult()
    }
    
    /// Navigate to the previous search result (older message)
    func previousSearchResult() {
        searchManager.previousSearchResult()
    }

    /// Load older search results (matches before the current oldest result).
    func loadOlderSearchResults() {
        searchManager.loadOlderSearchResults()
    }
    
    /// The currently focused search result message ID
    var currentSearchResultId: UUID? {
        searchManager.currentSearchResultId
    }
    
    /// Toggle search mode on/off
    func toggleSearch() {
        searchManager.toggleSearch()
    }
    
    // MARK: - Typing Delegation
    
    /// Start realtime observation for typing users in this conversation
    func startTypingObservation() {
        typingManager.startTypingObservation()
    }
    
    /// Stop realtime observation for typing users
    func stopTypingObservation() {
        typingManager.stopTypingObservation()
    }
    
    /// Signal that the current user is typing (debounced)
    func userDidType() {
        typingManager.userDidType()
    }
    
    /// Clear own typing status (e.g. after sending a message)
    func clearOwnTypingStatus() {
        typingManager.clearOwnTypingStatus()
    }
    
}
