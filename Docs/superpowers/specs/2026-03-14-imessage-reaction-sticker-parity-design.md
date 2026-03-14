# iMessage Reaction Sticker Parity

**Date:** 2026-03-14
**Status:** Approved
**Goal:** Unify the reaction system to match iMessage iOS 18 — per-person sticker badges, curated picker with extended emoji support, inline reaction details, and custom HAHA artwork.

---

## Context

The current reaction system has several inconsistencies with iMessage:

1. **Two rendering systems coexist** — 6 core reactions render as SF Symbol images via `TapbackGlyph`, while 15 extended reactions render as emoji text labels. At the same 22pt point size, these produce visually different sizes in the picker.
2. **Aggregated capsule badges** — reactions display as aggregated pills with counts (e.g., "❤️ 3") instead of per-person sticker badges with speech-bubble shapes.
3. **Selected state** — picker uses blue tint at 0.25 alpha + 1.15x scale transform, which breaks the uniform button grid. iMessage uses a solid blue filled circle at consistent size.
4. **Reaction set is defined in 3 places** — `MessageReaction.swift`, `ReactionBarView.swift`, and `TapbackGlyph.swift` with no single source of truth.
5. **Reaction details** — shown in a separate SwiftUI sheet, not inline in the overlay like iMessage.
6. **Fixed reaction set** — users are limited to 21 hardcoded reactions instead of being able to use any emoji.

### Approach

**Approach C: Rebuild badge, refactor picker, extend overlay.**

- **Rebuild** the badge view (per-person stickers are a fundamentally different data model than aggregated capsules)
- **Refactor** the picker bar (incremental: trim standard set, add recents + emoji button, fix selected state)
- **Extend** the overlay controller (add inline reaction details row)
- **Replace** the reaction details sheet with inline overlay details
- **Simplify** TapbackGlyph to HAHA-only custom artwork
- **Update** the reaction model to allow any emoji

The service layer, realtime sync, database schema, and optimistic update flow remain untouched. The ViewModel and `Message` model require minor additions to expose individual reaction records for per-person badge rendering.

---

## Section 1: Reaction Model Changes

### Files
- `NaarsCars/Core/Models/MessageReaction.swift`
- `NaarsCars/Core/Models/Message.swift`
- `NaarsCars/Core/Services/MessageReactionService.swift`

### Changes

**MessageReaction.swift:**
- Remove `quickReactions`, `extendedReactions`, `validReactions` static arrays
- Remove the `isValid` computed property
- Add a single `standardTapbacks` static array containing the 6 iMessage reactions: `["❤️", "👍", "👎", "😂", "‼️", "❓"]`
  - Note: `😂` is stored as the emoji but rendered as custom "HA HA" artwork in the UI layer. The model stores the emoji; the view layer handles the custom rendering.
- Any emoji string is now a valid reaction (no validation constraint)

**Message.swift:**
- Add a new optional property: `var individualReactions: [MessageReaction]?` alongside the existing `reactions: MessageReactions?`
- This stores the raw per-user reaction records needed by the sticker badge view

**Data source of truth invariant:**

`individualReactions` is the single UI source of truth for reaction state. The aggregated `MessageReactions` is derived from it — never independently fetched or stored. The invariant:

1. All reaction mutations (load, realtime update, optimistic update, removal) write to `individualReactions` first.
2. `reactions: MessageReactions?` is a computed or lazily-derived aggregation of `individualReactions`. It may be cached for performance, but it is never mutated independently.
3. If `individualReactions` is nil, `reactions` must also be nil. If `individualReactions` is empty, `reactions` must be nil or empty.
4. `MessageSendManager` optimistic updates must update `individualReactions` (inserting/removing a `MessageReaction` record), then re-derive `reactions` from the updated array.
5. `ConversationDetailViewModel.refreshReactions(for:)` fetches via `fetchIndividualReactions`, stores the result on `message.individualReactions`, and derives `message.reactions` from it.

This eliminates the synchronization risk of two independently-stored representations drifting apart.

