# iMessage Reaction Sticker Parity Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the reaction system to match iMessage iOS 18 — per-person sticker badges, 6 standard tapbacks + any-emoji picker, custom HAHA artwork, and inline reaction details.

**Architecture:** Rebuild the badge view (per-person stickers replace aggregated capsules), refactor the picker bar (6 tapbacks + recents + emoji keyboard button), extend the overlay controller (inline reaction details row), and simplify TapbackGlyph to HAHA-only artwork. `individualReactions` becomes the single source of truth; aggregated `MessageReactions` is derived from it.

**Tech Stack:** Swift, UIKit (all reaction UI components), SwiftUI (ConversationDetailView cleanup only), Supabase (existing service layer)

**Spec:** `Docs/superpowers/specs/2026-03-14-imessage-reaction-sticker-parity-design.md`

**Working directory:** All commands assume the working directory is `/Users/bcolf/Documents/naars-cars-ios`. All relative file paths are relative to this root.

**Xcode project inclusion:** When creating new `.swift` files, you must add them to the `NaarsCars` target in the Xcode project. Either create the file via Xcode (which adds it automatically) or manually add it to `project.pbxproj` after creating it on disk.

---

## Execution Rules

These constraints govern how the plan is executed. They override any conflicting step-level instructions.

1. **No knowingly broken commits.** Tasks 1-4 are an atomic data-layer block — execute all four, build-verify once, commit once. If any later task introduces a temporary red build due to caller mismatch, complete the dependent caller updates before committing.

2. **`individualReactions` is app-local state, not server payload.** `Message` uses explicit `CodingKeys` (line 209 of `Message.swift`) and already excludes `reactions` and `replyToMessage` from coding (line 230: `// reactions and replyToMessage are not in CodingKeys - populated separately`). `individualReactions` is safe to add — it will be automatically excluded from JSON encoding/decoding because it is not listed in `CodingKeys`.

3. **Centralize the data invariant via a helper.** Add `mutating func setIndividualReactions(_ records: [MessageReaction]?)` to `Message` (see Task 3). Use it everywhere: initial load, refresh, optimistic add, optimistic remove, rollback.

4. **Hidden emoji keyboard: stop-and-report if unstable.** The hidden `UITextField` approach is preferred. If it causes keyboard presentation instability, overlay dismissal bugs, responder conflicts, or inconsistent emoji capture, stop and report rather than forcing it through. A dedicated emoji picker surface is the documented fallback.

5. **Remove `"__details__"` sentinel codebase-wide.** When cleaning up the old flow, search the entire codebase for `"__details__"` and remove all references. Two live code sites: `ConversationDetailView.swift:379` and `MessageCellView.swift:309`.

6. **Optimistic updates use the latest UI state.** Confirmed: `messages` is passed by value from the `@Published` property at call time in `ConversationDetailViewModel.addReaction/removeReaction`. The existing pattern is safe — no redesign needed.

7. **All UI constants are tunable.** Implement sticker size, overlap, X/Y offsets, corner radii, and details-row dimensions as named constants. Never hard-code geometry in layout logic.

8. **Thread-context verification is required.** The final verification pass must include: sticker badge rendering in thread view, badge-tap opening overlay details in thread context, and remove-own-reaction from inline details in thread context.

9. **Accessibility requirements:**
   - HAHA artwork: `accessibilityLabel = "Ha ha"` in picker, badge, and details row
   - Sticker badges: descriptive labels (e.g., "2 reactions: heart, thumbs up" rather than raw emoji list when practical)
   - Selected picker reactions: expose `.selected` trait
   - Emoji keyboard button: labeled for VoiceOver

---

## Chunk 1: Data Model & Service Layer (Atomic Block — Tasks 1-4)

Tasks 1-4 are executed as a single atomic block. Build verification runs only after all four are complete. One commit for the entire block.

### Task 1: Simplify MessageReaction model

**Files:**
- Modify: `NaarsCars/Core/Models/MessageReaction.swift`

- [ ] **Step 1: Remove old reaction sets and validation**

Replace lines 40-52 of `MessageReaction.swift` with the new `standardTapbacks` array:

```swift
// Replace everything from line 40 to line 52 with:

/// The 6 standard iMessage tapback reactions.
/// 😂 is stored as the emoji but rendered as custom "HA HA" artwork by the UI layer.
static let standardTapbacks = ["❤️", "👍", "👎", "😂", "‼️", "❓"]
```

This removes `quickReactions`, `extendedReactions`, `validReactions`, and the `isValid` computed property. Any emoji is now a valid reaction — validation is no longer the model's responsibility.

_(No build verification or commit — part of atomic block. Proceed to Task 2.)_

---

### Task 2: Update MessageReactionService — remove validation, add fetchIndividualReactions

**Files:**
- Modify: `NaarsCars/Core/Services/MessageReactionService.swift`

- [ ] **Step 1: Remove the validation guard in addReaction**

In `MessageReactionService.swift`, delete lines 44-47 (the `guard MessageReaction.validReactions.contains(reaction)` block):

```swift
// DELETE these lines (44-47):
// guard MessageReaction.validReactions.contains(reaction) else {
//     throw AppError.invalidInput("Invalid reaction")
// }
```

The method now accepts any emoji string.

- [ ] **Step 2: Add fetchIndividualReactions method**

Add this new method after `fetchReactions` (after line 137):

