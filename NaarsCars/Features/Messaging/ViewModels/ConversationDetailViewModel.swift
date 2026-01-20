//
//  ConversationDetailViewModel.swift
//  NaarsCars
//
//  ViewModel for conversation detail (chat)
//

import Foundation
import UIKit
internal import Combine
import Realtime

/// ViewModel for conversation detail
@MainActor
final class ConversationDetailViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreMessages: Bool = true
    @Published var error: AppError?
    @Published var messageText: String = ""
    
    let conversationId: UUID
    private let messageService = MessageService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 25
    private var oldestMessageId: UUID?
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        setupRealtimeSubscription()
    }
    
    deinit {
        // Unsubscribe synchronously if possible, or use a detached task
        Task.detached { [conversationId] in
            await RealtimeManager.shared.unsubscribe(channelName: "messages:\(conversationId.uuidString)")
        }
    }
    
    func loadMessages() async {
        isLoading = true
        error = nil
        oldestMessageId = nil
        hasMoreMessages = true
        
        do {
            let fetched = try await messageService.fetchMessages(conversationId: conversationId, limit: pageSize, beforeMessageId: nil)
            self.messages = fetched
            oldestMessageId = fetched.first?.id // Oldest message (first in array after reverse)
            hasMoreMessages = fetched.count == pageSize
            // Update last_seen and mark as read when loading
            // This prevents push notifications when user is actively viewing
            if let userId = authService.currentUserId {
                // Update last_seen first to mark user as actively viewing
                try? await messageService.updateLastSeen(conversationId: conversationId, userId: userId)
                // Then mark messages as read
                try? await messageService.markAsRead(conversationId: conversationId, userId: userId)
                
                // Refresh badge counts after marking messages as read
                await BadgeCountManager.shared.refreshAllBadges()
            }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading messages: \(error.localizedDescription)")
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
        } catch {
            print("🔴 Error loading more messages: \(error.localizedDescription)")
            // Don't set error here - just log it
        }
        
        isLoadingMore = false
    }
    
    func sendMessage(image: UIImage? = nil) async {
        guard (!messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil),
              let fromId = authService.currentUserId else {
            return
        }
        
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let optimisticMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            createdAt: optimisticTimestamp
        )
        messages.append(optimisticMessage)
        
        do {
            let sentMessage = try await messageService.sendMessage(
                conversationId: conversationId,
                fromId: fromId,
                text: text,
                imageUrl: imageUrl
            )
            
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
    
    private func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "messages:\(conversationId.uuidString)",
                table: "messages",
                filter: "conversation_id=eq.\(conversationId.uuidString)",
                onInsert: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        self?.handleRealtimeInsert(payload)
                    }
                },
                onUpdate: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        self?.handleRealtimeUpdate(payload)
                    }
                },
                onDelete: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        self?.handleRealtimeDelete(payload)
                    }
                }
            )
        }
    }
    
    /// Handle realtime INSERT - parse message from payload and add to list
    private func handleRealtimeInsert(_ payload: Any) {
        guard let message = parseMessageFromPayload(payload) else {
            print("⚠️ [ConversationDetailVM] Could not parse message from realtime payload, falling back to reload")
            Task { await loadMessages() }
            return
        }
        
        // Check for duplicates - don't add if already in list
        // This handles the case where we sent the message (optimistic UI)
        if messages.contains(where: { $0.id == message.id }) {
            print("ℹ️ [ConversationDetailVM] Message \(message.id) already in list (optimistic UI), skipping")
            return
        }
        
        // Also check if this is our own message by matching text/time (optimistic message has different ID)
        if let currentUserId = authService.currentUserId,
           message.fromId == currentUserId {
            // Check if we have an optimistic message that matches this one
            let hasOptimistic = messages.contains { existing in
                existing.fromId == currentUserId &&
                existing.text == message.text &&
                abs(existing.createdAt.timeIntervalSince(message.createdAt)) < 10.0
            }
            if hasOptimistic {
                // Replace optimistic with real message
                if let index = messages.firstIndex(where: { existing in
                    existing.fromId == currentUserId &&
                    existing.text == message.text &&
                    abs(existing.createdAt.timeIntervalSince(message.createdAt)) < 10.0
                }) {
                    messages[index] = message
                    print("✅ [ConversationDetailVM] Replaced optimistic message with real message \(message.id)")
                }
                return
            }
        }
        
        // Add new message from another user
        messages.append(message)
        messages.sort { $0.createdAt < $1.createdAt }
        print("✅ [ConversationDetailVM] Added realtime message \(message.id) from \(message.fromId)")
        
        // Mark as read since user is actively viewing
        if let userId = authService.currentUserId, message.fromId != userId {
            Task {
                try? await messageService.updateLastSeen(conversationId: conversationId, userId: userId)
                try? await messageService.markAsRead(conversationId: conversationId, userId: userId)
            }
        }
        
        // Post notification to update conversations list
        NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: conversationId)
    }
    
    /// Handle realtime UPDATE - update message in list
    private func handleRealtimeUpdate(_ payload: Any) {
        guard let message = parseMessageFromPayload(payload) else {
            Task { await loadMessages() }
            return
        }
        
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            print("✅ [ConversationDetailVM] Updated message \(message.id) via realtime")
        }
    }
    
    /// Handle realtime DELETE - remove message from list
    private func handleRealtimeDelete(_ payload: Any) {
        guard let message = parseMessageFromPayload(payload) else {
            Task { await loadMessages() }
            return
        }
        
        messages.removeAll { $0.id == message.id }
        print("✅ [ConversationDetailVM] Deleted message \(message.id) via realtime")
    }
    
    /// Parse a Message from Supabase realtime payload
    private func parseMessageFromPayload(_ payload: Any) -> Message? {
        // Supabase realtime payloads are InsertAction/UpdateAction/DeleteAction
        // which contain a `record` property with the row data
        
        // Try to extract the record dictionary
        var recordDict: [String: Any]?
        
        // Handle different payload types from Supabase Realtime SDK
        if let insertAction = payload as? Realtime.InsertAction {
            recordDict = insertAction.record
        } else if let updateAction = payload as? Realtime.UpdateAction {
            recordDict = updateAction.record
        } else if let deleteAction = payload as? Realtime.DeleteAction {
            recordDict = deleteAction.oldRecord
        } else if let dict = payload as? [String: Any] {
            // Fallback: might be a raw dictionary
            recordDict = dict["record"] as? [String: Any] ?? dict
        }
        
        guard let record = recordDict else {
            print("⚠️ [ConversationDetailVM] Could not extract record from payload: \(type(of: payload))")
            return nil
        }
        
        // Parse the message fields
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let conversationIdString = record["conversation_id"] as? String,
              let convId = UUID(uuidString: conversationIdString),
              let fromIdString = record["from_id"] as? String,
              let fromId = UUID(uuidString: fromIdString),
              let text = record["text"] as? String else {
            print("⚠️ [ConversationDetailVM] Missing required fields in record: \(record.keys)")
            return nil
        }
        
        // Parse optional fields
        let imageUrl = record["image_url"] as? String
        
        // Parse read_by array
        var readBy: [UUID] = []
        if let readByArray = record["read_by"] as? [String] {
            readBy = readByArray.compactMap { UUID(uuidString: $0) }
        }
        
        // Parse created_at
        var createdAt = Date()
        if let createdAtString = record["created_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: createdAtString) {
                createdAt = date
            } else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: createdAtString) {
                    createdAt = date
                }
            }
        }
        
        return Message(
            id: id,
            conversationId: convId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            readBy: readBy,
            createdAt: createdAt,
            sender: nil, // Sender profile not included in realtime payload
            reactions: nil
        )
    }
    
    private func unsubscribeFromMessages() async {
        await realtimeManager.unsubscribe(channelName: "messages:\(conversationId.uuidString)")
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
        }
    }
    
    private func handleMessageDelete(_ deletedMessage: Message) {
        messages.removeAll { $0.id == deletedMessage.id }
    }
}



