//
//  MessageService.swift
//  NaarsCars
//
//  Service for core message operations
//

import Foundation
import Supabase
import UIKit
import OSLog

/// Service for core message operations
/// Handles sending, fetching, pagination, and managing individual messages
final class MessageService {
    
    // MARK: - Singleton
    
    static let shared = MessageService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let rateLimiter = RateLimiter.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Private Helpers
    
    /// Create a date decoder with custom date decoding strategy
    private func createDateDecoder() -> JSONDecoder {
        DateDecoderFactory.makeMessagingDecoder()
    }

    private func createISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private func hasLocalConversationMembership(conversationId: UUID, userId: UUID) -> Bool? {
        do {
            guard let localConversation = try MessagingRepository.shared.fetchSDConversation(id: conversationId) else {
                return nil
            }
            return localConversation.createdBy == userId || localConversation.participantIds.contains(userId)
        } catch {
            AppLogger.warning("messaging", "Local membership check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func hasRemoteConversationMembership(conversationId: UUID, userId: UUID) async -> Bool {
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()

        let conversationCheck = try? await supabase
            .from("conversations")
            .select("created_by")
            .eq("id", value: conversationId.uuidString)
            .eq("created_by", value: userId.uuidString)
            .limit(1)
            .execute()

        let hasParticipant: Bool = {
            guard let data = participantCheck?.data,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return false
            }
            return !rows.isEmpty
        }()
        let isCreator: Bool = {
            guard let data = conversationCheck?.data,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return false
            }
            return !rows.isEmpty
        }()
        return hasParticipant || isCreator
    }

    private func ensureConversationMembership(conversationId: UUID, userId: UUID) async -> Bool {
        if hasLocalConversationMembership(conversationId: conversationId, userId: userId) == true {
            return true
        }
        return await hasRemoteConversationMembership(conversationId: conversationId, userId: userId)
    }
    
    // MARK: - Fetch Messages
    
    /// Fetch messages for a conversation with pagination
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - limit: Maximum number of messages to fetch (default: 25)
    ///   - beforeMessageId: Optional message ID to fetch messages before (for pagination)
    /// - Returns: Array of messages ordered by creation date (oldest first)
    /// - Throws: AppError if fetch fails or user is not a participant
    func fetchMessages(conversationId: UUID, limit: Int = 25, beforeMessageId: UUID? = nil) async throws -> [Message] {
        // Security check: Verify user is a participant (RLS is disabled on conversation_participants)
        guard let currentUserId = AuthService.shared.currentUserId else {
            throw AppError.notAuthenticated
        }

        guard await ensureConversationMembership(conversationId: conversationId, userId: currentUserId) else {
            throw AppError.permissionDenied("You don't have permission to view messages in this conversation")
        }
        var query = supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("conversation_id", value: conversationId.uuidString)
        
        // If beforeMessageId is provided, fetch messages before that message
        if let beforeMessageId = beforeMessageId {
            // Get the created_at of the beforeMessageId message
            let beforeMessageResponse = try? await supabase
                .from("messages")
                .select("created_at")
                .eq("id", value: beforeMessageId.uuidString)
                .single()
                .execute()
            
            if let beforeData = beforeMessageResponse?.data {
                struct MessageDate: Codable {
                    let createdAt: Date
                    enum CodingKeys: String, CodingKey {
                        case createdAt = "created_at"
                    }
                }
                if let beforeMessage = try? createDateDecoder().decode(MessageDate.self, from: beforeData) {
                    // Fetch messages created before this date (for pagination - older messages)
                    let formatter = createISO8601Formatter()
                    query = query.lt("created_at", value: formatter.string(from: beforeMessage.createdAt))
                }
            }
        }
        
        // Order by created_at descending (newest first), then reverse for display
        // When beforeMessageId is provided, we want older messages (created_at < beforeMessage.created_at)
        // For initial load, get the most recent messages
        let response = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        
        let decoder = createDateDecoder()
        var messages: [Message] = try decoder.decode([Message].self, from: response.data)
        
        // Reverse to get oldest first (for display - newest at bottom)
        messages.reverse()
        
        await enrichMessages(&messages)
        
        // Cache results (only cache if this is the initial load, not pagination)
        AppLogger.network.info("Fetched \(messages.count) messages from network.")
        return messages
    }

