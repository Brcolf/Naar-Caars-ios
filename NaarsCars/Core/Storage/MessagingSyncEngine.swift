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
        print("🔴 [MessagingSyncEngine] Received realtime payload: \(type(of: payload))")
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
            print("⚠️ [MessagingSyncEngine] Failed to parse realtime message payload")
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
                print("🔴 [MessagingSyncEngine] Error upserting realtime message: \(error)")
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
        // Fetch all pending messages
        // In a real app, we'd use a more robust background task or a dedicated retry queue
        // For now, we'll implement a simple loop with exponential backoff
        
        // This is a placeholder for the actual retry logic implementation
        // which would involve fetching from repository and calling sendMessage
    }
}

