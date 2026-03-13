# Messaging Polish & Input Consolidation — Design Spec

**Date**: 2026-03-13
**Goal**: Fix the four remaining messaging audit issues (input bar duplication, `hasLeftConversation` dead state, location sentinel hack, system message icon matching) and eliminate the app-wide first-focus text input hitch via UIKit text subsystem prewarming.

---

## Problem

Five issues remain after the UIKit messaging migration:

1. **First-focus text input hitch** — The first time any SwiftUI `TextField` becomes first responder in a fresh process, UIKit's text interaction infrastructure (`UITextInteraction`, `UITextInputController`, autocorrect, etc.) is lazily initialized. This blocks the main thread for several hundred milliseconds. Affects every text field in the app: sign-in, messaging, forms.

2. **Dual input bar implementations** — `MessageInputBar` (SwiftUI, 774 lines, thread view) and `MessageInputAccessoryView` (UIKit, 800+ lines, main conversation) duplicate ~60% of their logic: text management, reply/edit context, audio recording, attachment processing, typing throttle. Changes to one are forgotten in the other.

3. **`hasLeftConversation` dead state** — `ConversationDetailViewModel` sets this `@Published` property but no view reads it. Users who have left a group conversation can still see the input bar and potentially attempt to send messages.

4. **Location sentinel hack** — The location button calls `delegate?.inputBar(self, didShareLocation: 0, lon: 0, name: nil)` using `(0, 0)` as a sentinel to mean "show the picker." The delegate ignores coordinates entirely.

5. **System message icon text matching** — `SystemMessageView.iconName(for:)` matches lowercased English substrings (`"added"`, `"left"`, `"name"`) in message text to select icons. No structured `systemAction` field exists.

---

## Fix 1: Text Input Prewarming

### Approach

In `AppDelegate.application(_:didFinishLaunchingWithOptions:)`, force-initialize UIKit's text interaction subsystem by creating an offscreen `UITextField`, making it first responder, then immediately resigning and discarding it. This runs once at launch and eliminates the hitch for every text field in the app.

### Implementation

```swift
// AppDelegate.swift — called from didFinishLaunchingWithOptions, before returning true
private func prewarmTextInput() {
    let offscreenWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    offscreenWindow.windowLevel = UIWindow.Level(rawValue: -1)
    let vc = UIViewController()
    offscreenWindow.rootViewController = vc
    offscreenWindow.isHidden = false

    let field = UITextField(frame: .zero)
    vc.view.addSubview(field)
    field.becomeFirstResponder()
    field.resignFirstResponder()
    field.removeFromSuperview()

    offscreenWindow.isHidden = true
    // offscreenWindow deallocates naturally when it falls out of scope
}
```

Note: Uses `windowLevel = -1` to keep the prewarming window below the app's actual UI. Does not call `makeKeyAndVisible()` to avoid interfering with the real key window.

### Files Modified

- `NaarsCars/App/AppDelegate.swift` — add `prewarmTextInput()` call

---

## Fix 2: InputBarController + View Layer Consolidation

### Why `@Observable` instead of `ObservableObject`

AGENTS.md specifies `ObservableObject` for ViewModels. `InputBarController` is not a ViewModel — it lives in `UI/Components/Messaging/`, not `Features/*/ViewModels/`, and it does not manage screen-level data loading, navigation, or service orchestration. It is a UI component controller: a shared state/coordination layer consumed by two view implementations.

`@Observable` is chosen because:
- SwiftUI gets per-property tracking. Reading `isRecording` doesn't invalidate the view when `currentText` changes. This is the primary mechanism for reducing first-focus view compilation cost.
- The UIKit `MessageInputAccessoryView` consumes it imperatively (calling methods, reading properties) and uses `withObservationTracking` sparingly — only for 3 reactive properties.

For the UIKit observation bridge, use the re-registration pattern established in `ConversationDetailViewModel.observeTypingUsers()` (line 271): `withObservationTracking` fires its `onChange` callback exactly once, then must be re-registered via `Task { @MainActor in self?.observe...() }`.

### Architecture

