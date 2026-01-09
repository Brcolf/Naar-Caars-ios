//
//  ConversationDetailViewModel.swift
//  NaarsCars
//
//  ViewModel for conversation detail (chat)
//

import Foundation
internal import Combine

/// ViewModel for conversation detail
@MainActor
final class ConversationDetailViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var messageText: String = ""
    
    let conversationId: UUID
    private let messageService = MessageService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    
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
        
        do {
            self.messages = try await messageService.fetchMessages(conversationId: conversationId)
            // Update last_seen and mark as read when loading
            // This prevents push notifications when user is actively viewing
            if let userId = authService.currentUserId {
                // Update last_seen first to mark user as actively viewing
                try? await messageService.updateLastSeen(conversationId: conversationId, userId: userId)
                // Then mark messages as read
                try? await messageService.markAsRead(conversationId: conversationId, userId: userId)
            }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading messages: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func sendMessage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let fromId = authService.currentUserId else {
            return
        }
        
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = "" // Clear input
        
        // Optimistic UI update - store the text and timestamp to match later
        let optimisticText = text
        let optimisticTimestamp = Date()
        let optimisticMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            createdAt: optimisticTimestamp
        )
        messages.append(optimisticMessage)
        
        do {
            let sentMessage = try await messageService.sendMessage(
                conversationId: conversationId,
                fromId: fromId,
                text: text
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



