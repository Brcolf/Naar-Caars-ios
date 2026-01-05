# PRD: Messaging

## Document Information
- **Feature Name**: Messaging
- **Phase**: 2 (Communication)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`, `prd-request-claiming.md`
- **Estimated Effort**: 1.5-2 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines the messaging system for Naar's Cars. Messaging enables communication between requesters and helpers to coordinate ride/favor details.

### Why does this matter?
After claiming a request, users need to coordinate specifics like exact pickup location, timing changes, or special instructions. Real-time messaging is essential for a good experience.

### What problem does it solve?
- Users need to communicate without sharing personal phone numbers initially
- Coordination details for rides/favors
- Group communication when multiple co-requesters are involved
- Direct messaging between any community members

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Real-time message delivery | Messages appear instantly |
| Conversation per request | Each ride/favor has dedicated chat |
| Direct messaging | Users can DM any community member |
| Group conversations | Support multiple participants |
| Unread indicators | Badge shows unread count |
| Message history | All messages persist |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| MSG-01 | Claimer | Message the poster | I can coordinate details |
| MSG-02 | Poster | Message my helper | I can provide updates |
| MSG-03 | User | See unread message count | I know I have new messages |
| MSG-04 | User | Start a direct message | I can contact anyone |
| MSG-05 | User | See message history | I can reference past discussions |
| MSG-06 | Co-requestor | Participate in group chat | We all stay coordinated |
| MSG-07 | User | Receive push notification | I'm alerted to new messages |
| MSG-08 | User | Share images in chat | I can send photos |

---

## 4. Functional Requirements

### 4.1 Data Models

**Requirement MSG-FR-001**: Conversation model:

```swift
// Core/Models/Conversation.swift
struct Conversation: Codable, Identifiable {
    let id: UUID
    let rideId: UUID?
    let favorId: UUID?
    var title: String?
    let createdBy: UUID
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // Computed
    var isActivityBased: Bool {
        rideId != nil || favorId != nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case favorId = "favor_id"
        case title
        case createdBy = "created_by"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

**Requirement MSG-FR-002**: Message model:

```swift
// Core/Models/Message.swift
struct Message: Codable, Identifiable {
    let id: UUID
    let conversationId: UUID
    let fromId: UUID
    var toId: UUID?  // Legacy, can be null
    let text: String
    var readBy: [UUID]?
    let createdAt: Date
    
    // Joined
    var sender: Profile?
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case fromId = "from_id"
        case toId = "to_id"
        case text
        case readBy = "read_by"
        case createdAt = "created_at"
    }
}
```

**Requirement MSG-FR-003**: ConversationParticipant model:

```swift
struct ConversationParticipant: Codable {
    let id: UUID
    let conversationId: UUID
    let userId: UUID
    let isAdmin: Bool
    let joinedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case userId = "user_id"
        case isAdmin = "is_admin"
        case joinedAt = "joined_at"
    }
}
```

---

### 4.2 Message Service

**Requirement MSG-FR-004**: MessageService implementation:

```swift
// Core/Services/MessageService.swift
@MainActor
final class MessageService {
    private let supabase = SupabaseService.shared.client
    static let shared = MessageService()
    private init() {}
    
    // MARK: - Conversations
    
    /// Fetch all conversations for current user
    func fetchConversations(userId: UUID) async throws -> [ConversationWithDetails] {
        // Get user's conversation IDs
        let participations = try await supabase
            .from("conversation_participants")
            .select("conversation_id")
            .eq("user_id", userId.uuidString)
            .execute()
        
        // Fetch conversations with latest message
        // ... implementation
    }
    
    /// Get or create direct conversation between two users
    func getOrCreateDirectConversation(userId: UUID, otherUserId: UUID) async throws -> Conversation {
        // Check for existing DM conversation
        // If none exists, create new one
        // ... implementation
    }
    
    /// Create new group conversation
    func createGroupConversation(creatorId: UUID, participantIds: [UUID], title: String?) async throws -> Conversation {
        // ... implementation
    }
    
    // MARK: - Messages
    
    /// Fetch messages for a conversation
    func fetchMessages(conversationId: UUID) async throws -> [Message] {
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
            .eq("conversation_id", conversationId.uuidString)
            .order("created_at", ascending: true)
            .execute()
        
        return try JSONDecoder().decode([Message].self, from: response.data)
    }
    
    /// Send a message
    func sendMessage(conversationId: UUID, fromId: UUID, text: String) async throws -> Message {
        let response = try await supabase
            .from("messages")
            .insert([
                "conversation_id": conversationId.uuidString,
                "from_id": fromId.uuidString,
                "text": text
            ])
            .select()
            .single()
            .execute()
        
        // Update conversation's updated_at
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", conversationId.uuidString)
            .execute()
        
        return try JSONDecoder().decode(Message.self, from: response.data)
    }
    
    /// Mark messages as read
    func markAsRead(conversationId: UUID, userId: UUID) async throws {
        // Fetch unread messages
        let response = try await supabase
            .from("messages")
            .select("id, read_by")
            .eq("conversation_id", conversationId.uuidString)
            .neq("from_id", userId.uuidString)
            .execute()
        
        struct MessageRow: Codable {
            let id: UUID
            let readBy: [UUID]?
            enum CodingKeys: String, CodingKey {
                case id
                case readBy = "read_by"
            }
        }
        
        let messages = try JSONDecoder().decode([MessageRow].self, from: response.data)
        
        for msg in messages {
            var readBy = msg.readBy ?? []
            if !readBy.contains(userId) {
                readBy.append(userId)
                try await supabase
                    .from("messages")
                    .update(["read_by": readBy.map { $0.uuidString }])
                    .eq("id", msg.id.uuidString)
                    .execute()
            }
        }
    }
    
    /// Get unread count for user
    func getUnreadCount(userId: UUID) async throws -> Int {
        // Get user's conversations
        // Count messages not from user and not in read_by
        // ... implementation
    }
}
```

---

### 4.3 Real-time Messages

**Requirement MSG-FR-005**: Messages MUST update in real-time using Supabase Realtime:

```swift
// In ConversationViewModel
func subscribeToMessages() {
    let channel = supabase.channel("messages:\(conversationId)")
    
    channel.on("postgres_changes",
               filter: ChannelFilter(
                   event: "INSERT",
                   schema: "public",
                   table: "messages",
                   filter: "conversation_id=eq.\(conversationId)"
               )) { [weak self] payload in
        Task { @MainActor in
            guard let self = self else { return }
            // Parse new message and append to list
            if let newMessage = self.parseMessage(from: payload) {
                self.messages.append(newMessage)
                self.scrollToBottom()
            }
        }
    }
    
    Task {
        await channel.subscribe()
    }
    
    self.realtimeChannel = channel
}
```

---

### 4.4 Conversation List View

**Requirement MSG-FR-006**: Conversations list wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Messages                    [+]   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ” Search messages...       â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Av][Av] ðŸš—               â€¢ â”‚   â”‚
â”‚   â”‚ John S., Jane D.       2m   â”‚   â”‚
â”‚   â”‚ Capitol Hill â†’ SEA          â”‚   â”‚
â”‚   â”‚ John: I'll be there at 7:45 â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar]                  3 â”‚   â”‚
â”‚   â”‚ Bob M.                  1h   â”‚   â”‚
â”‚   â”‚ Direct Message              â”‚   â”‚
â”‚   â”‚ Thanks for the help!        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] ðŸ› ï¸                  â”‚   â”‚
â”‚   â”‚ Sara K.                 2d   â”‚   â”‚
â”‚   â”‚ Help moving - Jan 11        â”‚   â”‚
â”‚   â”‚ You: No problem!            â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement MSG-FR-007**: Each conversation row MUST show:
- Participant avatar(s)
- Activity type icon (ðŸš—/ðŸ› ï¸) if activity-based
- Participant name(s)
- Time of last message
- Subject line (route for rides, title for favors, "Direct Message" for DMs)
- Last message preview (truncated)
- Unread badge (blue dot or count)

