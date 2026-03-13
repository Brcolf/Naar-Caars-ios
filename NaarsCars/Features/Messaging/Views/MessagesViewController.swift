//
//  MessagesViewController.swift
//  NaarsCars
//
//  UIViewController that owns the messages collection view and hosts
//  the MessageInputAccessoryView as its inputAccessoryView, enabling
//  interactive keyboard dismissal via keyboardDismissMode = .interactive.
//

import UIKit

final class MessagesViewController: UIViewController {

    // MARK: Public Configuration

    /// All callbacks and data the representable provides.
    struct Configuration {
        var messages: [Message] = []
        var cellConfigurations: [UUID: MessageCellConfiguration] = [:]
        var participantProfiles: [Profile] = []
        var isGroupConversation: Bool = false
        var totalParticipants: Int = 2
        var scrollToMessageId: UUID?
        var scrollToBottom: Bool = false

        // Unread divider
        var firstUnreadMessageId: UUID?
        var unreadCount: Int = 0
        var showUnreadDivider: Bool = false

        // Callbacks (kept as closures to avoid tight coupling to SwiftUI)
        var onOverlayAction: ((OverlayAction, Message) -> Void)?
        var onSwipeReply: ((Message) -> Void)?
        var onImageTap: ((URL) -> Void)?
        var onReplyPreviewTap: ((UUID) -> Void)?
        var onRetry: ((Message) -> Void)?
        var onReactionTap: ((Message, String?) -> Void)?
        var onLoadMore: (() -> Void)?
        var onScrolledToBottom: ((Bool) -> Void)?
        var onUnreadDividerDismissed: (() -> Void)?
    }

    var configuration = Configuration() {
        didSet { applyConfiguration() }
    }

    /// Called when the camera captures an image, so the hosting layer can
    /// keep its own image state in sync (e.g. the SwiftUI `imageToSend` binding).
    var onCameraCapturedImage: ((UIImage) -> Void)?

    let inputBarController = InputBarController()

    weak var inputDelegate: MessageInputDelegate? {
        didSet { inputBar.delegate = inputDelegate }
    }

    /// The input accessory bar — lazily created, returned as the VC's
    /// inputAccessoryView for interactive keyboard support.
    private(set) lazy var inputBar: MessageInputAccessoryView = {
        let bar = MessageInputAccessoryView(controller: inputBarController)
        bar.delegate = inputDelegate
        return bar
    }()

    // MARK: UIViewController inputAccessoryView

    override var inputAccessoryView: UIView? { inputBar }
    override var canBecomeFirstResponder: Bool { true }

    // MARK: Collection View

    private(set) lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        cv.backgroundColor = .clear
        cv.keyboardDismissMode = .interactive
        cv.alwaysBounceVertical = true
        cv.contentInsetAdjustmentBehavior = .automatic
        cv.transform = CGAffineTransform(scaleX: 1, y: -1) // flip for bottom-up
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    // MARK: Data Source

    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
    private var messagesById: [UUID: Message] = [:]
    private var cellConfigurations: [UUID: MessageCellConfiguration] = [:]
    private var dateSeparatorDates: [String: Date] = [:]
    private var lastSnapshotCount = 0
    private var isAtBottom = true
    /// The item identifier for the currently-inserted unread divider, e.g. "unread:3".
    private var unreadDividerItemId: String?
    /// Whether we already performed the initial scroll-to-unread on first load.
    private var didScrollToFirstUnread = false

    private var lastAppliedFingerprint: UpdateFingerprint?

    private struct UpdateFingerprint: Equatable {
        let messageIds: [UUID]
        let configKeys: Set<UUID>
        let scrollToMessageId: UUID?
        let scrollToBottom: Bool
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupDataSource()
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        inputBar.tearDown()
    }

    // MARK: Layout

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

    // MARK: Data Source Setup

    private func setupDataSource() {
        let messageCellRegistration = UICollectionView.CellRegistration<MessageContentCell, String> { [weak self] cell, _, itemId in
            guard let self,
                  let messageId = UUID(uuidString: itemId),
                  let message = self.messagesById[messageId],
                  let cellConfig = self.cellConfigurations[messageId] else { return }

            let currentUserId = AuthService.shared.currentUserId
            let isFromCurrentUser = message.fromId == currentUserId

            let config = MessageCellConfig(
                message: message,
                isFromCurrentUser: isFromCurrentUser,
                showAvatar: self.configuration.isGroupConversation && !isFromCurrentUser,
                isFirstInSeries: cellConfig.isFirstInSeries,
                isLastInSeries: cellConfig.isLastInSeries,
                isGroupConversation: self.configuration.isGroupConversation,
                totalParticipants: self.configuration.totalParticipants,
                participantProfiles: self.configuration.participantProfiles,
                showReplyPreview: message.replyToMessage != nil,
                replySpine: self.replyChainContext(for: message),
                isHighlighted: self.configuration.scrollToMessageId == messageId,
                shouldAnimate: false
            )

            cell.messageCellView.delegate = self
            cell.messageCellView.configure(with: config)
        }

        let dateSeparatorRegistration = UICollectionView.CellRegistration<FlippedDateSeparatorCell, String> { [weak self] cell, _, itemId in
            let date = self?.dateSeparatorDates[itemId] ?? Date()
            cell.dateSeparator.configure(date: date)
        }

        let unreadDividerRegistration = UICollectionView.CellRegistration<FlippedUnreadDividerCell, String> { cell, _, itemId in
            // Extract count from "unread:<count>"
            let count = Int(itemId.replacingOccurrences(of: "unread:", with: "")) ?? 0
            cell.dividerView.configure(count: count)
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { (collectionView, indexPath, itemId) -> UICollectionViewCell? in
            if itemId.hasPrefix("date:") {
                return collectionView.dequeueConfiguredReusableCell(using: dateSeparatorRegistration, for: indexPath, item: itemId)
            } else if itemId.hasPrefix("unread:") {
                return collectionView.dequeueConfiguredReusableCell(using: unreadDividerRegistration, for: indexPath, item: itemId)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: messageCellRegistration, for: indexPath, item: itemId)
            }
        }
    }

