# Messaging Polish & Input Consolidation — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix five remaining messaging issues — text input prewarming, input bar consolidation, `hasLeftConversation` frozen UI, location sentinel removal, and SystemAction enum — to reach messaging ship readiness.

**Architecture:** Extract shared input bar logic into an `@Observable` `InputBarController` consumed by both SwiftUI (thread view) and UIKit (main conversation) shells. Add text subsystem prewarming at app launch. Wire the existing `hasLeftConversation` state to freeze conversation UI. Replace text-based system message classification with a typed `SystemAction` enum. Location sentinel hack is eliminated as a side effect of the controller extraction.

**Tech Stack:** Swift, UIKit, SwiftUI, Observation framework (`@Observable`), AVFoundation (audio recording), Combine (typing throttle bridge)

**Spec:** `Docs/superpowers/specs/2026-03-13-messaging-polish-and-input-consolidation-design.md`

**Note:** Per AGENTS.md, tests are not added unless explicitly requested. Build verification via `xcodebuild` is used instead.

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `NaarsCars/UI/Components/Messaging/InputBarController.swift` | `@Observable` shared state for text, mode, attachments, recording coordination, callbacks |
| `NaarsCars/UI/Components/Messaging/AudioRecordingCoordinator.swift` | `AVAudioRecorder` lifecycle, recording duration timer, file management |
| `NaarsCars/UI/Components/Messaging/FrozenConversationBanner.swift` | SwiftUI banner shown when user has left conversation |

### Modified Files

| File | What Changes |
|------|-------------|
| `NaarsCars/App/AppDelegate.swift` | Add `prewarmTextInput()` call in `didFinishLaunchingWithOptions` |
| `NaarsCars/UI/Components/Messaging/MessageInputBar.swift` | Major rewrite — thin rendering shell over `InputBarController` |
| `NaarsCars/UI/Components/Messaging/MessageInputAccessoryView.swift` | Refactor to use `InputBarController`, remove `didShareLocation` from delegate |
| `NaarsCars/Features/Messaging/Views/MessagesViewController.swift` | Own `InputBarController`, pass frozen flag to overlay |
| `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift` | Own `InputBarController`, present location picker, show frozen banner |
| `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift` | Remove `didShareLocation` conformance, pass frozen flag |
| `NaarsCars/Features/Messaging/Views/MessageThreadRepresentable.swift` | Pass `hasLeftConversation` to thread VC |
| `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` | Conditional frozen banner, pass frozen flag to representable |
| `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift` | Add `isConversationFrozen` parameter, filter participation actions |
| `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift` | Add `isConversationFrozen`, hide reaction bar when frozen |
| `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift` | Add frozen guards to 7 mutation methods |
| `NaarsCars/Core/Utilities/AppError.swift` | Add `.conversationFrozen` case |
| `NaarsCars/Core/Models/Message.swift` | Add `SystemAction` enum, `systemAction` property, `resolvedSystemAction` |
| `NaarsCars/UI/Components/Messaging/Cells/SystemMessageView.swift` | Accept `SystemAction`, switch-based icon selection |
| `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift` | Pass `msg.resolvedSystemAction` to SystemMessageView |
| `NaarsCars/Resources/Localizable.xcstrings` | Add localization keys |

---

## Chunk 1: Independent Fixes (Prewarming + SystemAction)

These two fixes have zero dependencies on other chunks. They can be implemented and committed independently.

### Task 1: Text Input Prewarming

**Files:**
- Modify: `NaarsCars/App/AppDelegate.swift:16-48`

- [ ] **Step 1: Add prewarmTextInput method**

Add after the existing private methods in `AppDelegate.swift`:

```swift
/// Force-initialize UIKit's text interaction subsystem at launch.
/// This eliminates the multi-hundred-millisecond hitch on first text field focus
/// caused by lazy initialization of UITextInteraction infrastructure.
/// Runs once, synchronously, on the main thread.
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
}
```

- [ ] **Step 2: Call prewarmTextInput in didFinishLaunchingWithOptions**

Insert the call after `setupMetricKitIfNeeded()` (around line 36), before the DEBUG block:

```swift
prewarmTextInput()
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/App/AppDelegate.swift
git commit -m "perf: prewarm UIKit text input subsystem at launch to eliminate first-focus hitch"
```

---

### Task 2: Add SystemAction Enum to Message Model

**Files:**
- Modify: `NaarsCars/Core/Models/Message.swift:42-49` (after MessageType enum)
- Modify: `NaarsCars/Core/Models/Message.swift:173-194` (CodingKeys)
- Modify: `NaarsCars/Core/Models/Message.swift:198-248` (convenience init)

- [ ] **Step 1: Add SystemAction enum**

Add after the `MessageType` enum (after line 49), before `MessageSendStatus`:

