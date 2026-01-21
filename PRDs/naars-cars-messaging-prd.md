# **Product Requirements Document: iMessage-Style Messaging for Naars Cars**

**Version:** 1.0  
**Date:** January 2026  
**Target:** Cursor IDE with Claude Opus 4.5  
**Project:** Naars Cars iOS App Messaging Overhaul

---

## **Executive Summary**

Transform Naars Cars' messaging functionality from its current basic implementation into an iMessage-equivalent experience while maintaining the app's visual identity and ride-sharing context. The messaging system should feel native, professional, and indistinguishable from iMessage in terms of interaction patterns and performance, with **group chat as the #1 priority feature**.

---

## **1. PROJECT SCOPE & OBJECTIVES**

### **1.1 Primary Goals**

1. **GROUP CHAT FIRST** - Implement full-featured group messaging as top priority
2. Create an iMessage-equivalent UX while preserving Naars Cars branding
3. Achieve real-time, performant messaging using Supabase Realtime
4. Support hundreds of messages with smooth scrolling and interactions
5. Enable rich media sharing (photos, location, links, audio)
6. Implement social features (reactions, replies, typing indicators)

### **1.2 Success Criteria**

**Must Achieve:**
- ✅ Group chat creation with user search from existing app users
- ✅ Add/remove users from group conversations
- ✅ Smooth, responsive, truly real-time messaging (feels like live conversation)
- ✅ Visual similarity to iMessage (bubbles, spacing, animations)
- ✅ Gesture-based interactions (swipe-to-reply, long-press menus)
- ✅ Message reactions displayed like iMessage tapbacks
- ✅ Profile pictures in group chat bubbles
- ✅ All existing app workflows remain functional

**Performance Targets:**
- Messages appear in <100ms after sending
- Smooth 60fps scrolling with 500+ messages
- Keyboard interactions with zero jank
- Image compression and upload <2 seconds

---

## **2. MANDATORY DISCOVERY PHASE**

### **⚠️ DO THIS FIRST - NO EXCEPTIONS ⚠️**

Before writing ANY code or proposing ANY changes, you must complete a comprehensive discovery of the existing implementation. This is not optional.

### **2.1 Codebase Analysis**

**Step 1: Map Current Implementation**

Scan the entire iOS project and document:

1. **Messaging-Related Files**
   - All Views related to messaging/chat/conversations
   - All ViewModels handling messaging logic
   - All Models representing messages, conversations, participants
   - All Services managing message sending/receiving
   - All Utilities for image handling, compression, etc.
   - Navigation structure to/from messaging views
   - Any third-party dependencies in use

2. **Current Architecture**
   - How is data flowing? (MVVM? MVC? Other?)
   - What design patterns are being used?
   - Where is business logic located?
   - How are views communicating with each other?
   - What state management approach is used?

3. **Design System**
   - Extract ALL color definitions currently in use
   - Document spacing/padding patterns
   - Typography styles (fonts, sizes, weights)
   - Border radius values
   - Shadow/elevation patterns
   - Animation curves and timings
   - Any existing SwiftUI or UIKit styling utilities

**OUTPUT:** Create `CURRENT_STATE.md` with complete findings

---

### **2.2 Database Schema Analysis**

**Step 2: Understand Current Data Model**

Connect to the Supabase project and document:

1. **Existing Tables**
   - What tables exist for messaging? (messages, conversations, etc.)
   - What columns exist in each table?
   - What data types are being used?
   - What relationships exist between tables?
   - What indexes are currently in place?
   - What constraints exist?

2. **Current Schema Capabilities**
   - Does it support 1:1 conversations?
   - Does it support group conversations?
   - How are participants tracked?
   - How are read statuses handled?
   - Is there support for reactions?
   - Is there support for replies/threading?
   - How are different message types handled? (text, image, location, etc.)

3. **Security & Performance**
   - What Row Level Security (RLS) policies exist?
   - What triggers are in place?
   - Are there any stored procedures/functions?
   - What's the current indexing strategy?

**OUTPUT:** Create `CURRENT_DATABASE.md` with schema details

---

### **2.3 Supabase Realtime Investigation**

**Step 3: Audit Real-Time Implementation**

Find and analyze all Realtime-related code:

1. **Current Implementation**
   - Where are Realtime subscriptions set up?
   - What channels are being subscribed to?
   - What events are being listened for?
   - How are incoming messages handled?
   - Is there deduplication logic?
   - How are errors handled?
   - How is reconnection managed?

2. **Performance & Reliability**
   - Is Realtime actually working correctly?
   - Are messages arriving in real-time?
   - Are there any race conditions?
   - Are subscriptions being properly cleaned up?
   - Is there any message queuing for offline scenarios?

3. **Issues & Gaps**
   - Why isn't real-time working as expected?
   - What's causing delays or missed messages?
   - Are there subscription leaks?
   - Are there any error patterns in logs?

**OUTPUT:** Create `REALTIME_AUDIT.md` with findings and issues

---

### **2.4 Media Handling Review**

**Step 4: Understand Current Media Implementation**

1. **Image Handling**
   - How are images currently uploaded?
   - Is there compression? How does it work?
   - Where are images stored? (Supabase Storage? Other?)
   - How are images displayed in messages?
   - Is there any caching?
   - How are thumbnails generated?

