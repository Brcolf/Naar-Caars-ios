# Messaging Ship Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all ship-blocking and major messaging bugs identified in the UIKit message cell migration audit — gesture system, thread entry, composer state, mixed-content layout, accessibility parity, localized strings, read receipt parity, scroll-to highlight, reply spine, timestamp layout invalidation, and link preview defaults.

**Architecture:** Targeted fixes to existing files. No new files created. Each task is a single logical fix that can be committed independently. Tasks are ordered by severity: ship blockers first, then major issues, then low-priority polish.

**Tech Stack:** UIKit, SwiftUI (ConversationDetailView bindings), XCStrings localization, UIAccessibility

**Spec:** `Docs/plans/2026-03-11-uikit-message-cells-design.md`

---

## File Map

All changes are modifications to existing files:

| File | What changes |
|------|-------------|
| `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift` | Gesture fix, mixed-content layout, reply spine drawing, timestamp layout invalidation, last-in-series padding, accessibility |
| `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` | Thread entry wiring, delete-for-me alert localization |
| `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift` | Composer state tracking, image tap delegate, thread media no-ops |
| `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift` | Localized strings, Delete for Me destructive styling |
| `NaarsCars/UI/Components/Messaging/Cells/ReadReceiptView.swift` | Group delivered+read avatar parity |
| `NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift` | Async local image loading, generation counter for local path |
| `NaarsCars/UI/Components/Messaging/Cells/TextBubbleView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/AudioBubbleView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/LocationBubbleView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/LinkPreviewBubbleView.swift` | Preference default fix, accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/SystemMessageView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/UnsentMessageView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/ReplyPreviewView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Cells/DateSeparatorCell.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift` | Accessibility |
| `NaarsCars/UI/Components/Common/AvatarUIView.swift` | Accessibility |
| `NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift` | Highlight state passthrough |

---

## Chunk 1: Ship Blockers

### Task 1: Fix long-press gesture — remove `require(toFail: panGesture)`

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:539-552`

The long-press gesture has `require(toFail: panGesture)` (line 546). The pan's `gestureRecognizerShouldBegin` returns `false` for stationary touches (line 663-668), keeping the pan in `.possible` state indefinitely. A recognizer in `.possible` never transitions to `.failed`, so the long-press can never fire. The spec says pan and long-press should coexist without `require(toFail:)` between them — only tap requires both to fail.

- [ ] **Step 1: Remove the failure dependency and add the correct one**

In `setupGestures()`, change from:

```swift
longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
longPressGesture.minimumPressDuration = 0.5
longPressGesture.require(toFail: panGesture)
addGestureRecognizer(longPressGesture)

tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
tapGesture.require(toFail: panGesture)
tapGesture.require(toFail: longPressGesture)
addGestureRecognizer(tapGesture)
```

To:

```swift
longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
longPressGesture.minimumPressDuration = 0.5
// No require(toFail:) — pan and long-press coexist. Pan activates via
// horizontal direction lock in gestureRecognizerShouldBegin; long-press
// has its own 0.5s duration gate. Per spec: "Pan and long-press coexist."
addGestureRecognizer(longPressGesture)

tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
tapGesture.require(toFail: panGesture)
tapGesture.require(toFail: longPressGesture)
addGestureRecognizer(tapGesture)
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "fix: remove require(toFail:) blocking long-press — pan and long-press now coexist per spec"
```

---

