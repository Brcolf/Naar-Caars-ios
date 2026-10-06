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
        case ready(InputAttachment)

        var previewImage: UIImage? {
            switch self {
            case .none: return nil
            case .ready(let attachment): return attachment.image
            }
        }

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    /// The picked image only. Encoding happens once, in MessageSendManager,
    /// after the resize — a full-resolution JPEG here was never read.
    struct InputAttachment: Equatable {
        let image: UIImage
    }

    private(set) var attachmentState: AttachmentState = .none

    // MARK: - Recording

    let audioCoordinator = AudioRecordingCoordinator()

    var isRecording: Bool { audioCoordinator.isRecording }
    var recordingDuration: TimeInterval { audioCoordinator.duration }

    // MARK: - Computed

    var isSendable: Bool {
        guard !isOverCharacterLimit else { return false }
        return !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachmentState.isReady
            || audioCoordinator.hasRecordedFile
    }

    // MARK: - Length limit

    /// The counter appears once this many characters (or fewer) are left.
    static let characterCountThreshold = 200

    /// Characters left before the send path refuses the message as too long; negative when
    /// over. Counts the trimmed text, exactly as `MessageSendManager.sendMessage` does, so the
    /// composer stops an over-long message before it is sent (and the draft lost) rather than
    /// after.
    static func remainingCharacters(for text: String) -> Int {
        let length = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return Constants.Limits.messageTextMaxLength - length
    }

    /// VoiceOver text for the counter.
    static func characterCountAccessibilityText(remaining: Int) -> String {
        remaining >= 0
            ? "messaging_characters_remaining".localized(with: remaining)
            : "messaging_characters_over_limit".localized(with: -remaining)
    }

    var remainingCharacters: Int { Self.remainingCharacters(for: currentText) }
    var isOverCharacterLimit: Bool { remainingCharacters < 0 }
    var showsCharacterCount: Bool { remainingCharacters <= Self.characterCountThreshold }

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
    /// Microphone access was denied when a voice note was requested.
    var onMicrophoneAccessDenied: (() -> Void)?
    var onTypingChanged: (() -> Void)?
    /// Fired when the user dismisses the attachment (not after a send), so a host
    /// that mirrors the image in its own state can drop it too.
    var onAttachmentCleared: (() -> Void)?

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
        // Backstop for the disabled send button: an over-long message is never handed to the
        // send path (it would be refused there) and the draft stays in the bar.
        guard Self.remainingCharacters(for: payload.text) >= 0 else { return }
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

    /// Hands back a draft whose send was refused before a bubble existed (rate limit,
    /// over-long text). `send()` has already cleared the bar by then, so without this the
    /// typed text and picked photo were lost. A newer draft or an edit in progress is left
    /// alone, and no typing signal is sent (nothing was typed).
    func restoreDraft(text: String, image: UIImage?) {
        guard !isEditing else { return }
        if currentText.isEmpty {
            currentText = text
        }
        if let image, attachmentState == .none {
            attachmentState = .ready(InputAttachment(image: image))
        }
    }

    func setImage(_ image: UIImage) {
        // Skip if already ready with the same image instance
        if let existing = attachmentState.previewImage, existing === image { return }
        attachmentState = .ready(InputAttachment(image: image))
    }

    func clearAttachment() {
        guard attachmentState != .none else { return }
        attachmentState = .none
        onAttachmentCleared?()
    }

    func startRecording() {
        audioCoordinator.onPermissionDenied = { [weak self] in
            self?.onMicrophoneAccessDenied?()
        }
        audioCoordinator.start()
    }

    func stopRecording() {
        if let result = audioCoordinator.stop() {
            onAudioRecorded?(result.url, result.duration)
            // The recording has been handed off. Nothing else cleared this flag, so after one
            // voice note `isSendable` stayed true and the SwiftUI bar's send arrow stayed
            // tinted and enabled with nothing to send.
            audioCoordinator.clearRecordedFile()
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
        mode = .normal
    }

    private func signalTypingIfNeeded(oldLength: Int, newLength: Int, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, newLength > oldLength, trimmed.count >= 2 else { return }
        onTypingChanged?()
    }
}