```swift
/// Structured system message action type. Decoded from server `system_action` field
/// when available; falls back to text-based inference via `resolvedSystemAction`.
enum SystemAction: String, Codable, Sendable {
    case memberAdded = "member_added"
    case memberRemoved = "member_removed"
    case memberLeft = "member_left"
    case groupCreated = "group_created"
    case groupNameChanged = "group_name_changed"
    case groupAvatarChanged = "group_avatar_changed"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = SystemAction(rawValue: raw) ?? .unknown
    }
}
```

- [ ] **Step 2: Add systemAction property to Message struct**

Add after `let messageType: MessageType?` (line 78):

```swift
/// Server-provided system action type (nil for non-system messages or older messages)
let systemAction: SystemAction?
```

- [ ] **Step 3: Add resolvedSystemAction computed property**

Add after the existing computed properties (`isAudioMessage`, `isLocationMessage`, etc.):

```swift
/// Best-effort system action resolution. Prefers server-provided `systemAction`;
/// falls back to case-insensitive English text matching for older messages.
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

- [ ] **Step 4: Add CodingKeys entry**

In the `CodingKeys` enum, add after `case locationName = "location_name"` (line 191):

```swift
case systemAction = "system_action"
```

- [ ] **Step 5: Add systemAction parameter to convenience init**

In the convenience `init` (line 198), add `systemAction: SystemAction? = nil` parameter after `messageType`. Add `self.systemAction = systemAction` in the body.

Also update the `Equatable` conformance if it exists (check for `==` function) to include `systemAction`.

- [ ] **Step 6: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add NaarsCars/Core/Models/Message.swift
git commit -m "feat: add SystemAction enum to Message model with graceful decode fallback"
```

---

### Task 3: Wire SystemAction to SystemMessageView

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Cells/SystemMessageView.swift:50-58,107-121`
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift:138-147`

- [ ] **Step 1: Update SystemMessageView.configure to accept SystemAction**

Replace the `configure(text:)` method (lines 50-58) with:

```swift
func configure(text: String, action: SystemAction) {
    textLabel.text = text
    iconView.image = UIImage(systemName: Self.iconName(for: action))

    isAccessibilityElement = true
    accessibilityLabel = text
    accessibilityTraits = .staticText

    setNeedsLayout()
}
```

- [ ] **Step 2: Replace text-based iconName with switch on SystemAction**

Replace the `iconName(for text:)` method (lines 107-124) with:

```swift
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

- [ ] **Step 3: Update MessageCellView.showSystem call site**

In `MessageCellView.swift`, update `showSystem(msg:)` (around line 146) to pass the resolved action:

Change:
```swift
view.configure(text: msg.text)
```
To:
```swift
view.configure(text: msg.text, action: msg.resolvedSystemAction)
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/SystemMessageView.swift \
       NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "refactor: use typed SystemAction enum for system message icon selection"
```

---

## Chunk 2: InputBarController + Audio Coordinator Extraction

This is the core refactor. It creates the shared infrastructure, then rewires both view layers.

### Task 4: Create AudioRecordingCoordinator

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/AudioRecordingCoordinator.swift`

The audio recording logic is duplicated across `MessageInputBar.swift:231-351` and `MessageInputAccessoryView.swift:707-852`. This coordinator extracts the shared behavior.

- [ ] **Step 1: Create AudioRecordingCoordinator.swift**

```swift
//
//  AudioRecordingCoordinator.swift
//  NaarsCars
//
//  Manages AVAudioRecorder lifecycle, recording duration, and file management
//

import AVFoundation
import Observation

/// Coordinates audio recording for the message input bar.
/// Owns AVAudioRecorder, duration timer, and the recorded file URL.
@MainActor
@Observable
final class AudioRecordingCoordinator {

    struct RecordingResult {
        let url: URL
        let duration: TimeInterval
    }

    // MARK: - Observable State

    private(set) var isRecording = false
    private(set) var duration: TimeInterval = 0
    private(set) var hasRecordedFile = false

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?

    private let minimumDuration: TimeInterval = 1.0

    // MARK: - Actions

    func start() {
        Task {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = await AVAudioApplication.requestRecordPermission()
            } else {
                granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { result in
                        continuation.resume(returning: result)
                    }
                }
            }
            guard granted else { return }
            beginRecording()
        }
    }

    /// Stops recording and returns the result if duration >= minimum.
    /// Returns nil if recording was too short (file is cleaned up).
    func stop() -> RecordingResult? {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else { return nil }
        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil

        let finalDuration = Date().timeIntervalSince(recordingStartDate ?? Date())
        isRecording = false

        guard finalDuration >= minimumDuration else {
            cleanup(url: url)
            return nil
        }

        hasRecordedFile = true
        return RecordingResult(url: url, duration: finalDuration)
    }

    func cancel() {
        guard isRecording else { return }
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        if let url = recordingURL {
            cleanup(url: url)
        }
    }

    func clearRecordedFile() {
        hasRecordedFile = false
    }

    // MARK: - Private

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "voice_\(UUID().uuidString).m4a"
            let url = tempDir.appendingPathComponent(fileName)
            recordingURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            audioRecorder = recorder

            recordingStartDate = Date()
            duration = 0
            isRecording = true

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let start = self.recordingStartDate else { return }
                    self.duration = Date().timeIntervalSince(start)
                }
            }
        } catch {
            AppLogger.error("messaging", "Failed to begin audio recording: \(error)")
        }
    }

    private func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
        recordingStartDate = nil
        duration = 0
        hasRecordedFile = false
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED (new file not yet in project — tell user to add it)

**Important:** Tell the user: "Please add `NaarsCars/UI/Components/Messaging/AudioRecordingCoordinator.swift` to the Xcode project (File → Add Files to NaarsCars)."

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/AudioRecordingCoordinator.swift
git commit -m "refactor: extract AudioRecordingCoordinator from dual input bar implementations"
```