### Task 2: Wire thread entry — assign `activeThreadParent`

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift:607-631`
- Modify: `NaarsCars/UI/Components/Messaging/Overlay/OverlayAction.swift`

The `activeThreadParent` state variable drives `.fullScreenCover` for the thread view, but nothing ever assigns to it. The overlay needs a "Thread" / "View Replies" action, and `onSwipeReply` currently opens the inline reply composer — thread entry should come from the overlay or from tapping a reply-count indicator. Since the overlay is the primary long-press interaction and the spec lists "Reply" as the first action, we add the reply-to-thread action as an `OverlayAction` case and wire it in `handleOverlayAction`.

However, examining the app more carefully: threads are entered when a user taps the reply count on a parent message, not from the overlay. The overlay "Reply" action opens the inline reply composer. The thread entry path that was lost is likely a UI element in the old `MessageBubble` that showed reply count and navigated to the thread. We need to:

1. Add a `messageCellDidTapThread` delegate callback
2. Show a reply count indicator in `MessageCellView` when `message.replyToId == nil` and the message has replies
3. Wire that to set `activeThreadParent`

Since Message doesn't have a `replyCount` field, thread entry was likely triggered by tapping the reply preview. Looking at the old code, `replyToId` indicates a message IS a reply, not that it HAS replies. The simplest ship-worthy fix: add a "View Thread" action to the overlay for messages that have `replyToId` (replies to a parent), setting the thread parent to the `replyToId`.

- [ ] **Step 1: Add `viewThread` case to OverlayAction**

In `NaarsCars/UI/Components/Messaging/Overlay/OverlayAction.swift`, add:

```swift
enum OverlayAction {
    case react(String)
    case removeReaction
    case reply
    case viewThread(UUID)  // parentMessageId
    case copy
    case edit
    case unsend
    case deleteForMe
    case report
}
```

- [ ] **Step 2: Add "View Thread" row in OverlayActionListView**

In `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift`, in `buildActions()`, after the Reply item, add:

```swift
// View Thread — if this message is a reply (has a parent thread)
if let replyToId = message.replyToId {
    items.append(ActionItem(
        action: .viewThread(replyToId),
        title: NSLocalizedString("messaging_view_thread", comment: ""),
        icon: "bubble.left.and.bubble.right",
        isDestructive: false
    ))
}
```

- [ ] **Step 3: Handle `.viewThread` in ConversationDetailView**

In `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`, in `handleOverlayAction(_:message:)`, add the case:

```swift
case .viewThread(let parentId):
    activeThreadParent = ThreadParent(id: parentId)
```

- [ ] **Step 4: Add the XCStrings entry**

Add `"messaging_view_thread"` with value `"View Thread"` to `NaarsCars/Resources/Localizable.xcstrings`. (Use existing xcstrings patterns.)

- [ ] **Step 5: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/OverlayAction.swift \
       NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift \
       NaarsCars/Features/Messaging/Views/ConversationDetailView.swift \
       NaarsCars/Resources/Localizable.xcstrings
git commit -m "fix: wire thread entry via overlay View Thread action and activeThreadParent"
```

---

### Task 3: Fix thread composer send-button state tracking

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift:340-392`

The `MessageInputBar` is hosted via `UIHostingController`. The `isDisabled` parameter is captured at construction time; it does not reactively track typing. The Binding setters for `text` and `imageToSend` mutate the VC's properties but never call `updateInputBarDisabledState()`, so the button state goes stale.

Fix: make the Binding setters trigger a state rebuild.

- [ ] **Step 1: Update the binding setters in `setupInputBar()`**

Change `setupInputBar()` to use setters that call `updateInputBarDisabledState()`:

```swift
private func setupInputBar() {
    let inputBar = makeInputBar()

    let hostingController = UIHostingController(rootView: inputBar)
    hostingController.view.backgroundColor = .clear
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false

    addChild(hostingController)
    view.addSubview(hostingController.view)
    hostingController.didMove(toParent: self)

    NSLayoutConstraint.activate([
        hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        collectionView.bottomAnchor.constraint(equalTo: hostingController.view.topAnchor),
    ])

    inputHostingController = hostingController
}
```

- [ ] **Step 2: Extract `makeInputBar()` and fix `updateInputBarDisabledState()`**

Replace the existing `updateInputBarDisabledState()` with a shared builder that both methods use:

```swift
private func makeInputBar() -> MessageInputBar {
    let hasParent = threadViewModel.parentMessage != nil
    let hasContent = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageToSend != nil

    return MessageInputBar(
        text: Binding(
            get: { [weak self] in self?.messageText ?? "" },
            set: { [weak self] in
                self?.messageText = $0
                self?.updateInputBarDisabledState()
            }
        ),
        imageToSend: Binding(
            get: { [weak self] in self?.imageToSend },
            set: { [weak self] in
                self?.imageToSend = $0
                self?.updateInputBarDisabledState()
            }
        ),
        onSend: { [weak self] in self?.sendReply() },
        onImagePickerTapped: { },
        isDisabled: !hasParent || !hasContent
    )
}

