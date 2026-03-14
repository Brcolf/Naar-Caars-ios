# iMessage Reactions & Threading Visual Parity — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Naars Cars message reactions and threading visually match iMessage on iOS 18.

**Architecture:** 6 targeted changes across the messaging UI layer, plus one Supabase RPC migration for reply counts. All changes are isolated to the messaging feature — no changes to auth, navigation, or other features.

**Tech Stack:** UIKit (message cells), SwiftUI (details sheet, conversation view), Supabase (RPC function), SF Symbols

**Spec:** `Docs/superpowers/specs/2026-03-13-imessage-reactions-threading-parity-design.md`

---

## Chunk 1: SF Symbol Glyph System

### Task 1: Create TapbackGlyph Utility

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/TapbackGlyph.swift`
- Test: `NaarsCars/NaarsCarsTests/Features/Messaging/TapbackGlyphTests.swift`

- [ ] **Step 1: Write the test file**

```swift
// TapbackGlyphTests.swift
import XCTest
@testable import NaarsCars

final class TapbackGlyphTests: XCTestCase {

    func testCoreReactionsReturnImages() {
        let coreReactions = ["❤️", "👍", "👎", "😂", "‼️", "❓"]
        for reaction in coreReactions {
            let image = TapbackGlyph.image(for: reaction, pointSize: 13)
            XCTAssertNotNil(image, "Expected SF Symbol image for core reaction \(reaction)")
        }
    }

    func testExtendedReactionsReturnNil() {
        let extended = ["🔥", "👏", "😢", "💯", "🎉"]
        for reaction in extended {
            let image = TapbackGlyph.image(for: reaction, pointSize: 13)
            XCTAssertNil(image, "Expected nil for extended reaction \(reaction)")
        }
    }

    func testImageRenderingMode() {
        let image = TapbackGlyph.image(for: "❤️", pointSize: 13)
        XCTAssertEqual(image?.renderingMode, .alwaysOriginal)
    }