    /// Fetch messages newer than a timestamp for incremental sync.
    /// Returns messages ordered oldest-first.
    func fetchMessagesCreatedAfter(
        conversationId: UUID,
        after: Date,
        limit: Int
    ) async throws -> [Message] {
        guard let currentUserId = AuthService.shared.currentUserId else {
            throw AppError.notAuthenticated
        }

        guard await ensureConversationMembership(conversationId: conversationId, userId: currentUserId) else {
            throw AppError.permissionDenied("You don't have permission to view messages in this conversation")
        }

        let formatter = createISO8601Formatter()
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("conversation_id", value: conversationId.uuidString)
            .gt("created_at", value: formatter.string(from: after))
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()

        let decoder = createDateDecoder()
        var messages = try decoder.decode([Message].self, from: response.data)
        await enrichMessages(&messages)
        return messages
    }

    /// Fetch media messages for a conversation filtered by message type
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - type: The message type to filter by (e.g. "image", "audio", "link")
    /// - Returns: Array of messages of the given type, ordered newest first
    func fetchMediaMessages(conversationId: UUID, type: String) async throws -> [Message] {
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("message_type", value: type)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
        
        let decoder = createDateDecoder()
        let messages = try decoder.decode([Message].self, from: response.data)
        return messages
    }
    
