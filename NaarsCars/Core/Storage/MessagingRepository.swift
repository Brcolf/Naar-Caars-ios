//
//  MessagingRepository.swift
//  NaarsCars
//

import Foundation
import SwiftData
import SwiftUI
internal import Combine

@MainActor
final class MessagingRepository {
    static let shared = MessagingRepository()
    
    private var modelContext: ModelContext?
    private let messageService = MessageService.shared
    private let conversationService = ConversationService.shared
    private var lastMessageBackfillSyncAt: [UUID: Date] = [:]
    private let messageBackfillInterval: TimeInterval = 30
    private let conversationsSubject = CurrentValueSubject<[ConversationWithDetails], Never>([])
    private var messageSubjects: [UUID: CurrentValueSubject<[Message], Never>] = [:]
    
    /// Publisher for metadata-only changes (readBy, reactions) — allows views to update individual
    /// messages in-place without triggering a full list diff
    private var messageMetadataSubjects: [UUID: PassthroughSubject<MessageMetadataUpdate, Never>] = [:]

    /// Live subscriber count per conversation across both message publishers. A conversation's
    /// subjects are released once this drops to zero, so the repository only retains mapped
    /// message history for conversations that are currently being observed (bounded by the open
    /// detail screens). `getMessagesPublisher` rebuilds the subject from SwiftData on the next request.
    private var messageSubscriberCounts: [UUID: Int] = [:]

    var isConfigured: Bool {
        modelContext != nil
    }
    
    /// Expose the model context for the MessageSendWorker (read-only access)
    var modelContextForWorker: ModelContext? {
        modelContext
    }
    
    private init() {}