    func testDifferentPointSizes() {
        let small = TapbackGlyph.image(for: "👍", pointSize: 13)
        let large = TapbackGlyph.image(for: "👍", pointSize: 22)
        XCTAssertNotNil(small)
        XCTAssertNotNil(large)
        // Larger point size should produce a larger image
        XCTAssertGreaterThan(large!.size.width, small!.size.width)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/TapbackGlyphTests 2>&1 | tail -20`
Note: Test file must be added to the Xcode project's NaarsCarsTests target.
Expected: Compilation error — `TapbackGlyph` not defined

- [ ] **Step 3: Implement TapbackGlyph**

```swift
// TapbackGlyph.swift
import UIKit

/// Maps the 6 core iMessage Tapback reactions to colored SF Symbol images.
/// Returns nil for extended emoji reactions (caller falls back to text rendering).
enum TapbackGlyph {

    private static let mapping: [(emoji: String, symbol: String, color: UIColor)] = [
        ("❤️",  "heart.fill",            .systemRed),
        ("👍",  "hand.thumbsup.fill",    .systemYellow),
        ("👎",  "hand.thumbsdown.fill",  .systemGray),
        ("😂",  "face.smiling",           .systemGreen),
        ("‼️",  "exclamationmark.2",     .systemOrange),
        ("❓",  "questionmark",           .systemPurple),
    ]

    static func image(for reaction: String, pointSize: CGFloat) -> UIImage? {
        guard let entry = mapping.first(where: { $0.emoji == reaction }) else { return nil }
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let symbol = UIImage(systemName: entry.symbol, withConfiguration: config) else { return nil }
        return symbol.withTintColor(entry.color, renderingMode: .alwaysOriginal)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/TapbackGlyphTests 2>&1 | tail -20`
Note: Test file must be added to the Xcode project's NaarsCarsTests target.
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/TapbackGlyph.swift NaarsCars/NaarsCarsTests/Features/Messaging/TapbackGlyphTests.swift
git commit -m "feat: add TapbackGlyph utility for SF Symbol Tapback rendering"
```

---

### Task 2: Update ReactionBadgeView — Overlapping Layout + SF Symbols

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift`

This task has two sub-changes applied to the same file: (a) overlapping capsule layout and (b) SF Symbol rendering inside capsules.

- [ ] **Step 1: Change capsule spacing to negative overlap**

In `ReactionBadgeView.swift`, change line 24:
```swift
// OLD:
private let capsuleSpacing: CGFloat = 4
// NEW:
private let capsuleSpacing: CGFloat = -6
```

- [ ] **Step 2: Add z-position layering in layoutSubviews**

In `ReactionBadgeView.swift`, update `layoutSubviews()` (lines 56-64) to set z-position so first capsule is on top:

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    var x: CGFloat = 0
    for (index, item) in capsules.enumerated() {
        item.view.sizeToFit()
        item.view.frame.origin = CGPoint(x: x, y: 0)
        item.view.layer.zPosition = CGFloat(capsules.count - index)
        x += item.view.frame.width + capsuleSpacing
    }
}
```

- [ ] **Step 3: Add SF Symbol rendering to ReactionCapsuleView**

In the private `ReactionCapsuleView` class (~line 125), add a `UIImageView` for SF Symbol glyphs and update `configure` and layout:

Add new property after `countLabel` declaration (line 128):
```swift
private let glyphImageView = UIImageView()
```

In `init` (after line 146 `addSubview(countLabel)`), add:
```swift
glyphImageView.contentMode = .scaleAspectFit
addSubview(glyphImageView)
```

Replace `configure(emoji:count:)` (lines 151-155):
```swift
func configure(emoji: String, count: Int) {
    if let glyph = TapbackGlyph.image(for: emoji, pointSize: 13) {
        glyphImageView.image = glyph
        glyphImageView.isHidden = false
        emojiLabel.isHidden = true
    } else {
        emojiLabel.text = emoji
        emojiLabel.isHidden = false
        glyphImageView.isHidden = true
        glyphImageView.image = nil
    }
    countLabel.text = count > 1 ? "\(count)" : nil
    countLabel.isHidden = count <= 1
}
```

Update `layoutSubviews()` in `ReactionCapsuleView` (lines 157-168):
```swift
override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
    let hPad: CGFloat = 8
    let spacing: CGFloat = 2

    if !glyphImageView.isHidden {
        let glyphSize: CGFloat = 13
        glyphImageView.frame = CGRect(x: hPad, y: (bounds.height - glyphSize) / 2, width: glyphSize, height: glyphSize)
        if !countLabel.isHidden {
            let countSize = countLabel.sizeThatFits(bounds.size)
            countLabel.frame = CGRect(x: glyphImageView.frame.maxX + spacing, y: (bounds.height - countSize.height) / 2, width: countSize.width, height: countSize.height)
        }
    } else {
        let emojiSize = emojiLabel.sizeThatFits(bounds.size)
        emojiLabel.frame = CGRect(x: hPad, y: (bounds.height - emojiSize.height) / 2, width: emojiSize.width, height: emojiSize.height)
        if !countLabel.isHidden {
            let countSize = countLabel.sizeThatFits(bounds.size)
            countLabel.frame = CGRect(x: emojiLabel.frame.maxX + spacing, y: (bounds.height - countSize.height) / 2, width: countSize.width, height: countSize.height)
        }
    }
}
```

Update `sizeThatFits` in `ReactionCapsuleView` (lines 170-181):
```swift
override func sizeThatFits(_ size: CGSize) -> CGSize {
    let hPad: CGFloat = 8
    let vPad: CGFloat = 4
    let spacing: CGFloat = 2

    let contentWidth: CGFloat
    let contentHeight: CGFloat
    if !glyphImageView.isHidden {
        let glyphSize: CGFloat = 13
        contentWidth = glyphSize
        contentHeight = glyphSize
    } else {
        let emojiSize = emojiLabel.sizeThatFits(size)
        contentWidth = emojiSize.width
        contentHeight = emojiSize.height
    }

    var w = hPad + contentWidth + hPad
    if !countLabel.isHidden {
        let countSize = countLabel.sizeThatFits(size)
        w = hPad + contentWidth + spacing + countSize.width + hPad
    }
    return CGSize(width: w, height: contentHeight + vPad * 2)
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift
git commit -m "feat: overlapping reaction capsules with SF Symbol Tapback glyphs"
```

---

### Task 3: Update ReactionBarView — SF Symbol Buttons for Core 6

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift:106-143`

- [ ] **Step 1: Update makeReactionButton to use SF Symbols for core 6**

Replace `makeReactionButton(emoji:)` method (lines 106-143):

```swift
private func makeReactionButton(emoji: String) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false

    if let glyph = TapbackGlyph.image(for: emoji, pointSize: 22) {
        button.setImage(glyph, for: .normal)
        button.setTitle(nil, for: .normal)
    } else {
        button.setTitle(emoji, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22)
    }

    button.layer.cornerRadius = buttonSize / 2
    button.clipsToBounds = true

    NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: buttonSize),
        button.heightAnchor.constraint(equalToConstant: buttonSize),
    ])