```swift
/// Fetch individual reaction records for a message.
/// This is the primary fetch method — callers derive aggregated `MessageReactions` from these records.
/// - Parameter messageId: The message ID
/// - Returns: Array of individual MessageReaction records
/// - Throws: AppError if fetch fails
func fetchIndividualReactions(messageId: UUID) async throws -> [MessageReaction] {
    let response = try await supabase
        .from("message_reactions")
        .select()
        .eq("message_id", value: messageId.uuidString)
        .execute()

    let decoder = createDateDecoder()
    return try decoder.decode([MessageReaction].self, from: response.data)
}
```

- [ ] **Step 3: Remove the old fetchReactions method**

Delete the entire `fetchReactions(messageId:) -> MessageReactions` method (lines 115-137). All callers will be migrated to `fetchIndividualReactions` in subsequent tasks. This prevents any code from bypassing the source-of-truth invariant.

_(No build verification or commit — part of atomic block. Proceed to Task 3.)_

---

### Task 3: Add individualReactions to Message model with derivation helper

**Files:**
- Modify: `NaarsCars/Core/Models/Message.swift`

- [ ] **Step 1: Add individualReactions property**

After line 158 (`var reactions: MessageReactions?`), add:

```swift
/// Individual per-user reaction records — single source of truth for reaction state.
/// `reactions` (aggregated) is derived from this array. Never mutate `reactions` independently.
var individualReactions: [MessageReaction]?
```

- [ ] **Step 2: Add the derivation helper and centralized setter**

`individualReactions` is not in `CodingKeys` (line 230 confirms: `// reactions and replyToMessage are not in CodingKeys`), so adding it will not change JSON encode/decode behavior.

Add these to `Message.swift`:

```swift
// Inside the Message struct, after the individualReactions property:

/// Centralized setter that maintains the data invariant:
/// sets `individualReactions`, then derives `reactions` from it.
/// Use this everywhere instead of setting the two properties independently.
mutating func setIndividualReactions(_ records: [MessageReaction]?) {
    individualReactions = records?.isEmpty == true ? nil : records
    reactions = MessageReactions.from(records ?? [])
}
```

And add this extension at the bottom of `Message.swift` (after the struct closing brace):

```swift
extension MessageReactions {
    /// Derive aggregated reactions from individual records.
    /// This is the only sanctioned way to produce a `MessageReactions` value.
    static func from(_ records: [MessageReaction]) -> MessageReactions? {
        guard !records.isEmpty else { return nil }
        var dict: [String: [UUID]] = [:]
        for record in records {
            dict[record.reaction, default: []].append(record.userId)
        }
        return MessageReactions(reactions: dict)
    }
}
```

- [ ] **Step 3: Add individualReactions to Message's init and Equatable**

In `Message.swift`:

1. Find the manual `init` (search for `init(` in the struct body). Add `individualReactions: [MessageReaction]? = nil` at the end of the parameter list, and `self.individualReactions = individualReactions` in the body.

2. Find the manual `Equatable` conformance (the `static func ==` around line 319). Add the comparison after the existing `lhs.reactions == rhs.reactions` line (around line 344):
```swift
lhs.individualReactions == rhs.individualReactions &&
```

_(No build verification or commit — part of atomic block. Proceed to Task 4.)_

---

### Task 4: Migrate ViewModel to use fetchIndividualReactions

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

- [ ] **Step 1: Update refreshReactions to use fetchIndividualReactions and setIndividualReactions**

Replace the `refreshReactions(for:)` method (around line 284) with:

```swift
private func refreshReactions(for messageId: UUID) async {
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    do {
        let individual = try await MessageReactionService.shared.fetchIndividualReactions(messageId: messageId)
        messages[index].setIndividualReactions(individual)
    } catch {
        AppLogger.error("messaging", "Failed to refresh reactions: \(error)")
    }
}
```

- [ ] **Step 2: Update loadReactionsForMessages to use fetchIndividualReactions and setIndividualReactions**

Replace the `loadReactionsForMessages()` method (around line 331) — change the task group to fetch individual records and use the centralized setter:

```swift
private func loadReactionsForMessages() async {
    let messageIds = messages.map(\.id)
    guard !messageIds.isEmpty else { return }

    var results: [(UUID, [MessageReaction])] = []
    await withTaskGroup(of: (UUID, [MessageReaction]).self) { group in
        for id in messageIds {
            group.addTask {
                let records = (try? await MessageReactionService.shared.fetchIndividualReactions(messageId: id)) ?? []
                return (id, records)
            }
        }
        for await result in group {
            results.append(result)
        }
    }

    var updated = messages
    var didChange = false
    for (id, records) in results {
        if let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index].setIndividualReactions(records)
            didChange = true
        }
    }
    if didChange {
        messages = updated
    }
}
```

- [ ] **Step 3: Build verify the entire atomic block (Tasks 1-4)**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS — all callers of the deleted `fetchReactions` and `validReactions` have been migrated.

- [ ] **Step 4: Commit the entire atomic block**

```bash
git add NaarsCars/Core/Models/MessageReaction.swift NaarsCars/Core/Models/Message.swift NaarsCars/Core/Services/MessageReactionService.swift NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift
git commit -m "refactor: unify reaction data layer — individualReactions as source of truth, remove validation, centralized setter"
```

---

