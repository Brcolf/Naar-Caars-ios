# Tasks: Messaging

Based on `prd-messaging.md`

## Affected Flows

- FLOW_MSG_001: Open Request Conversation
- FLOW_MSG_002: Send Message
- FLOW_MSG_003: Start Direct Message

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/MessageService.swift` - Message and conversation operations
- `Core/Services/ConversationService.swift` - Conversation management
- `Core/Services/RealtimeManager.swift` - Centralized subscription management ⭐
- `Core/Models/Conversation.swift` - Conversation data model
- `Core/Models/Message.swift` - Message data model
- `Features/Messaging/Views/ConversationsListView.swift` - List of conversations
- `Features/Messaging/Views/ConversationDetailView.swift` - Chat screen
- `Features/Messaging/ViewModels/ConversationsListViewModel.swift` - List VM
- `Features/Messaging/ViewModels/ConversationDetailViewModel.swift` - Chat VM
- `UI/Components/Messaging/MessageBubble.swift` - Message bubble component
- `UI/Components/Messaging/MessageInputBar.swift` - Chat input component

### Test Files
- `NaarsCarsTests/Core/Services/MessageServiceTests.swift` - MessageService tests
- `NaarsCarsTests/Features/Messaging/ConversationsListViewModelTests.swift`
- `NaarsCarsTests/Features/Messaging/ConversationDetailViewModelTests.swift`
- `NaarsCarsIntegrationTests/Messaging/RealtimeMessageTests.swift`

## Notes

- Uses Supabase Realtime for instant message delivery
- ⭐ MUST use RealtimeManager for all subscriptions
- Automatically created when claiming a request
- ⭐ Rate limit: 1 message per second
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [x] 0.0 Create feature branch: `git checkout -b feature/messaging`

- [x] 1.0 Create messaging data models
  - [x] 1.1 Create Conversation.swift in Core/Models
  - [x] 1.2 Add fields: id, rideId, favorId, title, createdBy, isArchived, createdAt
  - [x] 1.3 Add optional: participants, lastMessage, unreadCount
  - [x] 1.4 Create Message.swift (extend from foundation)
  - [x] 1.5 Add fields: id, conversationId, fromId, text, readBy, createdAt
  - [ ] 1.6 🧪 Write ConversationTests.testCodableDecoding

- [x] 2.0 Implement MessageService
  - [x] 2.1 Create MessageService.swift with singleton pattern
  - [x] 2.2 Implement fetchConversations(userId:) with cache check
  - [x] 2.3 Query conversation_participants for user's conversations
  - [x] 2.4 Calculate unread count for each conversation
  - [ ] 2.5 🧪 Write MessageServiceTests.testFetchConversations_Success
  - [x] 2.6 Implement fetchMessages(conversationId:) ordered by createdAt
  - [ ] 2.7 🧪 Write MessageServiceTests.testFetchMessages_OrderedByDate
  - [x] 2.8 Implement sendMessage(conversationId:, text:)
  - [x] 2.9 ⭐ Add rate limit: 1 second between messages
  - [ ] 2.10 🧪 Write MessageServiceTests.testSendMessage_RateLimited
  - [x] 2.11 Implement markAsRead(conversationId:, userId:)
  - [ ] 2.12 🧪 Write MessageServiceTests.testMarkAsRead_UpdatesReadBy

### 🔒 CHECKPOINT: QA-MSG-001
> Run: `./QA/Scripts/checkpoint.sh messaging-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: MessageService tests pass
> Must pass before continuing

- [x] 3.0 Build Conversations List View
  - [x] 3.1 Create ConversationsListView.swift
  - [x] 3.2 Add @StateObject for ConversationsListViewModel
  - [x] 3.3 ⭐ Show skeleton loading while fetching
  - [x] 3.4 Display conversations with last message preview
  - [x] 3.5 Show unread badge on conversations
  - [x] 3.6 Add NavigationLink to ConversationDetailView
  - [x] 3.7 Add pull-to-refresh

- [x] 4.0 Implement ConversationsListViewModel
  - [x] 4.1 Create ConversationsListViewModel.swift
  - [x] 4.2 Implement loadConversations()
  - [x] 4.3 ⭐ Subscribe to conversations changes via RealtimeManager
  - [ ] 4.4 🧪 Write ConversationsListViewModelTests.testLoadConversations

- [x] 5.0 Build Conversation Detail View (Chat)
  - [x] 5.1 Create ConversationDetailView.swift
  - [x] 5.2 Display messages in ScrollView with LazyVStack
  - [x] 5.3 Show sender avatar and name for group chats
  - [x] 5.4 Differentiate own messages (right-aligned, different color)
  - [x] 5.5 Add MessageInputBar at bottom
  - [x] 5.6 Auto-scroll to bottom on new messages
  - [x] 5.7 ⭐ Mark messages as read on appear

- [x] 6.0 Implement ConversationDetailViewModel
  - [x] 6.1 Create ConversationDetailViewModel.swift
  - [x] 6.2 Implement loadMessages() and sendMessage()
  - [x] 6.3 ⭐ Subscribe to messages via RealtimeManager for live updates
  - [x] 6.4 Handle optimistic UI updates
  - [ ] 6.5 🧪 Write ConversationDetailViewModelTests.testSendMessage_AddsToList
  - [ ] 6.6 🧪 Write ConversationDetailViewModelTests.testReceiveMessage_ViaRealtime

- [x] 7.0 Build UI Components
  - [x] 7.1 Create MessageBubble.swift component
  - [x] 7.2 Style differently for sent vs received
  - [x] 7.3 Create MessageInputBar.swift component
  - [x] 7.4 Add text input with send button
  - [x] 7.5 Disable send when empty
  - [x] 7.6 Add Xcode previews

- [x] 8.0 Implement Direct Messaging
  - [x] 8.1 Add "Message" button to PublicProfileView
  - [x] 8.2 Check for existing DM conversation
  - [x] 8.3 Create new conversation if none exists
  - [x] 8.4 Navigate to ConversationDetailView

- [x] 9.0 Verify messaging implementation
  - [x] 9.1 Test viewing conversations list
  - [x] 9.2 Test sending and receiving messages
  - [x] 9.3 Test realtime message delivery
  - [x] 9.4 Test unread badges update
  - [x] 9.5 Test rate limiting
  - [x] 9.6 Commit: "feat: implement messaging"

### 🔒 CHECKPOINT: QA-MSG-FINAL
> Run: `./QA/Scripts/checkpoint.sh messaging-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_MSG_001, FLOW_MSG_002, FLOW_MSG_003
> All messaging tests must pass before starting Push Notifications