---

### 4.5 Conversation Detail View

**Requirement MSG-FR-008**: Conversation view wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ â† [Av][Av] John, Jane        [â„¹ï¸]  â”‚
â”‚   Capitol Hill â†’ SEA - Mon, Jan 6   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚         Monday, January 6           â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”           â”‚
â”‚   â”‚ Hi! I can pick you  â”‚  10:30 AM â”‚
â”‚   â”‚ up at 7:45. Does    â”‚           â”‚
â”‚   â”‚ that work?          â”‚           â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜           â”‚
â”‚                           [Avatar]  â”‚
â”‚                                     â”‚
â”‚              â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚    10:35 AM  â”‚ That's perfect!  â”‚   â”‚
â”‚              â”‚ Thanks so much!  â”‚   â”‚
â”‚              â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   [Avatar]                          â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”           â”‚
â”‚   â”‚ Great! See you then â”‚  10:36 AM â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜           â”‚
â”‚                           [Avatar]  â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [ðŸ“·]  Message...     [Send] â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement MSG-FR-009**: Message bubbles:
- Current user's messages: Right-aligned, accent color background
- Other users' messages: Left-aligned, gray background, show avatar
- Group indicator for sender in group chats
- Timestamps grouped by day

---

### 4.6 Message Input

**Requirement MSG-FR-010**: Message input MUST:
- Auto-grow to multiple lines (max 5)
- Support image attachment
- Send on Return key (with Shift+Return for newline)
- Show sending state
- Clear after send

