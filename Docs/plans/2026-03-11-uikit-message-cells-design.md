# UIKit Message Cell Migration — Design Spec

**Date**: 2026-03-11
**Goal**: Replace SwiftUI `MessageBubble` + `UIHostingConfiguration` cell rendering with pure UIKit cells to eliminate 700–1600ms frame drops on keyboard appearance. Achieve pixel-perfect iMessage visual fidelity. Include interaction overlay and thread view rewrite.

---

## Problem

The current message list uses `UICollectionView` with `UIHostingConfiguration` to host SwiftUI `MessageBubble` views inside each cell. When the keyboard appears, safe area changes cause every hosting configuration to invalidate and re-render its full SwiftUI view hierarchy simultaneously. With 10+ visible cells, each containing a 1,356-line `MessageBubble` view that imports AVFoundation, MapKit, runs NSDataDetector, and computes read receipts, this blocks the main thread for 700–1600ms.

iMessage avoids this entirely by using pure UIKit cells — `UILabel`, `UIImageView`, `CAShapeLayer` — which are lightweight, reusable, and don't re-render on safe area changes.

---

## Architecture

### Approach: Incremental Cell-First Migration

Migrate in 5 layers, each independently testable:

1. Pure UIKit cell views (standalone `UIView` subclasses)
2. Cell container with composition + gestures
3. Collection view integration swap (`UIHostingConfiguration` → native cells)
4. Interaction overlay using UIKit with cell frame capture
5. Thread view rewrite + cleanup of dead SwiftUI code

### File Structure

The 1,356-line `MessageBubble.swift` decomposes into ~12 focused files under 200 lines each:

```
NaarsCars/UI/Components/Messaging/Cells/
├── MessageCellView.swift          (~180 lines)  — top-level UIView: composes content + gestures
├── TextBubbleView.swift           (~120 lines)  — text content with BubblePath background
├── ImageBubbleView.swift          (~100 lines)  — remote/local image with loading states
├── AudioBubbleView.swift          (~130 lines)  — waveform, play/pause, duration, Combine sub
├── LocationBubbleView.swift       (~100 lines)  — map snapshot + name, tap-to-open
├── LinkPreviewBubbleView.swift    (~100 lines)  — metadata card with thumbnail + title
├── SystemMessageView.swift        (~60 lines)   — centered pill with icon + text
├── UnsentMessageView.swift        (~50 lines)   — strikethrough indicator
├── BubblePath.swift               (~110 lines)  — UIBezierPath iMessage-accurate tail
├── ReactionBadgeView.swift        (~80 lines)   — emoji capsule with count
├── ReadReceiptView.swift          (~90 lines)   — checkmarks / avatar thumbnails
├── ReplyPreviewView.swift         (~60 lines)   — accent bar + sender name + preview text
├── DateSeparatorCell.swift        (~50 lines)   — day separator as its own cell type
```

Overlay:

```
NaarsCars/UI/Components/Messaging/Overlay/
├── MessageOverlayController.swift (~200 lines)  — UIViewController presented over chat
├── ReactionBarView.swift          (~100 lines)  — horizontal scrolling reaction strip
├── OverlayActionListView.swift    (~120 lines)  — action button list
```

Thread view:

```
NaarsCars/Features/Messaging/Views/
├── MessageThreadViewController.swift      (~250 lines)
├── MessageThreadRepresentable.swift       (~30 lines)  — UIViewControllerRepresentable bridge
```

Supporting:

```
NaarsCars/UI/Components/Common/
├── AvatarUIView.swift             (~80 lines)   — UIKit wrapper for avatar display
```

---

## MessageCellView Architecture

`MessageCellView` is the top-level `UIView` subclass that replaces `MessageBubble`. Hosted directly inside `UICollectionViewCell.contentView` — no `UIHostingConfiguration`.

### Configuration

