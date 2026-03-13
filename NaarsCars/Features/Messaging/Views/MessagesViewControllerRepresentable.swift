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
    let cellConfigurations: [UUID: MessageCellConfiguration]
    let participantProfiles: [Profile]
    let isGroupConversation: Bool
    let totalParticipants: Int
    let onLongPress: (Message, CGRect, UIView?) -> Void
    let onSwipeReply: (Message) -> Void
    let onImageTap: (URL) -> Void
    let onReplyPreviewTap: (UUID) -> Void
    let onRetry: (Message) -> Void
    let onReactionTap: (Message, String?) -> Void
    let onLoadMore: () -> Void
    let onScrolledToBottom: (Bool) -> Void
    let scrollToMessageId: UUID?
    let scrollToBottom: Bool

    // MARK: Input Bar Props

    let replyContext: ReplyContext?
    let editingMessage: Message?
    @Binding var imageToSend: UIImage?

    // Input bar callbacks
    let onSendMessage: (String) -> Void
    let onSendEditedMessage: (String, UUID) -> Void
    let onImagePickerTapped: () -> Void
    let onCameraTapped: () -> Void
    let onAudioRecorded: (URL, Double) -> Void
    let onLocationRequested: () -> Void
    let onCancelReply: () -> Void
    let onCancelEdit: () -> Void
    let onTypingChanged: () -> Void

    // MARK: UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MessagesViewController {
        let vc = MessagesViewController()
        vc.inputDelegate = context.coordinator
        context.coordinator.viewController = vc
        return vc
    }

    func updateUIViewController(_ vc: MessagesViewController, context: Context) {
        context.coordinator.parent = self

        var config = MessagesViewController.Configuration()
        config.messages = messages
        config.cellConfigurations = cellConfigurations
        config.participantProfiles = participantProfiles
        config.isGroupConversation = isGroupConversation
        config.totalParticipants = totalParticipants
        config.scrollToMessageId = scrollToMessageId
        config.scrollToBottom = scrollToBottom

        config.onLongPress = onLongPress
        config.onSwipeReply = onSwipeReply
        config.onImageTap = onImageTap
        config.onReplyPreviewTap = onReplyPreviewTap
        config.onRetry = onRetry
        config.onReactionTap = onReactionTap
        config.onLoadMore = onLoadMore
        config.onScrolledToBottom = onScrolledToBottom

        vc.configuration = config

        // Update input bar state
        let bar = vc.inputBar

        // Reply / edit context
        if let edit = editingMessage {
            bar.setEditContext(text: edit.text, messageId: edit.id)
        } else if let reply = replyContext {
            bar.setReplyContext(name: reply.senderName, preview: reply.text)
        } else {
            // Only clear if something was previously showing
            bar.clearReplyContext()
            bar.clearEditContext()
        }

        // Image preview
        bar.setImagePreview(imageToSend)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MessageInputDelegate {
        var parent: MessagesViewControllerRepresentable
        weak var viewController: MessagesViewController?

        init(parent: MessagesViewControllerRepresentable) {
            self.parent = parent
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
            parent.onCameraTapped()
        }

        func inputBar(_ bar: MessageInputAccessoryView, didRecordAudio url: URL, duration: Double) {
            parent.onAudioRecorded(url, duration)
        }

        func inputBar(_ bar: MessageInputAccessoryView, didShareLocation lat: Double, lon: Double, name: String?) {
            // The sentinel (0,0) means "show location picker" — we route to the parent handler
            parent.onLocationRequested()
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
