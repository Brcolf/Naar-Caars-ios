# iMessage Parity — Messaging Module Design Spec

**Date:** 2026-03-12
**Status:** Approved (brainstorming)
**Scope:** 13 improvements to bring the NaarsCars messaging module closer to iMessage's UI/UX

---

## Overview

Following a detailed gap analysis comparing the NaarsCars messaging module to iMessage (iOS 17/18), 13 issues were selected for implementation. These range from single-constant tweaks to a full UIKit port of the input bar. All changes are backward compatible and designed to avoid breaking existing functionality.

### Issues Addressed

| # | Issue | Category | Effort |
|---|-------|----------|--------|
| 18 | Reaction badge positioning | UI fix | Easy |
| 2 | Text padding asymmetry | UI fix | Easy |
| 8 | Message grouping spacing | UI fix | Easy |
| 10 | Max bubble width | UI fix | Easy |
| 17 | Typing indicator pulse | UI fix | Easy |
| 19 | Long-press overlay scale | UI fix | Easy |
| 20 | Conversation list avatar + row height | UI fix | Easy |
| 23 | Avatar size consistency | UI fix | Easy |
| 7 | Emoji enlargement | New feature | Medium |
| 6 | Image bubble aspect ratio | UI fix + migration | Medium |
| 22 | Scroll-to-first-unread | New feature | Medium |
| 5 | Interactive keyboard dismissal | Architecture | Hard |
| 12 | Input bar design overhaul | UI rework | Hard |

### Issues Explicitly Skipped

- **#9** (Read receipt style): Keeping current checkmark style per user preference
- **#28-31** (Bubble effects, screen effects, text effects, text formatting): Deferred to future phase due to data model complexity

---

## Section 1: Reaction Badge Positioning (Issue #18)

**Most critical issue per user.**

### Current Behavior
Reaction badges sit at the top of the first content view, offset by half their height. For sent messages, positioned at `primary.frame.minX`; for received, at `primary.frame.maxX - width`.

### Target Behavior
iMessage places reaction badges overlapping the **top-trailing corner** of the bubble (received messages) and **top-leading corner** (sent messages). The badge peeks ~50% above the bubble's top edge and overlaps ~8pt inward.

### Changes

**File: `MessageCellView.swift` — `layoutSubviews()`**

Current badge positioning logic (around line 466-469):
```swift
let rbX = config.isFromCurrentUser ? primary.frame.minX : primary.frame.maxX - rbSize.width
rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height / 2, width: rbSize.width, height: rbSize.height)
```

New positioning:
- **Sent messages:** `rbX = primary.frame.minX + 8` (leading edge, opposite the tail)
- **Received messages:** `rbX = primary.frame.maxX - rbSize.width - 8` (trailing edge, opposite the tail)
- **Vertical:** `primary.frame.minY - rbSize.height / 2` (unchanged — half above, half below the bubble top edge)

**File: `ReactionBadgeView` (if exists)**

Add a 2pt `systemBackground`-colored border around the badge capsule so it visually separates from the bubble when overlapping.

### Impact
Layout-only change in one file plus a border addition. Zero risk to functionality.

---

## Section 2: Text Bubble Tuning (Issues #2, #8, #10)

### Issue #2 — Padding Asymmetry

**File: `TextBubbleView.swift`**

| Property | Current | Target |
|----------|---------|--------|
| `vPad` | 10pt | 7pt |
| `hPad` | 14pt (uniform) | 14pt interior / 18pt tail side |

When `showTail` is false, use 14pt on both sides (no tail to accommodate).

**Layout changes in `layoutSubviews()` and `sizeThatFits()`:**
- Compute `interiorPad = 14` and `tailPad = showTail ? 18 : 14`
- For sent messages (tail right): left padding = `interiorPad`, right padding = `tailPad`
- For received messages (tail left): left padding = `tailPad`, right padding = `interiorPad`
- Adjust `textOriginX` and width calculations accordingly

### Issue #10 — Max Bubble Width

**File: `MessageCellView.swift`**

Change `bounds.width * 0.7` → `bounds.width * 0.75` in:
- `layoutSubviews()` (line 429)
- `sizeThatFits()` (line 548)

### Issue #8 — Grouping Spacing

**File: `MessageCellView.swift`**

Current spacing logic in `sizeThatFits()` (line 568):
```swift
let verticalPadding: CGFloat = config.isLastInSeries ? 8 : 2
```

Change to apply gap above a new series start rather than below a series end:
```swift
let verticalPadding: CGFloat = config.isFirstInSeries ? 8 : 2
```

This puts the 8pt gap *above* a new sender's first message, matching iMessage's visual rhythm. 2pt between same-sender messages stays.

### Impact
Pure layout/constant changes. No data model or logic changes.

---

## Section 3: Emoji Enlargement (Issue #7)

