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
    
    private enum MessageEvent: String {
        case insert
        case update
        case delete
    }
    
    private init() {}
    
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func startSync() {
        setupMessagesSubscription()
        
        // Initial sync
        if let userId = authService.currentUserId {
            Task {
                try? await repository.syncConversations(userId: userId)
                await retryPendingMessages()
            }
        }
    }

    private func handleIncomingMessage(_ payload: Any, event: MessageEvent) {
        AppLogger.info("messaging", "Received realtime payload: \(type(of: payload))")
        if event == .update,
           let updateAction = payload as? UpdateAction,
           Self.shouldIgnoreReadByUpdate(
               record: updateAction.record,
               oldRecord: updateAction.oldRecord,
               currentUserId: authService.currentUserId
           ) {
            return
        }
        guard let message = MessagingMapper.parseMessageFromPayload(payload) else {
            AppLogger.warning("messaging", "Failed to parse realtime message payload")
            return
        }
        
        Task {
            do {
                try repository.upsertMessage(message)
                try repository.save()
                
                // Media Pre-caching
                if let imageUrl = message.imageUrl {
                    precacheMedia(url: imageUrl)
                }
                if let audioUrl = message.audioUrl {
                    precacheMedia(url: audioUrl)
                }

                NotificationCenter.default.post(
                    name: NSNotification.Name("conversationUpdated"),
                    object: message.conversationId,
                    userInfo: [
                        "message": message,
                        "event": event.rawValue
                    ]
                )
            } catch {
                AppLogger.error("messaging", "Error upserting realtime message: \(error)")
            }
        }
    }

    private func setupMessagesSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "messages:sync",
                table: "messages",
                onInsert: { [weak self] payload in
                    self?.handleIncomingMessage(payload, event: .insert)
                },
                onUpdate: { [weak self] payload in
                    self?.handleIncomingMessage(payload, event: .update)
                },
                onDelete: { [weak self] payload in
                    self?.handleIncomingMessage(payload, event: .delete)
                }
            )
        }
    }

    static func shouldIgnoreReadByUpdate(
        record: [String: AnyJSON],
        oldRecord: [String: AnyJSON],
        currentUserId: UUID?
    ) -> Bool {
        guard let currentUserId else { return false }

        var strippedRecord = record
        strippedRecord.removeValue(forKey: "read_by")
        strippedRecord.removeValue(forKey: "updated_at")

        var strippedOldRecord = oldRecord
        strippedOldRecord.removeValue(forKey: "read_by")
        strippedOldRecord.removeValue(forKey: "updated_at")

        guard strippedRecord == strippedOldRecord else { return false }

        let oldReadBy = readBySet(oldRecord["read_by"])
        let newReadBy = readBySet(record["read_by"])
        guard oldReadBy != newReadBy else { return false }

        return !oldReadBy.contains(currentUserId) && newReadBy.contains(currentUserId)
    }

    private static func readBySet(_ value: AnyJSON?) -> Set<UUID> {
        guard case let .array(items)? = value else { return [] }
        return Set(items.compactMap { item in
            if case let .string(raw) = item {
                return UUID(uuidString: raw)
            }
            return nil
        })
    }

    private func precacheMedia(url: String) {
        guard let mediaURL = URL(string: url) else { return }
        URLSession.shared.dataTask(with: mediaURL).resume() // Simple pre-fetch into URLCache
    }

    func retryPendingMessages() async {
        guard let modelContext = modelContext else { return }
        
        // Fetch pending messages from SwiftData
        let descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.isPending == true }
        )
        
        do {
            let pendingMessages = try modelContext.fetch(descriptor)
            guard !pendingMessages.isEmpty else { return }
            
            AppLogger.info("messaging", "Found \(pendingMessages.count) pending message(s) to retry")
            
            for sdMessage in pendingMessages {
                // Capture values needed by the sendable closure
                let conversationId = sdMessage.conversationId
                let fromId = sdMessage.fromId
                let text = sdMessage.text
                let imageUrl = sdMessage.imageUrl
                let replyToId = sdMessage.replyToId
                let messageId = sdMessage.id
                
                do {
                    let sentMessage = try await RetryableOperation.execute(maxAttempts: 3, initialDelay: 1.0) {
                        try await MessageService.shared.sendMessage(
                            conversationId: conversationId,
                            fromId: fromId,
                            text: text,
                            imageUrl: imageUrl,
                            replyToId: replyToId
                        )
                    }
                    
                    // Replace optimistic message with the real server message
                    modelContext.delete(sdMessage)
                    let finalSDMessage = MessagingMapper.mapToSDMessage(sentMessage, isPending: false)
                    
                    let convId = sentMessage.conversationId
                    let convFetch = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == convId })
                    if let sdConv = try? modelContext.fetch(convFetch).first {
                        finalSDMessage.conversation = sdConv
                        sdConv.updatedAt = sentMessage.createdAt
                    }
                    
                    modelContext.insert(finalSDMessage)
                    try? modelContext.save()
                    AppLogger.info("messaging", "Retried pending message \(messageId) successfully")
                } catch {
                    // Mark as failed after all retries exhausted
                    sdMessage.isPending = false
                    sdMessage.syncError = error.localizedDescription
                    try? modelContext.save()
                    AppLogger.error("messaging", "Failed to retry message \(messageId) after 3 attempts: \(error.localizedDescription)")
                }
            }
        } catch {
            AppLogger.error("messaging", "Failed to fetch pending messages: \(error.localizedDescription)")
        }
    }
}

