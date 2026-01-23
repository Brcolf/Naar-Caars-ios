//
//  MessagingSyncEngine.swift
//  NaarsCars
//

import Foundation
import SwiftData
import Realtime

@MainActor
final class MessagingSyncEngine {
    static let shared = MessagingSyncEngine()
    
    private let repository = MessagingRepository.shared
    private let realtimeManager = RealtimeManager.shared
    private let authService = AuthService.shared
    private var modelContext: ModelContext?
    
    private init() {}
    
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func startSync() {
        setupConversationsSubscription()
        setupMessagesSubscription()
        
        // Initial sync
        if let userId = authService.currentUserId {
            Task {
                try? await repository.syncConversations(userId: userId)
                await retryPendingMessages()
            }
        }
    }

    private func handleIncomingMessage(_ payload: Any) {
        guard let message = MessagingMapper.parseMessageFromPayload(payload) else { return }
        
        Task {
            do {
                try repository.upsertMessage(message)
                
                // Media Pre-caching
                if let imageUrl = message.imageUrl {
                    precacheMedia(url: imageUrl)
                }
                if let audioUrl = message.audioUrl {
                    precacheMedia(url: audioUrl)
                }
                
                NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: message.conversationId)
            } catch {
                print("🔴 [MessagingSyncEngine] Error upserting realtime message: \(error)")
            }
        }
    }

    private func setupConversationsSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "conversations:sync",
                table: "conversations",
                onInsert: { [weak self] _ in
                    self?.triggerConversationsSync()
                },
                onUpdate: { [weak self] _ in
                    self?.triggerConversationsSync()
                }
            )
        }
    }
    
    private func setupMessagesSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "messages:sync",
                table: "messages",
                onInsert: { [weak self] payload in
                    self?.handleIncomingMessage(payload)
                }
            )
        }
    }
    
    private func triggerConversationsSync() {
        guard let userId = authService.currentUserId else { return }
        Task {
            try? await repository.syncConversations(userId: userId)
        }
    }

    private func precacheMedia(url: String) {
        guard let mediaURL = URL(string: url) else { return }
        URLSession.shared.dataTask(with: mediaURL).resume() // Simple pre-fetch into URLCache
    }

    func retryPendingMessages() async {
        // Fetch all pending messages
        // In a real app, we'd use a more robust background task or a dedicated retry queue
        // For now, we'll implement a simple loop with exponential backoff
        
        // This is a placeholder for the actual retry logic implementation
        // which would involve fetching from repository and calling sendMessage
    }
}

