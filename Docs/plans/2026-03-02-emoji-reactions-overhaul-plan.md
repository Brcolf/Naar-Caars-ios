# Emoji Reactions Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the hardcoded 6-reaction system with an expanded emoji set, custom iMessage-style long-press overlay, overlay badge display, tap-to-toggle, and real-time sync.

**Architecture:** A new `MessageInteractionOverlay` replaces `.contextMenu` on messages. It captures the tapped message's frame via preference keys, presents a blurred full-screen overlay with the message "lifted", a floating reaction bar above, and action buttons below. Reaction badges move from inline pills to overlay capsules on the message bubble corner. Real-time sync follows the existing `MessagingSyncEngine` + `RealtimeManager` pattern.

**Tech Stack:** SwiftUI, Supabase (PostgREST + Realtime), UIKit (blur effect via UIViewRepresentable)

**Design doc:** `Docs/plans/2026-03-02-emoji-reactions-overhaul-design.md`

---

### Task 1: Database Migration — Expand Reactions

Remove the CHECK constraint so any emoji string is accepted, migrate "HaHa" to "😂", and enable Realtime on the table.

**Step 1: Apply migration via Supabase MCP**

```sql
-- Remove CHECK constraint on reaction column
ALTER TABLE message_reactions DROP CONSTRAINT IF EXISTS message_reactions_reaction_check;

-- Migrate legacy "HaHa" text reactions to emoji
UPDATE message_reactions SET reaction = '😂' WHERE reaction = 'HaHa';

-- Enable Realtime on message_reactions (adds to supabase_realtime publication)
ALTER PUBLICATION supabase_realtime ADD TABLE message_reactions;
```

**Step 2: Verify migration**

Query `message_reactions` to confirm no "HaHa" rows remain and that a non-standard emoji can be inserted.

**Step 3: Commit** — `feat(db): remove reaction CHECK constraint, migrate HaHa, enable realtime`

---

### Task 2: Expand Valid Reactions in Model

**Files:**
- Modify: `NaarsCars/Core/Models/MessageReaction.swift` (line 41)
- Modify: `NaarsCars/Core/Services/MessageReactionService.swift` (line 46)

**Step 1: Update `MessageReaction.validReactions`**

Replace the static list in `MessageReaction.swift` line 41:

```swift
/// Quick-access reactions (iMessage set)
static let quickReactions = ["❤️", "👍", "👎", "😂", "‼️", "❓"]

/// Extended curated reactions
static let extendedReactions = ["🔥", "👏", "😢", "😮", "🙏", "💯", "🎉", "😍", "🤔", "💀", "😱", "👀", "✅", "❌", "🙌"]

/// All valid reactions
static let validReactions = quickReactions + extendedReactions
```

Also remove the `"HaHa"` case from the comment on line 14.

**Step 2: Update validation in `MessageReactionService.swift`**

Line 46 — the guard check against `validReactions` already works dynamically since it reads from the static property. No change needed to the logic itself, but remove the hardcoded error message that lists individual reactions:

```swift
guard MessageReaction.validReactions.contains(reaction) else {
    throw AppError.invalidInput("Invalid reaction")
}
```

**Step 3: Build and verify** — `xcodebuild` should pass.

**Step 4: Commit** — `feat: expand valid reactions to 21 curated emojis`

---

### Task 3: Rewrite ReactionPicker with Quick-Access + Expanded Grid

**Files:**
- Rewrite: `NaarsCars/UI/Components/Messaging/ReactionPicker.swift`

**Step 1: Rewrite ReactionPicker**

The new picker has two states: collapsed (quick-access row of 6 + "+" button) and expanded (adds a 5-column grid of 15 extras below).