```swift
struct MessageCellConfig {
    let message: Message
    let isFromCurrentUser: Bool
    let showAvatar: Bool              // avatar column for received msgs in groups
    let isFirstInSeries: Bool
    let isLastInSeries: Bool
    let isGroupConversation: Bool
    let totalParticipants: Int
    let participantProfiles: [Profile]
    let showReplyPreview: Bool
    let replySpine: (showTop: Bool, showBottom: Bool)?
    let isHighlighted: Bool
    let shouldAnimate: Bool           // spring entrance for newly arrived messages
}
```

Note: The legacy `isFailed: Bool` parameter is retired. Failed state is derived exclusively from `message.sendStatus == .failed` within the cell. The legacy fallback path in the old `MessageBubble` is not carried forward.

### Delegate Protocol

```swift
protocol MessageCellDelegate: AnyObject {
    func messageCellDidLongPress(_ cell: MessageCellView, message: Message)
    func messageCellDidTapReaction(_ cell: MessageCellView, message: Message, reaction: String?)
    func messageCellDidSwipeToReply(_ cell: MessageCellView, message: Message)
    func messageCellDidTapImage(_ cell: MessageCellView, url: URL)
    func messageCellDidTapReplyPreview(_ cell: MessageCellView, replyToId: UUID)
    func messageCellDidTapRetry(_ cell: MessageCellView, message: Message)
}
```

### Layout

Manual frame layout in `layoutSubviews()` — no Auto Layout. Each content subview reports its preferred size via `sizeThatFits(_:)`, and `MessageCellView` arranges them. This matches iMessage's approach and gives precise control over tail positioning and spacing.

Content views are created lazily and reused. On `configure()`, the cell hides all content views except the relevant one, then calls that view's own `configure()`.

---

## Bubble Geometry — iMessage-Accurate Tail