    let isSelected = emoji == currentUserReaction
    if isSelected {
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.25)
        button.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        button.accessibilityTraits = [.button, .selected]
        button.accessibilityHint = NSLocalizedString("accessibility_reaction_remove_hint", comment: "Hint for removing an already-selected reaction")
    } else {
        button.accessibilityHint = NSLocalizedString("accessibility_reaction_add_hint", comment: "Hint for adding a reaction")
    }
    button.accessibilityLabel = emoji
    button.accessibilityIdentifier = "overlay.reaction.\(emoji)"

    button.addAction(UIAction { [weak self] _ in
        guard let self else { return }
        if emoji == self.currentUserReaction {
            self.onRemoveReaction?()
        } else {
            self.onReact?(emoji)
        }
    }, for: .touchUpInside)

    return button
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift
git commit -m "feat: SF Symbol Tapback glyphs in reaction picker bar"
```

---

### Task 4: Update ReactionDetailsSheet — SF Symbol Headers

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ReactionDetailsSheet.swift:21-22`

- [ ] **Step 1: Update section header to use TapbackGlyph**

Replace the section header (line 22) to conditionally render SF Symbol or emoji:

```swift
Section(header: reactionHeader(emoji: reactionData.reaction, count: reactionData.count)) {
```

Add a helper method before the `sortedReactions` computed property (before line 66):

```swift
@ViewBuilder
private func reactionHeader(emoji: String, count: Int) -> some View {
    HStack(spacing: 4) {
        if let uiImage = TapbackGlyph.image(for: emoji, pointSize: 18) {
            Image(uiImage: uiImage)
        } else {
            Text(emoji)
        }
        Text("\(count)")
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ReactionDetailsSheet.swift
git commit -m "feat: SF Symbol Tapback glyphs in reaction details sheet headers"
```

---

## Chunk 2: Message Cell Visual Tweaks

### Task 5: Reaction Badge Vertical Position + Long-Press Speed

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:491,609`

- [ ] **Step 1: Update badge vertical offset from 50% to 60%**

In `MessageCellView.swift` line 491, change:
```swift
// OLD:
rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height / 2, width: rbSize.width, height: rbSize.height)
// NEW:
rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height * 0.6, width: rbSize.width, height: rbSize.height)
```

- [ ] **Step 2: Update long-press duration from 0.5s to 0.3s**

In `MessageCellView.swift` line 609, change:
```swift
// OLD:
longPressGesture.minimumPressDuration = 0.5
// NEW:
longPressGesture.minimumPressDuration = 0.3
```

Update the comment on line 610-612:
```swift
// No require(toFail:) — pan and long-press coexist. Pan activates via
// horizontal direction lock in gestureRecognizerShouldBegin; long-press
// has its own 0.3s duration gate. Per spec: "Pan and long-press coexist."
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "fix: adjust reaction badge to 60% overlap, reduce long-press to 0.3s"
```

---

### Task 6: Curved Reply Spine

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:64-67,538-551`

- [ ] **Step 1: Set round line cap on spine layer**

In `MessageCellView.swift` init, after line 67 (`spineLayer.fillColor = nil`), add:
```swift
spineLayer.lineCap = .round
```

- [ ] **Step 2: Replace straight spine with curved bezier paths**

Replace the reply spine block (lines 538-551) with:

```swift
// Reply spine
if !spineLayer.isHidden, let spine = config.replySpine, let cv = contentViews.first {
    let spineX: CGFloat = config.isFromCurrentUser
        ? cv.frame.maxX + 4
        : (avatarSize > 0 ? avatarSize / 2 : cv.frame.minX - 4)
    let topY = spine.showTop ? 0 : cv.frame.midY * 0.35
    let bottomY = spine.showBottom ? bounds.height : cv.frame.midY + (bounds.height - cv.frame.midY) * 0.65

    let path = UIBezierPath()
    path.move(to: CGPoint(x: spineX, y: topY))

    if !spine.showTop && spine.showBottom {
        // First in chain: curve from reply preview down to cell bottom
        let controlY = topY + (bottomY - topY) * 0.3
        path.addQuadCurve(to: CGPoint(x: spineX, y: bottomY),
                          controlPoint: CGPoint(x: spineX + (config.isFromCurrentUser ? 6 : -6), y: controlY))
    } else if spine.showTop && !spine.showBottom {
        // Last in chain: curve from cell top down to content
        let controlY = topY + (bottomY - topY) * 0.7
        path.addQuadCurve(to: CGPoint(x: spineX, y: bottomY),
                          controlPoint: CGPoint(x: spineX + (config.isFromCurrentUser ? 6 : -6), y: controlY))
    } else {
        // Middle of chain or single: straight vertical line
        path.addLine(to: CGPoint(x: spineX, y: bottomY))
    }

    spineLayer.path = path.cgPath
    spineLayer.frame = bounds
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "feat: curved reply spine matching iMessage connector style"
```