    /// Fetch messages containing URLs for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of text messages containing links, ordered newest first
    func fetchLinkMessages(conversationId: UUID) async throws -> [Message] {
        // Fetch text messages and filter client-side for URLs
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("message_type", value: "text")
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
        
        let decoder = createDateDecoder()
        let messages = try decoder.decode([Message].self, from: response.data)
        
        // Filter for messages that contain URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return messages.filter { message in
            guard !message.text.isEmpty else { return false }
            let range = NSRange(message.text.startIndex..., in: message.text)
            return (detector?.numberOfMatches(in: message.text, range: range) ?? 0) > 0
        }
    }
    
    /// Fetch replies to a single message (ordered oldest first)
    func fetchReplies(conversationId: UUID, replyToId: UUID) async throws -> [Message] {
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("reply_to_id", value: replyToId.uuidString)
            .order("created_at", ascending: true)
            .execute()
        
        let decoder = createDateDecoder()
        var messages = try decoder.decode([Message].self, from: response.data)
        await enrichMessages(&messages)
        return messages
    }

    /// Fetch a single message by ID with sender join (for realtime enrichment)
    func fetchMessageById(_ messageId: UUID) async throws -> Message {
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("id", value: messageId.uuidString)
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        let message = try decoder.decode(Message.self, from: response.data)
        var messages = [message]
        await enrichMessages(&messages)
        return messages.first ?? message
    }

    // MARK: - Message Enrichment

    private func enrichMessages(_ messages: inout [Message]) async {
        await attachReactions(to: &messages)
        await attachReplyContexts(to: &messages)
    }

    private func attachReactions(to messages: inout [Message]) async {
        let messageIds = messages.map { $0.id.uuidString }
        guard !messageIds.isEmpty else { return }
        
        let reactionsResponse = try? await supabase
            .from("message_reactions")
            .select()
            .in("message_id", values: messageIds)
            .execute()
        
        guard let reactionsData = reactionsResponse?.data else { return }
        let decoder = createDateDecoder()
        let reactions: [MessageReaction] = (try? decoder.decode([MessageReaction].self, from: reactionsData)) ?? []
        
        // Group reactions by message ID
        var reactionsDict: [UUID: [String: [UUID]]] = [:]
        for reaction in reactions {
            if reactionsDict[reaction.messageId] == nil {
                reactionsDict[reaction.messageId] = [:]
            }
            if reactionsDict[reaction.messageId]?[reaction.reaction] == nil {
                reactionsDict[reaction.messageId]?[reaction.reaction] = []
            }
            reactionsDict[reaction.messageId]?[reaction.reaction]?.append(reaction.userId)
        }
        
        // Attach reactions to messages
        for index in messages.indices {
            if let reactionDict = reactionsDict[messages[index].id] {
                messages[index].reactions = MessageReactions(reactions: reactionDict)
            }
        }
    }

    private func attachReplyContexts(to messages: inout [Message]) async {
        let replyIds = Array(Set(messages.compactMap { $0.replyToId }))
        guard !replyIds.isEmpty else { return }
        
        if let replyContexts = try? await fetchReplyContexts(for: replyIds) {
            for index in messages.indices {
                if let replyId = messages[index].replyToId,
                   let context = replyContexts[replyId] {
                    messages[index].replyToMessage = context
                }
            }
        }
    }

    /// Fetch reply contexts for a set of message IDs
    private func fetchReplyContexts(for messageIds: [UUID]) async throws -> [UUID: ReplyContext] {
        guard !messageIds.isEmpty else { return [:] }
        
        let response = try await supabase
            .from("messages")
            .select("id, text, from_id, image_url, sender:profiles!messages_from_id_fkey(*)")
            .in("id", values: messageIds.map { $0.uuidString })
            .execute()

        struct ReplyRow: Codable {
            let id: UUID
            let text: String
            let fromId: UUID
            let imageUrl: String?
            let sender: Profile?
            
            enum CodingKeys: String, CodingKey {
                case id
                case text
                case fromId = "from_id"
                case imageUrl = "image_url"
                case sender
            }
        }
        
        let replyRows: [ReplyRow] = try DateDecoderFactory.makeSupabaseDecoder().decode([ReplyRow].self, from: response.data)
        var contexts: [UUID: ReplyContext] = [:]
        for row in replyRows {
            contexts[row.id] = ReplyContext(
                id: row.id,
                text: row.text,
                senderName: row.sender?.name ?? "Unknown",
                senderId: row.fromId,
                imageUrl: row.imageUrl
            )
        }
        
        return contexts
    }

    // MARK: - Send Messages
    
    /// Send a message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    ///   - text: The message text
    ///   - imageUrl: Optional image URL (if message includes an image)
    ///   - replyToId: Optional message ID being replied to
    /// - Returns: The created message
    /// - Throws: AppError if send fails
    func sendMessage(conversationId: UUID, fromId: UUID, text: String, imageUrl: String? = nil, replyToId: UUID? = nil) async throws -> Message {
        // Security check: Verify user is a participant (RLS is disabled on conversation_participants)
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: fromId.uuidString)
            .limit(1)
            .execute()
        
        let conversationCheck = try? await supabase
            .from("conversations")
            .select("created_by")
            .eq("id", value: conversationId.uuidString)
            .eq("created_by", value: fromId.uuidString)
            .limit(1)
            .execute()
        
        let hasParticipant = participantCheck?.data.isEmpty == false
        let isCreator = conversationCheck?.data.isEmpty == false
        let isParticipant = hasParticipant || isCreator
        
        guard isParticipant else {
            throw AppError.permissionDenied("You don't have permission to send messages in this conversation")
        }
        
        // Check rate limit (1 second between messages)
        let rateLimitKey = "send_message_\(fromId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: Constants.RateLimits.messageSend
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait before sending another message")
        }
        
        let newMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            replyToId: replyToId
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(*), reply_to_id")
            .single()
            .execute()
        
        // Decode message with joined sender profile
        let decoder = createDateDecoder()
        let message: Message
        do {
            message = try decoder.decode(Message.self, from: response.data)
        } catch {
            // Log the raw response for debugging
            if let jsonString = String(data: response.data, encoding: .utf8) {
                AppLogger.database.error("Failed to decode message. Raw JSON: \(jsonString.prefix(200))")
            }
            AppLogger.database.error("Decoding error: \(error)")
            throw error
        }
        
        // Update conversation updated_at
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Sent message: \(message.id)")
        return message
    }
    
    /// Send an audio message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender user ID
    ///   - audioUrl: The uploaded audio URL
    ///   - duration: Audio duration in seconds
    ///   - replyToId: Optional message ID being replied to
    /// - Returns: The created message
    func sendAudioMessage(conversationId: UUID, fromId: UUID, audioUrl: String, duration: Double, replyToId: UUID? = nil) async throws -> Message {
        let newMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: "",
            messageType: .audio,
            replyToId: replyToId,
            audioUrl: audioUrl,
            audioDuration: duration
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        let message = try decoder.decode(Message.self, from: response.data)
        
        // Update conversation timestamp
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Sent audio message: \(message.id)")
        return message
    }
    
    /// Send a location message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender user ID
    ///   - latitude: Location latitude
    ///   - longitude: Location longitude
    ///   - locationName: Human-readable location name/address
    ///   - replyToId: Optional message ID being replied to
    /// - Returns: The created message
    func sendLocationMessage(conversationId: UUID, fromId: UUID, latitude: Double, longitude: Double, locationName: String?, replyToId: UUID? = nil) async throws -> Message {
        let newMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: locationName ?? "Shared location",
            messageType: .location,
            replyToId: replyToId,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        let message = try decoder.decode(Message.self, from: response.data)
        
        // Update conversation timestamp
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Sent location message: \(message.id)")
        return message
    }
    
    // MARK: - Edit & Unsend Messages
    
    /// Update a message's text content (edit)
    /// - Parameters:
    ///   - messageId: The ID of the message to edit
    ///   - newContent: The new text content
    /// - Throws: AppError if the update fails
    func updateMessageContent(messageId: UUID, newContent: String) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        
        try await supabase
            .from("messages")
            .update([
                "text": newContent,
                "edited_at": now
            ])
            .eq("id", value: messageId.uuidString)
            .execute()
        
        AppLogger.database.info("Edited message: \(messageId)")
    }
    
    /// Unsend a message (soft delete — clears content and sets deleted_at)
    /// - Parameter messageId: The ID of the message to unsend
    /// - Throws: AppError if the update fails
    func unsendMessage(messageId: UUID) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        
        try await supabase
            .from("messages")
            .update([
                "text": "",
                "deleted_at": now
            ])
            .eq("id", value: messageId.uuidString)
            .execute()
        
        AppLogger.database.info("Unsent message: \(messageId)")
    }
    
    // MARK: - Read Status
    
    /// Mark messages as read
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID marking as read
    ///   - updateLastSeen: Whether to write `last_seen` immediately as part of this call
    /// - Throws: AppError if update fails
    func markAsRead(
        conversationId: UUID,
        userId: UUID,
        updateLastSeen: Bool = true
    ) async throws {
        // Get all unread messages
        let unreadResponse = try await supabase
            .from("messages")
            .select("id, read_by")
            .eq("conversation_id", value: conversationId.uuidString)
            .neq("from_id", value: userId.uuidString)
            .or(Self.unreadReadByFilter(userId: userId))
            .execute()
        
        let unreadMessages = try Self.decodeUnreadMessages(from: unreadResponse.data)
        
        if !unreadMessages.isEmpty {
            let messageIds = unreadMessages.map { $0.id.uuidString }
            do {
                try await supabase.rpc(
                    "mark_messages_read_batch",
                    params: [
                        "p_message_ids": AnyCodable(messageIds),
                        "p_user_id": AnyCodable(userId.uuidString)
                    ]
                ).execute()
            } catch {
                for message in unreadMessages {
                    var updatedReadBy = message.readBy
                    if !updatedReadBy.contains(userId) {
                        updatedReadBy.append(userId)
                    }
                    
                    try await supabase
                        .from("messages")
                        .update(["read_by": updatedReadBy.map { $0.uuidString }])
                        .eq("id", value: message.id.uuidString)
                        .execute()
                }
            }

        }
        
        // Optional last_seen write (can be throttled by caller to reduce write churn).
        if updateLastSeen {
            try? await self.updateLastSeen(conversationId: conversationId, userId: userId)
        }
        
        AppLogger.database.debug("Marked \(unreadMessages.count) messages as read for conversation \(conversationId)")
    }
    
    /// Update last_seen timestamp for a user in a conversation
    /// This is used to prevent push notifications when user is actively viewing
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID
    /// - Throws: AppError if update fails
    func updateLastSeen(conversationId: UUID, userId: UUID) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        
        try await supabase
            .from("conversation_participants")
            .update(["last_seen": now])
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        AppLogger.database.debug("Updated last_seen for user \(userId) in conversation \(conversationId)")
    }
    
    // MARK: - Reporting
    
    /// Submit a report for a user
    func reportUser(reporterId: UUID, reportedUserId: UUID, type: ReportType, description: String?) async throws {
        try await supabase.rpc(
            "submit_report",
            params: [
                "p_reporter_id": reporterId.uuidString,
                "p_reported_user_id": reportedUserId.uuidString,
                "p_report_type": type.rawValue,
                "p_description": description ?? ""
            ]
        ).execute()
        
        AppLogger.database.info("Reported user: \(reportedUserId)")
    }
    
    /// Submit a report for a message
    func reportMessage(reporterId: UUID, messageId: UUID, type: ReportType, description: String?) async throws {
        try await supabase.rpc(
            "submit_report",
            params: [
                "p_reporter_id": reporterId.uuidString,
                "p_reported_message_id": messageId.uuidString,
                "p_report_type": type.rawValue,
                "p_description": description ?? ""
            ]
        ).execute()
        
        AppLogger.database.info("Reported message: \(messageId)")
    }
    
    // MARK: - Blocking
    
    /// Block a user
    func blockUser(blockerId: UUID, blockedId: UUID, reason: String?) async throws {
        try await supabase.rpc(
            "block_user",
            params: [
                "p_blocker_id": blockerId.uuidString,
                "p_blocked_id": blockedId.uuidString,
                "p_reason": reason ?? ""
            ]
        ).execute()
        
        AppLogger.database.info("Blocked user: \(blockedId)")
    }
    
    /// Unblock a user
    func unblockUser(blockerId: UUID, blockedId: UUID) async throws {
        try await supabase.rpc(
            "unblock_user",
            params: [
                "p_blocker_id": blockerId.uuidString,
                "p_blocked_id": blockedId.uuidString
            ]
        ).execute()
        
        AppLogger.database.info("Unblocked user: \(blockedId)")
    }
    
    /// Check if a user is blocked
    func isUserBlocked(userId: UUID, otherUserId: UUID) async throws -> Bool {
        struct BlockedResult: Codable {
            let result: Bool
            
            enum CodingKeys: String, CodingKey {
                case result = "is_user_blocked"
            }
        }
        
        let response = try await supabase.rpc(
            "is_user_blocked",
            params: [
                "p_user_id": userId.uuidString,
                "p_other_user_id": otherUserId.uuidString
            ]
        ).execute()
        
        let decoder = JSONDecoder()
        if let result = try? decoder.decode(Bool.self, from: response.data) {
            return result
        }
        return false
    }
    
    /// Get list of blocked users
    func getBlockedUsers(userId: UUID) async throws -> [BlockedUser] {
        let response = try await supabase.rpc(
            "get_blocked_users",
            params: ["p_user_id": userId.uuidString]
        ).execute()
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([BlockedUser].self, from: response.data)
    }
    
    // MARK: - Search
    
    /// Search messages across all conversations the current user participates in
    /// - Parameters:
    ///   - query: The search text (case-insensitive contains)
    ///   - userId: The current user's ID (used to scope to their conversations)
    ///   - limit: Maximum number of results (default: 30)
    /// - Returns: Array of matching messages with sender profile joined
    /// - Throws: AppError if the search fails
    func searchMessages(query: String, userId: UUID, limit: Int = 30) async throws -> [Message] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        // 1. Get all conversation IDs the user participates in
        let participantsResponse = try await supabase
            .from("conversation_participants")
            .select("conversation_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let conversationId: UUID
            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
            }
        }
        
        let rows = try JSONDecoder().decode([ParticipantRow].self, from: participantsResponse.data)
        let conversationIds = rows.map { $0.conversationId.uuidString }
        
        guard !conversationIds.isEmpty else { return [] }
        
        // 2. Search messages in those conversations using ilike for case-insensitive match
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .in("conversation_id", values: conversationIds)
            .ilike("text", pattern: "%\(query)%")
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        
        let decoder = createDateDecoder()
        let messages = try decoder.decode([Message].self, from: response.data)
        return messages
    }
    
    /// Search messages within a specific conversation
    /// - Parameters:
    ///   - query: The search text (case-insensitive contains)
    ///   - conversationId: The conversation to search within
    ///   - limit: Maximum number of results (default: 50)
    ///   - before: Optional upper bound for created_at (exclusive) for loading older matches
    /// - Returns: Array of matching messages ordered oldest first
    /// - Throws: AppError if the search fails
    func searchMessagesInConversation(
        query: String,
        conversationId: UUID,
        limit: Int = 50,
        before: Date? = nil
    ) async throws -> [Message] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var queryBuilder = supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("conversation_id", value: conversationId.uuidString)
            .ilike("text", pattern: "%\(query)%")
            .is("deleted_at", value: nil)
        
        if let before {
            queryBuilder = queryBuilder.lt("created_at", value: createISO8601Formatter().string(from: before))
        }

        let response = try await queryBuilder
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()

        let decoder = createDateDecoder()
        let messages = try decoder.decode([Message].self, from: response.data)
        return messages
    }
    
    // MARK: - Typing Indicators
    
    /// Set typing status for current user in a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID
    func setTypingStatus(conversationId: UUID, userId: UUID) async {
        do {
            // Use upsert to update or insert typing indicator
            try await supabase
                .from("typing_indicators")
                .upsert([
                    "conversation_id": conversationId.uuidString,
                    "user_id": userId.uuidString,
                    "started_at": ISO8601DateFormatter().string(from: Date())
                ], onConflict: "conversation_id,user_id")
                .execute()
        } catch {
            // Typing indicator failures are non-critical, just log
            AppLogger.database.debug("Failed to set typing status: \(error.localizedDescription)")
        }
    }
    
    /// Clear typing status for current user in a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID
    func clearTypingStatus(conversationId: UUID, userId: UUID) async {
        do {
            try await supabase
                .from("typing_indicators")
                .delete()
                .eq("conversation_id", value: conversationId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            // Typing indicator failures are non-critical, just log
            AppLogger.database.debug("Failed to clear typing status: \(error.localizedDescription)")
        }
    }
    
    /// Fetch currently typing users in a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of typing users (excluding current user)
    func fetchTypingUsers(conversationId: UUID) async -> [TypingUser] {
        struct TypingUsersRPCRow: Codable {
            let userId: UUID
            let userName: String
            let avatarUrl: String?
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case userName = "user_name"
                case avatarUrl = "avatar_url"
            }
        }
        
        do {
            let response = try await supabase
                .rpc(
                    "get_typing_users",
                    params: ["p_conversation_id": AnyCodable(conversationId.uuidString)]
                )
                .execute()
            let rows = try createDateDecoder().decode([TypingUsersRPCRow].self, from: response.data)
            return rows.map { TypingUser(id: $0.userId, name: $0.userName, avatarUrl: $0.avatarUrl) }
        } catch {
            return await fetchTypingUsersFallback(conversationId: conversationId)
        }
    }

    private func fetchTypingUsersFallback(conversationId: UUID) async -> [TypingUser] {
        guard let currentUserId = AuthService.shared.currentUserId else { return [] }
        
        do {
            let response = try await supabase
                .from("typing_indicators")
                .select("user_id, started_at")
                .eq("conversation_id", value: conversationId.uuidString)
                .neq("user_id", value: currentUserId.uuidString)
                .gte("started_at", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-5)))
                .execute()
            
            struct TypingRow: Codable {
                let userId: UUID
                let startedAt: Date
                
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case startedAt = "started_at"
                }
            }
            
            let rows = try createDateDecoder().decode([TypingRow].self, from: response.data)
            
            guard !rows.isEmpty else { return [] }
            
            let userIds = rows.map { $0.userId.uuidString }
            let profilesResponse = try await supabase
                .from("profiles")
                .select("id, name, avatar_url")
                .in("id", values: userIds)
                .execute()
            
            struct ProfileData: Codable {
                let id: UUID
                let name: String
                let avatarUrl: String?
                
                enum CodingKeys: String, CodingKey {
                    case id, name
                    case avatarUrl = "avatar_url"
                }
            }
            
            let profiles = try JSONDecoder().decode([ProfileData].self, from: profilesResponse.data)
            return profiles.map { TypingUser(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) }
        } catch {
            return []
        }
    }
}

extension MessageService: MessageServiceProtocol {}
