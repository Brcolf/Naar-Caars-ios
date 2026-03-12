---
color: blue
position:
  x: -558
  y: -1419
isContextNode: false
agent_name: Amy
---

# Messaging Module

Full-featured chat system with iMessage-like capabilities.

## Architecture

### Views
- **ConversationsListView** - Inbox with search, badges, swipe actions
- **ConversationDetailView** - Message thread with UICollectionView (custom `MessagesCollectionView`)
- **MessageBubble** - Rich message rendering (text, images, audio, location, replies, reactions)
- **MessageInputBar** - Compose with attachments, voice, location
- **ConversationMediaGalleryView** - Photo browser

### ViewModels
- **ConversationsListViewModel** - Loads conversations with last message, unread counts
- **ConversationDetailViewModel** - Message thread logic with optimistic sending
- **ConversationSearchManager** - Full-text message search
- **TypingIndicatorManager** - Real-time typing presence

### Services
- **ConversationService** - CRUD for conversations
- **MessageService** - Send/edit/delete/react to messages
- **MessageMediaService** - Upload images/audio to Supabase Storage
- **ConversationParticipantService** - Manage participants, last seen

### Storage
- **MessagingRepository** - SwiftData abstraction for messages/conversations
- **MessagingSyncEngine** - Realtime sync from Supabase
- **MessageSendWorker** - Durable background message sending

## Features

✅ **Message Types**: Text, images, audio recordings, location sharing, system messages
✅ **Reactions**: Emoji reactions with aggregated counts
✅ **Replies**: Thread context with quoted messages
✅ **Edit & Unsend**: 15-minute window for message corrections
✅ **Read Receipts**: Track which participants have read messages
✅ **Typing Indicators**: Real-time presence via Supabase Realtime broadcast
✅ **Media Gallery**: Photo/video browser with swipe gestures
✅ **Search**: Full-text search across all messages
✅ **Local-First**: Optimistic sending with retry on failure

## Recent Improvements (Feb 6, 2026)

Per `Docs/COMPREHENSIVE_FIX_SUMMARY.md`:
- ✅ Fixed message pagination and scroll jumpiness
- ✅ Resolved context menu latency
- ✅ Fixed reply color rendering
- ✅ Improved keyboard handling and scroll-to-bottom
- ✅ Added database indexes for message search and badge counts

## Known Issues

### 🔴 Main Thread Sorting (High Priority)
`ConversationDetailViewModel` sorts messages on `@MainActor` during initial load. For large conversations (>1000 messages), this causes UI lag.

**From STRUCTURAL_HANDOFF_AUDIT.md:**
> While `insertionIndex` (binary search) was added for *new* messages, the initial load still performs a full sort on the main thread.

**Recommendation:** Move sorting to background `actor` or `Task.detached`.

### 🟡 Optimistic ID Reconciliation (Medium Priority)
Complex `optimisticIdMap` logic to match local temporary UUIDs with server-assigned IDs. Prone to state desync if WebSocket messages arrive out of order.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
