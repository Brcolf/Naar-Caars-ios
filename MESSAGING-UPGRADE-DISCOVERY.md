# Messaging Upgrade Discovery Document

**Date:** January 2026  
**PRD Reference:** `PRDs/naars-cars-messaging-prd.md`

---

## 📊 Executive Summary

The Naars Cars messaging system has a **solid foundation** with most core features already implemented. The upgrade path focuses on:

1. **Completing Group Chat** (Priority #1) - Missing: leave group, remove participants, group avatars
2. **iMessage Polish** - Better bubble styling, animations, profile pictures in groups
3. **New Features** - Typing indicators, swipe-to-reply, message threading
4. **Advanced Media** - Audio messages, location sharing, link previews

**Risk Level:** LOW - The existing architecture is clean and extensible.

---

## 🗂️ Current Implementation Map

### Models (Core/Models/)

| File | Status | Purpose |
|------|--------|---------|
| `Message.swift` | ✅ Complete | Text, images, reactions, read tracking |
| `Conversation.swift` | ✅ Complete | 1:1 and group support, participants, titles |
| `MessageReaction.swift` | ✅ Complete | 6 reaction types with validation |
| `Profile.swift` | ✅ Complete | User profiles with avatar support |

### Services (Core/Services/)

| File | Status | Purpose |
|------|--------|---------|
| `MessageService.swift` | ✅ Complete | All CRUD operations, pagination, rate limiting |
| `RealtimeManager.swift` | ✅ Complete | Centralized subscriptions, max 3 channels |
| `CacheManager.swift` | ✅ Complete | In-memory caching for conversations/messages |
| `ImageCompressor.swift` | ✅ Complete | Message image compression |

### Views (Features/Messaging/Views/)

| File | Status | Purpose |
|------|--------|---------|
| `ConversationsListView.swift` | ✅ Complete | List with pagination, swipe actions |
| `ConversationDetailView.swift` | ✅ Complete | Chat with images, reactions |
| `MessageDetailsPopup.swift` | ⚠️ Partial | Title editing, add participants (no remove) |

### UI Components (UI/Components/Messaging/)

| File | Status | Purpose |
|------|--------|---------|
| `MessageBubble.swift` | ⚠️ Basic | Needs iMessage polish, animations |
| `MessageInputBar.swift` | ⚠️ Basic | Works but needs enhancements |
| `UserSearchView.swift` | ✅ Complete | Multi-select user search |
| `ReactionPicker.swift` | ✅ Complete | 6-reaction picker |

### ViewModels (Features/Messaging/ViewModels/)

| File | Status | Purpose |
|------|--------|---------|
| `ConversationsListViewModel.swift` | ✅ Complete | Real-time updates, pagination |
| `ConversationDetailViewModel.swift` | ✅ Complete | Optimistic UI, deduplication |

---

## 🗄️ Database Schema Analysis

### Existing Tables

#### `conversations`
```sql
- id: UUID PRIMARY KEY
- title: TEXT (nullable, for group names)
- created_by: UUID REFERENCES profiles(id)
- is_archived: BOOLEAN DEFAULT false (not in DB yet!)
- created_at: TIMESTAMPTZ
- updated_at: TIMESTAMPTZ
```

#### `conversation_participants`
```sql
- id: UUID PRIMARY KEY
- conversation_id: UUID REFERENCES conversations(id)
- user_id: UUID REFERENCES profiles(id)
- is_admin: BOOLEAN DEFAULT false
- joined_at: TIMESTAMPTZ
- last_seen: TIMESTAMPTZ (nullable)
```

#### `messages`
```sql
- id: UUID PRIMARY KEY
- conversation_id: UUID REFERENCES conversations(id)
- from_id: UUID REFERENCES profiles(id)
- text: TEXT
- image_url: TEXT (nullable)
- read_by: UUID[] (array)
- created_at: TIMESTAMPTZ
```

#### `message_reactions`
```sql
- id: UUID PRIMARY KEY
- message_id: UUID REFERENCES messages(id) ON DELETE CASCADE
- user_id: UUID REFERENCES profiles(id) ON DELETE CASCADE
- reaction: TEXT CHECK (reaction IN ('👍', '👎', '❤️', '😂', '‼️', 'HaHa'))
- created_at: TIMESTAMPTZ
- UNIQUE(message_id, user_id)
```

### Missing Database Elements

1. **`left_at` column** on `conversation_participants` - For tracking when users leave groups
2. **`group_image_url`** on `conversations` - For group avatars
3. **`reply_to_id`** on `messages` - For threading/replies
4. **`message_type`** on `messages` - For system messages, audio, location
5. **`typing_indicators`** table - For real-time typing status
6. **Indexes** - Most are in place, but verify for new columns

---

## ⚡ Realtime Implementation Audit

### Current Setup
- **REPLICA IDENTITY FULL** on messages, conversations, notifications ✅
- **Publication** `supabase_realtime` includes required tables ✅
- **RLS Policies** allow SELECT for conversation participants ✅

### Channels in Use
1. `messages:{conversationId}` - Per-conversation message subscription
2. `conversations:all` - Global conversation updates
3. `messages:list-updates` - For conversation list previews

### Potential Issues
- **Max 3 channels limit** may drop subscriptions when switching views fast
- **No typing indicator channel** - Need to add
- **No presence channel** - For online status (optional)

### Recommendations
1. Consider increasing max channels to 5 for typing indicators
2. Add typing indicator broadcast channel
3. Implement connection status monitoring

---

## 🎨 Design System Analysis

### Colors (ColorTheme.swift)
```swift
.naarsPrimary  // Terracotta #B5634B (light) / #C97A64 (dark)
.naarsAccent   // Warm amber #D4A574
.naarsSuccess  // Green
.naarsWarning  // Orange/Amber
.naarsTextSecondary, .naarsTextTertiary
```

### Typography (Typography.swift)
```swift
.naarsLargeTitle  // 34pt bold
.naarsTitle       // 28pt semibold
.naarsHeadline    // 17pt semibold
.naarsBody        // 17pt regular
.naarsCaption     // 12pt regular
```

### Spacing (Constants.swift)
```swift
Constants.Spacing.xs = 4
Constants.Spacing.sm = 8
Constants.Spacing.md = 16
Constants.Spacing.lg = 24
Constants.Spacing.xl = 32
```

---

## 🔴 Gap Analysis: PRD vs Current State

### Group Chat Features (Priority #1)

| Feature | PRD Requirement | Current State | Gap |
|---------|----------------|---------------|-----|
| Create group | ✅ Required | ✅ Implemented | None |
| User search | ✅ Required | ✅ Implemented | None |
| Multi-select | ✅ Required | ✅ Implemented | None |
| Add participants | ✅ Required | ✅ Implemented | None |
| Remove participants | ✅ Required | ⚠️ Placeholder | **Need to implement** |
| Leave group | ✅ Required | ❌ Missing | **Need to implement** |
| Group name | ✅ Required | ✅ Implemented | None |
| Group avatar | ✅ Required | ❌ Missing | **Need to implement** |
| Profile pics in bubbles | ✅ Required | ❌ Missing | **Only shows name** |
| System messages | ✅ Required | ⚠️ Basic | Style needs work |
| Admin roles | ✅ Optional | ⚠️ Field exists | Not enforced |

### Core Messaging

| Feature | PRD Requirement | Current State | Gap |
|---------|----------------|---------------|-----|
| Real-time messages | ✅ Required | ✅ Implemented | None |
| Optimistic UI | ✅ Required | ✅ Implemented | None |
| Message pagination | ✅ Required | ✅ Implemented | None |
| Image sharing | ✅ Required | ✅ Implemented | None |
| Reactions | ✅ Required | ✅ Implemented | None |
| Read receipts | ✅ Required | ✅ Implemented | Display could be better |
| Typing indicators | ✅ Required | ❌ Missing | **Need to implement** |
| Swipe-to-reply | ✅ Required | ❌ Missing | **Need to implement** |
| Message threading | ✅ Required | ❌ Missing | **Need to implement** |
| Audio messages | ✅ Required | ❌ Missing | Phase 4 |
| Location sharing | ✅ Required | ❌ Missing | Phase 4 |
| Link previews | ✅ Required | ❌ Missing | Phase 4 |

### iMessage-Style UX

| Feature | PRD Requirement | Current State | Gap |
|---------|----------------|---------------|-----|
| Bubble styling | ✅ Required | ⚠️ Basic | **Need polish** |
| Bubble tail | ✅ Required | ❌ Missing | **Need to add** |
| Send animation | ✅ Required | ❌ Missing | **Need to add** |
| Receive animation | ✅ Required | ❌ Missing | **Need to add** |
| Timestamp grouping | ✅ Required | ⚠️ Basic | **Improve logic** |
| Long-press menu | ✅ Required | ⚠️ Partial | **Add more options** |
| Scroll-to-bottom | ✅ Required | ❌ Missing | **Need to add** |
| Keyboard handling | ✅ Required | ⚠️ Okay | Verify no issues |

---

## 🐛 Known Issues & Technical Debt

### Issues Found

1. **Remove participant not implemented** - `removeParticipant` in MessageDetailsPopup is empty
2. **isArchived column** - Model expects it but may not exist in database
3. **Duplicate realtime handlers** - `handleNewMessage` vs `handleRealtimeInsert` in ConversationDetailViewModel
4. **Message deduplication** - Relies on text+time matching for optimistic UI, could fail with identical messages

### Technical Debt

1. **ConversationParticipantsViewModel** is defined inline in ConversationDetailView
2. **Date decoding** is repeated in multiple places (should centralize)
3. **Profile fetching** in loops (could batch)
4. **No offline message queue** - Messages fail silently if offline

---

## 📋 Recommended Implementation Phases

### Phase 1: Complete Group Chat (Week 1) ⭐ TOP PRIORITY

**Database Changes:**
1. Add `left_at` column to `conversation_participants`
2. Add `group_image_url` column to `conversations`
3. Create storage bucket for group images

**iOS Changes:**
1. Implement `removeParticipantFromConversation()` in MessageService
2. Implement `leaveConversation()` in MessageService  
3. Add group avatar picker to MessageDetailsPopup
4. Add profile pictures to MessageBubble for group chats
5. Improve system message styling

**Files to Modify:**
- `MessageService.swift` - Add remove/leave methods
- `MessageDetailsPopup.swift` - Add leave button, avatar picker
- `MessageBubble.swift` - Add sender avatar for groups
- `Conversation.swift` - Add groupImageUrl field

### Phase 2: iMessage Polish (Week 2)

**iOS Changes:**
1. Redesign MessageBubble with tail effect
2. Add send/receive animations
3. Improve timestamp grouping logic
4. Add scroll-to-bottom button
5. Enhance long-press context menu
6. Verify keyboard handling

**Files to Modify:**
- `MessageBubble.swift` - Complete redesign
- `ConversationDetailView.swift` - Scroll button, animations
- `MessageInputBar.swift` - Animation improvements

### Phase 3: Swipe-to-Reply & Threading (Week 3)

**Database Changes:**
1. Add `reply_to_id` column to `messages`

**iOS Changes:**
1. Add swipe gesture to MessageBubble
2. Create reply preview component
3. Update MessageInputBar with reply context
4. Display threaded messages with quote

**Files to Modify:**
- `Message.swift` - Add replyToId field
- `MessageBubble.swift` - Add swipe gesture, quote display
- `MessageInputBar.swift` - Reply context bar
- `MessageService.swift` - Handle reply_to_id

### Phase 4: Typing Indicators (Week 3)

**Database Changes:**
1. Create `typing_indicators` table (or use Supabase Presence)

**iOS Changes:**
1. Create TypingIndicator component
2. Send typing status on text input
3. Subscribe to typing channel
4. Auto-expire typing after 5s

**Files to Create:**
- `TypingIndicator.swift` - UI component
- `TypingService.swift` - Or integrate into MessageService

### Phase 5: Rich Media (Week 4)

**Database Changes:**
1. Add `message_type` enum to messages
2. Add `location_data` JSONB column
3. Add `audio_url` column
4. Create audio storage bucket

**iOS Changes:**
1. Audio recording UI and playback
2. Location picker with MapKit
3. Link preview generation (LinkPresentation framework)

### Phase 6: Final Polish (Week 5)

1. Performance optimization
2. Accessibility audit
3. Edge case testing
4. Bug fixes

---

## 🛡️ Risk Mitigation

### Preserve Existing Functionality

1. **Feature flags** - Enable new features gradually
2. **Backwards compatibility** - New columns should be nullable
3. **Regression testing** - Test all existing flows after changes
4. **Incremental deployment** - Database migrations before iOS release

### Files NOT to Modify (Unless Necessary)

- App startup flow (`AppState.swift`, `ContentView.swift`)
- Authentication (`AuthService.swift`, login views)
- Other features (Rides, Favors, TownHall)
- Navigation structure

---

## ✅ Next Steps

1. **Review this document** and confirm priorities
2. **Approve Phase 1** scope (Group Chat completion)
3. Begin implementation with database migrations
4. Implement iOS changes incrementally
5. Test each phase thoroughly before proceeding

---

## 📁 Key File Locations Reference

```
NaarsCars/
├── Core/
│   ├── Models/
│   │   ├── Conversation.swift
│   │   ├── Message.swift
│   │   └── MessageReaction.swift
│   └── Services/
│       ├── MessageService.swift
│       └── RealtimeManager.swift
├── Features/
│   └── Messaging/
│       ├── ViewModels/
│       │   ├── ConversationsListViewModel.swift
│       │   └── ConversationDetailViewModel.swift
│       └── Views/
│           ├── ConversationsListView.swift
│           ├── ConversationDetailView.swift
│           └── MessageDetailsPopup.swift
├── UI/
│   ├── Components/
│   │   └── Messaging/
│   │       ├── MessageBubble.swift
│   │       ├── MessageInputBar.swift
│   │       ├── ReactionPicker.swift
│   │       └── UserSearchView.swift
│   └── Styles/
│       ├── ColorTheme.swift
│       └── Typography.swift
└── database/
    ├── 064_create_message_reactions.sql
    └── 081_fix_realtime_messaging.sql
```