### Detection Logic

New utility function (e.g., in a `EmojiDetection.swift` file or as an extension):

```swift
func isEmojiOnlyMessage(_ text: String) -> (isEmojiOnly: Bool, count: Int)
```

- Trims whitespace
- Checks every `Character` in the string has `isEmoji` property (Unicode property check via scalar properties)
- Returns `(true, count)` if all characters are emoji and count is 1-3
- Returns `(false, 0)` otherwise

### New View: `EmojiBubbleView.swift`

A lightweight UIKit view:
- Single `UILabel` with `.systemFont(ofSize: 42)`
- No `CAShapeLayer` background — no bubble shape, no fill color
- `sizeThatFits` returns label intrinsic size plus 4pt margins
- Alignment follows same sent/received logic as text bubbles
- Accessibility: label set to the emoji text, trait `.staticText`
- `prepareForReuse` clears the label

### Integration in `MessageCellView.showRegular()`

Before creating the `TextBubbleView`, check `isEmojiOnlyMessage(msg.text)`:
- If `true`: instantiate/show `EmojiBubbleView` instead of `TextBubbleView`
- If `false`: use existing `TextBubbleView` as-is

Add `emojiBubble: EmojiBubbleView?` as a lazy property alongside `textBubble`, `imageBubble`, etc.
Add to `visibleContentViews()`, `hideAllContent()`, and `prepareForReuse()`.

### Impact
New file `EmojiBubbleView.swift`, small detection utility, branching logic in `MessageCellView`. Existing text rendering completely untouched.

---

## Section 4: Input Bar UIKit Port + Interactive Keyboard (Issues #5, #12)

### Architecture

The SwiftUI `MessageInputBar` is replaced by a UIKit `UIView` subclass that serves as the `inputAccessoryView` on the conversation's view controller. This enables `keyboardDismissMode = .interactive` on the collection view.

### New File: `MessageInputAccessoryView.swift`

**Layout (top to bottom):**
1. Hairline separator (1px `UIColor.separator`)
2. Context banner area (reply banner / edit banner / recording banner — conditionally shown)
3. Image preview thumbnail (conditionally shown)
4. Input row: Plus button → Text view container → Send button

**Background:**
- `UIVisualEffectView` with `UIBlurEffect(style: .systemMaterial)` — translucent blur
- No shadow (replaced by hairline separator)

**Text input:** `UITextView` (not `UITextField`) for multi-line:
- Wrapped in a custom rounded rect container view
- 20pt corner radius, `quaternaryLabel` border (1px)
- Grows from 1 line to 5 lines max, then scrolls internally
- `intrinsicContentSize` override for auto-resizing
- Placeholder `UILabel` overlay ("Type a message...") — hidden when `textView.text` is non-empty

**Buttons:**
- Plus button: `UIButton` with `plus.circle.fill` SF Symbol, `naarsPrimary` tint, triggers `UIMenu` (camera, photos, voice note, location)
- Send button: `UIButton` with `arrow.up.circle.fill` SF Symbol, `naarsPrimary` when enabled, `systemGray` when disabled
- Spring scale animation on send tap (same timing: 0.15s down to 0.8, 0.2s back to 1.0)

**Banners (UIKit ports of existing SwiftUI):**
- Reply banner: vertical accent bar (3pt, `naarsPrimary`) + "Replying to [name]" + preview + cancel button
- Edit banner: vertical accent bar + "Editing" + original text preview + cancel button
- Recording banner: pulsing red dot + "Recording..." + duration label + cancel + send buttons
- All banners animate in/out with `UIView.animate` (move from bottom + opacity)

### Delegate Protocol: `MessageInputDelegate`

```swift
protocol MessageInputDelegate: AnyObject {
    func inputBar(_ bar: MessageInputAccessoryView, didSendText text: String)
    func inputBarDidRequestImagePicker(_ bar: MessageInputAccessoryView)
    func inputBarDidRequestCamera(_ bar: MessageInputAccessoryView)
    func inputBar(_ bar: MessageInputAccessoryView, didRecordAudio url: URL, duration: Double)
    func inputBar(_ bar: MessageInputAccessoryView, didShareLocation lat: Double, lon: Double, name: String?)
    func inputBarDidCancelReply(_ bar: MessageInputAccessoryView)
    func inputBarDidCancelEdit(_ bar: MessageInputAccessoryView)
    func inputBarDidChangeTypingState(_ bar: MessageInputAccessoryView)
}
```

### Integration

**MessagesCollectionView controller (the UIViewController hosting the collection view):**
- Override `var inputAccessoryView` to return the `MessageInputAccessoryView` instance
- Override `var canBecomeFirstResponder` to return `true`
- Set `collectionView.keyboardDismissMode = .interactive`
- Implement `MessageInputDelegate` and forward events to `ConversationDetailViewModel`