```
InputBarController (@Observable, @MainActor)
├── Text: currentText (private(set), single mutation path via updateText(_:))
├── Mode: .normal / .replying(ReplyContext) / .editing(messageId, originalText)
├── Attachment: pendingAttachment (InputAttachment?, generation-counted async compression)
├── Recording: delegates to AudioRecordingCoordinator
├── Computed: isSendable (accounts for text, attachment, recorded audio)
│
├── Actions: send(), updateText(), setReplyContext(), cancelReply(),
│            startEditing(), cancelEditing(), setImage(), clearAttachment(),
│            startRecording(), stopRecording(), cancelRecording()
│
├── Callbacks: onSend(SendPayload), onAudioRecorded(URL, Double),
│              onImagePickerRequested, onCameraRequested,
│              onLocationPickerRequested, onTypingChanged
│
└── Delegates to:
    ├── AudioRecordingCoordinator (AVAudioRecorder lifecycle, waveform, file)
    └── Task.detached for image compression (generation-guarded)
```

### Key Design Decisions

- **Single text mutation path** — `updateText(_:)` is the only way to change `currentText`. Handles typing notification internally.
- **Single attachment representation** — `InputAttachment` holds both `UIImage` (for preview) and `Data` (compressed, for send). No parallel state.
- **`SendPayload`** — rich struct carries text, attachment, reply context, and edit message ID together. Consumers don't query controller mode to infer send type.
- **Generation counter** on attachment processing — stale compressions are discarded on reuse/clear.
- **Callbacks, not delegate** — simpler to wire from both SwiftUI closures and UIKit without protocol conformance mismatch.

### SendPayload

```swift
struct SendPayload {
    let text: String
    let attachment: InputAttachment?
    let replyContext: ReplyContext?
    let editMessageId: UUID?
}

struct InputAttachment: Equatable {
    let image: UIImage
    let data: Data
}
```

### AudioRecordingCoordinator

Extracted from both existing implementations. Owns `AVAudioRecorder`, waveform sampling timer, and recorded file URL. Exposes `isRecording`, `duration`, `waveformSamples`, `hasRecordedFile`. Returns `(url: URL, duration: TimeInterval)` on `stop()`.

### View Layer Changes

**SwiftUI `MessageInputBar` (thread view)** — shrinks from 774 lines to ~200 lines. Becomes a rendering shell:
- Reads `@Observable` controller properties for display
- Owns only `@FocusState` and layout/animation state
- Calls controller actions on user interaction
- Does NOT own audio recording, image compression, typing throttle, or context management

**UIKit `MessageInputAccessoryView` (main conversation)** — refactored to use controller:
- Owns an `InputBarController` instance
- `UITextViewDelegate` calls `controller.updateText()`
- Button targets call `controller.send()`, `controller.startRecording()`, etc.
- Uses `withObservationTracking` with re-registration (see `observeTypingUsers()` pattern) for 3 reactive properties: `isSendable`, `mode`, `pendingAttachment`
- Keyboard/layout unchanged

### Location Picker in Thread View

Currently the SwiftUI `MessageInputBar` owns `@State private var showLocationPicker` and presents a `.sheet`. After consolidation, the controller provides `onLocationPickerRequested` callback. In the thread view, `MessageThreadViewController` sets this callback to present a `LocationPickerSheet` via `UIHostingController`, matching the pattern already used for image picker presentation. The SwiftUI `MessageInputBar` no longer owns the sheet.

### Wiring

```
MessagesViewController
├── owns InputBarController
├── sets callbacks (onSend, onAudioRecorded, onLocationPickerRequested, etc.)
├── passes controller to MessageInputAccessoryView
└── callbacks route to MessagesViewControllerRepresentable → ConversationDetailView

MessageThreadViewController
├── owns InputBarController
├── sets callbacks (including onLocationPickerRequested → presents LocationPickerSheet)
├── passes controller to MessageInputBar (SwiftUI via UIHostingController)
└── callbacks route to ConversationDetailViewModel
```

### Files Created

- `NaarsCars/UI/Components/Messaging/InputBarController.swift`
- `NaarsCars/UI/Components/Messaging/AudioRecordingCoordinator.swift`

**Xcode project note:** These new files must be added to the Xcode project manually (File → Add Files to "NaarsCars"… or drag into the `UI/Components/Messaging` group). Per AGENTS.md, `project.pbxproj` is not edited to add new files.

### Files Modified

- `NaarsCars/UI/Components/Messaging/MessageInputBar.swift` — major rewrite (thin shell)
- `NaarsCars/UI/Components/Messaging/MessageInputAccessoryView.swift` — refactor to use controller, remove `didShareLocation` from delegate protocol
- `NaarsCars/Features/Messaging/Views/MessagesViewController.swift` — wire controller
- `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift` — wire controller, present LocationPickerSheet
- `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift` — remove `inputBar(_:didShareLocation:)` conformance

---

## Fix 3: `hasLeftConversation` Frozen UI

### UI Changes