---

## Chunk 3: Reply Count System

### Task 7: Supabase Migration — Reply Count RPC

**Files:**
- Create: `database/129_add_reply_count_rpc.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Add RPC function to batch-fetch reply counts for messages
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

- [ ] **Step 2: Apply migration via Supabase MCP**

Use `mcp__supabase__apply_migration` to apply the migration with name `add_reply_count_rpc`.

- [ ] **Step 3: Verify RPC works**

Use `mcp__supabase__execute_sql` to test:
```sql
SELECT * FROM get_reply_counts(
  '00000000-0000-0000-0000-000000000000'::UUID,
  ARRAY[]::UUID[]
);
```
Expected: Empty result set (no error).

- [ ] **Step 4: Commit**

```bash
git add database/129_add_reply_count_rpc.sql
git commit -m "feat: add get_reply_counts RPC function for batch reply count queries"
```

---

### Task 8: MessageService — fetchReplyCounts Method

**Files:**
- Modify: `NaarsCars/Core/Services/MessageService.swift`

- [ ] **Step 1: Add the fetchReplyCounts method**

Add this method to `MessageService` (after the existing `fetchReplies` method). Follow the existing RPC pattern from `AdminService.swift`:

```swift
/// Batch-fetch reply counts for a set of message IDs in a conversation.
func fetchReplyCounts(conversationId: UUID, messageIds: [UUID]) async throws -> [UUID: Int] {
    guard !messageIds.isEmpty else { return [:] }

    struct RPCRow: Decodable {
        let parent_id: UUID
        let reply_count: Int
    }

    let params: [String: AnyEncodable] = [
        "p_conversation_id": AnyEncodable(conversationId),
        "p_message_ids": AnyEncodable(messageIds)
    ]

    let response = try await supabase
        .rpc("get_reply_counts", params: params)
        .execute()

    let rows = try JSONDecoder().decode([RPCRow].self, from: response.data)

    var result: [UUID: Int] = [:]
    for row in rows {
        result[row.parent_id] = row.reply_count
    }
    return result
}
```

Note: Check if the codebase uses `AnyEncodable`, `AnyCodable`, or a similar type-erased wrapper for RPC params. Match the existing pattern (e.g., `AdminService` uses `AnyCodable`).

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Core/Services/MessageService.swift
git commit -m "feat: add fetchReplyCounts RPC method to MessageService"
```

---

### Task 9: ConversationDetailViewModel — Reply Count Hydration

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

- [ ] **Step 1: Add replyCountMap published property**

Add alongside other published properties (near existing `@Published` vars):
```swift
@Published var replyCountMap: [UUID: Int] = [:]
```

- [ ] **Step 2: Add loadReplyCountsForMessages method**

Add after the existing `loadReactionsForMessages()` method:

```swift
/// Batch-fetch reply counts for all loaded messages.
private func loadReplyCountsForMessages() async {
    let messageIds = messages.map(\.id)
    guard !messageIds.isEmpty, let conversationId = conversation?.id else { return }
    do {
        let counts = try await MessageService.shared.fetchReplyCounts(
            conversationId: conversationId,
            messageIds: messageIds
        )
        guard !counts.isEmpty else { return }
        await MainActor.run {
            replyCountMap.merge(counts) { _, new in new }
        }
    } catch {
        // Non-critical — reply counts are supplementary UI, don't surface error
        print("[ConversationDetailVM] Failed to load reply counts: \(error)")
    }
}
```

- [ ] **Step 3: Call loadReplyCountsForMessages after loading messages**

Find where `loadReactionsForMessages()` is called (typically after messages are loaded) and add the reply count call alongside it:
```swift
await loadReplyCountsForMessages()
```

- [ ] **Step 4: Increment count on real-time new reply**