### Task 5: Update MessageSendManager optimistic updates for data invariant

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/MessageSendManager.swift`

- [ ] **Step 1: Update addReaction to maintain both representations**

Replace the `addReaction` method body (lines 404-441). The key change: also update `individualReactions` alongside the existing `reactions` mutation, then re-derive `reactions` from `individualReactions`:

```swift
func addReaction(
    messageId: UUID,
    reaction: String,
    messages: [Message],
    setMessages: @escaping @MainActor ([Message]) -> Void,
    setError: @escaping @MainActor (AppError?) -> Void
) async {
    guard let userId = authService.currentUserId else { return }
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

    let previousIndividual = messages[index].individualReactions
    var updated = messages

    // Update via centralized setter (maintains invariant)
    var records = updated[index].individualReactions ?? []
    records.removeAll { $0.userId == userId } // Remove user's old reaction
    records.append(MessageReaction(messageId: messageId, userId: userId, reaction: reaction))
    updated[index].setIndividualReactions(records)
    setMessages(updated)

    do {
        try await reactionService.addReaction(messageId: messageId, userId: userId, reaction: reaction)
    } catch {
        // Rollback via centralized setter
        var rollback = messages
        if let revertIndex = rollback.firstIndex(where: { $0.id == messageId }) {
            rollback[revertIndex].setIndividualReactions(previousIndividual)
            setMessages(rollback)
        }
        setError(AppError.processingError(error.localizedDescription))
    }
}
```

- [ ] **Step 2: Update removeReaction to maintain both representations**

Replace the `removeReaction` method body (lines 443-475):

```swift
func removeReaction(
    messageId: UUID,
    messages: [Message],
    setMessages: @escaping @MainActor ([Message]) -> Void,
    setError: @escaping @MainActor (AppError?) -> Void
) async {
    guard let userId = authService.currentUserId else { return }
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

    let previousIndividual = messages[index].individualReactions
    var updated = messages

    // Update via centralized setter (maintains invariant)
    var records = updated[index].individualReactions ?? []
    records.removeAll { $0.userId == userId }
    updated[index].setIndividualReactions(records)
    setMessages(updated)

    do {
        try await reactionService.removeReaction(messageId: messageId, userId: userId)
    } catch {
        // Rollback via centralized setter
        var rollback = messages
        if let revertIndex = rollback.firstIndex(where: { $0.id == messageId }) {
            rollback[revertIndex].setIndividualReactions(previousIndividual)
            setMessages(rollback)
        }
        setError(AppError.processingError(error.localizedDescription))
    }
}
```

- [ ] **Step 3: Verify the project compiles and tests pass**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS — all data-layer changes are now consistent.

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/ViewModels/MessageSendManager.swift
git commit -m "refactor: update optimistic updates to maintain individualReactions invariant"
```

---

## Chunk 2: TapbackArtwork & RecentReactionsStore

These tasks create the two new utility components needed before the UI tasks.

### Task 6: Rename TapbackGlyph → TapbackArtwork and implement HAHA rendering

**Files:**
- Rename: `NaarsCars/UI/Components/Messaging/TapbackGlyph.swift` → `NaarsCars/UI/Components/Messaging/TapbackArtwork.swift`
- Rename: `NaarsCars/NaarsCarsTests/Features/Messaging/TapbackGlyphTests.swift` → `NaarsCars/NaarsCarsTests/Features/Messaging/TapbackArtworkTests.swift`

- [ ] **Step 1: Write the failing tests**

Rename `TapbackGlyphTests.swift` to `TapbackArtworkTests.swift` in Xcode (or via git mv + project file update). Replace the entire test file content:

```swift
import XCTest
@testable import NaarsCars

final class TapbackArtworkTests: XCTestCase {
    func testIsHahaRecognizesLaughEmoji() {
        XCTAssertTrue(TapbackArtwork.isHaha("😂"))
    }

    func testIsHahaRejectsOtherEmoji() {
        XCTAssertFalse(TapbackArtwork.isHaha("❤️"))
        XCTAssertFalse(TapbackArtwork.isHaha("👍"))
        XCTAssertFalse(TapbackArtwork.isHaha("🔥"))
    }

    func testHahaImageReturnsNonNilAtAllSizes() {
        let sizes: [CGFloat] = [13, 22, 28]
        for size in sizes {
            let image = TapbackArtwork.hahaImage(pointSize: size)
            XCTAssertNotNil(image, "Expected HAHA image at pointSize \(size)")
        }
    }

    func testHahaImageScalesWithPointSize() {
        let small = TapbackArtwork.hahaImage(pointSize: 13)!
        let large = TapbackArtwork.hahaImage(pointSize: 28)!
        XCTAssertGreaterThan(large.size.width, small.size.width)
    }

    func testHahaImageRenderingMode() {
        let image = TapbackArtwork.hahaImage(pointSize: 22)!
        XCTAssertEqual(image.renderingMode, .alwaysOriginal)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/TapbackArtworkTests -quiet 2>&1 | tail -10`

Expected: FAIL — `TapbackArtwork` doesn't exist yet.

- [ ] **Step 3: Implement TapbackArtwork**

Rename `TapbackGlyph.swift` to `TapbackArtwork.swift` in Xcode. Replace its entire content:

```swift
import UIKit

enum TapbackArtwork {
    /// Returns true if this reaction should be rendered as custom "HA HA" artwork instead of emoji.
    static func isHaha(_ reaction: String) -> Bool {
        reaction == "😂"
    }

    /// Renders the custom "HA HA" artwork at the specified point size.
    /// Use `UIGraphicsImageRenderer` with screen scale for crisp rendering on retina displays.
    /// - Parameter pointSize: The desired height of the artwork in points.
    /// - Returns: A tinted image with rendering mode `.alwaysOriginal`.
    static func hahaImage(pointSize: CGFloat) -> UIImage {
        let font = UIFont.systemFont(ofSize: pointSize * 0.45, weight: .black)
        let text = "HA\nHA"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = -pointSize * 0.08
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.systemBlue,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.boundingRect(
            with: CGSize(width: pointSize, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).size

        let canvasSize = CGSize(
            width: ceil(max(textSize.width, pointSize * 0.8)),
            height: ceil(max(textSize.height, pointSize))
        )
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { _ in
            let drawRect = CGRect(
                x: (canvasSize.width - textSize.width) / 2,
                y: (canvasSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            attrString.draw(in: drawRect)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
```