**MessageReactionService.swift:**
- Remove the validation check against `validReactions` in `addReaction()` — accept any emoji string
- Add a new method `fetchIndividualReactions(messageId:) -> [MessageReaction]` that returns the raw decoded records (the existing `fetchReactions` already decodes them internally before aggregating — extract and expose this step)
- All other service logic (upsert, delete, fetch, participant check) remains unchanged

**Database:**
- No schema changes. The `message_reactions` table already uses `TEXT` with no `CHECK` constraint — validation was purely at the application layer.

---

## Section 2: Picker Bar (ReactionBarView Refactor)

### File
- `NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift`

### Changes

**Layout:**
- Keep the scrollable horizontal `UIStackView` inside `UIScrollView` with blur background
- First 6 items: the standard tapbacks from `MessageReaction.standardTapbacks`
  - ❤️, 👍, 👎 — rendered as emoji (UIButton title)
  - HAHA — rendered using `TapbackArtwork` custom view (not 😂 emoji, not SF Symbol)
  - ‼️, ❓ — rendered as emoji (UIButton title)
- After the 6: recently used emoji (tracked per-user, persisted via `UserDefaults`)
- Thin vertical divider (1pt, white at 0.2 alpha) between reaction items and the emoji keyboard button
- Emoji keyboard button at the end: smiley face icon in a circle with `rgba(255,255,255,0.12)` background — tapping it presents the system emoji keyboard

**Selected state:**
- Solid `UIColor.systemBlue` background (no alpha) on the button's `layer.backgroundColor`
- No scale transform — button stays at the existing `buttonSize` (40pt × 40pt)
- Remove `CGAffineTransform(scaleX: 1.15, y: 1.15)`

**Single source of truth:**
- Remove the duplicated `allReactions` Unicode escape array
- Reference `MessageReaction.standardTapbacks` for the 6 standard reactions
- Recent emoji managed separately via a local `RecentReactionsStore` (UserDefaults-backed, stores last ~15 used emoji)

**Emoji keyboard integration:**
- Use a hidden `UITextField` with `becomeFirstResponder()` to present the system emoji keyboard
- On emoji input, fire `onReact` callback and dismiss the keyboard
- Restrict input to emoji-only (validate via `Character.isActualEmoji` from `EmojiDetection.swift`)

> **Implementation risk:** The hidden `UITextField` approach is the preferred initial implementation for accessing the system emoji keyboard. However, it has known risks: responder chain conflicts with the overlay's backdrop tap-to-dismiss gesture, keyboard dismissal edge cases when the overlay animates out, and potential focus issues if the text field competes with other responders. If keyboard behavior proves unstable during development, fall back to a dedicated emoji picker surface (e.g., a grid-based `UICollectionView` of emoji organized by category) instead of the system keyboard.

---

## Section 3: Sticker Badge (New ReactionStickerBadgeView)

### Files
- **New:** `NaarsCars/UI/Components/Messaging/Cells/ReactionStickerBadgeView.swift`
- **Delete:** `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift`

### Design

**Per-person stickers (not aggregated capsules):**
- Each reaction record (from `MessageReaction`) gets its own sticker view
- Sticker shape: rounded rect with asymmetric corner radii — three large corners + one small corner (bottom-leading) to create the speech-bubble tail effect
  - Approximate: `UIBezierPath` with `cornerRadius: 14` on top-left, top-right, bottom-right, and `cornerRadius: 4` on bottom-left
- Size: ~28-30pt diameter
- Content: emoji rendered as text, except HAHA which uses `TapbackArtwork`

> **Tuning note:** The geometry constants above (corner radii, sticker size, overlap spacing, X/Y offsets) are initial values derived from visual analysis of iMessage screenshots. They should be treated as tunable starting points and adjusted after visual testing across text bubbles, image bubbles, short messages, long messages, and sent vs. received layouts. Extract them as named constants at the top of `ReactionStickerBadgeView` for easy adjustment.

**Color coding:**
- Current user's reaction: `UIColor.systemBlue` background
- Other users' reactions: `UIColor.systemGray` at ~0.6 alpha (dark mode) / `UIColor.systemGray5` (light mode)