private func updateInputBarDisabledState() {
    inputHostingController?.rootView = makeInputBar()
}
```

- [ ] **Step 3: Build and commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift
git commit -m "fix: thread composer button now tracks typing via Binding setters"
```

---

### Task 4: Fix mixed-content layout — stack multiple visible content views

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:430-447, :494-498, :519-522`

`activeContentView()` returns only the first non-hidden content view. When text + link preview are both visible, only the text bubble gets laid out. Fix: replace `activeContentView()` with `visibleContentViews()` that returns all non-hidden content views, and stack them vertically in layout.

- [ ] **Step 1: Replace `activeContentView()` with `visibleContentViews()`**

```swift
private func visibleContentViews() -> [UIView] {
    [textBubble, imageBubble, audioBubble, locationBubble, linkPreviewBubble]
        .compactMap { $0 }
        .filter { !$0.isHidden }
}
```

- [ ] **Step 2: Update `layoutSubviews()` content section**

Replace the single-content-view layout block (lines ~430-447) with:

```swift
// Content bubbles (may have multiple: e.g. text + link preview, image + caption)
let contentViews = visibleContentViews()
var primaryContentView: UIView? // used for reaction badge + reply arrow positioning
for cv in contentViews {
    let cvSize = cv.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude))
    let x = config.isFromCurrentUser
        ? bounds.width - cvSize.width
        : avatarSize + avatarSpacing
    cv.frame = CGRect(x: x, y: y, width: cvSize.width, height: cvSize.height)
    y = cv.frame.maxY + 2
    if primaryContentView == nil { primaryContentView = cv }
}
if !contentViews.isEmpty { y += 2 } // extra spacing after content block

// Reaction badge (anchored to first content view)
if let primary = primaryContentView, let rb = reactionBadge, !rb.isHidden {
    let rbSize = rb.sizeThatFits(.zero)
    let rbX = config.isFromCurrentUser ? primary.frame.minX : primary.frame.maxX - rbSize.width
    rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height / 2, width: rbSize.width, height: rbSize.height)
}
```

- [ ] **Step 3: Update reply arrow positioning to use `primaryContentView`**

Replace the reply arrow block (lines ~449-458) to use `primaryContentView` instead of `contentView`:

```swift
// Reply arrow icon position (to the side of the first content bubble)
if let cv = primaryContentView {
    let arrowSize: CGFloat = 24
    let arrowY = cv.frame.midY - arrowSize / 2
    if config.isFromCurrentUser {
        replyArrowIcon.frame = CGRect(x: cv.frame.minX - arrowSize - 8, y: arrowY, width: arrowSize, height: arrowSize)
    } else {
        replyArrowIcon.frame = CGRect(x: cv.frame.maxX + 8, y: arrowY, width: arrowSize, height: arrowSize)
    }
}
```

Note: `primaryContentView` needs to be accessible to the reply arrow block. Either hoist it as a local above both blocks or restructure. Since both blocks are sequential in `layoutSubviews()`, defining `primaryContentView` before both blocks works.

- [ ] **Step 4: Update `sizeThatFits()` to sum all visible content heights**

Replace the single content height (lines ~519-522) with:

```swift
// Content — sum all visible content views
for cv in visibleContentViews() {
    height += cv.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude)).height + 2
}
if !visibleContentViews().isEmpty { height += 2 }
```

- [ ] **Step 5: Update swipe pan handler to transform all content views**

In `handlePan`, replace `activeContentView()?.transform = ...` (line 585) with:

```swift
for cv in visibleContentViews() {
    cv.transform = CGAffineTransform(translationX: swipeOffset, y: 0)
}
```

And in the `.ended` animator (line 593):

```swift
let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.7) {
    for cv in self.visibleContentViews() {
        cv.transform = .identity
    }
    self.replyArrowIcon.alpha = 0
    self.replyArrowIcon.transform = .identity
}
```

- [ ] **Step 6: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "fix: stack multiple visible content views in layout (text+link, image+caption)"
```

