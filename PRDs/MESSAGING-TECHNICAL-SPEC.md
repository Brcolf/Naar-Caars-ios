# Naar's Cars Messaging: Complete Technical Specification

## Document Information
- **Feature**: iMessage-Style Messaging System
- **Version**: 2.0 (Enhanced)
- **Date**: January 2025
- **Status**: Technical Specification
- **Supersedes**: `prd-messaging.md` (extends, does not replace)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Database Schema](#2-database-schema)
3. [API Layer](#3-api-layer)
4. [Real-Time System](#4-real-time-system)
5. [State Management](#5-state-management)
6. [UI/UX Specifications](#6-uiux-specifications)
7. [Feature Specifications](#7-feature-specifications)
8. [Push Notifications](#8-push-notifications)
9. [Image Handling](#9-image-handling)
10. [Edge Cases & Error Handling](#10-edge-cases--error-handling)
11. [Performance Requirements](#11-performance-requirements)
12. [Implementation Phases](#12-implementation-phases)

---

# 1. Architecture Overview

## 1.1 System Components

```
┌─────────────────────────────────────────────────────────────┐
│                     iOS App (SwiftUI)                        │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Conversation │  │  Message     │  │   Image      │      │
│  │    Views     │  │   Views      │  │   Picker     │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                  │                  │               │
│  ┌──────▼──────────────────▼──────────────────▼───────┐     │
│  │            ViewModels (State Management)            │     │
│  └──────┬──────────────────┬──────────────────┬───────┘     │
│         │                  │                  │               │
│  ┌──────▼───────┐  ┌──────▼───────┐  ┌──────▼───────┐      │
│  │  Message     │  │  Realtime    │  │   Storage    │      │
│  │  Service     │  │  Manager     │  │   Service    │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
└─────────┼──────────────────┼──────────────────┼──────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                    Supabase Backend                          │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │PostgreSQL│  │ Realtime │  │  Storage │  │   APNs   │   │
│  │  Tables  │  │ Channels │  │  Bucket  │  │  Bridge  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 1.2 Data Flow Patterns

### Pattern 1: Send Message
```
User types message
    ↓
ViewModel validates & creates optimistic UI
    ↓
MessageService.send()
    ↓
Supabase INSERT (authenticated user)
    ↓
Database trigger fires
    ↓
Realtime broadcast to all participants
    ↓
All devices receive via RealtimeManager
    ↓
ViewModels update & UI refreshes
```

### Pattern 2: Receive Message
```
Supabase Realtime event
    ↓
RealtimeManager receives broadcast
    ↓
Filters by active subscriptions
    ↓
Calls registered callback
    ↓
ViewModel handles on @MainActor
    ↓
Updates @Published properties
    ↓
SwiftUI re-renders affected views
```

---

# 2. Database Schema

## 2.1 Conversations Table

```sql
CREATE TABLE conversations (
    -- Identity
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Metadata
    title TEXT,                          -- Custom name (null for 1:1 chats)
    created_by UUID NOT NULL             -- Creator user ID
        REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Context (what spawned this conversation)
    ride_id UUID REFERENCES rides(id) ON DELETE SET NULL,
    favor_id UUID REFERENCES favors(id) ON DELETE SET NULL,
    
    -- Type
    conversation_type TEXT NOT NULL      -- 'direct', 'group', 'request'
        CHECK (conversation_type IN ('direct', 'group', 'request')),
    
    -- State
    is_archived BOOLEAN DEFAULT FALSE,
    last_message_at TIMESTAMPTZ,
    
    -- Metadata for search/display
    last_message_preview TEXT,           -- First 100 chars of last message
    
    -- Indexes
    INDEX idx_conversations_updated (updated_at DESC),
    INDEX idx_conversations_ride (ride_id),
    INDEX idx_conversations_favor (favor_id),
    INDEX idx_conversations_type (conversation_type)
);

-- Trigger to update updated_at
CREATE TRIGGER update_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

## 2.2 Conversation Participants Table

```sql
CREATE TABLE conversation_participants (
    -- Composite primary key
    conversation_id UUID NOT NULL 
        REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL 
        REFERENCES profiles(id) ON DELETE CASCADE,
    
    PRIMARY KEY (conversation_id, user_id),
    
    -- Participant metadata
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by UUID REFERENCES profiles(id),  -- Who added this person
    left_at TIMESTAMPTZ,                    -- NULL if still active
    
    -- Permissions
    role TEXT DEFAULT 'member'              -- 'creator', 'admin', 'member'
        CHECK (role IN ('creator', 'admin', 'member')),
    can_add_members BOOLEAN DEFAULT FALSE,
    can_remove_members BOOLEAN DEFAULT FALSE,
    can_rename BOOLEAN DEFAULT FALSE,
    
    -- Read tracking
    last_read_message_id UUID REFERENCES messages(id),
    last_read_at TIMESTAMPTZ,
    unread_count INTEGER DEFAULT 0,
    
    -- Notifications
    notifications_enabled BOOLEAN DEFAULT TRUE,
    is_muted BOOLEAN DEFAULT FALSE,
    muted_until TIMESTAMPTZ,
    
    -- Indexes
    INDEX idx_conv_participants_user (user_id),
    INDEX idx_conv_participants_conv (conversation_id),
    INDEX idx_conv_participants_active (conversation_id, left_at) 
        WHERE left_at IS NULL
);
```

## 2.3 Messages Table

```sql
CREATE TABLE messages (
    -- Identity
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL 
        REFERENCES conversations(id) ON DELETE CASCADE,
    
    -- Sender
    from_user_id UUID NOT NULL 
        REFERENCES profiles(id) ON DELETE CASCADE,
    
    -- Content
    content_type TEXT NOT NULL              -- 'text', 'image', 'system'
        CHECK (content_type IN ('text', 'image', 'system')),
    text_content TEXT,                      -- For text messages
    image_url TEXT,                         -- For image messages (Storage path)
    image_thumbnail_url TEXT,               -- Thumbnail version
    
    -- System message metadata
    system_event_type TEXT,                 -- 'user_added', 'user_removed', 'renamed', etc.
    system_event_data JSONB,                -- Event-specific data
    
    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,                 -- For edits (future)
    is_deleted BOOLEAN DEFAULT FALSE,       -- Soft delete
    
    -- Reply threading (future enhancement)
    reply_to_message_id UUID REFERENCES messages(id),
    
    -- Indexes
    INDEX idx_messages_conversation (conversation_id, created_at DESC),
    INDEX idx_messages_sender (from_user_id),
    INDEX idx_messages_created (created_at DESC)
);

-- Update conversation's last_message_at on new message
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET 
        last_message_at = NEW.created_at,
        last_message_preview = LEFT(NEW.text_content, 100),
        updated_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER message_updates_conversation
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_last_message();
```

## 2.4 Message Reactions Table

```sql
CREATE TABLE message_reactions (
    -- Composite key
    message_id UUID NOT NULL 
        REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL 
        REFERENCES profiles(id) ON DELETE CASCADE,
    reaction_type TEXT NOT NULL             -- 'love', 'like', 'dislike', 'laugh', 'emphasize', 'question'
        CHECK (reaction_type IN ('love', 'like', 'dislike', 'laugh', 'emphasize', 'question')),
    
    PRIMARY KEY (message_id, user_id, reaction_type),
    
    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Indexes
    INDEX idx_reactions_message (message_id),
    INDEX idx_reactions_user (user_id)
);

-- Limit 1 reaction per user per message (they can change it)
CREATE UNIQUE INDEX idx_one_reaction_per_user_per_message 
    ON message_reactions(message_id, user_id);
```

## 2.5 Message Read Receipts Table

```sql
CREATE TABLE message_read_receipts (
    message_id UUID NOT NULL 
        REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL 
        REFERENCES profiles(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (message_id, user_id),
    
    -- Indexes
    INDEX idx_read_receipts_message (message_id),
    INDEX idx_read_receipts_user (user_id)
);

-- Update participant's last_read tracking
CREATE OR REPLACE FUNCTION update_participant_read_status()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversation_participants
    SET 
        last_read_message_id = NEW.message_id,
        last_read_at = NEW.read_at
    WHERE user_id = NEW.user_id
        AND conversation_id = (
            SELECT conversation_id 
            FROM messages 
            WHERE id = NEW.message_id
        );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER read_receipt_updates_participant
    AFTER INSERT ON message_read_receipts
    FOR EACH ROW
    EXECUTE FUNCTION update_participant_read_status();
```

## 2.6 Typing Indicators (Ephemeral)

**Note**: Typing indicators are NOT stored in database. They use Realtime presence only.

```swift
// Handled via Supabase Realtime Presence API
// Channel: "conversation:{conversation_id}:presence"
// Payload: { user_id: UUID, typing: Bool, timestamp: ISO8601 }
```

---

# 3. API Layer

## 3.1 MessageService

```swift
// Core/Services/MessageService.swift

import Foundation
import Supabase

final class MessageService {
    static let shared = MessageService()
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Message Operations
    
    /// Send a text message
    func sendTextMessage(
        conversationId: UUID,
        text: String
    ) async throws -> Message {
        let sanitized = sanitizeText(text)
        
        guard !sanitized.isEmpty else {
            throw MessageError.emptyMessage
        }
        
        guard sanitized.count <= 2000 else {
            throw MessageError.messageTooLong
        }
        
        let message = Message(
            id: UUID(),
            conversationId: conversationId,
            fromUserId: try await getCurrentUserId(),
            contentType: .text,
            textContent: sanitized,
            createdAt: Date()
        )
        
        try await supabase
            .from("messages")
            .insert(message)
            .execute()
        
        // Mark as read for sender immediately
        try await markMessageAsRead(messageId: message.id)
        
        return message
    }
    
    /// Send an image message
    func sendImageMessage(
        conversationId: UUID,
        imageData: Data
    ) async throws -> Message {
        // 1. Compress image
        let compressed = try compressImage(imageData, maxSizeKB: 1024)
        let thumbnail = try createThumbnail(from: compressed, size: CGSize(width: 200, height: 200))
        
        // 2. Upload to storage
        let messageId = UUID()
        let imagePath = "messages/\(conversationId)/\(messageId).jpg"
        let thumbnailPath = "messages/\(conversationId)/\(messageId)_thumb.jpg"
        
        async let imageUpload = StorageService.shared.uploadImage(
            data: compressed,
            path: imagePath
        )
        async let thumbnailUpload = StorageService.shared.uploadImage(
            data: thumbnail,
            path: thumbnailPath
        )
        
        let (imageUrl, thumbnailUrl) = try await (imageUpload, thumbnailUpload)
        
        // 3. Create message record
        let message = Message(
            id: messageId,
            conversationId: conversationId,
            fromUserId: try await getCurrentUserId(),
            contentType: .image,
            imageUrl: imageUrl,
            imageThumbnailUrl: thumbnailUrl,
            createdAt: Date()
        )
        
        try await supabase
            .from("messages")
            .insert(message)
            .execute()
        
        try await markMessageAsRead(messageId: message.id)
        
        return message
    }
    
    /// Fetch messages for conversation (paginated)
    func fetchMessages(
        conversationId: UUID,
        limit: Int = 50,
        before: Date? = nil
    ) async throws -> [Message] {
        var query = supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("is_deleted", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
        
        if let before = before {
            query = query.lt("created_at", value: before.ISO8601Format())
        }
        
        let response: [Message] = try await query.execute().value
        return response.reversed() // Return in chronological order
    }
    
    /// Mark message as read
    func markMessageAsRead(messageId: UUID) async throws {
        let userId = try await getCurrentUserId()
        
        try await supabase
            .from("message_read_receipts")
            .insert([
                "message_id": messageId.uuidString,
                "user_id": userId.uuidString
            ])
            .execute()
        
        // Note: Trigger will update conversation_participants.last_read_message_id
    }
    
    /// Mark all messages in conversation as read
    func markConversationAsRead(conversationId: UUID) async throws {
        let messages = try await fetchUnreadMessages(conversationId: conversationId)
        
        for message in messages {
            try await markMessageAsRead(messageId: message.id)
        }
    }
    
    /// Fetch unread messages for conversation
    private func fetchUnreadMessages(conversationId: UUID) async throws -> [Message] {
        let userId = try await getCurrentUserId()
        
        // Get user's last read message
        let participant: ConversationParticipant = try await supabase
            .from("conversation_participants")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        // Fetch messages after last read
        var query = supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("is_deleted", value: false)
            .neq("from_user_id", value: userId.uuidString) // Don't include own messages
        
        if let lastReadId = participant.lastReadMessageId {
            query = query.gt("created_at", value: lastReadId.uuidString)
        }
        
        return try await query.execute().value
    }
    
    /// Delete message (soft delete)
    func deleteMessage(messageId: UUID) async throws {
        try await supabase
            .from("messages")
            .update(["is_deleted": true])
            .eq("id", value: messageId.uuidString)
            .execute()
    }
    
    // MARK: - Reactions
    
    /// Add or update reaction to message
    func addReaction(
        messageId: UUID,
        reactionType: ReactionType
    ) async throws {
        let userId = try await getCurrentUserId()
        
        // Upsert reaction (replaces if exists)
        try await supabase
            .from("message_reactions")
            .upsert([
                "message_id": messageId.uuidString,
                "user_id": userId.uuidString,
                "reaction_type": reactionType.rawValue
            ])
            .execute()
    }
    
    /// Remove reaction from message
    func removeReaction(
        messageId: UUID,
        reactionType: ReactionType
    ) async throws {
        let userId = try await getCurrentUserId()
        
        try await supabase
            .from("message_reactions")
            .delete()
            .eq("message_id", value: messageId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .eq("reaction_type", value: reactionType.rawValue)
            .execute()
    }
    
    /// Fetch reactions for message
    func fetchReactions(messageId: UUID) async throws -> [MessageReaction] {
        return try await supabase
            .from("message_reactions")
            .select()
            .eq("message_id", value: messageId.uuidString)
            .execute()
            .value
    }
    
    // MARK: - Helpers
    
    private func sanitizeText(_ text: String) -> String {
        var sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = String(sanitized.prefix(2000))
        // Remove control characters except newline
        sanitized = sanitized.filter { 
            $0.isNewline || !$0.isASCII || ($0.asciiValue ?? 0) >= 32 
        }
        return sanitized
    }
    
    private func getCurrentUserId() async throws -> UUID {
        guard let session = try await supabase.auth.session else {
            throw MessageError.notAuthenticated
        }
        return UUID(uuidString: session.user.id.uuidString)!
    }
}

// MARK: - Errors

enum MessageError: LocalizedError {
    case emptyMessage
    case messageTooLong
    case notAuthenticated
    case imageUploadFailed
    case invalidConversation
    
    var errorDescription: String? {
        switch self {
        case .emptyMessage: return "Message cannot be empty"
        case .messageTooLong: return "Message is too long (max 2000 characters)"
        case .notAuthenticated: return "You must be signed in to send messages"
        case .imageUploadFailed: return "Failed to upload image"
        case .invalidConversation: return "Invalid conversation"
        }
    }
}
```

## 3.2 ConversationService

```swift
// Core/Services/ConversationService.swift

import Foundation
import Supabase

final class ConversationService {
    static let shared = ConversationService()
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Conversation CRUD
    
    /// Fetch all conversations for current user
    func fetchConversations() async throws -> [ConversationWithDetails] {
        let userId = try await getCurrentUserId()
        
        // Fetch conversations where user is participant
        let conversations: [Conversation] = try await supabase
            .from("conversations")
            .select("""
                *,
                conversation_participants!inner(user_id, unread_count, last_read_at)
            """)
            .eq("conversation_participants.user_id", value: userId.uuidString)
            .is("conversation_participants.left_at", value: "null")
            .order("last_message_at", ascending: false)
            .execute()
            .value
        
        // For each conversation, fetch participants and last message
        var conversationsWithDetails: [ConversationWithDetails] = []
        
        for conversation in conversations {
            let participants = try await fetchParticipants(conversationId: conversation.id)
            let lastMessage = try await fetchLastMessage(conversationId: conversation.id)
            let unreadCount = try await fetchUnreadCount(conversationId: conversation.id)
            
            conversationsWithDetails.append(ConversationWithDetails(
                conversation: conversation,
                participants: participants,
                lastMessage: lastMessage,
                unreadCount: unreadCount
            ))
        }
        
        return conversationsWithDetails
    }
    
    /// Create a new direct conversation (1:1)
    func createDirectConversation(
        withUserId otherUserId: UUID
    ) async throws -> Conversation {
        let currentUserId = try await getCurrentUserId()
        
        // Check if conversation already exists
        if let existing = try await findExistingDirectConversation(
            user1: currentUserId,
            user2: otherUserId
        ) {
            return existing
        }
        
        // Create new conversation
        let conversation = Conversation(
            id: UUID(),
            conversationType: .direct,
            createdBy: currentUserId,
            createdAt: Date()
        )
        
        try await supabase
            .from("conversations")
            .insert(conversation)
            .execute()
        
        // Add both participants
        try await addParticipant(
            conversationId: conversation.id,
            userId: currentUserId,
            role: .creator
        )
        try await addParticipant(
            conversationId: conversation.id,
            userId: otherUserId,
            role: .member
        )
        
        return conversation
    }
    
    /// Create a group conversation
    func createGroupConversation(
        title: String?,
        participantIds: [UUID]
    ) async throws -> Conversation {
        let currentUserId = try await getCurrentUserId()
        
        let conversation = Conversation(
            id: UUID(),
            title: title,
            conversationType: .group,
            createdBy: currentUserId,
            createdAt: Date()
        )
        
        try await supabase
            .from("conversations")
            .insert(conversation)
            .execute()
        
        // Add creator
        try await addParticipant(
            conversationId: conversation.id,
            userId: currentUserId,
            role: .creator,
            canAddMembers: true,
            canRemoveMembers: true,
            canRename: true
        )
        
        // Add other participants
        for userId in participantIds where userId != currentUserId {
            try await addParticipant(
                conversationId: conversation.id,
                userId: userId,
                role: .member
            )
        }
        
        // Send system message
        try await sendSystemMessage(
            conversationId: conversation.id,
            eventType: .conversationCreated,
            eventData: ["participant_count": participantIds.count + 1]
        )
        
        return conversation
    }
    
    /// Create conversation for request (ride/favor)
    func createRequestConversation(
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        participantIds: [UUID]
    ) async throws -> Conversation {
        let currentUserId = try await getCurrentUserId()
        
        let conversation = Conversation(
            id: UUID(),
            conversationType: .request,
            createdBy: currentUserId,
            rideId: rideId,
            favorId: favorId,
            createdAt: Date()
        )
        
        try await supabase
            .from("conversations")
            .insert(conversation)
            .execute()
        
        // Add all participants
        for userId in participantIds {
            try await addParticipant(
                conversationId: conversation.id,
                userId: userId,
                role: userId == currentUserId ? .creator : .member
            )
        }
        
        return conversation
    }
    
    /// Update conversation title
    func updateConversationTitle(
        conversationId: UUID,
        newTitle: String
    ) async throws {
        let currentUserId = try await getCurrentUserId()
        
        // Verify user has permission
        guard try await userCanRename(conversationId: conversationId) else {
            throw ConversationError.permissionDenied
        }
        
        try await supabase
            .from("conversations")
            .update(["title": newTitle])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        // Send system message
        try await sendSystemMessage(
            conversationId: conversationId,
            eventType: .conversationRenamed,
            eventData: ["new_title": newTitle]
        )
    }
    
    // MARK: - Participant Management
    
    /// Add participant to conversation
    func addParticipant(
        conversationId: UUID,
        userId: UUID,
        role: ParticipantRole = .member,
        canAddMembers: Bool = false,
        canRemoveMembers: Bool = false,
        canRename: Bool = false
    ) async throws {
        let currentUserId = try await getCurrentUserId()
        
        // Verify current user has permission to add
        if currentUserId != userId {
            guard try await userCanAddMembers(conversationId: conversationId) else {
                throw ConversationError.permissionDenied
            }
        }
        
        let participant = ConversationParticipant(
            conversationId: conversationId,
            userId: userId,
            joinedAt: Date(),
            addedBy: currentUserId,
            role: role,
            canAddMembers: canAddMembers,
            canRemoveMembers: canRemoveMembers,
            canRename: canRename
        )
        
        try await supabase
            .from("conversation_participants")
            .insert(participant)
            .execute()
        
        // Send system message
        if currentUserId != userId {
            try await sendSystemMessage(
                conversationId: conversationId,
                eventType: .userAdded,
                eventData: [
                    "user_id": userId.uuidString,
                    "added_by": currentUserId.uuidString
                ]
            )
        }
    }
    
    /// Remove participant from conversation
    func removeParticipant(
        conversationId: UUID,
        userId: UUID
    ) async throws {
        let currentUserId = try await getCurrentUserId()
        
        // Verify permission (can remove others OR removing self)
        let canRemove = userId == currentUserId || 
            (try await userCanRemoveMembers(conversationId: conversationId))
        
        guard canRemove else {
            throw ConversationError.permissionDenied
        }
        
        // Mark as left
        try await supabase
            .from("conversation_participants")
            .update(["left_at": Date().ISO8601Format()])
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        // Send system message
        let eventType: SystemEventType = userId == currentUserId ? .userLeft : .userRemoved
        try await sendSystemMessage(
            conversationId: conversationId,
            eventType: eventType,
            eventData: [
                "user_id": userId.uuidString,
                "removed_by": currentUserId.uuidString
            ]
        )
    }
    
    /// Fetch participants for conversation
    func fetchParticipants(
        conversationId: UUID
    ) async throws -> [ParticipantWithProfile] {
        let participants: [ConversationParticipant] = try await supabase
            .from("conversation_participants")
            .select("""
                *,
                profiles(id, username, avatar_url, full_name)
            """)
            .eq("conversation_id", value: conversationId.uuidString)
            .is("left_at", value: "null")
            .execute()
            .value
        
        // Map to ParticipantWithProfile (includes Profile data)
        return participants.map { participant in
            // Profile data comes from the joined table
            ParticipantWithProfile(
                participant: participant,
                profile: participant.profile // Supabase includes this from the join
            )
        }
    }
    
    // MARK: - Permission Checks
    
    private func userCanAddMembers(conversationId: UUID) async throws -> Bool {
        let userId = try await getCurrentUserId()
        
        let participant: ConversationParticipant = try await supabase
            .from("conversation_participants")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        return participant.canAddMembers
    }
    
    private func userCanRemoveMembers(conversationId: UUID) async throws -> Bool {
        let userId = try await getCurrentUserId()
        
        let participant: ConversationParticipant = try await supabase
            .from("conversation_participants")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        return participant.canRemoveMembers
    }
    
    private func userCanRename(conversationId: UUID) async throws -> Bool {
        let userId = try await getCurrentUserId()
        
        let participant: ConversationParticipant = try await supabase
            .from("conversation_participants")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        return participant.canRename
    }
    
    // MARK: - Helpers
    
    private func findExistingDirectConversation(
        user1: UUID,
        user2: UUID
    ) async throws -> Conversation? {
        // Find conversations where both users are participants
        let conversations: [Conversation] = try await supabase
            .from("conversations")
            .select("""
                *,
                conversation_participants!inner(user_id)
            """)
            .eq("conversation_type", value: "direct")
            .in("conversation_participants.user_id", values: [user1.uuidString, user2.uuidString])
            .execute()
            .value
        
        // Filter to conversation where ONLY these two users are participants
        for conversation in conversations {
            let participants = try await fetchParticipants(conversationId: conversation.id)
            if participants.count == 2 &&
               participants.contains(where: { $0.participant.userId == user1 }) &&
               participants.contains(where: { $0.participant.userId == user2 }) {
                return conversation
            }
        }
        
        return nil
    }
    
    private func fetchLastMessage(conversationId: UUID) async throws -> Message? {
        let messages: [Message] = try await supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("is_deleted", value: false)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        
        return messages.first
    }
    
    private func fetchUnreadCount(conversationId: UUID) async throws -> Int {
        let userId = try await getCurrentUserId()
        
        let participant: ConversationParticipant = try await supabase
            .from("conversation_participants")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        return participant.unreadCount
    }
    
    private func sendSystemMessage(
        conversationId: UUID,
        eventType: SystemEventType,
        eventData: [String: Any]
    ) async throws {
        let message = Message(
            id: UUID(),
            conversationId: conversationId,
            fromUserId: try await getCurrentUserId(),
            contentType: .system,
            systemEventType: eventType,
            systemEventData: eventData,
            createdAt: Date()
        )
        
        try await supabase
            .from("messages")
            .insert(message)
            .execute()
    }
    
    private func getCurrentUserId() async throws -> UUID {
        guard let session = try await supabase.auth.session else {
            throw ConversationError.notAuthenticated
        }
        return UUID(uuidString: session.user.id.uuidString)!
    }
}

// MARK: - Errors

enum ConversationError: LocalizedError {
    case notAuthenticated
    case permissionDenied
    case conversationNotFound
    case invalidParticipants
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in"
        case .permissionDenied: return "You don't have permission to perform this action"
        case .conversationNotFound: return "Conversation not found"
        case .invalidParticipants: return "Invalid participant list"
        }
    }
}
```

---

# 4. Real-Time System

## 4.1 RealtimeManager (Centralized)

```swift
// Core/Services/RealtimeManager.swift

import Foundation
import Supabase

@MainActor
final class RealtimeManager: ObservableObject {
    static let shared = RealtimeManager()
    private let supabase = SupabaseService.shared.client
    
    // Active channels
    private var activeChannels: [String: RealtimeChannel] = [:]
    
    // Typing presence per conversation
    @Published private(set) var typingUsers: [UUID: Set<UUID>] = [:]
    
    private init() {
        setupAppLifecycleHandlers()
    }
    
    // MARK: - Message Subscriptions
    
    func subscribeToConversation(
        conversationId: UUID,
        onNewMessage: @escaping (Message) -> Void,
        onReaction: @escaping (MessageReaction) -> Void,
        onParticipantChange: @escaping () -> Void
    ) async {
        let channelName = "conversation:\(conversationId)"
        
        // Unsubscribe if already subscribed
        if activeChannels[channelName] != nil {
            await unsubscribe(channelName: channelName)
        }
        
        // Create channel
        let channel = await supabase.channel(channelName)
        
        // Subscribe to message inserts
        await channel
            .on(.postgresChanges(
                event: .insert,
                schema: "public",
                table: "messages",
                filter: "conversation_id=eq.\(conversationId)"
            )) { [weak self] payload in
                Task { @MainActor in
                    if let message = try? payload.decodeRecord(as: Message.self) {
                        onNewMessage(message)
                    }
                }
            }
        
        // Subscribe to reaction changes
        await channel
            .on(.postgresChanges(
                event: .insert,
                schema: "public",
                table: "message_reactions"
            )) { payload in
                Task { @MainActor in
                    if let reaction = try? payload.decodeRecord(as: MessageReaction.self) {
                        onReaction(reaction)
                    }
                }
            }
        
        // Subscribe to participant changes
        await channel
            .on(.postgresChanges(
                event: .update,
                schema: "public",
                table: "conversation_participants",
                filter: "conversation_id=eq.\(conversationId)"
            )) { _ in
                Task { @MainActor in
                    onParticipantChange()
                }
            }
        
        // Subscribe to presence (typing indicators)
        await channel
            .on(.presence(event: .sync)) { [weak self] in
                self?.handlePresenceSync(conversationId: conversationId, channel: channel)
            }
            .on(.presence(event: .join)) { [weak self] payload in
                self?.handlePresenceJoin(conversationId: conversationId, payload: payload)
            }
            .on(.presence(event: .leave)) { [weak self] payload in
                self?.handlePresenceLeave(conversationId: conversationId, payload: payload)
            }
        
        // Subscribe to channel
        await channel.subscribe()
        
        // Store active channel
        activeChannels[channelName] = channel
    }
    
    func unsubscribe(channelName: String) async {
        guard let channel = activeChannels[channelName] else { return }
        
        await supabase.removeChannel(channel)
        activeChannels.removeValue(forKey: channelName)
        
        // Clean up typing indicators if it's a conversation channel
        if let conversationIdString = channelName.split(separator: ":").last,
           let conversationId = UUID(uuidString: String(conversationIdString)) {
            typingUsers.removeValue(forKey: conversationId)
        }
    }
    
    func unsubscribeAll() async {
        for (channelName, _) in activeChannels {
            await unsubscribe(channelName: channelName)
        }
    }
    
    // MARK: - Typing Indicators
    
    func sendTypingIndicator(conversationId: UUID, isTyping: Bool) async {
        let channelName = "conversation:\(conversationId)"
        guard let channel = activeChannels[channelName] else { return }
        
        guard let userId = try? await getCurrentUserId() else { return }
        
        if isTyping {
            await channel.track(["typing": true])
        } else {
            await channel.untrack()
        }
    }
    
    private func handlePresenceSync(conversationId: UUID, channel: RealtimeChannel) {
        let presenceState = channel.presenceState()
        
        var typingUserIds: Set<UUID> = []
        for (userId, presences) in presenceState {
            if let uuid = UUID(uuidString: userId),
               let presence = presences.first,
               let isTyping = presence["typing"] as? Bool,
               isTyping {
                typingUserIds.insert(uuid)
            }
        }
        
        typingUsers[conversationId] = typingUserIds
    }
    
    private func handlePresenceJoin(conversationId: UUID, payload: PresencePayload) {
        if let userId = UUID(uuidString: payload.presenceKey),
           let isTyping = payload.newPresences.first?["typing"] as? Bool,
           isTyping {
            typingUsers[conversationId, default: []].insert(userId)
        }
    }
    
    private func handlePresenceLeave(conversationId: UUID, payload: PresencePayload) {
        if let userId = UUID(uuidString: payload.presenceKey) {
            typingUsers[conversationId]?.remove(userId)
        }
    }
    
    // MARK: - Lifecycle
    
    private func setupAppLifecycleHandlers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        Task { @MainActor in
            // Keep subscriptions but stop sending typing indicators
            for (conversationIdString, _) in activeChannels {
                if let conversationIdString = conversationIdString.split(separator: ":").last,
                   let conversationId = UUID(uuidString: String(conversationIdString)) {
                    await sendTypingIndicator(conversationId: conversationId, isTyping: false)
                }
            }
        }
    }
    
    @objc private func appWillEnterForeground() {
        // Channels auto-reconnect, no action needed
    }
    
    // MARK: - Helpers
    
    private func getCurrentUserId() async throws -> UUID {
        guard let session = try await supabase.auth.session else {
            throw RealtimeError.notAuthenticated
        }
        return UUID(uuidString: session.user.id.uuidString)!
    }
}

enum RealtimeError: Error {
    case notAuthenticated
    case channelNotFound
}
```

---

# 5. State Management

## 5.1 ConversationListViewModel

```swift
// Features/Messaging/ViewModels/ConversationsListViewModel.swift

import Foundation
import SwiftUI

@MainActor
final class ConversationsListViewModel: ObservableObject {
    // State
    @Published var conversations: [ConversationWithDetails] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var searchText = ""
    
    // Services
    private let conversationService = ConversationService.shared
    private let realtimeManager = RealtimeManager.shared
    
    // Computed
    var filteredConversations: [ConversationWithDetails] {
        guard !searchText.isEmpty else { return conversations }
        
        return conversations.filter { conversation in
            // Search by title or participant names
            if let title = conversation.conversation.title,
               title.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            return conversation.participants.contains { participant in
                participant.profile.username.localizedCaseInsensitiveContains(searchText) ||
                participant.profile.fullName?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    var totalUnreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }
    
    // MARK: - Actions
    
    func loadConversations() async {
        isLoading = true
        error = nil
        
        do {
            conversations = try await conversationService.fetchConversations()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    func createDirectMessage(withUserId userId: UUID) async throws -> UUID {
        let conversation = try await conversationService.createDirectConversation(
            withUserId: userId
        )
        
        await loadConversations()
        
        return conversation.id
    }
    
    func createGroupConversation(
        title: String?,
        participantIds: [UUID]
    ) async throws -> UUID {
        let conversation = try await conversationService.createGroupConversation(
            title: title,
            participantIds: participantIds
        )
        
        await loadConversations()
        
        return conversation.id
    }
    
    func archiveConversation(_ conversationId: UUID) async {
        // TODO: Implement archive
    }
    
    func deleteConversation(_ conversationId: UUID) async {
        // Remove participant (leave conversation)
        do {
            let userId = try await getCurrentUserId()
            try await conversationService.removeParticipant(
                conversationId: conversationId,
                userId: userId
            )
            
            await loadConversations()
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Helpers
    
    private func getCurrentUserId() async throws -> UUID {
        guard let session = try await SupabaseService.shared.client.auth.session else {
            throw ConversationError.notAuthenticated
        }
        return UUID(uuidString: session.user.id.uuidString)!
    }
}
```

## 5.2 ConversationDetailViewModel

```swift
// Features/Messaging/ViewModels/ConversationDetailViewModel.swift

import Foundation
import SwiftUI
import Combine

@MainActor
final class ConversationDetailViewModel: ObservableObject {
    // State
    @Published var messages: [Message] = []
    @Published var participants: [ParticipantWithProfile] = []
    @Published var conversation: Conversation?
    @Published var messageText = ""
    @Published var isLoading = false
    @Published var isSending = false
    @Published var error: Error?
    
    // Typing indicators
    @Published var typingUserIds: Set<UUID> = []
    
    // Image upload
    @Published var selectedImage: UIImage?
    @Published var isUploadingImage = false
    @Published var uploadProgress: Double = 0
    
    // Services
    private let messageService = MessageService.shared
    private let conversationService = ConversationService.shared
    private let realtimeManager = RealtimeManager.shared
    
    // Conversation ID
    let conversationId: UUID
    
    // Typing debounce
    private var typingCancellable: AnyCancellable?
    private var isCurrentlyTyping = false
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        setupTypingDebounce()
    }
    
    // MARK: - Lifecycle
    
    func onAppear() async {
        await loadConversation()
        await loadMessages()
        await loadParticipants()
        await subscribeToUpdates()
        await markAsRead()
    }
    
    func onDisappear() async {
        await unsubscribe()
        await stopTyping()
    }
    
    // MARK: - Data Loading
    
    private func loadConversation() async {
        // Fetch conversation details
        // (Implementation depends on ConversationService having a fetchById method)
    }
    
    private func loadMessages() async {
        isLoading = true
        
        do {
            messages = try await messageService.fetchMessages(
                conversationId: conversationId,
                limit: 50
            )
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    private func loadParticipants() async {
        do {
            participants = try await conversationService.fetchParticipants(
                conversationId: conversationId
            )
        } catch {
            self.error = error
        }
    }
    
    func loadOlderMessages() async {
        guard let oldestMessage = messages.first else { return }
        
        do {
            let olderMessages = try await messageService.fetchMessages(
                conversationId: conversationId,
                limit: 50,
                before: oldestMessage.createdAt
            )
            
            messages.insert(contentsOf: olderMessages, at: 0)
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Realtime Subscriptions
    
    private func subscribeToUpdates() async {
        await realtimeManager.subscribeToConversation(
            conversationId: conversationId,
            onNewMessage: { [weak self] message in
                self?.handleNewMessage(message)
            },
            onReaction: { [weak self] reaction in
                self?.handleNewReaction(reaction)
            },
            onParticipantChange: { [weak self] in
                Task {
                    await self?.loadParticipants()
                }
            }
        )
        
        // Subscribe to typing indicators
        setupTypingSubscription()
    }
    
    private func unsubscribe() async {
        await realtimeManager.unsubscribe(
            channelName: "conversation:\(conversationId)"
        )
    }
    
    private func handleNewMessage(_ message: Message) {
        // Don't add if it's an optimistic message we already have
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        
        messages.append(message)
        
        // Mark as read if from someone else
        Task {
            if message.fromUserId != try? await getCurrentUserId() {
                try? await messageService.markMessageAsRead(messageId: message.id)
            }
        }
    }
    
    private func handleNewReaction(_ reaction: MessageReaction) {
        // Find message and update its reactions
        if let index = messages.firstIndex(where: { $0.id == reaction.messageId }) {
            // Fetch updated reactions for this message
            Task {
                if let reactions = try? await messageService.fetchReactions(
                    messageId: reaction.messageId
                ) {
                    messages[index].reactions = reactions
                }
            }
        }
    }
    
    // MARK: - Send Message
    
    func sendMessage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isSending = true
        let textToSend = messageText
        
        // Clear input immediately (optimistic UI)
        messageText = ""
        
        // Create optimistic message
        let optimisticMessage = Message(
            id: UUID(),
            conversationId: conversationId,
            fromUserId: try! await getCurrentUserId(),
            contentType: .text,
            textContent: textToSend,
            createdAt: Date()
        )
        messages.append(optimisticMessage)
        
        do {
            let sentMessage = try await messageService.sendTextMessage(
                conversationId: conversationId,
                text: textToSend
            )
            
            // Replace optimistic with real
            if let index = messages.firstIndex(where: { $0.id == optimisticMessage.id }) {
                messages[index] = sentMessage
            }
            
        } catch {
            self.error = error
            
            // Remove optimistic message on error
            messages.removeAll { $0.id == optimisticMessage.id }
            
            // Restore text
            messageText = textToSend
        }
        
        isSending = false
    }
    
    func sendImage(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        
        isUploadingImage = true
        uploadProgress = 0
        
        // Create optimistic image message
        let optimisticMessage = Message(
            id: UUID(),
            conversationId: conversationId,
            fromUserId: try! await getCurrentUserId(),
            contentType: .image,
            imageUrl: nil, // Will be set when uploaded
            createdAt: Date()
        )
        messages.append(optimisticMessage)
        
        do {
            // TODO: Add upload progress tracking
            let sentMessage = try await messageService.sendImageMessage(
                conversationId: conversationId,
                imageData: imageData
            )
            
            // Replace optimistic with real
            if let index = messages.firstIndex(where: { $0.id == optimisticMessage.id }) {
                messages[index] = sentMessage
            }
            
        } catch {
            self.error = error
            messages.removeAll { $0.id == optimisticMessage.id }
        }
        
        isUploadingImage = false
        selectedImage = nil
    }
    
    // MARK: - Reactions
    
    func addReaction(to messageId: UUID, type: ReactionType) async {
        do {
            try await messageService.addReaction(
                messageId: messageId,
                reactionType: type
            )
            
            // Update handled by realtime subscription
        } catch {
            self.error = error
        }
    }
    
    func removeReaction(from messageId: UUID, type: ReactionType) async {
        do {
            try await messageService.removeReaction(
                messageId: messageId,
                reactionType: type
            )
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Typing Indicators
    
    private func setupTypingDebounce() {
        typingCancellable = $messageText
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                Task { @MainActor in
                    if text.isEmpty && self?.isCurrentlyTyping == true {
                        await self?.stopTyping()
                    }
                }
            }
    }
    
    private func setupTypingSubscription() {
        // Subscribe to typing users from RealtimeManager
        realtimeManager.$typingUsers
            .map { $0[conversationId] ?? [] }
            .assign(to: &$typingUserIds)
    }
    
    func onMessageTextChanged() async {
        if !messageText.isEmpty && !isCurrentlyTyping {
            await startTyping()
        } else if messageText.isEmpty && isCurrentlyTyping {
            await stopTyping()
        }
    }
    
    private func startTyping() async {
        isCurrentlyTyping = true
        await realtimeManager.sendTypingIndicator(
            conversationId: conversationId,
            isTyping: true
        )
    }
    
    private func stopTyping() async {
        isCurrentlyTyping = false
        await realtimeManager.sendTypingIndicator(
            conversationId: conversationId,
            isTyping: false
        )
    }
    
    // MARK: - Conversation Management
    
    func renameConversation(newTitle: String) async {
        do {
            try await conversationService.updateConversationTitle(
                conversationId: conversationId,
                newTitle: newTitle
            )
            
            conversation?.title = newTitle
        } catch {
            self.error = error
        }
    }
    
    func addParticipant(userId: UUID) async {
        do {
            try await conversationService.addParticipant(
                conversationId: conversationId,
                userId: userId
            )
            
            await loadParticipants()
        } catch {
            self.error = error
        }
    }
    
    func removeParticipant(userId: UUID) async {
        do {
            try await conversationService.removeParticipant(
                conversationId: conversationId,
                userId: userId
            )
            
            await loadParticipants()
        } catch {
            self.error = error
        }
    }
    
    func leaveConversation() async {
        do {
            let userId = try await getCurrentUserId()
            try await conversationService.removeParticipant(
                conversationId: conversationId,
                userId: userId
            )
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Read Tracking
    
    private func markAsRead() async {
        do {
            try await messageService.markConversationAsRead(
                conversationId: conversationId
            )
        } catch {
            // Silently fail - not critical
        }
    }
    
    // MARK: - Helpers
    
    var typingUsersText: String {
        let currentUserId = try? await getCurrentUserId()
        let typingOthers = typingUserIds.filter { $0 != currentUserId }
        
        guard !typingOthers.isEmpty else { return "" }
        
        let names = participants
            .filter { typingOthers.contains($0.participant.userId) }
            .map { $0.profile.username }
        
        if names.count == 1 {
            return "\(names[0]) is typing..."
        } else if names.count == 2 {
            return "\(names[0]) and \(names[1]) are typing..."
        } else {
            return "Several people are typing..."
        }
    }
    
    private func getCurrentUserId() async throws -> UUID {
        guard let session = try await SupabaseService.shared.client.auth.session else {
            throw MessageError.notAuthenticated
        }
        return UUID(uuidString: session.user.id.uuidString)!
    }
}
```

---

# 6. UI/UX Specifications

## 6.1 Conversations List View

### Layout Specification

```
┌─────────────────────────────────────────┐
│  ← Messages                     [+] [⚙]  │ ← Navigation bar
├─────────────────────────────────────────┤
│  🔍 Search messages...                   │ ← Search bar
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────────┐ │
│  │ 👤  Sarah Johnson             3:24PM │ │ ← Conversation row
│  │     Hey, are you free tomorrow? 🚗   │ │   (unread = bold)
│  │     [2]                               │ │   Unread badge
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │ 👥  Capitol Hill → Airport    Tue    │ │ ← Group conversation
│  │     Mike: Sounds good!                │ │   (subtitle shows last sender)
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │ 👤  Tom Wilson              Yesterday │ │ ← Read conversation
│  │     Thanks for the ride!              │ │   (normal weight)
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
     Tab Bar: 🏠 Rides Favors 💬(2) Profile
```

### Component Breakdown

```swift
// Features/Messaging/Views/ConversationsListView.swift

struct ConversationsListView: View {
    @StateObject private var viewModel = ConversationsListViewModel()
    @State private var showingNewMessage = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $viewModel.searchText)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if viewModel.filteredConversations.isEmpty {
                    emptyState
                } else {
                    conversationsList
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewMessage = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingNewMessage) {
                NewMessageView()
            }
            .sheet(isPresented: $showingSettings) {
                MessagingSettingsView()
            }
            .task {
                await viewModel.loadConversations()
            }
            .refreshable {
                await viewModel.loadConversations()
            }
        }
    }
    
    private var conversationsList: some View {
        List {
            ForEach(viewModel.filteredConversations) { conversation in
                NavigationLink(destination: ConversationDetailView(
                    conversationId: conversation.conversation.id
                )) {
                    ConversationRow(conversation: conversation)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteConversation(
                                conversation.conversation.id
                            )
                        }
                    } label: {
                        Label("Leave", systemImage: "arrow.right.square")
                    }
                    
                    Button {
                        Task {
                            await viewModel.archiveConversation(
                                conversation.conversation.id
                            )
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Messages Yet")
                .font(.title2.bold())
            
            Text("Start a conversation with your Carbardians")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("New Message") {
                showingNewMessage = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
}
```

### Conversation Row Component

```swift
// UI/Components/Messaging/ConversationRow.swift

struct ConversationRow: View {
    let conversation: ConversationWithDetails
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 50, height: 50)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title and time
                HStack {
                    Text(conversationTitle)
                        .font(.headline)
                        .fontWeight(conversation.unreadCount > 0 ? .bold : .semibold)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(timeAgoText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Last message preview
                HStack {
                    if let lastMessage = conversation.lastMessage {
                        lastMessageView(lastMessage)
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Unread badge
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var avatarView: some View {
        if conversation.conversation.conversationType == .group {
            // Group avatar (multiple faces)
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                
                Image(systemName: "person.2.fill")
                    .foregroundColor(.gray)
            }
        } else if let otherUser = conversation.participants.first(where: { 
            $0.participant.userId != currentUserId 
        }) {
            // Individual avatar
            AsyncImage(url: URL(string: otherUser.profile.avatarUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Text(otherUser.profile.username.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
        }
    }
    
    private func lastMessageView(_ message: Message) -> some View {
        HStack(spacing: 4) {
            // Sender name for group chats
            if conversation.conversation.conversationType == .group,
               let sender = conversation.participants.first(where: { 
                   $0.participant.userId == message.fromUserId 
               }) {
                Text("\(sender.profile.username):")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // Message content
            Group {
                switch message.contentType {
                case .text:
                    Text(message.textContent ?? "")
                        .lineLimit(1)
                case .image:
                    Label("Photo", systemImage: "photo")
                case .system:
                    Text(message.systemEventType?.displayText ?? "")
                        .italic()
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
    
    private var conversationTitle: String {
        if let title = conversation.conversation.title {
            return title
        }
        
        // For direct chats, use other person's name
        if conversation.conversation.conversationType == .direct,
           let otherUser = conversation.participants.first(where: { 
               $0.participant.userId != currentUserId 
           }) {
            return otherUser.profile.fullName ?? otherUser.profile.username
        }
        
        // For groups without title, list participants
        let names = conversation.participants
            .filter { $0.participant.userId != currentUserId }
            .prefix(3)
            .map { $0.profile.username }
        
        if names.count > 2 {
            return names.prefix(2).joined(separator: ", ") + "..."
        } else {
            return names.joined(separator: ", ")
        }
    }
    
    private var timeAgoText: String {
        guard let lastMessageAt = conversation.conversation.lastMessageAt else {
            return ""
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastMessageAt, relativeTo: Date())
    }
    
    // Helper to get current user ID
    // (In real implementation, would come from environment or service)
    private var currentUserId: UUID {
        // Placeholder
        UUID()
    }
}
```

---

## 6.2 Conversation Detail View

### Layout Specification

```
┌─────────────────────────────────────────┐
│  ← Sarah Johnson                    [i]  │ ← Nav bar with info button
├─────────────────────────────────────────┤
│                                          │
│  ┌────────────────────┐                 │ ← Their message (left)
│  │ Hey! Are you free  │  Sarah  11:30AM │
│  │ tomorrow? 🚗       │                 │
│  └────────────────────┘                 │
│  ❤️ 2                                    │ ← Reactions below
│                                          │
│                 ┌────────────────────┐  │ ← Your message (right)
│        11:32AM  │ Yes! What time?    │  │
│                 └────────────────────┘  │
│                                          │
│  ┌────────────────────┐                 │
│  │ [Image: Car photo] │  Sarah  11:35AM │ ← Image message
│  └────────────────────┘                 │
│  👍 1  😂 1                              │ ← Multiple reactions
│                                          │
│                 ┌────────────────────┐  │
│        11:36AM  │ Nice ride! 10am?   │  │
│                 └────────────────────┘  │
│                 Read                     │ ← Read receipt
│                                          │
│  Sarah is typing...                      │ ← Typing indicator
│                                          │
├─────────────────────────────────────────┤
│  [📷] [📎] [Message field...] [↑Send]   │ ← Input bar
└─────────────────────────────────────────┘
```

### Implementation

```swift
// Features/Messaging/Views/ConversationDetailView.swift

struct ConversationDetailView: View {
    @StateObject private var viewModel: ConversationDetailViewModel
    @State private var showingInfo = false
    @State private var showingImagePicker = false
    @FocusState private var isInputFocused: Bool
    
    init(conversationId: UUID) {
        _viewModel = StateObject(wrappedValue: 
            ConversationDetailViewModel(conversationId: conversationId)
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            messagesList
            
            // Typing indicator
            if !viewModel.typingUsersText.isEmpty {
                typingIndicator
            }
            
            // Input bar
            MessageInputBar(
                text: $viewModel.messageText,
                isSending: viewModel.isSending,
                onSend: {
                    Task { await viewModel.sendMessage() }
                },
                onImageTap: { showingImagePicker = true },
                onTextChanged: {
                    Task { await viewModel.onMessageTextChanged() }
                }
            )
            .focused($isInputFocused)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingInfo = true }) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingInfo) {
            ConversationInfoView(
                conversationId: viewModel.conversationId,
                participants: viewModel.participants
            )
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $viewModel.selectedImage)
        }
        .onChange(of: viewModel.selectedImage) { _, newImage in
            if let image = newImage {
                Task {
                    await viewModel.sendImage(image)
                }
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            Task {
                await viewModel.onDisappear()
            }
        }
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Load more button
                    if viewModel.messages.count >= 50 {
                        Button("Load Earlier Messages") {
                            Task {
                                await viewModel.loadOlderMessages()
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    
                    // Messages
                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            isFromCurrentUser: message.fromUserId == currentUserId,
                            showSenderName: viewModel.conversation?.conversationType == .group,
                            senderName: senderName(for: message.fromUserId),
                            onReactionTap: { reactionType in
                                Task {
                                    await viewModel.addReaction(
                                        to: message.id,
                                        type: reactionType
                                    )
                                }
                            },
                            onReactionRemove: { reactionType in
                                Task {
                                    await viewModel.removeReaction(
                                        from: message.id,
                                        type: reactionType
                                    )
                                }
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                // Scroll to bottom when new message arrives
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var typingIndicator: some View {
        HStack {
            Text(viewModel.typingUsersText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
    }
    
    private var navigationTitle: String {
        if let title = viewModel.conversation?.title {
            return title
        }
        
        // For direct chats
        if viewModel.conversation?.conversationType == .direct,
           let otherUser = viewModel.participants.first(where: { 
               $0.participant.userId != currentUserId 
           }) {
            return otherUser.profile.fullName ?? otherUser.profile.username
        }
        
        // For groups
        return "\(viewModel.participants.count) participants"
    }
    
    private func senderName(for userId: UUID) -> String? {
        viewModel.participants
            .first { $0.participant.userId == userId }?
            .profile.username
    }
    
    private var currentUserId: UUID {
        // Get from session/environment
        UUID() // Placeholder
    }
}
```

### Message Bubble Component

```swift
// UI/Components/Messaging/MessageBubble.swift

struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let showSenderName: Bool
    let senderName: String?
    var onReactionTap: ((ReactionType) -> Void)?
    var onReactionRemove: ((ReactionType) -> Void)?
    
    @State private var showingReactionPicker = false
    
    var body: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
            // Sender name (for group chats)
            if showSenderName && !isFromCurrentUser {
                Text(senderName ?? "Unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
            }
            
            HStack {
                if isFromCurrentUser {
                    Spacer()
                    timestamp
                }
                
                // Message content
                VStack(alignment: .leading, spacing: 0) {
                    messageBubbleContent
                    
                    // Reactions
                    if !message.reactions.isEmpty {
                        reactionsView
                    }
                }
                .contextMenu {
                    reactionMenu
                }
                
                if !isFromCurrentUser {
                    timestamp
                    Spacer()
                }
            }
            
            // Read receipt (only for your messages)
            if isFromCurrentUser && message.readBy.count > 1 {
                Text("Read")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var messageBubbleContent: some View {
        switch message.contentType {
        case .text:
            textBubble
        case .image:
            imageBubble
        case .system:
            systemMessage
        }
    }
    
    private var textBubble: some View {
        Text(message.textContent ?? "")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isFromCurrentUser ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isFromCurrentUser ? .white : .primary)
            .clipShape(MessageBubbleShape(isFromCurrentUser: isFromCurrentUser))
    }
    
    private var imageBubble: some View {
        AsyncImage(url: URL(string: message.imageUrl ?? "")) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(width: 200, height: 200)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 250, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .failure:
                Image(systemName: "photo")
                    .frame(width: 200, height: 200)
            @unknown default:
                EmptyView()
            }
        }
    }
    
    private var systemMessage: some View {
        Text(message.systemEventType?.displayText ?? "")
            .font(.caption)
            .foregroundColor(.secondary)
            .italic()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }
    
    private var timestamp: some View {
        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundColor(.secondary)
    }
    
    private var reactionsView: some View {
        HStack(spacing: 4) {
            ForEach(reactionGroups, id: \.type) { group in
                ReactionChip(
                    reactionType: group.type,
                    count: group.count,
                    isFromCurrentUser: group.includedCurrentUser,
                    onTap: {
                        if group.includedCurrentUser {
                            onReactionRemove?(group.type)
                        } else {
                            onReactionTap?(group.type)
                        }
                    }
                )
            }
            
            // Add reaction button
            Button(action: { showingReactionPicker = true }) {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .sheet(isPresented: $showingReactionPicker) {
            ReactionPickerView(onSelect: { reactionType in
                onReactionTap?(reactionType)
                showingReactionPicker = false
            })
        }
    }
    
    private var reactionMenu: some View {
        ForEach(ReactionType.allCases, id: \.self) { reactionType in
            Button(action: {
                onReactionTap?(reactionType)
            }) {
                Label(reactionType.emoji, systemImage: "")
            }
        }
    }
    
    private var reactionGroups: [(type: ReactionType, count: Int, includedCurrentUser: Bool)] {
        var groups: [ReactionType: (count: Int, includedCurrentUser: Bool)] = [:]
        
        for reaction in message.reactions {
            let current = groups[reaction.reactionType] ?? (count: 0, includedCurrentUser: false)
            groups[reaction.reactionType] = (
                count: current.count + 1,
                includedCurrentUser: current.includedCurrentUser || reaction.userId == currentUserId
            )
        }
        
        return groups.map { ($0.key, $0.value.count, $0.value.includedCurrentUser) }
            .sorted { $0.count > $1.count }
    }
    
    private var currentUserId: UUID {
        UUID() // Placeholder
    }
}

// Custom bubble shape
struct MessageBubbleShape: Shape {
    let isFromCurrentUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: isFromCurrentUser ? 
                [.topLeft, .topRight, .bottomLeft] : 
                [.topLeft, .topRight, .bottomRight],
            cornerRadii: CGSize(width: 16, height: 16)
        )
        return Path(path.cgPath)
    }
}
```

### Reaction Chip

```swift
// UI/Components/Messaging/ReactionChip.swift

struct ReactionChip: View {
    let reactionType: ReactionType
    let count: Int
    let isFromCurrentUser: Bool
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 4) {
                Text(reactionType.emoji)
                    .font(.caption)
                
                if count > 1 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(isFromCurrentUser ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isFromCurrentUser ? 
                Color.accentColor.opacity(0.1) : 
                Color(.systemGray6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFromCurrentUser ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

### Message Input Bar

```swift
// UI/Components/Messaging/MessageInputBar.swift

struct MessageInputBar: View {
    @Binding var text: String
    let isSending: Bool
    var onSend: () -> Void
    var onImageTap: () -> Void
    var onTextChanged: () -> Void
    
    @State private var inputHeight: CGFloat = 36
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Camera button
            Button(action: onImageTap) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .disabled(isSending)
            
            // Text input
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Message")
                        .foregroundColor(Color(.placeholderText))
                        .padding(.leading, 12)
                }
                
                TextView(
                    text: $text,
                    height: $inputHeight,
                    onTextChanged: onTextChanged
                )
                .frame(height: min(inputHeight, 100))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            
            // Send button
            Button(action: onSend) {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.isEmpty ? .gray : .accentColor)
            }
            .disabled(text.isEmpty || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// Custom TextView for auto-growing input
struct TextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onTextChanged: () -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isScrollEnabled = false
        textView.font = .systemFont(ofSize: 16)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        
        // Update height
        let size = uiView.sizeThatFits(CGSize(width: uiView.frame.width, height: .infinity))
        if height != size.height {
            DispatchQueue.main.async {
                height = size.height
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        
        init(_ parent: TextView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onTextChanged()
        }
    }
}
```

---

## 6.3 Conversation Info View

### Layout

```
┌─────────────────────────────────────────┐
│  ✕ Conversation Info                     │
├─────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ 👥 Group Photo/Name                │ │
│  │    Capitol Hill → Airport Group   │ │
│  └────────────────────────────────────┘ │
│                                          │
│  Participants (4)                        │
│  ├─ 👤 Sarah Johnson (You)              │
│  ├─ 👤 Mike Chen                        │
│  ├─ 👤 Tom Wilson                       │
│  └─ 👤 Amy Park                         │
│                                          │
│  [+ Add Participants]                    │
│                                          │
│  Customization                           │
│  ├─ ✏️ Change Group Name                │
│  └─ 📷 Change Group Photo               │
│                                          │
│  Notifications                           │
│  └─ 🔕 Mute Notifications [ Toggle ]    │
│                                          │
│  Media & Links (23)                      │
│  [Thumbnail grid of images]              │
│                                          │
│  Danger Zone                             │
│  └─ 🚪 Leave Conversation                │
│                                          │
└─────────────────────────────────────────┘
```

### Implementation

```swift
// Features/Messaging/Views/ConversationInfoView.swift

struct ConversationInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let conversationId: UUID
    @State var participants: [ParticipantWithProfile]
    
    @State private var showingRename = false
    @State private var showingAddParticipants = false
    @State private var newGroupName = ""
    
    var body: some View {
        NavigationStack {
            List {
                // Group header
                Section {
                    groupHeader
                }
                
                // Participants
                Section("Participants") {
                    ForEach(participants) { participant in
                        ParticipantRow(participant: participant)
                    }
                    
                    Button("Add Participants") {
                        showingAddParticipants = true
                    }
                }
                
                // Customization
                Section("Customization") {
                    Button("Change Group Name") {
                        showingRename = true
                    }
                    
                    Button("Change Group Photo") {
                        // TODO: Implement
                    }
                }
                
                // Leave
                Section {
                    Button("Leave Conversation", role: .destructive) {
                        // Confirm and leave
                    }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRename) {
                RenameGroupView(conversationId: conversationId)
            }
            .sheet(isPresented: $showingAddParticipants) {
                AddParticipantsView(conversationId: conversationId)
            }
        }
    }
    
    private var groupHeader: some View {
        VStack(spacing: 12) {
            // Group avatar
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "person.2.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
            
            // Group name
            Text("Group Name")
                .font(.title2.bold())
            
            Text("\(participants.count) participants")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

struct ParticipantRow: View {
    let participant: ParticipantWithProfile
    
    var body: some View {
        HStack {
            AsyncImage(url: URL(string: participant.profile.avatarUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.2))
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            
            VStack(alignment: .leading) {
                Text(participant.profile.fullName ?? participant.profile.username)
                    .font(.headline)
                
                if participant.participant.role == .creator {
                    Text("Admin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Remove button (if you have permission)
            if canRemoveParticipant {
                Button(action: {
                    // Remove participant
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private var canRemoveParticipant: Bool {
        // Check if current user has permission
        false // Placeholder
    }
}
```

---

# 7. Feature Specifications

## 7.1 Reactions

### Available Reaction Types

```swift
enum ReactionType: String, Codable, CaseIterable {
    case love = "love"         // ❤️
    case like = "like"         // 👍
    case dislike = "dislike"   // 👎
    case laugh = "laugh"       // 😂
    case emphasize = "emphasize" // ‼️
    case question = "question"   // ❓
    
    var emoji: String {
        switch self {
        case .love: return "❤️"
        case .like: return "👍"
        case .dislike: return "👎"
        case .laugh: return "😂"
        case .emphasize: return "‼️"
        case .question: return "❓"
        }
    }
}
```

### Reaction Behavior

1. **Adding a Reaction**:
   - Long press message → Reaction picker appears
   - Tap reaction type
   - Reaction immediately added (optimistic UI)
   - Synced to database
   - Realtime broadcast to all participants
   - Other participants see reaction appear

2. **Removing a Reaction**:
   - Tap your reaction chip on message
   - Reaction immediately removed
   - Synced to database
   - Realtime broadcast

3. **Changing a Reaction**:
   - System allows only 1 reaction per user per message
   - Selecting new reaction replaces old one
   - Upsert operation in database

4. **Display Rules**:
   - Group identical reactions together
   - Show count if > 1
   - Highlight reactions from current user
   - Sort by count (most popular first)

---

## 7.2 Group Management

### Creating a Group

```swift
// Flow
1. Tap "New Message" → "New Group"
2. Select participants (2+ people required)
3. Optionally set group name
4. Tap "Create"
5. Group conversation created
6. System message: "You created this group"
```

### Adding Participants

```swift
// Requirements
- Only users with `can_add_members = true`
- Creator always has permission
- Can optionally grant permission to others

// Flow
1. Open conversation info
2. Tap "Add Participants"
3. Search/select users
4. Tap "Add"
5. System message: "You added [Name] to the conversation"
6. New participant sees full message history
```

### Removing Participants

```swift
// Requirements
- Can remove yourself (leave)
- Can remove others if `can_remove_members = true`
- Cannot remove conversation creator

// Flow
1. Open conversation info
2. Swipe on participant → "Remove"
3. Confirm removal
4. System message: "You removed [Name] from the conversation"
5. Removed user can no longer see new messages
6. Removed user keeps old message history
```

### Renaming Conversation

```swift
// Requirements
- Only users with `can_rename = true`
- Creator always has permission

// Flow
1. Open conversation info
2. Tap "Change Group Name"
3. Enter new name
4. Tap "Save"
5. System message: "You renamed the group to [New Name]"
6. All participants see updated name
```

---

## 7.3 System Messages

### System Message Types

```swift
enum SystemEventType: String, Codable {
    case conversationCreated = "conversation_created"
    case conversationRenamed = "conversation_renamed"
    case userAdded = "user_added"
    case userRemoved = "user_removed"
    case userLeft = "user_left"
    case photoChanged = "photo_changed"
    
    var displayText: String {
        switch self {
        case .conversationCreated:
            return "Group created"
        case .conversationRenamed:
            return "Group renamed"
        case .userAdded:
            return "was added to the group"
        case .userRemoved:
            return "was removed from the group"
        case .userLeft:
            return "left the conversation"
        case .photoChanged:
            return "changed the group photo"
        }
    }
}
```

### Display Rules

- System messages appear in center of conversation
- Smaller, gray, italic text
- No reactions allowed
- No avatar shown
- Example: "Sarah added Mike to the group"

---

## 7.4 Read Receipts

### Behavior

1. **Individual Conversations**:
   - "Delivered" shown when message reaches server
   - "Read" shown when recipient opens conversation
   - Timestamp shown with read receipt

2. **Group Conversations**:
   - "Read" shown when ALL participants have read
   - Tap "Read" to see who has/hasn't read
   - Modal shows list:
     ```
     Read by:
     ✓ Sarah (2:30 PM)
     ✓ Mike (2:32 PM)
     
     Not yet read:
     • Tom
     ```

### Privacy Consideration

- Users cannot disable read receipts (iMessage parity)
- Read receipts help coordination for ride/favor requests

---

## 7.5 Typing Indicators

### Implementation

1. **Triggering**:
   - Start typing → Send presence update
   - Stop typing for 3 seconds → Clear presence
   - Send message → Clear presence

2. **Display**:
   - Single person: "Sarah is typing..."
   - Two people: "Sarah and Mike are typing..."
   - Three+ people: "Several people are typing..."

3. **Animation**:
   - Three dots bouncing animation
   - Appears above input bar
   - Fades in/out smoothly

4. **Performance**:
   - Debounced (don't send on every keystroke)
   - Only sent when actively typing
   - Automatically cleared on app background

---

# 8. Push Notifications

## 8.1 Notification Triggers

```swift
// Send push notification when:
1. New message received
2. User mentioned in group chat (future enhancement)
3. Someone reacts to your message
```

## 8.2 Notification Payload

```swift
// APNs payload structure
{
  "aps": {
    "alert": {
      "title": "Sarah Johnson",
      "subtitle": "Capitol Hill → Airport",
      "body": "Hey, are you free tomorrow?"
    },
    "badge": 3,  // Unread count
    "sound": "default",
    "category": "MESSAGE"
  },
  "conversation_id": "uuid-here",
  "message_id": "uuid-here"
}
```

## 8.3 Notification Actions

```swift
// Interactive notifications
UNNotificationCategory(
    identifier: "MESSAGE",
    actions: [
        UNTextInputNotificationAction(
            identifier: "REPLY",
            title: "Reply",
            options: []
        ),
        UNNotificationAction(
            identifier: "MARK_READ",
            title: "Mark as Read",
            options: []
        )
    ],
    intentIdentifiers: []
)
```

## 8.4 Handling Notification Tap

```swift
// When user taps notification:
1. App opens
2. Navigate to ConversationDetailView(conversationId)
3. Mark conversation as read
4. Scroll to new messages
```

## 8.5 Notification Grouping

```swift
// Group notifications by conversation
"thread-id": "conversation-{conversationId}"

// iOS will group:
Sarah Johnson (3 messages)
├─ "Hey, are you free tomorrow?"
├─ "Let me know!"
└─ "🚗"
```

---

# 9. Image Handling

## 9.1 Image Selection Flow

```swift
1. User taps camera icon in input bar
2. PhotosPicker sheet appears
3. User selects image
4. Image compressed to max 1MB
5. Thumbnail created (200x200)
6. Upload both to Supabase Storage
7. Create message record with URLs
8. Display in conversation
```

## 9.2 Image Compression

```swift
// Core/Services/ImageService.swift

final class ImageService {
    static func compressImage(_ image: UIImage, maxSizeKB: Int) throws -> Data {
        var compression: CGFloat = 1.0
        var imageData = image.jpegData(compressionQuality: compression)!
        
        while imageData.count > maxSizeKB * 1024 && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)!
        }
        
        guard imageData.count <= maxSizeKB * 1024 else {
            throw ImageError.compressionFailed
        }
        
        return imageData
    }
    
    static func createThumbnail(from imageData: Data, size: CGSize) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw ImageError.invalidImage
        }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) else {
            throw ImageError.thumbnailFailed
        }
        
        return thumbnailData
    }
}

enum ImageError: Error {
    case compressionFailed
    case invalidImage
    case thumbnailFailed
}
```

## 9.3 Image Display

```swift
// In conversation:
- Show thumbnail initially
- Tap to view full size
- Pinch to zoom
- Swipe to dismiss

// Full screen viewer:
AsyncImage(url: fullSizeURL)
    .resizable()
    .aspectRatio(contentMode: .fit)
    .pinchToZoom()
```

## 9.4 Storage Structure

```
supabase-storage/
  messages/
    {conversation-id}/
      {message-id}.jpg          // Full size
      {message-id}_thumb.jpg    // Thumbnail
```

---

# 10. Edge Cases & Error Handling

## 10.1 Network Errors

### Scenario: Message fails to send

```swift
// Handle in ViewModel
do {
    try await messageService.sendTextMessage(...)
} catch {
    // Show error banner
    showError("Failed to send message. Tap to retry.")
    
    // Keep message in failed state
    failedMessages.append(message)
}

// Retry mechanism
func retryFailedMessage(_ message: Message) {
    // Remove from failed list
    // Attempt send again
}
```

### Scenario: Realtime connection drops

```swift
// RealtimeManager handles automatically
- Supabase client auto-reconnects
- Missed messages fetched on reconnect
- No user action required
```

## 10.2 Data Integrity

### Scenario: Duplicate messages

```swift
// Prevention
- Use message ID for deduplication
- Check if message already exists before adding

if !messages.contains(where: { $0.id == newMessage.id }) {
    messages.append(newMessage)
}
```

### Scenario: Out-of-order messages

```swift
// Solution
- Always sort by created_at
- Use stable sort to preserve order
- Scroll to correct position on new message
```

## 10.3 User Experience

### Scenario: User deleted from conversation while viewing

```swift
// Detection
- Realtime subscription becomes invalid
- Participant fetch returns 403

// Handling
- Show alert: "You are no longer in this conversation"
- Navigate back to conversations list
- Remove from local cache
```

### Scenario: Conversation deleted

```swift
// For request conversations:
- Ride/favor completed → Archive conversation
- Ride/favor cancelled → Keep conversation

// For direct/group:
- "Leave" = Remove yourself as participant
- Cannot delete conversation (other users need history)
```

## 10.4 Rate Limiting

### Message Send Rate Limit

```swift
// Enforce client-side
private var lastMessageSentAt: Date?

func sendMessage() async {
    // Limit to 1 message per second
    if let lastSent = lastMessageSentAt,
       Date().timeIntervalSince(lastSent) < 1.0 {
        showError("Please slow down")
        return
    }
    
    lastMessageSentAt = Date()
    // ... proceed with send
}
```

### Server-side Rate Limit

```sql
-- In Supabase Edge Function (future enhancement)
CREATE TABLE rate_limits (
    user_id UUID PRIMARY KEY,
    messages_sent_count INTEGER DEFAULT 0,
    window_start TIMESTAMPTZ DEFAULT NOW()
);

-- Limit: 60 messages per minute
-- Enforced via database constraint
```

---

# 11. Performance Requirements

## 11.1 Load Times

| Operation | Target | Notes |
|-----------|--------|-------|
| Open conversation list | < 1s | Including unread counts |
| Open conversation | < 1s | Load last 50 messages |
| Send message | < 500ms | Optimistic UI |
| Receive message (realtime) | < 2s | From send to display |
| Load older messages | < 1s | Paginated |
| Upload image | < 5s | 1MB file |

## 11.2 Memory Management

```swift
// Limit messages in memory
private let maxMessagesInMemory = 200

func addMessage(_ message: Message) {
    messages.append(message)
    
    // Trim old messages
    if messages.count > maxMessagesInMemory {
        messages.removeFirst(messages.count - maxMessagesInMemory)
    }
}
```

## 11.3 Database Query Optimization

```sql
-- Essential indexes (already included in schema)
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_conversations_updated ON conversations(updated_at DESC);
CREATE INDEX idx_conv_participants_user ON conversation_participants(user_id);

-- Query optimization
- Use LIMIT on message queries
- Paginate with created_at < cursor
- Only fetch active participants (left_at IS NULL)
```

## 11.4 Realtime Performance

```swift
// Best practices
1. Subscribe only to active conversation
2. Unsubscribe when leaving view
3. Use presence for ephemeral data (typing)
4. Debounce typing indicator sends
5. Batch read receipts (mark all as read vs individual)
```

---

# 12. Implementation Phases

## Phase 1: Core Messaging (Week 1-2)

### Deliverables
- [ ] Database schema implemented
- [ ] MessageService with send/receive
- [ ] ConversationService with CRUD
- [ ] Basic conversation list view
- [ ] Basic conversation detail view
- [ ] Text messages only
- [ ] Realtime message delivery
- [ ] Basic UI (no polish)

### Testing
- [ ] Can create direct conversation
- [ ] Can send text messages
- [ ] Messages appear in realtime
- [ ] Unread counts update
- [ ] Messages persist across app restart

---

## Phase 2: Group Features (Week 3)

### Deliverables
- [ ] Create group conversations
- [ ] Add/remove participants
- [ ] Rename conversations
- [ ] Participant permissions
- [ ] System messages
- [ ] Group UI components

### Testing
- [ ] Can create groups
- [ ] Can add participants
- [ ] Can remove participants
- [ ] Permissions enforced
- [ ] System messages appear correctly

---

## Phase 3: Reactions & Images (Week 4)

### Deliverables
- [ ] Reaction system (add/remove)
- [ ] Reaction UI (chips, picker)
- [ ] Image upload
- [ ] Image compression
- [ ] Image display in chat
- [ ] Full-screen image viewer

### Testing
- [ ] Can add reactions
- [ ] Can remove reactions
- [ ] Multiple users can react
- [ ] Images upload successfully
- [ ] Images display correctly
- [ ] Image compression works

---

## Phase 4: Push Notifications (Week 5)

### Deliverables
- [ ] APNs configuration
- [ ] Notification permissions
- [ ] Send notifications on new message
- [ ] Notification tap handling
- [ ] Badge count management
- [ ] Notification grouping

### Testing
- [ ] Notifications received
- [ ] Badge count accurate
- [ ] Tapping notification opens conversation
- [ ] Notifications grouped correctly

---

## Phase 5: Polish & Edge Cases (Week 6)

### Deliverables
- [ ] Typing indicators
- [ ] Read receipts
- [ ] Error handling
- [ ] Loading states
- [ ] Empty states
- [ ] Animations
- [ ] Accessibility
- [ ] Dark mode support

### Testing
- [ ] Typing indicators work
- [ ] Read receipts accurate
- [ ] Errors handled gracefully
- [ ] Loading states smooth
- [ ] Animations feel native
- [ ] VoiceOver works
- [ ] Dark mode looks good

---

# Appendix A: Models

## Complete Model Definitions

```swift
// Core/Models/Conversation.swift
struct Conversation: Codable, Identifiable {
    let id: UUID
    var title: String?
    let createdBy: UUID
    let createdAt: Date
    var updatedAt: Date
    let rideId: UUID?
    let favorId: UUID?
    let conversationType: ConversationType
    var isArchived: Bool
    var lastMessageAt: Date?
    var lastMessagePreview: String?
}

enum ConversationType: String, Codable {
    case direct
    case group
    case request
}

// Core/Models/ConversationParticipant.swift
struct ConversationParticipant: Codable {
    let conversationId: UUID
    let userId: UUID
    let joinedAt: Date
    let addedBy: UUID?
    var leftAt: Date?
    let role: ParticipantRole
    let canAddMembers: Bool
    let canRemoveMembers: Bool
    let canRename: Bool
    var lastReadMessageId: UUID?
    var lastReadAt: Date?
    var unreadCount: Int
    var notificationsEnabled: Bool
    var isMuted: Bool
    var mutedUntil: Date?
}

enum ParticipantRole: String, Codable {
    case creator
    case admin
    case member
}

// Core/Models/Message.swift
struct Message: Codable, Identifiable {
    let id: UUID
    let conversationId: UUID
    let fromUserId: UUID
    let contentType: MessageContentType
    var textContent: String?
    var imageUrl: String?
    var imageThumbnailUrl: String?
    var systemEventType: SystemEventType?
    var systemEventData: [String: Any]?
    let createdAt: Date
    var updatedAt: Date?
    var isDeleted: Bool
    var replyToMessageId: UUID?
    
    // Joined data (not in DB)
    var reactions: [MessageReaction] = []
    var readBy: [UUID] = []
}

enum MessageContentType: String, Codable {
    case text
    case image
    case system
}

// Core/Models/MessageReaction.swift
struct MessageReaction: Codable, Identifiable {
    let messageId: UUID
    let userId: UUID
    let reactionType: ReactionType
    let createdAt: Date
    
    var id: String {
        "\(messageId)-\(userId)-\(reactionType.rawValue)"
    }
}

// Core/Models/ViewModels.swift
struct ConversationWithDetails: Identifiable {
    let conversation: Conversation
    let participants: [ParticipantWithProfile]
    let lastMessage: Message?
    let unreadCount: Int
    
    var id: UUID { conversation.id }
}

struct ParticipantWithProfile: Identifiable {
    let participant: ConversationParticipant
    let profile: Profile
    
    var id: UUID { participant.userId }
}
```

---

# Appendix B: Security Policies (RLS)

```sql
-- Conversations: Users can only see conversations they're in
CREATE POLICY "Users can view their conversations"
    ON conversations FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_id = conversations.id
            AND user_id = auth.uid()
            AND left_at IS NULL
        )
    );

-- Messages: Users can only see messages from their conversations
CREATE POLICY "Users can view messages in their conversations"
    ON messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_id = messages.conversation_id
            AND user_id = auth.uid()
            AND left_at IS NULL
        )
    );

-- Messages: Users can only send as themselves
CREATE POLICY "Users can send messages"
    ON messages FOR INSERT
    WITH CHECK (
        from_user_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_id = messages.conversation_id
            AND user_id = auth.uid()
            AND left_at IS NULL
        )
    );

-- Reactions: Users can manage their own reactions
CREATE POLICY "Users can manage their reactions"
    ON message_reactions FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Read receipts: Users can create their own read receipts
CREATE POLICY "Users can create read receipts"
    ON message_read_receipts FOR INSERT
    WITH CHECK (user_id = auth.uid());
```

---

# Summary

This technical specification provides a complete blueprint for implementing an iMessage-style messaging system in Naar's Cars. Key highlights:

✅ **Complete database schema** with all tables and relationships
✅ **Full API layer** with MessageService and ConversationService
✅ **Centralized realtime** management via RealtimeManager
✅ **Comprehensive state management** with ViewModels
✅ **Detailed UI/UX specifications** for all screens
✅ **Feature-complete** group messaging with add/remove/rename
✅ **Reactions system** with 6 reaction types
✅ **Image handling** with compression and thumbnails
✅ **Push notifications** with interactive actions
✅ **Edge case handling** and error recovery
✅ **Performance requirements** and optimization
✅ **6-week implementation plan** broken into phases

**Estimated Development Time**: 6 weeks (150-180 hours)

**Next Steps**:
1. Review and approve this specification
2. Begin Phase 1: Core Messaging
3. Set up database schema in Supabase production
4. Implement services layer
5. Build UI components

