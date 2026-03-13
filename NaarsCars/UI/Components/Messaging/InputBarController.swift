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