---

### Task 5: Create InputBarController

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/InputBarController.swift`

- [ ] **Step 1: Create InputBarController.swift**

```swift
//
//  InputBarController.swift
//  NaarsCars
//
//  Shared @Observable state controller for message input bars (SwiftUI and UIKit)
//

import UIKit
import Observation

/// Shared state and coordination layer for the message input bar.
/// Consumed by SwiftUI `MessageInputBar` (thread view) and UIKit
/// `MessageInputAccessoryView` (main conversation). Uses `@Observable`
/// for per-property tracking in SwiftUI — this is a UI component controller,
/// not a ViewModel (see spec for justification).
@MainActor
@Observable
final class InputBarController {

    // MARK: - Text (single mutation path)

    private(set) var currentText: String = ""

    /// The only way to mutate text. Notifies typing callback.
    func updateText(_ newValue: String) {
        let oldLength = currentText.count
        currentText = newValue
        signalTypingIfNeeded(oldLength: oldLength, newLength: newValue.count, newText: newValue)
    }

    // MARK: - Mode

    enum Mode: Equatable {
        case normal
        case replying(ReplyContext)
        case editing(messageId: UUID, originalText: String)

        var replyContext: ReplyContext? {
            if case .replying(let ctx) = self { return ctx }
            return nil
        }
        var editMessageId: UUID? {
            if case .editing(let id, _) = self { return id }
            return nil
        }
    }

    private(set) var mode: Mode = .normal

    // MARK: - Attachment

    enum AttachmentState: Equatable {
        case none
        case processing(UIImage)
        case ready(InputAttachment)

        var previewImage: UIImage? {
            switch self {
            case .none: return nil
            case .processing(let image): return image
            case .ready(let attachment): return attachment.image
            }
        }

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    struct InputAttachment: Equatable {
        let image: UIImage
        let data: Data
    }

    private(set) var attachmentState: AttachmentState = .none
    private var attachmentGeneration: UInt64 = 0

    // MARK: - Recording

    let audioCoordinator = AudioRecordingCoordinator()

    var isRecording: Bool { audioCoordinator.isRecording }
    var recordingDuration: TimeInterval { audioCoordinator.duration }

    // MARK: - Computed

    var isSendable: Bool {
        !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || attachmentState.isReady
        || audioCoordinator.hasRecordedFile
    }

    var isEditing: Bool {
        if case .editing = mode { return true }
        return false
    }

    // MARK: - Send Payload

    struct SendPayload {
        let text: String
        let attachment: InputAttachment?
        let replyContext: ReplyContext?
        let editMessageId: UUID?
    }

    // MARK: - Callbacks

    var onSend: ((SendPayload) -> Void)?
    var onAudioRecorded: ((URL, Double) -> Void)?
    var onImagePickerRequested: (() -> Void)?
    var onCameraRequested: (() -> Void)?
    var onLocationPickerRequested: (() -> Void)?
    var onTypingChanged: (() -> Void)?

    // MARK: - Actions

    /// Send the current draft as text/attachment message.
    /// Audio recordings are sent separately via stopRecording() -> onAudioRecorded callback,
    /// not through this method.
    func send() {
        let attachment: InputAttachment?
        if case .ready(let att) = attachmentState {
            attachment = att
        } else {
            attachment = nil
        }

        let payload = SendPayload(
            text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
            attachment: attachment,
            replyContext: mode.replyContext,
            editMessageId: mode.editMessageId
        )
        guard !payload.text.isEmpty || payload.attachment != nil else { return }
        onSend?(payload)
        reset()
    }

    func setReplyContext(_ context: ReplyContext) {
        mode = .replying(context)
    }

    func cancelReply() {
        if case .replying = mode { mode = .normal }
    }

    func startEditing(messageId: UUID, text: String) {
        mode = .editing(messageId: messageId, originalText: text)
        currentText = text
    }

    func cancelEditing() {
        if case .editing = mode {
            currentText = ""
            mode = .normal
        }
    }

    func setImage(_ image: UIImage) {
        attachmentGeneration &+= 1
        let gen = attachmentGeneration
        attachmentState = .processing(image)
        Task.detached(priority: .userInitiated) {
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                await MainActor.run {
                    guard self.attachmentGeneration == gen else { return }
                    AppLogger.error("messaging", "Failed to compress image attachment")
                    self.attachmentState = .none
                }
                return
            }
            await MainActor.run {
                guard self.attachmentGeneration == gen else { return }
                self.attachmentState = .ready(InputAttachment(image: image, data: data))
            }
        }
    }

