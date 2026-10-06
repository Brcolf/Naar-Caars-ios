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
    private var layoutInvalidationWork: DispatchWorkItem?

    /// Cache key for height lookup — set by cell provider, used by preferredLayoutAttributesFitting.
    var heightCacheKey: String?
    /// Closure to look up cached height — set by cell provider, avoids direct VC coupling.
    var heightCacheLookup: ((String) -> CGFloat?)?
    /// Closure to store computed height — set by cell provider.
    var heightCacheStore: ((CGFloat, String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(messageCellView)
        // Counter-flip: the collection view uses scaleY: -1
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)

        messageCellView.onIntrinsicSizeChanged = { [weak self] in
            guard let self else { return }
            // Debounce rapid-fire size changes into a single layout pass
            self.layoutInvalidationWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let collectionView = self.superview as? UICollectionView else { return }
                collectionView.collectionViewLayout.invalidateLayout()
            }
            self.layoutInvalidationWork = work
            DispatchQueue.main.async(execute: work)
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
        let width = layoutAttributes.frame.width

        // Check height cache before expensive sizeThatFits measurement
        if let key = heightCacheKey, let cached = heightCacheLookup?(key) {
            attrs.frame.size.height = cached
            return attrs
        }

        let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let fittingSize = messageCellView.sizeThatFits(targetSize)
        attrs.frame.size.height = fittingSize.height

        // Store in cache for next layout pass
        if let key = heightCacheKey {
            heightCacheStore?(fittingSize.height, key)
        }
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

/// Flipped wrapper for UnreadDividerView so it renders correctly in
/// the bottom-up (scaleY: -1) collection view.
final class FlippedUnreadDividerCell: UICollectionViewCell {

    let dividerView = UnreadDividerView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(dividerView)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        dividerView.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dividerView.prepareForReuse()
    }
}

/// iMessage-style typing bubble, shown as the newest item of the transcript: a grey bubble
/// with three pulsing dots on the incoming side (with the typer's avatar in group threads).
/// Flipped like the other cells because the list uses scaleY: -1.
final class FlippedTypingIndicatorCell: UICollectionViewCell {

    /// Diffable item identifier for the single typing item.
    static let itemIdentifier = "typing"
    static let fixedHeight: CGFloat = 44

    private let bubble = UIView()
    private let dots = CAReplicatorLayer()
    private let dot = CALayer()
    private let avatarView = AvatarUIView()
    private var showsAvatar = false

