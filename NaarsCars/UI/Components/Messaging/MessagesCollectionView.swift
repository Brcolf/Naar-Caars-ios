//
//  MessagesCollectionView.swift
//  NaarsCars
//
//  UICollectionView wrapper for the message list, providing perfect scroll
//  position maintenance during top-insertion (pagination) and smooth
//  animated updates via NSDiffableDataSourceSnapshot.
//
//  Layer 3: Performance-critical swap — native UIKit cells replace UIHostingConfiguration.
//

import SwiftUI
import UIKit

// MessageCellConfiguration and MessageListItem are defined in MessageListItem.swift
// to avoid @MainActor inference from UIViewRepresentable.

/// Cell that hosts a `MessageCellView` in its `contentView`.
/// Applies the counter-flip so content is right-side up inside the flipped collection view.
final class MessageContentCell: UICollectionViewCell {

    let messageCellView = MessageCellView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(messageCellView)
        // Counter-flip: the collection view uses scaleY: -1
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)

        messageCellView.onIntrinsicSizeChanged = { [weak self] in
            guard let self, let collectionView = self.superview as? UICollectionView else { return }
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        messageCellView.frame = contentView.bounds
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attrs = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetSize = CGSize(width: layoutAttributes.frame.width, height: UIView.layoutFittingCompressedSize.height)
        let fittingSize = messageCellView.sizeThatFits(targetSize)
        attrs.frame.size.height = fittingSize.height
        return attrs
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageCellView.prepareForReuse()
    }
}

/// Cell wrapper for `DateSeparatorCell` that applies the counter-flip.
final class FlippedDateSeparatorCell: UICollectionViewCell {

    let dateSeparator = DateSeparatorCell()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(dateSeparator)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        dateSeparator.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dateSeparator.prepareForReuse()
    }
}

/// UIViewRepresentable wrapping UICollectionView for the messages list
struct MessagesCollectionView: UIViewRepresentable {
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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = createLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .automatic