In the handler where new messages arrive in real-time, add:
```swift
if let replyToId = newMessage.replyToId {
    replyCountMap[replyToId, default: 0] += 1
}
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift
git commit -m "feat: batch reply count hydration in ConversationDetailViewModel"
```

---

### Task 10: MessageCellConfig + MessageCellDelegate — Add replyCount

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewController.swift:166-179,415-459`
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift:340-353,580-610`
- Modify: `NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift:314-327`

There are THREE `MessageCellDelegate` conformers and THREE `MessageCellConfig` call sites. All must be updated in this task to avoid a build break.

- [ ] **Step 1: Add replyCount to MessageCellConfig**

In `MessageCellConfig.swift`, add new property after `shouldAnimate` (line 17):
```swift
let replyCount: Int
```

- [ ] **Step 2: Add delegate method for thread tap**

Add to `MessageCellDelegate` protocol (after `messageCellDidTapRetry`):
```swift
func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message)
```

- [ ] **Step 3: Fix ALL THREE call sites that construct MessageCellConfig**

**(a) MessagesViewController.swift** line 178 — add before closing paren:
```swift
replyCount: 0
```

**(b) MessageThreadViewController.swift** line 352 — add before closing paren:
```swift
replyCount: 0
```

**(c) MessagesCollectionView.swift** line 326 — add before closing paren:
```swift
replyCount: 0
```

(All three get `0` for now. Task 12 will wire the actual values through `MessagesViewController`.)

- [ ] **Step 4: Add delegate method stubs to ALL THREE conformers**

**(a) MessagesViewController.swift** — add in the `MessageCellDelegate` extension (after `messageCellDidTapRetry`, ~line 458):
```swift
func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message) {
    configuration.onViewThread?(message)
}
```

**(b) MessageThreadViewController.swift** — add in the `MessageCellDelegate` extension (after last method):
```swift
func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message) {
    // Thread view doesn't support nested thread navigation
}
```

**(c) MessagesCollectionView.Coordinator** — add in the `MessageCellDelegate` extension:
```swift
func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message) {
    // Not used — MessagesViewController is the production path
}
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (note: `configuration.onViewThread` doesn't exist yet — that's added in Task 12. The build won't break because `MessagesViewController.Configuration` uses optional closures. Actually, `onViewThread` doesn't exist yet so this line WILL fail. Add the property to `Configuration` in this task instead.)

**IMPORTANT**: Also add `var onViewThread: ((Message) -> Void)?` to `MessagesViewController.Configuration` struct (line 43) in this step. This prevents the build break from Step 4a.

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift \
       NaarsCars/Features/Messaging/Views/MessagesViewController.swift \
       NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift \
       NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift
git commit -m "feat: add replyCount to MessageCellConfig and thread tap delegate"
```

---

### Task 11: MessageCellView — Reply Count Label UI

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift`

- [ ] **Step 1: Add replyCountLabel property**

Add after `failedRetryLabel` declaration (line 31):
```swift
private var replyCountLabel: UILabel?
```

- [ ] **Step 2: Add reply count configuration in configure(with:)**

After the reply spine block (after line 327), add:

```swift
// Reply count label
if config.replyCount > 0 {
    let label = replyCountLabel ?? {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .naarsPrimary
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleReplyCountTap))
        l.addGestureRecognizer(tap)
        l.isUserInteractionEnabled = true
        addSubview(l)
        replyCountLabel = l
        return l
    }()
    label.isHidden = false
    label.text = config.replyCount == 1
        ? NSLocalizedString("messaging_1_reply", comment: "")
        : String(format: NSLocalizedString("messaging_n_replies", comment: ""), config.replyCount)
} else {
    replyCountLabel?.isHidden = true
}
```

- [ ] **Step 3: Add tap handler**

Add after `handleTap` or in the gestures section:
```swift
@objc private func handleReplyCountTap() {
    guard let config else { return }
    delegate?.messageCellDidTapViewThread(self, message: config.message)
}
```

- [ ] **Step 4: Add layout for replyCountLabel in layoutSubviews**

After the failed retry block (after line 530), before the avatar block, add:

```swift
// Reply count label
if let rcl = replyCountLabel, !rcl.isHidden {
    rcl.sizeToFit()
    let rclX = config.isFromCurrentUser
        ? bounds.width - rcl.frame.width - 4
        : avatarSize + avatarSpacing + 4
    rcl.frame.origin = CGPoint(x: rclX, y: y)
    y += rcl.frame.height + 4
}
```

**Important:** Make sure the `y` variable is being accumulated before the avatar block. The existing code at line 530 does not increment `y` after the failed retry label. You may need to also add `y += fr.frame.height` after line 529 if not already done, or track `y` through the timestamp and failed-retry blocks.

- [ ] **Step 5: Update sizeThatFits to account for reply count**

After line 589 (`if failedRetryLabel?.isHidden == false { height += 18 }`), add:
```swift
// Reply count
if replyCountLabel?.isHidden == false { height += 18 }
```

- [ ] **Step 6: Add prepareForReuse cleanup**

In the existing `prepareForReuse()` method, add:
```swift
replyCountLabel?.isHidden = true
```

- [ ] **Step 7: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "feat: add N Replies tappable label below parent messages"
```