    private let dotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 5
    private let bubbleSize = CGSize(width: 62, height: 36)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)

        avatarView.isHidden = true
        contentView.addSubview(avatarView)

        bubble.layer.cornerRadius = 18
        bubble.layer.cornerCurve = .continuous
        contentView.addSubview(bubble)

        dot.cornerRadius = dotSize / 2
        dots.instanceCount = 3
        dots.instanceTransform = CATransform3DMakeTranslation(dotSize + dotSpacing, 0, 0)
        dots.instanceDelay = 0.2
        dots.addSublayer(dot)
        bubble.layer.addSublayer(dots)
        applyColors()

        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently
        accessibilityIdentifier = "messages.thread.typingIndicator"
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(typingUsers: [TypingUser], showsAvatar: Bool) {
        self.showsAvatar = showsAvatar && !typingUsers.isEmpty
        avatarView.isHidden = !self.showsAvatar
        if self.showsAvatar, let first = typingUsers.first {
            avatarView.configure(imageUrl: first.avatarUrl, name: first.name, size: 28)
        }
        accessibilityLabel = Self.accessibilityText(for: typingUsers)
        setNeedsLayout()
        startAnimatingIfNeeded()
    }

    static func accessibilityText(for typingUsers: [TypingUser]) -> String {
        switch typingUsers.count {
        case 0:
            return ""
        case 1:
            return "messaging_typing_single".localized(with: typingUsers[0].name)
        case 2:
            return "messaging_typing_two".localized(with: typingUsers[0].name, typingUsers[1].name)
        case 3:
            return "messaging_typing_three".localized(with: typingUsers[0].name, typingUsers[1].name)
        default:
            return "messaging_typing_many".localized(with: typingUsers[0].name, typingUsers[1].name, typingUsers.count - 2)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        let bubbleY = (b.height - bubbleSize.height) / 2
        let bubbleX: CGFloat = showsAvatar ? 28 + 8 : 0
        avatarView.frame = CGRect(x: 0, y: bubbleY + bubbleSize.height - 28, width: 28, height: 28)
        bubble.frame = CGRect(origin: CGPoint(x: bubbleX, y: bubbleY), size: bubbleSize)

        let dotsWidth = dotSize * 3 + dotSpacing * 2
        dots.frame = CGRect(
            x: (bubbleSize.width - dotsWidth) / 2,
            y: (bubbleSize.height - dotSize) / 2,
            width: dotsWidth,
            height: dotSize
        )
        dot.frame = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.size.height = Self.fixedHeight
        return attributes
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Core Animation drops running animations when a layer leaves the window.
        if window != nil { startAnimatingIfNeeded() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        dot.removeAnimation(forKey: Self.pulseKey)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors() // CALayer colours do not follow dynamic UIColors on their own
    }

    private static let pulseKey = "typingPulse"

    private func applyColors() {
        bubble.backgroundColor = .systemGray5
        dot.backgroundColor = UIColor.systemGray.cgColor
    }

    private func startAnimatingIfNeeded() {
        guard dot.animation(forKey: Self.pulseKey) == nil else { return }
        guard !UIAccessibility.isReduceMotionEnabled else {
            dot.opacity = 0.6
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.3
        pulse.toValue = 1.0
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        dot.opacity = 0.3
        dot.add(pulse, forKey: Self.pulseKey)
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

        // Always update the backing data so visible cells see fresh content
        // (reactions, read receipts, etc.) even when the message list structure
        // hasn't changed.
        coordinator.messagesById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        coordinator.cellConfigurations = cellConfigurations

        // Fast path: skip expensive snapshot rebuild if structure is unchanged.
        let currentFingerprint = Coordinator.UpdateFingerprint(
            messageIds: messages.map(\.id),
            configKeys: Set(cellConfigurations.keys),
            scrollToMessageId: scrollToMessageId,
            scrollToBottom: scrollToBottom
        )
        let messageIdsChanged = currentFingerprint.messageIds != (coordinator.lastAppliedFingerprint?.messageIds ?? [])
        let fingerprintChanged = currentFingerprint != coordinator.lastAppliedFingerprint
        coordinator.lastAppliedFingerprint = currentFingerprint

        // Only rebuild the snapshot when the message list structure changed
        // (messages added/removed). Content-only changes (reactions, read receipts)
        // are handled by the reconfigure path below.
        if fingerprintChanged && messageIdsChanged {
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

            // Prune stale date separator entries not in current snapshot
            let currentSeparatorIds = Set(items.filter { $0.hasPrefix("date:") })
            coordinator.dateSeparatorDates = coordinator.dateSeparatorDates.filter { currentSeparatorIds.contains($0.key) }

            snapshot.appendItems(items, toSection: 0)

            let isInitialLoad = coordinator.lastSnapshotCount == 0 && !messages.isEmpty
            let isPagination = messages.count > coordinator.lastSnapshotCount && coordinator.lastSnapshotCount > 0
            let isSingleNewMessage = messages.count == coordinator.lastSnapshotCount + 1 && coordinator.lastSnapshotCount > 0
            coordinator.lastSnapshotCount = messages.count

            if isInitialLoad || isPagination || !isSingleNewMessage {
                coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
            } else {
                coordinator.dataSource?.apply(snapshot, animatingDifferences: true)
            }
        }

        // Reconfigure visible message cells to pick up content changes
        // (reactions, read receipts) that don't alter the snapshot structure.
        let isInitialLoad = coordinator.lastSnapshotCount == 0
        if !isInitialLoad, let dataSource = coordinator.dataSource {
            let visibleIds = collectionView.indexPathsForVisibleItems.compactMap {
                dataSource.itemIdentifier(for: $0)
            }.filter { !$0.hasPrefix("date:") }
            if !visibleIds.isEmpty {
                var reconfigureSnapshot = dataSource.snapshot()
                reconfigureSnapshot.reconfigureItems(visibleIds)
                dataSource.apply(reconfigureSnapshot, animatingDifferences: false)
            }
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

        /// Fingerprint of the last applied update, used to skip no-op updateUIView calls.
        var lastAppliedFingerprint: UpdateFingerprint?

        struct UpdateFingerprint: Equatable {
            let messageIds: [UUID]
            let configKeys: Set<UUID>
            let scrollToMessageId: UUID?
            let scrollToBottom: Bool
        }

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
                    isHighlighted: self.parent.scrollToMessageId == messageId,
                    shouldAnimate: false,
                    replyCount: 0
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

        func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message) {
            // Not used -- MessagesViewController is the production path
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