---

### Task 5: Add accessibility to all UIKit messaging cells and overlay

**Files:**
- Modify: Every file in `NaarsCars/UI/Components/Messaging/Cells/` and `NaarsCars/UI/Components/Messaging/Overlay/`
- Modify: `NaarsCars/UI/Components/Common/AvatarUIView.swift`

The spec states: "All UIKit cell views must maintain accessibility parity with the existing SwiftUI MessageBubble — labels, hints, and traits must be replicated." Currently zero accessibility setup exists across all new UIKit views.

- [ ] **Step 1: MessageCellView — container accessibility**

Add at the end of `configure(with:)`, before `setNeedsLayout()`:

```swift
// Accessibility
isAccessibilityElement = false
accessibilityElements = visibleContentViews() + [reactionBadge, timestampLabel, readReceipt, failedRetryLabel, replyPreview].compactMap { $0 }.filter { !$0.isHidden }
```

- [ ] **Step 2: TextBubbleView — text content label**

In `configure(text:isFromCurrentUser:showTail:)`, add:

```swift
isAccessibilityElement = true
accessibilityLabel = text
accessibilityTraits = .staticText
```

- [ ] **Step 3: ImageBubbleView — image accessibility**

In `showImage(_:)`:
```swift
isAccessibilityElement = true
accessibilityLabel = NSLocalizedString("messaging_photo", comment: "")
accessibilityTraits = [.image, .button]
accessibilityHint = NSLocalizedString("accessibility_tap_to_view", comment: "")
```

In `showError()`:
```swift
accessibilityLabel = NSLocalizedString("messaging_image_failed", comment: "")
accessibilityHint = NSLocalizedString("accessibility_tap_to_retry", comment: "")
```

- [ ] **Step 4: AudioBubbleView — playback accessibility**

In `configure(audioUrl:duration:isFromCurrentUser:)`:
```swift
isAccessibilityElement = true
accessibilityTraits = .button
```

In `updateUI(isPlaying:progress:)`:
```swift
let statusText = isPlaying
    ? NSLocalizedString("accessibility_audio_playing", comment: "")
    : NSLocalizedString("accessibility_audio_paused", comment: "")
accessibilityLabel = "\(statusText), \(durationLabel.text ?? "")"
accessibilityHint = NSLocalizedString("accessibility_tap_to_toggle", comment: "")
```

- [ ] **Step 5: LocationBubbleView — location accessibility**

In `configure(latitude:longitude:name:)`:
```swift
isAccessibilityElement = true
accessibilityLabel = nameLabel.text
accessibilityTraits = .button
accessibilityHint = NSLocalizedString("accessibility_tap_to_open_maps", comment: "")
```

- [ ] **Step 6: LinkPreviewBubbleView — link accessibility**

In `configure(url:isFromCurrentUser:)`:
```swift
isAccessibilityElement = true
accessibilityTraits = .link
accessibilityLabel = url.host ?? url.absoluteString
accessibilityHint = NSLocalizedString("accessibility_tap_to_open_link", comment: "")
```

- [ ] **Step 7: SystemMessageView — system message accessibility**

In `configure(text:)`:
```swift
isAccessibilityElement = true
accessibilityLabel = text
accessibilityTraits = .staticText
```

- [ ] **Step 8: UnsentMessageView — unsent accessibility**

In `configure(isFromCurrentUser:)`:
```swift
isAccessibilityElement = true
accessibilityLabel = textLabel.text
accessibilityTraits = .staticText
```

- [ ] **Step 9: ReactionBadgeView — reaction capsule accessibility**