**ConversationDetailView** — when `viewModel.hasLeftConversation` is true, replace only the composer/input area with `FrozenConversationBanner`. The message history remains visible and scrollable.

```swift
// In ConversationDetailView, where the input bar area is rendered:
if viewModel.hasLeftConversation {
    FrozenConversationBanner()
} else {
    // existing input bar / MessagesViewControllerRepresentable
}
```

**FrozenConversationBanner** — simple SwiftUI view: lock icon + localized text "You left this conversation". Non-interactive. ~30 lines. Must include `isAccessibilityElement = true` with `accessibilityLabel` set to the localized text so VoiceOver users understand the conversation state.

**Xcode project note:** `FrozenConversationBanner.swift` must be added to the Xcode project manually.

**OverlayActionListView** — add `isConversationFrozen: Bool` parameter to `init`. When frozen:
- **Hide:** Reply, Edit, Undo Send (participation/mutation actions). React is also suppressed (reaction bar hidden by overlay controller).
- **Keep:** Copy, Delete for Me, Report, View Thread (read-only, moderation, or local-only actions)

Report stays because users should be able to report messages after leaving. View Thread stays because threads are read-only navigation — the thread view itself also shows `FrozenConversationBanner` instead of an input bar.

**MessageOverlayController** — add `isConversationFrozen: Bool` to its `init`. Pass to `OverlayActionListView` and conditionally hide `ReactionBarView` when frozen.

### Frozen Flag Propagation

The full call chain for the frozen flag:

1. `ConversationDetailViewModel.hasLeftConversation` (`@Published`, already exists)
2. `ConversationDetailView` reads it for the banner conditional
3. `MessagesViewControllerRepresentable` passes it as a configuration property
4. `MessagesViewController` stores it in its configuration
5. `MessagesViewController.messageCellDidLongPress` passes it to `MessageOverlayController(... isConversationFrozen:)`
6. `MessageOverlayController.init` passes it to `OverlayActionListView(... isConversationFrozen:)` and uses it to hide `ReactionBarView`

### Lower-Level Guard

Add guards in `ConversationDetailViewModel` that reject mutation operations when `hasLeftConversation` is true. `ConversationDetailViewModel` already owns `hasLeftConversation` and is the entry point for all these operations. The guard is placed in the following methods:

- `sendMessage()` / `sendTextMessage()`
- `sendAudioMessage()`
- `sendLocationMessage()`
- `editMessage()`
- `addReaction()`
- `removeReaction()`
- `unsendMessage()`

```swift
// At the top of each mutation method in ConversationDetailViewModel:
guard !hasLeftConversation else { return }
```

`MessageSendManager` is not modified — it has no knowledge of conversation membership and doesn't need it. The guard lives at the ViewModel layer where the state already exists.

### Thread View

`MessageThreadViewController` receives `hasLeftConversation` (passed via `MessageThreadRepresentable`) and shows `FrozenConversationBanner` (embedded via `UIHostingController`) instead of the input bar when true. Thread messages remain readable.

### Files Created

- `NaarsCars/UI/Components/Messaging/FrozenConversationBanner.swift` (~30 lines)

### Files Modified

- `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` — conditional on `hasLeftConversation`
- `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift` — add `isConversationFrozen` parameter to init, filter actions in `buildActions`
- `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift` — add `isConversationFrozen` to init, pass to action list, hide reaction bar when frozen
- `NaarsCars/Features/Messaging/Views/MessagesViewController.swift` — pass frozen flag through to overlay
- `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift` — pass frozen flag from SwiftUI to VC configuration
- `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift` — show frozen banner when left
- `NaarsCars/Features/Messaging/Views/MessageThreadRepresentable.swift` — pass `hasLeftConversation`
- `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift` — add guards to 7 mutation methods

### Localization

- Add `"messaging_left_conversation"` → "You left this conversation"

---

## Fix 4: Location Sentinel Removal

### Approach

With the `InputBarController` refactor (Fix 2), the location sentinel disappears naturally. The controller provides:

```swift
var onLocationPickerRequested: (() -> Void)?
```

The location button action becomes `controller.onLocationPickerRequested?()` — no delegate method, no sentinel coordinates, no protocol change. The old `inputBar(_:didShareLocation:lon:name:)` delegate method is removed entirely.

The actual location send (after the user picks a location in the picker) goes through `ConversationDetailViewModel.sendLocationMessage()` directly, which is already the current flow — the picker sheet calls the ViewModel, not the input bar.

### Files Modified