    // MARK: Apply Configuration

    private func applyConfiguration() {
        let config = configuration
        messagesById = Dictionary(uniqueKeysWithValues: config.messages.map { ($0.id, $0) })
        cellConfigurations = config.cellConfigurations

        let currentFingerprint = UpdateFingerprint(
            messageIds: config.messages.map(\.id),
            configKeys: Set(config.cellConfigurations.keys),
            scrollToMessageId: config.scrollToMessageId,
            scrollToBottom: config.scrollToBottom
        )
        let messageIdsChanged = currentFingerprint.messageIds != (lastAppliedFingerprint?.messageIds ?? [])
        let fingerprintChanged = currentFingerprint != lastAppliedFingerprint
        lastAppliedFingerprint = currentFingerprint

        if fingerprintChanged && messageIdsChanged {
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])

            let reversed = Array(config.messages.reversed())
            var items: [String] = []
            let calendar = Calendar.current

            for (index, message) in reversed.enumerated() {
                items.append(message.id.uuidString)

                if index < reversed.count - 1 {
                    let nextMessage = reversed[index + 1]
                    if !calendar.isDate(message.createdAt, inSameDayAs: nextMessage.createdAt) {
                        let dayKey = calendar.startOfDay(for: message.createdAt).timeIntervalSinceReferenceDate
                        let separatorId = "date:\(dayKey)"
                        items.append(separatorId)
                        dateSeparatorDates[separatorId] = message.createdAt
                    }
                } else {
                    let dayKey = calendar.startOfDay(for: message.createdAt).timeIntervalSinceReferenceDate
                    let separatorId = "date:\(dayKey)"
                    items.append(separatorId)
                    dateSeparatorDates[separatorId] = message.createdAt
                }
            }

            let currentSeparatorIds = Set(items.filter { $0.hasPrefix("date:") })
            dateSeparatorDates = dateSeparatorDates.filter { currentSeparatorIds.contains($0.key) }

            // Insert unread divider if applicable
            let shouldInsertDivider = config.showUnreadDivider && config.unreadCount > 0 && config.firstUnreadMessageId != nil
            var unreadItemId: String?
            if shouldInsertDivider, let firstUnreadId = config.firstUnreadMessageId {
                let targetItemId = firstUnreadId.uuidString
                if items.contains(targetItemId) {
                    let divId = "unread:\(config.unreadCount)"
                    // In the reversed/flipped list, the unread divider goes *after* the
                    // first-unread message item (which visually appears *above* it).
                    if let idx = items.firstIndex(of: targetItemId) {
                        items.insert(divId, at: idx + 1)
                    }
                    unreadItemId = divId
                } else {
                    // Fallback: find the next chronologically-later message (earlier in the reversed list)
                    let chronological = config.messages
                    if let fallbackIdx = chronological.firstIndex(where: { $0.id == firstUnreadId }) {
                        // Try messages after it in chronological order (reversed = before in items)
                        var fallbackItemId: String?
                        for i in stride(from: fallbackIdx + 1, to: chronological.count, by: 1) {
                            let candidateId = chronological[i].id.uuidString
                            if items.contains(candidateId) {
                                fallbackItemId = candidateId
                                break
                            }
                        }
                        if let fallback = fallbackItemId {
                            let divId = "unread:\(config.unreadCount)"
                            // In reversed list, chronologically-later messages come before,
                            // so insert the divider after the fallback item.
                            if let idx = items.firstIndex(of: fallback) {
                                items.insert(divId, at: idx + 1)
                            }
                            unreadItemId = divId
                        }
                    }
                }
            }
            self.unreadDividerItemId = unreadItemId

            snapshot.appendItems(items, toSection: 0)

            let isInitialLoad = lastSnapshotCount == 0 && !config.messages.isEmpty
            let isPagination = config.messages.count > lastSnapshotCount && lastSnapshotCount > 0
            let isSingleNewMessage = config.messages.count == lastSnapshotCount + 1 && lastSnapshotCount > 0
            lastSnapshotCount = config.messages.count

