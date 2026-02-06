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
    
    /// IDs of messages that failed to send (kept in the list for retry)
    @Published var failedMessageIds: Set<UUID> = []
    // MARK: - Extracted Managers
    
    /// Manages in-conversation search state and logic
    let searchManager: ConversationSearchManager
    
    /// Manages typing indicator polling and status updates
    let typingManager: TypingIndicatorManager
    
    /// Convenience accessor for typing users (from manager)
    var typingUsers: [TypingUser] { typingManager.typingUsers }
    
    /// Convenience accessor for search text (from manager)
    var searchText: String {
        get { searchManager.searchText }
        set { searchManager.searchText = newValue }
    }
    
    /// Convenience accessor for search results (from manager)
    var searchResults: [Message] { searchManager.searchResults }
    
    /// Convenience accessor for current search index (from manager)
    var currentSearchIndex: Int {
        get { searchManager.currentSearchIndex }
        set { searchManager.currentSearchIndex = newValue }
    }
    
    /// Convenience accessor for search active state (from manager)
    var isSearchActive: Bool {
        get { searchManager.isSearchActive }
        set { searchManager.isSearchActive = newValue }
    }
    
    /// Convenience accessor for searching state (from manager)
    var isSearchingMessages: Bool { searchManager.isSearchingMessages }
    
    /// The message currently being edited (nil when not editing)
    @Published var editingMessage: Message? = nil
    
    /// Count of unread messages (messages not from current user that haven't been read)
    var unreadCount: Int {
        guard let userId = authService.currentUserId else { return 0 }
        return messages.filter { message in
            message.fromId != userId && !message.readBy.contains(userId)
        }.count
    }
    
    let conversationId: UUID
    private let messageService = MessageService.shared
    private let mediaService = MessageMediaService.shared
    private let reactionService = MessageReactionService.shared
    private let authService = AuthService.shared
    private let repository = MessagingRepository.shared
    private let throttler = Throttler.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 25
    private var oldestMessageId: UUID?
    private var conversationUpdatedObserver: NSObjectProtocol?
    
    /// Maps a local optimistic message UUID to the parameters needed for retry
    private var pendingMessageParams: [UUID: PendingMessageParams] = [:]
    
    /// Maps a local optimistic UUID so we can match it when the server response arrives
    private var optimisticIdMap: [UUID: OptimisticMessageInfo] = [:]
#if DEBUG
    private var lastReplyDebugSnapshot: (total: Int, replyIds: Int, replyContexts: Int) = (-1, -1, -1)
