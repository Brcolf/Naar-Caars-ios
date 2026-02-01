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
    
    /// Count of unread messages (messages not from current user that haven't been read)
    var unreadCount: Int {
        guard let userId = authService.currentUserId else { return 0 }
        return messages.filter { message in
            message.fromId != userId && !message.readBy.contains(userId)
        }.count
    }
    
    let conversationId: UUID
    private let messageService = MessageService.shared
    private let authService = AuthService.shared
    private let repository = MessagingRepository.shared
    private let throttler = Throttler.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 25
    private var oldestMessageId: UUID?
    private var conversationUpdatedObserver: NSObjectProtocol?
#if DEBUG
    private var lastReplyDebugSnapshot: (total: Int, replyIds: Int, replyContexts: Int) = (-1, -1, -1)
#endif
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        setupLocalObservation()
        setupConversationUpdatedObserver()
    }
    
    deinit {
        if let observer = conversationUpdatedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupLocalObservation() {
        repository.getMessagesPublisher(for: conversationId)
            .sink { [weak self] updatedMessages in
                guard let self = self, self.repository.isConfigured else { return }
                self.messages = updatedMessages
                self.scheduleReplyContextHydration()
#if DEBUG
                self.logReplyDebugSnapshot(source: "publisher(local)", messages: updatedMessages)
#endif
            }
            .store(in: &cancellables)
    }
    
    func loadMessages() async {
        isLoading = true
        error = nil
        oldestMessageId = nil
        hasMoreMessages = true
        
        do {
            let localMessages = try repository.getMessages(for: conversationId)
            self.messages = localMessages
            oldestMessageId = localMessages.first?.id
            hasMoreMessages = localMessages.count == pageSize
            scheduleReplyContextHydration()
#if DEBUG
            logReplyDebugSnapshot(source: "loadMessages(local)", messages: localMessages)
#endif
        } catch {
            print("⚠️ [ConversationDetailVM] Error loading local messages: \(error.localizedDescription)")
        }
        
        // Update last_seen and mark as read when loading
        // This prevents push notifications when user is actively viewing
        if let userId = authService.currentUserId {
            // Update last_seen first to mark user as actively viewing
            try? await messageService.updateLastSeen(conversationId: conversationId, userId: userId)
            // Then mark messages as read
            try? await messageService.markAsRead(conversationId: conversationId, userId: userId)
            
            // Clear badges and local unread count for this conversation
            await BadgeCountManager.shared.clearMessagesBadge(for: conversationId)
        }
        
        Task { [weak self] in
            await self?.refreshMessagesInBackground()
        }
        
        isLoading = false
    }
    
    func loadMoreMessages() async {
        guard !isLoadingMore, hasMoreMessages,
              let beforeId = oldestMessageId else {
            return
        }
        
        isLoadingMore = true
        
        do {
            let fetched = try await messageService.fetchMessages(conversationId: conversationId, limit: pageSize, beforeMessageId: beforeId)
            // Prepend older messages to the beginning
            self.messages.insert(contentsOf: fetched, at: 0)
            oldestMessageId = fetched.first?.id
            hasMoreMessages = fetched.count == pageSize
            scheduleReplyContextHydration()
        } catch {
            print("🔴 Error loading more messages: \(error.localizedDescription)")
            // Don't set error here - just log it
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
        
        // Upload image first if provided
        var imageUrl: String? = nil
        if let image = image, let imageData = image.jpegData(compressionQuality: 1.0) {
            do {
                imageUrl = try await messageService.uploadMessageImage(
                    imageData: imageData,
                    conversationId: conversationId,
                    fromId: fromId
                )
            } catch {
                self.error = AppError.processingError("Failed to upload image: \(error.localizedDescription)")
                print("🔴 Error uploading image: \(error.localizedDescription)")
                return // Don't send message if image upload fails
            }
        }
        
        // Optimistic UI update - store the text and timestamp to match later
        let optimisticText = text
        let optimisticTimestamp = Date()
        var optimisticMessage = Message(
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
            
            // Replace optimistic message with real one
            // Match by text and timestamp (within 5 seconds) since IDs will differ
            if let index = messages.firstIndex(where: { msg in
                msg.text == optimisticText &&
                msg.fromId == fromId &&
                abs(msg.createdAt.timeIntervalSince(optimisticTimestamp)) < 5.0
            }), index < messages.count {
                messages[index] = sentMessage
            } else {
                // If not found, remove optimistic and add real message
                messages.removeAll { msg in
                    msg.text == optimisticText &&
                    msg.fromId == fromId &&
                    abs(msg.createdAt.timeIntervalSince(optimisticTimestamp)) < 5.0
                }
                messages.append(sentMessage)
                messages.sort { $0.createdAt < $1.createdAt }
            }
        } catch {
            // Remove optimistic message on error
            messages.removeAll { msg in
                msg.text == optimisticText &&
                msg.fromId == fromId &&
                abs(msg.createdAt.timeIntervalSince(optimisticTimestamp)) < 5.0
            }
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error sending message: \(error.localizedDescription)")
        }
    }
    
    private func setupConversationUpdatedObserver() {
        conversationUpdatedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("conversationUpdated"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if Thread.isMainThread {
                self.handleConversationUpdatedImmediate(notification)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.handleConversationUpdatedImmediate(notification)
                }
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
                minimumInterval: 1.0
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
            print("⚠️ [ConversationDetailVM] Background sync failed: \(error.localizedDescription)")
        }
    }

    private func scheduleReplyContextHydration() {
        guard messages.contains(where: { $0.replyToId != nil && $0.replyToMessage == nil }) else { return }

        Task { [weak self] in
            guard let self = self else { return }
            await self.throttler.run(
                key: "messages.replyContext.\(self.conversationId.uuidString)",
                minimumInterval: 0.5
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

        return ReplyContextBuilder.applyReplyContexts(messages: messages, profilesById: profilesById)
    }

#if DEBUG
    private func logReplyDebugSnapshot(source: String, messages: [Message]) {
        let replyIds = messages.filter { $0.replyToId != nil }.count
        let replyContexts = messages.filter { $0.replyToMessage != nil }.count
        let snapshot = (total: messages.count, replyIds: replyIds, replyContexts: replyContexts)
        guard snapshot != lastReplyDebugSnapshot else { return }
        lastReplyDebugSnapshot = snapshot
        print("🧵 [ReplyThreadDebug] \(source) total=\(snapshot.total) replyToId=\(snapshot.replyIds) replyContext=\(snapshot.replyContexts)")
        if let sample = messages.first(where: { $0.replyToId != nil }) {
            print("🧵 [ReplyThreadDebug] sample messageId=\(sample.id) replyToId=\(sample.replyToId?.uuidString ?? "nil") context=\(sample.replyToMessage != nil)")
        }
    }
#endif
    
    // MARK: - Audio Messages
    
    /// Send an audio message
    func sendAudioMessage(audioURL: URL, duration: Double, replyToId: UUID? = nil) async {
        guard let fromId = authService.currentUserId else { return }
        
        do {
            // Read audio data from file
            let audioData = try Data(contentsOf: audioURL)
            
            // Upload audio to storage
            let uploadedUrl = try await messageService.uploadAudioMessage(
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
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            self.error = AppError.processingError("Failed to send audio: \(error.localizedDescription)")
            print("🔴 Error sending audio message: \(error.localizedDescription)")
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
        } catch {
            self.error = AppError.processingError("Failed to send location: \(error.localizedDescription)")
            print("🔴 Error sending location message: \(error.localizedDescription)")
        }
    }
    
    
    func addReaction(messageId: UUID, reaction: String) async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            try await messageService.addReaction(messageId: messageId, userId: userId, reaction: reaction)
            // Reload messages to get updated reactions
            await loadMessages()
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error adding reaction: \(error.localizedDescription)")
        }
    }
    
    func removeReaction(messageId: UUID) async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            try await messageService.removeReaction(messageId: messageId, userId: userId)
            // Reload messages to get updated reactions
            await loadMessages()
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error removing reaction: \(error.localizedDescription)")
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

    
}



