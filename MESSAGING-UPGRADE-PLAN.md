# Messaging Upgrade Implementation Plan

**Date:** January 2026  
**PRD Reference:** `PRDs/naars-cars-messaging-prd.md`  
**Discovery:** `MESSAGING-UPGRADE-DISCOVERY.md`

---

## 🎯 Implementation Strategy

The upgrade follows the PRD's recommended phases, prioritizing **Group Chat completion** as the #1 priority while preserving all existing functionality.

### Guiding Principles

1. **Modify existing code** rather than creating new files when possible
2. **Database changes first**, then iOS code
3. **Test each feature** before moving to the next
4. **No breaking changes** to existing conversations/messages
5. **Preserve the design system** - use existing colors, fonts, spacing

---

## Phase 1: Complete Group Chat ⭐ TOP PRIORITY

### 1.1 Database Migrations

#### Migration: `083_enhance_group_conversations.sql`

```sql
-- Add left_at column for tracking when users leave groups
ALTER TABLE public.conversation_participants 
ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ DEFAULT NULL;

-- Add group image URL for group avatars
ALTER TABLE public.conversations 
ADD COLUMN IF NOT EXISTS group_image_url TEXT DEFAULT NULL;

-- Add is_archived column (model expects it but might be missing)
ALTER TABLE public.conversations 
ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE;

-- Create index for active participants (not left)
CREATE INDEX IF NOT EXISTS idx_active_participants 
ON public.conversation_participants(conversation_id) 
WHERE left_at IS NULL;

-- Update RLS policy to hide left participants from queries
-- (participants who have left can still see old messages but can't send)
```

#### Storage: Group Images Bucket

```sql
-- Create bucket for group images
INSERT INTO storage.buckets (id, name, public)
VALUES ('group-images', 'group-images', true)
ON CONFLICT (id) DO NOTHING;

-- RLS policy for group images
CREATE POLICY "Group participants can upload group images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'group-images' 
  AND auth.role() = 'authenticated'
);

CREATE POLICY "Anyone can view group images"
ON storage.objects FOR SELECT
USING (bucket_id = 'group-images');
```

### 1.2 Update Conversation Model

**File:** `NaarsCars/Core/Models/Conversation.swift`

```swift
// Add to Conversation struct:
var groupImageUrl: String?

// Add to CodingKeys:
case groupImageUrl = "group_image_url"

// Update decoder to handle optional groupImageUrl

// Add to ConversationParticipant:
var leftAt: Date?

// Add to ConversationParticipant CodingKeys:
case leftAt = "left_at"
```

### 1.3 Implement Remove/Leave Methods in MessageService

**File:** `NaarsCars/Core/Services/MessageService.swift`

Add these methods:

```swift
/// Remove a participant from a conversation (admin action)
/// - Parameters:
///   - conversationId: The conversation ID
///   - userId: The user ID to remove
///   - removedBy: The admin/user performing the removal
///   - createAnnouncement: Whether to create a system message
func removeParticipantFromConversation(
    conversationId: UUID,
    userId: UUID,
    removedBy: UUID,
    createAnnouncement: Bool = true
) async throws

/// Leave a conversation (self-removal)
/// - Parameters:
///   - conversationId: The conversation ID
///   - userId: The user leaving
func leaveConversation(
    conversationId: UUID,
    userId: UUID
) async throws

/// Upload group image
/// - Parameters:
///   - imageData: The image data
///   - conversationId: The conversation ID
/// - Returns: Public URL of uploaded image
func uploadGroupImage(
    imageData: Data,
    conversationId: UUID
) async throws -> String

/// Update group image URL
/// - Parameters:
///   - conversationId: The conversation ID
///   - imageUrl: The new image URL (nil to remove)
///   - userId: The user making the update
func updateGroupImage(
    conversationId: UUID,
    imageUrl: String?,
    userId: UUID
) async throws
```

### 1.4 Update MessageDetailsPopup

**File:** `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`

Changes needed:
1. Add group image picker section
2. Implement `removeParticipant(userId:)` properly
3. Add "Leave Group" button
4. Show confirmation dialogs

### 1.5 Add Profile Pictures to Message Bubbles

**File:** `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

Changes needed:
1. Accept optional `senderProfile: Profile?` parameter
2. Display avatar on left side for received messages in groups
3. Only show for first message in consecutive series from same sender

### 1.6 Improve System Message Styling

**File:** `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

Changes needed:
1. Better detection of system message types
2. Centered pill-style background
3. Smaller, italicized text
4. Appropriate icons for different system actions

---

## Phase 2: iMessage-Style Polish

### 2.1 Redesign Message Bubbles

**File:** `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

iMessage characteristics to implement:
- Rounded rectangle with subtle "tail" on appropriate corner
- Max width ~75% of screen
- Proper corner radius (16-18pt)
- Spacing: 2pt between consecutive, 8pt for new sender
- Read receipt indicators below sent messages

### 2.2 Add Animations

**File:** `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

Animations to add:
- Send: Scale up with slight bounce, auto-scroll
- Receive: Slide in from left, subtle scale
- Keyboard: Smooth push/dismiss

### 2.3 Timestamp Grouping

**File:** `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

Logic:
- Show timestamp on first message
- Show when 5+ minutes between messages
- Show when day changes
- Format: "Today 10:30 AM", "Yesterday", "Monday", "Jan 15"

### 2.4 Scroll-to-Bottom Button

**File:** `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

