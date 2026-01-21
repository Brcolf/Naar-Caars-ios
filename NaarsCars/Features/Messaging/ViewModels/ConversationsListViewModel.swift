//
//  ConversationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for conversations list
//

import Foundation
internal import Combine
import Realtime

/// ViewModel for conversations list
@MainActor
final class ConversationsListViewModel: ObservableObject {
    @Published var conversations: [ConversationWithDetails] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreConversations: Bool = true
    @Published var error: AppError?
    
    private let messageService = MessageService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 10
    private var currentOffset = 0
    
    init() {
        setupRealtimeSubscription()
        setupMessagesRealtimeSubscription()
    }
    
    deinit {
        // Use Task.detached to avoid capturing self strongly
        let convChannelName = "conversations:all"
        let msgChannelName = "messages:list-updates"
        Task.detached {
            await RealtimeManager.shared.unsubscribe(channelName: convChannelName)
            await RealtimeManager.shared.unsubscribe(channelName: msgChannelName)
        }
    }
    
    func loadConversations() async {
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        error = nil
        currentOffset = 0
        hasMoreConversations = true
        
        do {
            let fetched = try await messageService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            self.conversations = fetched
            currentOffset = fetched.count
            hasMoreConversations = fetched.count == pageSize
        } catch {
            // Don't show error if task was cancelled (happens during pull-to-refresh)
            // Check both for CancellationError and if error message contains "cancelled"
            if Task.isCancelled || error is CancellationError || error.localizedDescription.lowercased().contains("cancel") {
                print("ℹ️ Load conversations task was cancelled, ignoring error")
            } else {
                self.error = AppError.processingError(error.localizedDescription)
                print("🔴 Error loading conversations: \(error.localizedDescription)")
            }
        }
        
        isLoading = false
    }
    
    func loadMoreConversations() async {
        guard !isLoadingMore, hasMoreConversations,
              let userId = authService.currentUserId else {
            return
        }
        
        isLoadingMore = true
        
        do {
            let fetched = try await messageService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            self.conversations.append(contentsOf: fetched)
            currentOffset += fetched.count
            hasMoreConversations = fetched.count == pageSize
        } catch {
            // Don't show error if task was cancelled
            if Task.isCancelled || error is CancellationError || error.localizedDescription.lowercased().contains("cancel") {
                print("ℹ️ Load more conversations task was cancelled, ignoring error")
            } else {
                print("🔴 Error loading more conversations: \(error.localizedDescription)")
                // Don't set error here - just log it
            }
        }
        
        isLoadingMore = false
    }
    
    func refreshConversations() async {
        guard let userId = authService.currentUserId else { return }
        await CacheManager.shared.invalidateConversations(userId: userId)
        await loadConversations()
    }
    
