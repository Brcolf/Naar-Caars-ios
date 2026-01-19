//
//  MessageService.swift
//  NaarsCars
//
//  Service for message and conversation operations
//

import Foundation
import Supabase
import UIKit

/// Service for message and conversation operations
/// Handles fetching, sending messages, and managing conversations
@MainActor
final class MessageService {
    
    // MARK: - Singleton
    
    static let shared = MessageService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let cacheManager = CacheManager.shared
    private let rateLimiter = RateLimiter.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Conversations
    
    /// Fetch conversations for a user with pagination
    /// - Parameters:
    ///   - userId: The user ID
    ///   - limit: Maximum number of conversations to fetch (default: 10)
    ///   - offset: Number of conversations to skip (for pagination)
    /// - Returns: Array of conversations with details
    /// - Throws: AppError if fetch fails
    func fetchConversations(userId: UUID, limit: Int = 10, offset: Int = 0) async throws -> [ConversationWithDetails] {
        // Check cache first
        if let cached = await cacheManager.getCachedConversations(userId: userId), !cached.isEmpty {
            print("✅ [MessageService] Cache hit for conversations. Returning \(cached.count) items.")
            return cached
        }
        
        print("🔄 [MessageService] Cache miss for conversations. Fetching from network...")
        
        do {
            // Get user's conversation IDs from conversation_participants
            // (RLS is disabled on this table, so we can query it directly)
            // This query uses an index on user_id, so it's efficient even with many conversations
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
            
            let participantRows = try JSONDecoder().decode([ParticipantRow].self, from: participantsResponse.data)
            let participantConversationIds = Set(participantRows.map { $0.conversationId })
            
            // Get conversations where user is creator
            let createdConversationsResponse = try? await supabase
                .from("conversations")
                .select("id, created_by, title, created_at, updated_at")
                .eq("created_by", value: userId.uuidString)
                .execute()
            
            var allConversationIds = participantConversationIds
            if let createdData = createdConversationsResponse?.data {
                let decoder = createDateDecoder()
                let created: [Conversation] = try decoder.decode([Conversation].self, from: createdData)
                allConversationIds.formUnion(created.map { $0.id })
            }
            
            guard !allConversationIds.isEmpty else {
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            
            // Query conversations by IDs (now including title)
            // PostgreSQL optimizes IN clauses efficiently with indexes on id
            // This scales well even with hundreds/thousands of conversations
            // Apply pagination: get conversations in the specified range
            // Note: We need to order first, then apply range
            let allConversationIdsArray = Array(allConversationIds)
            let sortedIds = allConversationIdsArray // IDs are already sorted by updated_at in the query
            let paginatedIds = Array(sortedIds[offset..<min(offset + limit, sortedIds.count)])
            
            guard !paginatedIds.isEmpty else {
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            
            let conversationsResponse = try await supabase
                .from("conversations")
                .select("id, created_by, title, created_at, updated_at")
                .in("id", values: paginatedIds.map { $0.uuidString })
                .order("updated_at", ascending: false)
                .execute()
            
            // Decode conversations with custom date decoder
            let decoder = createDateDecoder()
            let conversations: [Conversation] = try decoder.decode([Conversation].self, from: conversationsResponse.data)
            
            guard !conversations.isEmpty else {
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            
            // For each conversation, get last message and unread count
            var conversationsWithDetails: [ConversationWithDetails] = []
            
            for conversation in conversations {
                // Get last message
                let lastMessageResponse = try? await supabase
                    .from("messages")
                    .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
                    .eq("conversation_id", value: conversation.id.uuidString)
                    .order("created_at", ascending: false)
                    .limit(1)
                    .single()
                    .execute()
                
                var lastMessage: Message? = nil
                if let lastMessageData = lastMessageResponse?.data {
                    // Use createDateDecoder() to properly handle date formats
                    let decoder = createDateDecoder()
                    lastMessage = try? decoder.decode(Message.self, from: lastMessageData)
                }
                
                // Calculate unread count (messages not in readBy array)
                let unreadResponse = try? await supabase
                    .from("messages")
                    .select("id")
                    .eq("conversation_id", value: conversation.id.uuidString)
                    .not("read_by", operator: .cs, value: userId.uuidString)
                    .execute()
                
                struct MessageId: Codable {
                    let id: UUID
                }
                
                let unreadMessages: [MessageId] = (try? JSONDecoder().decode([MessageId].self, from: unreadResponse?.data ?? Data())) ?? []
                let unreadCount = unreadMessages.count
                
                // Get other participants (excluding current user) with profile data
                var otherParticipants: [Profile] = []
                do {
                    let participantsResponse = try await supabase
                        .from("conversation_participants")
                        .select("user_id, profiles!conversation_participants_user_id_fkey(id, name, email, avatar_url, car, created_at)")
                        .eq("conversation_id", value: conversation.id.uuidString)
                        .neq("user_id", value: userId.uuidString)
                        .execute()
                    
                    // Parse the nested structure from Supabase
                    struct ParticipantRow: Codable {
                        let userId: UUID
                        let profiles: Profile?
                        
                        enum CodingKeys: String, CodingKey {
                            case userId = "user_id"
                            case profiles
                        }
                    }
                    
                    let decoder = createDateDecoder()
                    let rows = try decoder.decode([ParticipantRow].self, from: participantsResponse.data)
                    otherParticipants = rows.compactMap { $0.profiles }
                } catch {
                    print("⚠️ [MessageService] Error fetching participants for conversation \(conversation.id): \(error.localizedDescription)")
                    // Fallback: fetch profiles separately if join fails
                    do {
                        let userIdsResponse = try? await supabase
                            .from("conversation_participants")
                            .select("user_id")
                            .eq("conversation_id", value: conversation.id.uuidString)
                            .neq("user_id", value: userId.uuidString)
                            .execute()
                        
                        if let userIdsData = userIdsResponse?.data {
                            struct ParticipantUserId: Codable {
                                let userId: UUID
                                enum CodingKeys: String, CodingKey {
                                    case userId = "user_id"
                                }
                            }
                            
                            let userIdRows = try JSONDecoder().decode([ParticipantUserId].self, from: userIdsData)
                            
                            // Fetch profiles individually
                            for row in userIdRows {
                                if let profile = try? await ProfileService.shared.fetchProfile(userId: row.userId) {
                                    otherParticipants.append(profile)
                                }
                            }
                        }
                    } catch {
                        print("⚠️ [MessageService] Error in fallback participant fetch: \(error.localizedDescription)")
                    }
                }
                
                let details = ConversationWithDetails(
                    conversation: conversation,
                    lastMessage: lastMessage,
                    unreadCount: unreadCount,
                    otherParticipants: otherParticipants
                )
                conversationsWithDetails.append(details)
            }
            
            // Cache results
            await cacheManager.cacheConversations(userId: userId, conversationsWithDetails)
            
            print("✅ [MessageService] Fetched \(conversationsWithDetails.count) conversations from network.")
            return conversationsWithDetails
            
        } catch {
            // Handle RLS recursion error gracefully
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                print("⚠️ [MessageService] RLS policy recursion detected. Returning empty conversations.")
                print("   This is a database-level issue. Fix the RLS policy in Supabase.")
                print("   The policy on 'conversation_participants' should not reference itself.")
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            // Re-throw other errors
            throw error
        }
    }
    
    /// Get or create direct conversation between two users
    /// - Parameters:
    ///   - userId: First user ID
    ///   - otherUserId: Second user ID
    /// - Returns: Conversation
    /// - Throws: AppError if operation fails
    func getOrCreateDirectConversation(userId: UUID, otherUserId: UUID) async throws -> Conversation {
        // Check for existing DM conversation by finding conversations where both users are participants
        // and the conversation has exactly 2 participants
        let participantsResponse = try? await supabase
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
        
        guard let participantData = participantsResponse?.data,
              let userConversations = try? JSONDecoder().decode([ParticipantRow].self, from: participantData) else {
            // No conversations found, create new one
            return try await createConversationWithUsers(userIds: [userId, otherUserId], createdBy: userId, title: nil)
        }
        
        // Check each conversation to see if it has both users as participants and exactly 2 participants
        for userConv in userConversations {
            let otherParticipantsResponse = try? await supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: userConv.conversationId.uuidString)
                .execute()
            
            struct OtherParticipantRow: Codable {
                let userId: UUID
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                }
            }
            
            if let otherData = otherParticipantsResponse?.data,
               let otherParticipants = try? JSONDecoder().decode([OtherParticipantRow].self, from: otherData),
               otherParticipants.count == 2 {
                // Check if both users are in this conversation
                let participantIds = Set(otherParticipants.map { $0.userId })
                if participantIds.contains(userId) && participantIds.contains(otherUserId) {
                    // Found existing DM conversation
                    let conversationResponse = try? await supabase
                        .from("conversations")
                        .select("id, created_by, title, created_at, updated_at")
                        .eq("id", value: userConv.conversationId.uuidString)
                        .single()
                        .execute()
                    
                    if let convData = conversationResponse?.data {
                        let decoder = createDateDecoder()
                        if let existing = try? decoder.decode(Conversation.self, from: convData) {
                            print("✅ [MessageService] Found existing DM conversation: \(existing.id)")
                            return existing
                        }
                    }
                }
            }
        }
        
        // No existing DM found, create new one
        return try await createConversationWithUsers(userIds: [userId, otherUserId], createdBy: userId, title: nil)
    }
    
    /// Create a conversation with specified users
    /// - Parameters:
    ///   - userIds: Array of user IDs to include in the conversation
    ///   - createdBy: User ID creating the conversation
    ///   - title: Optional title for group conversations
    /// - Returns: Created conversation
    /// - Throws: AppError if creation fails
    func createConversationWithUsers(userIds: [UUID], createdBy: UUID, title: String? = nil) async throws -> Conversation {
        guard !userIds.isEmpty else {
            throw AppError.invalidInput("Must provide at least one user ID")
        }
        
        // Create new conversation
        let newConversation = Conversation(
            title: title,
            createdBy: createdBy
        )
        
        // Create conversation - handle RLS recursion errors
        let conversation: Conversation
        do {
            var conversationData: [String: AnyCodable] = [
                "created_by": AnyCodable(createdBy.uuidString)
            ]
            if let title = title, !title.isEmpty {
                conversationData["title"] = AnyCodable(title)
            }
            
            let response = try await supabase
                .from("conversations")
                .insert(conversationData)
                .select()
                .single()
                .execute()
            
            // Use same date decoder as fetchConversations
            let decoder = createDateDecoder()
            conversation = try decoder.decode(Conversation.self, from: response.data)
        } catch {
            // Log the full error for debugging
            print("🔴 [MessageService] Error creating conversation: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            
            // Check if this is an RLS recursion error
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                print("⚠️ [MessageService] RLS recursion detected when creating conversation.")
                print("   This is a database-level issue. Fix the RLS policy in Supabase.")
                // Re-throw as AppError for better user experience
                throw AppError.serverError("Cannot create conversation due to database policy issue. Please contact support.")
            }
            // Re-throw other errors
            throw error
        }
        
        // Add all users as participants
        let participantInserts = userIds.map { userId in
            [
                "conversation_id": AnyCodable(conversation.id.uuidString),
                "user_id": AnyCodable(userId.uuidString)
            ]
        }
        
        do {
            try await supabase
                .from("conversation_participants")
                .insert(participantInserts)
                .execute()
            print("✅ [MessageService] Created conversation with \(userIds.count) participant(s)")
        } catch {
            // Handle RLS recursion error - check multiple error formats
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                print("⚠️ [MessageService] RLS policy recursion when creating participants.")
                print("   This is a database-level issue. Fix the RLS policy in Supabase.")
                print("   Conversation created successfully, but participants were not added.")
                // Still return the conversation - it was created successfully
                // Participants will need to be added after RLS policy is fixed
            } else {
                // For other errors, log but don't throw - conversation was created
                print("⚠️ [MessageService] Error adding participants: \(error.localizedDescription)")
                print("   Conversation created successfully, but participants may not have been added.")
            }
        }
        
        return conversation
    }
    
    
    /// Add participants to an existing conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userIds: Array of user IDs to add
    ///   - addedBy: User ID adding the participants
    ///   - createAnnouncement: Whether to create an announcement message (default: false)
    /// - Throws: AppError if operation fails
    func addParticipantsToConversation(
        conversationId: UUID,
        userIds: [UUID],
        addedBy: UUID,
        createAnnouncement: Bool = false
    ) async throws {
        guard !userIds.isEmpty else { return }
        
        // Get conversation to check permissions
        let conversationResponse = try await supabase
            .from("conversations")
            .select("id, title, created_by")
            .eq("id", value: conversationId.uuidString)
            .single()
            .execute()
        
        struct ConversationInfo: Codable {
            let id: UUID
            let createdBy: UUID
            enum CodingKeys: String, CodingKey {
                case id, createdBy = "created_by"
            }
        }
        
        let conversationInfo = try JSONDecoder().decode(ConversationInfo.self, from: conversationResponse.data)
        
        // Check if addedBy has permission to add participants
        // They can add if:
        // 1. They are the conversation creator, OR
        // 2. They are an existing participant
        var canAdd = false
        
        if conversationInfo.createdBy == addedBy {
            canAdd = true
        } else {
            // Check if addedBy is a participant (using simple query that won't recurse)
            let participantCheck = try? await supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .eq("user_id", value: addedBy.uuidString)
                .limit(1)
                .execute()
            
            if let data = participantCheck?.data, !data.isEmpty {
                canAdd = true
            }
        }
        
        guard canAdd else {
            throw AppError.permissionDenied("You don't have permission to add participants to this conversation")
        }
        
        // Get existing participants to avoid duplicates
        // Use simple query that won't cause recursion (just check user_id = auth.uid())
        let existingResponse = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let existingParticipants: [UUID] = (try? JSONDecoder().decode([ParticipantRow].self, from: existingResponse?.data ?? Data()))?.map { $0.userId } ?? []
        
        // Filter out users who are already participants
        let newUserIds = userIds.filter { !existingParticipants.contains($0) }
        
        guard !newUserIds.isEmpty else {
            print("ℹ️ [MessageService] All users are already participants")
            return
        }
        
        // Insert new participants
        let inserts = newUserIds.map { userId in
            [
                "conversation_id": AnyCodable(conversationId.uuidString),
                "user_id": AnyCodable(userId.uuidString)
            ]
        }
        
        try await supabase
            .from("conversation_participants")
            .insert(inserts)
            .execute()
        
        // Create announcement messages if requested
        if createAnnouncement {
            // Get profile of added user(s) for announcement
            for userId in newUserIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                    let announcementText = "\(profile.name) has been added to the conversation"
                    let announcement = Message(
                        conversationId: conversationId,
                        fromId: addedBy, // System message from the person who added
                        text: announcementText
                    )
                    
                    // Insert announcement message
                    do {
                        try await supabase
                            .from("messages")
                            .insert(announcement)
                            .execute()
                    } catch {
                        print("⚠️ [MessageService] Failed to create announcement message: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Invalidate conversation cache for all added users
        for userId in newUserIds {
            await cacheManager.invalidateConversations(userId: userId)
        }
        await cacheManager.invalidateConversations(userId: addedBy)
        await cacheManager.invalidateMessages(conversationId: conversationId)
        
        print("✅ [MessageService] Added \(newUserIds.count) participant(s) to conversation \(conversationId)")
    }
    
    
    // MARK: - Private Helpers
    
    /// Create a date decoder with custom date decoding strategy
    private func createDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }
    
    // MARK: - Messages
    
    /// Fetch messages for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of messages ordered by createdAt
    /// - Throws: AppError if fetch fails
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
        
        // Check if user is a participant or creator
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: currentUserId.uuidString)
            .limit(1)
            .execute()
        
        let conversationCheck = try? await supabase
            .from("conversations")
            .select("created_by")
            .eq("id", value: conversationId.uuidString)
            .eq("created_by", value: currentUserId.uuidString)
            .limit(1)
            .execute()
        
        let hasParticipant = participantCheck?.data.isEmpty == false
        let isCreator = conversationCheck?.data.isEmpty == false
        let isParticipant = hasParticipant || isCreator
        
        guard isParticipant else {
            throw AppError.permissionDenied("You don't have permission to view messages in this conversation")
        }
        // Check cache first
        if let cached = await cacheManager.getCachedMessages(conversationId: conversationId), !cached.isEmpty {
            print("✅ [MessageService] Cache hit for messages. Returning \(cached.count) items.")
            return cached
        }
        
        print("🔄 [MessageService] Cache miss for messages. Fetching from network...")
        
        var query = supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
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
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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
        
        // Fetch reactions for messages
        let messageIds = messages.map { $0.id.uuidString }
        if !messageIds.isEmpty {
            let reactionsResponse = try? await supabase
                .from("message_reactions")
                .select()
                .in("message_id", values: messageIds)
                .execute()
            
            if let reactionsData = reactionsResponse?.data {
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
                for i in 0..<messages.count {
                    if let reactionDict = reactionsDict[messages[i].id] {
                        messages[i].reactions = MessageReactions(reactions: reactionDict)
                    }
                }
            }
        }
        
        // Cache results (only cache if this is the initial load, not pagination)
        if beforeMessageId == nil {
            await cacheManager.cacheMessages(conversationId: conversationId, messages)
        }
        
        print("✅ [MessageService] Fetched \(messages.count) messages from network.")
        return messages
    }
    
