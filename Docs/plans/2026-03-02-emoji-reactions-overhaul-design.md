# Emoji Reactions Overhaul - Design

**Date**: 2026-03-02
**Goal**: Replace the current hardcoded 6-reaction system with an expanded emoji set, full iMessage UX parity, and real-time sync.

---

## Context

Current reactions use `.contextMenu` → center-screen picker → inline capsule pills below messages. Six reactions are hardcoded at the model, UI, and database CHECK constraint levels. No real-time sync exists — reactions only appear after conversation reload.

This overhaul brings the experience to iMessage parity: custom long-press overlay with floating reaction bar, overlay badge display on message corners, tap-to-toggle, and live reaction updates via Supabase Realtime.

---

## 1. Custom Long-Press Overlay (MessageInteractionOverlay)

Replaces `.contextMenu` on `MessageBubble` entirely.

**Flow:**
1. User long-presses a message
2. Haptic feedback fires
3. Full-screen overlay appears with blurred/dimmed background
4. The pressed message is rendered at its original position, slightly scaled up
5. Reaction bar (floating pill) appears above the message
6. Action buttons appear below the message (Reply, Copy, and conditionally Edit/Unsend/Report)
7. Tapping the dimmed background dismisses everything

**Frame capture:** `GeometryReader` + `PreferenceKey` on each message row stores its frame. On long press, the overlay reads the tapped message's frame to position the reaction bar and action buttons relative to the message.

**Blur:** Uses `UIVisualEffectView` via `UIViewRepresentable` (GPU-accelerated) rather than SwiftUI `.blur()`.

**Files:**
- New: `NaarsCars/UI/Components/Messaging/MessageInteractionOverlay.swift`
- Modified: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (remove `.contextMenu`, add long-press gesture)
- Modified: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` (overlay presentation, remove old reaction picker state)

---

## 2. Expanded Emoji Set

**Quick-access row (6 — matches iMessage):**
❤️ 👍 👎 😂 ‼️ ❓

**Expanded tray (~15 extras, shown when "+" tapped):**
🔥 👏 😢 😮 🙏 💯 🎉 😍 🤔 💀 😱 👀 ✅ ❌ 🙌

**Reaction bar UI:**
- Quick-access: horizontal row of 6 emoji buttons in a capsule pill
- "+" button at the end expands to a 5-column grid of extras below the pill
- Tapping any emoji adds the reaction and dismisses the overlay

**Files:**
- New or rewritten: `NaarsCars/UI/Components/Messaging/ReactionPicker.swift`
- Modified: `NaarsCars/Core/Models/MessageReaction.swift` (expand `validReactions`)

---

## 3. Database Changes

- **Remove CHECK constraint** on `message_reactions.reaction` column. Validation moves to app-side only (`MessageReaction.validReactions`). This allows future emoji additions without migrations.
- **Keep UNIQUE constraint** on `(message_id, user_id)` — one reaction per user per message.
- **Migrate existing data**: `UPDATE message_reactions SET reaction = '😂' WHERE reaction = 'HaHa'`
- **Enable Realtime** on `message_reactions` table if not already enabled.

**Files:**
- New migration via Supabase MCP

---

## 4. Reaction Badge Display (iMessage-style)

Replaces inline capsule pills with overlay badges on the message bubble corner.

**Positioning:**
- Sent messages (right-aligned): badge at bottom-leading corner
- Received messages (left-aligned): badge at bottom-trailing corner
- Badge overlaps the message bubble edge by ~8pt

**Badge design:**
- Single capsule containing all unique reaction emojis (16pt each) + total count
- Background: `.ultraThinMaterial` with subtle border and shadow
- Max 5 emojis shown; overflow indicated by count

**Interactions:**
- **Tap badge**: If user has already reacted → toggles their reaction off. If not → opens reaction picker.
- **Long-press badge**: Opens `ReactionDetailsSheet` (who reacted with what).

**Layout impact:** The message row needs slight bottom padding when reactions exist to accommodate the overlapping badge without clipping.

**Files:**
- Modified: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (replace `reactionsView` with overlay badge)
- Modified or rewritten: `NaarsCars/Features/Messaging/Views/ReactionDetailsSheet.swift` (keep as-is, minor updates)

---

## 5. Real-Time Sync

Follows the existing `MessagingSyncEngine` pattern for message real-time updates.

**Subscription:**
- Channel: `"reactions:{conversationId}"` scoped to the active conversation
- Table: `message_reactions`
- Events: INSERT, DELETE
- Subscribe when conversation opens, unsubscribe on exit

**Event handling:**
- INSERT: Parse the reaction record, find the message in the current messages array, add the reaction to its `MessageReactions` dictionary
- DELETE: Parse the record, remove the reaction from the message
- All state updates dispatched to `@MainActor`

**Files:**
- Modified: `NaarsCars/Core/Storage/MessagingSyncEngine.swift` (add reactions subscription)
- Modified: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift` (handle reaction updates)
- Modified: `NaarsCars/Core/Services/RealtimeManager.swift` (add `"reactions:"` to protected channels if needed)

---

## 6. Performance Safeguards

- **Overlay is ephemeral**: Only exists while active, not embedded in every message cell
- **Blur via UIKit**: `UIVisualEffectView` is GPU-composited, no main thread cost
- **Animations on render server**: SwiftUI `.animation(.spring())` runs off main thread
- **Optimistic UI**: Reaction mutations are instant local dictionary updates (microseconds), network call is fire-and-forget with rollback on error
- **Real-time events**: Received on background thread, dispatched to `@MainActor` for minimal state update
- **No new ViewModels**: Overlay receives data via closures, no additional `ObservableObject` subscriptions
- **SwiftData**: No new SwiftData models needed — reactions remain in-memory on Message objects, synced via network

---

## Files Summary

| File | Action |
|------|--------|
| `MessageInteractionOverlay.swift` | New — custom long-press overlay |
| `ReactionPicker.swift` | Rewrite — quick-access row + expanded grid |
| `MessageBubble.swift` | Modify — remove `.contextMenu`, add long-press, overlay badge |
| `ConversationDetailView.swift` | Modify — overlay presentation, remove old picker state |
| `MessageReaction.swift` | Modify — expand `validReactions` |
| `MessageReactionService.swift` | Modify — remove server-side validation of reaction set |
| `MessagingSyncEngine.swift` | Modify — add reactions real-time subscription |
| `ConversationDetailViewModel.swift` | Modify — handle real-time reaction events |
| `ReactionDetailsSheet.swift` | Minor updates |
| Database migration | Remove CHECK constraint, migrate HaHa→😂, enable realtime |
