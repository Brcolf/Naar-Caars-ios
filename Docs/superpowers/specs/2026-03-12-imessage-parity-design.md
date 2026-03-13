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

**File: `ReactionBadgeView.swift` (exists at `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift`)**

Add a 2pt `systemBackground`-colored border to each `ReactionCapsuleView` (the private inner class that renders individual emoji+count pills). Set `layer.borderWidth = 2` and `layer.borderColor = UIColor.systemBackground.cgColor` on each capsule so they visually separate from the bubble when overlapping. Update `traitCollectionDidChange` to refresh the border color for dark mode transitions.

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

**Layout changes in both `layoutSubviews()` and `sizeThatFits()`:**

Compute padding using stored `isFromCurrentUser` and `showTail` properties (already available as instance state):
```swift
private let interiorPad: CGFloat = 14
private let tailSidePad: CGFloat = 18

// In both layoutSubviews() and sizeThatFits():
let tailPad = showTail ? tailSidePad : interiorPad
let leftPad = isFromCurrentUser ? interiorPad : tailPad  // sent: interior left; received: tail left
let rightPad = isFromCurrentUser ? tailPad : interiorPad  // sent: tail right; received: interior right
let textWidth = constrainedWidth - leftPad - rightPad
```

In `sizeThatFits()`:
```swift
let totalWidth = textSize.width + leftPad + rightPad + (showTail ? 6 : 0) // 6 = tailWidth from BubblePath
let totalHeight = textSize.height + vPad * 2
return CGSize(width: totalWidth, height: totalHeight)
```

In `layoutSubviews()`:
```swift
textLabel.frame = CGRect(x: leftPad + (showTail && !isFromCurrentUser ? 6 : 0), y: vPad, width: textSize.width, height: textSize.height)
```

### Issue #10 — Max Bubble Width

**File: `MessageCellView.swift`**

Change `bounds.width * 0.7` → `bounds.width * 0.75` in:
- `layoutSubviews()` (line 429)
- `sizeThatFits()` (line 548)

### Issue #8 — Grouping Spacing

**File: `MessageCellView.swift`**

Current spacing logic uses a single `verticalPadding` added to the bottom of each cell's height in `sizeThatFits()`. Simply swapping `isLastInSeries` to `isFirstInSeries` would put the gap in the wrong place (bottom of the first message rather than above it).

**Fix: introduce separate `topPadding` and `bottomPadding`:**

In `sizeThatFits()`:
```swift
let topPadding: CGFloat = config.isFirstInSeries ? 8 : 2
let bottomPadding: CGFloat = 2
// ... add topPadding + bottomPadding to the returned height instead of the single verticalPadding
```

In `layoutSubviews()`:
```swift
let topPadding: CGFloat = config.isFirstInSeries ? 8 : 2
var y: CGFloat = topPadding  // Start content below the top padding
```

This puts the 8pt gap *above* a new sender's first message, matching iMessage's visual rhythm. 2pt between same-sender messages stays. The reaction badge offset calculation must also account for `topPadding`.

### Impact
Pure layout/constant changes. No data model or logic changes.

---

## Section 3: Emoji Enlargement (Issue #7)

### Detection Logic

New file: `EmojiDetection.swift`

**Important:** Swift's `Character` has no built-in `isEmoji` property. `Unicode.Scalar.Properties.isEmoji` is unreliable because it returns `true` for digits (0-9) and `#`. The detection must use `isEmojiPresentation` and handle ZWJ (zero-width joiner) sequences correctly.

```swift
extension Character {
    /// Returns true if this character renders as an emoji glyph.
    /// Handles ZWJ sequences (family emoji), skin tone modifiers, and keycap sequences.
    var isActualEmoji: Bool {
        // A character with emoji presentation selector always renders as emoji
        if unicodeScalars.first?.properties.isEmojiPresentation == true {
            return true
        }
        // Multi-scalar sequences (ZWJ, skin tones, keycaps) are emoji
        // if the base scalar has the emoji property
        if unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji == true {
            return true
        }
        return false
    }
}

func isEmojiOnlyMessage(_ text: String) -> (isEmojiOnly: Bool, count: Int) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (false, 0) }
    let characters = Array(trimmed)
    guard characters.allSatisfy(\.isActualEmoji) else { return (false, 0) }
    let count = characters.count
    return (count >= 1 && count <= 3) ? (true, count) : (false, 0)
}
```

Swift's `Character` type correctly groups grapheme clusters, so `String.count` returns the visual emoji count even for ZWJ sequences like family emoji.

### New View: `EmojiBubbleView.swift`