Features:
- Appears when scrolled >200pt from bottom
- Shows unread count badge
- Circular button, bottom-right
- Smooth scroll animation on tap

### 2.5 Enhanced Long-Press Menu

**File:** `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

Add to context menu:
1. Reactions row (existing)
2. Reply (new)
3. Copy (new)
4. Delete (own messages only)
5. Report (others' messages only)

---

## Phase 3: Swipe-to-Reply & Threading

### 3.1 Database Migration

#### Migration: `084_add_message_replies.sql`

```sql
-- Add reply_to_id for threading
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES public.messages(id) ON DELETE SET NULL;

-- Index for fetching replies
CREATE INDEX IF NOT EXISTS idx_messages_reply_to 
ON public.messages(reply_to_id) 
WHERE reply_to_id IS NOT NULL;
```

### 3.2 Update Message Model

**File:** `NaarsCars/Core/Models/Message.swift`

```swift
// Add field:
let replyToId: UUID?
var replyToMessage: Message? // Populated when fetched

// Add to CodingKeys:
case replyToId = "reply_to_id"
```

### 3.3 Implement Swipe Gesture

**File:** `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

- Add DragGesture to bubble
- Show reply icon on swipe right
- Haptic feedback at threshold
- Trigger reply callback

### 3.4 Reply Context Bar

**File:** `NaarsCars/UI/Components/Messaging/MessageInputBar.swift`

- Show "Replying to [Name]" banner
- Display quoted message preview
- Close button to cancel reply
- Pass replyToId when sending

### 3.5 Display Quoted Messages

**File:** `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

- Show quoted message above bubble
- Tap to scroll to original (if in viewport)
- Truncate long quotes

---

## Phase 4: Typing Indicators

### 4.1 Implementation Approach

**Option A: Database table + Realtime (Simpler)**
- Create `typing_indicators` table
- Insert/update on typing, auto-expire
- Subscribe via Realtime

**Option B: Supabase Broadcast (Lower latency)**
- Use Realtime broadcast channel
- No database persistence
- Pure client-to-client

**Recommendation:** Start with Option A for reliability

### 4.2 Database Migration (Option A)

```sql
CREATE TABLE IF NOT EXISTS public.typing_indicators (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (conversation_id, user_id)
);

-- Auto-delete old indicators (older than 10 seconds)
-- Use pg_cron or application logic
```

### 4.3 Create TypingIndicator Component

**File:** `NaarsCars/UI/Components/Messaging/TypingIndicator.swift`

- Three animated dots
- Shows "[Name] is typing..."
- Multiple typers: "[Name] and [Name] are typing..."

### 4.4 Integrate with ConversationDetailView

- Send typing status on text input change
- Subscribe to typing channel
- Display indicator above input bar

---

## Phase 5: Rich Media (Future)

### 5.1 Audio Messages
- Recording UI with waveform
- Playback with seek
- Upload to storage
- Duration display

### 5.2 Location Sharing
- MapKit picker
- Send coordinates + address
- Static map preview in bubble
- Open in Maps on tap

### 5.3 Link Previews
- Detect URLs in text
- Use LinkPresentation framework
- Cache previews
- Display card in bubble

---

## 🔧 Testing Checklist

### Phase 1 Tests
- [ ] Create new group conversation
- [ ] Add participants to existing group
- [ ] Remove participant (as admin)
- [ ] Leave group (as member)
- [ ] Upload group image
- [ ] Profile pictures display in group bubbles
- [ ] System messages styled correctly
- [ ] Existing 1:1 conversations still work
- [ ] Existing group conversations still work

### Phase 2 Tests
- [ ] Message bubbles match iMessage style
- [ ] Send animation works
- [ ] Receive animation works
- [ ] Timestamps grouped correctly
- [ ] Scroll-to-bottom button appears/works
- [ ] Context menu shows all options
- [ ] Dark mode looks correct
- [ ] 60fps scrolling with 500+ messages

### Phase 3 Tests
- [ ] Swipe right triggers reply
- [ ] Reply context shows in input bar
- [ ] Sent reply includes quote
- [ ] Tap quote scrolls to original
- [ ] Cancel reply works

### Phase 4 Tests
- [ ] Typing indicator appears when other user types
- [ ] Indicator disappears after sending
- [ ] Indicator times out after 5s idle
- [ ] Multiple typers displayed correctly

---

## 📅 Timeline Estimate

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Phase 1 | 5-7 days | Complete group chat |
| Phase 2 | 3-5 days | iMessage polish |
| Phase 3 | 3-4 days | Reply/threading |
| Phase 4 | 2-3 days | Typing indicators |
| Phase 5 | 5-7 days | Rich media |
| Testing | 3-5 days | QA and fixes |

**Total: 3-5 weeks**

---

## 🚀 Ready to Start?

To begin implementation:

1. **Confirm priorities** - Group chat first?
2. **Review database migrations** - Any concerns?
3. **Approve Phase 1 scope** - Missing anything?

Once approved, I'll start with:
1. Create database migration `083_enhance_group_conversations.sql`
2. Update `Conversation.swift` model
3. Add methods to `MessageService.swift`
4. Update `MessageDetailsPopup.swift`
5. Update `MessageBubble.swift`

Let me know when you're ready to proceed!