#endif
    
    /// Parameters saved for retrying a failed message send
    struct PendingMessageParams {
        let text: String
        let imageUrl: String?
        let replyToId: UUID?
    }
    
    /// Info tracked for an optimistic message so we can match server responses
    struct OptimisticMessageInfo {
        let localId: UUID
        let text: String
        let fromId: UUID
        let timestamp: Date
    }
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        self.searchManager = ConversationSearchManager(conversationId: conversationId)
        self.typingManager = TypingIndicatorManager(conversationId: conversationId)
        setupLocalObservation()
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
    }
    
    private func setupLocalObservation() {
        repository.getMessagesPublisher(for: conversationId)
            .sink { [weak self] updatedMessages in
                guard let self = self, self.repository.isConfigured else { return }
                // Preserve any failed optimistic messages that only exist in-memory
                if self.failedMessageIds.isEmpty {
                    self.messages = updatedMessages
                } else {
                    let failedMessages = self.messages.filter { self.failedMessageIds.contains($0.id) }
                    var merged = updatedMessages
                    for failedMsg in failedMessages where !merged.contains(where: { $0.id == failedMsg.id }) {
                        merged.append(failedMsg)
                    }
                    merged.sort { $0.createdAt < $1.createdAt }
                    self.messages = merged
                }
                self.scheduleReplyContextHydration()
#if DEBUG
                self.logReplyDebugSnapshot(source: "publisher(local)", messages: self.messages)
#endif
            }
            .store(in: &cancellables)
    }
    
    /// Guard to prevent concurrent loadMessages calls causing UI flicker
    private var isLoadingMessagesInFlight = false
    
    func loadMessages() async {
        guard !isLoadingMessagesInFlight else { return }
        isLoadingMessagesInFlight = true
        defer { isLoadingMessagesInFlight = false }
        
        isLoading = true
        error = nil
        oldestMessageId = nil
        // Assume there are more messages until we know otherwise from the server
        hasMoreMessages = true
        
        do {
            let localMessages = try repository.getMessages(for: conversationId)
            // Preserve failed optimistic messages when reloading
            if failedMessageIds.isEmpty {
                self.messages = localMessages
            } else {
                let failedMessages = self.messages.filter { failedMessageIds.contains($0.id) }
                var merged = localMessages
                for failedMsg in failedMessages where !merged.contains(where: { $0.id == failedMsg.id }) {
                    merged.append(failedMsg)
                }
                merged.sort { $0.createdAt < $1.createdAt }
                self.messages = merged
            }
            scheduleReplyContextHydration()
#if DEBUG
            logReplyDebugSnapshot(source: "loadMessages(local)", messages: self.messages)
#endif
        } catch {
            AppLogger.warning("messaging", "[ConversationDetailVM] Error loading local messages: \(error.localizedDescription)")
        }
        
        // Update last_seen and mark as read when loading
        if let userId = authService.currentUserId {
            try? await messageService.updateLastSeen(conversationId: conversationId, userId: userId)
            try? await messageService.markAsRead(conversationId: conversationId, userId: userId)
            await BadgeCountManager.shared.clearMessagesBadge(for: conversationId)
        }
        
        // Fetch from network to get the initial page and set proper pagination state
        do {
            let networkMessages = try await messageService.fetchMessages(conversationId: conversationId, limit: pageSize)
            
            // Merge network messages into local
            var merged = self.messages
            let existingIds = Set(merged.map { $0.id })
            for msg in networkMessages where !existingIds.contains(msg.id) {
                merged.append(msg)
            }
            // Update existing messages with fresh data from network
            for msg in networkMessages {
                if let idx = merged.firstIndex(where: { $0.id == msg.id }) {
                    // Preserve reply context if we already hydrated it
                    var updated = msg
                    if updated.replyToMessage == nil, let existing = merged[idx].replyToMessage {
                        updated.replyToMessage = existing
                    }
                    merged[idx] = updated
                }
            }
            merged.sort { $0.createdAt < $1.createdAt }
            self.messages = merged
            
            // Set pagination state from what the server returned
            oldestMessageId = merged.first?.id
            hasMoreMessages = networkMessages.count >= pageSize
            
            scheduleReplyContextHydration()
        } catch {
            // Fall back to local data — set pagination from what we have
            oldestMessageId = messages.first?.id
            hasMoreMessages = messages.count >= pageSize
            AppLogger.warning("messaging", "[ConversationDetailVM] Network fetch failed, using local: \(error.localizedDescription)")
        }
        
        // Also sync to SwiftData in background
        Task { [weak self] in
            await self?.refreshMessagesInBackground()
        }
        
        isLoading = false
    }
    
    func loadMoreMessages() async {
        guard !isLoadingMore, hasMoreMessages,
              let beforeId = oldestMessageId else {
            AppLogger.info("messaging", "[ConversationDetailVM] loadMore skipped: isLoadingMore=\(isLoadingMore) hasMore=\(hasMoreMessages) oldestId=\(oldestMessageId?.uuidString ?? "nil")")
            return
        }
        
        isLoadingMore = true
        AppLogger.info("messaging", "[ConversationDetailVM] Loading more messages before \(beforeId)")
        
        do {
            let fetched = try await messageService.fetchMessages(conversationId: conversationId, limit: pageSize, beforeMessageId: beforeId)
            
            // Deduplicate before prepending
            let existingIds = Set(self.messages.map { $0.id })
            let newMessages = fetched.filter { !existingIds.contains($0.id) }
            
            if !newMessages.isEmpty {
                self.messages.insert(contentsOf: newMessages, at: 0)
            }
            
            // Update oldest message to the earliest in the full list
            oldestMessageId = self.messages.first?.id
            hasMoreMessages = fetched.count >= pageSize
            
            AppLogger.info("messaging", "[ConversationDetailVM] Loaded \(fetched.count) older messages (\(newMessages.count) new). hasMore=\(hasMoreMessages)")
            scheduleReplyContextHydration()
        } catch {
            AppLogger.error("messaging", "Error loading more messages: \(error.localizedDescription)")
        }
        
        isLoadingMore = false
    }
    
    func sendMessage(textOverride: String? = nil, image: UIImage? = nil, replyToId: UUID? = nil) async {
        let effectiveText = textOverride ?? messageText
        guard (!effectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil),
              let fromId = authService.currentUserId else {
            return
        }
        
        let text = effectiveText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = "" // Clear input
        HapticManager.lightImpact()
        
        // Upload image first if provided
        var imageUrl: String? = nil
        if let image = image, let imageData = image.resizedForUpload(maxDimension: 1920).jpegData(compressionQuality: 0.7) {
            do {
                imageUrl = try await mediaService.uploadMessageImage(
                    imageData: imageData,
                    conversationId: conversationId,
                    fromId: fromId
                )
            } catch {
                self.error = AppError.processingError("Failed to upload image: \(error.localizedDescription)")
                AppLogger.error("messaging", "Error uploading image: \(error.localizedDescription)")
                return // Don't send message if image upload fails
            }
        }
        
        // Optimistic UI update - generate a local UUID to track this message
        let localId = UUID()
        let optimisticTimestamp = Date()
        var optimisticMessage = Message(
            id: localId,
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            createdAt: optimisticTimestamp,
            replyToId: replyToId
        )
        if let replyToId = replyToId,
           let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
            optimisticMessage.replyToMessage = context
        }
        messages.append(optimisticMessage)
        
        // Track the optimistic message info for matching
        let info = OptimisticMessageInfo(localId: localId, text: text, fromId: fromId, timestamp: optimisticTimestamp)
        optimisticIdMap[localId] = info
        
        // Save params in case we need to retry
        pendingMessageParams[localId] = PendingMessageParams(text: text, imageUrl: imageUrl, replyToId: replyToId)
        
        do {
            var sentMessage = try await messageService.sendMessage(
                conversationId: conversationId,
                fromId: fromId,
                text: text,
                imageUrl: imageUrl,
                replyToId: replyToId
            )
            
            // Attach reply context if available locally
            if let replyToId = replyToId,
               let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
                sentMessage.replyToMessage = context
            }
            
            // Replace optimistic message with real one by local UUID first
            if let index = messages.firstIndex(where: { $0.id == localId }) {
                messages[index] = sentMessage
            } else {
                // Fallback: match by text + timestamp window
                if let index = messages.firstIndex(where: { msg in
                    msg.text == text &&
                    msg.fromId == fromId &&
                    abs(msg.createdAt.timeIntervalSince(optimisticTimestamp)) < 5.0
                }), index < messages.count {
                    messages[index] = sentMessage
                } else {
                    messages.append(sentMessage)
                    messages.sort { $0.createdAt < $1.createdAt }
                }
            }
            
            // Clean up tracking
            optimisticIdMap.removeValue(forKey: localId)
            pendingMessageParams.removeValue(forKey: localId)
        } catch {
            // Keep the optimistic message but mark it as failed
            failedMessageIds.insert(localId)
            HapticManager.error()
            self.error = AppError.processingError(error.localizedDescription)
            AppLogger.error("messaging", "Error sending message: \(error.localizedDescription)")
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
            switch event {
            case "update":
                handleMessageUpdate(message)
            case "delete":
                handleMessageDelete(message)
            default:
                handleNewMessage(message)
            }
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            await self.throttler.run(
                key: "messages.sync.\(self.conversationId.uuidString)",
                minimumInterval: Constants.RateLimits.throttleSend
            ) {
                await self.refreshMessagesInBackground()
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

                let enriched = await Self.buildReplyContexts(from: snapshot)
                await MainActor.run {
                    guard enriched != self.messages else { return }
                    self.messages = enriched
#if DEBUG
                    self.logReplyDebugSnapshot(source: "replyContext(builder)", messages: enriched)
#endif
                }
            }
        }
    }

    nonisolated private static func buildReplyContexts(from messages: [Message]) async -> [Message] {
        let replyParentIds = Set(messages.compactMap { $0.replyToId })
        guard !replyParentIds.isEmpty else { return messages }

        let messagesById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        let senderIds = Set(replyParentIds.compactMap { messagesById[$0]?.fromId })
        var profilesById: [UUID: Profile] = [:]

        for senderId in senderIds {
            if let profile = await CacheManager.shared.getCachedProfile(id: senderId) {
                profilesById[senderId] = profile
            }
        }

        let finalProfiles = profilesById
        return await MainActor.run { ReplyContextBuilder.applyReplyContexts(messages: messages, profilesById: finalProfiles) }
    }

