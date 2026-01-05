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

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/messaging`

- [ ] 1.0 Create messaging data models
  - [ ] 1.1 Create Conversation.swift in Core/Models
  - [ ] 1.2 Add fields: id, rideId, favorId, title, createdBy, isArchived, createdAt
  - [ ] 1.3 Add optional: participants, lastMessage, unreadCount
  - [ ] 1.4 Create Message.swift (extend from foundation)
  - [ ] 1.5 Add fields: id, conversationId, fromId, text, readBy, createdAt
  - [ ] 1.6 🧪 Write ConversationTests.testCodableDecoding

- [ ] 2.0 Implement MessageService
  - [ ] 2.1 Create MessageService.swift with singleton pattern
  - [ ] 2.2 Implement fetchConversations(userId:) with cache check
  - [ ] 2.3 Query conversation_participants for user's conversations
  - [ ] 2.4 Calculate unread count for each conversation
  - [ ] 2.5 🧪 Write MessageServiceTests.testFetchConversations_Success
  - [ ] 2.6 Implement fetchMessages(conversationId:) ordered by createdAt
  - [ ] 2.7 🧪 Write MessageServiceTests.testFetchMessages_OrderedByDate
  - [ ] 2.8 Implement sendMessage(conversationId:, text:)
  - [ ] 2.9 ⭐ Add rate limit: 1 second between messages
  - [ ] 2.10 🧪 Write MessageServiceTests.testSendMessage_RateLimited
  - [ ] 2.11 Implement markAsRead(conversationId:, userId:)
  - [ ] 2.12 🧪 Write MessageServiceTests.testMarkAsRead_UpdatesReadBy

### 🔒 CHECKPOINT: QA-MSG-001
> Run: `./QA/Scripts/checkpoint.sh messaging-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: MessageService tests pass
> Must pass before continuing

- [ ] 3.0 Build Conversations List View
  - [ ] 3.1 Create ConversationsListView.swift
  - [ ] 3.2 Add @StateObject for ConversationsListViewModel
  - [ ] 3.3 ⭐ Show skeleton loading while fetching
  - [ ] 3.4 Display conversations with last message preview
  - [ ] 3.5 Show unread badge on conversations
  - [ ] 3.6 Add NavigationLink to ConversationDetailView
  - [ ] 3.7 Add pull-to-refresh

- [ ] 4.0 Implement ConversationsListViewModel
  - [ ] 4.1 Create ConversationsListViewModel.swift
  - [ ] 4.2 Implement loadConversations()
  - [ ] 4.3 ⭐ Subscribe to conversations changes via RealtimeManager
  - [ ] 4.4 🧪 Write ConversationsListViewModelTests.testLoadConversations

- [ ] 5.0 Build Conversation Detail View (Chat)
  - [ ] 5.1 Create ConversationDetailView.swift
  - [ ] 5.2 Display messages in ScrollView with LazyVStack
  - [ ] 5.3 Show sender avatar and name for group chats
  - [ ] 5.4 Differentiate own messages (right-aligned, different color)
  - [ ] 5.5 Add MessageInputBar at bottom
  - [ ] 5.6 Auto-scroll to bottom on new messages
  - [ ] 5.7 ⭐ Mark messages as read on appear

- [ ] 6.0 Implement ConversationDetailViewModel
  - [ ] 6.1 Create ConversationDetailViewModel.swift
  - [ ] 6.2 Implement loadMessages() and sendMessage()
  - [ ] 6.3 ⭐ Subscribe to messages via RealtimeManager for live updates
  - [ ] 6.4 Handle optimistic UI updates
  - [ ] 6.5 🧪 Write ConversationDetailViewModelTests.testSendMessage_AddsToList
  - [ ] 6.6 🧪 Write ConversationDetailViewModelTests.testReceiveMessage_ViaRealtime

- [ ] 7.0 Build UI Components
  - [ ] 7.1 Create MessageBubble.swift component
  - [ ] 7.2 Style differently for sent vs received
  - [ ] 7.3 Create MessageInputBar.swift component
  - [ ] 7.4 Add text input with send button
  - [ ] 7.5 Disable send when empty
  - [ ] 7.6 Add Xcode previews

- [ ] 8.0 Implement Direct Messaging
  - [ ] 8.1 Add "Message" button to PublicProfileView
  - [ ] 8.2 Check for existing DM conversation
  - [ ] 8.3 Create new conversation if none exists
  - [ ] 8.4 Navigate to ConversationDetailView

- [ ] 9.0 Verify messaging implementation
  - [ ] 9.1 Test viewing conversations list
  - [ ] 9.2 Test sending and receiving messages
  - [ ] 9.3 Test realtime message delivery
  - [ ] 9.4 Test unread badges update
  - [ ] 9.5 Test rate limiting
  - [ ] 9.6 Commit: "feat: implement messaging"

### 🔒 CHECKPOINT: QA-MSG-FINAL
> Run: `./QA/Scripts/checkpoint.sh messaging-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_MSG_001, FLOW_MSG_002, FLOW_MSG_003
> All messaging tests must pass before starting Push Notifications
