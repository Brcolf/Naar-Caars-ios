//
//  MessageService.swift
//  NaarsCars
//
//  Service for message and conversation operations
//

import Foundation
import Supabase

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
    
    /// Fetch all conversations for a user
    /// - Parameter userId: The user ID
    /// - Returns: Array of conversations with details
    /// - Throws: AppError if fetch fails
    func fetchConversations(userId: UUID) async throws -> [ConversationWithDetails] {
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
                .select("id, created_by, ride_id, favor_id, created_at, updated_at")
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
            
            // Query conversations by IDs
            // PostgreSQL optimizes IN clauses efficiently with indexes on id
            // This scales well even with hundreds/thousands of conversations
            let conversationsResponse = try await supabase
                .from("conversations")
                .select("id, created_by, ride_id, favor_id, created_at, updated_at")
                .in("id", values: Array(allConversationIds).map { $0.uuidString })
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
                    lastMessage = try? JSONDecoder().decode(Message.self, from: lastMessageData)
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
                
                // Get other participants (excluding current user)
                _ = try? await supabase
                    .from("conversation_participants")
                    .select("user_id, profiles!conversation_participants_user_id_fkey(id, name, avatar_url)")
                    .eq("conversation_id", value: conversation.id.uuidString)
                    .neq("user_id", value: userId.uuidString)
                    .execute()
                
                // Parse other participants (simplified - would need proper join parsing)
                let otherParticipants: [Profile] = []
                // TODO: Parse joined profiles from response
                
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
        // Check for existing DM conversation (no ride_id or favor_id)
        // Query conversations directly - RLS will filter to user's conversations
        var existingConversations: [Conversation]? = nil
        do {
            let response = try await supabase
                .from("conversations")
                .select("id, created_by, ride_id, favor_id, created_at, updated_at")
                .is("ride_id", value: nil)
                .is("favor_id", value: nil)
                .execute()
            
            // Decode conversations with custom date decoder
            let decoder = createDateDecoder()
            existingConversations = try decoder.decode([Conversation].self, from: response.data)
        } catch {
            // Log the full error for debugging
            print("🔴 [MessageService] Error checking existing conversations: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            
            // If RLS recursion error, just proceed to create new conversation
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                print("⚠️ [MessageService] RLS recursion detected. Creating new one.")
                existingConversations = nil
            } else {
                // For other errors, still proceed - we'll create a new conversation
                print("⚠️ [MessageService] Non-recursion error. Creating new one.")
                existingConversations = nil
            }
        }
        
        // TODO: Filter to find conversation with both users as participants
        
        // If none exists, create new one
        let newConversation = Conversation(
            createdBy: userId
        )
        
        // Create conversation - handle RLS recursion errors
        let conversation: Conversation
        do {
            let response = try await supabase
                .from("conversations")
                .insert(newConversation)
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
        
        // Add both users as participants
        do {
            try await supabase
                .from("conversation_participants")
                .insert([
                    [
                        "conversation_id": AnyCodable(conversation.id.uuidString),
                        "user_id": AnyCodable(userId.uuidString)
                    ],
                    [
                        "conversation_id": AnyCodable(conversation.id.uuidString),
                        "user_id": AnyCodable(otherUserId.uuidString)
                    ]
                ])
                .execute()
            print("✅ [MessageService] Created conversation with participants")
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
    
    /// Create or get existing conversation for a ride or favor request
    /// - Parameters:
    ///   - rideId: Ride ID (if conversation is for a ride)
    ///   - favorId: Favor ID (if conversation is for a favor)
    ///   - createdBy: User ID creating the conversation
    /// - Returns: Conversation
    /// - Throws: AppError if operation fails
    func createOrGetRequestConversation(rideId: UUID? = nil, favorId: UUID? = nil, createdBy: UUID) async throws -> Conversation {
        // Validate: exactly one of rideId or favorId must be provided
        guard (rideId != nil) != (favorId != nil) else {
            throw AppError.invalidInput("Must provide either rideId or favorId, but not both")
        }
        
        // Check for existing conversation
        var query = supabase
            .from("conversations")
            .select("id, created_by, ride_id, favor_id, created_at, updated_at")
        
        if let rideId = rideId {
            query = query.eq("ride_id", value: rideId.uuidString)
        } else if let favorId = favorId {
            query = query.eq("favor_id", value: favorId.uuidString)
        }
        
        let existingResponse = try? await query.single().execute()
        
        if let existingData = existingResponse?.data {
            let decoder = createDateDecoder()
            let existing: Conversation = try decoder.decode(Conversation.self, from: existingData)
            print("✅ [MessageService] Found existing request conversation: \(existing.id)")
            return existing
        }
        
        // Create new conversation
        let newConversation = Conversation(
            rideId: rideId,
            favorId: favorId,
            createdBy: createdBy
        )
        
        let response = try await supabase
            .from("conversations")
            .insert(newConversation)
            .select()
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        let conversation = try decoder.decode(Conversation.self, from: response.data)
        
        // Add creator as participant (bypass permission check since they're the creator)
        do {
            try await supabase
                .from("conversation_participants")
                .insert([
                    "conversation_id": AnyCodable(conversation.id.uuidString),
                    "user_id": AnyCodable(createdBy.uuidString)
                ])
                .execute()
            print("✅ [MessageService] Added creator as participant")
        } catch {
            print("⚠️ [MessageService] Failed to add creator as participant: \(error.localizedDescription)")
            // Don't throw - conversation was created successfully
        }
        
        print("✅ [MessageService] Created new request conversation: \(conversation.id)")
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
        
        // Get conversation to check if it's linked to a request
        let conversationResponse = try await supabase
            .from("conversations")
            .select("id, ride_id, favor_id, created_by")
            .eq("id", value: conversationId.uuidString)
            .single()
            .execute()
        
        struct ConversationInfo: Codable {
            let id: UUID
            let rideId: UUID?
            let favorId: UUID?
            let createdBy: UUID
            enum CodingKeys: String, CodingKey {
                case id, createdBy = "created_by"
                case rideId = "ride_id", favorId = "favor_id"
            }
        }
        
        let conversationInfo = try JSONDecoder().decode(ConversationInfo.self, from: conversationResponse.data)
        
        // Check if addedBy has permission to add participants
        // They can add if:
        // 1. They are the conversation creator
        // 2. They are the request creator (if conversation is linked to a request)
        // 3. They are an existing participant (check in app code to avoid RLS recursion)
        var canAdd = false
        
        if conversationInfo.createdBy == addedBy {
            canAdd = true
        } else if let rideId = conversationInfo.rideId {
            let ride = try? await RideService.shared.fetchRide(id: rideId)
            if ride?.userId == addedBy {
                canAdd = true
            }
        } else if let favorId = conversationInfo.favorId {
            let favor = try? await FavorService.shared.fetchFavor(id: favorId)
            if favor?.userId == addedBy {
                canAdd = true
            }
        }
        
        // If not creator/request creator, check if they're a participant
        if !canAdd {
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
        
        // If conversation is linked to a request, add participants to the request
        // Only add if the person adding is the request creator (to avoid unauthorized additions)
        if let rideId = conversationInfo.rideId {
            // Check if addedBy is the ride creator
            let ride = try? await RideService.shared.fetchRide(id: rideId)
            if ride?.userId == addedBy {
                // Add participants to ride (this will also add them to conversation with announcement)
                // But we already added them above, so we need to avoid double-adding
                // Instead, just update the ride participants without triggering conversation update
                let inserts = newUserIds.map { userId in
                    [
                        "ride_id": AnyCodable(rideId.uuidString),
                        "user_id": AnyCodable(userId.uuidString),
                        "added_by": AnyCodable(addedBy.uuidString)
                    ]
                }
                
                do {
                    try await supabase
                        .from("ride_participants")
                        .insert(inserts)
                        .execute()
                    print("✅ [MessageService] Added participants to ride \(rideId)")
                } catch {
                    print("⚠️ [MessageService] Failed to add participant to ride: \(error.localizedDescription)")
                }
            }
        } else if let favorId = conversationInfo.favorId {
            // Check if addedBy is the favor creator
            let favor = try? await FavorService.shared.fetchFavor(id: favorId)
            if favor?.userId == addedBy {
                // Add participants to favor
                let inserts = newUserIds.map { userId in
                    [
                        "favor_id": AnyCodable(favorId.uuidString),
                        "user_id": AnyCodable(userId.uuidString),
                        "added_by": AnyCodable(addedBy.uuidString)
                    ]
                }
                
                do {
                    try await supabase
                        .from("favor_participants")
                        .insert(inserts)
                        .execute()
                    print("✅ [MessageService] Added participants to favor \(favorId)")
                } catch {
                    print("⚠️ [MessageService] Failed to add participant to favor: \(error.localizedDescription)")
                }
            }
        }
        
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
    
    /// Find existing conversation for a request
    /// - Parameters:
    ///   - rideId: Ride ID (if looking for ride conversation)
    ///   - favorId: Favor ID (if looking for favor conversation)
    /// - Returns: Conversation if found, nil otherwise
    func findExistingRequestConversation(rideId: UUID? = nil, favorId: UUID? = nil) async throws -> Conversation? {
        guard (rideId != nil) != (favorId != nil) else {
            return nil
        }
        
        var query = supabase
            .from("conversations")
            .select("id, created_by, ride_id, favor_id, created_at, updated_at")
        
        if let rideId = rideId {
            query = query.eq("ride_id", value: rideId.uuidString)
        } else if let favorId = favorId {
            query = query.eq("favor_id", value: favorId.uuidString)
        }
        
        let response = try? await query.single().execute()
        
        guard let data = response?.data else {
            return nil
        }
        
        let decoder = createDateDecoder()
        return try? decoder.decode(Conversation.self, from: data)
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
    /// Fetch messages for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of messages ordered by creation date
    /// - Throws: AppError if fetch fails or user is not a participant
    func fetchMessages(conversationId: UUID) async throws -> [Message] {
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
        
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
            .eq("conversation_id", value: conversationId.uuidString)
            .order("created_at", ascending: true)
            .execute()
        
        let decoder = createDateDecoder()
        let messages: [Message] = try decoder.decode([Message].self, from: response.data)
        
        // Cache results
        await cacheManager.cacheMessages(conversationId: conversationId, messages)
        
        print("✅ [MessageService] Fetched \(messages.count) messages from network.")
        return messages
    }
    
    /// Send a message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    ///   - text: The message text
    /// - Returns: The created message
    /// - Throws: AppError if send fails
    func sendMessage(conversationId: UUID, fromId: UUID, text: String) async throws -> Message {
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
            text: text
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
}