- [ ] **Step 4: Fix all callers of the old TapbackGlyph API**

Search the codebase for `TapbackGlyph` references and update them. Key callers:
- `ReactionBarView.swift:110` — `TapbackGlyph.image(for:pointSize:)` → will be refactored in Task 8
- `ReactionBadgeView.swift:158` — will be deleted in Task 9
- `ReactionDetailsSheet.swift:69` — will be deleted in Task 12

For now, temporarily add a compatibility shim at the bottom of `TapbackArtwork.swift` to keep the project compiling until those files are modified. **Note:** This shim returns `nil` for the 5 non-HAHA reactions that previously had SF Symbol mappings, so `ReactionBadgeView` will temporarily fall back to emoji text for all 6 standard tapbacks. This is a known transient regression — `ReactionBadgeView` is deleted in Task 11.

```swift
// MARK: - Temporary compatibility (remove after Tasks 8, 9, 12)
enum TapbackGlyph {
    static func image(for reaction: String, pointSize: CGFloat) -> UIImage? {
        guard TapbackArtwork.isHaha(reaction) else { return nil }
        return TapbackArtwork.hahaImage(pointSize: pointSize)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/TapbackArtworkTests -quiet 2>&1 | tail -10`

Expected: PASS

- [ ] **Step 6: Verify full project compiles**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS — the compatibility shim keeps old callers working.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: rename TapbackGlyph to TapbackArtwork, implement HAHA custom rendering"
```

---

### Task 7: Create RecentReactionsStore

**Files:**
- Create: `NaarsCars/Core/Storage/RecentReactionsStore.swift`

- [ ] **Step 1: Implement RecentReactionsStore**

```swift
import Foundation

/// Persists the user's recently used emoji reactions via UserDefaults.
/// Maintains an ordered list of up to `maxRecents` emoji, most recent first.
enum RecentReactionsStore {
    private static let key = "com.naarscars.recentReactions"
    private static let maxRecents = 15

    /// Returns the list of recently used emoji, most recent first.
    /// Excludes any emoji that appear in `MessageReaction.standardTapbacks`.
    static var recents: [String] {
        let all = UserDefaults.standard.stringArray(forKey: key) ?? []
        let standard = Set(MessageReaction.standardTapbacks)
        return all.filter { !standard.contains($0) }
    }

    /// Records an emoji as recently used. Moves it to the front if already present.
    /// Standard tapbacks are not recorded (they are always shown in the picker).
    static func record(_ emoji: String) {
        let standard = Set(MessageReaction.standardTapbacks)
        guard !standard.contains(emoji) else { return }

        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == emoji }
        list.insert(emoji, at: 0)
        if list.count > maxRecents {
            list = Array(list.prefix(maxRecents))
        }
        UserDefaults.standard.set(list, forKey: key)
    }
}
```

- [ ] **Step 2: Verify the project compiles**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Core/Storage/RecentReactionsStore.swift
git commit -m "feat: add RecentReactionsStore for tracking recently used emoji reactions"
```

---

## Chunk 3: Picker Bar Refactor

### Task 8: Refactor ReactionBarView

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift`

- [ ] **Step 1: Replace the allReactions array and makeReactionButton method**

Replace the entire `ReactionBarView.swift` content. Key changes:
- Remove `allReactions` (21 hardcoded Unicode escapes)
- Build buttons from `MessageReaction.standardTapbacks` + `RecentReactionsStore.recents`
- HAHA button uses `TapbackArtwork.hahaImage(pointSize:)` with `accessibilityLabel = "Ha ha"`
- All other tapbacks render as emoji `UIButton.setTitle`
- Add a thin vertical divider (1pt, white at 0.2 alpha)
- Add emoji keyboard button (smiley face SF Symbol in a circle)
- Selected state: solid `UIColor.systemBlue`, NO scale transform
- Add hidden `UITextField` for emoji keyboard input

```swift
import UIKit

final class ReactionBarView: UIView {

    // MARK: - Callbacks

    var onReact: ((String) -> Void)?
    var onRemoveReaction: (() -> Void)?

    // MARK: - Configuration

    private let buttonSize: CGFloat = 40
    private let buttonSpacing: CGFloat = 6

    // MARK: - State

    private var currentUserReaction: String?
    private let emojiTextField = EmojiTextField()

    // MARK: - Subviews