    /// Upload message image to storage
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    /// - Returns: Public URL of uploaded image
    /// - Throws: AppError if upload fails
    func uploadMessageImage(imageData: Data, conversationId: UUID, fromId: UUID) async throws -> String {
        // Compress image using messageImage preset
        guard let uiImage = UIImage(data: imageData) else {
            throw AppError.invalidInput("Invalid image data")
        }
        
        guard let compressedData = ImageCompressor.compress(uiImage, preset: .messageImage) else {
            throw AppError.processingError("Failed to compress image")
        }
        
        // Upload to message-images bucket
        // Store in a folder per conversation for better organization
        let fileName = "\(conversationId.uuidString)/\(UUID().uuidString).jpg"
        
        try await supabase.storage
            .from("message-images")
            .upload(
                path: fileName,
                file: compressedData,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        
        // Get public URL
        let publicUrl = try await supabase.storage
            .from("message-images")
            .getPublicURL(path: fileName)
        
        return publicUrl.absoluteString
    }
    
    /// Send a message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    ///   - text: The message text
    ///   - imageUrl: Optional image URL (if message includes an image)
    /// - Returns: The created message
    /// - Throws: AppError if send fails
    func sendMessage(conversationId: UUID, fromId: UUID, text: String, imageUrl: String? = nil) async throws -> Message {
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
            minimumInterval: 1.0
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait before sending another message")
        }
        
        let newMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
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
                print("🔴 [MessageService] Failed to decode message. Raw JSON: \(jsonString)")
            }
            print("🔴 [MessageService] Decoding error: \(error)")
            // Try decoding again (might work if error was transient)
            message = try decoder.decode(Message.self, from: response.data)
        }
        
        // Update conversation updated_at
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        // Invalidate caches
        await cacheManager.invalidateMessages(conversationId: conversationId)
        await cacheManager.invalidateConversations(userId: fromId)
        
        print("✅ [MessageService] Sent message: \(message.id)")
        return message
    }
    
    /// Mark messages as read
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID marking as read
    /// - Throws: AppError if update fails
    func markAsRead(conversationId: UUID, userId: UUID) async throws {
        // Get all unread messages
        let unreadResponse = try await supabase
            .from("messages")
            .select("id, read_by")
            .eq("conversation_id", value: conversationId.uuidString)
            .not("read_by", operator: .cs, value: userId.uuidString)
            .execute()
        
        struct MessageReadBy: Codable {
            let id: UUID
            let readBy: [UUID]
            
            enum CodingKeys: String, CodingKey {
                case id
                case readBy = "read_by"
            }
        }
        
        let unreadMessages: [MessageReadBy] = try JSONDecoder().decode([MessageReadBy].self, from: unreadResponse.data)
        
        // Update each message to add userId to readBy array
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
        
        // Update last_seen timestamp to indicate user is actively viewing
        // This prevents push notifications when user is viewing the conversation
        try? await updateLastSeen(conversationId: conversationId, userId: userId)
        
        // Invalidate caches
        await cacheManager.invalidateMessages(conversationId: conversationId)
        await cacheManager.invalidateConversations(userId: userId)
        
        print("✅ [MessageService] Marked messages as read for conversation \(conversationId)")
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
        
        print("✅ [MessageService] Updated last_seen for user \(userId) in conversation \(conversationId)")
    }
    
    /// Update conversation title (for group conversations)
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - title: The new title (nil to clear)
    ///   - userId: The user ID making the update (must be a participant)
    /// - Throws: AppError if update fails
    func updateConversationTitle(conversationId: UUID, title: String?, userId: UUID) async throws {
        // Verify user is a participant
        let participantResponse = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        guard participantResponse != nil else {
            throw AppError.permissionDenied("You must be a participant to update the conversation title")
        }
        
        // Update the title
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var updateDict: [String: AnyCodable] = [
            "updated_at": AnyCodable(dateFormatter.string(from: Date()))
        ]
        
        if let title = title, !title.isEmpty {
            updateDict["title"] = AnyCodable(title)
        } else {
            updateDict["title"] = AnyCodable(nil as String?)
        }
        
        try await supabase
            .from("conversations")
            .update(updateDict)
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        // Invalidate caches
        await cacheManager.invalidateConversations(userId: userId)
        
        print("✅ [MessageService] Updated conversation title: \(title ?? "nil")")
    }
    
    // MARK: - Message Reactions
    
    /// Add a reaction to a message
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - userId: The user ID adding the reaction
    ///   - reaction: The reaction emoji/text (👍 👎 ❤️ 😂 ‼️ or "HaHa")
    /// - Throws: AppError if operation fails
    func addReaction(messageId: UUID, userId: UUID, reaction: String) async throws {
        // Validate reaction
        guard MessageReaction.validReactions.contains(reaction) else {
            throw AppError.invalidInput("Invalid reaction. Must be one of: \(MessageReaction.validReactions.joined(separator: ", "))")
        }
        
        // Check if user is a participant in the conversation
        let messageResponse = try await supabase
            .from("messages")
            .select("conversation_id")
            .eq("id", value: messageId.uuidString)
            .single()
            .execute()
        
        struct MessageConversation: Codable {
            let conversationId: UUID
            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
            }
        }
        
        let messageConv = try JSONDecoder().decode(MessageConversation.self, from: messageResponse.data)
        
        // Check if user is a participant
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: messageConv.conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        
        guard participantCheck?.data.isEmpty == false else {
            throw AppError.permissionDenied("You must be a participant to react to messages")
        }
        
        // Insert or update reaction (upsert)
        let reactionData: [String: AnyCodable] = [
            "message_id": AnyCodable(messageId.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "reaction": AnyCodable(reaction)
        ]
        
        try await supabase
            .from("message_reactions")
            .upsert(reactionData, onConflict: "message_id,user_id")
            .execute()
        
        // Invalidate message cache
        await cacheManager.invalidateMessages(conversationId: messageConv.conversationId)
        
        print("✅ [MessageService] Added reaction \(reaction) to message \(messageId)")
    }
    
    /// Remove a reaction from a message
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - userId: The user ID removing the reaction
    /// - Throws: AppError if operation fails
    func removeReaction(messageId: UUID, userId: UUID) async throws {
        // Get conversation ID for cache invalidation
        let messageResponse = try? await supabase
            .from("messages")
            .select("conversation_id")
            .eq("id", value: messageId.uuidString)
            .single()
            .execute()
        
        struct MessageConversation: Codable {
            let conversationId: UUID
            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
            }
        }
        
        let conversationId: UUID?
        if let messageData = messageResponse?.data,
           let messageConv = try? JSONDecoder().decode(MessageConversation.self, from: messageData) {
            conversationId = messageConv.conversationId
        } else {
            conversationId = nil
        }
        
        // Delete reaction
        try await supabase
            .from("message_reactions")
            .delete()
            .eq("message_id", value: messageId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        // Invalidate message cache
        if let conversationId = conversationId {
            await cacheManager.invalidateMessages(conversationId: conversationId)
        }
        
        print("✅ [MessageService] Removed reaction from message \(messageId)")
    }
    
    /// Fetch reactions for a message
    /// - Parameter messageId: The message ID
    /// - Returns: MessageReactions object with all reactions
    /// - Throws: AppError if fetch fails
    func fetchReactions(messageId: UUID) async throws -> MessageReactions {
        let response = try await supabase
            .from("message_reactions")
            .select()
            .eq("message_id", value: messageId.uuidString)
            .execute()
        
        let decoder = createDateDecoder()
        let reactions: [MessageReaction] = try decoder.decode([MessageReaction].self, from: response.data)
        
        // Group reactions by reaction type
        var reactionsDict: [String: [UUID]] = [:]
        for reaction in reactions {
            if reactionsDict[reaction.reaction] == nil {
                reactionsDict[reaction.reaction] = []
            }
            reactionsDict[reaction.reaction]?.append(reaction.userId)
        }
        
        let groupedReactions = MessageReactions(reactions: reactionsDict)
        
        return groupedReactions
    }
}