**Layout:**
- Overlapping z-order: newest (rightmost) sticker on top, ~8pt horizontal overlap
- `layer.zPosition` increases left to right (newest = highest)
- Positioned at top-trailing corner of the message bubble (same anchor as current)
- X: `primary.frame.maxX - badgeWidth - 4` for received, `primary.frame.minX + 4` for sent
- Y: `primary.frame.minY - badgeHeight * 0.6` (60% above top edge)

**Ordering rules:**
- Stickers are ordered by `createdAt` ascending (oldest left, newest right)
- Z-order follows the same direction: `layer.zPosition` increases left to right, so the newest sticker renders on top of the stack
- This produces deterministic, stable ordering — new reactions always append to the right and sit on top visually
- If two reactions share the same `createdAt` timestamp, break ties by `userId` (lexicographic UUID sort) for stability

**Compact overflow mode (4+ unique reaction types):**

When the number of unique reaction types exceeds 3, the badge switches to a compact fallback that prioritizes layout stability over per-person fidelity. This is an intentional tradeoff — rendering every per-person sticker at scale would overflow the bubble's top edge and create visual clutter, especially on short messages or narrow image bubbles.

- Show max 3 unique reaction-type stickers, selected by count descending (most popular reactions shown)
- Ties broken by earliest `createdAt` among each type's records
- All rendered in gray (no blue/gray user distinction in compact mode)
- Each shows the emoji only (no avatar context, no per-person attribution)
- Tapping compact badges opens the overlay with full per-person reaction details
- This is not full iMessage parity for dense cases — iMessage has more layout space and proprietary logic for dense stacking. Compact mode is a pragmatic approximation.

**Data hydration:**
- Badge receives `[MessageReaction]` (individual records with userId) instead of `MessageReactions` (aggregated dictionary)
- `ConversationDetailViewModel` exposes the individual records via a new computed property or by keeping them alongside the aggregated data
- Badge uses `currentUserId` to determine blue/gray coloring

**Interaction:**
- Tap: opens the `MessageOverlayController` with reaction details pre-populated
- No long-press behavior needed on the badge itself

---

## Section 4: Inline Reaction Details (Replaces ReactionDetailsSheet)