    private let blurView: UIVisualEffectView = {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 24
        blur.clipsToBounds = true
        return blur
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceHorizontal = true
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()

    // MARK: - Init

    init(currentUserReaction: String? = nil) {
        self.currentUserReaction = currentUserReaction
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(blurView)
        blurView.contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)

        // Hidden text field for emoji keyboard
        emojiTextField.onEmojiInput = { [weak self] emoji in
            RecentReactionsStore.record(emoji)
            self?.onReact?(emoji)
        }
        emojiTextField.isHidden = true
        addSubview(emojiTextField)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            stackView.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        // Standard tapbacks
        for emoji in MessageReaction.standardTapbacks {
            stackView.addArrangedSubview(makeReactionButton(emoji: emoji))
        }

        // Recent emoji
        let recents = RecentReactionsStore.recents
        if !recents.isEmpty {
            for emoji in recents {
                stackView.addArrangedSubview(makeReactionButton(emoji: emoji))
            }
        }

        // Divider
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: buttonSize - 16),
        ])
        stackView.addArrangedSubview(divider)

        // Emoji keyboard button
        stackView.addArrangedSubview(makeEmojiKeyboardButton())
    }

    // MARK: - Button Factories

    private func makeReactionButton(emoji: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        if TapbackArtwork.isHaha(emoji) {
            let img = TapbackArtwork.hahaImage(pointSize: 22)
            button.setImage(img, for: .normal)
            button.setTitle(nil, for: .normal)
            button.accessibilityLabel = "Ha ha"
        } else {
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 22)
            button.accessibilityLabel = emoji
        }

        button.layer.cornerRadius = buttonSize / 2
        button.clipsToBounds = true

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize),
            button.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        let isSelected = emoji == currentUserReaction
        if isSelected {
            button.backgroundColor = .systemBlue
            button.accessibilityTraits = [.button, .selected]
            button.accessibilityHint = NSLocalizedString("accessibility_reaction_remove_hint", comment: "")
        } else {
            button.accessibilityHint = NSLocalizedString("accessibility_reaction_add_hint", comment: "")
        }
        button.accessibilityIdentifier = "overlay.reaction.\(emoji)"

        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if emoji == self.currentUserReaction {
                self.onRemoveReaction?()
            } else {
                if !MessageReaction.standardTapbacks.contains(emoji) {
                    RecentReactionsStore.record(emoji)
                }
                self.onReact?(emoji)
            }
        }, for: .touchUpInside)

        return button
    }

    private func makeEmojiKeyboardButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.setImage(UIImage(systemName: "face.smiling", withConfiguration: config), for: .normal)
        button.tintColor = UIColor.white.withAlphaComponent(0.6)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = buttonSize / 2
        button.clipsToBounds = true
        button.accessibilityLabel = NSLocalizedString("accessibility_emoji_picker", comment: "Open emoji picker")

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize),
            button.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        button.addAction(UIAction { [weak self] _ in
            self?.emojiTextField.becomeFirstResponder()
        }, for: .touchUpInside)

        return button
    }
}

// MARK: - Hidden emoji text field

/// A zero-frame UITextField that opens the emoji keyboard.
/// Validates input to accept only emoji characters.
private final class EmojiTextField: UITextField, UITextFieldDelegate {

    var onEmojiInput: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: .zero)
        delegate = self
        textContentType = .none
        autocorrectionType = .no
        spellCheckingType = .no
    }

    required init?(coder: NSCoder) { fatalError() }

    override var textInputMode: UITextInputMode? {
        // Prefer emoji keyboard if available
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard !string.isEmpty else { return false }
        for character in string {
            if character.isActualEmoji {
                onEmojiInput?(String(character))
                // Dismiss keyboard after input
                DispatchQueue.main.async { textField.resignFirstResponder() }
                return false
            }
        }
        return false
    }
}
```

- [ ] **Step 2: Verify EmojiDetection API compatibility**

The `EmojiTextField` class uses `character.isActualEmoji`. Confirm this is a `Character` extension property in `NaarsCars/Core/Utilities/EmojiDetection.swift` (it is — defined as `var isActualEmoji: Bool` on `extension Character`). No changes needed.

- [ ] **Step 3: Verify the project compiles**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift
git commit -m "refactor: ReactionBarView to 6 tapbacks + recents + emoji keyboard button"
```

---

## Chunk 4: Sticker Badge View

### Task 9: Create ReactionStickerBadgeView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/ReactionStickerBadgeView.swift`

- [ ] **Step 1: Implement ReactionStickerBadgeView**

This is the core new component — per-person speech-bubble stickers replacing the old aggregated capsule badges. Read the spec Section 3 carefully for all design requirements: speech-bubble shape, color coding, ordering, compact overflow mode, tunable geometry constants.

