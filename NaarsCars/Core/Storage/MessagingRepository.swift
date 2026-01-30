//
//  MessagingRepository.swift
//  NaarsCars
//

import Foundation
import SwiftData
import SwiftUI
internal import Combine
import CoreData

@MainActor
final class MessagingRepository {
    static let shared = MessagingRepository()
    
    private var modelContext: ModelContext?
    private let messageService = MessageService.shared
    
    var isConfigured: Bool {
        modelContext != nil
    }
    
    private init() {}
    
    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Conversations
    
    func getConversations() throws -> [ConversationWithDetails] {
        guard let modelContext = modelContext else { return [] }
        let descriptor = FetchDescriptor<SDConversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let sdConversations = try modelContext.fetch(descriptor)
        
        return sdConversations.map { sdConv in
            let lastSDMessage = sdConv.messages?.sorted(by: { $0.createdAt > $1.createdAt }).first
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
        let remoteConversations = try await messageService.fetchConversations(userId: userId)
        
        for remote in remoteConversations {
            let id = remote.conversation.id
            let fetchDescriptor = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == id })
            let existing = try modelContext.fetch(fetchDescriptor).first
            
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
        
        // Check for conversations that exist locally but not on remote (deleted elsewhere)
        let localDescriptor = FetchDescriptor<SDConversation>()
        let localConversations = try modelContext.fetch(localDescriptor)
        let remoteIds = Set(remoteConversations.map { $0.conversation.id })
        
        for local in localConversations {
            if !remoteIds.contains(local.id) {
                modelContext.delete(local)
            }
        }
        
        try modelContext.save()
    }
    
    // MARK: - Messages
    
    func getConversationsPublisher() -> AnyPublisher<[ConversationWithDetails], Never> {
        // Since SwiftData doesn't have a built-in Publisher for FetchDescriptors yet like CoreData,
        // we use a NotificationCenter approach or a simple Timer-based refresh for now, 
        // but the best way is to trigger a refresh whenever the context saves.
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: RunLoop.main)
            .map { _ in (try? self.getConversations()) ?? [] }
            .eraseToAnyPublisher()
    }
    
    func getMessagesPublisher(for conversationId: UUID) -> AnyPublisher<[Message], Never> {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: RunLoop.main)
            .map { _ in (try? self.getMessages(for: conversationId)) ?? [] }
            .eraseToAnyPublisher()
    }
    
    func getMessages(for conversationId: UUID) throws -> [Message] {
        guard let modelContext = modelContext else { return [] }
        let fetchDescriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let sdMessages = try modelContext.fetch(fetchDescriptor)
        return sdMessages.map { MessagingMapper.mapToMessage($0) }
    }
    
    func syncMessages(conversationId: UUID) async throws {
        guard let modelContext = modelContext else { return }
        // Incremental sync: only fetch messages newer than our latest local message
        let latestTimestamp = getLatestMessageTimestamp(for: conversationId)
        
        // We'll need to update MessageService to support fetching by timestamp, 
        // but for now we'll fetch the last 25 as a safety net.
        let remoteMessages = try await messageService.fetchMessages(conversationId: conversationId)
        
        for remote in remoteMessages {
            try upsertMessage(remote)
        }
        
        try modelContext.save()
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
        try modelContext.save()
        
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
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    sdMessage.syncError = error.localizedDescription
                    try? modelContext.save()
                }
            }
        }
    }
    
    func fetchSDConversation(id: UUID) throws -> SDConversation? {
        guard let modelContext = modelContext else { return nil }
        let fetchDescriptor = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(fetchDescriptor).first
    }

    func save() throws {
        guard let modelContext = modelContext else { return }
        try modelContext.save()
    }

    func upsertMessage(_ message: Message) throws {
        guard let modelContext = modelContext else { return }
        let id = message.id
        let fetchDescriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
        let existing = try modelContext.fetch(fetchDescriptor).first
        
        if let existing = existing {
            let previousReadBy = existing.readBy
            existing.text = message.text
            existing.readBy = message.readBy
            existing.imageUrl = message.imageUrl
            existing.audioUrl = message.audioUrl
            existing.audioDuration = message.audioDuration
            existing.latitude = message.latitude
            existing.longitude = message.longitude
            existing.locationName = message.locationName
            existing.isPending = false // If it's from sync, it's not pending
            
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

    private func updateUnreadCount(for conversation: SDConversation) {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        let messages = conversation.messages ?? []
        let unreadCount = messages.filter { msg in
            msg.fromId != currentUserId && !msg.readBy.contains(currentUserId)
        }.count
        conversation.unreadCount = unreadCount
    }

    func deleteConversation(id: UUID) async throws {
        guard let modelContext = modelContext else { return }
        
        // 1. Delete from Supabase
        try await messageService.deleteConversation(id: id)
        
        // 2. Delete from local SwiftData
        let fetchDescriptor = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
            
            // 3. Post notification to force UI refresh
            NotificationCenter.default.post(name: NSNotification.Name("conversationUpdated"), object: id)
        }
    }
}