    func clearAttachment() {
        attachmentGeneration &+= 1
        attachmentState = .none
    }

    func startRecording() { audioCoordinator.start() }

    func stopRecording() {
        if let result = audioCoordinator.stop() {
            onAudioRecorded?(result.url, result.duration)
        }
    }

    func cancelRecording() { audioCoordinator.cancel() }

    // MARK: - Private

    /// Resets text, attachment, and mode after a successful text/attachment send.
    /// Does NOT reset audio state — audio recordings are sent separately via
    /// stopRecording() -> onAudioRecorded and do not flow through send().
    private func reset() {
        currentText = ""
        attachmentState = .none
        attachmentGeneration &+= 1
        mode = .normal
    }

    private func signalTypingIfNeeded(oldLength: Int, newLength: Int, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, newLength > oldLength, trimmed.count >= 2 else { return }
        onTypingChanged?()
    }
}
```

- [ ] **Step 2: Build to verify**

Tell user to add `NaarsCars/UI/Components/Messaging/InputBarController.swift` to the Xcode project.

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/InputBarController.swift
git commit -m "feat: add InputBarController — shared @Observable state for message input"
```

---

### Task 6: Rewire UIKit Input Bar + MessagesViewController + Representable

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageInputAccessoryView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewController.swift:52-65`
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift:62-71,119-165`

This is the largest single task. The UIKit input bar keeps its view layer (subviews, layout, keyboard behavior) but replaces inline state management with calls to the shared controller. `MessagesViewController` and `MessagesViewControllerRepresentable` are updated in the same atomic unit because changing the `init` signature would break the call site. All three files must be committed together.

- [ ] **Step 1: Add controller property and update delegate protocol**

Add a `controller` property to the class and remove `didShareLocation` from the delegate protocol.

At the top of the class, add:
```swift
let controller: InputBarController
```

Update `init` to accept the controller:
```swift
init(controller: InputBarController) {
    self.controller = controller
    super.init(frame: .zero)
    // ... existing setup ...
}
```

Remove from `MessageInputDelegate` protocol (line 21):
```swift
// DELETE: func inputBar(_ bar: MessageInputAccessoryView, didShareLocation lat: Double, lon: Double, name: String?)
```

- [ ] **Step 2: Replace internal state with controller reads**

Remove the internal state properties (lines 93-108):
- `replyName`, `replyPreview`, `editMessageId`, `editOriginalText` → use `controller.mode`
- `audioRecorder`, `recordingURL`, etc. → use `controller.audioCoordinator`
- `lastTypingSignalAt`, `previousTextLength` → handled by `controller.updateText()`

Replace `setReplyContext()`, `clearReplyContext()`, `setEditContext()`, `clearEditContext()` methods (lines 45-77) with calls to the controller. Note: `InputBarController.setReplyContext()` accepts a full `ReplyContext` object (which has `id`, `text`, `senderName`, `senderId`). The UIKit view's bridge methods change to accept `ReplyContext` directly rather than individual strings — the `MessagesViewControllerRepresentable` (Task 7) already has the full `ReplyContext` and passes it:

```swift
func setReplyContext(_ context: ReplyContext) {
    controller.setReplyContext(context)
    showReplyBanner(name: context.senderName, preview: context.text)
}

func clearReplyContext() {
    controller.cancelReply()
    hideContextBanner()
}

func setEditContext(text: String, messageId: UUID) {
    controller.startEditing(messageId: messageId, text: text)
    showEditBanner(text: text)
}

func clearEditContext() {
    controller.cancelEditing()
    hideContextBanner()
}
```

- [ ] **Step 3: Replace send action with controller.send()**

In the send button target, replace the current logic that reads text and assembles the message with:
```swift
controller.send()
```

The `controller.onSend` callback (set by `MessagesViewController`) handles the actual send.

- [ ] **Step 4: Replace audio recording with controller calls**

Replace `toggleRecording()`, `startRecording()`, `beginRecording()`, `stopAndSendRecording()`, `cancelRecording()` (lines 707-852) with controller delegates:
```swift
@objc private func toggleRecording() {
    if controller.isRecording {
        controller.stopRecording()
        hideRecordingBanner()
    } else {
        controller.startRecording()
        showRecordingBanner()
    }
}
```

Set up `withObservationTracking` to observe `controller.isRecording` for banner show/hide, using the re-registration pattern from `ConversationDetailViewModel.observeTypingUsers()`.

- [ ] **Step 5: Replace location button action**

Replace the sentinel hack (lines 597-607) with:
```swift
let location = UIAction(
    title: "messaging_menu_location".localized,
    image: UIImage(systemName: "location.fill")
) { [weak self] _ in
    self?.controller.onLocationPickerRequested?()
}
```

- [ ] **Step 6: Wire text updates through controller**

In `textViewDidChange()` (UITextViewDelegate), replace the inline typing throttle with:
```swift
controller.updateText(textView.text)
```