---

### Task 12: Wire Reply Counts Through the View Layer

The data flow is: `ConversationDetailView` → `MessagesViewControllerRepresentable` → `MessagesViewController.Configuration` → cell construction. The `MessagesCollectionView` UIViewRepresentable is NOT the production path — `MessagesViewController` is.

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift:13-57,96-124`
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewController.swift:17-44,166-179`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift:354-454`

- [ ] **Step 1: Add replyCountMap to MessagesViewControllerRepresentable**

Add property after `onScrolledToBottom` (around line 30):
```swift
let replyCountMap: [UUID: Int]
```

- [ ] **Step 2: Add replyCountMap to MessagesViewController.Configuration**

In `MessagesViewController.swift`, add to `Configuration` struct (after `isConversationFrozen`, line 32):
```swift
var replyCountMap: [UUID: Int] = [:]
```

(`onViewThread` was already added in Task 10.)

- [ ] **Step 3: Wire replyCountMap in updateUIViewController**

In `MessagesViewControllerRepresentable.swift` `updateUIViewController` (line 96-124), add after `config.isConversationFrozen = isConversationFrozen` (line 122):
```swift
config.replyCountMap = replyCountMap
config.onViewThread = { [weak coordinator = context.coordinator] message in
    coordinator?.parent.onViewThread?(message)
}
```

Wait — `onViewThread` is not a property on the representable yet. Add it:
```swift
let onViewThread: ((Message) -> Void)?
```

- [ ] **Step 4: Pass replyCount in MessagesViewController cell config**

In `MessagesViewController.swift` line 178, change `replyCount: 0` (from Task 10) to:
```swift
replyCount: self.configuration.replyCountMap[messageId] ?? 0
```

- [ ] **Step 5: Pass from ConversationDetailView**

In `ConversationDetailView.swift`, update the `MessagesViewControllerRepresentable(` init (~line 354).

Add after `isConversationFrozen: viewModel.hasLeftConversation` (line 453):
```swift
replyCountMap: viewModel.replyCountMap,
onViewThread: { message in
    activeThreadParent = ThreadParent(id: message.id)
}
```

- [ ] **Step 6: Add localization strings**

Add to `Localizable.xcstrings` (or the appropriate localization file):
- Key: `messaging_1_reply` → Value: `"1 Reply"`
- Key: `messaging_n_replies` → Value: `"%d Replies"`

- [ ] **Step 7: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift \
       NaarsCars/Features/Messaging/Views/MessagesViewController.swift \
       NaarsCars/Features/Messaging/Views/ConversationDetailView.swift
git commit -m "feat: wire reply count map through view layer to message cells"
```

---

## Final Verification

### Task 13: Build + Test Full Suite

- [ ] **Step 1: Run full test suite**

```bash
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```
Expected: All tests PASS, no regressions

- [ ] **Step 2: Visual verification checklist**

Run the app in Simulator and verify:
- [ ] Reaction badges overlap with first capsule on top
- [ ] Core 6 reactions show SF Symbol glyphs (heart=red, thumb=yellow, etc.)
- [ ] Extended reactions (🔥 👏 etc.) still show as emoji text
- [ ] Reaction picker bar shows SF Symbols for first 6 buttons
- [ ] Reaction details sheet shows SF Symbol headers for core 6
- [ ] Badge sits ~60% above bubble top edge
- [ ] Long-press triggers after ~0.3s (noticeably snappier)
- [ ] Reply spine has gentle curve at chain start/end
- [ ] Messages with replies show "N Replies" label below timestamp
- [ ] Tapping "N Replies" opens thread view
- [ ] Messages with both reactions AND reply counts display correctly

- [ ] **Step 3: Final commit if any fixups needed**

```bash
git add -A && git commit -m "fix: visual polish from manual verification"
```