```swift
import UIKit

/// Per-person reaction sticker badges displayed at the top-trailing corner of a message bubble.
/// Matches iMessage iOS 18 sticker style — each user's reaction is a separate speech-bubble-shaped sticker.
final class ReactionStickerBadgeView: UIView {

    // MARK: - Callbacks

    var onTap: (() -> Void)?

    // MARK: - Tunable Geometry Constants
    // These are initial values — adjust after visual testing across bubble types.

    private let stickerSize: CGFloat = 28
    private let stickerOverlap: CGFloat = 8
    private let majorCornerRadius: CGFloat = 14
    private let tailCornerRadius: CGFloat = 4
    private let maxCompactStickers = 3

    // MARK: - State

    private var stickerViews: [UIView] = []
    private var isCompactMode = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isAccessibilityElement = true
        accessibilityTraits = .button
        // iOS 17+ trait change registration (replaces deprecated traitCollectionDidChange)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ReactionStickerBadgeView, _) in
            view.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configure

    /// Configure with individual reaction records and the current user's ID.
    /// - Parameters:
    ///   - reactions: Individual `MessageReaction` records for this message
    ///   - currentUserId: The logged-in user's ID (used for blue/gray coloring)
    func configure(reactions: [MessageReaction], currentUserId: UUID) {
        // Clear old stickers
        stickerViews.forEach { $0.removeFromSuperview() }
        stickerViews.removeAll()

        // Determine display mode
        let uniqueTypes = Set(reactions.map(\.reaction))
        isCompactMode = uniqueTypes.count > maxCompactStickers

        if isCompactMode {
            configureCompact(reactions: reactions)
        } else {
            configurePerPerson(reactions: reactions, currentUserId: currentUserId)
        }

        updateAccessibilityLabel(reactions: reactions)
        setNeedsLayout()
    }

    // MARK: - Per-Person Mode

    private func configurePerPerson(reactions: [MessageReaction], currentUserId: UUID) {
        // Sort by createdAt ascending, tiebreak by userId
        let sorted = reactions.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.userId.uuidString < $1.userId.uuidString
            }
            return $0.createdAt < $1.createdAt
        }

        for record in sorted {
            let isCurrentUser = record.userId == currentUserId
            let sticker = makeStickerView(emoji: record.reaction, isCurrentUser: isCurrentUser)
            addSubview(sticker)
            stickerViews.append(sticker)
        }
    }

    // MARK: - Compact Overflow Mode

    private func configureCompact(reactions: [MessageReaction]) {
        // Group by reaction type, pick top 3 by count
        var groups: [String: [MessageReaction]] = [:]
        for r in reactions { groups[r.reaction, default: []].append(r) }

        let topGroups = groups.sorted { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
            let lhsEarliest = lhs.value.map(\.createdAt).min() ?? .distantPast
            let rhsEarliest = rhs.value.map(\.createdAt).min() ?? .distantPast
            return lhsEarliest < rhsEarliest
        }.prefix(maxCompactStickers)

        for group in topGroups {
            let sticker = makeStickerView(emoji: group.key, isCurrentUser: false)
            addSubview(sticker)
            stickerViews.append(sticker)
        }
    }

    // MARK: - Sticker Factory

    private func makeStickerView(emoji: String, isCurrentUser: Bool) -> UIView {
        let container = UIView()
        container.backgroundColor = isCurrentUser ? .systemBlue : .systemGray.withAlphaComponent(0.6)
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.25
        container.layer.shadowOffset = CGSize(width: 0, height: 1)
        container.layer.shadowRadius = 2

        if TapbackArtwork.isHaha(emoji) {
            let imageView = UIImageView(image: TapbackArtwork.hahaImage(pointSize: stickerSize * 0.45))
            imageView.contentMode = .scaleAspectFit
            container.addSubview(imageView)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: stickerSize * 0.6),
                imageView.heightAnchor.constraint(equalToConstant: stickerSize * 0.6),
            ])
        } else {
            let label = UILabel()
            label.text = emoji
            label.font = .systemFont(ofSize: stickerSize * 0.55)
            label.textAlignment = .center
            container.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }

        return container
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        for (index, sticker) in stickerViews.enumerated() {
            sticker.frame = CGRect(x: x, y: 0, width: stickerSize, height: stickerSize)
            applySpeechBubbleMask(to: sticker)
            sticker.layer.zPosition = CGFloat(index) // Newest (last) on top
            x += stickerSize - stickerOverlap
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard !stickerViews.isEmpty else { return .zero }
        let count = CGFloat(stickerViews.count)
        let width = stickerSize + (count - 1) * (stickerSize - stickerOverlap)
        return CGSize(width: width, height: stickerSize)
    }

    // MARK: - Speech Bubble Mask

    private func applySpeechBubbleMask(to view: UIView) {
        let rect = CGRect(origin: .zero, size: CGSize(width: stickerSize, height: stickerSize))
        let path = UIBezierPath()
        let major = majorCornerRadius
        let tail = tailCornerRadius

        // Top-left (major)
        path.move(to: CGPoint(x: major, y: 0))
        // Top-right (major)
        path.addLine(to: CGPoint(x: rect.maxX - major, y: 0))
        path.addArc(withCenter: CGPoint(x: rect.maxX - major, y: major), radius: major, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        // Bottom-right (major)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - major))
        path.addArc(withCenter: CGPoint(x: rect.maxX - major, y: rect.maxY - major), radius: major, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        // Bottom-left (tail — small radius)
        path.addLine(to: CGPoint(x: tail, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: tail, y: rect.maxY - tail), radius: tail, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        // Back to top-left
        path.addLine(to: CGPoint(x: 0, y: major))
        path.addArc(withCenter: CGPoint(x: major, y: major), radius: major, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        path.close()

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        view.layer.mask = mask
    }

    // MARK: - Interaction

    @objc private func handleTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap?()
    }

    // MARK: - Reuse

    func prepareForReuse() {
        stickerViews.forEach { $0.removeFromSuperview() }
        stickerViews.removeAll()
        onTap = nil
    }

    // MARK: - Accessibility

    private func updateAccessibilityLabel(reactions: [MessageReaction]) {
        let count = reactions.count
        let uniqueTypes = Set(reactions.map { r in
            TapbackArtwork.isHaha(r.reaction) ? "Ha ha" : r.reaction
        })
        let typeList = uniqueTypes.sorted().joined(separator: ", ")
        accessibilityLabel = "\(count) \(count == 1 ? "reaction" : "reactions"): \(typeList)"
    }

}
```

- [ ] **Step 2: Verify the project compiles**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS — the new view exists but is not wired up yet.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/ReactionStickerBadgeView.swift
git commit -m "feat: add ReactionStickerBadgeView — per-person iMessage-style sticker badges"
```

---

### Task 10: Wire ReactionStickerBadgeView into MessageCellView

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift`

- [ ] **Step 1: Replace reactionBadge with reactionStickerBadge**

In `MessageCellView.swift`:
1. Change the property declaration (line 27): `private var reactionBadge: ReactionBadgeView?` → `private var reactionStickerBadge: ReactionStickerBadgeView?`
2. Update `configure()` (around line 288): replace `ReactionBadgeView` instantiation with `ReactionStickerBadgeView`, pass `individualReactions` and `currentUserId` instead of aggregated `MessageReactions`
3. Update `layoutSubviews()` (around line 516): rename `reactionBadge` → `reactionStickerBadge`, keep the same positioning logic
4. Update `hideAllContent()` (line 447): rename reference
5. Update `sizeThatFits()` (line 653): rename reference
6. Update `prepareForReuse()` (line 785): rename reference
7. Update accessibility elements (line 120): rename reference