#if DEBUG
    private func logReplyDebugSnapshot(source: String, messages: [Message]) {
        let replyIds = messages.filter { $0.replyToId != nil }.count
        let replyContexts = messages.filter { $0.replyToMessage != nil }.count
        let snapshot = (total: messages.count, replyIds: replyIds, replyContexts: replyContexts)
        guard snapshot != lastReplyDebugSnapshot else { return }
        lastReplyDebugSnapshot = snapshot
        AppLogger.info("messaging", "[ReplyThreadDebug] \(source) total=\(snapshot.total) replyToId=\(snapshot.replyIds) replyContext=\(snapshot.replyContexts)")
        if let sample = messages.first(where: { $0.replyToId != nil }) {
            AppLogger.info("messaging", "[ReplyThreadDebug] sample messageId=\(sample.id) replyToId=\(sample.replyToId?.uuidString ?? "nil") context=\(sample.replyToMessage != nil)")
        }
    }
#endif
    
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
        guard let editMsg = editingMessage else { return }
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Optimistic update
        if let index = messages.firstIndex(where: { $0.id == editMsg.id }) {
            messages[index].text = trimmed
            messages[index].editedAt = Date()
        }
        
        // Clear edit state
        editingMessage = nil
        messageText = ""
        HapticManager.lightImpact()
        
        do {
            try await messageService.updateMessageContent(messageId: editMsg.id, newContent: trimmed)
        } catch {
            // Revert optimistic update on failure
            if let index = messages.firstIndex(where: { $0.id == editMsg.id }) {
                messages[index].text = editMsg.text
                messages[index].editedAt = editMsg.editedAt
            }
            self.error = AppError.processingError("Failed to edit message: \(error.localizedDescription)")
            AppLogger.error("messaging", "Error editing message: \(error.localizedDescription)")
        }
    }
    
    /// Unsend a message (soft delete — clears content and sets deleted_at)
    func unsendMessage(id: UUID) async {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        
        let originalMessage = messages[index]
        
        // Optimistic update
        messages[index].text = ""
        messages[index].deletedAt = Date()
        HapticManager.lightImpact()
        
        do {
            try await messageService.unsendMessage(messageId: id)
        } catch {
            // Revert optimistic update on failure
            if let revertIndex = messages.firstIndex(where: { $0.id == id }) {
                messages[revertIndex].text = originalMessage.text
                messages[revertIndex].deletedAt = originalMessage.deletedAt
            }
            self.error = AppError.processingError("Failed to unsend message: \(error.localizedDescription)")
            AppLogger.error("messaging", "Error unsending message: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Audio Messages
    
    /// Send an audio message
    func sendAudioMessage(audioURL: URL, duration: Double, replyToId: UUID? = nil) async {
        guard let fromId = authService.currentUserId else { return }
        
        do {
            // Read audio data from file
            let audioData = try Data(contentsOf: audioURL)
            
            // Upload audio to storage
            let uploadedUrl = try await mediaService.uploadAudioMessage(
                audioData: audioData,
                conversationId: conversationId,
                fromId: fromId
            )
            
            // Create optimistic message
            var optimisticMessage = Message(
                conversationId: conversationId,
                fromId: fromId,
                messageType: .audio,
                replyToId: replyToId,
                audioUrl: uploadedUrl,
                audioDuration: duration
            )
            if let replyToId = replyToId,
               let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
                optimisticMessage.replyToMessage = context
            }
            messages.append(optimisticMessage)
            
            // Send audio message
            var sentMessage = try await messageService.sendAudioMessage(
                conversationId: conversationId,
                fromId: fromId,
                audioUrl: uploadedUrl,
                duration: duration,
                replyToId: replyToId
            )
            
            if let replyToId = replyToId,
               let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
                sentMessage.replyToMessage = context
            }
            
            // Replace optimistic message
            if let index = messages.firstIndex(where: { $0.audioUrl == uploadedUrl && $0.fromId == fromId }) {
                messages[index] = sentMessage
            }
            
            HapticManager.lightImpact()
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            self.error = AppError.processingError("Failed to send audio: \(error.localizedDescription)")
            AppLogger.error("messaging", "Error sending audio message: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Location Messages
    
    /// Send a location message
    func sendLocationMessage(latitude: Double, longitude: Double, locationName: String?, replyToId: UUID? = nil) async {
        guard let fromId = authService.currentUserId else { return }
        
        // Create optimistic message
        var optimisticMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: locationName ?? "Shared location",
            messageType: .location,
            replyToId: replyToId,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
        if let replyToId = replyToId,
           let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
            optimisticMessage.replyToMessage = context
        }
        messages.append(optimisticMessage)
        
        do {
            var sentMessage = try await messageService.sendLocationMessage(
                conversationId: conversationId,
                fromId: fromId,
                latitude: latitude,
                longitude: longitude,
                locationName: locationName,
                replyToId: replyToId
            )
            
            if let replyToId = replyToId,
               let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
                sentMessage.replyToMessage = context
            }
            
            // Replace optimistic message
            if let index = messages.firstIndex(where: { msg in
                msg.latitude == latitude && msg.longitude == longitude && msg.fromId == fromId
            }) {
                messages[index] = sentMessage
            }
            
            HapticManager.lightImpact()
        } catch {
            self.error = AppError.processingError("Failed to send location: \(error.localizedDescription)")
            AppLogger.error("messaging", "Error sending location message: \(error.localizedDescription)")
        }
    }
    
    
    // MARK: - Retry Failed Messages
    
    /// Retry sending a failed message
    func retryMessage(id: UUID) async {
        guard failedMessageIds.contains(id),
              let params = pendingMessageParams[id],
              let fromId = authService.currentUserId else {
            return
        }
        
        // Clear the failed state while retrying
        failedMessageIds.remove(id)
        HapticManager.lightImpact()
        
        do {
            var sentMessage = try await messageService.sendMessage(
                conversationId: conversationId,
                fromId: fromId,
                text: params.text,
                imageUrl: params.imageUrl,
                replyToId: params.replyToId
            )
            
            // Attach reply context if available locally
            if let replyToId = params.replyToId,
               let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
                sentMessage.replyToMessage = context
            }
            
            // Replace the failed optimistic message with the real one
            if let index = messages.firstIndex(where: { $0.id == id }) {
                messages[index] = sentMessage
            } else {
                messages.append(sentMessage)
                messages.sort { $0.createdAt < $1.createdAt }
            }
            
            // Clean up tracking
            optimisticIdMap.removeValue(forKey: id)
            pendingMessageParams.removeValue(forKey: id)
        } catch {
            // Mark as failed again
            failedMessageIds.insert(id)
            HapticManager.error()
            self.error = AppError.processingError(error.localizedDescription)
            AppLogger.error("messaging", "Error retrying message: \(error.localizedDescription)")
        }
    }
    
    /// Dismiss a failed message (remove it from the list entirely)
    func dismissFailedMessage(id: UUID) {
        failedMessageIds.remove(id)
        optimisticIdMap.removeValue(forKey: id)
        pendingMessageParams.removeValue(forKey: id)
        messages.removeAll { $0.id == id }
    }
    
    func addReaction(messageId: UUID, reaction: String) async {
        guard let userId = authService.currentUserId else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        // Save previous reactions for rollback
        let previousReactions = messages[index].reactions
        
        // Optimistic update: add the reaction locally
        var updatedReactions = messages[index].reactions ?? MessageReactions()
        var userIds = updatedReactions.reactions[reaction] ?? []
        if !userIds.contains(userId) {
            userIds.append(userId)
        }
        // Remove user from any other reaction (upsert semantics — one reaction per user)
        for key in updatedReactions.reactions.keys where key != reaction {
            updatedReactions.reactions[key]?.removeAll { $0 == userId }
            if updatedReactions.reactions[key]?.isEmpty == true {
                updatedReactions.reactions.removeValue(forKey: key)
            }
        }
        updatedReactions.reactions[reaction] = userIds
        messages[index].reactions = updatedReactions
        
        do {
            try await reactionService.addReaction(messageId: messageId, userId: userId, reaction: reaction)
        } catch {
            // Revert optimistic update on failure
            if let revertIndex = messages.firstIndex(where: { $0.id == messageId }) {
                messages[revertIndex].reactions = previousReactions
            }
            self.error = AppError.processingError(error.localizedDescription)
            AppLogger.error("messaging", "Error adding reaction: \(error.localizedDescription)")
        }
    }
    
    func removeReaction(messageId: UUID) async {
        guard let userId = authService.currentUserId else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        // Save previous reactions for rollback
        let previousReactions = messages[index].reactions
        
        // Optimistic update: remove the user from all reaction groups
        if var updatedReactions = messages[index].reactions {
            for key in updatedReactions.reactions.keys {
                updatedReactions.reactions[key]?.removeAll { $0 == userId }
                if updatedReactions.reactions[key]?.isEmpty == true {
                    updatedReactions.reactions.removeValue(forKey: key)
                }
            }
            messages[index].reactions = updatedReactions.reactions.isEmpty ? nil : updatedReactions
        }
        
        do {
            try await reactionService.removeReaction(messageId: messageId, userId: userId)
        } catch {
            // Revert optimistic update on failure
            if let revertIndex = messages.firstIndex(where: { $0.id == messageId }) {
                messages[revertIndex].reactions = previousReactions
            }
            self.error = AppError.processingError(error.localizedDescription)
            AppLogger.error("messaging", "Error removing reaction: \(error.localizedDescription)")
        }
    }
    
    private func handleNewMessage(_ newMessage: Message) {
        // Only add if it's for this conversation and not already in list
        guard newMessage.conversationId == conversationId,
              !messages.contains(where: { $0.id == newMessage.id }) else {
            return
        }
        
        messages.append(newMessage)
        messages.sort { $0.createdAt < $1.createdAt }
        scheduleReplyContextHydration()
        
        // Update last_seen and mark as read if it's not from current user
        // This ensures we don't get push notifications for messages we see in real-time
        if let userId = authService.currentUserId,
           newMessage.fromId != userId {
            Task {
                // Update last_seen to indicate user is actively viewing
                try? await messageService.updateLastSeen(conversationId: conversationId, userId: userId)
                // Then mark messages as read
                try? await messageService.markAsRead(conversationId: conversationId, userId: userId)
            }
        }
    }
    
    private func handleMessageUpdate(_ updatedMessage: Message) {
        guard updatedMessage.conversationId == conversationId else { return }
        
        if let index = messages.firstIndex(where: { $0.id == updatedMessage.id }),
           index < messages.count {
            messages[index] = updatedMessage
            scheduleReplyContextHydration()
        }
    }
    
    private func handleMessageDelete(_ deletedMessage: Message) {
        messages.removeAll { $0.id == deletedMessage.id }
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
    
    /// The currently focused search result message ID
    var currentSearchResultId: UUID? {
        searchManager.currentSearchResultId
    }
    
    /// Toggle search mode on/off
    func toggleSearch() {
        searchManager.toggleSearch()
    }
    
    // MARK: - Typing Delegation
    
    /// Start polling for typing users in this conversation
    func startTypingObservation() {
        typingManager.startTypingObservation()
    }
    
    /// Stop polling for typing users
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



