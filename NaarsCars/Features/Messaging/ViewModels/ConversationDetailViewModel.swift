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
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreMessages: Bool = true
    @Published var error: AppError?
    @Published var messageText: String = ""
    
    let searchManager: ConversationSearchManager
    let typingManager: TypingIndicatorManager
    let paginationManager: MessagePaginationManager
    let sendManager: MessageSendManager
    
    var typingUsers: [TypingUser] { typingManager.typingUsers }
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
    var unreadCount: Int {
        guard let userId = authService.currentUserId else { return 0 }
        return messages.filter { message in
            message.fromId != userId && !message.readBy.contains(userId)
        }.count
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
        setupManagerObservation()
    }
    
    deinit {
        if let observer = conversationUpdatedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Forward objectWillChange from child managers so the view updates
    private func setupManagerObservation() {
        searchManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        typingManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        paginationManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sendManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
    
    func loadMessages() async {
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
            forName: NSNotification.Name("conversationUpdated"),
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
        await sendManager.unsendMessage(
            id: id,
            getMessages: { [weak self] in self?.messages ?? [] },
            setMessages: { [weak self] updated in self?.messages = updated }
        ) { [weak self] appError in
            self?.error = appError
        }
    }
    
    // MARK: - Audio Messages
    
    /// Send an audio message
    func sendAudioMessage(audioURL: URL, duration: Double, replyToId: UUID? = nil) async {
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
        
        messages = paginationManager.insertNewMessage(newMessage, into: messages)
        scheduleReplyContextHydration()
        
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