```swift
import SwiftUI

struct ReactionPicker: View {
    let currentUserReaction: String?
    let onReactionSelected: (String) -> Void
    let onDismiss: () -> Void

    @State private var showExtended = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 8) {
            // Quick-access row
            HStack(spacing: 10) {
                ForEach(MessageReaction.quickReactions, id: \.self) { reaction in
                    reactionButton(reaction)
                }

                // Expand button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showExtended.toggle()
                    }
                } label: {
                    Image(systemName: showExtended ? "chevron.up" : "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .accessibilityLabel(showExtended ? "Show fewer reactions" : "Show more reactions")
            }

            // Extended grid
            if showExtended {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(MessageReaction.extendedReactions, id: \.self) { reaction in
                        reactionButton(reaction)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }

    private func reactionButton(_ reaction: String) -> some View {
        let isSelected = currentUserReaction == reaction
        return Button {
            HapticManager.selectionChanged()
            onReactionSelected(reaction)
            onDismiss()
        } label: {
            Text(reaction)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.naarsPrimary.opacity(0.2) : Color.clear)
                .clipShape(Circle())
                .scaleEffect(isSelected ? 1.15 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("React with \(reaction)")
    }
}
```

**Step 2: Build and verify.**

**Step 3: Commit** — `feat: rewrite ReactionPicker with quick-access row and expanded grid`

---

### Task 4: Create MessageInteractionOverlay

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/MessageInteractionOverlay.swift`

This is the core new component. It replaces `.contextMenu` with a custom full-screen overlay on long press.

**Step 1: Create the overlay view**

The overlay receives:
- The message to act on
- The message's frame in the scroll view coordinate space
- Callbacks for all actions (react, reply, copy, edit, unsend, report)
- The current user's existing reaction (if any)

Key design decisions:
- Uses `UIVisualEffectView` wrapped in `UIViewRepresentable` for GPU-accelerated blur
- Positions reaction picker above the message frame, action buttons below
- Tap on dimmed background dismisses
- Spring animation on appear/disappear

```swift
import SwiftUI

struct MessageInteractionOverlay: View {
    let message: Message
    let messageFrame: CGRect
    let isFromCurrentUser: Bool
    let currentUserReaction: String?

    // Action callbacks
    let onReact: (String) -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onEdit: (() -> Void)?
    let onUnsend: (() -> Void)?
    let onReport: (() -> Void)?
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Blurred background
            BlurView(style: .systemUltraThinMaterialDark)
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
                .onTapGesture { dismiss() }

