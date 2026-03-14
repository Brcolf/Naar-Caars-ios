// NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift
import Foundation

/// Configuration passed to MessageCellView for rendering a message.
struct MessageCellConfig {
    let message: Message
    let isFromCurrentUser: Bool
    let showAvatar: Bool
    let isFirstInSeries: Bool
    let isLastInSeries: Bool
    let isGroupConversation: Bool
    let totalParticipants: Int
    let participantProfiles: [Profile]
    let showReplyPreview: Bool
    let replySpine: (showTop: Bool, showBottom: Bool)?
    let isHighlighted: Bool
    let shouldAnimate: Bool
    let replyCount: Int

    /// Derived: whether this message failed to send
    var isFailed: Bool { message.sendStatus == .failed }
}

/// Delegate protocol for message cell interactions.
protocol MessageCellDelegate: AnyObject {
    func messageCellDidLongPress(_ cell: MessageCellView, message: Message)
    func messageCellDidTapReaction(_ cell: MessageCellView, message: Message, reaction: String?)
    func messageCellDidSwipeToReply(_ cell: MessageCellView, message: Message)
    func messageCellDidTapImage(_ cell: MessageCellView, url: URL)
    func messageCellDidTapReplyPreview(_ cell: MessageCellView, replyToId: UUID)
    func messageCellDidTapRetry(_ cell: MessageCellView, message: Message)
    func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message)
}