In `makeCapsule(emoji:count:)`, on the container:
```swift
container.isAccessibilityElement = true
container.accessibilityLabel = count > 1 ? "\(emoji) \(count)" : emoji
container.accessibilityTraits = .button
```

- [ ] **Step 10: ReplyPreviewView — reply preview accessibility**

In `configure(reply:isFromCurrentUser:onTap:)`:
```swift
isAccessibilityElement = true
accessibilityLabel = "\(senderLabel.text ?? ""), \(previewLabel.text ?? "")"
accessibilityTraits = .button
accessibilityHint = NSLocalizedString("accessibility_tap_to_scroll_to_reply", comment: "")
```

- [ ] **Step 11: DateSeparatorCell — date accessibility**

In `configure(date:)`:
```swift
contentView.isAccessibilityElement = true
contentView.accessibilityLabel = dateLabel.text
contentView.accessibilityTraits = .header
```

- [ ] **Step 12: ReactionBarView — reaction button accessibility**

In `makeReactionButton(emoji:)`:
```swift
button.accessibilityLabel = emoji
if isSelected {
    button.accessibilityTraits = [.button, .selected]
} else {
    button.accessibilityTraits = .button
}
```

- [ ] **Step 13: OverlayActionListView — action button accessibility**

In `makeRow(item:)`:
```swift
button.accessibilityLabel = item.title
button.accessibilityTraits = item.isDestructive ? [.button] : .button
```

(Buttons using `UIButton.Configuration` already have accessible titles from `config.title`, so this is a defensive addition.)

- [ ] **Step 14: AvatarUIView — avatar accessibility**

In `configure(imageUrl:name:size:)`:
```swift
isAccessibilityElement = true
accessibilityLabel = name
accessibilityTraits = .image
```

- [ ] **Step 15: Add all XCStrings entries for accessibility**

Add the following keys to `NaarsCars/Resources/Localizable.xcstrings`:
- `"accessibility_tap_to_view"` → `"Tap to view full screen"`
- `"accessibility_tap_to_retry"` → `"Tap to retry"`
- `"accessibility_audio_playing"` → `"Audio playing"`
- `"accessibility_audio_paused"` → `"Audio message"`
- `"accessibility_tap_to_toggle"` → `"Tap to play or pause"`
- `"accessibility_tap_to_open_maps"` → `"Tap to open in Maps"`
- `"accessibility_tap_to_open_link"` → `"Tap to open link"`
- `"accessibility_tap_to_scroll_to_reply"` → `"Tap to scroll to original message"`
- `"messaging_image_failed"` → `"Image failed to load"`

