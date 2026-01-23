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
import Realtime

/// ViewModel for conversation detail
@MainActor
final class ConversationDetailViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreMessages: Bool = true
    @Published var error: AppError?
    @Published var messageText: String = "" {
        didSet {
            handleTypingChange()
        }
    }
    
    /// Users currently typing in this conversation
    @Published var typingUsers: [TypingUser] = []
    
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
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 25
    private var oldestMessageId: UUID?
    
    // Typing indicator state
    private var typingTimer: Timer?
    private var typingRefreshTimer: Timer?
    private var lastTypingUpdate: Date?
    private let typingDebounceInterval: TimeInterval = 2.0
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        setupRealtimeSubscription()
        setupTypingIndicatorSubscription()
        startTypingRefreshTimer()
    }
    
    deinit {
        // Clear typing status on deinit
        Task.detached { [conversationId] in
            await RealtimeManager.shared.unsubscribe(channelName: "messages:\(conversationId.uuidString)")
            await RealtimeManager.shared.unsubscribe(channelName: "typing:\(conversationId.uuidString)")
            if let userId = await AuthService.shared.currentUserId {
                await MessageService.shared.clearTypingStatus(conversationId: conversationId, userId: userId)
            }
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
                
                // Also refresh conversations list to clear unread indicator there
                NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: conversationId)
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
    
    // MARK: - Typing Indicators
    
    private func setupTypingIndicatorSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "typing:\(conversationId.uuidString)",
                table: "typing_indicators",
                filter: "conversation_id=eq.\(conversationId.uuidString)",
                onInsert: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.refreshTypingUsers()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.refreshTypingUsers()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.refreshTypingUsers()
                    }
                }
            )
        }
    }
    
    private func startTypingRefreshTimer() {
        // Refresh typing users every 2 seconds to handle stale indicators
        typingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshTypingUsers()
            }
        }
    }
    
    private func refreshTypingUsers() async {
        let users = await messageService.fetchTypingUsers(conversationId: conversationId)
        if users != typingUsers {
            withAnimation(.easeInOut(duration: 0.2)) {
                typingUsers = users
            }
        }
    }
    
    private func handleTypingChange() {
        guard let userId = authService.currentUserId else { return }
        
        // Only send typing status if text is not empty
        if messageText.isEmpty {
            // Clear typing status
            typingTimer?.invalidate()
            typingTimer = nil
            Task {
                await messageService.clearTypingStatus(conversationId: conversationId, userId: userId)
            }
            return
        }
        
        // Debounce typing updates
        let now = Date()
        if let lastUpdate = lastTypingUpdate, now.timeIntervalSince(lastUpdate) < typingDebounceInterval {
            return
        }
        
        lastTypingUpdate = now
        
        // Send typing status
        Task {
            await messageService.setTypingStatus(conversationId: conversationId, userId: userId)
        }
        
        // Reset typing timer - clear after 5 seconds of no typing
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let userId = self.authService.currentUserId else { return }
                await self.messageService.clearTypingStatus(conversationId: self.conversationId, userId: userId)
            }
        }
    }
    
    /// Clear typing status when sending a message
    func clearTypingStatusOnSend() {
        guard let userId = authService.currentUserId else { return }
        typingTimer?.invalidate()
        typingTimer = nil
        Task {
            await messageService.clearTypingStatus(conversationId: conversationId, userId: userId)
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
        var incomingMessage = message
        if let replyToId = incomingMessage.replyToId,
           let context = messages.first(where: { $0.id == replyToId }).map({ ReplyContext(from: $0) }) {
            incomingMessage.replyToMessage = context
        }
        
        // Enrich message with sender profile immediately if missing (common in realtime payloads)
        if incomingMessage.sender == nil {
            Task {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: incomingMessage.fromId) {
                    await MainActor.run {
                        if let index = messages.firstIndex(where: { $0.id == incomingMessage.id }) {
                            messages[index].sender = profile
                        } else {
                            // If not added yet, set it on the local variable before appending
                            incomingMessage.sender = profile
                        }
                    }
                }
            }
        }

        messages.append(incomingMessage)
        messages.sort { $0.createdAt < $1.createdAt }
        print("✅ [ConversationDetailVM] Added realtime message \(message.id) from \(message.fromId)")

        // Enrich message with full context from server if still missing fields
        if incomingMessage.replyToId != nil && incomingMessage.replyToMessage == nil {
            Task {
                if let enriched = try? await messageService.fetchMessageById(incomingMessage.id),
                   let index = messages.firstIndex(where: { $0.id == incomingMessage.id }) {
                    messages[index] = enriched
                }
            }
        }
        
        // Mark as read since user is actively viewing
        if let userId = authService.currentUserId, message.fromId != userId {
            Task {
                try? await messageService.updateLastSeen(conversationId: conversationId, userId: userId)
                try? await messageService.markAsRead(conversationId: conversationId, userId: userId)
                // Refresh badges and list after marking as read
                await BadgeCountManager.shared.refreshAllBadges()
                NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: conversationId)
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
        let replyToId = (record["reply_to_id"] as? String).flatMap(UUID.init)
        let messageType = (record["message_type"] as? String).flatMap(MessageType.init(rawValue:))
        let audioUrl = record["audio_url"] as? String
        let audioDuration = parseDouble(record["audio_duration"])
        let latitude = parseDouble(record["latitude"])
        let longitude = parseDouble(record["longitude"])
        let locationName = record["location_name"] as? String
        
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
            messageType: messageType,
            replyToId: replyToId,
            audioUrl: audioUrl,
            audioDuration: audioDuration,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            sender: nil, // Sender profile not included in realtime payload
            reactions: nil
        )
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let stringValue = value as? String {
            return Double(stringValue)
        }
        return nil
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



