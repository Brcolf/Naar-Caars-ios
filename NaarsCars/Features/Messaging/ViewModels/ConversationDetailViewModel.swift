//
//  ConversationDetailViewModel.swift
//  NaarsCars
//
//  ViewModel for conversation detail (chat)
//

import Foundation
import UIKit
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
            self.messages = fetched.messages
            oldestMessageId = fetched.messages.first?.id // Oldest message (first in array after reverse)
            hasMoreMessages = fetched.hasMore
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
            self.messages.insert(contentsOf: fetched.messages, at: 0)
            oldestMessageId = fetched.messages.first?.id
            hasMoreMessages = fetched.hasMore
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
                onInsert: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadMessages()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadMessages()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadMessages()
                    }
                }
            )
        }
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

