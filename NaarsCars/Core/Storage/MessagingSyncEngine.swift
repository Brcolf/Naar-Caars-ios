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
    private let conversationService = ConversationService.shared
    private let realtimeManager = RealtimeManager.shared
    private let authService = AuthService.shared
    private var modelContext: ModelContext?
    private var backgroundActor: BackgroundSyncActor?
    private var lastStartSyncAt: Date = .distantPast
    let health = SyncHealthMetrics()

    private init() {}

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Initialize the background actor for off-MainActor SwiftData writes
    func setupBackgroundActor(container: ModelContainer) {
        self.backgroundActor = BackgroundSyncActor(modelContainer: container)
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
                do {
                    // Step 1: Fetch conversations from network
                    let remoteConversations = try await conversationService.fetchConversations(userId: userId)

                    // Step 2: Write to SwiftData on background actor (if available)
                    if let backgroundActor {
                        let payloads = remoteConversations.map { ConversationSyncPayload(from: $0, currentUserId: userId) }
                        let changedIds = try await backgroundActor.syncConversations(payloads, currentUserId: userId)

                        // Step 3: Refresh Combine publishers on MainActor
                        repository.refreshPublishersAfterBackgroundSync(changedConversationIds: changedIds)
                    } else {
                        // Fallback: use repository's MainActor path if actor not yet wired
                        try await repository.syncConversations(userId: userId)
                    }

                    health.recordSuccess()
                } catch {
                    health.recordFailure(error)
                }
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
        backgroundActor = nil
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

                    // Un-hide the conversation if the user previously soft-deleted it,
                    // so it reappears when new messages arrive (iMessage-like behavior).
                    if result == .inserted,
                       let userId = self.authService.currentUserId,
                       message.fromId != userId,
                       self.conversationService.isConversationHidden(conversationId: message.conversationId, for: userId) {
                        self.conversationService.unhideConversationForUser(conversationId: message.conversationId, userId: userId)
                    }

                    // Media Pre-caching
                    if let imageUrl = message.imageUrl {
                        precacheMedia(url: imageUrl)
                    }
                    if let audioUrl = message.audioUrl {
                        precacheMedia(url: audioUrl)
                    }

                    NotificationCenter.default.post(
                        name: .conversationUpdated,
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

    /// Subscribe to reaction changes for a specific conversation
    func setupReactionsSubscription(conversationId: UUID) {
        Task {
            await realtimeManager.subscribe(
                channelName: "reactions:\(conversationId.uuidString)",
                table: "message_reactions",
                onInsert: { [weak self] record in
                    self?.handleReactionChange(record, conversationId: conversationId)
                },
                onDelete: { [weak self] record in
                    self?.handleReactionChange(record, conversationId: conversationId)
                }
            )
        }
    }

    /// Unsubscribe from reaction changes for a conversation
    func teardownReactionsSubscription(conversationId: UUID) {
        Task {
            await realtimeManager.unsubscribe(channelName: "reactions:\(conversationId.uuidString)")
        }
    }

    /// Handle an incoming reaction change event
    private func handleReactionChange(_ event: RealtimeRecord, conversationId: UUID) {
        guard let messageIdString = event.record["message_id"] as? String,
              let messageId = UUID(uuidString: messageIdString) else { return }

        NotificationCenter.default.post(
            name: .messageReactionChanged,
            object: nil,
            userInfo: ["messageId": messageId, "conversationId": conversationId]
        )
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