```swift
struct MessageInputView: View {
    @Binding var text: String
    @State private var selectedImage: UIImage?
    let onSend: (String, UIImage?) -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Image picker button
            Button {
                // Show image picker
            } label: {
                Image(systemName: "camera.fill")
                    .foregroundColor(.secondary)
            }
            
            // Text input
            TextField("Message...", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
            
            // Send button
            Button {
                onSend(text, selectedImage)
                text = ""
                selectedImage = nil
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.isEmpty ? .secondary : .accentColor)
            }
            .disabled(text.isEmpty && selectedImage == nil)
        }
        .padding()
    }
}
```

---

### 4.7 New Conversation

**Requirement MSG-FR-011**: Users can start new direct conversations:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Ã—  New Message                    â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   To:                               â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ” Search people...         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Selected:                         â”‚
â”‚   [Avatar] John S.  Ã—               â”‚
â”‚   [Avatar] Jane D.  Ã—               â”‚
â”‚                                     â”‚
â”‚   Community Members:                â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] Bob M.         âœ“   â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ [Avatar] Sara K.            â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ [Avatar] Mike T.            â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚      Start Conversation     â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement MSG-FR-012**: If selecting one person who already has a DM conversation, navigate to existing conversation.

---

### 4.8 Unread Badges

**Requirement MSG-FR-013**: Unread message count MUST be shown:
- On Messages tab icon (total unread)
- On each conversation row (per-conversation unread)

**Requirement MSG-FR-014**: Messages are marked as read when:
- User opens the conversation
- User scrolls to see the message

---

### 4.9 Image Messages

**Requirement MSG-FR-015**: Image sharing MUST:
- Allow selecting from photo library
- Compress to max 1MB before sending
- Upload to Supabase Storage
- Display inline as image bubble
- Support tap to view full screen

---

## 5. Non-Goals

- Voice messages
- Video calling
- Message reactions/emoji
- Message editing
- Message deletion
- Typing indicators
- End-to-end encryption

---

## 6. Design Considerations

### iOS-Native Patterns

| Pattern | Implementation |
|---------|---------------|
| Native keyboard handling | Auto-scroll when keyboard appears |
| `ScrollViewReader` | Scroll to latest message |
| `PhotosPicker` | Image selection |
| Context menus | Long-press on messages (copy) |

### Improvements Over Web

| Web Behavior | iOS Improvement |
|--------------|-----------------|
| Manual refresh | Real-time with Supabase |
| Basic input | Multi-line with auto-grow |
| Toast for new message | Native push notification |

---

## 7. Technical Considerations

### Real-time Performance
- Subscribe only to active conversation
- Unsubscribe when leaving conversation
- Reconnect on app foreground

### Message Ordering
- Use `created_at` for sorting
- Handle optimistic UI (show sending state)
- Reconcile with server response

---

## 8. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`
- `prd-request-claiming.md`

### Used By
- `prd-notifications-push.md`

---

## 9. Success Metrics

| Metric | Target |
|--------|--------|
| Send message | Delivered in <1s |
| Real-time receive | Appears in <2s |
| Unread count | Updates correctly |
| Image send | Uploads and displays |

---

*End of PRD: Messaging*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 4.3 - Realtime Message Subscription

**Replace/enhance existing realtime subscription with:**

```markdown
### 4.3 Realtime Message Subscription

**Requirement MSG-FR-005**: Subscribe to realtime message updates using `RealtimeManager`:

```swift
// In ConversationViewModel
func subscribeToMessages() async {
    await RealtimeManager.shared.subscribe(
        channelName: "messages:\(conversationId)",
        table: "messages",
        filter: "conversation_id=eq.\(conversationId)",
        onInsert: { [weak self] payload in
            Task { @MainActor in
                self?.handleNewMessage(payload)
            }
        }
    )
}

func unsubscribeFromMessages() async {
    await RealtimeManager.shared.unsubscribe(
        channelName: "messages:\(conversationId)"
    )
}
```

**Requirement MSG-FR-005a**: Subscription cleanup MUST occur:
- When user navigates away from conversation (`onDisappear`)
- When conversation view is deallocated
- When app enters background (handled by `RealtimeManager`)

**Requirement MSG-FR-005b**: View implementation pattern:

```swift
struct ConversationView: View {
    @StateObject private var viewModel: ConversationViewModel
    
    var body: some View {
        // ... view content ...
        .task {
            await viewModel.loadMessages()
            await viewModel.subscribeToMessages()
        }
        .onDisappear {
            Task {
                await viewModel.unsubscribeFromMessages()
            }
        }
    }
}
```

**Requirement MSG-FR-005c**: NEVER create Supabase channels directly in views. Always use `RealtimeManager` to:
- Enforce max 3 concurrent subscriptions
- Handle app lifecycle automatically
- Provide consistent logging
```

---

## ADD: Section 4.4a - Message Rate Limiting