- [ ] **Step 16: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/*.swift \
       NaarsCars/UI/Components/Messaging/Overlay/*.swift \
       NaarsCars/UI/Components/Common/AvatarUIView.swift \
       NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add accessibility labels, hints, and traits to all UIKit messaging cells and overlay"
```

---

### Task 6: Localize overlay action strings via XCStrings

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift:59-92`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift:280`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

The overlay uses hardcoded English strings. The xcstrings file already has entries for `"Reply"`, `"Copy"`, `"Edit"`, `"Delete for Me"` but the UIKit code doesn't run them through localization lookup. `"Undo Send"` and `"Report"` are missing from xcstrings entirely.

- [ ] **Step 1: Use `NSLocalizedString` in `buildActions()`**

Replace each hardcoded title in `buildActions()`:

```swift
items.append(ActionItem(action: .reply, title: NSLocalizedString("Reply", comment: ""), icon: "arrow.uturn.left", isDestructive: false))
```
```swift
items.append(ActionItem(action: .copy, title: NSLocalizedString("Copy", comment: ""), icon: "doc.on.doc", isDestructive: false))
```
```swift
items.append(ActionItem(action: .edit, title: NSLocalizedString("Edit", comment: ""), icon: "pencil", isDestructive: false))
```
```swift
items.append(ActionItem(action: .unsend, title: NSLocalizedString("messaging_undo_send", comment: ""), icon: "arrow.uturn.backward", isDestructive: true))
```
```swift
items.append(ActionItem(action: .deleteForMe, title: NSLocalizedString("Delete for Me", comment: ""), icon: "trash", isDestructive: true))
```
```swift
items.append(ActionItem(action: .report, title: NSLocalizedString("messaging_report_message", comment: ""), icon: "exclamationmark.triangle", isDestructive: true))
```

Note: `"Delete for Me"` is also changed to `isDestructive: true` per spec.

- [ ] **Step 2: Localize the delete-for-me alert title**

In `ConversationDetailView.swift:280`, change:

```swift
.alert("Delete for Me", isPresented: $showDeleteForMeConfirmation) {
```

To:

```swift
.alert("messaging_delete_for_me".localized, isPresented: $showDeleteForMeConfirmation) {
```

The key `"messaging_delete_for_me"` already exists in xcstrings (confirmed in audit).

- [ ] **Step 3: Add missing XCStrings entries**

Add to `Localizable.xcstrings`:
- `"messaging_undo_send"` → `"Undo Send"`
- `"messaging_report_message"` → `"Report"`
- `"messaging_view_thread"` → `"View Thread"` (if not added in Task 2)

- [ ] **Step 4: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift \
       NaarsCars/Features/Messaging/Views/ConversationDetailView.swift \
       NaarsCars/Resources/Localizable.xcstrings
git commit -m "fix: localize overlay action strings and delete-for-me alert via XCStrings"
```

---

## Chunk 2: Major Messaging Issues

### Task 7: Tap-to-timestamp — invalidate collection layout

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:611-634`

When the user taps a non-last cell to reveal the timestamp, `sizeThatFits()` grows by 18pt but the cell doesn't notify the collection view. The timestamp renders outside the cell bounds or overlaps adjacent rows.

- [ ] **Step 1: Add a layout invalidation callback**

Add a closure property to `MessageCellView`:

```swift
/// Called when the cell's intrinsic size changes (e.g. timestamp toggle).
/// The hosting cell should invalidate its collection view layout.
var onIntrinsicSizeChanged: (() -> Void)?
```

- [ ] **Step 2: Call it in `handleTap` after showing/hiding timestamp**

In `handleTap`, after `setNeedsLayout()` on line 623, add:

```swift
onIntrinsicSizeChanged?()
```

And in the hide work item (after line 630), after `self.setNeedsLayout()`:

```swift
self.onIntrinsicSizeChanged?()
```

- [ ] **Step 3: Wire it in `MessageContentCell` and `ThreadMessageCell`**

In `MessageContentCell` (in `MessagesCollectionView.swift`), in `override init`, after `contentView.addSubview(messageCellView)`:

```swift
messageCellView.onIntrinsicSizeChanged = { [weak self] in
    guard let self else { return }
    self.invalidateIntrinsicContentSize()
    if let collectionView = self.superview as? UICollectionView {
        collectionView.collectionViewLayout.invalidateLayout()
    }
}
```

Same for `ThreadMessageCell` in `MessageThreadViewController.swift`.

- [ ] **Step 4: Clear callback on reuse**

In `MessageCellView.prepareForReuse()`, add:

```swift
onIntrinsicSizeChanged = nil
```

(The hosting cell's init re-wires it, so clearing on reuse prevents stale closures.)

Wait — the hosting cell's init only runs once per cell instance, so the closure is set once. `prepareForReuse()` should NOT nil it out. Remove that step. The closure is stable across reuses.

- [ ] **Step 4 (revised): Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift \
       NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift \
       NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift
git commit -m "fix: invalidate collection layout when timestamp toggle changes cell height"
```

---

### Task 8: Draw reply spine path in `layoutSubviews()`

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:393-491`

`spineLayer` is toggled visible/hidden but no path is ever assigned. Add the path drawing at the end of the regular message layout in `layoutSubviews()`.

- [ ] **Step 1: Draw the spine path after avatar layout**

After the avatar layout block (line ~491), before the closing `}` of `layoutSubviews()`, add:

```swift
// Reply spine
if !spineLayer.isHidden, let spine = config.replySpine, let cv = visibleContentViews().first {
    let spineX: CGFloat = config.isFromCurrentUser
        ? cv.frame.maxX + 4
        : (avatarSize > 0 ? avatarSize / 2 : cv.frame.minX - 4)
    let topY = spine.showTop ? 0 : cv.frame.midY * 0.35
    let bottomY = spine.showBottom ? bounds.height : cv.frame.midY + (bounds.height - cv.frame.midY) * 0.65

    let path = UIBezierPath()
    path.move(to: CGPoint(x: spineX, y: topY))
    path.addLine(to: CGPoint(x: spineX, y: bottomY))
    spineLayer.path = path.cgPath
    spineLayer.frame = bounds
}
```

- [ ] **Step 2: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "fix: draw reply spine path in layoutSubviews — was declared but never rendered"
```

---

### Task 9: Group read receipt — show avatars for `.delivered` too

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/ReadReceiptView.swift:108-147`

The old SwiftUI implementation showed avatar thumbnails for both `.delivered` and `.read` when reader profiles were available. The current UIKit version only shows avatars for `.read`.

- [ ] **Step 1: Widen the avatar condition**

Change line 114 from:

```swift
if status == .read && !readByProfiles.isEmpty {
```

To:

```swift
if (status == .delivered || status == .read) && !readByProfiles.isEmpty {
```

- [ ] **Step 2: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/ReadReceiptView.swift
git commit -m "fix: show group read receipt avatars for delivered and read states"
```

---

### Task 10: Thread cell image tap + disconnected media actions

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift:513-537`

Image tap is a no-op in threads. The old thread view also didn't support overlay/swipe-reply, but image viewing should work.

- [ ] **Step 1: Implement image tap in the thread VC delegate**

```swift
func messageCellDidTapImage(_ cell: MessageCellView, url: URL) {
    let viewer = UIHostingController(rootView: FullScreenImageView(url: url, onDismiss: { [weak self] in
        self?.dismiss(animated: true)
    }))
    viewer.modalPresentationStyle = .fullScreen
    present(viewer, animated: true)
}
```

If `FullScreenImageView` does not exist as a standalone SwiftUI view, use the simpler approach of opening via SFSafariViewController for file URLs or presenting the image in a basic UIKit image viewer. Check what `ConversationDetailView` does — it uses a `.fullScreenCover` with an inline `fullscreenImageViewer(imageUrl:)`. Since we're in UIKit, the simplest approach:

```swift
func messageCellDidTapImage(_ cell: MessageCellView, url: URL) {
    let imageVC = UIViewController()
    imageVC.modalPresentationStyle = .fullScreen
    imageVC.view.backgroundColor = .black

    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageVC.view.addSubview(imageView)
    NSLayoutConstraint.activate([
        imageView.topAnchor.constraint(equalTo: imageVC.view.topAnchor),
        imageView.bottomAnchor.constraint(equalTo: imageVC.view.bottomAnchor),
        imageView.leadingAnchor.constraint(equalTo: imageVC.view.leadingAnchor),
        imageView.trailingAnchor.constraint(equalTo: imageVC.view.trailingAnchor),
    ])

    Task {
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            imageView.image = img
        }
    }

    let closeButton = UIButton(type: .system)
    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.tintColor = .white
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    imageVC.view.addSubview(closeButton)
    NSLayoutConstraint.activate([
        closeButton.topAnchor.constraint(equalTo: imageVC.view.safeAreaLayoutGuide.topAnchor, constant: 16),
        closeButton.trailingAnchor.constraint(equalTo: imageVC.view.trailingAnchor, constant: -16),
    ])
    closeButton.addAction(UIAction { _ in imageVC.dismiss(animated: true) }, for: .touchUpInside)

    present(imageVC, animated: true)
}
```

- [ ] **Step 2: Build and commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift
git commit -m "fix: thread cell image tap now opens full-screen viewer"
```

---

### Task 11: Scroll-to-message highlight state

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift:232-244`
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:69-101`

`isHighlighted` is hardcoded to `false`. The cell never renders highlight state on scroll-to-reply.

- [ ] **Step 1: Pass `highlightedMessageId` into MessagesCollectionView**

The `MessagesCollectionView` struct already receives `scrollToMessageId` which doubles as the highlight target. In the cell registration (line 243), change:

```swift
isHighlighted: false,
```

To:

```swift
isHighlighted: self.parent.scrollToMessageId == messageId,
```

- [ ] **Step 2: Render highlight in `MessageCellView.configure()`**

In `configure(with:)`, after the entrance animation block (after line 98), add:

```swift
// Highlight flash (scroll-to-reply)
if config.isHighlighted {
    backgroundColor = UIColor.naarsPrimary.withAlphaComponent(0.12)
    UIView.animate(withDuration: 1.5, delay: 0.3, options: .curveEaseOut) {
        self.backgroundColor = .clear
    }
} else {
    backgroundColor = .clear
}
```

- [ ] **Step 3: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift \
       NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "fix: render highlight flash on scroll-to-message for reply preview navigation"
```

---

### Task 12: Fix link preview default inversion

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/LinkPreviewBubbleView.swift:96`

`UserDefaults.standard.bool(forKey:)` returns `false` for missing keys, so `isCompact = !false = true` on first run. The user expectation (and Settings default) is that link previews are enabled.

- [ ] **Step 1: Use `object(forKey:)` with explicit default**

Change line 96 from:

```swift
self.isCompact = !UserDefaults.standard.bool(forKey: "messaging_showLinkPreviews")
```

To:

```swift
let prefValue = UserDefaults.standard.object(forKey: "messaging_showLinkPreviews") as? Bool ?? true
self.isCompact = !prefValue
```

- [ ] **Step 2: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/LinkPreviewBubbleView.swift
git commit -m "fix: default link preview preference to true for users without stored setting"
```

---

### Task 13: Async local image loading + generation counter

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift:89-102`

`Data(contentsOf:)` is synchronous on the main thread. For pending upload images this can be multi-MB JPEG decode. Also, the local configure path doesn't bump the generation counter, leaving a race window where a prior remote completion could overwrite the local image.

- [ ] **Step 1: Make local image loading async with generation counter**

Replace `configure(localPath:onTap:)`:

```swift
func configure(localPath: String, onTap: ((URL) -> Void)? = nil) {
    self.onTap = onTap
    let fileURL = LocalAttachmentStorage.fileURL(for: localPath)
    self.imageURL = fileURL
    self.lastLocalPath = localPath
    self.lastRemoteUrl = nil

    showLoading()

    loadGeneration &+= 1
    let gen = loadGeneration

    Task.detached(priority: .userInitiated) { [weak self] in
        let img: UIImage? = {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return UIImage(data: data)
        }()
        await MainActor.run {
            guard let self, self.loadGeneration == gen else { return }
            if let img {
                self.showImage(img)
            } else {
                self.showError()
            }
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift
git commit -m "fix: async local image loading with generation counter — eliminates main thread hitch"
```

---

## Chunk 3: Low-Priority Polish

### Task 14: Fix last-in-series bottom padding (12pt → 8pt)

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:528`

- [ ] **Step 1: Change padding constant**

```swift
let verticalPadding: CGFloat = config.isLastInSeries ? 8 : 2
```

- [ ] **Step 2: Build and commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "fix: last-in-series bottom padding 12pt → 8pt per spec"
```

---

### Task 15: Final build verification

- [ ] **Step 1: Clean build**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' clean build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Verify no remaining hardcoded English in overlay**

```bash
grep -n '"Reply"\|"Copy"\|"Edit"\|"Undo Send"\|"Delete for Me"\|"Report"' NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift
```

Expected: No matches (all wrapped in `NSLocalizedString`).

- [ ] **Step 3: Verify accessibility coverage**

```bash
grep -rn "accessibilityLabel\|isAccessibilityElement" NaarsCars/UI/Components/Messaging/Cells/ NaarsCars/UI/Components/Messaging/Overlay/ | wc -l
```

Expected: > 20 matches.