2. **Other Media**
   - Is location sharing implemented?
   - Is audio recording implemented?
   - How are files/attachments handled?
   - Are there any size limits?

**OUTPUT:** Add to `CURRENT_STATE.md` under "Media Handling" section

---

### **2.5 Issues Identification**

**Step 5: Document Problems**

Based on your investigation, create a comprehensive list of:

1. **Bugs**
   - What's broken?
   - What's not working as expected?
   - What error scenarios exist?

2. **Performance Issues**
   - What's slow?
   - What causes jank or lag?
   - What causes crashes?
   - What causes high memory usage?

3. **Missing Features**
   - What's required but doesn't exist?
   - What's partially implemented?
   - What needs refactoring?

4. **Technical Debt**
   - What code needs cleanup?
   - What's duplicated?
   - What's poorly structured?

**OUTPUT:** Create `ISSUES_FOUND.md` prioritized by severity

---

### **2.6 Pause and Present Findings**

**⛔ STOP HERE ⛔**

Do not proceed with any implementation until you:
1. Present all discovery documents
2. Get approval on findings
3. Discuss proposed approach
4. Get approval to proceed

---

## **3. DATABASE REQUIREMENTS**

Based on your discovery, the database must support these capabilities:

### **3.1 Required Data Model Capabilities**

**Conversations Must Support:**
- Both 1:1 and group conversation types
- Conversation metadata (created date, updated date, last message info)
- Group-specific data:
  - Group name
  - Group image/avatar
  - Creator identification
