//
//  MessagesViewControllerRepresentable.swift
//  NaarsCars
//
//  UIViewControllerRepresentable wrapper around MessagesViewController.
//  Replaces the MessagesCollectionView UIViewRepresentable and owns
//  the input bar via inputAccessoryView for interactive keyboard dismissal.
//

import SwiftUI
import UIKit

struct MessagesViewControllerRepresentable: UIViewControllerRepresentable {

    // MARK: Collection View Props (same as MessagesCollectionView)

    let messages: [Message]
    let messagesVersion: Int
    let cellConfigurations: [UUID: MessageCellConfiguration]
    let participantProfiles: [Profile]
    let isGroupConversation: Bool
    let totalParticipants: Int
    let onOverlayAction: (OverlayAction, Message) -> Void
    let onSwipeReply: (Message) -> Void
    let onImageTap: (URL) -> Void
    let onReplyPreviewTap: (UUID) -> Void
    let onRetry: (Message) -> Void
    let onReactionTap: (Message, String?) -> Void
    let onLoadMore: () -> Void
    let onScrolledToBottom: (Bool) -> Void
    let scrollToMessageId: UUID?
    let scrollToBottom: Bool

    // Unread divider
    let firstUnreadMessageId: UUID?
    let unreadCount: Int
    let showUnreadDivider: Bool
    let onUnreadDividerDismissed: () -> Void

    // MARK: Input Bar Props

    let replyContext: ReplyContext?
    let editingMessage: Message?
    @Binding var imageToSend: UIImage?

    // Input bar callbacks
    let onSendMessage: (String) -> Void
    let onSendEditedMessage: (String, UUID) -> Void
    let onImagePickerTapped: () -> Void
    let onAudioRecorded: (URL, Double) -> Void
    let onLocationRequested: () -> Void
    let onCancelReply: () -> Void
    let onCancelEdit: () -> Void
    let onTypingChanged: () -> Void

    let replyCountMap: [UUID: Int]
    let onViewThread: ((Message) -> Void)?

    /// When true the conversation is frozen (user has left) and the overlay
    /// should suppress send-oriented actions.
    var isConversationFrozen: Bool = false

    // MARK: UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MessagesViewController {
        let vc = MessagesViewController()
        vc.inputDelegate = context.coordinator
        vc.onCameraCapturedImage = { [weak coordinator = context.coordinator] image in
            coordinator?.parent.imageToSend = image
        }
        context.coordinator.viewController = vc

