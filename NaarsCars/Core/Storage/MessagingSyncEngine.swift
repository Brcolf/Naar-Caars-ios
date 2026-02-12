//
//  MessagingSyncEngine.swift
//  NaarsCars
//

import Foundation
import SwiftData

@MainActor
final class MessagingSyncEngine: SyncEngineProtocol {
    static let shared = MessagingSyncEngine()
    let engineName = "messaging"
    
    private let repository = MessagingRepository.shared
    private let realtimeManager = RealtimeManager.shared
    private let authService = AuthService.shared
    private var modelContext: ModelContext?
    private var lastStartSyncAt: Date = .distantPast
    
    private init() {}
    
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func startSync() {
        setupMessagesSubscription()

        let now = Date()
        guard now.timeIntervalSince(lastStartSyncAt) >= Constants.Timing.syncEngineStartCooldown else {
            return
        }
        lastStartSyncAt = now

        if let userId = authService.currentUserId {
            Task {
                try? await repository.syncConversations(userId: userId)
                // Start the durable send worker and process any pending messages
                await MessageSendWorker.shared.start()
                await MessageSendWorker.shared.notifyNewPendingMessage()
            }
        }
    }

    func pauseSync() async {
        await realtimeManager.unsubscribe(channelName: "messages:sync")
        await MessageSendWorker.shared.stop()
    }

    func resumeSync() async {
        setupMessagesSubscription()
    }

    func teardown() async {
        await pauseSync()
        modelContext = nil
        lastStartSyncAt = .distantPast
    }

    private func handleIncomingMessage(_ event: RealtimeRecord) {
#if DEBUG
        if FeatureFlags.verbosePerformanceLogsEnabled {
            AppLogger.info("messaging", "Received realtime payload event: \(event.eventType)")
        }
#endif
        if event.eventType == .update,
           let oldRecord = event.oldRecord,
           Self.shouldIgnoreReadByUpdate(record: event.record, oldRecord: oldRecord) {
            return
        }
        guard let message = MessagingMapper.parseMessage(from: event.record) else {
            AppLogger.warning("messaging", "Failed to parse realtime message payload")
            return
        }
        
        Task {
            do {
                let result = try repository.upsertMessageDetailed(message)
                
                switch result {
                case .noChange:
                    return
                    
                case .metadataOnly:
                    // Metadata-only change (readBy) — already emitted via metadata publisher.
                    // Save the context but skip the full list rebuild and notification.
                    try? repository.saveContextOnly()
                    return
                    
                case .contentChanged, .inserted:
                    try repository.save(changedConversationIds: Set([message.conversationId]))
                    
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
                            "event": String(describing: event.eventType)
                        ]
                    )
                }
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
                onInsert: { [weak self] record in
                    self?.handleIncomingMessage(record)
                },
                onUpdate: { [weak self] record in
                    self?.handleIncomingMessage(record)
                },
                onDelete: { [weak self] record in
                    self?.handleIncomingMessage(record)
                }
            )
        }
    }

    static func shouldIgnoreReadByUpdate(
        record: [String: Any],
        oldRecord: [String: Any]
    ) -> Bool {
        var strippedRecord = record
        strippedRecord.removeValue(forKey: "read_by")
        strippedRecord.removeValue(forKey: "updated_at")

        var strippedOldRecord = oldRecord
        strippedOldRecord.removeValue(forKey: "read_by")
        strippedOldRecord.removeValue(forKey: "updated_at")

        let lhs = strippedRecord as NSDictionary
        return lhs.isEqual(to: strippedOldRecord)
    }

    private func precacheMedia(url: String) {
        guard let mediaURL = URL(string: url) else { return }
        URLSession.shared.dataTask(with: mediaURL).resume() // Simple pre-fetch into URLCache
    }

    /// Retry pending messages via the durable MessageSendWorker
    func retryPendingMessages() async {
        await MessageSendWorker.shared.start()
        await MessageSendWorker.shared.notifyNewPendingMessage()
    }
}
