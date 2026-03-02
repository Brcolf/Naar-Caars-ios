# Messaging iMessage Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the broken reaction overlay and polish the full messaging experience to match iMessage across three phases.

**Architecture:** Phase 1 replaces the `fullScreenCover`-based reaction overlay with a ZStack overlay that keeps the conversation visible behind a blur. Phase 2 fixes bubble tails, sender names, avatars, animations, and input polish. Phase 3 adds group visual refinements.

**Tech Stack:** SwiftUI, UIKit (UIVisualEffectView), Supabase

**Design doc:** `Docs/plans/2026-03-02-messaging-imessage-polish-design.md`

---

## Phase 1: Fix Reaction Overlay (Critical)

### Task 1: Rewrite MessageInteractionOverlay as an inline overlay

**Files:**
- Rewrite: `NaarsCars/UI/Components/Messaging/MessageInteractionOverlay.swift`

The current overlay assumes it's presented via `fullScreenCover`. Rewrite it to work as an inline ZStack overlay that renders on top of the conversation content.

**Key changes:**
- Remove `BlurView` from the overlay itself — the blur will be applied by the parent
- Accept a `messageContent: AnyView` parameter so the parent can pass a snapshot of the tapped message bubble to render at its original position
- Position the reaction picker above the message content and action buttons below
- Use `GeometryReader` to respect safe areas and position content correctly
- The overlay's dismiss still uses the `appeared` state animation

**Step 1:** Rewrite the full file. The overlay should:
- Accept `messageContent: AnyView` to render the tapped message
- Position content vertically: ReactionPicker → message → ActionButtons (centered in screen, adjusted for safe areas)
- Remove `BlurView` (parent handles it)
- Remove `messageFrame`-based positioning (parent handles position context)
- Keep all existing callbacks (onReact, onReply, onCopy, onEdit, onUnsend, onReport, onDismiss)
- Keep the spring appear/disappear animation

**Step 2:** Build and verify no compile errors.

**Step 3:** Commit — `refactor: rewrite MessageInteractionOverlay as inline ZStack overlay`

---

### Task 2: Replace fullScreenCover with ZStack overlay in ConversationDetailView

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

**Step 1: Add frame storage state**

Add a state dictionary to store captured message frames:

```swift
@State private var messageFrames: [UUID: CGRect] = [:]
```

**Step 2: Add `onPreferenceChange` to capture frames**

On the messages list container (around the `MessagesCollectionView` or its parent ZStack at line 459), add:

```swift
.onPreferenceChange(MessageFramePreferenceKey.self) { frames in
    messageFrames = frames
}
```

**Step 3: Replace `.fullScreenCover` with ZStack overlay**

Remove the `.fullScreenCover(isPresented: $showInteractionOverlay)` at line 228 and the `interactionOverlayContent` computed property at lines 329-366.

Instead, wrap the root `VStack` (containing the search bar + `messagesListView`) in a ZStack and add the overlay as a conditional layer:

```swift
ZStack {
    // Existing content
    VStack(spacing: 0) {
        if viewModel.isSearchActive { ... }
        messagesListView
    }

    // Interaction overlay
    if showInteractionOverlay, let message = interactionMessage {
        // Blur backdrop
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showInteractionOverlay = false
                    interactionMessage = nil
                }
            }

        MessageInteractionOverlay(
            message: message,
            messageContent: AnyView(messageBubbleSnapshot(for: message)),
            isFromCurrentUser: isFromCurrentUser(message),
            currentUserReaction: currentUserReaction(for: message),
            onReact: { reaction in
                Task { await viewModel.addReaction(messageId: message.id, reaction: reaction) }
                showInteractionOverlay = false
                interactionMessage = nil
            },
            onReply: { ... },
            onCopy: { ... },
            onEdit: ...,
            onUnsend: ...,
            onReport: ...,
            onDismiss: {
                showInteractionOverlay = false
                interactionMessage = nil
            }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
```

**Step 4: Add `messageBubbleSnapshot` helper**

Create a helper that renders a lightweight version of the tapped message bubble:

```swift
@ViewBuilder
private func messageBubbleSnapshot(for message: Message) -> some View {
    MessageBubble(
        message: message,
        isFromCurrentUser: isFromCurrentUser(message),
        isFirstInSeries: true,
        isLastInSeries: true,
        shouldAnimate: false,
        totalParticipants: totalParticipantsCount
    )
    .allowsHitTesting(false)
}
```

**Step 5: Update `onLongPress` to capture the frame**

```swift
onLongPress: {
    interactionMessage = message
    if let frame = messageFrames[message.id] {
        interactionFrame = frame
    }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
        showInteractionOverlay = true
    }
},
```

**Step 6:** Build and verify.

**Step 7:** Commit — `fix: replace fullScreenCover with ZStack overlay for reactions`

---

### Task 3: Fix long-press gesture with immediate haptic

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (line 549)

**Step 1:** Replace the long-press gesture. Change:

```swift
.onLongPressGesture(minimumDuration: 0.4) {
    HapticManager.mediumImpact()
    onLongPress?()
}
```

To:

```swift
.onLongPressGesture(minimumDuration: 0.4, pressing: { isPressing in
    if isPressing {
        HapticManager.mediumImpact()
    }
}, perform: {
    onLongPress?()
})
```

This fires the haptic immediately when the finger touches (during the `pressing` phase), then triggers the overlay after 0.4 seconds when the gesture is recognized.

**Step 2:** Build and verify.

**Step 3:** Commit — `fix: add immediate haptic feedback on message long-press`

---

### Task 4: Build verification and test

**Step 1:** Full build: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