        // Transform so messages grow from bottom
        collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)

        context.coordinator.setupDataSource(collectionView: collectionView)
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator

        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Store messages for the data source
        coordinator.messagesById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        coordinator.cellConfigurations = cellConfigurations

        // Build interleaved snapshot with date separators.
        // Items are String-typed: UUID strings for messages, "date:<timeInterval>" for separators.
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])

        // Messages are in chronological order; reverse for the flipped collection view
        let reversed = Array(messages.reversed())
        var items: [String] = []
        let calendar = Calendar.current

        for (index, message) in reversed.enumerated() {
            items.append(message.id.uuidString)

            // Insert date separator between messages that span different calendar days.
            // In the reversed array, the next element is the chronologically earlier message.
            if index < reversed.count - 1 {
                let nextMessage = reversed[index + 1]
                if !calendar.isDate(message.createdAt, inSameDayAs: nextMessage.createdAt) {
                    let dayKey = calendar.startOfDay(for: message.createdAt).timeIntervalSinceReferenceDate
                    let separatorId = "date:\(dayKey)"
                    items.append(separatorId)
                    coordinator.dateSeparatorDates[separatorId] = message.createdAt
                }
            } else {
                // Always show a date separator above the oldest message
                let dayKey = calendar.startOfDay(for: message.createdAt).timeIntervalSinceReferenceDate
                let separatorId = "date:\(dayKey)"
                items.append(separatorId)
                coordinator.dateSeparatorDates[separatorId] = message.createdAt
            }
        }

        snapshot.appendItems(items, toSection: 0)

        let isInitialLoad = coordinator.lastSnapshotCount == 0 && !messages.isEmpty
        let isPagination = messages.count > coordinator.lastSnapshotCount && coordinator.lastSnapshotCount > 0
        let isSingleNewMessage = messages.count == coordinator.lastSnapshotCount + 1 && coordinator.lastSnapshotCount > 0
        coordinator.lastSnapshotCount = messages.count

        if isInitialLoad {
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        } else if isPagination || !isSingleNewMessage {
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        } else {
            coordinator.dataSource?.apply(snapshot, animatingDifferences: true)
        }

        // Handle scroll-to-message
        if let targetId = scrollToMessageId {
            if let indexPath = coordinator.dataSource?.indexPath(for: targetId.uuidString) {
                collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
            }
        }

        // Handle scroll-to-bottom
        if scrollToBottom && !messages.isEmpty {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
        }
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(60)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(60)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, MessageCellDelegate {
        var parent: MessagesCollectionView
        var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        var messagesById: [UUID: Message] = [:]
        var cellConfigurations: [UUID: MessageCellConfiguration] = [:]
        var dateSeparatorDates: [String: Date] = [:]
        var lastSnapshotCount = 0
        private var isAtBottom = true

        init(parent: MessagesCollectionView) {
            self.parent = parent
        }

        func setupDataSource(collectionView: UICollectionView) {
            // Register message content cell (item is a UUID string)
            let messageCellRegistration = UICollectionView.CellRegistration<MessageContentCell, String> { [weak self] cell, indexPath, itemId in
                guard let self,
                      let messageId = UUID(uuidString: itemId),
                      let message = self.messagesById[messageId],
                      let cellConfig = self.cellConfigurations[messageId] else { return }

                let currentUserId = AuthService.shared.currentUserId
                let isFromCurrentUser = message.fromId == currentUserId

                // Build MessageCellConfig from MessageCellConfiguration + extra data
                let config = MessageCellConfig(
                    message: message,
                    isFromCurrentUser: isFromCurrentUser,
                    showAvatar: self.parent.isGroupConversation && !isFromCurrentUser,
                    isFirstInSeries: cellConfig.isFirstInSeries,
                    isLastInSeries: cellConfig.isLastInSeries,
                    isGroupConversation: self.parent.isGroupConversation,
                    totalParticipants: self.parent.totalParticipants,
                    participantProfiles: self.parent.participantProfiles,
                    showReplyPreview: message.replyToMessage != nil,
                    replySpine: self.replyChainContext(for: message),
                    isHighlighted: false,
                    shouldAnimate: false
                )

                cell.messageCellView.delegate = self
                cell.messageCellView.configure(with: config)
            }

            // Register date separator cell (item is "date:<timeInterval>")
            let dateSeparatorRegistration = UICollectionView.CellRegistration<FlippedDateSeparatorCell, String> { [weak self] cell, indexPath, itemId in
                let date = self?.dateSeparatorDates[itemId] ?? Date()
                cell.dateSeparator.configure(date: date)
            }

            dataSource = UICollectionViewDiffableDataSource<Int, String>(
                collectionView: collectionView
            ) { (collectionView: UICollectionView, indexPath: IndexPath, itemId: String) -> UICollectionViewCell? in
                if itemId.hasPrefix("date:") {
                    return collectionView.dequeueConfiguredReusableCell(using: dateSeparatorRegistration, for: indexPath, item: itemId)
                } else {
                    return collectionView.dequeueConfiguredReusableCell(using: messageCellRegistration, for: indexPath, item: itemId)
                }
            }
        }

        // MARK: - Reply Chain Context

        /// Compute reply-spine visibility for a message based on adjacent messages sharing the same replyToId.
        private func replyChainContext(for message: Message) -> (showTop: Bool, showBottom: Bool)? {
            guard let replyToId = message.replyToId else { return nil }
            let messages = parent.messages
            guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return nil }

            let hasPrevious = index > 0 && messages[index - 1].replyToId == replyToId
            let hasNext = index < messages.count - 1 && messages[index + 1].replyToId == replyToId

            return (showTop: hasPrevious, showBottom: hasNext)
        }

        // MARK: - MessageCellDelegate

        func messageCellDidLongPress(_ cell: MessageCellView, message: Message) {
            // Capture cell frame in window coordinates (accounts for flipped transforms)
            let cellFrame = cell.convert(cell.bounds, to: nil)
            let snapshot = cell.snapshotView(afterScreenUpdates: false)
            parent.onLongPress(message, cellFrame, snapshot)
        }

        func messageCellDidTapReaction(_ cell: MessageCellView, message: Message, reaction: String?) {
            parent.onReactionTap(message, reaction)
        }

        func messageCellDidSwipeToReply(_ cell: MessageCellView, message: Message) {
            parent.onSwipeReply(message)
        }

        func messageCellDidTapImage(_ cell: MessageCellView, url: URL) {
            parent.onImageTap(url)
        }

        func messageCellDidTapReplyPreview(_ cell: MessageCellView, replyToId: UUID) {
            parent.onReplyPreviewTap(replyToId)
        }

        func messageCellDidTapRetry(_ cell: MessageCellView, message: Message) {
            parent.onRetry(message)
        }

        // MARK: - UICollectionViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let frameHeight = scrollView.frame.height

            // Since the view is flipped, "bottom" (newest messages) is at offset 0
            let wasAtBottom = isAtBottom
            isAtBottom = offsetY < 50

            if wasAtBottom != isAtBottom {
                parent.onScrolledToBottom(isAtBottom)
            }

            // Trigger pagination when scrolling near the "top" (oldest messages)
            // In flipped view, the top is at the maximum content offset
            if contentHeight > frameHeight && offsetY > contentHeight - frameHeight - 200 {
                parent.onLoadMore()
            }
        }

        // MARK: - UICollectionViewDataSourcePrefetching

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            // Only trigger load-more when very close to end (oldest) to avoid duplicate calls with scrollViewDidScroll
            let itemCount = collectionView.numberOfItems(inSection: 0)
            let maxIndex = indexPaths.map { $0.item }.max() ?? 0
            if itemCount > 0 && maxIndex >= itemCount - 2 {
                parent.onLoadMore()
            }
        }
    }
}