- [ ] **Step 7: Set up observation for reactive properties**

Add observation for `isSendable`, `mode`, and `attachmentState` using `withObservationTracking` with re-registration:

```swift
private func observeController() {
    withObservationTracking {
        let _ = self.controller.isSendable
        let _ = self.controller.mode
        let _ = self.controller.attachmentState
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            self?.updateFromController()
            self?.observeController()
        }
    }
}

private func updateFromController() {
    // Send button
    sendButton.isEnabled = controller.isSendable

    // Attachment preview
    switch controller.attachmentState {
    case .none:
        imagePreviewContainer.isHidden = true
    case .processing(let image), .ready(InputBarController.InputAttachment(image: let image, data: _)):
        imagePreviewView.image = image
        imagePreviewContainer.isHidden = false
    }

    // Recording banner
    if controller.isRecording {
        showRecordingBanner()
        recordingDurationLabel.text = formatDuration(controller.recordingDuration)
    } else if recordingBanner?.isHidden == false {
        hideRecordingBanner()
    }
}
```

Call `observeController()` from init.

- [ ] **Step 8: Wire MessagesViewController to own InputBarController**

This step is part of the same atomic unit as Steps 1-7 — the project cannot build until both the view and its owner are updated together.

Replace the lazy `inputBar` property in `MessagesViewController.swift` (lines 57-61) to create both the controller and the input bar:

```swift
let inputBarController = InputBarController()

private lazy var inputBar: MessageInputAccessoryView = {
    let bar = MessageInputAccessoryView(controller: inputBarController)
    bar.delegate = self
    return bar
}()
```

- [ ] **Step 9: Update MessagesViewControllerRepresentable coordinator**

In `makeUIViewController`, wire the controller callbacks instead of relying solely on delegate:

```swift
let vc = MessagesViewController(...)
vc.inputBarController.onSend = { [weak coordinator] payload in
    coordinator?.handleSend(payload)
}
vc.inputBarController.onAudioRecorded = { [weak coordinator] url, duration in
    coordinator?.parent.onAudioRecorded(url, duration)
}
vc.inputBarController.onImagePickerRequested = { [weak coordinator] in
    coordinator?.parent.onImagePickerTapped()
}
vc.inputBarController.onCameraRequested = { [weak coordinator] in
    coordinator?.viewController?.presentCamera()
}
vc.inputBarController.onLocationPickerRequested = { [weak coordinator] in
    coordinator?.parent.onLocationRequested()
}
vc.inputBarController.onTypingChanged = { [weak coordinator] in
    coordinator?.parent.onTypingChanged()
}
```

- [ ] **Step 10: Remove didShareLocation from coordinator conformance**

Remove `inputBar(_:didShareLocation:lon:name:)` from the `Coordinator` extension (line 149-151).

- [ ] **Step 11: Update updateUIViewController to use controller**

In `updateUIViewController`, replace calls to `bar.setReplyContext()`, `bar.setEditContext()`, `bar.setImagePreview()` with controller calls:

```swift
if let reply = parent.replyingTo {
    vc.inputBarController.setReplyContext(reply)
} else {
    vc.inputBarController.cancelReply()
}
if let editing = parent.editingMessage {
    vc.inputBarController.startEditing(messageId: editing.id, text: editing.text)
} else if vc.inputBarController.isEditing {
    vc.inputBarController.cancelEditing()
}
if let image = parent.imageToSend {
    vc.inputBarController.setImage(image)
} else {
    vc.inputBarController.clearAttachment()
}
```

- [ ] **Step 12: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 13: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessageInputAccessoryView.swift \
       NaarsCars/Features/Messaging/Views/MessagesViewController.swift \
       NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift
git commit -m "refactor: wire UIKit input bar and MessagesViewController to InputBarController, remove location sentinel"
```

---

### Task 8: Rewrite MessageInputBar + Rewire MessageThreadViewController

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageInputBar.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift:155,358-402`

This is a major rewrite. The 774-line SwiftUI view becomes a ~200-line rendering shell. The thread VC is updated in the same atomic unit because changing `MessageInputBar`'s initializer would break the call site in `MessageThreadViewController.makeInputBar()`. Both files must be committed together.

- [ ] **Step 1: Replace state properties with controller reference**

Remove all `@State` and `@Binding` properties (lines 17-59). Replace with a single controller reference:

```swift
struct MessageInputBar: View {
    let controller: InputBarController
    let isDisabled: Bool

    @FocusState private var isTextFieldFocused: Bool
    @State private var sendButtonScale: CGFloat = 1.0
}
```

- [ ] **Step 2: Rewrite body to read controller state**

The body reads `controller.currentText`, `controller.mode`, `controller.attachmentState`, `controller.isRecording`, `controller.recordingDuration`, `controller.isSendable` for display. It calls `controller.updateText()`, `controller.send()`, `controller.clearAttachment()`, etc. for actions.

