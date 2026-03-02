# Messaging iMessage Polish — Design

**Date**: 2026-03-02
**Goal**: Fix the broken reaction overlay and polish the messaging experience to match iMessage across three phases.

---

## Context

The reaction overlay implemented via `fullScreenCover` is architecturally wrong — it creates a modal that hides the conversation, resulting in a disconnected dark screen. Additionally, the message bubble tails appear disconnected, group chats lack sender names and reliable avatars, and micro-interactions (haptics, animations, scroll) need polish to feel native.

---

## Phase 1: Fix Reaction Overlay (Critical)

### Problem
`fullScreenCover` is a separate modal layer. The conversation disappears behind it. If the animation fails, the user is trapped on a black screen. The long-press gesture has no immediate haptic and may fire on release.

### Fix: ZStack Overlay

Replace `fullScreenCover(isPresented: $showInteractionOverlay)` with a conditional ZStack overlay on ConversationDetailView's root container:

```
ConversationDetailView
  └─ ZStack
       ├─ Conversation content (messages, input bar)
       └─ if showInteractionOverlay:
            ├─ BlurView (conversation visible beneath)
            ├─ Tapped message re-rendered at captured frame position
            ├─ ReactionPicker (positioned above message frame)
            └─ Action buttons (positioned below message frame)
```

**Key behaviors:**
- Conversation stays visible behind the blur (it's underneath in the same view tree)
- The tapped message is rendered at its original screen position using `MessageFramePreferenceKey` data
- Tap anywhere on the blurred backdrop dismisses
- No fullScreenCover, no modal, no black screen trap

### Fix: Long-Press Gesture

Replace `.onLongPressGesture(minimumDuration: 0.4)` with the three-callback form:

```swift
.onLongPressGesture(minimumDuration: 0.4, pressing: { isPressing in
    if isPressing {
        HapticManager.mediumImpact()       // Immediate feedback
        withAnimation(.easeOut(duration: 0.15)) {
            messageScaleEffect = 0.97       // Subtle shrink hint
        }
    } else {
        withAnimation(.spring()) {
            messageScaleEffect = 1.0
        }
    }
}) {
    showInteractionOverlay = true           // Show overlay after 0.4s
}
```

### Files
- Rewrite: `MessageInteractionOverlay.swift` — Remove `fullScreenCover` assumption, accept `messageContent` view to render
- Modify: `ConversationDetailView.swift` — Replace `fullScreenCover` with ZStack overlay, store captured frames
- Modify: `MessageBubble.swift` — Use `pressing:` callback, add scale state

---

## Phase 2: Conversation Feel Polish

### 2A. Bubble Tail Redesign

**Problem**: Current tail is visually disconnected from the bubble body — it looks like a separate shape stuck on the side rather than a natural extension.

**Fix**: Rewrite `BubbleShape` to use a continuous bezier path where the tail curves seamlessly out of the bubble's bottom corner. The tail should:
- Flow naturally from the bubble's corner radius
- Use a quadratic bezier that starts at the bubble's edge (not offset from it)
- Match iMessage's proportions: small, subtle, ~6pt wide at base tapering to a point

**File**: `MessageBubble.swift` — `BubbleShape` struct (~lines 884-944)

### 2B. Group Sender Names

**Problem**: In group chats, you can't tell who sent which message without tapping.

**Fix**: Show the sender's first name above the first message in each series (when sender != current user), in a small secondary-colored label. This matches iMessage's group chat behavior exactly.

**File**: `MessageBubble.swift` — Add sender name label in `regularMessageView` when `isFirstInSeries && !isFromCurrentUser && showAvatar` (showAvatar is the group indicator)

### 2C. Group Avatars

**Problem**: Avatars sometimes show blank/missing when a user has no profile photo.

**Fix**: The existing `AvatarView` component should already handle this (it shows initials as fallback). Verify that `sender.name` and `sender.avatarUrl` are always populated on group messages. The issue is likely that `sender` is nil on some messages (e.g., optimistic sends, realtime inserts without join).

**File**: `MessageBubble.swift`, `MessageService.swift` (ensure sender join), `MessagingSyncEngine.swift` (ensure sender data on realtime events)

### 2D. Send Animation

**Problem**: No visual feedback when the send button is tapped.

**Fix**:
- Send button: Subtle scale pulse (1.0 → 0.85 → 1.0) on tap
- New message: Already has spring slide-in animation. Verify it triggers correctly for sent messages.

**File**: `MessageInputBar.swift` — Add `.scaleEffect` animation on send button

### 2E. Input Bar Polish

**Problem**: Input bar may feel stiff compared to iMessage's fluid auto-grow.

**Fix**:
- Verify auto-grow height is smooth (TextEditor/TextField should animate height changes)
- Verify keyboard avoidance uses `.safeAreaInset` or equivalent for smooth transitions
- Ensure attachment button (+) and send button have consistent touch targets (44pt min)

**File**: `MessageInputBar.swift`

### 2F. Scroll Behavior

**Problem**: Scroll-to-bottom, position maintenance, and pull-to-load need to feel tighter.

**Fix**:
- Verify `scrollTo` uses `.bottom` anchor with animation on new messages
- Verify scroll position is preserved when loading older messages (existing `anchorMessageId` logic)
- Ensure the scroll-to-bottom FAB appears only when scrolled up significantly (not on every small scroll)

**File**: `ConversationDetailView.swift` — Scroll proxy logic

### 2G. Swipe-to-Reply Bounce

**Problem**: Static opacity feedback on swipe. Should have spring physics.

**Fix**: Add horizontal offset that follows the drag gesture with spring dampening. Show reply icon revealed behind the bubble as it slides.

**File**: `MessageBubble.swift` — Swipe gesture handling

### 2H. Spacing Breathing Room

**Problem**: Messages feel slightly cramped between series.

**Fix**: Increase between-series vertical gap from 8pt to 12pt. Add 4pt extra when sender changes + timestamp shows.

**File**: `MessageBubble.swift` or `ConversationDetailView.swift` — Message spacing logic

### 2I. Haptic on Receive

**Fix**: Light impact haptic when an incoming message arrives while app is in foreground.

**File**: `ConversationDetailViewModel.swift` or `MessagingSyncEngine.swift` — On new message notification

---

## Phase 3: Group Messaging Polish

### 3A. Group Image in Header
Show the group image (or a multi-avatar stack of 2-3 participants) in the conversation toolbar instead of just text names.

### 3B. Info Button for All Conversations
Show the info button for DMs (2 participants) too — linking to the other person's profile, shared media, and mute/block options.

### 3C. Stacked Avatars in Conversation List
Group conversations show 2-3 overlapping participant avatars in the list row instead of a single avatar or placeholder.

---

## Implementation Priority

| Phase | Priority | Scope |
|-------|----------|-------|
| Phase 1 | Critical | Fix overlay architecture — currently broken |
| Phase 2 | High | Conversation feel — makes the whole messaging experience native |
| Phase 3 | Medium | Group visual polish — nice-to-have refinements |
