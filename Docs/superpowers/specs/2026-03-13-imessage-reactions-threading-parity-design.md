# iMessage Reactions & Threading Visual Parity

**Date:** 2026-03-13
**Status:** Draft
**Goal:** Make message reactions and threading in Naars Cars visually match iMessage on iOS 18.

---

## Context

Naars Cars messaging already implements reactions (tapbacks) and inline reply threading, but several visual details diverge from iMessage. This spec covers 6 targeted changes to close the gap.

**Key files affected:**
- `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift`
- `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift`
- `NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift`
- `NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift`
- `NaarsCars/Core/Models/MessageReaction.swift`
- `NaarsCars/Core/Services/MessageService.swift`
- `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`
- `NaarsCars/Features/Messaging/Views/ReactionDetailsSheet.swift`

---

## Change 1: Overlapping Reaction Capsules

### Current
Separate capsules per reaction type laid out with 4pt gap: `[👍]  [❤️ 2]`

### Target
Same separate capsules but overlapping each other to create a stacked/grouped appearance, similar to iMessage's compact badge cluster.

### Design

**ReactionBadgeView changes:**
- Change `capsuleSpacing` from `4` to a negative overlap value of approximately `-6pt`
- In `layoutSubviews`, each subsequent capsule starts at `previousCapsule.maxX + overlapOffset` where `overlapOffset ≈ -6`
- Add `zPosition` layering: first capsule gets highest z-index, each subsequent capsule tucks behind
  - `item.view.layer.zPosition = CGFloat(capsules.count - index)`
- The existing 2pt `systemBackground` border on each capsule creates clean visual separation between overlapping pills

**Sizing changes:**
- `sizeThatFits` must account for overlap: `totalW += s.width + overlapOffset` (instead of `+ capsuleSpacing`)
- No other styling changes — background, border, shadow, corner radius all stay the same

**Interaction unchanged:**
- Tap on any visible capsule → reaction details or overlay
- Long-press → reaction details sheet showing who reacted with what
- Max 5 capsules shown

---

## Change 2: Apple Tapback Glyphs via SF Symbols

### Current
Standard Unicode emoji for all reactions (❤️ 👍 👎 😂 ‼️ ❓) rendered as text labels.

### Target
SF Symbol glyphs with iOS 18 Tapback colors for the 6 core reactions. Extended reactions remain standard emoji.

### SF Symbol Mapping

| Reaction String | SF Symbol Name | Tint Color |
|----------------|---------------|------------|
| ❤️ | `heart.fill` | `.systemRed` |
| 👍 | `hand.thumbsup.fill` | `.systemYellow` |
| 👎 | `hand.thumbsdown.fill` | `.systemGray` |
| 😂 | `face.smiling` | `.systemGreen` |
| ‼️ | `exclamationmark.2` | `.systemOrange` |
| ❓ | `questionmark` | `.systemPurple` |

### New Utility: TapbackGlyph

**File:** `NaarsCars/UI/Components/Messaging/TapbackGlyph.swift`

```swift
enum TapbackGlyph {
    /// Returns a colored SF Symbol UIImage for the 6 core Tapback reactions.
    /// Returns nil for extended emoji reactions (caller falls back to text rendering).
    static func image(for reaction: String, pointSize: CGFloat) -> UIImage?
}
```

**Rendering sizes:**
- Badge (ReactionBadgeView capsules): 13pt
- Picker bar (ReactionBarView buttons): 22pt
- Details sheet (ReactionDetailsSheet headers): 18pt

### Where SF Symbols Render

1. **ReactionBadgeView** — `ReactionCapsuleView` checks `TapbackGlyph.image(for:pointSize:)`. If non-nil, displays a `UIImageView` instead of the `emojiLabel`. If nil, falls back to current text label rendering.
2. **ReactionBarView** — First 6 buttons use SF Symbol images with tint colors instead of emoji text titles. Remaining 15 extended emoji buttons unchanged.
3. **ReactionDetailsSheet** — Section headers for core 6 reactions display the SF Symbol glyph alongside the count.