**Insert after section 4.4**

```markdown
### 4.4a Message Rate Limiting

**Requirement MSG-FR-004a**: Message sending MUST be rate-limited:

| Layer | Limit | Behavior |
|-------|-------|----------|
| Client-side | 1 second between messages | Disable send button |
| Server-side (recommended) | 10 messages per minute per conversation | Reject with error |

**Requirement MSG-FR-004b**: Client-side implementation:

```swift
func sendMessage() async {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }
    
    // Rate limit check
    guard await RateLimiter.shared.checkAndRecord(
        action: "send_message",
        minimumInterval: 1
    ) else {
        // Visual feedback only - no error alert
        HapticFeedback.warning()
        return
    }
    
    isSending = true
    defer { isSending = false }
    
    let text = messageText
    messageText = "" // Clear immediately for responsiveness
    
    do {
        try await MessageService.shared.sendMessage(
            conversationId: conversationId,
            text: text
        )
    } catch {
        // Restore message on failure
        messageText = text
        self.error = .unknown("Failed to send message")
    }
}
```

**Requirement MSG-FR-004c**: While rate-limited:
- Send button disabled (reduced opacity)
- No error dialog (avoid annoyance)
- Subtle haptic feedback if user taps disabled button

**Requirement MSG-FR-004d**: Server-side rate limiting (Edge Function, recommended for production):

```javascript
// Edge Function: send-message
const recentCount = await countRecentMessages(userId, conversationId, 60); // last 60 seconds
if (recentCount >= 10) {
    return { error: 'rate_limited', message: 'Sending too fast. Please slow down.' };
}
// ... send message ...
```
```

---

## REVISE: Section 4.9 - Image Messages

**Replace existing image message section with:**

```markdown
### 4.9 Image Messages

**Requirement MSG-FR-015**: Image sharing MUST use `ImageCompressor`:

```swift
func sendImageMessage(image: UIImage) async throws {
    // Compress using message preset
    guard let compressedData = ImageCompressor.compress(image, preset: .messageImage) else {
        throw AppError.unknown("Image too large to send")
    }
    
    isSending = true
    defer { isSending = false }
    
    // Upload to Supabase Storage
    let fileName = "\(conversationId.uuidString)/\(UUID().uuidString).jpg"
    
    try await supabase.storage
        .from("message-images")
        .upload(path: fileName, file: compressedData)
    
    let publicUrl = try supabase.storage
        .from("message-images")
        .getPublicURL(path: fileName)
    
    // Send message with image URL
    try await sendMessage(
        text: "[Image]",
        imageUrl: publicUrl.absoluteString
    )
}
```

**Requirement MSG-FR-015a**: Message image specifications:

| Property | Value |
|----------|-------|
| Max dimension | 1200px (longest side) |
| Max file size | 500KB |
| Format | JPEG |
| Quality | Auto-adjusted to meet size |

**Requirement MSG-FR-015b**: Show compression progress for large images:

```swift
func selectAndSendImage(_ image: UIImage) async {
    // Show preparing indicator
    imageUploadState = .preparing
    
    // Compress (may take a moment for large images)
    guard let data = await Task.detached(priority: .userInitiated) {
        ImageCompressor.compress(image, preset: .messageImage)
    }.value else {
        imageUploadState = .failed("Image too large")
        return
    }
    
    // Upload
    imageUploadState = .uploading
    
    do {
        try await uploadAndSend(data)
        imageUploadState = .idle
    } catch {
        imageUploadState = .failed(error.localizedDescription)
    }
}
```

**Requirement MSG-FR-015c**: Image upload states:

```swift
enum ImageUploadState {
    case idle
    case preparing      // "Preparing image..."
    case uploading      // "Sending..."
    case failed(String) // Show error
}
```
```

---

## ADD: Section 6.1 - Security Considerations

**Insert in Security section or create new section 6.1**

```markdown
### 6.1 Security Considerations

**Requirement MSG-SEC-001**: Message access controlled by RLS:
- Users can only read messages in conversations they're participants of
- Users can only send messages as themselves
- See `SECURITY.md` for RLS policy details

**Requirement MSG-SEC-002**: Message content validation:
- Max message length: 2000 characters (enforced client and server)
- Strip control characters except newlines
- No HTML/script injection (display as plain text)

```swift
func sanitizeMessageText(_ text: String) -> String {
    var sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized = String(sanitized.prefix(2000))
    // Remove control characters except newline
    sanitized = sanitized.filter { $0.isNewline || !$0.isASCII || $0.asciiValue! >= 32 }
    return sanitized
}
```

**Requirement MSG-SEC-003**: Image uploads:
- Only JPEG format accepted
- Virus scanning deferred to Supabase Storage (if enabled)
- Images served from Supabase CDN (no direct database storage)
```

---

*End of Messaging Addendum*
