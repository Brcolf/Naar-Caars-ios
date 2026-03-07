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
    
    var isConfigured: Bool {
        modelContext != nil
    }
    
    /// Expose the model context for the MessageSendWorker (read-only access)
    var modelContextForWorker: ModelContext? {
        modelContext
    }
    
    private init() {}
    
    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshConversationsPublisher()
    }
    
    // MARK: - Conversations
    
    func getConversations() throws -> [ConversationWithDetails] {
        guard let modelContext = modelContext else { return [] }
        let descriptor = FetchDescriptor<SDConversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let sdConversations = try modelContext.fetch(descriptor)
        
        return sdConversations.map { sdConv in
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
            let lastMessage = lastSDMessage.map { MessagingMapper.mapToMessage($0) }
            
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
        if let existing = messageSubjects[conversationId] {
            return existing.eraseToAnyPublisher()
        }
        let subject = CurrentValueSubject<[Message], Never>((try? getMessages(for: conversationId)) ?? [])
        messageSubjects[conversationId] = subject
        return subject.eraseToAnyPublisher()
    }
    
    /// Publisher for metadata-only updates (readBy changes) that don't require full list re-rendering
    func getMessageMetadataPublisher(for conversationId: UUID) -> AnyPublisher<MessageMetadataUpdate, Never> {
        if let existing = messageMetadataSubjects[conversationId] {
            return existing.eraseToAnyPublisher()
        }
        let subject = PassthroughSubject<MessageMetadataUpdate, Never>()
        messageMetadataSubjects[conversationId] = subject
        return subject.eraseToAnyPublisher()
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
        let fetchDescriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(fetchDescriptor))?.first?.createdAt
    }
    
    func sendMessage(conversationId: UUID, fromId: UUID, text: String, imageUrl: String? = nil, replyToId: UUID? = nil) async throws {
        guard let modelContext = modelContext else { return }
        // 1. Create optimistic local message
        let tempId = UUID()
        let optimisticMessage = Message(
            id: tempId,
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            createdAt: Date(),
            messageType: imageUrl != nil ? .image : .text,
            replyToId: replyToId
        )
        
        let sdMessage = MessagingMapper.mapToSDMessage(optimisticMessage, isPending: true)
        
        // Link to conversation
        let convFetch = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == conversationId })
        if let sdConv = try modelContext.fetch(convFetch).first {
            sdMessage.conversation = sdConv
            sdConv.updatedAt = Date()
        }
        
        modelContext.insert(sdMessage)
        try save(changedConversationIds: Set([conversationId]))
        
        // 2. Attempt background sync
        Task {
            do {
                let sentMessage = try await messageService.sendMessage(
                    conversationId: conversationId,
                    fromId: fromId,
                    text: text,
                    imageUrl: imageUrl,
                    replyToId: replyToId
                )
                
                // 3. Replace optimistic message with real one
                await MainActor.run {
                    modelContext.delete(sdMessage)
                    let finalSDMessage = MessagingMapper.mapToSDMessage(sentMessage, isPending: false)
                    
                    if let sdConv = try? modelContext.fetch(convFetch).first {
                        finalSDMessage.conversation = sdConv
                        sdConv.updatedAt = sentMessage.createdAt
                    }
                    
                    modelContext.insert(finalSDMessage)
                    try? self.save(changedConversationIds: Set([conversationId]))
                }
            } catch {
                await MainActor.run {
                    sdMessage.syncError = error.localizedDescription
                    try? self.save(changedConversationIds: Set([conversationId]))
                }
            }
        }
    }
    
    func fetchSDConversation(id: UUID) throws -> SDConversation? {
        guard let modelContext = modelContext else { return nil }
        let fetchDescriptor = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(fetchDescriptor).first
    }

    func save(changedConversationIds: Set<UUID> = []) throws {
        guard let modelContext = modelContext else { return }
        try modelContext.save()
        refreshConversationsPublisher()
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
        let existing = try modelContext.fetch(fetchDescriptor).first
        
        if let existing = existing {
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
            existing.status = incomingStatus
            existing.localAttachmentPath = message.localAttachmentPath
            existing.syncError = message.syncError
            existing.isPending = incomingStatus == "sending"
            
            // Update unread count incrementally to avoid rescanning all messages
            if let sdConv = existing.conversation,
               let currentUserId = AuthService.shared.currentUserId {
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
        } else {
            let newSDMessage = MessagingMapper.mapToSDMessage(message)
            
            // Link to conversation
            let convId = message.conversationId
            let convFetch = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == convId })
            if let sdConv = try modelContext.fetch(convFetch).first {
                newSDMessage.conversation = sdConv
                // Update conversation's updatedAt to ensure it moves to top of list
                if message.createdAt > sdConv.updatedAt {
                    sdConv.updatedAt = message.createdAt
                }
                if let currentUserId = AuthService.shared.currentUserId {
                    sdConv.unreadCount = Self.updatedUnreadCountForInsert(
                        currentCount: sdConv.unreadCount,
                        fromId: message.fromId,
                        currentUserId: currentUserId,
                        readBy: message.readBy
                    )
                }
            }
            
            modelContext.insert(newSDMessage)
            return .inserted
        }
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
        refreshConversationsPublisher()
        refreshMessagesPublishers(changedConversationIds: changedConversationIds)
    }

    private func refreshConversationsPublisher() {
        conversationsSubject.send((try? getConversations()) ?? [])
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