            VStack(spacing: 8) {
                // Reaction picker above message
                ReactionPicker(
                    currentUserReaction: currentUserReaction,
                    onReactionSelected: { reaction in
                        onReact(reaction)
                        dismiss()
                    },
                    onDismiss: { dismiss() }
                )
                .padding(.horizontal, 16)

                // Placeholder for message preview (keeps spatial context)
                Spacer()
                    .frame(height: messageFrame.height)

                // Action buttons
                actionButtons
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .position(
                x: UIScreen.main.bounds.width / 2,
                y: messageFrame.midY
            )
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 0) {
            actionButton("Reply", icon: "arrowshape.turn.up.left", action: { onReply(); dismiss() })

            if !message.text.isEmpty {
                Divider()
                actionButton("Copy", icon: "doc.on.doc") {
                    UIPasteboard.general.string = message.text
                    HapticManager.selectionChanged()
                    onCopy()
                    dismiss()
                }
            }

            if let onEdit, !message.text.isEmpty, !message.isAudioMessage, !message.isLocationMessage {
                Divider()
                actionButton("Edit", icon: "pencil") { onEdit(); dismiss() }
            }

            if let onUnsend, message.canUnsend {
                Divider()
                actionButton("Unsend", icon: "arrow.uturn.backward", isDestructive: true) { onUnsend(); dismiss() }
            }

            if let onReport {
                Divider()
                actionButton("Report", icon: "exclamationmark.bubble", isDestructive: true) { onReport(); dismiss() }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actionButton(_ title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.naarsBody)
                Spacer()
                Image(systemName: icon)
            }
            .foregroundColor(isDestructive ? .red : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}

// MARK: - UIKit Blur Wrapper

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}
```

**Step 2: Add to Xcode project** — Verify the file is included in the build target.

**Step 3: Build and verify.**

**Step 4: Commit** — `feat: add MessageInteractionOverlay with blur, reaction bar, and action menu`

---

### Task 5: Add Frame Capture to MessageBubble

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

**Step 1: Create a PreferenceKey for message frames**

Add above the `MessageBubble` struct definition:

```swift
struct MessageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
```

**Step 2: Add GeometryReader to capture frame**

In the `regularMessageView` body (around line 284), wrap the existing outermost container with a background GeometryReader:

```swift
.background(
    GeometryReader { geo in
        Color.clear.preference(
            key: MessageFramePreferenceKey.self,
            value: [message.id: geo.frame(in: .named("messageList"))]
        )
    }
)
```

**Step 3: Replace `.contextMenu` with long-press gesture**

Remove the `.contextMenu { ... }` block (lines 520-589) and replace with:

```swift
.onLongPressGesture(minimumDuration: 0.4) {
    HapticManager.mediumImpact()
    onLongPress?()
}
```

**Step 4: Add new callback for frame-aware long press**

Add a new callback property to MessageBubble:

```swift
var onLongPressWithFrame: ((CGRect) -> Void)? = nil
```

Update the long press gesture to pass the frame (the frame will be read from preference keys by the parent — ConversationDetailView).

**Step 5: Build and verify.**

**Step 6: Commit** — `feat: add message frame capture and replace contextMenu with long-press gesture`

---

### Task 6: Replace Reaction Display with Overlay Badges

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (lines 391-394 and 807-838)

**Step 1: Replace `reactionsView` with overlay badge**

Remove the current inline call at lines 391-394 and the `reactionsView` function at lines 807-838.

Add an overlay badge on the message bubble content. The badge should:
- Appear at bottom-leading for sent messages, bottom-trailing for received
- Overlap the bubble edge by ~8pt
- Show grouped emojis with total count in a capsule

```swift
private func reactionBadge(reactions: MessageReactions) -> some View {
    let sorted = reactions.sortedReactions.prefix(5)
    let totalCount = reactions.reactions.values.reduce(0) { $0 + $1.count }

    return HStack(spacing: 2) {
        ForEach(sorted, id: \.reaction) { data in
            Text(data.reaction)
                .font(.system(size: 14))
        }
        if totalCount > 1 {
            Text("\(totalCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(
        Capsule()
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    )
    .overlay(
        Capsule()
            .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
    )
}
```

**Step 2: Apply as overlay on the message content VStack**

In `regularMessageView`, apply the badge as an `.overlay()` with alignment based on `isFromCurrentUser`:

```swift
.overlay(alignment: isFromCurrentUser ? .bottomLeading : .bottomTrailing) {
    if let reactions = message.reactions, !reactions.reactions.isEmpty {
        reactionBadge(reactions: reactions)
            .offset(y: 12) // Overlap the bubble edge
            .onTapGesture {
                // Toggle own reaction or show picker
                if let userId = AuthService.shared.currentUserId,
                   reactions.allUserIds.contains(userId) {
                    onReactionTap?(nil) // Signal to remove own reaction
                } else {
                    onLongPress?() // Open picker
                }
            }
            .onLongPressGesture {
                onReactionTap?("__details__") // Signal to show details sheet
            }
    }
}
.padding(.bottom, (message.reactions?.reactions.isEmpty == false) ? 10 : 0)
```

**Step 3: Update `onReactionTap` callback** to accept an optional String:

```swift
var onReactionTap: ((String?) -> Void)? = nil
```

**Step 4: Build and verify.**

**Step 5: Commit** — `feat: replace inline reaction pills with iMessage-style overlay badges`

---

### Task 7: Integrate Overlay in ConversationDetailView

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

**Step 1: Replace reaction state variables**

Replace the old state (lines 28-33):

```swift
// Message interaction overlay state
@State private var interactionMessage: Message?
@State private var interactionFrame: CGRect = .zero
@State private var showInteractionOverlay = false
// Keep existing:
@State private var showReactionDetails = false
@State private var reactionDetailsMessage: Message?
@State private var reactionProfiles: [String: [Profile]] = [:]
```

**Step 2: Add coordinate space to ScrollView**

Add `.coordinateSpace(name: "messageList")` to the message scroll view.

**Step 3: Add preference key reader**

On the message list, add:

```swift
.onPreferenceChange(MessageFramePreferenceKey.self) { frames in
    // Store frames for overlay positioning (only when overlay is about to show)
}
```

**Step 4: Remove old ReactionPicker overlay** (lines 512-542)

**Step 5: Add MessageInteractionOverlay presentation**

```swift
.fullScreenCover(isPresented: $showInteractionOverlay) {
    if let message = interactionMessage {
        MessageInteractionOverlay(
            message: message,
            messageFrame: interactionFrame,
            isFromCurrentUser: isFromCurrentUser(message),
            currentUserReaction: currentUserReaction(for: message),
            onReact: { reaction in
                Task { await viewModel.addReaction(messageId: message.id, reaction: reaction) }
            },
            onReply: {
                replyingToMessage = ReplyContext(from: message)
            },
            onCopy: { /* already handled in overlay */ },
            onEdit: isFromCurrentUser(message) ? {
                viewModel.startEditing(message)
            } : nil,
            onUnsend: (isFromCurrentUser(message) && message.canUnsend) ? {
                showUnsendConfirmation = true
                messageToUnsend = message
            } : nil,
            onReport: {
                messageToReport = message
                showReportSheet = true
            },
            onDismiss: {
                showInteractionOverlay = false
                interactionMessage = nil
            }
        )
        .background(Color.clear)
    }
}
.transaction { $0.disablesAnimations = true } // Let overlay handle its own animations
```

**Step 6: Update MessageBubble callbacks**

Update `onLongPress` callback in the message row builder to set the overlay state:

```swift
onLongPress: {
    interactionMessage = message
    // Frame will be read from preference key
    showInteractionOverlay = true
},
```

**Step 7: Add helper for current user's reaction**

```swift
private func currentUserReaction(for message: Message) -> String? {
    guard let userId = AuthService.shared.currentUserId,
          let reactions = message.reactions else { return nil }
    return reactions.reactions.first(where: { $0.value.contains(userId) })?.key
}
```

**Step 8: Build and verify.**

**Step 9: Commit** — `feat: integrate MessageInteractionOverlay in ConversationDetailView`

---

### Task 8: Add Real-Time Reaction Sync

**Files:**
- Modify: `NaarsCars/Core/Storage/MessagingSyncEngine.swift`
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Step 1: Add reactions subscription in MessagingSyncEngine**

Add a new function following the `setupMessagesSubscription` pattern (line 144):

```swift
func setupReactionsSubscription(conversationId: UUID) {
    Task {
        // We filter by conversation's messages using a Supabase filter
        // Since message_reactions doesn't have conversation_id directly,
        // we subscribe to all reaction changes and filter client-side
        await realtimeManager.subscribe(
            channelName: "reactions:\(conversationId.uuidString)",
            table: "message_reactions",
            onInsert: { [weak self] record in
                self?.handleReactionChange(record, conversationId: conversationId)
            },
            onDelete: { [weak self] record in
                self?.handleReactionChange(record, conversationId: conversationId)
            }
        )
    }
}

func teardownReactionsSubscription(conversationId: UUID) {
    Task {
        await realtimeManager.unsubscribe(channelName: "reactions:\(conversationId.uuidString)")
    }
}

private func handleReactionChange(_ event: RealtimeRecord, conversationId: UUID) {
    guard let messageIdString = event.record["message_id"] as? String,
          let messageId = UUID(uuidString: messageIdString) else { return }

    NotificationCenter.default.post(
        name: .messageReactionChanged,
        object: nil,
        userInfo: ["messageId": messageId, "conversationId": conversationId]
    )
}
```

**Step 2: Add notification name**

In `NotificationNames.swift`, add:

```swift
static let messageReactionChanged = Notification.Name("messageReactionChanged")
```

**Step 3: Handle reaction changes in ConversationDetailViewModel**

Add a notification observer in init:

```swift
NotificationCenter.default.publisher(for: .messageReactionChanged)
    .receive(on: RunLoop.main)
    .sink { [weak self] notification in
        guard let self,
              let messageId = notification.userInfo?["messageId"] as? UUID,
              let convId = notification.userInfo?["conversationId"] as? UUID,
              convId == self.conversationId else { return }
        Task {
            await self.refreshReactions(for: messageId)
        }
    }
    .store(in: &cancellables)
```

Add the refresh function:

```swift
private func refreshReactions(for messageId: UUID) async {
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    do {
        let reactions = try await MessageReactionService.shared.fetchReactions(messageId: messageId)
        messages[index].reactions = reactions.reactions.isEmpty ? nil : reactions
    } catch {
        AppLogger.error("messaging", "Failed to refresh reactions: \(error)")
    }
}
```

**Step 4: Subscribe/unsubscribe on conversation open/close**

In `ConversationDetailViewModel.loadMessages()`, after loading:

```swift
MessagingSyncEngine.shared.setupReactionsSubscription(conversationId: conversationId)
```

In `deinit` or `stop()`:

```swift
MessagingSyncEngine.shared.teardownReactionsSubscription(conversationId: conversationId)
```

**Step 5: Build and verify.**

**Step 6: Commit** — `feat: add real-time reaction sync via Supabase Realtime`

---

### Task 9: Integration Testing and Polish

**Step 1: Manual testing checklist**

- [ ] Long press a message → overlay appears with blur, reaction bar, action buttons
- [ ] Tap an emoji → reaction appears as overlay badge on message corner
- [ ] Tap the same emoji again → reaction is removed (toggle)
- [ ] Tap "+" → extended emoji grid appears with animation
- [ ] Pick an extended emoji → works correctly
- [ ] Tap dimmed background → overlay dismisses
- [ ] All action buttons work: Reply, Copy, Edit, Unsend, Report
- [ ] Reaction badge shows on correct corner (leading for sent, trailing for received)
- [ ] Multiple reactions from different users show grouped in badge
- [ ] Long-press reaction badge → shows ReactionDetailsSheet
- [ ] Real-time: Second device/session adds reaction → appears live
- [ ] Scroll performance not degraded with reaction badges

**Step 2: Clean up old code**

- Remove any unused state variables from ConversationDetailView
- Remove the old `showReactionPicker`/`reactionPickerMessageId` state if still present
- Delete old overlay code (lines 512-542 of ConversationDetailView)
- Remove `onLongPress` from MessageBubble if replaced

**Step 3: Commit** — `chore: clean up old reaction picker code`

**Step 4: Final build verification** — `xcodebuild`

**Step 5: Commit** — `feat: complete emoji reactions overhaul with iMessage parity`

---

## File Summary

| File | Action | Task |
|------|--------|------|
| Database migration | New | 1 |
| `MessageReaction.swift` | Modify | 2 |
| `MessageReactionService.swift` | Modify | 2 |
| `ReactionPicker.swift` | Rewrite | 3 |
| `MessageInteractionOverlay.swift` | Create | 4 |
| `MessageBubble.swift` | Modify | 5, 6 |
| `ConversationDetailView.swift` | Modify | 7 |
| `MessagingSyncEngine.swift` | Modify | 8 |
| `ConversationDetailViewModel.swift` | Modify | 8 |
| `NotificationNames.swift` | Modify | 8 |
| `ReactionDetailsSheet.swift` | Minor updates | 7 |