        // Wire controller callbacks
        vc.inputBarController.onSend = { [weak coordinator = context.coordinator] payload in
            coordinator?.handleSend(payload)
        }
        vc.inputBarController.onAudioRecorded = { [weak coordinator = context.coordinator] url, duration in
            coordinator?.parent.onAudioRecorded(url, duration)
        }
        vc.inputBarController.onImagePickerRequested = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onImagePickerTapped()
        }
        vc.inputBarController.onCameraRequested = { [weak coordinator = context.coordinator] in
            coordinator?.viewController?.presentCamera()
        }
        vc.inputBarController.onLocationPickerRequested = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onLocationRequested()
        }
        vc.inputBarController.onTypingChanged = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTypingChanged()
        }

        return vc
    }

    func updateUIViewController(_ vc: MessagesViewController, context: Context) {
        context.coordinator.parent = self
        let coord = context.coordinator

        // O(1) gate: only rebuild message-collection config when relevant data changed.
        // Typing indicators, search state, loading flags do NOT affect message cells.
        let needsConfigUpdate =
            messagesVersion != coord.lastMessagesVersion
            || scrollToMessageId != coord.lastScrollToId
            || scrollToBottom != coord.lastScrollToBottom
            || firstUnreadMessageId != coord.lastFirstUnreadId
            || showUnreadDivider != coord.lastShowUnreadDivider
            || participantProfiles.count != coord.lastProfileCount
            || isConversationFrozen != coord.lastIsFrozen

        if needsConfigUpdate {
            var config = MessagesViewController.Configuration()
            config.messages = messages
            config.cellConfigurations = cellConfigurations
            config.participantProfiles = participantProfiles
            config.isGroupConversation = isGroupConversation
            config.totalParticipants = totalParticipants
            config.scrollToMessageId = scrollToMessageId
            config.scrollToBottom = scrollToBottom

            config.firstUnreadMessageId = firstUnreadMessageId
            config.unreadCount = unreadCount
            config.showUnreadDivider = showUnreadDivider

            config.onOverlayAction = onOverlayAction
            config.onSwipeReply = onSwipeReply
            config.onImageTap = onImageTap
            config.onReplyPreviewTap = onReplyPreviewTap
            config.onRetry = onRetry
            config.onReactionTap = onReactionTap
            config.onLoadMore = onLoadMore
            config.onScrolledToBottom = onScrolledToBottom
            config.onUnreadDividerDismissed = onUnreadDividerDismissed

            config.isConversationFrozen = isConversationFrozen
            config.replyCountMap = replyCountMap
            config.onViewThread = { [weak coordinator = context.coordinator] message in
                coordinator?.parent.onViewThread?(message)
            }

            vc.configuration = config

            coord.lastMessagesVersion = messagesVersion
            coord.lastScrollToId = scrollToMessageId
            coord.lastScrollToBottom = scrollToBottom
            coord.lastFirstUnreadId = firstUnreadMessageId
            coord.lastShowUnreadDivider = showUnreadDivider
            coord.lastProfileCount = participantProfiles.count
            coord.lastIsFrozen = isConversationFrozen
        }

        // Input bar state — always update (cheap, independent of message collection)
        let bar = vc.inputBar
        let prevMode = coord.lastInputMode
        if let edit = editingMessage {
            bar.setEditContext(text: edit.text, messageId: edit.id)
            coord.lastInputMode = .editing
        } else if let reply = replyContext {
            bar.setReplyContext(reply)
            coord.lastInputMode = .replying
        } else {
            // Only clear when transitioning OUT of reply/edit mode
            if prevMode == .replying { bar.clearReplyContext() }
            if prevMode == .editing  { bar.clearEditContext() }
            coord.lastInputMode = .normal
        }

        bar.setImagePreview(imageToSend)
    }

    // MARK: - Coordinator

    enum InputMode { case normal, replying, editing }

    class Coordinator: NSObject, MessageInputDelegate {
        var parent: MessagesViewControllerRepresentable
        weak var viewController: MessagesViewController?
        /// Tracks the last input-bar mode so updateUIViewController only
        /// clears reply/edit state on actual mode transitions, not every call.
        var lastInputMode: InputMode = .normal

        // O(1) tracking for message-collection config gating
        var lastMessagesVersion: Int = -1
        var lastScrollToId: UUID?
        var lastScrollToBottom: Bool = false
        var lastFirstUnreadId: UUID?
        var lastShowUnreadDivider: Bool = false
        var lastProfileCount: Int = -1
        var lastIsFrozen: Bool = false

        init(parent: MessagesViewControllerRepresentable) {
            self.parent = parent
        }

        // MARK: Controller Send Handler

        func handleSend(_ payload: InputBarController.SendPayload) {
            if let editId = payload.editMessageId {
                parent.onSendEditedMessage(payload.text, editId)
            } else {
                parent.onSendMessage(payload.text)
            }
        }

        // MARK: MessageInputDelegate

        func inputBar(_ bar: MessageInputAccessoryView, didSendText text: String) {
            parent.onSendMessage(text)
        }

        func inputBar(_ bar: MessageInputAccessoryView, didSendEditedText text: String, messageId: UUID) {
            parent.onSendEditedMessage(text, messageId)
        }

        func inputBarDidRequestImagePicker(_ bar: MessageInputAccessoryView) {
            parent.onImagePickerTapped()
        }

        func inputBarDidRequestCamera(_ bar: MessageInputAccessoryView) {
            viewController?.presentCamera()
        }

        func inputBar(_ bar: MessageInputAccessoryView, didRecordAudio url: URL, duration: Double) {
            parent.onAudioRecorded(url, duration)
        }

        func inputBarDidCancelReply(_ bar: MessageInputAccessoryView) {
            parent.onCancelReply()
        }

        func inputBarDidCancelEdit(_ bar: MessageInputAccessoryView) {
            parent.onCancelEdit()
        }

        func inputBarDidChangeTypingState(_ bar: MessageInputAccessoryView) {
            parent.onTypingChanged()
        }
    }
}