### Bubble Body
- Corner radius: 18pt (matching existing `BubbleShape`; will be tuned to iMessage's 17pt as a follow-up visual polish pass after the migration is stable)
- Max width: 70% of screen width
- Padding: 14pt horizontal, 10pt vertical for text (matching existing `MessageBubble`; will be tuned to iMessage's 12pt/8pt in the same follow-up pass)

### Tail
- Appears only on the last message in a series
- Sent: bottom-right. Received: bottom-left.
- Curves downward and inward, tapering to a point
- Height: ~6pt below bubble body. Width: ~10pt at base → 1pt point.
- Corner radius reduces from 17pt to ~2pt at the tail root for seamless flow
- Drawn as a single continuous `UIBezierPath` using `addCurve(to:controlPoint1:controlPoint2:)` — no joined arc/line segments
- Applied as a `CAShapeLayer` on the cell background

### Spacing
- Same sender, consecutive: 2pt
- Last in series: 8pt bottom padding
- Different day: `DateSeparatorCell` with 16pt vertical padding

---

## Gesture System

Three gestures on `MessageCellView`, all native UIKit recognizers:

### Swipe-to-Reply (UIPanGestureRecognizer)
- Minimum distance: 40pt
- Direction lock: horizontal > 2× vertical
- Sent: swipe left. Received: swipe right.
- Deceleration: 0.6× multiplier. Threshold: 60pt. Max: 72pt.
- Reply arrow icon fades/scales with progress
- Haptic: medium impact at threshold
- Release: `UIViewPropertyAnimator` spring (response: 0.3, damping: 0.7)
- Requires failure of scroll gesture when horizontal lock not met

### Long-Press (UILongPressGestureRecognizer)
- Duration: 0.5 seconds
- On `.began`: heavy haptic, delegate callback, coordinator captures cell frame via `layoutAttributesForItem(at:)` and snapshots cell, presents overlay controller

### Tap (UITapGestureRecognizer)
- Toggles timestamp visibility for 2 seconds (scheduled `DispatchWorkItem`)
- Failed messages: tap triggers retry instead

### Priority Chain
1. Pan and long-press coexist — pan activates immediately via direction lock (no failure dependency on long-press). Long-press has its own 0.5s duration gate.
2. Long-press requires pan to fail — if the user starts dragging horizontally, long-press is cancelled. This matches the current SwiftUI behavior where `DragGesture` and the UIKit `UILongPressGestureRecognizer` coexist without `require(toFail:)`.
3. Tap requires both pan and long-press to fail.

### Reaction Badge Gestures (on ReactionBadgeView)
- Tap: if current user has already reacted, call `messageCellDidTapReaction` with `nil` (remove their reaction). If current user has NOT reacted, call `messageCellDidLongPress` to open the overlay (so they can pick a reaction).
- Long-press (0.3s): call `messageCellDidTapReaction` with `"__details__"` to show `ReactionDetailsSheet`.

---

## Async Content Loading

### Cell-Reuse Safety: Generation Counter

Each async-loading content view holds `private var loadGeneration: UInt64 = 0`. On `configure()`, generation increments. On load completion, check generation matches — if not, discard result silently.

### Remote Images (ImageBubbleView)
- Sync check `PersistentImageService` disk cache first (no flash on cache hit)
- Cache miss: gray placeholder + spinner, async load, set if generation matches
- Error: retry icon, tap retries

### Audio Playback (AudioBubbleView)
- Combine `AnyCancellable` subscription to `MessageAudioPlayer.shared`
- On `configure()`: cancel previous, create new sink filtered to this audio URL
- Waveform: 20 bars as `CAShapeLayer` sublayers, progress fills left-to-right
- No UIHostingConfiguration overhead

### Map Snapshots (LocationBubbleView)
- Sync check `MapSnapshotCache.shared` first
- Miss: gray placeholder, async generate, set if generation matches
- Red pin overlay via `UIImageView`

### Link Previews (LinkPreviewBubbleView)
- Sync check `LinkPreviewService` cache (the existing `@MainActor` class defined in `LinkPreviewView.swift` — reused as-is, not renamed)
- Miss: show compact inline (domain name only), async fetch, upgrade to full card if generation matches
- URL detection via `URLDetectionCache` (currently `private` inside `MessageBubble.swift` — extracted to its own file as a Layer 1 prerequisite)
- User preference `messaging_showLinkPreviews` read from `UserDefaults.standard.bool(forKey:)` — controls whether to show full card or compact inline. `@AppStorage` is not available in UIKit.

### Avatar Images (AvatarUIView)
- Circular `UIImageView` + initials fallback `UILabel`
- Same generation-counter + `PersistentImageService` pattern
- Badge emojis positioned via manual frame layout

### Cancellation on Reuse
`prepareForReuse()` propagates from cell → `MessageCellView` → all content subviews. Each increments generation counter and cancels active `AnyCancellable`.

---

## Interaction Overlay

Replaces `MessageInteractionOverlay` (SwiftUI ZStack) and `ReactionPicker` with pure UIKit.

### Presentation Flow
1. Long-press fires on `MessageCellView`
2. Coordinator captures the cell's window-space frame. Because the collection view is flipped (`scaleY: -1`) and cells are counter-flipped, `convert(_:to:)` produces inverted Y coordinates. The correct approach: use `cell.convert(cell.bounds, to: nil)` which gives the cell's frame in window coordinates accounting for all ancestor transforms.
3. Snapshots cell via `cell.snapshotView(afterScreenUpdates: false)` (<1ms)
4. Creates `MessageOverlayController` with snapshot, frame, message, and an `OverlayAction` completion handler
5. Presents as `.overFullScreen` with `modalTransitionStyle = .crossDissolve`

### MessageOverlayController Layout
```
UIView (root)
├── UIVisualEffectView (.systemUltraThinMaterialDark)
├── messageSnapshotView (at captured frame, scaled 1.02×)
├── ReactionBarView (above snapshot)
└── OverlayActionListView (below snapshot)
```

### Entrance Animation (0.3s spring, response: 0.35, damping: 0.85)
- Blur: 0 → full opacity
- Snapshot: 1.0 → 1.02× scale
- Reaction bar: slides down 10pt, fades in
- Action list: slides up 10pt, fades in

### Dismissal
- Tap blur or any action button
- Reverse of entrance (0.25s)
- On completion: `dismiss(animated: false)`

### ReactionBarView
- `UIScrollView` with horizontal scroll, no paging
- `UIStackView` of 40pt circular reaction buttons
- Default 6 visible without scrolling: ❤️ 👍 👎 😂 ‼️ ❓
- Full set of 21 reactions (the current 6 + the 15 from the existing extended grid in `ReactionPicker.swift`) accessible via horizontal scroll — no expand/collapse toggle needed
- Selected reaction: 1.15× scale + background highlight
- Tap selected → removes reaction
- Pill-shaped background with ultra-thin material blur

### OverlayActionListView
- `UIStackView` in rounded rect (13pt corner radius, system material)
- 44pt rows: icon + label, separator lines
- Conditional actions:
  - **Reply** — always
  - **Copy** — if text exists
  - **Edit** — sent, text-only
  - **Undo Send** — sent, within 15 minutes
  - **Delete for Me** — always
  - **Report** — received only
- Destructive actions in `.systemRed`

### Adaptive Positioning
If reaction bar would clip top safe area → bar moves below snapshot, action list above. If action list would clip bottom → shifts upward.

### Callback Flow (Overlay → ConversationDetailView)

The current SwiftUI overlay is a ZStack layer that directly mutates `@State` variables on `ConversationDetailView` (e.g., `showUnsendConfirmation`, `messageToReport`). Switching to a presented `UIViewController` means the overlay cannot access that state directly.

**Solution:** `MessageOverlayController` takes a completion handler:

```swift
enum OverlayAction {
    case react(String)           // emoji string
    case removeReaction
    case reply
    case copy
    case edit
    case unsend
    case deleteForMe
    case report
}

init(
    snapshot: UIView,
    sourceFrame: CGRect,
    message: Message,
    isFromCurrentUser: Bool,
    currentUserReaction: String?,
    onAction: @escaping (OverlayAction) -> Void
)
```

The coordinator creates the overlay controller with an `onAction` closure that translates each action into the appropriate SwiftUI state mutation:

```swift
onAction: { [weak self] action in
    switch action {
    case .react(let emoji):
        Task { await viewModel.addReaction(messageId: message.id, reaction: emoji) }
    case .removeReaction:
        Task { await viewModel.removeReaction(messageId: message.id) }
    case .reply:
        replyingToMessage = ReplyContext(from: message)
    case .copy:
        UIPasteboard.general.string = message.text
    case .edit:
        viewModel.startEditing(message)
    case .unsend:
        showUnsendConfirmation = true; messageToUnsend = message
    case .deleteForMe:
        showDeleteForMeConfirmation = true; messageToDeleteForMe = message
    case .report:
        messageToReport = message; showReportSheet = true
    }
}
```

Each action button in `OverlayActionListView` dismisses the overlay first, then fires the action callback in the dismiss completion handler. This ensures the overlay is gone before any confirmation sheets are presented.

---

## Collection View Integration

### Current Flow (replaced)
```
SwiftUI body → closure → UIHostingConfiguration { MessageBubble } → full SwiftUI render per cell
```

### New Flow
```
updateUIView() → diffable snapshot → cell.configure(with: MessageCellConfig) → UIView layout only
```

### Snapshot Item Type
Changes from `UUID` to:
```swift
enum MessageListItem: Hashable {
    case message(UUID)
    case dateSeparator(Date)
}
```

Date separators become their own cells (previously rendered inside message cell content).

### Cell Registrations
Two registrations replace the single `UIHostingConfiguration` registration:
1. `MessageContentCell` — hosts `MessageCellView`
2. `DateSeparatorCell` — pure UIKit label in pill

### Delegate Wiring
`MessagesCollectionView.Coordinator` conforms to `MessageCellDelegate`. Translates callbacks into existing SwiftUI closure pattern passed from `ConversationDetailView`.

### ConversationDetailView Changes
The `messageCellContent: (Message, MessageCellConfiguration) -> AnyView` closure is removed. Replaced with raw data + callbacks:

```swift
MessagesCollectionView(
    messages: viewModel.messages,
    cellConfigurations: viewModel.messageCellConfigurations,
    participantProfiles: participantsViewModel.participants,
    isGroupConversation: isGroup,
    totalParticipants: totalParticipantsCount,
    onLongPress: { message, cellFrame, snapshot in ... },
    onSwipeReply: { message in ... },
    onImageTap: { url in ... },
    onReplyPreviewTap: { replyToId in ... },
    onRetry: { message in ... },
    onReactionTap: { message, reaction in ... },
    onLoadMore: { ... },
    onScrolledToBottom: { ... },
    scrollToMessageId: ...,
    scrollToBottom: ...
)
```

### What Stays the Same
- Flipped collection view transform
- Diffable data source with debounced applies
- Scroll-to-message and scroll-to-bottom
- Pagination via scroll delegate
- `contentInsetAdjustmentBehavior = .automatic` (now safe — no hosting contexts to invalidate)

---

## Thread View Rewrite

`MessageThreadView` (SwiftUI, ~200 lines) becomes `MessageThreadViewController` (UIKit).

### Architecture
`UIViewController` containing:
- `UICollectionView` with same cell registrations as main list
- Header: parent message as `MessageContentCell`
- Divider
- Replies section
- `MessageInputBar` stays SwiftUI, embedded via child `UIHostingController`

### Differences from Main List
- No flipped transform — normal top-to-bottom scroll
- No pagination — all replies loaded at once
- No typing indicators
- Auto-scrolls to bottom on new replies

### Presentation
Presented via `.fullScreenCover` using `MessageThreadRepresentable` (`UIViewControllerRepresentable` bridge).

### Data Flow
- Observes `MessageThreadViewModel` via Combine publishers (`$replies`, `$parentMessage`)
- Send actions route through `ConversationDetailViewModel.sendMessage(replyToId:)`
- `MessageCellDelegate` conformance for all interactions

---

## Deletion Inventory

### Files Deleted Entirely
- `MessageBubble.swift` (1,356 lines)
- `MessageInteractionOverlay.swift` (161 lines)
- `ReactionPicker.swift` (92 lines)

### Files with Major Deletions
- `ConversationDetailView.swift` — removes ~400 lines:
  - `createMessageBubble()` (~40 lines)
  - `messageBubbleSnapshot()` (~12 lines)
  - `interactionOverlayContent` (~45 lines)
  - `ReplyThreadSpineView` (~20 lines)
  - `DateSeparatorView` (~50 lines)
  - `MessageThreadView` struct (~200 lines)
  - `ThreadParent` struct
  - `showInteractionOverlay` / `interactionMessage` state
  - ZStack overlay layer with `BlurView`
  - `messageCellContent` closure

### Files Rewritten
- `MessagesCollectionView.swift` — same length, `UIHostingConfiguration` → native cells

### Files Unchanged
- All models (Message, Profile)
- All services (MessageAudioPlayer, MapSnapshotCache, PersistentImageService, LinkPreviewService, AuthService)
- All utilities (HapticManager, LocalAttachmentStorage)
- ConversationDetailViewModel, MessageSendManager
- AvatarView (stays SwiftUI, gains thin UIKit wrapper)
- CachedAsyncImage (stays SwiftUI, used elsewhere in app — profiles, conversation avatars, etc.)
- MessageInputBar (stays SwiftUI)
- ReactionDetailsSheet (stays SwiftUI, presented as `.sheet` from ConversationDetailView)
- ReportMessageSheet (stays SwiftUI)

### Files Extracted (new from existing code)
- `URLDetectionCache.swift` — extracted from `private` scope in `MessageBubble.swift` to standalone utility file
- `MessageThreadViewModel.swift` — extracted from inline definition in `ConversationDetailView.swift` (~55 lines) to its own file. Observed via Combine `$replies` and `$parentMessage` publishers by `MessageThreadViewController`. No logic changes.

### Notes
- `BlurView` (defined inside `MessageInteractionOverlay.swift`) is also deleted. Currently only used by the overlay ZStack in `ConversationDetailView` which is itself removed. No other code references it.
- `DebugFrameDropMonitor` (private class in `ConversationDetailView.swift`) is unaffected and continues to monitor frame performance.
- All UIKit cell views must maintain accessibility parity with the existing SwiftUI `MessageBubble` — labels, hints, and traits must be replicated.

### Net Change
- Deleted: ~1,850 lines
- Added: ~1,900 lines across 20 focused files (longest ~250 lines)
- Net increase: ~50 lines, but no file exceeds 250 lines (down from 1,356)

---

## Migration Layers

### Layer 1: UIKit Cell Views
Build all cell view files + BubblePath + AvatarUIView. Standalone, no integration.

*Test:* Instantiate each view with test data, verify rendering.

### Layer 2: MessageCellView Composition + Gestures
Build container with layout + gesture recognizers + delegate protocol.

*Test:* Single-cell test harness, verify all gesture callbacks.

### Layer 3: Collection View Integration (Performance-Critical)
Swap UIHostingConfiguration for native cells. Change snapshot type. Wire delegate.

*Test:* Main message list renders all types, keyboard no longer causes frame drops. A/B frame drop comparison.

### Layer 4: Interaction Overlay
Build overlay controller + reaction bar + action list. Wire long-press → frame capture → present.

*Test:* Long-press all message types, verify positioning, reactions, all actions.

### Layer 5: Thread View + Cleanup
Build thread view controller. Delete all dead SwiftUI code.

*Test:* Full regression — every message type, every interaction, every context (DM, group, thread).

### Risk Mitigation
Each layer is a commit boundary. Layers 1–2 add new files without touching existing code. Layer 3 is the swap — revertible independently. Layer 5 (deletion) is last so old code remains as reference during development.

---

## Dependencies & Risk Summary

### High-Risk Areas
1. **BubblePath bezier conversion** — 110 lines of path geometry, must match iMessage exactly
2. **Gesture state machine** — swipe deceleration + spring release + coexistence with scroll. Pan and long-press must coexist without `require(toFail:)` between them — long-press requires pan to fail (not vice versa), matching the current SwiftUI behavior
3. **Audio Combine subscription lifecycle** — must cancel on reuse, filter per-URL
4. **Layer 3 swap** — the performance-critical integration point
5. **Overlay frame capture** — coordinate conversion with flipped collection view. Must use `cell.convert(cell.bounds, to: nil)` to account for the `scaleY: -1` transforms on both the collection view and the cell content view
6. **MessageInputBar keyboard avoidance in thread view** — the input bar stays SwiftUI, embedded via child `UIHostingController`. SwiftUI's automatic keyboard avoidance (`.safeAreaInset(edge: .bottom)`) does not apply inside a UIKit parent. The thread view controller must manage `additionalSafeAreaInsets` or observe `UIResponder.keyboardWillShowNotification` to adjust the input bar position manually
7. **Overlay → ConversationDetailView callback flow** — the overlay is a presented view controller that cannot directly mutate SwiftUI `@State`. All actions route through an `OverlayAction` completion handler that the coordinator translates into state mutations. Confirmation sheets (unsend, delete, report) must be presented after overlay dismissal completes

### External Dependencies (unchanged)
- MessageAudioPlayer, MapSnapshotCache, PersistentImageService, LinkPreviewService
- AuthService, HapticManager, LocalAttachmentStorage, BadgeCache
- Date+Extensions, Typography, Color extensions

### Frameworks
- UIKit (primary), AVFoundation (audio), MapKit (location), LinkPresentation (link previews), Combine (async observation)