### Files
- **New:** `NaarsCars/UI/Components/Messaging/Overlay/ReactionDetailsRowView.swift`
- **Delete:** `NaarsCars/Features/Messaging/Views/ReactionDetailsSheet.swift`
- **Modified:** `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift`
- **Modified:** `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

### Design

**ReactionDetailsRowView:**
- Horizontal scrollable `UIScrollView` containing a `UIStackView`
- Each item is a vertical stack:
  - Large sticker (~48-52pt) in speech-bubble shape with gray background
  - User avatar/initials circle (~24pt) below the sticker
- If multiple users reacted with the same emoji, their avatars overlap below that single sticker
- Styled with dark blur background (`systemUltraThinMaterial`), rounded corners (16pt)

**Ordering rules:**
- Reaction groups are ordered by count descending (most popular reaction type first)
- Ties broken by earliest `createdAt` among each group's records
- Within each group, avatars are ordered by `createdAt` ascending (earliest reactor first, newest last in the overlap stack)

**Integration with MessageOverlayController:**
- Details row is positioned above the message snapshot, below the picker bar
- Layout order top-to-bottom: picker bar → details row → message snapshot → action list
- Details row is shown when:
  1. User taps on reaction badges on a message (overlay opens with details visible)
  2. User long-presses a message that already has reactions (details visible by default)
- Details row is hidden when the message has no reactions
- Requires `[MessageReaction]` individual records and profile data (avatar URLs, display names) for the avatar circles

**Profile data for avatars:**
- The existing `ConversationDetailView.refreshReactionProfiles(for:)` method fetches `Profile` objects for reactors — this logic moves into `ConversationDetailViewModel` as a new method
- Profile data is passed through to `MessageOverlayController` when presenting, which forwards it to `ReactionDetailsRowView`

**ConversationDetailView.swift cleanup:**
- Remove `@State private var showReactionDetails: Bool`
- Remove `@State private var reactionDetailsMessage: Message?`
- Remove `@State private var reactionProfiles: [String: [Profile]]`
- Remove the `.sheet(isPresented: $showReactionDetails)` modifier that presents `ReactionDetailsSheet`
- Remove the `reactionDetailsContent` computed property
- Remove the `refreshReactionProfiles(for:)` method
- Remove the `"__details__"` sentinel handling in `onReactionTap` — badge taps now go directly through the overlay flow

**Remove own reaction:**
- User can tap their own reaction sticker in the details row to remove it
- Fires the existing `onRemoveReaction` callback through the overlay

**Animation:**
- Details row fades in with the same entrance animation as the picker bar (0.3s, damping 0.85)
- Slides in from the same direction as the picker bar (±10pt offset)

---

## Section 5: TapbackGlyph → TapbackArtwork

### File
- `NaarsCars/UI/Components/Messaging/TapbackGlyph.swift` → rename to `TapbackArtwork.swift`

### Changes

- Remove the 6-entry mapping array
- Remove SF Symbol rendering for ❤️, 👍, 👎, ‼️, ❓
- Single purpose: render the custom "HA HA" artwork for the laugh tapback
- API: `static func hahaImage(pointSize: CGFloat) -> UIImage`
  - Renders "HA HA" text in a stacked layout with bold weight and blue color (`UIColor.systemBlue`)
  - Uses `UIGraphicsImageRenderer` to produce a rasterized image at the requested point size
- Also provide: `static func isHaha(_ reaction: String) -> Bool` — checks if a reaction string matches the 😂 emoji (which should be rendered as HAHA)
- Update `NaarsCars/NaarsCarsTests/Features/Messaging/TapbackGlyphTests.swift` to match the new API (rename to `TapbackArtworkTests.swift`)

---

## Section 6: Wiring Changes

### MessageCellView.swift
- Replace `reactionBadge: ReactionBadgeView?` with `reactionStickerBadge: ReactionStickerBadgeView?`
- Pass individual `[MessageReaction]` records and `currentUserId` to the badge instead of aggregated `MessageReactions`
- Badge tap opens the overlay with details (new delegate method or callback)

### MessagesViewController.swift
- Handle the new badge-tap entry point: present `MessageOverlayController` with `showDetails: true` flag
- Remove any references to `ReactionDetailsSheet` presentation
- The `onReactionTap` callback in `MessagesViewController.Configuration` may need signature changes or the `"__details__"` sentinel pattern may become obsolete — badge taps now go through the overlay directly

### MessagesViewControllerRepresentable.swift
- Update the `onReactionTap` callback wiring to match any signature changes in `MessagesViewController.Configuration`

### ConversationDetailViewModel.swift
- Expose individual `MessageReaction` records per message (not just aggregated `MessageReactions`)
- The service already decodes individual records internally — use the new `fetchIndividualReactions` method and store results on `Message.individualReactions`
- Move the `refreshReactionProfiles(for:)` logic from `ConversationDetailView` into the ViewModel so profile data is available for the overlay's inline details row

### ConversationDetailView.swift
- Remove all `ReactionDetailsSheet`-related state, modifiers, and methods (see Section 4 for full list)

### MessageOverlayController.swift
- Add `ReactionDetailsRowView` as a subview
- Accept a `showDetails: Bool` flag to control whether details are visible on entry
- Update layout constraints to accommodate the details row between picker and snapshot
- Pass reaction data and current user ID to the details row

---

## Untouched Components

These components require **no changes**:
- Database schema (`message_reactions` table)
- `MessagingSyncEngine` (realtime subscription)
- `MessageReactions` struct (aggregated model still used by ViewModel, now derived from `individualReactions`)
- All message bubble views (TextBubbleView, ImageBubbleView, etc.)
- Audio, location, link preview components
- Reply/threading system
- Read receipts

**Minimal changes (data invariant only):**
- `MessageSendManager` — optimistic update methods (`addReaction`, `removeReaction`) must be updated to mutate `individualReactions` and re-derive `reactions` per the data source of truth invariant (Section 1). The overall optimistic-update-with-rollback pattern is unchanged.

**Implicitly affected (no direct changes needed):**
- `MessageThreadViewController.swift` — reuses `MessageCellView` via `ThreadMessageCell`, so the badge swap propagates automatically. The badge-tap-to-overlay flow should be verified in thread context.
- `MessagesCollectionView.swift` — defines `MessageContentCell` hosting `MessageCellView`, implicitly affected by the property rename.
- `project.pbxproj` — file deletions, additions, and the `TapbackGlyph` → `TapbackArtwork` rename require Xcode project file updates.

### Consolidated File Manifest

| Action | File |
|--------|------|
| **New** | `NaarsCars/UI/Components/Messaging/Cells/ReactionStickerBadgeView.swift` |
| **New** | `NaarsCars/UI/Components/Messaging/Overlay/ReactionDetailsRowView.swift` |
| **Rename** | `TapbackGlyph.swift` → `TapbackArtwork.swift` |
| **Rename** | `TapbackGlyphTests.swift` → `TapbackArtworkTests.swift` |
| **Delete** | `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift` |
| **Delete** | `NaarsCars/Features/Messaging/Views/ReactionDetailsSheet.swift` |
| **Modify** | `NaarsCars/Core/Models/MessageReaction.swift` |
| **Modify** | `NaarsCars/Core/Models/Message.swift` |
| **Modify** | `NaarsCars/Core/Services/MessageReactionService.swift` |
| **Modify** | `NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift` |
| **Modify** | `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift` |
| **Modify** | `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift` |
| **Modify** | `NaarsCars/Features/Messaging/Views/MessagesViewController.swift` |
| **Modify** | `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift` |
| **Modify** | `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` |
| **Modify** | `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift` |
| **Modify** | `NaarsCars/Features/Messaging/ViewModels/MessageSendManager.swift` |

### Deprecation note
- The new `ReactionStickerBadgeView` should use the modern `UITraitChangeObservable` registration API instead of `traitCollectionDidChange(_:)`, which is deprecated in iOS 17+.

---

## Verification Checklist

- [ ] Picker shows 6 standard tapbacks + recents + emoji button in scrollable row
- [ ] All 6 tapbacks render at visually consistent sizes (no SF Symbol / emoji mismatch)
- [ ] HAHA tapback renders as custom "HA HA" artwork, not 😂 emoji
- [ ] Selected reaction in picker shows solid blue circle, no scale transform
- [ ] Emoji keyboard button opens system emoji keyboard and accepts any emoji
- [ ] Sticker badges show per-person speech-bubble stickers (not aggregated capsules)
- [ ] Current user's sticker is blue, others are gray
- [ ] 4+ unique reaction types truncate to ~3 compact badge stickers
- [ ] Tapping badges opens overlay with inline reaction details
- [ ] Reaction details show large sticker + user avatar per reaction
- [ ] User can remove their own reaction from the details row
- [ ] Details row animates in with the overlay entrance
- [ ] Extended emoji reactions (from picker) render at visually consistent sizes with standard tapbacks in the picker bar
- [ ] `individualReactions` and derived `reactions` remain synchronized after:
  - [ ] Initial message load
  - [ ] Realtime update from another user
  - [ ] Optimistic update (local react)
  - [ ] Reaction removal
- [ ] Realtime reaction updates still work (other user reacts → badge updates)
- [ ] Optimistic UI updates still work (instant local feedback on react)
- [ ] Dark mode and light mode both render correctly
- [ ] Cell reuse / `prepareForReuse` works correctly with new badge view
- [ ] Accessibility: sticker badges have meaningful labels
- [ ] Sticker badge rendering is correct across:
  - [ ] Text bubbles (short and long messages)
  - [ ] Image bubbles
  - [ ] Sent messages
  - [ ] Received messages
- [ ] No regressions in message cell layout for all bubble types