Key sections:
- Text field binds via `Binding(get: { controller.currentText }, set: { controller.updateText($0) })`
- Attachment preview reads `controller.attachmentState.previewImage`
- Send button enabled by `controller.isSendable && !isDisabled`
- Reply/edit banner reads `controller.mode`
- Recording UI reads `controller.isRecording`, `controller.recordingDuration`
- Menu actions call `controller.onImagePickerRequested?()`, `controller.onCameraRequested?()`, `controller.onLocationPickerRequested?()`

- [ ] **Step 3: Remove all inline logic**

Delete:
- Audio recording methods (`toggleRecording`, `startRecording`, `beginRecording`, `stopAndSendRecording`, `cancelRecording`, `formatDuration`) — ~120 lines
- Typing throttle (`signalTypingIfNeeded`) — ~10 lines
- Location picker `@State showLocationPicker` and `.sheet` modifier — removed (controller callback handles presentation). **Keep `LocationPickerSheet` struct in `MessageInputBar.swift`** — it is also referenced by `ConversationDetailView.swift:521`. Do not extract it; just remove the sheet presentation logic that wired it.
- Reply/edit context management — simplified to reading `controller.mode`

- [ ] **Step 4: Rewire MessageThreadViewController to use InputBarController**

This step is part of the same atomic unit as Steps 1-3 — the project cannot build until both the SwiftUI view and its UIKit host are updated together.

Replace the `inputHostingController` and `makeInputBar()` pattern in `MessageThreadViewController.swift` (lines 155, 358-402) with:

```swift
let inputBarController = InputBarController()
private var inputHostingController: UIHostingController<MessageInputBar>?
```

Update `setupInputBar()` to:
```swift
private func setupInputBar() {
    inputBarController.onSend = { [weak self] payload in
        self?.handleSend(payload)
    }
    inputBarController.onImagePickerRequested = { [weak self] in
        self?.presentImagePicker()
    }
    inputBarController.onLocationPickerRequested = { [weak self] in
        self?.presentLocationPicker()
    }
    inputBarController.onTypingChanged = { [weak self] in
        self?.conversationViewModel?.typingManager.userDidType()
    }

    let inputBar = MessageInputBar(controller: inputBarController, isDisabled: false)
    let host = UIHostingController(rootView: inputBar)
    // ... existing constraint setup ...
}
```

- [ ] **Step 5: Add presentLocationPicker method to MessageThreadViewController**

```swift
private func presentLocationPicker() {
    let picker = LocationPickerSheet { [weak self] coordinate, name in
        guard let self else { return }
        Task {
            await self.conversationViewModel?.sendLocationMessage(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                locationName: name,
                replyToId: self.threadViewModel.parentMessage?.id
            )
        }
    }
    let host = UIHostingController(rootView: picker)
    present(host, animated: true)
}
```

- [ ] **Step 6: Update handleSend to use SendPayload**

```swift
private func handleSend(_ payload: InputBarController.SendPayload) {
    guard let parentId = threadViewModel.parentMessage?.id else { return }
    Task {
        if let editId = payload.editMessageId {
            // Edit targets the specific message being edited (editId), not the thread parent.
            // ConversationDetailViewModel.editMessage reads editingMessage for the target ID,
            // so set it before calling editMessage.
            conversationViewModel?.editingMessage = conversationViewModel?.messages.first { $0.id == editId }
            await conversationViewModel?.editMessage(newContent: payload.text)
        } else if let attachment = payload.attachment {
            await conversationViewModel?.sendMessage(
                textOverride: payload.text.isEmpty ? nil : payload.text,
                image: attachment.image,
                replyToId: parentId
            )
        } else {
            await conversationViewModel?.sendMessage(
                textOverride: payload.text,
                replyToId: parentId
            )
        }
    }
}
```

- [ ] **Step 7: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessageInputBar.swift \
       NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift
git commit -m "refactor: rewrite MessageInputBar as thin shell and wire MessageThreadViewController to InputBarController"
```

---

## Chunk 3: Frozen Conversation UI

### Task 10: Add conversationFrozen Error Case

**Files:**
- Modify: `NaarsCars/Core/Utilities/AppError.swift:12-107`

- [ ] **Step 1: Add conversationFrozen case**

Add after `case unknown(String)` (line 29):

```swift
case conversationFrozen
```

Add to `errorDescription` switch (after the `.unknown` case). Note: existing AppError cases use hardcoded English strings for `errorDescription`, so match that pattern for consistency within the file:

```swift
case .conversationFrozen:
    return "You can't send messages in a conversation you've left."
```

Add to `failureReason` switch:

```swift
case .conversationFrozen:
    return "Conversation frozen — user has left"
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Core/Utilities/AppError.swift
git commit -m "feat: add conversationFrozen AppError case for left-conversation guard"
```

---

### Task 11: Add Frozen Guards to ConversationDetailViewModel

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

- [ ] **Step 1: Add frozen guard to all 7 mutation methods**

At the top of each method, add:

```swift
guard !hasLeftConversation else {
    AppLogger.warning("messaging", "Blocked \(#function): user has left conversation \(conversationId)")
    error = .conversationFrozen
    return
}
```

Methods to guard (line numbers from current file):
- `sendMessage()` — line 362
- `editMessage()` — line 477
- `unsendMessage()` — line 491
- `sendAudioMessage()` — line 512
- `sendLocationMessage()` — line 526
- `addReaction()` — line 558
- `removeReaction()` — line 570

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift
git commit -m "fix: add frozen conversation guards to all ViewModel mutation methods"
```