For the configure block, the new code should look like:

```swift
if let individualReactions = msg.individualReactions, !individualReactions.isEmpty {
    let badge = reactionStickerBadge ?? {
        let v = ReactionStickerBadgeView()
        addSubview(v)
        reactionStickerBadge = v
        return v
    }()
    badge.isHidden = false
    // AuthService.shared.currentUserId is already used in this file (line 299) for reaction tap handling
    let currentUserId = AuthService.shared.currentUserId ?? UUID()
    badge.configure(reactions: individualReactions, currentUserId: currentUserId)
    badge.onTap = { [weak self] in
        guard let self else { return }
        self.delegate?.messageCellDidTapReactionBadge?(self, message: config.message)
    }
} else {
    reactionStickerBadge?.isHidden = true
}
```

Note: You will need to pass `currentUserId` through from the configuration. Check how the existing code accesses the current user (likely via `config.isFromCurrentUser` or through the delegate). Add a `currentUserId: UUID` field to `MessageCellConfig` if one doesn't already exist.

- [ ] **Step 2: Add messageCellDidTapReactionBadge to the delegate protocol**

In `NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift`, find the `MessageCellDelegate` protocol (line 25) and add the new method. Since this is a plain Swift protocol (not `@objc`), add it as a required method with a default empty implementation via extension:

```swift
// Add to the protocol body (after line 32):
func messageCellDidTapReactionBadge(_ cell: MessageCellView, message: Message)
```

Then add a default implementation below the protocol so existing conformers don't break:

```swift
extension MessageCellDelegate {
    func messageCellDidTapReactionBadge(_ cell: MessageCellView, message: Message) {}
}
```

- [ ] **Step 3: Search for any remaining reactionBadge references outside MessageCellView**

Search the codebase for `reactionBadge` — all references should now be replaced. `MessagesCollectionView.swift` does not reference it directly (verified), but check `MessageThreadViewController.swift` and any other files. Fix any remaining references.

- [ ] **Step 4: Verify the project compiles**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift
git commit -m "feat: wire ReactionStickerBadgeView into MessageCellView"
```

---

### Task 11: Delete ReactionBadgeView

**Files:**
- Delete: `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift`

- [ ] **Step 1: Delete the file**

Remove `ReactionBadgeView.swift` from the Xcode project and filesystem.

- [ ] **Step 2: Verify no remaining references**

Search for `ReactionBadgeView` across the codebase. All references should have been replaced in Task 10. Fix any remaining ones.

- [ ] **Step 3: Verify the project compiles**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete ReactionBadgeView, replaced by ReactionStickerBadgeView"
```

---

## Chunk 5: Inline Reaction Details & Overlay Integration

### Task 12: Create ReactionDetailsRowView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Overlay/ReactionDetailsRowView.swift`

- [ ] **Step 1: Implement ReactionDetailsRowView**

Build the horizontal scrollable row that shows each reaction as a large sticker with user avatar below. Read spec Section 4 for ordering rules: groups by count descending, avatars by createdAt ascending.

**Required public API:**

```swift
final class ReactionDetailsRowView: UIView {
    /// Called when the user taps their own reaction to remove it.
    /// The String is the reaction emoji being removed.
    var onRemoveReaction: ((String) -> Void)?

    /// Configure the details row with reaction data.
    /// - Parameters:
    ///   - reactions: Individual `MessageReaction` records for this message
    ///   - profiles: Profile data keyed by userId for avatar rendering
    ///   - currentUserId: The logged-in user's ID (used to identify removable reactions)
    func configure(reactions: [MessageReaction], profiles: [UUID: Profile], currentUserId: UUID)

    func prepareForReuse()
}
```

**Implementation requirements:**
- Horizontal `UIScrollView` containing `UIStackView`
- Each item: vertical stack with ~50pt speech-bubble sticker (using same `applySpeechBubbleMask` shape as `ReactionStickerBadgeView`) + ~24pt avatar circle
- Grouped by reaction type (count descending, ties by earliest createdAt), avatars ordered by createdAt ascending within each group
- If multiple users reacted with the same emoji, their avatar circles overlap below the single sticker
- Dark blur background (`systemUltraThinMaterial`) with 16pt corner radius
- Tap on own reaction triggers `onRemoveReaction` callback with the reaction emoji
- HAHA stickers: `accessibilityLabel = "Ha ha"`
- All geometry values (sticker size, avatar size, spacing) as named constants

- [ ] **Step 2: Verify the project compiles**

Expected: PASS — new file, not yet wired.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/ReactionDetailsRowView.swift
git commit -m "feat: add ReactionDetailsRowView — inline reaction details for overlay"
```

---

### Task 13: Integrate ReactionDetailsRowView into MessageOverlayController

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift`

- [ ] **Step 1: Add ReactionDetailsRowView and showDetails flag**

1. Add a `showDetails: Bool` parameter to `MessageOverlayController.init`
2. Add `individualReactions: [MessageReaction]`, `reactionProfiles: [UUID: Profile]`, and `currentUserId: UUID` parameters
3. Create and add `ReactionDetailsRowView` as a subview
4. Position it between the reaction bar and the message snapshot in the layout
5. Configure the details row with the reaction data
6. Animate it in with the same entrance animation (0.3s, damping 0.85, ±10pt offset)
7. Wire the details row's remove-reaction callback to the overlay's `onAction`