**ConversationDetailView.swift:**
- Remove `MessageInputBar` from the SwiftUI `VStack`
- The input bar is now owned by the UIKit view controller, not the SwiftUI view hierarchy
- Reply/edit context is passed to the input bar via `setReplyContext(_:)` / `setEditContext(_:)` methods

**Risk mitigation:**
- `MessageInputBar.swift` (SwiftUI) is kept in the project but no longer referenced from `ConversationDetailView`. It can be deleted once the UIKit version is validated.

### Audio Recording

All recording logic ports directly:
- `AVAudioRecorder` setup identical (M4A, 44.1kHz, 1 channel, high quality)
- Permission check via `AVAudioApplication.requestRecordPermission()` (iOS 17+) with fallback
- Duration timer: `Timer.scheduledTimer` at 1.0s interval
- Haptic feedback on record start
- Minimum 1s duration before send

### Location Sharing

- Plus menu "Location" action presents `LocationPickerSheet` (kept as SwiftUI, presented via `UIHostingController` in a sheet from the view controller)

### Photo Picker

- Plus menu "Photos" action triggers delegate method
- `ConversationDetailView` still handles `PhotosPicker` presentation (SwiftUI) and passes selected image back to the input bar via `setImagePreview(_:)`

---

## Section 5: Image Bubble Aspect Ratio (Issue #6)

### Supabase Migration

Add two nullable columns to the `messages` table:

```sql
ALTER TABLE messages ADD COLUMN image_width integer;
ALTER TABLE messages ADD COLUMN image_height integer;
```

### Message Model Changes

**`Message.swift`:**
- Add `imageWidth: Int?` and `imageHeight: Int?` properties

**`SDMessage` (SwiftData):**
- Add `imageWidth: Int?` and `imageHeight: Int?` persisted properties

**`MessagingMapper.swift`:**
- Map `imageWidth`/`imageHeight` in both `mapToSDMessage()` and `mapToMessage()` directions
- Handle nil values gracefully (legacy messages)

### Upload Flow Change

**`MessageSendManager`:**
- When compressing an image for upload, capture `UIImage.size.width` and `UIImage.size.height` (in points)
- Pass `imageWidth: Int(image.size.width)` and `imageHeight: Int(image.size.height)` through to `MessageService.sendMessage`

**`MessageService.sendMessage`:**
- Accept and store `imageWidth`/`imageHeight` in the insert payload

### ImageBubbleView Rendering Change

**`ImageBubbleView.swift`:**

New configuration method:
```swift
func configure(remoteUrl: String, imageWidth: Int?, imageHeight: Int?, onTap: ((URL) -> Void)?)
```

**`sizeThatFits` change:**
```swift
override func sizeThatFits(_ size: CGSize) -> CGSize {
    guard let w = imageWidth, let h = imageHeight, w > 0, h > 0 else {
        // Legacy fallback: square
        let side = min(size.width, maxSize)
        return CGSize(width: side, height: side)
    }
    let aspectRatio = CGFloat(h) / CGFloat(w)
    let width = min(CGFloat(w), min(size.width, maxSize))
    let height = min(width * aspectRatio, 300) // Cap height at 300pt
    return CGSize(width: width, height: height)
}
```

- `contentMode` stays `.scaleAspectFill` but now the frame matches the actual ratio, eliminating cropping
- Corner radius stays 18pt

### Impact
Migration + model change + mapper update + send manager + `ImageBubbleView` sizing. All backward compatible: nil dimensions = current 220x220 square behavior.

---

## Section 6: Small UI Fixes (Issues #17, #19, #20, #23)

### Issue #17 — Typing Indicator Pulse

**File: `TypingIndicatorView.swift`**

Add a `@State private var isPulsing = false` and apply to the bubble background:

```swift
.scaleEffect(isPulsing ? 1.04 : 1.0)
.onAppear {
    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
        isPulsing = true
    }
}
```

Applied to the `BubbleShape` background container that wraps the dots. The dots' own animation stays unchanged.

### Issue #19 — Long-Press Overlay Scale

**File: `MessageOverlayController.swift`**

Line 213, change:
```swift
self.snapshot.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
```
to:
```swift
self.snapshot.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
```

### Issue #20 — Conversation List Avatar + Row Height

**Files:**
- `ConversationRow.swift`: Change avatar size constant from 50 → 56
- `ConversationAvatar.swift`: Change size parameter from 50 → 56
- `ConversationRow.swift`: Change row vertical padding from 8 → 11 (achieves ~78pt total: 56 + 11 + 11)
- `SkeletonConversationRow.swift`: Change avatar skeleton from 50 → 56

### Issue #23 — Avatar Size Consistency

Resolved by #20 changes above. Conversation list avatars go from 50 → 56pt. In-chat avatars remain 28pt (already matches iMessage).