Absorbed into Fix 2. No additional files beyond those already listed:
- `MessageInputAccessoryView.swift` — remove `didShareLocation` from delegate protocol
- `MessagesViewControllerRepresentable.swift` — remove `inputBar(_:didShareLocation:)` conformance

### Net Change

Delete ~10 lines, add 0 lines.

---

## Fix 5: SystemAction Enum for Icon Selection

### Model Changes

Add to `Message.swift`:

```swift
enum SystemAction: String, Codable, Sendable {
    case memberAdded = "member_added"
    case memberRemoved = "member_removed"
    case memberLeft = "member_left"
    case groupCreated = "group_created"
    case groupNameChanged = "group_name_changed"
    case groupAvatarChanged = "group_avatar_changed"
    case unknown

    /// Decode gracefully — unrecognized server values map to .unknown
    /// instead of failing the entire Message decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = SystemAction(rawValue: raw) ?? .unknown
    }
}
```

Add to `Message` struct:

```swift
/// Server-provided system action type (nil for non-system messages or older messages)
let systemAction: SystemAction?
```

With `CodingKeys` mapping to `system_action`. Decodes as `nil` if the server doesn't send it.

### Backward Compatibility

Computed fallback for messages without server-provided `systemAction`:

```swift
/// Best-effort inference for messages without a server-provided systemAction.
/// Uses case-insensitive English text matching. Will become unnecessary
/// once the server populates system_action for all system messages.
var resolvedSystemAction: SystemAction {
    if let systemAction { return systemAction }
    guard messageType == .system else { return .unknown }
    let lower = text.lowercased()
    if lower.contains("added") || lower.contains("joined") { return .memberAdded }
    if lower.contains("left") { return .memberLeft }
    if lower.contains("removed") { return .memberRemoved }
    if lower.contains("name") { return .groupNameChanged }
    if lower.contains("photo") || lower.contains("image") || lower.contains("avatar") { return .groupAvatarChanged }
    if lower.contains("created") { return .groupCreated }
    return .unknown
}
```

Note: The `groupAvatarChanged` fallback matches `"photo"`, `"image"`, and `"avatar"` to maintain backward compatibility with the existing text matching in `SystemMessageView`.

### SystemMessageView Changes

```swift
func configure(text: String, action: SystemAction) {
    textLabel.text = text
    iconView.image = UIImage(systemName: Self.iconName(for: action))
    // ...accessibility unchanged...
}

private static func iconName(for action: SystemAction) -> String {
    switch action {
    case .memberAdded: return "person.badge.plus"
    case .memberRemoved, .memberLeft: return "person.badge.minus"
    case .groupNameChanged: return "pencil"
    case .groupAvatarChanged: return "photo"
    case .groupCreated: return "sparkles"
    case .unknown: return "info.circle"
    }
}
```

### MessageCellView Change

```swift
private func showSystem(msg: Message) {
    // ...
    view.configure(text: msg.text, action: msg.resolvedSystemAction)
}
```

### Migration Path

The text-matching fallback in `resolvedSystemAction` stays until the server populates `system_action`. Once it does, `resolvedSystemAction` prefers the server value and the fallback becomes dead code that can be removed.

### Files Modified

- `NaarsCars/Core/Models/Message.swift` — add `SystemAction` enum, `systemAction` property, `resolvedSystemAction` computed, `CodingKeys` entry
- `NaarsCars/UI/Components/Messaging/Cells/SystemMessageView.swift` — accept `SystemAction`, switch-based icon selection
- `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift` — pass `msg.resolvedSystemAction`

---

## Summary

| Fix | New Files | Modified Files | Key Risk |
|-----|-----------|----------------|----------|
| 1. Text input prewarming | 0 | 1 | Low — standard UIKit technique |
| 2. InputBarController + consolidation + location sentinel | 2 | 5 | Medium — major refactor of two 700+ line files |
| 3. `hasLeftConversation` frozen UI | 1 | 8 | Low — wiring existing state to views |
| 5. SystemAction enum | 0 | 3 | Low — additive model change with fallback |

**Unique files touched:** 3 new, 14 modified (some files appear in multiple fixes: `MessagesViewController`, `MessageThreadViewController`, `MessagesViewControllerRepresentable`).

Net code reduction from input bar consolidation (774-line SwiftUI view → ~200 lines, shared logic centralized).

---

## Dependencies

- Fix 4 (location sentinel) is absorbed into Fix 2 (InputBarController). They ship together.
- Fix 3 (`hasLeftConversation`) depends on Fix 2 for the frozen banner placement in the thread view but can be implemented after Fix 2 with minimal coupling.
- Fixes 1 and 5 are fully independent.