            if isInitialLoad || isPagination || !isSingleNewMessage {
                dataSource?.apply(snapshot, animatingDifferences: false)
            } else {
                dataSource?.apply(snapshot, animatingDifferences: true)
            }

            // On initial load with unread messages, scroll to the first unread
            if isInitialLoad && !didScrollToFirstUnread,
               let firstUnreadId = config.firstUnreadMessageId,
               config.showUnreadDivider {
                didScrollToFirstUnread = true
                let scrollTarget = firstUnreadId.uuidString
                if let indexPath = dataSource?.indexPath(for: scrollTarget) {
                    // Slight delay to let the layout settle after initial snapshot apply
                    DispatchQueue.main.async { [weak self] in
                        self?.collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
                    }
                }
            }
        }

        // Reconfigure visible cells for content-only changes
        let isInitialLoad = lastSnapshotCount == 0
        if !isInitialLoad, let dataSource {
            let visibleIds = collectionView.indexPathsForVisibleItems.compactMap {
                dataSource.itemIdentifier(for: $0)
            }.filter { !$0.hasPrefix("date:") && !$0.hasPrefix("unread:") }
            if !visibleIds.isEmpty {
                var reconfigureSnapshot = dataSource.snapshot()
                reconfigureSnapshot.reconfigureItems(visibleIds)
                dataSource.apply(reconfigureSnapshot, animatingDifferences: false)
            }
        }

        // Handle scroll-to-message
        if let targetId = config.scrollToMessageId {
            if let indexPath = dataSource?.indexPath(for: targetId.uuidString) {
                collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
            }
        }

        // Handle scroll-to-bottom
        if config.scrollToBottom && !config.messages.isEmpty {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
        }
    }

    // MARK: Reply Chain Context

    private func replyChainContext(for message: Message) -> (showTop: Bool, showBottom: Bool)? {
        guard let replyToId = message.replyToId else { return nil }
        let messages = configuration.messages
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return nil }

        let hasPrevious = index > 0 && messages[index - 1].replyToId == replyToId
        let hasNext = index < messages.count - 1 && messages[index + 1].replyToId == replyToId
        return (showTop: hasPrevious, showBottom: hasNext)
    }
}

// MARK: - UICollectionViewDelegate

extension MessagesViewController: UICollectionViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.height

        let wasAtBottom = isAtBottom
        isAtBottom = offsetY < 50

        if wasAtBottom != isAtBottom {
            configuration.onScrolledToBottom?(isAtBottom)
        }

        if contentHeight > frameHeight && offsetY > contentHeight - frameHeight - 200 {
            configuration.onLoadMore?()
        }

        // Dismiss unread divider when the user reaches the bottom (all unreads scrolled past)
        if isAtBottom {
            dismissUnreadDividerIfNeeded()
        }
    }

    private func dismissUnreadDividerIfNeeded() {
        guard let dividerId = unreadDividerItemId, let dataSource else { return }
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(dividerId) else { return }
        snapshot.deleteItems([dividerId])
        unreadDividerItemId = nil
        dataSource.apply(snapshot, animatingDifferences: true)
        configuration.onUnreadDividerDismissed?()
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension MessagesViewController: UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        let maxIndex = indexPaths.map { $0.item }.max() ?? 0
        if itemCount > 0 && maxIndex >= itemCount - 2 {
            configuration.onLoadMore?()
        }
    }
}

// MARK: - MessageCellDelegate

extension MessagesViewController: MessageCellDelegate {

    func messageCellDidLongPress(_ cell: MessageCellView, message: Message) {
        let cellFrame = cell.convert(cell.bounds, to: nil)
        guard let snapshot = cell.snapshotView(afterScreenUpdates: false) else { return }

        let isFromCurrentUser = message.fromId == AuthService.shared.currentUserId
        let currentReaction = message.reactions?.currentUserReaction(
            userId: AuthService.shared.currentUserId ?? UUID()
        )

        let overlay = MessageOverlayController(
            snapshot: snapshot,
            sourceFrame: cellFrame,
            message: message,
            isFromCurrentUser: isFromCurrentUser,
            currentUserReaction: currentReaction,
            onAction: { [weak self] action in
                self?.configuration.onOverlayAction?(action, message)
            }
        )
        present(overlay, animated: false)
    }

    func messageCellDidTapReaction(_ cell: MessageCellView, message: Message, reaction: String?) {
        configuration.onReactionTap?(message, reaction)
    }

    func messageCellDidSwipeToReply(_ cell: MessageCellView, message: Message) {
        configuration.onSwipeReply?(message)
    }

    func messageCellDidTapImage(_ cell: MessageCellView, url: URL) {
        configuration.onImageTap?(url)
    }

    func messageCellDidTapReplyPreview(_ cell: MessageCellView, replyToId: UUID) {
        configuration.onReplyPreviewTap?(replyToId)
    }

    func messageCellDidTapRetry(_ cell: MessageCellView, message: Message) {
        configuration.onRetry?(message)
    }
}

// MARK: - Camera Presentation

extension MessagesViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    /// Presents the system camera for capturing a photo.
    func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        inputBarController.setImage(image)
        onCameraCapturedImage?(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
