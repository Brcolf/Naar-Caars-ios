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
    private var activeConversationId: UUID?
    private var gracePeriodTimer: Timer?
    private let messageService = MessageService.shared
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
        // No global messages subscription — conversations are WebSocket-scoped now

        let now = Date()
        guard now.timeIntervalSince(lastStartSyncAt) >= Constants.Timing.syncEngineStartCooldown else {
            return
        }
        lastStartSyncAt = now

        if let userId = authService.currentUserId {
            Task {
                do {
                    let remoteConversations = try await conversationService.fetchConversations(userId: userId)
                    if let backgroundActor {
                        let payloads = remoteConversations.map { ConversationSyncPayload(from: $0, currentUserId: userId) }
                        let changedIds = try await backgroundActor.syncConversations(payloads, currentUserId: userId)
                        repository.refreshPublishersAfterBackgroundSync(changedConversationIds: changedIds)
                    } else {
                        try await repository.syncConversations(userId: userId)
                    }
                    health.recordSuccess()
                } catch {
                    health.recordFailure(error)
                }
                await MessageSendWorker.shared.start()
                await MessageSendWorker.shared.notifyNewPendingMessage()
            }
        }
    }

    func pauseSync() async {
        await MessageSendWorker.shared.stop()
    }

    func resumeSync() async {
        // Conversation subscription managed by subscribeToConversation/beginGracePeriod
        // Send worker restarted by startSync
    }

    func teardown() async {
        cancelGracePeriodAndUnsubscribe()
        await MessageSendWorker.shared.stop()
        modelContext = nil
        backgroundActor = nil
        lastStartSyncAt = .distantPast
    }

    // MARK: - Coordinator Entry Points

    /// Called by RefreshCoordinator to refresh the conversation list.
    func refreshConversationList() async throws -> RefreshMetrics {
        guard let userId = authService.currentUserId else { return .empty }
        let start = Date()

        let remoteConversations = try await conversationService.fetchConversations(userId: userId)
        guard !Task.isCancelled else { throw CancellationError() }

        if let backgroundActor {
            let payloads = remoteConversations.map { ConversationSyncPayload(from: $0, currentUserId: userId) }
            let changedIds = try await backgroundActor.syncConversations(payloads, currentUserId: userId)
            repository.refreshPublishersAfterBackgroundSync(changedConversationIds: changedIds)

            health.recordSuccess()
            return RefreshMetrics(
                recordsEvaluated: remoteConversations.count,
                recordsMutated: changedIds.count,
                recordsInserted: 0, recordsDeleted: 0,
                savedToStore: !changedIds.isEmpty,
                durationMs: Int(Date().timeIntervalSince(start) * 1000)
            )
        } else {
            try await repository.syncConversations(userId: userId)
            health.recordSuccess()
            return .empty
        }
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

        // Block realtime messages from blocked users
        if MessageService.shared.isBlocked(message.fromId) { return }

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

    // MARK: - Conversation WebSocket Lifecycle

    /// Subscribe to messages and reactions for a specific conversation.
    /// Called by conversation detail ViewModel on appear.
    func subscribeToConversation(_ conversationId: UUID) {
        // Cancel grace period if re-entering same conversation
        gracePeriodTimer?.invalidate()
        gracePeriodTimer = nil

        guard activeConversationId != conversationId else { return }

        if activeConversationId != nil {
            unsubscribeFromActiveConversation()
        }

        activeConversationId = conversationId
        RefreshCoordinator.shared.setActiveConversation(conversationId)

        Task {
            // Subscribe to messages for this conversation
            await realtimeManager.subscribe(
                channelName: "messages:\(conversationId.uuidString)",
                table: "messages",
                filter: "conversation_id=eq.\(conversationId.uuidString)",
                onInsert: { [weak self] record in self?.handleIncomingMessage(record) },
                onUpdate: { [weak self] record in self?.handleIncomingMessage(record) },
                onDelete: { [weak self] record in self?.handleIncomingMessage(record) }
            )

            // Subscribe to reactions for this conversation
            setupReactionsSubscription(conversationId: conversationId)

            // Subscribe-then-fetch: REST hydration after subscription
            await hydrateConversation(conversationId)
        }
    }

    /// Start 5-second grace period before tearing down WebSocket.
    /// Called by conversation detail ViewModel on disappear (back to list).
    func beginGracePeriod() {
        gracePeriodTimer?.invalidate()
        gracePeriodTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.Timing.conversationGracePeriod,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.unsubscribeFromActiveConversation()
            }
        }
    }

    /// Immediately tear down WebSocket. Called on tab switch or app background.
    func cancelGracePeriodAndUnsubscribe() {
        gracePeriodTimer?.invalidate()
        gracePeriodTimer = nil
        unsubscribeFromActiveConversation()
    }

    private func unsubscribeFromActiveConversation() {
        guard let id = activeConversationId else { return }
        Task {
            await realtimeManager.unsubscribe(channelName: "messages:\(id.uuidString)")
            await realtimeManager.unsubscribe(channelName: "reactions:\(id.uuidString)")
        }
        activeConversationId = nil
        RefreshCoordinator.shared.setActiveConversation(nil)
    }

    /// Subscribe-then-fetch: REST fetch recent messages to cover the connection gap.
    /// Dedup by message UUID prevents duplicates with buffered WebSocket events.
    private func hydrateConversation(_ conversationId: UUID) async {
        do {
            let messages = try await messageService.fetchMessages(
                conversationId: conversationId,
                limit: 50,
                beforeMessageId: nil
            )
            guard !Task.isCancelled else { return }

            var changedCount = 0
            for message in messages {
                let result = try repository.upsertMessageDetailed(message)
                if case .contentChanged = result { changedCount += 1 }
                if case .inserted = result { changedCount += 1 }
            }

            if changedCount > 0 {
                try repository.save(changedConversationIds: [conversationId])
            }
        } catch {
            AppLogger.error("messaging", "Conversation hydration failed for \(conversationId): \(error)")
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

    /// Handle an incoming reaction change event.
    /// Parses the realtime payload into a `MessageReaction` when possible so
    /// consumers can apply the change locally without an additional API call.
    private func handleReactionChange(_ event: RealtimeRecord, conversationId: UUID) {
        let dict = event.record
        guard let messageIdString = dict["message_id"] as? String,
              let messageId = UUID(uuidString: messageIdString) else { return }

        var userInfo: [String: Any] = [
            "messageId": messageId,
            "conversationId": conversationId,
            "eventType": String(describing: event.eventType)
        ]

        // For insert AND update events, include the full parsed reaction so
        // consumers can apply the change locally without an API round-trip.
        // Upsert (reaction change) fires .update, not .insert — both carry
        // the same record shape and must be handled identically.
        if (event.eventType == .insert || event.eventType == .update),
           let idStr = dict["id"] as? String, let reactionId = UUID(uuidString: idStr),
           let userIdStr = dict["user_id"] as? String, let userId = UUID(uuidString: userIdStr),
           let reaction = dict["reaction"] as? String {
            let parsed = MessageReaction(
                id: reactionId,
                messageId: messageId,
                userId: userId,
                reaction: reaction
            )
            userInfo["reaction"] = parsed
        }

        // For delete events, include the user ID so the consumer can remove
        // the correct reaction locally.
        if event.eventType == .delete {
            let oldDict = event.oldRecord ?? dict
            if let userIdStr = oldDict["user_id"] as? String,
               let userId = UUID(uuidString: userIdStr) {
                userInfo["removedUserId"] = userId
            }
        }

        NotificationCenter.default.post(
            name: .messageReactionChanged,
            object: nil,
            userInfo: userInfo
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