---

### Task 12: Create FrozenConversationBanner

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/FrozenConversationBanner.swift`

- [ ] **Step 1: Create FrozenConversationBanner.swift**

```swift
//
//  FrozenConversationBanner.swift
//  NaarsCars
//
//  Read-only banner shown when user has left a conversation
//

import SwiftUI

/// Non-interactive banner replacing the input bar when the user has left a conversation.
struct FrozenConversationBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("messaging_left_conversation".localized)
                .font(.naarsFootnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.naarsCardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("messaging_left_conversation".localized)
    }
}
```

- [ ] **Step 2: Add localization key**

Add to `Localizable.xcstrings`:
- `"messaging_left_conversation"` → `"You left this conversation"`

**Important:** Tell user to add `NaarsCars/UI/Components/Messaging/FrozenConversationBanner.swift` to the Xcode project.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/FrozenConversationBanner.swift \
       NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add FrozenConversationBanner for left-conversation UI state"
```

---

### Task 13: Wire Frozen State to Overlay

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift:46-49,59-101`
- Modify: `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift:38-59`
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewController.swift:416-426`

- [ ] **Step 1: Add isConversationFrozen to OverlayActionListView**

Update the `init` (line 46) to accept the frozen flag:

```swift
init(message: Message, isFromCurrentUser: Bool, isConversationFrozen: Bool = false) {
    super.init(frame: .zero)
    let items = Self.buildActions(message: message, isFromCurrentUser: isFromCurrentUser, isConversationFrozen: isConversationFrozen)
    setupViews(items: items)
}
```

Update `buildActions` (line 59) to filter participation actions when frozen:

```swift
private static func buildActions(message: Message, isFromCurrentUser: Bool, isConversationFrozen: Bool) -> [ActionItem] {
    var items: [ActionItem] = []

    if !isConversationFrozen {
        // Reply — only when participating
        items.append(ActionItem(action: .reply, title: NSLocalizedString("Reply", comment: "Message action: reply to this message"), icon: "arrow.uturn.left", isDestructive: false))
    }

    // View Thread — always available (read-only navigation)
    if let replyToId = message.replyToId {
        items.append(ActionItem(
            action: .viewThread(replyToId),
            title: NSLocalizedString("messaging_view_thread", comment: "Message action: open the reply thread"),
            icon: "bubble.left.and.bubble.right",
            isDestructive: false
        ))
    }

    // Copy — always available
    if !message.text.isEmpty {
        items.append(ActionItem(action: .copy, title: NSLocalizedString("Copy", comment: "Message action: copy message text to clipboard"), icon: "doc.on.doc", isDestructive: false))
    }

    if !isConversationFrozen {
        // Edit — only when participating
        if isFromCurrentUser,
           message.messageType == .text || message.messageType == nil,
           !message.isAudioMessage,
           !message.isLocationMessage {
            items.append(ActionItem(action: .edit, title: NSLocalizedString("Edit", comment: "Message action: edit own message text"), icon: "pencil", isDestructive: false))
        }

        // Undo Send — only when participating
        if isFromCurrentUser, message.canUnsend {
            items.append(ActionItem(action: .unsend, title: NSLocalizedString("messaging_undo_send", comment: "Message action: recall sent message within time limit"), icon: "arrow.uturn.backward", isDestructive: true))
        }
    }

    // Delete for Me — always available (local-only action)
    items.append(ActionItem(action: .deleteForMe, title: NSLocalizedString("messaging_delete_for_me", comment: "Message action: delete message for current user only"), icon: "trash", isDestructive: true))

    // Report — always available (moderation action)
    if !isFromCurrentUser {
        items.append(ActionItem(action: .report, title: NSLocalizedString("messaging_report_message", comment: "Message action: report inappropriate message"), icon: "exclamationmark.triangle", isDestructive: true))
    }

    return items
}
```

- [ ] **Step 2: Add isConversationFrozen to MessageOverlayController**

Add `isConversationFrozen: Bool` to the `init` (line 38). Pass it to `OverlayActionListView`. When frozen, hide `reactionBar`:

```swift
private let isConversationFrozen: Bool

// In init:
self.isConversationFrozen = isConversationFrozen
self.actionList = OverlayActionListView(message: message, isFromCurrentUser: isFromCurrentUser, isConversationFrozen: isConversationFrozen)

// In setupReactionBar:
if isConversationFrozen {
    reactionBar.isHidden = true
    reactionBar.alpha = 0
}
```

- [ ] **Step 3: Pass frozen flag from MessagesViewController**

In `messageCellDidLongPress` (line 416), pass the frozen flag to the overlay:

```swift
let overlay = MessageOverlayController(
    snapshot: snapshot,
    sourceFrame: cellFrame,
    message: message,
    isFromCurrentUser: isFromCurrentUser,
    currentUserReaction: currentReaction,
    isConversationFrozen: configuration.isConversationFrozen,
    onAction: { [weak self] action in
        self?.configuration.onOverlayAction?(action, message)
    }
)
```

Add `isConversationFrozen` to the VC's `Configuration` struct.

- [ ] **Step 4: Build to verify**

Run build command. Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift \
       NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift \
       NaarsCars/Features/Messaging/Views/MessagesViewController.swift
git commit -m "feat: filter overlay actions when conversation is frozen — hide Reply, Edit, Undo Send, React"
```

---

### Task 14: Wire Frozen State from ConversationDetailView Through to MessagesViewController

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift:354-453,166-168`
- Modify: `NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadRepresentable.swift`

- [ ] **Step 1: ConversationDetailView — show frozen banner instead of input bar**

In `ConversationDetailView`, where the input bar area is rendered, wrap it with the frozen conditional. The exact location depends on how the input bar integrates with `MessagesViewControllerRepresentable` — if the representable includes the input bar via `inputAccessoryView`, then the frozen banner replaces the entire representable's input area by overlaying or by passing the frozen flag so the VC hides its input bar internally.

Pass `hasLeftConversation` to `MessagesViewControllerRepresentable`:
```swift
MessagesViewControllerRepresentable(
    // ... existing params ...
    isConversationFrozen: viewModel.hasLeftConversation
)
```

Add `FrozenConversationBanner()` in the view hierarchy when frozen, positioned where the input bar would be.

- [ ] **Step 2: MessagesViewControllerRepresentable passes frozen flag**

In `makeUIViewController`/`updateUIViewController`, set the VC's frozen configuration:
```swift
vc.configuration.isConversationFrozen = parent.isConversationFrozen
```

- [ ] **Step 3: MessageThreadRepresentable passes frozen flag**

Add `hasLeftConversation: Bool` parameter to `MessageThreadRepresentable`. Pass through to `MessageThreadViewController`.

- [ ] **Step 4: MessageThreadViewController shows frozen banner when left**

When `hasLeftConversation` is true, replace the input bar with a `FrozenConversationBanner` embedded via `UIHostingController`. Explicitly remove whichever bottom view is being replaced to avoid stale views:

```swift
private var frozenBannerController: UIHostingController<FrozenConversationBanner>?

private func setupBottomView() {
    // Remove existing bottom view (input bar or frozen banner)
    if let existing = inputHostingController {
        existing.willMove(toParent: nil)
        existing.view.removeFromSuperview()
        existing.removeFromParent()
        inputHostingController = nil
    }
    if let existing = frozenBannerController {
        existing.willMove(toParent: nil)
        existing.view.removeFromSuperview()
        existing.removeFromParent()
        frozenBannerController = nil
    }

    if hasLeftConversation {
        let banner = UIHostingController(rootView: FrozenConversationBanner())
        addChild(banner)
        banner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner.view)
        NSLayoutConstraint.activate([
            banner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        banner.didMove(toParent: self)
        frozenBannerController = banner
    } else {
        setupInputBar()
    }
}
```

Call `setupBottomView()` from `viewDidLoad()` instead of calling `setupInputBar()` directly.

- [ ] **Step 5: Build to verify**

Run build command. Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationDetailView.swift \
       NaarsCars/Features/Messaging/Views/MessagesViewControllerRepresentable.swift \
       NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift \
       NaarsCars/Features/Messaging/Views/MessageThreadRepresentable.swift
git commit -m "feat: wire hasLeftConversation through to all messaging surfaces — frozen banner replaces input bar"
```

---

## Verification Checklist

After all tasks are complete:

- [ ] Build succeeds: `xcodebuild -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build`
- [ ] No references to `MessageBubble`, `MessageInteractionOverlay`, `ReactionPicker`, `BubbleShape` in Swift files
- [ ] No `UIHostingConfiguration` in messaging Swift files (except comments)
- [ ] `grep -rn "didShareLocation.*0.*0" NaarsCars/` returns no results (sentinel removed)
- [ ] `grep -rn "inputBar.*didShareLocation" NaarsCars/` returns no results in Swift files
- [ ] `grep -rn "hasLeftConversation" NaarsCars/` shows reads in ConversationDetailView, MessagesViewControllerRepresentable, MessageThreadViewController, MessageThreadRepresentable, and writes/guards in ConversationDetailViewModel
- [ ] `grep -rn "SystemAction" NaarsCars/` shows enum in Message.swift, usage in SystemMessageView.swift and MessageCellView.swift
- [ ] `grep -rn "prewarmTextInput" NaarsCars/` shows definition and call in AppDelegate.swift
- [ ] `grep -rn "InputBarController" NaarsCars/` shows usage in MessagesViewController, MessageThreadViewController, MessageInputBar, MessageInputAccessoryView