    /// Set up the model context for SwiftData operations.
    /// The conversations publisher is populated asynchronously to avoid blocking
    /// the main thread during app init (was taking 1.3s+ for O(n) SwiftData fetches).
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task { @MainActor in
            await Task.yield()
            refreshConversationsPublisher()
        }
    }

    /// Reset all in-memory publisher caches on sign-out.
    /// Must be called BEFORE the UI transition notification so new sessions start clean.
    func resetPublishers() {
        conversationsSubject.send([])
        messageSubjects.removeAll()
        messageMetadataSubjects.removeAll()
        messageSubscriberCounts.removeAll()
        lastMessageBackfillSyncAt.removeAll()
    }
    
    // MARK: - Conversations
    
    func getConversations(for userId: UUID? = nil) throws -> [ConversationWithDetails] {
        try buildConversations(for: userId, cachedLastMessages: [:])
    }

    /// Shared builder for `getConversations` and the incremental publisher refresh.
    /// `cachedLastMessages` holds last messages known to be current, keyed by conversation id
    /// (a present key with a nil value means "known to have no last message"); conversations
    /// absent from it run the per-conversation last-message query. Everything else — ordering,
    /// unreadCount, participantIds, deletions — always comes from the fresh SDConversation fetch.
    private func buildConversations(
        for userId: UUID?,
        cachedLastMessages: [UUID: Message?]
    ) throws -> [ConversationWithDetails] {
        guard let modelContext = modelContext else { return [] }
        let descriptor = FetchDescriptor<SDConversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let allConversations = try modelContext.fetch(descriptor)

        // Defensive filter: only return conversations where user is a participant.
        // After the sign-out wipe fix this should never filter anything, but guards
        // against cross-user data leakage if a race ever reappears.
        let sdConversations: [SDConversation]
        if let userId {
            let before = allConversations.count
            sdConversations = allConversations.filter { $0.participantIds.contains(userId) }
            let removed = before - sdConversations.count
            if removed > 0 {
                AppLogger.warning("messaging", "[MessagingRepository] Filtered \(removed) conversations not belonging to user \(userId) — possible cross-user leak")
            }
        } else {
            sdConversations = allConversations
        }
        
        return sdConversations.map { sdConv in
            let lastMessage: Message?
            if let cached = cachedLastMessages[sdConv.id] {
                lastMessage = cached
            } else {
                // Query by conversationId field (not relationship) for reliability —
                // the @Relationship may not eagerly include all linked messages.
                let convId = sdConv.id
                let msgDescriptor = FetchDescriptor<SDMessage>(
                    predicate: #Predicate<SDMessage> {
                        $0.conversationId == convId
                        && $0.messageType != "system"
                        && $0.deletedAt == nil
                    },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                var msgFetch = msgDescriptor
                msgFetch.fetchLimit = 1
                let lastSDMessage = (try? modelContext.fetch(msgFetch))?.first
                lastMessage = lastSDMessage.map { MessagingMapper.mapToMessage($0) }
            }

            var conversation = MessagingMapper.mapToConversation(sdConv, lastMessage: lastMessage, unreadCount: sdConv.unreadCount)
            
            // Map participant IDs back to ConversationParticipant objects for compatibility
            let participants = sdConv.participantIds.map { userId in
                ConversationParticipant(conversationId: sdConv.id, userId: userId)
            }
            conversation.participants = participants
            
            return ConversationWithDetails(
                conversation: conversation,
                lastMessage: lastMessage,
                unreadCount: sdConv.unreadCount,
                otherParticipants: [] // Profiles will be hydrated by the ViewModel
            )
        }
    }
    
    func syncConversations(userId: UUID) async throws {
        guard let modelContext = modelContext else { return }
        let remoteConversations = try await conversationService.fetchConversations(userId: userId)
        var changedConversationIds = Set<UUID>()
        
        for remote in remoteConversations {
            let id = remote.conversation.id
            let fetchDescriptor = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == id })
            let existing = try modelContext.fetch(fetchDescriptor).first
            changedConversationIds.insert(id)
            
            // Collect all participant IDs from other participants + current user
            let participantIds = remote.otherParticipants.map { $0.id } + [userId]
            
            if let existing = existing {
                existing.title = remote.conversation.title
                existing.groupImageUrl = remote.conversation.groupImageUrl
                existing.isArchived = remote.conversation.isArchived
                existing.updatedAt = remote.conversation.updatedAt
                existing.unreadCount = remote.unreadCount
                existing.participantIds = participantIds
            } else {
                let newSDConv = MessagingMapper.mapToSDConversation(remote.conversation, participantIds: participantIds)
                newSDConv.unreadCount = remote.unreadCount
                modelContext.insert(newSDConv)
            }
            
            // Also sync the last message if available
            if let lastMessage = remote.lastMessage {
                try upsertMessage(lastMessage)
            }
        }
        
        // Note: We do NOT delete local conversations missing from the remote result,
        // because the sync only fetches a single page (default limit 10). Deleting
        // conversations not in that page would destroy paginated data the user has
        // already scrolled through. Conversations are removed via the explicit
        // soft-delete flow (deleteConversation) instead.

        try save(changedConversationIds: changedConversationIds)
    }
    
    // MARK: - Messages
    
    func getConversationsPublisher() -> AnyPublisher<[ConversationWithDetails], Never> {
        refreshConversationsPublisher()
        return conversationsSubject.eraseToAnyPublisher()
    }
    
    func getMessagesPublisher(for conversationId: UUID) -> AnyPublisher<[Message], Never> {
        let subject: CurrentValueSubject<[Message], Never>
        if let existing = messageSubjects[conversationId] {
            subject = existing
        } else {
            subject = CurrentValueSubject<[Message], Never>((try? getMessages(for: conversationId)) ?? [])
            messageSubjects[conversationId] = subject
        }
        return trackSubscribers(of: subject, for: conversationId)
    }

    /// Publisher for metadata-only updates (readBy changes) that don't require full list re-rendering
    func getMessageMetadataPublisher(for conversationId: UUID) -> AnyPublisher<MessageMetadataUpdate, Never> {
        let subject: PassthroughSubject<MessageMetadataUpdate, Never>
        if let existing = messageMetadataSubjects[conversationId] {
            subject = existing
        } else {
            subject = PassthroughSubject<MessageMetadataUpdate, Never>()
            messageMetadataSubjects[conversationId] = subject
        }
        return trackSubscribers(of: subject, for: conversationId)
    }

    /// Wrap a per-conversation subject so the conversation's subjects are released once its
    /// last subscriber cancels (ConversationDetailViewModel.stop() clears its cancellables).
    /// The closures are formed on the main actor, like the ViewModels' own sinks.
    private func trackSubscribers<P: Publisher>(of publisher: P, for conversationId: UUID) -> AnyPublisher<P.Output, P.Failure> {
        publisher
            .handleEvents(
                receiveSubscription: { [weak self] _ in
                    self?.retainMessageSubjects(for: conversationId)
                },
                receiveCancel: { [weak self] in
                    self?.releaseMessageSubjects(for: conversationId)
                }
            )
            .eraseToAnyPublisher()
    }

    private func retainMessageSubjects(for conversationId: UUID) {
        messageSubscriberCounts[conversationId, default: 0] += 1
    }

    private func releaseMessageSubjects(for conversationId: UUID) {
        // No tracked subscribers (e.g. a late cancel after resetPublishers) — nothing to release.
        guard let count = messageSubscriberCounts[conversationId] else { return }
        if count > 1 {
            messageSubscriberCounts[conversationId] = count - 1
            return
        }
        messageSubscriberCounts.removeValue(forKey: conversationId)
        messageSubjects.removeValue(forKey: conversationId)
        messageMetadataSubjects.removeValue(forKey: conversationId)
    }
    
    func getMessages(for conversationId: UUID) throws -> [Message] {
        guard let modelContext = modelContext else { return [] }
        let fetchDescriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let sdMessages = try modelContext.fetch(fetchDescriptor)
        let deletedIds = fetchLocallyDeletedMessageIds(for: conversationId)
        return sdMessages
            .filter { !deletedIds.contains($0.id) }
            .map { MessagingMapper.mapToMessage($0) }
    }
    
    func syncMessages(conversationId: UUID) async throws {
        guard modelContext != nil else { return }
        let latestTimestamp = getLatestMessageTimestamp(for: conversationId)
        let remoteMessages: [Message]

        if let latestTimestamp {
            let incrementalMessages = try await messageService.fetchMessagesCreatedAfter(
                conversationId: conversationId,
                after: latestTimestamp,
                limit: Constants.PageSizes.fetchAll
            )

            if incrementalMessages.isEmpty, shouldRunMessageBackfill(for: conversationId) {
                remoteMessages = try await messageService.fetchMessages(
                    conversationId: conversationId,
                    limit: Constants.PageSizes.messages
                )
                lastMessageBackfillSyncAt[conversationId] = Date()
            } else {
                remoteMessages = incrementalMessages
            }
        } else {
            remoteMessages = try await messageService.fetchMessages(
                conversationId: conversationId,
                limit: Constants.PageSizes.messages
            )
            lastMessageBackfillSyncAt[conversationId] = Date()
        }

#if DEBUG
        if FeatureFlags.verbosePerformanceLogsEnabled {
            let replyIds = remoteMessages.filter { $0.replyToId != nil }.count
            let replyContexts = remoteMessages.filter { $0.replyToMessage != nil }.count
            AppLogger.info("messaging", "sync(remote) total=\(remoteMessages.count) replyToId=\(replyIds) replyContext=\(replyContexts)")
            if let sample = remoteMessages.first(where: { $0.replyToId != nil }) {
                AppLogger.info("messaging", "remote sample messageId=\(sample.id) replyToId=\(sample.replyToId?.uuidString ?? "nil") context=\(sample.replyToMessage != nil)")
            }
        }
#endif
        
        for remote in remoteMessages {
            try upsertMessage(remote)
        }

        try save(changedConversationIds: Set([conversationId]))
    }

    private func shouldRunMessageBackfill(for conversationId: UUID) -> Bool {
        guard let lastSyncAt = lastMessageBackfillSyncAt[conversationId] else { return true }
        return Date().timeIntervalSince(lastSyncAt) >= messageBackfillInterval
    }

    func getLatestMessageTimestamp(for conversationId: UUID) -> Date? {
        guard let modelContext = modelContext else { return nil }
        var fetchDescriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        fetchDescriptor.fetchLimit = 1
        return (try? modelContext.fetch(fetchDescriptor))?.first?.createdAt
    }
    
    func fetchSDConversation(id: UUID) throws -> SDConversation? {
        guard let modelContext = modelContext else { return nil }
        let fetchDescriptor = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(fetchDescriptor).first
    }

    func save(changedConversationIds: Set<UUID> = []) throws {
        guard let modelContext = modelContext else { return }
        try modelContext.save()
        refreshConversationsPublisher(changedConversationIds: changedConversationIds)
        refreshMessagesPublishers(changedConversationIds: changedConversationIds)
    }
    
    /// Save the SwiftData context without triggering any publisher refreshes.
    /// Used for metadata-only updates (readBy) where the metadata publisher already handled the UI update.
    func saveContextOnly() throws {
        guard let modelContext = modelContext else { return }
        try modelContext.save()
    }

    /// Result type for upsert operations to distinguish content vs metadata changes
    enum UpsertResult {
        case noChange
        case contentChanged
        case metadataOnly
        case inserted
    }
    
    @discardableResult
    func upsertMessage(_ message: Message) throws -> Bool {
        try upsertMessageDetailed(message) != .noChange
    }
    
    /// Upsert with detailed result indicating what kind of change occurred
    func upsertMessageDetailed(_ message: Message) throws -> UpsertResult {
        guard let modelContext = modelContext else { return .noChange }
        let id = message.id
        let fetchDescriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
        let currentUserId = AuthService.shared.currentUserId
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            return updateExistingMessage(existing, with: message, currentUserId: currentUserId)
        }
        let sdConv = try fetchSDConversation(id: message.conversationId)
        insertNewMessage(message, conversation: sdConv, currentUserId: currentUserId, modelContext: modelContext)
        return .inserted
    }

    /// Batch form of `upsertMessageDetailed` for REST hydration pages: one prefetch of the
    /// existing rows by id and one conversation fetch per distinct conversation instead of a
    /// SwiftData fetch per message. Each message goes through the same per-message body as the
    /// single API, so the `UpsertResult` values, unread-count math and metadata-publisher
    /// emissions are identical to calling `upsertMessageDetailed` in order. Synchronous on the
    /// main actor — no suspension point, so buffered WebSocket events cannot interleave.
    func upsertMessagesDetailed(_ messages: [Message]) throws -> [UUID: UpsertResult] {
        guard let modelContext = modelContext, !messages.isEmpty else { return [:] }
        let ids = messages.map { $0.id }
        let existingDescriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { ids.contains($0.id) })
        let existingRows = try modelContext.fetch(existingDescriptor)
        var existingById = Dictionary(existingRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentUserId = AuthService.shared.currentUserId
        var conversationsById: [UUID: SDConversation?] = [:]
        var results: [UUID: UpsertResult] = [:]

        for message in messages {
            let result: UpsertResult
            if let existing = existingById[message.id] {
                result = updateExistingMessage(existing, with: message, currentUserId: currentUserId)
            } else {
                let sdConv: SDConversation?
                if let cached = conversationsById[message.conversationId] {
                    sdConv = cached
                } else {
                    sdConv = try fetchSDConversation(id: message.conversationId)
                    conversationsById.updateValue(sdConv, forKey: message.conversationId)
                }
                // Track the new row so a repeated id later in the same batch is treated as an
                // update, exactly as a per-message fetch would see the earlier unsaved insert.
                existingById[message.id] = insertNewMessage(
                    message, conversation: sdConv, currentUserId: currentUserId, modelContext: modelContext
                )
                result = .inserted
            }
            if let previous = results[message.id], Self.rank(previous) >= Self.rank(result) {
                continue
            }
            results[message.id] = result
        }
        return results
    }

    /// Ordering used when a message id appears more than once in a batch: the outcome implying
    /// the larger change wins, so a later `.noChange` can never mask an earlier insert or edit.
    private static func rank(_ result: UpsertResult) -> Int {
        switch result {
        case .noChange: return 0
        case .metadataOnly: return 1
        case .contentChanged: return 2
        case .inserted: return 3
        }
    }

    /// Update path shared by the single and batch upserts. Change detection, field copy, the
    /// incremental unread count and the metadata-only publisher emission are unchanged.
    private func updateExistingMessage(_ existing: SDMessage, with message: Message, currentUserId: UUID?) -> UpsertResult {
        let incomingStatus = message.sendStatus?.rawValue ?? "sent"

        // Check if ONLY readBy changed (metadata-only update)
        let readByChanged = existing.readBy != message.readBy
        let contentChanged =
            existing.text != message.text ||
            existing.imageUrl != message.imageUrl ||
            existing.audioUrl != message.audioUrl ||
            existing.audioDuration != message.audioDuration ||
            existing.latitude != message.latitude ||
            existing.longitude != message.longitude ||
            existing.locationName != message.locationName ||
            existing.messageType != (message.messageType?.rawValue ?? "text") ||
            existing.replyToId != message.replyToId ||
            existing.editedAt != message.editedAt ||
            existing.deletedAt != message.deletedAt ||
            existing.hiddenAt != message.hiddenAt ||
            existing.hiddenBy != message.hiddenBy ||
            existing.hiddenReason != message.hiddenReason ||
            existing.status != incomingStatus ||
            existing.localAttachmentPath != message.localAttachmentPath ||
            existing.isPending

        guard readByChanged || contentChanged else { return .noChange }

        let previousReadBy = existing.readBy
        existing.text = message.text
        existing.readBy = message.readBy
        existing.imageUrl = message.imageUrl
        existing.audioUrl = message.audioUrl
        existing.audioDuration = message.audioDuration
        existing.latitude = message.latitude
        existing.longitude = message.longitude
        existing.locationName = message.locationName
        existing.messageType = message.messageType?.rawValue ?? "text"
        existing.replyToId = message.replyToId
        existing.editedAt = message.editedAt
        existing.deletedAt = message.deletedAt
        existing.hiddenAt = message.hiddenAt
        existing.hiddenBy = message.hiddenBy
        existing.hiddenReason = message.hiddenReason
        existing.status = incomingStatus
        existing.localAttachmentPath = message.localAttachmentPath
        existing.syncError = message.syncError
        existing.isPending = incomingStatus == "sending"
        
        // Update unread count incrementally to avoid rescanning all messages
        if let sdConv = existing.conversation,
           let currentUserId {
            sdConv.unreadCount = Self.updatedUnreadCount(
                currentCount: sdConv.unreadCount,
                fromId: message.fromId,
                currentUserId: currentUserId,
                previousReadBy: previousReadBy,
                newReadBy: message.readBy
            )
        }

        // If only readBy changed, emit on metadata publisher instead of full list rebuild
        if readByChanged && !contentChanged {
            messageMetadataSubjects[message.conversationId]?.send(
                MessageMetadataUpdate(messageId: message.id, readBy: message.readBy)
            )
            return .metadataOnly
        }

        return .contentChanged
    }

    /// Insert path shared by the single and batch upserts. Links the new row to `conversation`
    /// when it exists locally, bumping the conversation's `updatedAt` and unread count.
    @discardableResult
    private func insertNewMessage(
        _ message: Message,
        conversation sdConv: SDConversation?,
        currentUserId: UUID?,
        modelContext: ModelContext
    ) -> SDMessage {
        let newSDMessage = MessagingMapper.mapToSDMessage(message)

        // Link to conversation
        if let sdConv {
            newSDMessage.conversation = sdConv
            // Update conversation's updatedAt to ensure it moves to top of list
            if message.createdAt > sdConv.updatedAt {
                sdConv.updatedAt = message.createdAt
            }
            if let currentUserId {
                sdConv.unreadCount = Self.updatedUnreadCountForInsert(
                    currentCount: sdConv.unreadCount,
                    fromId: message.fromId,
                    currentUserId: currentUserId,
                    readBy: message.readBy
                )
            }
        }

        modelContext.insert(newSDMessage)
        return newSDMessage
    }

    static func updatedUnreadCount(
        currentCount: Int,
        fromId: UUID,
        currentUserId: UUID,
        previousReadBy: [UUID],
        newReadBy: [UUID]
    ) -> Int {
        guard fromId != currentUserId else { return currentCount }
        let didRead = previousReadBy.contains(currentUserId)
        let nowRead = newReadBy.contains(currentUserId)
        if !didRead && nowRead {
            return max(currentCount - 1, 0)
        }
        if didRead && !nowRead {
            return currentCount + 1
        }
        return currentCount
    }

    static func updatedUnreadCountForInsert(
        currentCount: Int,
        fromId: UUID,
        currentUserId: UUID,
        readBy: [UUID]
    ) -> Int {
        guard fromId != currentUserId else { return currentCount }
        guard !readBy.contains(currentUserId) else { return currentCount }
        return currentCount + 1
    }

    func fetchSDMessage(id: UUID) throws -> SDMessage? {
        guard let modelContext = modelContext else { return nil }
        let fetchDescriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(fetchDescriptor).first
    }

    /// Delete a message from SwiftData by ID (used for replacing optimistic messages)
    func deleteMessage(id: UUID) {
        guard let modelContext = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(existing)
        }
    }

    private func updateUnreadCount(for conversation: SDConversation) {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        let messages = conversation.messages ?? []
        let unreadCount = messages.filter { msg in
            msg.fromId != currentUserId && !msg.readBy.contains(currentUserId)
        }.count
        conversation.unreadCount = unreadCount
    }

    func deleteConversation(id: UUID) async throws {
        // 1. Soft-delete: hide the conversation for the current user via UserDefaults
        try await conversationService.deleteConversation(id: id)

        // 2. Keep the SwiftData record so it can be restored when new messages arrive.
        //    filterHiddenConversations() already hides it from the UI.
        //    Post notification so other observers can react.
        NotificationCenter.default.post(name: .conversationUpdated, object: id)
    }

    /// Remove a participant from local SDConversation after a successful server leave/remove.
    /// This prevents phantom participants between syncs.
    func removeParticipantLocally(conversationId: UUID, userId: UUID) {
        guard let modelContext = self.modelContext else { return }
        do {
            let descriptor = FetchDescriptor<SDConversation>(
                predicate: #Predicate { $0.id == conversationId }
            )
            guard let sdConv = try modelContext.fetch(descriptor).first else { return }
            sdConv.participantIds.removeAll { $0 == userId }
            try modelContext.save()
            refreshConversationsPublisher()
        } catch {
            AppLogger.error("messaging", "Failed to remove participant locally: \(error)")
        }
    }

    // MARK: - Delete for Me (local-only message hiding)

    /// Record a message as locally hidden ("Delete for Me") so it is excluded from future fetches.
    func deleteMessageForMe(messageId: UUID, conversationId: UUID) {
        guard let modelContext = modelContext else { return }
        // Avoid duplicate records
        let existing = FetchDescriptor<SDDeletedMessage>(
            predicate: #Predicate<SDDeletedMessage> { $0.messageId == messageId }
        )
        guard (try? modelContext.fetch(existing))?.isEmpty ?? true else { return }

        let record = SDDeletedMessage(messageId: messageId, conversationId: conversationId)
        modelContext.insert(record)
        try? modelContext.save()
        refreshMessagesPublishers(changedConversationIds: Set([conversationId]))
        refreshConversationsPublisher()
    }

    /// Fetch all locally-deleted message IDs for a given conversation.
    func fetchLocallyDeletedMessageIds(for conversationId: UUID) -> Set<UUID> {
        guard let modelContext = modelContext else { return [] }
        let descriptor = FetchDescriptor<SDDeletedMessage>(
            predicate: #Predicate<SDDeletedMessage> { $0.conversationId == conversationId }
        )
        let deleted = (try? modelContext.fetch(descriptor)) ?? []
        return Set(deleted.map { $0.messageId })
    }

    /// Refresh Combine publishers after a background actor write has persisted data.
    /// The MainActor model context re-fetches from the store and pushes new values to subscribers.
    func refreshPublishersAfterBackgroundSync(changedConversationIds: Set<UUID> = []) {
        refreshConversationsPublisher(changedConversationIds: changedConversationIds)
        refreshMessagesPublishers(changedConversationIds: changedConversationIds)
    }

    /// Re-emit the conversation list. With a non-empty `changedConversationIds`, the last-message
    /// query runs only for those conversations and for any not present in the previous emission;
    /// every other conversation reuses the last message it emitted before (every path that writes
    /// an SDMessage passes its conversation id to `save`). Conversation rows are always re-fetched,
    /// so ordering by updatedAt, unread counts, participants and deletions are current either way.
    /// An empty set is a full rebuild (setup, first subscription, participant removal, delete-for-me).
    private func refreshConversationsPublisher(changedConversationIds: Set<UUID> = []) {
        var cachedLastMessages: [UUID: Message?] = [:]
        if !changedConversationIds.isEmpty {
            for details in conversationsSubject.value where !changedConversationIds.contains(details.id) {
                cachedLastMessages.updateValue(details.lastMessage, forKey: details.id)
            }
        }
        conversationsSubject.send((try? buildConversations(for: nil, cachedLastMessages: cachedLastMessages)) ?? [])
    }

    private func refreshMessagesPublishers(changedConversationIds: Set<UUID>) {
        if changedConversationIds.isEmpty {
            for (conversationId, subject) in messageSubjects {
                subject.send((try? getMessages(for: conversationId)) ?? [])
            }
            return
        }

        for conversationId in changedConversationIds {
            guard let subject = messageSubjects[conversationId] else { continue }
            subject.send((try? getMessages(for: conversationId)) ?? [])
        }
    }
}

// MARK: - Message Metadata Update

/// Lightweight update for metadata-only changes (readBy) that don't require full list re-rendering
struct MessageMetadataUpdate {
    let messageId: UUID
    let readBy: [UUID]
}