`GroupAvatarComposite.swift`: Update container size from 50 → 56pt to match.

---

## Section 7: Scroll-to-First-Unread (Issue #22)

### Behavior

When opening a conversation with unread messages:
1. Scroll to the **first unread message** instead of the bottom
2. Show a "X New Messages" divider banner above that message
3. Existing scroll-to-bottom button remains functional
4. Once the user scrolls past all unreads (reaches bottom), the divider fades out and messages are marked as read

### New View: `UnreadDividerView.swift`

A UIKit view displayed as a special cell in the diffable data source:
- Horizontal hairline on both sides of a centered pill label
- Label text: "3 New Messages" (localized, pluralized)
- Pill background: `naarsPrimary.withAlphaComponent(0.1)`
- Text color: `naarsPrimary`
- Font: `.preferredFont(forTextStyle: .caption1)` with `.semibold`
- Fixed height: 30pt

### MessagePaginationManager Changes

On `loadMessages()`:
- After fetching messages, identify the first message where `readBy` does not contain the current user ID
- Expose `firstUnreadMessageId: UUID?` as a published property
- Only computed on initial load, not on subsequent real-time message arrivals while the conversation is open

### MessagesCollectionView / Diffable Data Source Changes

- Add a new item type to the snapshot enum: `.unreadDivider(count: Int)`
- On initial load, if `firstUnreadMessageId` is set:
  - Insert `.unreadDivider(count: unreadCount)` immediately before `firstUnreadMessageId` in the snapshot
  - After snapshot is applied, scroll to `firstUnreadMessageId`
- When user scrolls past the divider (it exits the visible rect at the top), remove it from the snapshot with `UIView.animate` fade

### ConversationDetailViewModel Changes

- Track `hasShownUnreadDivider: Bool` flag — only show on first open
- When the divider is dismissed (scrolled past), set the flag and don't re-show

### Impact
New view, changes to pagination manager and collection view snapshot logic. Existing scroll-to-bottom and markAsRead flows are untouched.

---

## Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Read receipt style | Keep checkmarks (skip #9) | User preference |
| Bubble/screen/text effects | Deferred (#28-31) | Data model complexity |
| Send button color | `naarsPrimary` | Brand consistency |
| Image dimensions | Store in DB (migration) | No layout jumps on render |
| Conversation list badge | Keep count badge | More informative than blue dot |
| Avatar size (list) | 50 → 56pt | Match iMessage proportions |
| Scroll-to-unread | Auto-scroll + divider banner | Full iMessage iOS 17 parity |
| Input bar port | Full UIKit rewrite | Enables interactive keyboard dismiss |
| SwiftUI MessageInputBar | Keep file, stop referencing | Safe rollback path |

---

## Files Changed (Summary)

### New Files
- `NaarsCars/UI/Components/Messaging/Cells/EmojiBubbleView.swift`
- `NaarsCars/UI/Components/Messaging/MessageInputAccessoryView.swift`
- `NaarsCars/UI/Components/Messaging/Cells/UnreadDividerView.swift`
- `NaarsCars/Core/Utilities/EmojiDetection.swift` (or extension)

### Modified Files
- `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift` — reaction badge positioning, emoji branch, grouping spacing, max width
- `NaarsCars/UI/Components/Messaging/Cells/TextBubbleView.swift` — padding constants
- `NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift` — aspect ratio sizing, new configure signature
- `NaarsCars/UI/Components/Messaging/TypingIndicatorView.swift` — pulse animation
- `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift` — scale constant
- `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` — remove SwiftUI input bar
- `NaarsCars/Features/Messaging/Views/ConversationRow.swift` — avatar size, row padding
- `NaarsCars/Features/Messaging/Views/ConversationAvatar.swift` — size constant
- `NaarsCars/UI/Components/Common/GroupAvatarComposite.swift` — size constant
- `NaarsCars/UI/Components/Feedback/SkeletonConversationRow.swift` — skeleton size
- `NaarsCars/Features/Messaging/ViewModels/MessagePaginationManager.swift` — first unread tracking
- `NaarsCars/Features/Messaging/ViewModels/MessageSendManager.swift` — image dimensions capture
- `NaarsCars/Core/Models/Message.swift` — imageWidth, imageHeight fields
- `NaarsCars/Core/Storage/SDModels.swift` — SDMessage imageWidth, imageHeight
- `NaarsCars/Core/Storage/MessagingMapper.swift` — dimension mapping
- `NaarsCars/Core/Services/MessageService.swift` — accept imageWidth/imageHeight in send
- `NaarsCars/Resources/Localizable.xcstrings` — new localization keys for unread divider

### Supabase Migration
- Add `image_width` and `image_height` columns to `messages` table

### Unchanged
- `NaarsCars/UI/Components/Messaging/MessageInputBar.swift` — kept but no longer referenced (rollback safety)