- Soft deletion (don't hard delete, just mark as deleted)
- Efficient querying by recency (for conversation list sorting)

**Messages Must Support:**
- Multiple message types: text, image, location, audio, system messages
- Message content and metadata
- Sender identification
- Conversation association
- Timestamps (created, updated, optionally edited)
- Rich content fields:
  - Image data (URL, dimensions)
  - Location data (coordinates, name/address)
  - Audio data (URL, duration)
  - Link preview data (URL, title, description, image)
- Threading/replies (reference to parent message)
- Optimistic updates (client-side ID for deduplication)
- Status tracking (sending, failed, delivered, read)
- Soft deletion

**Participants Must Support:**
- Association between users and conversations
- Join/leave timestamps
- Read tracking (last read message, last read time)
- Notification preferences (muted status)
- Role management (admin vs member for future features)
- Efficient querying (find all conversations for a user, find all users in a conversation)

**Reactions Must Support:**
- Multiple reaction types (love, like, dislike, laugh, emphasize, question)
- User who reacted
- Message association
- Timestamp
- Prevent duplicate reactions from same user

**Typing Indicators Must Support:**
- Real-time updates via Supabase Realtime
- Automatic expiration (old indicators should be removed)
- User and conversation association

**After Discovery:** Review existing schema and propose specific changes needed

---

### **3.2 Database Performance Requirements**

Your schema should support:
- Fast conversation list queries (sorted by recent activity)
- Efficient message pagination (load 50 at a time, fetch older on scroll)
- Quick participant lookups
- Real-time message delivery via Supabase Realtime
- Proper indexing for all common queries
- Optimized foreign key relationships

**After Discovery:** Identify missing indexes and optimization opportunities

---

### **3.3 Data Integrity & Security**

Required:
- Row Level Security (RLS) policies:
  - Users can only see conversations they're participants in
  - Users can only send messages to conversations they're in
  - Users can only modify their own messages
  - Users can only react to messages they can access
- Proper foreign key constraints
- Cascading deletes where appropriate
- Data validation at database level
- Protection against SQL injection

**After Discovery:** Document existing RLS policies and identify gaps

---

## **4. GROUP CHAT REQUIREMENTS** ⭐ **TOP PRIORITY**

### **4.1 Group Creation Flow**

**User Story:**
> As a user, I want to create a group chat with multiple app users so I can coordinate rides or socialize with my community.

**Required UI Flow:**
1. From Conversations List → "+" Button → "New Group" option
2. User Search Screen:
   - Search bar to find existing app users
   - Display search results with user avatars and names
   - Allow multi-select (checkboxes or toggle selection)
   - Show selected users as removable chips
   - "Next" button (enabled only when 2+ users selected)
3. Group Details Screen:
   - Input field for group name (required)
   - Option to upload/select group photo (optional)
   - List of selected participants (with option to remove before creating)
   - "Create Group" button
4. After creation:
   - Navigate to the new group conversation
   - Insert system message: "[User] created the group"

**Technical Requirements:**
- Must search existing app users (from auth.users or your user table)
- Search should be fast and responsive (search as you type)
- Should exclude current user from search results
- Should exclude already-selected users from search results
- Must create conversation record with type='group'
- Must create participant records for all selected users plus creator
- Must handle creation errors gracefully

**After Discovery:** Review how user search currently works (if at all) and propose implementation

---

### **4.2 Group Management Features**

**Add Participants:**
- UI: From group conversation settings → "Add Participants" button
- Flow: Same search interface as group creation
- Action: Insert new participant records, add system message
- Notification: New members should be notified they were added

**Remove Participants:**
- UI: From group conversation settings → participant list → swipe or long-press to remove
- Requirements:
  - Only group admins can remove others (or allow any member to remove - decide based on app needs)
  - Any member can remove themselves (leave group)
  - Update participant record (set left_at timestamp)
  - Insert system message
  - Removed user can still see message history but can't send new messages

**Edit Group Details:**
- Group name: Any member or admin-only (you decide)
- Group photo: Any member or admin-only (you decide)
- Insert system message when changed

**Group Info Screen Must Show:**
- Group photo (tap to view fullscreen, tap again to change if permitted)
- Group name (tap to edit if permitted)
- Participant list:
  - Profile picture
  - Name
  - Role badge (if admin)
  - Swipe actions or menu to remove (if permitted)
- "Add Participants" button
- "Leave Group" button (red, prominent)
- "Report Group" option (if implementing reporting)

**After Discovery:** Check if any group features exist and what needs to be built

---

### **4.3 Group Chat UI Patterns**

**Message Display in Groups:**

Each message should show:
- Profile picture (for messages from others, not from current user)
- Sender name (above message bubble, unless consecutive messages from same sender)
- Message bubble (left-aligned for others, right-aligned for current user)
- Timestamp (shown periodically, not on every message)
- Reactions (displayed at bubble corner)

**Visual Grouping Logic:**
- Consecutive messages from the same sender should be grouped
- First message in group: show profile picture and name
- Middle messages: no picture/name, slight reduction in spacing
- Last message: normal spacing to next group
- Don't repeat sender name/picture for consecutive messages within ~5 minutes

**iMessage Reference Pattern:**
```
[Photo] Alice
        Message bubble 1
        Message bubble 2
        Message bubble 3
        (2 minutes later)
        Message bubble 4
        
[Photo] Bob
        Message bubble 5
        
[Photo] Alice
        Message bubble 6
```

**After Discovery:** Review current message display logic and identify needed changes

---

## **5. CORE MESSAGING FEATURES**

### **5.1 Real-Time Messaging**

**Must Work Perfectly:**
- Message appears instantly for sender (optimistic UI)
- Message appears in <200ms for receivers via Realtime
- Messages appear in correct chronological order
- No duplicate messages
- Handles reconnection gracefully
- Works when app is in background (with push notifications)

**Optimistic UI Pattern Required:**
1. User hits send
2. Message appears immediately in UI with "sending" indicator
3. Upload any media first (if applicable)
4. Send to database
5. On success: update message with server ID, show delivered indicator
6. On failure: show error state, offer retry button
7. Realtime subscription delivers to other participants

**Realtime Channels Needed:**
- New messages in conversation
- Message updates (edited, deleted)
- Typing indicators
- Read receipts
- Reactions

**After Discovery:** Analyze current Realtime implementation and propose fixes/improvements

---

### **5.2 Message Bubble Design**

**Visual Requirements:**

Follow iMessage design patterns:
- Bubble shape: Rounded rectangles with subtle tail
- Current user: Right-aligned, app primary color background, white text
- Others: Left-aligned, gray background (light/dark mode appropriate), contrasting text
- Max width: ~70% of screen width
- Proper padding inside bubbles
- Smooth corner radius
- Spacing between messages (2px for consecutive, 8px for new sender)

**Animations:**
- Send: Scale up with slight bounce, scroll to bottom
- Receive: Slide in from appropriate side, subtle scale effect
- Haptic feedback on receive (subtle)

**After Discovery:** Extract current bubble styling and propose iMessage-style improvements

---

### **5.3 Input Bar & Keyboard**

**Input Bar Must Have:**
- Text input field that auto-expands (up to ~5 lines max)
- Send button (appears when text entered, replaces audio/voice button)
- Attachment options (+, camera, photo, location, etc.)
- Smooth keyboard interaction (no jank, no gaps)
- Input bar stays above keyboard (proper keyboard avoidance)

**Keyboard Behavior:**
- When keyboard appears: smoothly push input bar up
- Maintain scroll position or scroll to bottom (depending on context)
- When keyboard dismisses: smoothly lower input bar
- No visual glitches or gaps
- Handle external keyboard properly

**Attachment Actions:**
- Photo library: Multi-select, show thumbnails below input
- Camera: Inline camera view or system camera
- Location: Map picker with current location
- Audio: Press-hold to record (visual feedback)

**After Discovery:** Review current input implementation and identify issues

---

### **5.4 Gestures & Interactions**

**Swipe to Reply:**
- Swipe right on any message bubble
- Visual: Bubble slides right, reply icon appears
- Haptic feedback at threshold
- Action: Focus input field, show "Replying to [User]" banner, include quoted message preview
- When sent: Message includes reference to parent message

**Long Press Menu:**
- Long press on message bubble
- Visual: Bubble scales up slightly, background blurs, menu appears
- Menu items (prioritized order):
  1. Reactions row (❤️ 👍 👎 😂 ‼️ ❓)
  2. Reply
  3. Copy
  4. Forward (optional feature)
  5. Delete (only for own messages)
  6. Report (only for others' messages)
- Haptic feedback on menu appearance and selection

**Tap Interactions:**
- Single tap: Dismiss keyboard (if open)
- Single tap on image: Open fullscreen viewer
- Single tap on link: Show preview, then open
- Single tap on location: Open in Maps app
- Single tap on reaction: Show who reacted
- Double tap: Quick react with ❤️ (optional Instagram-style feature)

**After Discovery:** Check what gesture handling exists and what needs to be added

---

### **5.5 Reactions (Tapback Style)**

**Visual Design:**
- Small circular badges on message bubble
- Positioned at bottom-right corner (for right-aligned) or bottom-left (for left-aligned)
- White background with subtle shadow
- Emoji centered inside
- When multiple: Stack horizontally with slight overlap
- If more than 3: Show first 3 + "+N" indicator

**Supported Reactions:**
- ❤️ Love
- 👍 Like
- 👎 Dislike
- 😂 Laugh
- ‼️ Emphasize
- ❓ Question

**Interaction:**
- Add reaction: Long press → tap reaction in menu OR double-tap for ❤️
- Remove reaction: Tap on your own reaction OR long press → tap same reaction again
- View who reacted: Tap on reaction cluster → show list with names and avatars

**After Discovery:** Check if reactions exist, review data model

---

### **5.6 Typing Indicators**

**Visual:**
- Small gray bubble appears where next message would be
- Three animated dots pulsing in sequence
- Positioned on left side (where received messages appear)
- Sized like a small message bubble

**Text for Multiple Typers:**
- 1 person: "[Name] is typing..."
- 2 people: "[Name] and [Name] are typing..."
- 3+ people: "[Name], [Name], and N others are typing..."

**Technical Behavior:**
- Send typing indicator when user starts typing
- Update every few seconds while actively typing
- Automatically expire after 3-5 seconds of no activity
- Clear when message is sent
- Use Realtime for instant updates

**After Discovery:** Check if typing indicators exist and how they're implemented

---

### **5.7 Read Receipts**

**Visual Display:**
- Below message bubble (right-aligned messages only)
- States:
  - Sending: Gray spinner or clock icon
  - Sent: Single gray checkmark
  - Delivered: Double gray checkmark
  - Read: "Read" text in blue or profile pictures (in groups)

**In Group Chats:**
- Show "Read by N" as tappable text
- Tap to see list of who has read, with profile pictures

**Privacy:**
- Setting to enable/disable read receipts
- If disabled by user: They don't send read status, and don't see others' read status
- Update read status when conversation is visible and scrolled to bottom

**After Discovery:** Check current read receipt implementation

---

### **5.8 Timestamp Display**

**Display Rules:**
- Don't show timestamp on every message (too cluttered)
- Show timestamp:
  - On first message of conversation
  - Every 5+ minutes between messages
  - When day changes
  - When user taps message (show timestamp for that message)

**Format:**
- Today: "10:30 AM"
- Yesterday: "Yesterday 10:30 AM"
- This week: "Monday 10:30 AM"
- Older: "Jan 15, 10:30 AM"
- Different year: "Jan 15, 2025"

**Positioning:**
- Centered above message group
- Small gray text (13pt system font)
- Subtle, doesn't interrupt flow
- Optional: Semi-transparent pill background

**After Discovery:** Review current timestamp handling

---

### **5.9 Scroll Behavior**

**Smart Auto-Scroll:**
- Auto-scroll to bottom when:
  - User sends message
  - New message arrives AND user is near bottom (within 100-200pt)
  - Keyboard appears AND user is near bottom
  - User taps "scroll to bottom" button
  
- Do NOT auto-scroll when:
  - New message arrives but user is scrolled up (reading old messages)
  - Loading older messages from pagination

**Scroll-to-Bottom Button:**
- Appears when user scrolls >200pt from bottom
- Circular button, bottom-right corner
- Shows badge with unread count
- Animated appearance (slide up from bottom)
- Tap to smoothly scroll to bottom

**Performance:**
- Must maintain 60fps during scrolling
- Use proper list virtualization (LazyVStack in SwiftUI)
- Implement pagination (load 50 messages at a time)
- Load older messages when scrolled to top
- Maintain scroll position when loading older messages

**After Discovery:** Analyze current scroll implementation and identify performance issues

---

## **6. RICH MEDIA FEATURES**

### **6.1 Photo/Image Sharing**

**Requirements:**
- Select from photo library (multi-select up to 10 images)
- Capture new photo with camera
- Show thumbnail preview below input bar before sending
- Compress images before upload (target: <500KB without sacrificing too much quality)
- Upload to Supabase Storage (or wherever currently storing images)
- Display in message bubble with proper sizing
- Tap to view fullscreen
- Fullscreen viewer with pinch-zoom, pan, swipe to dismiss
- Save to photos option in fullscreen view

**Performance:**
- Fast compression (<500ms for typical photo)
- Upload progress indicator
- Optimistic UI (show image immediately, upload in background)
- Cache loaded images to avoid re-downloading
- Progressive loading (thumbnail first, then full quality)

**After Discovery:** Review existing image handling utilities and storage setup

---

### **6.2 Location Sharing**

**Requirements:**
- Get current location
- Show map view with:
  - Blue dot for current position
  - Draggable pin to adjust exact location
  - Search bar for address lookup
  - "Send Location" button
- Reverse geocode to get readable address
- Send message with coordinates and address name
- Display in chat as map preview (static snapshot) with address text
- Tap to open in Apple Maps
- Option to get directions

**After Discovery:** Check if location features exist and how they're implemented

---

### **6.3 Audio Messages**

**Requirements:**
- Press and hold button to record
- Visual feedback while recording (pulsing, waveform, timer)
- Slide up to lock recording (can navigate away)
- Slide left to cancel
- Maximum duration: 2 minutes (auto-send after)
- Upload to storage
- Playback UI:
  - Play/pause button
  - Waveform or progress bar
  - Time elapsed / total time
  - Seek by dragging
  - Optional: Playback speed options (1x, 1.5x, 2x)

**After Discovery:** Check if audio recording exists

---

### **6.4 Link Previews**

**Requirements:**
- Auto-detect URLs in message text
- Fetch preview metadata (title, description, image)
- Can use LinkPresentation framework or custom OpenGraph scraping
- Display preview card in message bubble
- Tap to open link
- Cache previews to avoid repeated fetches
- Handle failures gracefully (just show plain URL)

**After Discovery:** Check if link preview functionality exists

---

## **7. SYSTEM MESSAGES**

**Types of System Messages:**
- Group created: "[User] created the group"
- User added: "[User] added [User]"
- User removed: "[User] removed [User]"
- User left: "[User] left the group"
- Group name changed: "[User] changed the group name to '[New Name]'"
- Group photo changed: "[User] changed the group photo"

**Visual Styling:**
- Centered text
- Small, gray font
- No bubble background
- Doesn't disrupt conversation flow
- Subtle, informational

**After Discovery:** Check how system messages are currently handled

---

## **8. CONVERSATIONS LIST**

### **8.1 List View Design**

**Each Conversation Cell Must Show:**
- Avatar/photo:
  - 1:1 chat: Other user's profile picture
  - Group chat: Composite of participant pictures (2-4 faces in grid) or group photo if set
- Name:
  - 1:1: Other user's name
  - Group: Group name or "You, [Name], and N others" if no name set
- Last message preview (truncated, gray text)
- Timestamp of last message (right-aligned)
- Unread count badge (if any unread messages)
- Delivery/read status for your last sent message (checkmarks)

**Interaction:**
- Tap to open conversation
- Swipe actions:
  - Delete conversation
  - Mute notifications
  - Pin to top (optional)

**Sorting:**
- Most recent activity first (last_message_at descending)
- Optionally: Pinned conversations at top
- Update order in real-time as new messages arrive

**After Discovery:** Review current conversations list implementation

---

### **8.2 Empty States**

**When No Conversations Exist:**
- Friendly illustration or icon
- Text: "No messages yet"
- Subtext: "Start a conversation with your community"
- Prominent "New Message" button

**When Conversation is Empty:**
- "Start your conversation"
- "Send a message to get started"

**After Discovery:** Check what empty states exist currently

---

### **8.3 Search Functionality**

**Conversations List Search:**
- Search bar at top of list
- Search in:
  - Conversation names
  - Participant names
  - Recent message content (optional)
- Live filtering as user types
- Show number of results

**After Discovery:** Check if search exists

---

## **9. SETTINGS & PREFERENCES**

**Message Settings Should Include:**

**Notifications Section:**
- Allow notifications (toggle)
- Show message previews (Always / When Unlocked / Never)
- Sound/vibration options
- Badge app icon (toggle)

**Privacy Section:**
- Send read receipts (toggle)
- Share typing status (toggle)
- Who can add me to groups (Everyone / Contacts Only / Nobody)

**Media Section:**
- Auto-download images (Wi-Fi Only / Wi-Fi & Cellular / Never)
- Save to photos automatically (toggle)
- Image quality preference (High / Medium / Low)

**Data Management:**
- Delete old messages (keep for 30 days / 90 days / 1 year / forever)
- Clear all conversations (with confirmation)

**After Discovery:** Check if settings infrastructure exists for messaging

---

## **10. REPORTING & BLOCKING**

### **10.1 Report Message/Conversation**

**User Flow:**
- Long press message → "Report" option OR conversation settings → "Report"
- Report screen:
  - Reason dropdown: Spam, Harassment, Inappropriate Content, Scam, Other
  - Optional text field for details
  - Submit button

**Technical:**
- Store report in database
- Include: reporter ID, reported user/message/conversation, reason, details, timestamp
- Send notification to admin/moderator (push, email, or internal notification)
- Don't show confirmation to reporter (privacy)

**After Discovery:** Check if reporting system exists

---

### **10.2 Block User**

**User Flow:**
- From conversation → Settings → "Block [User]"
- Confirmation alert: "Are you sure? [User] won't be able to message you."

**Effect:**
- Blocked user can't send you messages
- Blocked user can't see your profile
- Blocked user can't add you to groups
- Existing 1:1 conversation becomes hidden (not deleted)
- You can unblock from settings later

**After Discovery:** Check if blocking functionality exists

---

### **10.3 Admin Reporting Dashboard**

**If Admin Features Exist:**
- New view showing all user reports
- Display: Reporter name, reported user/content, reason, timestamp, status
- Actions: Dismiss, Warn User, Suspend User, Ban User
- Track resolution status

**After Discovery:** Check if admin dashboard exists in app

---

## **11. ERROR HANDLING & EDGE CASES**

### **11.1 Network Issues**

**Offline Scenarios:**
- Detect offline state
- Show banner: "No Internet Connection"
- Queue messages locally
- Show "Waiting to send..." status
- Auto-retry when connection restored
- Allow viewing old messages while offline
- Don't allow sending new messages while offline (or queue and warn user)

**Failed Messages:**
- Show error indicator (red "!" icon)
- Tap to see error details
- Options: Retry or Delete
- Keep failed messages in local state until resolved

**After Discovery:** Check current network error handling

---

### **11.2 Edge Cases to Handle**

**User Leaves Group:**
- Can still see message history
- Can't send new messages
- Show "You left this group" banner
- Option to delete conversation from list

**Last Person Leaves Group:**
- Group remains in database but inactive
- No one can send messages
- Archive automatically

**Deleted Messages:**
- Soft delete (set deleted_at timestamp)
- Show "This message was deleted" placeholder
- Don't show content
- Reactions may remain visible (your decision)

**Large Messages:**
- Handle messages with 1000+ characters
- Handle long text without breaking layout
- Truncate or allow expansion

**Many Participants:**
- Groups with 50+ members
- Performance considerations
- UI adjustments (don't show all profile pics)

**Rate Limiting:**
- Handle Supabase rate limits gracefully
- Don't spam database with requests
- Batch operations where possible

**After Discovery:** Identify existing edge cases and issues

---

## **12. PERFORMANCE REQUIREMENTS**

### **12.1 Target Metrics**

**Must Achieve:**
- Message send latency: <100ms to appear in sender's UI
- Message receive latency: <200ms via Realtime to receivers
- Scroll performance: Solid 60fps with 500+ messages loaded
- Image upload: <2 seconds for typical photo
- Conversation load time: <1 second
- Memory usage: <100MB for active conversation
- Crash-free rate: >99.9%

**After Discovery:** Measure current performance and identify bottlenecks

---

### **12.2 Optimization Strategies**

**Message List Performance:**
- Use LazyVStack or LazyVGrid (SwiftUI) or proper cell reuse (UIKit)
- Implement pagination (load 50-100 messages initially, more on scroll)
- Prefetch images as they come into viewport
- Cancel image downloads for off-screen cells
- Reuse message bubble views
- Minimize layout calculations
- Debounce scroll events

**Image Handling:**
- Implement image cache (in-memory + disk)
- Progressive loading (show placeholder, load thumbnail, then full image)
- Limit concurrent image downloads (max 3-5)
- Use thumbnails where appropriate
- Cancel downloads for off-screen images
- Compress before upload

**Database Queries:**
- Use proper indexes on conversation_id, created_at, sender_id
- Limit query results (pagination)
- Use efficient joins
- Avoid N+1 query problems
- Cache conversation metadata

**Realtime Efficiency:**
- Subscribe only to active conversation
- Unsubscribe when leaving view
- Batch updates (debounce rapid changes)
- Deduplicate messages by ID
- Handle reconnection without duplicates

**After Discovery:** Profile current performance and identify specific optimizations needed

---

## **13. TESTING REQUIREMENTS**

### **13.1 Core Functionality Test Checklist**

**Must Test:**
- [ ] Send text message (1:1)
- [ ] Receive text message (1:1)
- [ ] Send text message (group)
- [ ] Receive text message (group)
- [ ] Create group chat
- [ ] Add user to group
- [ ] Remove user from group
- [ ] Leave group
- [ ] Send image
- [ ] Receive image
- [ ] Send location
- [ ] Receive location
- [ ] Send audio message
- [ ] Receive audio message
- [ ] Add reaction
- [ ] Remove reaction
- [ ] Reply to message
- [ ] Delete message
- [ ] Report message/user
- [ ] Block user

**Edge Cases to Test:**
- [ ] Send message while offline
- [ ] Receive message while app in background
- [ ] Load conversation with 1000+ messages
- [ ] Send 10 messages rapidly (within 5 seconds)
- [ ] Upload very large image (>10MB)
- [ ] Kill app during message send
- [ ] Force close and reopen mid-conversation
- [ ] Switch between multiple conversations quickly
- [ ] Receive messages in different conversations simultaneously
- [ ] Group with 50+ members
- [ ] Very long text message (5000+ characters)
- [ ] Special characters and emojis in messages
- [ ] Multiple users typing at once

**Performance Tests:**
- [ ] Scroll through 500+ messages at 60fps
- [ ] Load conversation in <1 second
- [ ] Send message appears in <100ms
- [ ] No memory leaks over 30-minute session
- [ ] App remains responsive under load

**Visual/UX Tests:**
- [ ] Matches iMessage bubble design
- [ ] Animations are smooth
- [ ] Colors match app design system
- [ ] Spacing/padding is consistent
- [ ] Dark mode works properly
- [ ] Accessibility features work (VoiceOver, Dynamic Type)

---

### **13.2 Acceptance Criteria**

Before marking as complete, verify:

**Visual Quality:**
- [ ] Message bubbles look like iMessage
- [ ] Animations are smooth and natural
- [ ] Design is consistent with rest of app
- [ ] All UI states look polished
- [ ] Dark mode is properly implemented
- [ ] Layout works on all iOS device sizes

**Functionality:**
- [ ] All messaging features work as specified
- [ ] Real-time updates work consistently
- [ ] No duplicate messages appear
- [ ] Messages stay in chronological order
- [ ] Read receipts update correctly
- [ ] Typing indicators work properly
- [ ] Group features all functional
- [ ] Media sharing works reliably

**Performance:**
- [ ] No lag when typing
- [ ] Smooth scrolling at all times
- [ ] Fast image loading
- [ ] No crashes during testing
- [ ] Reasonable memory usage
- [ ] Battery impact is acceptable

**Integration:**
- [ ] Rest of app still works correctly
- [ ] Navigation flows properly
- [ ] Notifications work
- [ ] Deep linking works (if applicable)
- [ ] Settings integrate properly
- [ ] No broken features

**Code Quality:**
- [ ] Code is well-documented
- [ ] Follows Swift best practices
- [ ] Proper error handling throughout
- [ ] No force-unwrapping optionals
- [ ] Reusable components are extracted
- [ ] Clean architecture maintained

---

## **14. IMPLEMENTATION APPROACH**

### **14.1 Recommended Phases**

**Phase 1: Foundation & Discovery (Week 1)**
- Complete all discovery tasks (Section 2)
- Fix critical Realtime issues
- Ensure database schema supports requirements
- Establish design system documentation
- Create clean service layer architecture
- Get current messaging to "working baseline"

**Phase 2: Core Messaging Polish (Week 2)**
- Implement iMessage-style message bubbles
- Add proper send/receive animations
- Fix keyboard handling completely
- Implement input bar properly
- Add timestamp grouping
- Optimize scroll performance
- Implement optimistic UI for sending

**Phase 3: GROUP CHAT - TOP PRIORITY (Week 3)** ⭐
- Create group creation flow
- Implement user search
- Build group info/settings screen
- Add/remove participants functionality
- Group name and photo
- Profile pictures in group chat bubbles
- System messages
- Test thoroughly with multiple users

**Phase 4: Rich Media (Week 4)**
- Photo sharing with compression
- Fullscreen image viewer
- Location sharing and map preview
- Audio message recording and playback
- Link preview generation
- Media optimization

**Phase 5: Interactions & Social Features (Week 5)**
- Swipe-to-reply gesture
- Long-press context menu
- Reactions (tapback style)
- Typing indicators
- Read receipts
- Double-tap quick react
- Message deletion

**Phase 6: Polish & Settings (Week 6)**
- Conversations list redesign
- Search functionality
- Settings screens
- Reporting and blocking
- Empty states
- Error states
- Loading states

**Phase 7: Testing & Performance (Week 7)**
- Run full test suite
- Performance profiling
- Memory leak detection
- Bug fixing
- User acceptance testing
- Final polish and optimization

---

### **14.2 Critical Implementation Rules**

**1. PRESERVE EXISTING FUNCTIONALITY**
- Don't break other app features during messaging work
- Test navigation to/from messaging regularly
- Verify ride booking still works
- Ensure profile views still work
- Check all related features after changes

**2. USE EXISTING DESIGN SYSTEM**
- Extract and use colors already in codebase
- Match existing spacing, fonts, and patterns
- Maintain app's visual identity
- Only update messaging-specific UI
- Don't introduce new design patterns without review

**3. REAL-TIME MUST WORK PERFECTLY**
- This is non-negotiable
- Fix Supabase Realtime subscriptions properly
- Handle reconnection gracefully
- Deduplicate messages correctly
- Test with multiple devices/users
- Monitor for subscription leaks

**4. GROUP CHAT IS PRIORITY #1**
- Don't deprioritize group features
- Must be fully functional before moving to other features
- User search, add/remove, all group features required
- Test with real multiple-user scenarios
- This is the most important feature in this PRD

**5. INVESTIGATE BEFORE IMPLEMENTING**
- Always check what already exists
- Don't create duplicate files/components
- Modify existing code where possible
- Only create new files when truly needed
- Document why new files were created

**6. ASK BEFORE MAJOR ARCHITECTURAL CHANGES**
- Don't assume your approach is correct
- Present options with pros/cons
- Get approval for significant refactors
- Document architectural decisions
- Explain trade-offs clearly

**7. PERFORMANCE IS A FEATURE**
- Profile before optimizing
- Measure improvements
- Don't sacrifice performance for features
- Test with realistic data volumes
- Monitor memory usage

**8. DOCUMENT EVERYTHING**
- Comment complex code thoroughly
- Explain non-obvious logic
- Note any workarounds or hacks
- Keep README updated
- Document any assumptions

---

## **15. DELIVERABLES**

### **15.1 Discovery Documents** (Before Implementation)

**Required:**
- `CURRENT_STATE.md` - Complete codebase analysis
- `CURRENT_DATABASE.md` - Database schema documentation
- `REALTIME_AUDIT.md` - Realtime implementation review
- `ISSUES_FOUND.md` - All identified problems
- `DESIGN_TOKENS.md` - Design system extraction

**Present these before proceeding with any code changes**

---

### **15.2 Implementation Documents** (During/After)

**Architecture:**
- `ARCHITECTURE_PLAN.md` - Proposed changes and rationale
- `DATABASE_MIGRATION.md` - SQL changes needed (if any)
- `API_CHANGES.md` - New or modified Supabase queries/RPCs

**Testing:**
- `TESTING_CHECKLIST.md` - All test scenarios
- `PERFORMANCE_REPORT.md` - Before/after metrics
- `BUG_LOG.md` - Issues found and resolutions

**Code:**
- Update README with setup instructions
- Comment all new/modified code
- Document any new dependencies
- Explain any workarounds used

---

### **15.3 Code Quality Requirements**

**Every File Should:**
- Have clear, descriptive names
- Include header comments explaining purpose
- Follow Swift naming conventions
- Use proper access control (private, fileprivate, internal, public)
- Have well-organized structure
- Use SwiftLint rules (if project has them)

**Every Function Should:**
- Have a single, clear responsibility
- Use descriptive parameter names
- Handle errors appropriately
- Avoid force-unwrapping optionals (use guard/if let/nil coalescing)
- Include comments for complex logic
- Be reasonably short (<50 lines when possible)

**Data Flow Should:**
- Be unidirectional and predictable
- Use proper separation of concerns
- Have clear boundaries between layers
- Minimize side effects
- Be testable

---

## **16. SUCCESS METRICS (POST-LAUNCH)**

**Track These Metrics:**

**Engagement:**
- Daily active messagers (target: 80% of app users)
- Messages sent per user per day (target: 10+)
- Group chat adoption rate (target: 60% of users in groups)
- Average conversation length (target: 15+ messages)
- Media sharing rate (images, location, audio)

**Performance:**
- Message send success rate (target: >99.9%)
- Average send-to-receive latency (target: <150ms)
- Crash-free rate (target: >99.9%)
- User-reported bugs (target: <5 per 1000 users)
- App Store rating (monitor for changes)

**User Satisfaction:**
- Feature usage rates (reactions, replies, media)
- Support tickets related to messaging
- User feedback sentiment
- Retention rate (should improve)
- Time spent in messaging feature

---

## **17. APPENDIX: DESIGN REFERENCE**

### **17.1 iMessage Study**

**Before implementing any UI, study the actual iMessage app:**

- Bubble styling, spacing, corner radius
- Animation timing and curves (send, receive, keyboard)
- Gesture responsiveness and haptic feedback
- Menu appearance and interaction
- Reaction positioning and animation
- Input bar behavior and keyboard handling
- Typing indicator animation style
- Timestamp formatting and positioning
- Profile picture sizing and placement
- Group chat layout patterns
- Scroll behavior and auto-scroll logic
- Loading states and placeholders

**Take screenshots and notes** - This is the gold standard to match

---

### **17.2 Accessibility Requirements**

**Must Support:**
- VoiceOver navigation
- Dynamic Type (respect user's text size preference)
- Reduce Motion (disable animations if preferred)
- Increase Contrast (adjust colors if needed)
- Voice Control (for hands-free use)
- Switch Control (for adaptive input)

**Test With:**
- VoiceOver enabled
- Largest text size
- Reduce Motion enabled
- Different accessibility settings combinations

---

## **18. FINAL INSTRUCTIONS FOR CURSOR/OPUS**

### **Your Mission:**

Transform Naars Cars messaging into an iMessage-quality experience, with group chat as the #1 priority.

### **Start Here:**

1. **Begin with Discovery** (Section 2)
   - Don't skip this
   - Generate all required documents
   - Present findings
   - Get approval before coding

2. **After Approval, Propose Architecture**
   - Based on what you discovered
   - Show specific changes needed
   - Explain your reasoning
   - Get approval before implementing

3. **Implement Phase by Phase**
   - Follow the recommended phases
   - Don't skip ahead
   - Test after each phase
   - Fix issues before moving forward

4. **Prioritize Group Chat**
   - This is the most important feature
   - Make sure it works perfectly
   - Test with multiple users
   - Don't cut corners here

5. **Maintain Quality**
   - Follow all implementation rules
   - Document your work
   - Ask questions when uncertain
   - Present options for major decisions

### **Remember:**

- **Investigate first, implement second**
- **Modify existing code when possible**
- **Create new files only when necessary**
- **Test thoroughly at each phase**
- **Group chat is the top priority**
- **Real-time must work perfectly**
- **Performance matters**
- **Document everything**

### **Communication:**

- Present discoveries before implementing
- Explain your reasoning for decisions
- Ask questions when requirements are unclear
- Show alternatives for significant choices
- Update progress regularly
- Flag blockers immediately

---

**This PRD is now ready for Cursor/Claude Opus 4.5.**

**Expected workflow:**
1. Load this PRD into Cursor
2. Start with Discovery Phase
3. Present findings
4. Get approval
5. Proceed with implementation phase by phase
6. Build an iMessage-quality messaging experience for Naars Cars

**Good luck! 🚀**