### Data Layer

No changes. Reactions are stored as emoji strings in the database. SF Symbol rendering is purely a display-layer concern.

---

## Change 3: Curved Reply Spine

### Current
Straight vertical `CAShapeLayer` line in `MessageCellView`, 2pt width, `secondaryLabel` at 0.35 alpha.

```swift
path.move(to: CGPoint(x: spineX, y: topY))
path.addLine(to: CGPoint(x: spineX, y: bottomY))
```

### Target
iMessage-style gently curved connector between reply preview and reply message.

### Design

The existing spine uses `replySpine: (showTop: Bool, showBottom: Bool)?` to draw a continuous vertical line that extends to cell edges, connecting consecutive replies in the same thread across multiple cells. The curve behavior must respect this multi-cell spanning:

**Spine cases:**
- `showTop = false, showBottom = true` (first reply in chain): Spine starts from the reply preview area and curves down to the cell bottom edge
- `showTop = true, showBottom = true` (middle of chain): Straight vertical line from cell top to cell bottom (no curve needed — it's a continuation)
- `showTop = true, showBottom = false` (last reply in chain): Straight line from cell top, ending at the content bubble area
- `showTop = false, showBottom = false` (single reply, not in chain): Short curved connector from reply preview to content bubble

**Curve implementation** (for the start/end of chains):
- Replace `addLine(to:)` with `addCurve(to:controlPoint1:controlPoint2:)` where the spine begins or ends
- Control points create a gentle curve rather than a hard right angle
- For received messages: spine X is at `avatarSize / 2` (center of avatar column)
- For sent messages: spine X is at `contentView.maxX + 4`

**Stroke styling:** 2pt line width, `secondaryLabel.withAlphaComponent(0.35)`, no fill. Add `spineLayer.lineCap = .round` (currently defaults to `.butt`).

---

## Change 4: "N Replies" Badge on Parent Messages

### Current
No reply count indicator. Users discover threads only via the long-press context menu "View Thread" action.

### Target
Tappable "N Replies" label below parent messages that have replies.

### Data Layer

**New Supabase RPC function (migration required):**

A new database function is needed because the Supabase PostgREST query builder cannot express `GROUP BY` + `COUNT` aggregations directly.

```sql
-- Migration: xxx_add_reply_count_rpc.sql
CREATE OR REPLACE FUNCTION get_reply_counts(p_conversation_id UUID, p_message_ids UUID[])
RETURNS TABLE(parent_id UUID, reply_count BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT reply_to_id, COUNT(*)
  FROM messages
  WHERE conversation_id = p_conversation_id
    AND reply_to_id = ANY(p_message_ids)
    AND deleted_at IS NULL
  GROUP BY reply_to_id;
$$;
```

**New service method:**
```swift
// MessageService.swift
func fetchReplyCounts(conversationId: UUID, messageIds: [UUID]) async throws -> [UUID: Int]
```
- Calls Supabase `.rpc("get_reply_counts", params: ...)` — consistent with existing codebase patterns
- Returns map of parentMessageId → replyCount

**ViewModel hydration:**
- `ConversationDetailViewModel` gains `replyCountMap: [UUID: Int]`
- New method `loadReplyCountsForMessages()` called after `loadMessages()`, modeled on `loadReactionsForMessages()`
- Fetches counts for all loaded messages in a single batch RPC call
- Real-time updates: when a new message with `replyToId` arrives via sync, increment the count for that parent locally. When a message is deleted, re-fetch counts to stay accurate (same pattern as `refreshReactions`).

**Data flow: ViewModel → Config → Cell:**
- `MessagesCollectionView` receives `replyCountMap: [UUID: Int]` as a new init parameter (alongside existing `messages`, `reactions`, etc.)
- `Coordinator.setupDataSource` reads from this map when constructing `MessageCellConfig`
- Add `replyCount: Int` to `MessageCellConfig`
- Passed as `replyCountMap[message.id] ?? 0`

### UI

**New subview in MessageCellView:**
- `replyCountLabel: UILabel` — `.caption1` font, `naarsPrimary` color
- Positioned below the timestamp row, same horizontal alignment as message content
- Text: `"1 Reply"` / `"N Replies"` (localized via `String.localizedStringWithFormat`)
- Hidden when `replyCount == 0`

**Interaction:**
- Tap gesture on `replyCountLabel` → calls new delegate method `messageCellDidTapViewThread(_ cell:, message:)` on `MessageCellDelegate`
- `MessageCellDelegate` protocol gains this new method (in `MessageCellConfig.swift`)
- `MessagesCollectionView.Coordinator` (which conforms to `MessageCellDelegate`) handles the call by forwarding to `ConversationDetailView` via an `onViewThread` closure
- `ConversationDetailView` sets `activeThreadParent = message` — the same state mechanism used by `OverlayAction.viewThread(UUID)` — to present `MessageThreadViewController`

**Visibility rule:**
- Shown on messages where `replyCount > 0`
- Shown regardless of whether the message itself is a reply (a reply can also be a thread root)

**Layout impact:**
- When visible, adds ~18pt to cell height (label height + 4pt top spacing)
- `sizeThatFits` must account for this

---

## Change 5: Reaction Badge Vertical Position

### Current
Badge centered on bubble top edge (50% above, 50% below):
```swift
rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height / 2, ...)
```

### Target
Badge shifted to ~60% above bubble edge (matching iMessage):
```swift
rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height * 0.6, ...)
```

One-line change in `MessageCellView.layoutSubviews()` line 491.

---

## Change 6: Long-Press Speed

### Current
0.5s `minimumPressDuration` on the message cell long-press gesture recognizer.

### Target
0.3s to match iMessage's snappy feel.

**Location:** `MessageCellView` initialization where the long-press gesture is configured. Change `minimumPressDuration` from `0.5` to `0.3`.

---

## Files Changed Summary

| File | Changes |
|------|---------|
| `ReactionBadgeView.swift` | Overlap layout, SF Symbol rendering in capsules, z-position layering |
| `TapbackGlyph.swift` | **New file** — SF Symbol mapping utility |
| `ReactionBarView.swift` | SF Symbol buttons for core 6 Tapbacks |
| `ReactionDetailsSheet.swift` | SF Symbol glyphs in section headers |
| `MessageCellView.swift` | Badge vertical offset, curved spine bezier, reply count label, long-press duration |
| `MessageCellConfig.swift` | Add `replyCount: Int` field, add `messageCellDidTapViewThread` delegate method |
| `MessageService.swift` | Add `fetchReplyCounts()` RPC method |
| `ConversationDetailViewModel.swift` | Reply count hydration, `replyCountMap` state |
| `MessagesCollectionView.swift` | Accept `replyCountMap` param, pass `replyCount` when building `MessageCellConfig`, forward `didTapViewThread` to parent |
| `ConversationDetailView.swift` | Pass `replyCountMap` to `MessagesCollectionView`, handle `onViewThread` callback |
| `database/xxx_add_reply_count_rpc.sql` | **New migration** — `get_reply_counts` RPC function |

## Edge Cases

- **Reactions + reply count on same message:** Both can appear simultaneously. The reaction badge floats above the bubble (Change 5), the reply count label sits below the timestamp. Height accounting is additive — `sizeThatFits` sums both contributions.
- **Reply that is also a thread root:** A message can have both `replyToId` (it's a reply) and `replyCount > 0` (it has replies). The cell shows reply preview above, content, and reply count below. Visual density is acceptable since this is uncommon.
- **Zero reactions / zero replies:** No badge shown, no reply count label. No layout impact.

## Out of Scope

- Changing the reply preview accent bar color (keeping `naarsPrimary`)
- Changing the reply preview background styling
- Double-tap to react gesture
- Full emoji keyboard in reaction picker (iOS 18 feature)
- Denormalized `reply_count` column in DB (using query-time RPC counts instead)