- [ ] **Step 2: Update the overlay layout to accommodate the details row**

Adjust the Y-position calculation in the layout code. The details row sits between the picker bar and the snapshot. If there are reactions, the layout should be:
- Picker bar top Y
- Details row Y = picker bar bottom + 8pt spacing
- Snapshot Y = details row bottom + 8pt spacing (or picker bar bottom + 8pt if no reactions)

- [ ] **Step 3: Verify the project compiles**

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift
git commit -m "feat: integrate ReactionDetailsRowView into MessageOverlayController"
```

---

### Task 14: Wire badge-tap and update MessagesViewController

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewController.swift`
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

- [ ] **Step 1: Add profile-fetching to ConversationDetailViewModel**

Move the `refreshReactionProfiles(for:)` logic from `ConversationDetailView` into the ViewModel. The data shape intentionally changes: the old method produced `[String: [Profile]]` (grouped by reaction type for the sheet's section headers), but the new `ReactionDetailsRowView` renders per-user avatars, so it needs `[UUID: Profile]` (keyed by userId). Add a method like:

```swift
func fetchReactionProfiles(for message: Message) async -> [UUID: Profile] {
    // Fetch profiles for all unique userIds in message.individualReactions
    // Return as [UUID: Profile] dictionary
}
```

- [ ] **Step 2: Handle messageCellDidTapReactionBadge in MessagesViewController**

Implement the new delegate method to present the overlay with `showDetails: true`:

```swift
func messageCellDidTapReactionBadge(_ cell: MessageCellView, message: Message) {
    // Create snapshot, get frame, fetch profiles
    // Present MessageOverlayController with showDetails: true
    // Pass individualReactions, profiles, currentUserId
}
```

- [ ] **Step 3: Verify the project compiles**

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessagesViewController.swift NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift
git commit -m "feat: wire badge-tap to overlay with inline reaction details"
```

---

### Task 15: Clean up ConversationDetailView and delete ReactionDetailsSheet

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift`
- Delete: `NaarsCars/Features/Messaging/Views/ReactionDetailsSheet.swift`

- [ ] **Step 1: Remove reaction details state from ConversationDetailView**

In `ConversationDetailView.swift`:
1. Delete `@State private var showReactionDetails = false` (line 29)
2. Delete `@State private var reactionDetailsMessage: Message?` (line 30)
3. Delete `@State private var reactionProfiles: [String: [Profile]]` (line 31)
4. Delete the `.sheet(isPresented: $showReactionDetails)` modifier
5. Delete the `reactionDetailsContent` computed property
6. Delete the `refreshReactionProfiles(for:)` method
7. Remove the `"__details__"` sentinel handling in `onReactionTap` (line 379). Badge taps now go through the overlay flow directly.

- [ ] **Step 1b: Remove `"__details__"` sentinel from MessageCellView**

In `MessageCellView.swift` (line 309), the `onReactionLongPress` callback sends `"__details__"`. This entire callback is no longer needed — badge taps now go directly through `messageCellDidTapReactionBadge`. Remove the `onReactionLongPress` wiring.

- [ ] **Step 1c: Search entire codebase for remaining `"__details__"` references**

Search for `"__details__"` across all `.swift` files. Remove any remaining live code references. (Doc/plan files can be left as-is — they are historical.)

- [ ] **Step 2: Update MessagesViewControllerRepresentable if needed**

Check if the `onReactionTap` callback signature changed. Update wiring accordingly.

- [ ] **Step 3: Delete ReactionDetailsSheet.swift**

Remove the file from the Xcode project and filesystem.

- [ ] **Step 4: Verify the project compiles**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove ReactionDetailsSheet and details state from ConversationDetailView"
```

---

## Chunk 6: Cleanup & Verification

### Task 16: Remove TapbackGlyph compatibility shim

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/TapbackArtwork.swift`

- [ ] **Step 1: Remove the TapbackGlyph compatibility enum**

Delete the `// MARK: - Temporary compatibility` section from the bottom of `TapbackArtwork.swift`.

- [ ] **Step 2: Search for any remaining TapbackGlyph references**

Run a codebase search for `TapbackGlyph`. There should be zero results. Fix any remaining references.

- [ ] **Step 3: Verify the project compiles and tests pass**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/TapbackArtwork.swift
git commit -m "chore: remove TapbackGlyph compatibility shim"
```

---

### Task 17: Full verification pass

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 2: Walk through the verification checklist**

Open the spec at `Docs/superpowers/specs/2026-03-14-imessage-reaction-sticker-parity-design.md` and manually verify each item in the Verification Checklist section. For items requiring visual inspection (badge rendering across bubble types, dark/light mode, HAHA crispness), run the app in the simulator and test manually.

- [ ] **Step 3: Test in thread view context (required — not optional)**

Navigate to a message thread (`MessageThreadViewController`) in the app. Verify:
1. Reaction sticker badges render correctly on thread messages
2. Badge tap opens the overlay with inline reaction details
3. Remove-own-reaction from inline details works in thread context
4. Realtime updates from other users update badges in thread view

- [ ] **Step 4: Verify accessibility**

Using Xcode Accessibility Inspector or VoiceOver:
1. HAHA artwork reads "Ha ha" in picker, badge, and details row
2. Sticker badge reads descriptive label (e.g., "2 reactions: heart, thumbs up")
3. Selected picker reaction exposes `.selected` trait
4. Emoji keyboard button is labeled for VoiceOver

- [ ] **Step 5: Commit any final fixes**

If any issues were found and fixed during verification:

```bash
git add -A
git commit -m "fix: address issues found during verification pass"
```