A lightweight UIKit view:
- Single `UILabel` — **tiered font size**: 42pt for 1 emoji, 36pt for 2, 30pt for 3 (matches iMessage's scaling)
- No `CAShapeLayer` background — no bubble shape, no fill color
- `sizeThatFits` returns label intrinsic size plus 4pt margins
- **Not constrained by `maxBubbleWidth`** — emoji bubbles have no background, so they don't need width limiting
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

### Architecture Change: UIViewRepresentable → UIViewControllerRepresentable

**Critical:** The current `MessagesCollectionView` is a `UIViewRepresentable` (wraps a `UIView`). `inputAccessoryView` is a `UIViewController` property — it cannot be set on a plain `UIView`. The fix:

**Promote `MessagesCollectionView` from `UIViewRepresentable` to `UIViewControllerRepresentable`:**
- Create a new `MessagesViewController` (`UIViewController` subclass) that owns the collection view
- Override `var inputAccessoryView` → returns `MessageInputAccessoryView` instance
- Override `var canBecomeFirstResponder` → returns `true`
- Set `collectionView.keyboardDismissMode = .interactive`
- The existing `Coordinator` logic (diffable data source, cell registration, delegate methods) moves into or is retained by this view controller
- The `UIViewControllerRepresentable` wrapper replaces the current `UIViewRepresentable` in `ConversationDetailView`

### Integration

**ConversationDetailView.swift:**
- Replace the `MessagesCollectionView` (UIViewRepresentable) with the new `MessagesViewControllerRepresentable` (UIViewControllerRepresentable)
- Remove `MessageInputBar` from the SwiftUI `VStack`
- The input bar is now owned by the UIKit view controller, not the SwiftUI view hierarchy
- Reply/edit context is passed to the input bar via `setReplyContext(_:)` / `setEditContext(_:)` methods

**MessageThreadViewController:**
- `MessageThreadViewController` **continues to use the SwiftUI `MessageInputBar`** via `UIHostingController`. It is a standalone `UIViewController` with its own input handling and does not need `inputAccessoryView`-based interactive dismiss (thread views are simpler, shorter conversations).
- Therefore `MessageInputBar.swift` is **still referenced** by `MessageThreadViewController` and must not be deleted.

### Delegate Protocol: `MessageInputDelegate`

Updated to include the missing edit submission method and camera presentation:

```swift
protocol MessageInputDelegate: AnyObject {
    func inputBar(_ bar: MessageInputAccessoryView, didSendText text: String)
    func inputBar(_ bar: MessageInputAccessoryView, didSendEditedText text: String, messageId: UUID)
    func inputBarDidRequestImagePicker(_ bar: MessageInputAccessoryView)
    func inputBarDidRequestCamera(_ bar: MessageInputAccessoryView)
    func inputBar(_ bar: MessageInputAccessoryView, didRecordAudio url: URL, duration: Double)
    func inputBar(_ bar: MessageInputAccessoryView, didShareLocation lat: Double, lon: Double, name: String?)
    func inputBarDidCancelReply(_ bar: MessageInputAccessoryView)
    func inputBarDidCancelEdit(_ bar: MessageInputAccessoryView)
    func inputBarDidChangeTypingState(_ bar: MessageInputAccessoryView)
}
```

**Camera presentation:** The delegate's `inputBarDidRequestCamera` is handled by `MessagesViewController`, which presents `UIImagePickerController(sourceType: .camera)` directly from its own view controller hierarchy.

**Risk mitigation:**
- `MessageInputBar.swift` (SwiftUI) is kept and still used by `MessageThreadViewController`. It is only removed from `ConversationDetailView`.

### Audio Recording

All recording logic ports directly:
- `AVAudioRecorder` setup identical (M4A, 44.1kHz, 1 channel, high quality)
- Permission check via `AVAudioApplication.requestRecordPermission()` (iOS 17+) with fallback
- Duration timer: `Timer.scheduledTimer` at 1.0s interval
- Haptic feedback on record start
- Minimum 1s duration before send
- Duration display format: `M:SS.T` (minutes:seconds.tenths) — matching the existing SwiftUI format in `MessageInputBar.formatDuration()`

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

**RLS consideration:** Verify that existing RLS INSERT/UPDATE policies on the `messages` table use wildcard column grants (not an explicit column list). If policies enumerate allowed columns, add `image_width` and `image_height` to the allowed set. Check via `SELECT * FROM pg_policies WHERE tablename = 'messages'`.

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
    var width = min(CGFloat(w), min(size.width, maxSize))
    var height = width * aspectRatio
    // Cap height at 300pt — but recalculate width to maintain aspect ratio
    if height > 300 {
        height = 300
        width = height / aspectRatio
    }
    return CGSize(width: width, height: height)
}
```

- `contentMode` stays `.scaleAspectFill` but now the frame matches the actual ratio, eliminating cropping
- When the height cap triggers, width is recalculated to maintain the correct aspect ratio (prevents cropping tall portrait images)
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

Apply the `scaleEffect` to the **entire `HStack` containing the dots** (not just the `.background` modifier), so the dots and the bubble background scale together. Otherwise applying it only to the background shape would scale the background without the content, causing a visual mismatch. The dots' own bounce/opacity animation stays unchanged and composes naturally with the outer pulse.

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

**Recommendation:** Extract the hardcoded `50` to a shared constant `Constants.Avatar.conversationList = 56` to avoid missing any occurrences.

**Files and specific locations to change:**
- `ConversationRow.swift`: Avatar size reference → 56
- `ConversationAvatar.swift`: The value `50` appears in ~6 locations (frame sizes for single avatar, group avatar container, `AvatarView` size parameters, `GroupAvatarComposite` size, default group avatar circle). All must change to 56 or reference the shared constant.
- `ConversationRow.swift`: Row vertical padding from 8 → 11 (achieves ~78pt total: 56 + 11 + 11)
- `SkeletonConversationRow.swift`: Avatar skeleton from 50 → 56

### Issue #23 — Avatar Size Consistency

Resolved by #20 changes above. Conversation list avatars go from 50 → 56pt. In-chat avatars remain 28pt (already matches iMessage).

`GroupAvatarComposite.swift`: Update container size from 50 → 56pt to match. Search for all hardcoded `50` references in this file and update.

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

The current diffable data source uses `<Int, String>` item identifiers (UUID strings for messages, `"date:..."` for date separators). The unread divider follows this same string-based pattern:

- Use the string identifier `"unread:\(count)"` for the divider item, consistent with the existing `"date:..."` pattern
- Register a supplementary cell provider for `"unread:*"` prefix items that dequeues `UnreadDividerView`
- On initial load, if `firstUnreadMessageId` is set:
  - Insert `"unread:\(count)"` immediately before the `firstUnreadMessageId` string in the snapshot
  - After snapshot is applied, scroll to `firstUnreadMessageId`
- When user scrolls past the divider (visually: it moves above the screen in the flipped collection view, meaning it exits the *bottom* of the visible bounds in flipped coordinates), remove it from the snapshot with an animated snapshot apply

**Edge case — deleted/missing firstUnreadMessageId:** If the first unread message has been unsent/deleted between computation and render, the message ID won't exist in the snapshot. Fallback: find the next chronologically-later message in the loaded message list and use that as the scroll target. If no messages remain unread, skip the divider entirely and scroll to bottom.

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
| SwiftUI MessageInputBar | Keep file, still used by thread view | MessageThreadViewController depends on it |
| MessagesCollectionView | Promote to UIViewControllerRepresentable | Required for inputAccessoryView support |
| Emoji font size | Tiered: 42/36/30pt for 1/2/3 emoji | Matches iMessage scaling |
| Unread divider item | String-based "unread:N" identifier | Consistent with existing diffable data source pattern |

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

### Still Used
- `NaarsCars/UI/Components/Messaging/MessageInputBar.swift` — still used by `MessageThreadViewController`, removed only from `ConversationDetailView`

### New Files (additional)
- `NaarsCars/Features/Messaging/Views/MessagesViewController.swift` — UIViewController wrapping the collection view (replaces UIViewRepresentable)
- `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift` — UIViewControllerRepresentable wrapper

---

## Testing Considerations

### Unit Tests
- **Emoji detection:** Test `isEmojiOnlyMessage()` with: single emoji, 2-3 emoji, 4+ emoji (should return false), mixed text+emoji, digits-only ("123" must return false), ZWJ sequences (family emoji, skin tones), flag emoji, keycap sequences, empty string, whitespace-only
- **Image aspect ratio sizing:** Test `sizeThatFits` with: landscape image, portrait image, square image, very tall image (height cap trigger), nil dimensions (legacy fallback), zero dimensions

### Manual Regression Tests
- **Input bar:** Verify all input bar functions work in the new UIKit version: send text, send image, send audio, share location, reply context, edit context, cancel reply/edit, typing indicator, multi-line growth, keyboard dismiss
- **MessageThreadViewController:** Verify the thread view still works correctly with the SwiftUI `MessageInputBar` (it should be untouched)
- **Reaction badges:** Verify positioning on sent bubbles, received bubbles, image bubbles, audio bubbles, emoji-only messages, and messages with multiple reactions
- **Scroll-to-unread:** Test with 1 unread, many unreads, all-read (no divider), deleted first-unread (fallback), conversation with 0 messages
- **Image aspect ratio:** Test with existing messages (no dimensions — should show square), new messages (landscape, portrait, square), very tall/wide extremes
- **Dark mode:** Verify all new/changed views update correctly on trait collection change