**Step 2:** Manual verification:
- [ ] Long press a message → haptic fires immediately on touch
- [ ] After 0.4s → overlay appears with conversation visible behind blur
- [ ] Reaction bar and action buttons visible around the message
- [ ] Tap backdrop → overlay dismisses cleanly
- [ ] No black screen trap
- [ ] React to a message → reaction appears as badge overlay
- [ ] All action buttons work (Reply, Copy, Edit, Unsend, Report)

**Step 3:** Commit — `feat: complete Phase 1 — reaction overlay fix`

---

## Phase 2: Conversation Feel Polish

### Task 5: Fix bubble tail shape

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (lines 885-944, `BubbleShape`)

**Problem:** The tail is drawn as a separate subpath from the rounded rect, creating a visible disconnect. The `addRoundedRect` creates one shape, then `move(to:)` starts a new disconnected subpath for the tail.

**Fix:** Draw the entire bubble + tail as a single continuous path. Instead of `addRoundedRect` + separate tail, manually draw all four corners with arcs and integrate the tail into the bottom-right (or bottom-left) corner.

The new `BubbleShape.path(in:)` should:
1. Start at top-left corner
2. Draw top edge → top-right arc → right edge → bottom-right arc
3. For sent messages with tail: Instead of a simple bottom-right arc, transition into a smooth bezier curve that extends down and right to form the tail point, then curves back to meet the bottom edge
4. Continue bottom edge → bottom-left arc → left edge → close

For received messages, mirror the tail to bottom-left.

Key proportions (matching iMessage):
- Corner radius: 18pt (keep existing)
- Tail extends ~8pt below the bubble bottom
- Tail curves out ~6pt from the bubble side
- The transition from bubble to tail should use cubic bezier for smoothness

**Step 1:** Rewrite `BubbleShape.path(in:)` with a single continuous path.

**Step 2:** Build and visual verify in preview.

**Step 3:** Commit — `fix: redesign bubble tail as continuous bezier path (iMessage-style)`

---

### Task 6: Verify group sender names and avatars

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (lines 306-335)

**Sender names** already show at line 331 for `!isFromCurrentUser && totalParticipants > 2 && isFirstInSeries`. Verify this works correctly by reading the code and checking that `message.sender` is populated for all group messages.

**Avatars** at line 306-312 use `AvatarView` which should have initial-letter fallback. The `else` branch (line 312) shows a gray circle when `sender` is nil. Fix: always show the AvatarView with a fallback name:

```swift
AvatarView(
    imageUrl: message.sender?.avatarUrl,
    name: message.sender?.name ?? "?",
    size: 28
)
```

Remove the `if let sender` conditional — always render the AvatarView so the fallback initial works.

**Step 1:** Fix the avatar to always render with fallback.

**Step 2:** Build and verify.

**Step 3:** Commit — `fix: always show avatar with initial fallback in group messages`

---

### Task 7: Send button animation

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageInputBar.swift`

Find the send button and add a scale pulse animation on tap:

```swift
.scaleEffect(isSending ? 0.85 : 1.0)
.animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSending)
```

Use a brief `isSending` state that flips true on tap and resets after 0.2 seconds.

**Step 1:** Add the send button animation.

**Step 2:** Commit — `feat: add send button pulse animation`

---

### Task 8: Message spacing breathing room

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` or `ConversationDetailView.swift`

Find where between-series spacing is set (likely the `VStack(spacing:)` or padding on message rows). Increase between-series gap from 8pt to 12pt.

**Step 1:** Adjust spacing values.

**Step 2:** Commit — `fix: increase message group spacing for breathing room`

---

### Task 9: Haptic on incoming message

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

In the notification handler for new incoming messages (when a message from another user arrives), add:

```swift
if message.fromId != AuthService.shared.currentUserId {
    HapticManager.lightImpact()
}
```

**Step 1:** Add haptic.

**Step 2:** Commit — `feat: add haptic feedback on incoming message`

---

### Task 10: Phase 2 build verification

**Step 1:** Full build.

**Step 2:** Manual verification:
- [ ] Bubble tails seamlessly merge with bubble body
- [ ] Group messages show sender name above first message in series
- [ ] Avatars always show (image or initial, never blank gray circle)
- [ ] Send button pulses on tap
- [ ] Message groups have comfortable breathing room
- [ ] Haptic fires on incoming message

**Step 3:** Commit — `feat: complete Phase 2 — conversation feel polish`

---

## Phase 3: Group Messaging Polish

### Task 11: Group image in conversation header

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

In the toolbar/navigation title area, if the conversation has a `groupImageUrl`, show it. Otherwise show a multi-avatar stack of 2-3 participants.

**Step 1:** Add group avatar to toolbar.

**Step 2:** Commit — `feat: show group image or avatar stack in conversation header`

---

### Task 12: Info button for all conversations

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

Currently the info button only shows for 3+ participants. Show it for DMs too, linking to the other user's profile.

**Step 1:** Remove the `isGroup` guard on the info button.

**Step 2:** Commit — `feat: show info button for all conversations including DMs`

---

### Task 13: Phase 3 build verification

**Step 1:** Full build.

**Step 2:** Manual verification.

**Step 3:** Commit — `feat: complete Phase 3 — group messaging polish`

---

## File Summary

| File | Phase | Tasks |
|------|-------|-------|
| `MessageInteractionOverlay.swift` | 1 | 1 |
| `ConversationDetailView.swift` | 1, 3 | 2, 11, 12 |
| `MessageBubble.swift` | 1, 2 | 3, 5, 6, 8 |
| `MessageInputBar.swift` | 2 | 7 |
| `ConversationDetailViewModel.swift` | 2 | 9 |