    private func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "conversations:all",
                table: "conversations",
                onInsert: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        print("📬 [ConversationsListVM] New conversation detected via realtime")
                        await self?.refreshConversations()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        print("📬 [ConversationsListVM] Conversation updated via realtime")
                        await self?.refreshConversations()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        print("📬 [ConversationsListVM] Conversation deleted via realtime")
                        await self?.refreshConversations()
                    }
                }
            )
        }
    }
    
    /// Subscribe to messages table for real-time list updates
    /// When a new message arrives, update the conversation preview immediately
    private func setupMessagesRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "messages:list-updates",
                table: "messages",
                // Note: No filter - RLS will ensure we only see messages we have access to
                // and Supabase will only send us events for conversations we're part of
                onInsert: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        self?.handleMessageInsertForList(payload)
                    }
                }
            )
        }
    }
    
    /// Handle a new message for updating the conversation list
    private func handleMessageInsertForList(_ payload: Any) {
        guard let message = parseMessageFromPayload(payload) else {
            print("⚠️ [ConversationsListVM] Could not parse message from payload, refreshing list")
            Task { await refreshConversations() }
            return
        }
        
        print("📬 [ConversationsListVM] New message in conversation \(message.conversationId)")
        
        // Find the conversation in our list
        if let index = conversations.firstIndex(where: { $0.conversation.id == message.conversationId }) {
            let existingConversation = conversations[index]
            
            // Show local notification if message is from someone else
            if let currentUserId = authService.currentUserId, message.fromId != currentUserId {
                // Get sender name from participants
                let senderName = existingConversation.otherParticipants
                    .first(where: { $0.id == message.fromId })?.name ?? "Someone"
                
                // Show local notification
                Task {
                    await PushNotificationService.shared.showLocalMessageNotification(
                        senderName: senderName,
                        messagePreview: message.text,
                        conversationId: message.conversationId
                    )
                }
            }
            
            // Calculate new unread count (increment if not from current user)
            var newUnreadCount = existingConversation.unreadCount
            if let currentUserId = authService.currentUserId, message.fromId != currentUserId {
                newUnreadCount += 1
            }
            
            // Create updated conversation with new message (ConversationWithDetails is immutable)
            let updatedConversation = ConversationWithDetails(
                conversation: existingConversation.conversation,
                lastMessage: message,
                unreadCount: newUnreadCount,
                otherParticipants: existingConversation.otherParticipants
            )
            
            // Remove from current position and insert at top (most recent)
            conversations.remove(at: index)
            conversations.insert(updatedConversation, at: 0)
            
            print("✅ [ConversationsListVM] Updated conversation \(message.conversationId) in list (moved to top)")
        } else {
            // Message is for a conversation not in our list - might be a new conversation
            print("ℹ️ [ConversationsListVM] Message for unknown conversation, refreshing list")
            Task { await refreshConversations() }
        }
    }
    
    /// Parse a Message from Supabase realtime payload
    private func parseMessageFromPayload(_ payload: Any) -> Message? {
        var recordDict: [String: Any]?
        
        if let insertAction = payload as? Realtime.InsertAction {
            recordDict = insertAction.record
        } else if let dict = payload as? [String: Any] {
            recordDict = dict["record"] as? [String: Any] ?? dict
        }
        
        guard let record = recordDict else {
            return nil
        }
        
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let conversationIdString = record["conversation_id"] as? String,
              let convId = UUID(uuidString: conversationIdString),
              let fromIdString = record["from_id"] as? String,
              let fromId = UUID(uuidString: fromIdString),
              let text = record["text"] as? String else {
            return nil
        }
        
        let imageUrl = record["image_url"] as? String
        let messageType = (record["message_type"] as? String).flatMap(MessageType.init(rawValue:))
        let audioUrl = record["audio_url"] as? String
        let audioDuration = parseDouble(record["audio_duration"])
        let latitude = parseDouble(record["latitude"])
        let longitude = parseDouble(record["longitude"])
        let locationName = record["location_name"] as? String
        
        var readBy: [UUID] = []
        if let readByArray = record["read_by"] as? [String] {
            readBy = readByArray.compactMap { UUID(uuidString: $0) }
        }
        
        var createdAt = Date()
        if let createdAtString = record["created_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: createdAtString) {
                createdAt = date
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: createdAtString) {
                    createdAt = date
                }
            }
        }
        
        return Message(
            id: id,
            conversationId: convId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            readBy: readBy,
            createdAt: createdAt,
            messageType: messageType,
            audioUrl: audioUrl,
            audioDuration: audioDuration,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let stringValue = value as? String {
            return Double(stringValue)
        }
        return nil
    }
    
    private func unsubscribeFromConversations() async {
        await realtimeManager.unsubscribe(channelName: "conversations:all")
        await realtimeManager.unsubscribe(channelName: "messages:list-updates")
    }
    
    // MARK: - Debug Support
    
    /// Get debug information about the current state
    func getDebugInfo() -> String {
        var info = """
        === Conversations List Debug Info ===
        Loaded Conversations: \(conversations.count)
        Is Loading: \(isLoading)
        Is Loading More: \(isLoadingMore)
        Has More: \(hasMoreConversations)
        Current Offset: \(currentOffset)
        Page Size: \(pageSize)
        """
        
        if let error = error {
            info += "\nError: \(error.localizedDescription)"
        }
        
        if !conversations.isEmpty {
            info += "\n\nFirst 5 Conversations:"
            for (index, conv) in conversations.prefix(5).enumerated() {
                info += "\n  \(index + 1). ID: \(conv.conversation.id)"
                info += "\n     Participants: \(conv.otherParticipants.count)"
                info += "\n     Last Message: \(conv.lastMessage?.text.prefix(30) ?? "None")"
            }
        }
        
        return info
    }
}

