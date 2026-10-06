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

        // Frozen state
        var isConversationFrozen: Bool = false

        // Callbacks (kept as closures to avoid tight coupling to SwiftUI)
        var onOverlayAction: ((OverlayAction, Message) -> Void)?
        var onSwipeReply: ((Message) -> Void)?
        var onImageTap: ((URL) -> Void)?
        var onReplyPreviewTap: ((UUID) -> Void)?
        var onRetry: ((Message) -> Void)?
        var onReactionTap: ((Message, String?) -> Void)?
        var onViewThread: ((Message) -> Void)?
        var onLoadMore: (() -> Void)?
        var onScrolledToBottom: ((Bool) -> Void)?
        var onUnreadDividerDismissed: (() -> Void)?

        var replyCountMap: [UUID: Int] = [:]
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
        bar.onGeometryChange = { [weak self] in
            self?.updateComposerOverlapInset()
        }
        return bar
    }()

    // MARK: UIViewController inputAccessoryView

    override var inputAccessoryView: UIView? { inputBar }
    override var canBecomeFirstResponder: Bool { !isComposerSuppressed }

    /// True while a full-screen cover (reply thread, image viewer) sits on top of this
    /// conversation. The composer is an inputAccessoryView: it lives in the keyboard window, so
    /// while this controller stays first responder it remains docked on top of the cover (the
    /// reply thread then showed two composers). Suppressing gives up first responder; clearing
    /// it takes first responder back, which brings the composer back.
    private(set) var isComposerSuppressed = false

    func setComposerSuppressed(_ suppressed: Bool) {
        guard suppressed != isComposerSuppressed else { return }
        isComposerSuppressed = suppressed
        if suppressed {
            inputBar.endEditing(true)
            resignFirstResponder()
        } else if viewIfLoaded?.window != nil, !becomeFirstResponder() {
            // A dismissal still in flight (the photo picker, the in-thread search field) can
            // refuse the request, and nothing else asks again: the thread would be left
            // without a composer. Try once more when the transition has had time to finish.
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Animation.long) { [weak self] in
                guard let self,
                      !self.isComposerSuppressed,
                      !self.isFirstResponder,
                      !self.inputBar.isEditingText,
                      self.viewIfLoaded?.window != nil else { return }
                self.becomeFirstResponder()
            }
        }
    }

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

    /// Members currently typing; drives the typing bubble item. Set through `setTypingUsers`.
    private(set) var typingUsers: [TypingUser] = []
    private var isTypingItemVisible: Bool {
        !typingUsers.isEmpty && !configuration.isConversationFrozen
    }

    private var lastAppliedFingerprint: UpdateFingerprint?
    /// The newest message from the current user; only its cell shows the delivery status.
    private var lastOutgoingMessageId: UUID?
    /// The participant count the delivery status was last drawn with (see applyConfiguration).
    private var lastAppliedTotalParticipants: Int?
    /// Central height cache: avoids repeated sizeThatFits in preferredLayoutAttributesFitting.
    /// Key: "messageId:width:contentHash". Invalidated on structural snapshot changes.
    private var heightCache: [String: CGFloat] = [:]
    /// Previous message state for targeted reconfigure — only reconfigure cells whose content changed.
    private var previousMessages: [UUID: Message] = [:]
    /// The scroll target already honoured, so a reconfigure (new message, receipt,
    /// reaction) does not yank the list back to it while it remains in the config.
    private var lastScrolledToMessageId: UUID?

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
        observeKeyboardTransitions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        updateComposerOverlapInset()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateComposerOverlapInset()
    }

    // MARK: Composer overlap

    /// True between a keyboard will-change and did-change notification. While the keyboard
    /// animates, the list frame and the bar frame are not updated together, so the overlap is
    /// only allowed to shrink during a transition and is re-measured when it ends.
    private var isKeyboardTransitioning = false

    private func observeKeyboardTransitions() {
        // Selector-based observers are unregistered automatically when the controller deallocates.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillChangeFrame),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardDidChangeFrame),
                           name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    @objc private func keyboardWillChangeFrame() {
        isKeyboardTransitioning = true
        // Safety net: never stay "transitioning" if the matching did-change is not delivered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isKeyboardTransitioning else { return }
            self.isKeyboardTransitioning = false
            self.updateComposerOverlapInset()
        }
    }

    @objc private func keyboardDidChangeFrame() {
        isKeyboardTransitioning = false
        updateComposerOverlapInset()
    }

    /// Keep the newest message clear of the docked input bar.
    ///
    /// SwiftUI's keyboard avoidance normally ends this controller's view at the top of the bar
    /// (the accessory view counts as keyboard height). On the first presentation after launch
    /// it is not told about the accessory, the list keeps running underneath the composer, and
    /// the newest message stayed hidden until the user touched the list (2026-10-05 trace:
    /// list frame 113…818, bar top 764, zero insets). Measure the real overlap in screen
    /// coordinates and reserve it as content inset; it is zero whenever SwiftUI has already
    /// resized the view, so the two mechanisms never add up.
    private func updateComposerOverlapInset() {
        guard isViewLoaded, let window = view.window, inputBar.window != nil else { return }
        let screenSpace = window.screen.coordinateSpace
        let listFrame = view.convert(collectionView.frame, to: screenSpace)
        let barFrame = inputBar.convert(inputBar.bounds, to: screenSpace)
        // Right after attachment UIKit has not sized or positioned the bar yet (a zero-size
        // frame at the centre of the screen); measuring then produced a one-frame 392 pt inset.
        guard barFrame.width > 1, barFrame.height > 1 else { return }
        let overlap = max(0, min(listFrame.maxY - barFrame.minY, listFrame.height))

        // The list is flipped (scaleY: -1): its content-inset *top* is the visual bottom.
        let current = collectionView.contentInset.top
        guard abs(current - overlap) > 0.5 else { return }
        if overlap > current && isKeyboardTransitioning { return }
        // A modal on top (alert, bubble overlay, sheet) or a full-screen cover takes the bar
        // away only for as long as it is up. Shrinking the inset then made the transcript drop
        // by the bar's height and jump back on dismissal; keep it until the bar is back.
        if overlap < current && (presentedViewController != nil || isComposerSuppressed) { return }

        let wasAtNewest = collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
        collectionView.contentInset.top = overlap
        collectionView.verticalScrollIndicatorInsets.top = overlap
        if wasAtNewest {
            let restOffsetY = -collectionView.adjustedContentInset.top
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: restOffsetY), animated: false)
        }
        debugLogGeometry("composerOverlap=\(Int(overlap)) bar=(\(Int(barFrame.minX)),\(Int(barFrame.minY)),\(Int(barFrame.width)),\(Int(barFrame.height))) barSuperview=\(type(of: inputBar.superview as Any)) kbTransition=\(isKeyboardTransitioning)")
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
                shouldAnimate: false,
                replyCount: self.configuration.replyCountMap[messageId] ?? 0,
                isLastOutgoingMessage: messageId == self.lastOutgoingMessageId
            )

            // Wire height cache — avoids duplicate sizeThatFits in preferredLayoutAttributesFitting
            let isLastOutgoing = messageId == self.lastOutgoingMessageId
            cell.heightCacheKey = self.heightCacheKey(messageId: messageId, width: self.collectionView.bounds.width, message: message)
                + (isLastOutgoing ? ":lo" : "")
            cell.heightCacheLookup = { [weak self] key in self?.cachedHeight(for: key) }
            cell.heightCacheStore = { [weak self] h, key in self?.storeHeight(h, for: key) }

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

        let typingRegistration = UICollectionView.CellRegistration<FlippedTypingIndicatorCell, String> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(typingUsers: self.typingUsers, showsAvatar: self.configuration.isGroupConversation)
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { (collectionView, indexPath, itemId) -> UICollectionViewCell? in
            if itemId == FlippedTypingIndicatorCell.itemIdentifier {
                return collectionView.dequeueConfiguredReusableCell(using: typingRegistration, for: indexPath, item: itemId)
            } else if itemId.hasPrefix("date:") {
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

        // Always update content lookups — cell provider reads from these
        messagesById = Dictionary(uniqueKeysWithValues: config.messages.map { ($0.id, $0) })
        cellConfigurations = config.cellConfigurations
        let currentUserId = AuthService.shared.currentUserId
        let previousLastOutgoingId = lastOutgoingMessageId
        // The delivery status belongs under the newest message the user actually sent: an unsent
        // tombstone or a system line recorded under their id does not carry it.
        lastOutgoingMessageId = config.messages.last(where: {
            $0.fromId == currentUserId && !$0.isUnsent && $0.messageType != .system
        })?.id

        let currentFingerprint = UpdateFingerprint(
            messageIds: config.messages.map(\.id),
            configKeys: Set(config.cellConfigurations.keys),
            scrollToMessageId: config.scrollToMessageId,
            scrollToBottom: config.scrollToBottom
        )

        let messageIdsChanged = currentFingerprint.messageIds != (lastAppliedFingerprint?.messageIds ?? [])
        lastAppliedFingerprint = currentFingerprint

        // Snapshot rebuild — only when message list structure changed
        if messageIdsChanged {
            heightCache.removeAll(keepingCapacity: true)
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])

            let reversed = Array(config.messages.reversed())
            var items: [String] = []
            let calendar = Calendar.current

            for (index, message) in reversed.enumerated() {
                items.append(message.id.uuidString)

                // Time header (iMessage): above the oldest loaded message, on a day change, and
                // whenever more than an hour passed since the previous message. Keyed by the
                // message it precedes so several headers can exist within one day.
                let needsTimeHeader: Bool
                if index < reversed.count - 1 {
                    let olderMessage = reversed[index + 1]
                    needsTimeHeader = !calendar.isDate(message.createdAt, inSameDayAs: olderMessage.createdAt)
                        || message.createdAt.timeIntervalSince(olderMessage.createdAt) >= Constants.Timing.messageTimeHeaderGap
                } else {
                    needsTimeHeader = true
                }
                if needsTimeHeader {
                    let separatorId = "date:\(message.id.uuidString)"
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

            // The typing bubble is the newest item of the transcript (index 0 in this
            // reversed list). Added last so the index arithmetic above is unaffected.
            if isTypingItemVisible {
                items.insert(FlippedTypingIndicatorCell.itemIdentifier, at: 0)
            }

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

            // On initial load with unread messages, scroll to the first unread — but only when
            // there really are unread messages (the first-unread id is computed once from the
            // local cache and can be stale after the server marked them read).
            if isInitialLoad && !didScrollToFirstUnread,
               let firstUnreadId = config.firstUnreadMessageId,
               config.showUnreadDivider {
                didScrollToFirstUnread = true
                if config.unreadCount > 0 {
                    // The divider sits visually above the first unread message; target it so
                    // "N New Messages" is on screen rather than just above the fold.
                    let scrollTarget = unreadItemId ?? firstUnreadId.uuidString
                    // Slight delay to let the layout settle after initial snapshot apply
                    DispatchQueue.main.async { [weak self] in
                        self?.scrollToFirstUnread(itemId: scrollTarget)
                    }
                }
            }
        }

        // Targeted reconfigure — only reconfigure visible cells whose content actually changed.
        // Compares only visible items (not full message list) to keep this O(visible), not O(N).
        let isInitialLoad = lastSnapshotCount == 0
        if !isInitialLoad, !messageIdsChanged, let dataSource {
            let visibleItemIds = collectionView.indexPathsForVisibleItems.compactMap {
                dataSource.itemIdentifier(for: $0)
            }.filter { !$0.hasPrefix("date:") && !$0.hasPrefix("unread:") }

            var changedItems: [String] = []
            for itemId in visibleItemIds {
                guard let msgId = UUID(uuidString: itemId),
                      let msg = messagesById[msgId] else { continue }
                // Full struct compare: count-based proxies missed same-count reaction
                // swaps, late reply/sender hydration, moderation/unsend, and
                // localAttachmentPath -> imageUrl upload completion.
                if let prev = previousMessages[msgId], prev == msg {
                    continue // unchanged
                }
                changedItems.append(itemId)
            }

            if !changedItems.isEmpty {
                var snap = dataSource.snapshot()
                snap.reconfigureItems(changedItems)
                dataSource.apply(snap, animatingDifferences: false)
            }
        }
        // The delivery status moves to the newest outgoing message (iMessage); reconfigure the
        // cell that showed it before so "Delivered" does not linger under two bubbles.
        // It can also move back to an older bubble (the newest one was unsent), so the cell that
        // gains it is reconfigured as well.
        if previousLastOutgoingId != lastOutgoingMessageId, let dataSource {
            let affected = [previousLastOutgoingId, lastOutgoingMessageId]
                .compactMap { $0?.uuidString }
                .filter { dataSource.indexPath(for: $0) != nil }
            if !affected.isEmpty {
                var snap = dataSource.snapshot()
                snap.reconfigureItems(affected)
                dataSource.apply(snap, animatingDifferences: false)
            }
        }
        // "Delivered" / "Read" is derived from the participant count, which loads after the first
        // messages are drawn. The cell kept the status it was given while the count was still
        // short, so a message the other person had read showed "Delivered" after the thread was
        // reopened, until some other update happened to touch that cell.
        if config.totalParticipants != lastAppliedTotalParticipants {
            let isFirstValue = lastAppliedTotalParticipants == nil
            lastAppliedTotalParticipants = config.totalParticipants
            if !isFirstValue, let dataSource,
               let itemId = lastOutgoingMessageId?.uuidString,
               dataSource.indexPath(for: itemId) != nil {
                var snap = dataSource.snapshot()
                snap.reconfigureItems([itemId])
                dataSource.apply(snap, animatingDifferences: false)
            }
        }
        previousMessages = messagesById

        // Handle scroll-to-message — once per target. A target not yet in the
        // snapshot is retried on later updates (e.g. after pagination), as before.
        if config.scrollToMessageId != lastScrolledToMessageId {
            if let targetId = config.scrollToMessageId {
                if let indexPath = dataSource?.indexPath(for: targetId.uuidString) {
                    collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
                    lastScrolledToMessageId = targetId
                }
            } else {
                lastScrolledToMessageId = nil
            }
        }

        // Handle scroll-to-bottom
        if config.scrollToBottom && !config.messages.isEmpty,
           collectionView.numberOfSections > 0, collectionView.numberOfItems(inSection: 0) > 0 {
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

    // MARK: - Typing bubble

    /// Show, update or remove the typing bubble (the newest item of the transcript, as in
    /// iMessage). Independent of the message configuration so typing ticks never rebuild
    /// message cells.
    func setTypingUsers(_ users: [TypingUser]) {
        guard users != typingUsers else { return }
        typingUsers = users
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        // Nothing to attach to until the first message snapshot exists; the full rebuild in
        // applyConfiguration() adds the item then.
        guard snapshot.numberOfSections > 0 else { return }

        let itemId = FlippedTypingIndicatorCell.itemIdentifier
        let isShown = snapshot.itemIdentifiers.contains(itemId)

        if isTypingItemVisible && !isShown {
            let stickToNewest = isAtBottom
            if let newest = snapshot.itemIdentifiers.first {
                snapshot.insertItems([itemId], beforeItem: newest)
            } else {
                snapshot.appendItems([itemId], toSection: 0)
            }
            dataSource.apply(snapshot, animatingDifferences: true)
            if stickToNewest {
                // Keep the bubble in view when the user is reading the newest messages.
                let restOffsetY = -collectionView.adjustedContentInset.top
                collectionView.setContentOffset(
                    CGPoint(x: collectionView.contentOffset.x, y: restOffsetY), animated: true
                )
            }
        } else if !isTypingItemVisible && isShown {
            snapshot.deleteItems([itemId])
            dataSource.apply(snapshot, animatingDifferences: true)
        } else if isShown {
            snapshot.reconfigureItems([itemId])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    // MARK: - Unread positioning

    /// Position the list for a thread opened with unread messages (iMessage behaviour): when
    /// everything from the newest message up to the unread divider fits on screen, stay at the
    /// bottom; otherwise put the divider at the top of the visible area. The result is clamped
    /// to the valid scroll range — an unclamped `scrollToItem` in this flipped list left the
    /// newest message hidden behind the composer until the user touched the list.
    private func scrollToFirstUnread(itemId: String) {
        guard let dataSource, let indexPath = dataSource.indexPath(for: itemId) else { return }
        collectionView.layoutIfNeeded()
        let inset = collectionView.adjustedContentInset
        let restOffsetY = -inset.top
        let visibleHeight = collectionView.bounds.height - inset.top - inset.bottom
        debugLogGeometry("firstUnread:before")

        // Flipped list: content y grows toward older messages, so the target's maxY is the
        // distance from the newest message to the top edge of the unread block.
        if let attributes = collectionView.layoutAttributesForItem(at: indexPath),
           attributes.frame.maxY <= visibleHeight {
            setContentOffsetY(restOffsetY)
            debugLogGeometry("firstUnread:fits")
            return
        }

        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
        collectionView.layoutIfNeeded()
        let maxOffsetY = max(restOffsetY, collectionView.contentSize.height - collectionView.bounds.height + inset.bottom)
        setContentOffsetY(min(max(collectionView.contentOffset.y, restOffsetY), maxOffsetY))
        debugLogGeometry("firstUnread:scrolled")
    }

    private func setContentOffsetY(_ y: CGFloat) {
        guard abs(collectionView.contentOffset.y - y) > 0.5 else { return }
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: y), animated: false)
    }

    /// DEBUG-only geometry trace for scroll-position investigations.
    private func debugLogGeometry(_ tag: String) {
#if DEBUG
        let cv = collectionView
        let inset = cv.adjustedContentInset
        let frameInWindow = cv.superview?.convert(cv.frame, to: nil) ?? cv.frame
        AppLogger.info("messaging", "[MessagesVC:geom] \(tag) offsetY=\(Int(cv.contentOffset.y)) contentH=\(Int(cv.contentSize.height)) boundsH=\(Int(cv.bounds.height)) insetTop=\(Int(inset.top)) insetBottom=\(Int(inset.bottom)) safeTop=\(Int(cv.safeAreaInsets.top)) safeBottom=\(Int(cv.safeAreaInsets.bottom)) frameY=\(Int(frameInWindow.minY)) frameMaxY=\(Int(frameInWindow.maxY)) items=\(cv.numberOfSections > 0 ? cv.numberOfItems(inSection: 0) : 0))")
#endif
    }

    // MARK: - Height Cache

    /// Lightweight content hash for cache key — covers all layout-affecting fields.
    static func contentHash(for msg: Message) -> Int {
        var h = msg.text.hashValue
        h ^= (msg.individualReactions?.count ?? 0)
        h ^= msg.readBy.count &* 31
        h ^= (msg.replyToMessage != nil ? 1 : 0) &* 97
        h ^= (msg.imageUrl != nil ? 1 : 0) &* 127
        h ^= (msg.audioUrl != nil ? 1 : 0) &* 151
        h ^= (msg.latitude != nil ? 1 : 0) &* 173
        h ^= (msg.editedAt != nil ? 1 : 0) &* 199
        h ^= (msg.sendStatus?.rawValue.hashValue ?? 0) &* 211
        h ^= (msg.hiddenAt != nil ? 1 : 0) &* 223
        h ^= (msg.deletedAt != nil ? 1 : 0) &* 227
        h ^= (msg.localAttachmentPath != nil ? 1 : 0) &* 229
        h ^= (msg.sender?.name.hashValue ?? 0) &* 233
        return h
    }

    func heightCacheKey(messageId: UUID, width: CGFloat, message: Message) -> String {
        "\(messageId.uuidString):\(Int(width)):\(Self.contentHash(for: message))"
    }

    func cachedHeight(for key: String) -> CGFloat? {
        heightCache[key]
    }

    func storeHeight(_ height: CGFloat, for key: String) {
        heightCache[key] = height
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
        guard collectionView.numberOfSections > 0 else { return }
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
        afterDismissingKeyboard { [weak self, weak cell] in
            guard let self, let cell, cell.window != nil else { return }
            self.presentOverlay(
                for: cell,
                message: message,
                showDetails: !(message.individualReactions ?? []).isEmpty
            )
        }
    }

    func messageCellDidTapReaction(_ cell: MessageCellView, message: Message, reaction: String?) {
        configuration.onReactionTap?(message, reaction)
    }

    func messageCellDidTapReactionBadge(_ cell: MessageCellView, message: Message) {
        afterDismissingKeyboard { [weak self, weak cell] in
            guard let self, let cell, cell.window != nil else { return }
            self.presentOverlay(for: cell, message: message, showDetails: true)
        }
    }

    /// Puts the keyboard away before a bubble overlay, as iMessage does. While the composer's
    /// text view is first responder the accessory bar stays above any modal presented
    /// overFullScreen, and it covered the bottom of the overlay's action menu. Once the text
    /// view has resigned, this controller takes first responder back so the bar returns when
    /// the overlay goes away. `work` runs immediately when no text was focused.
    private func afterDismissingKeyboard(_ work: @escaping () -> Void) {
        guard inputBar.isEditingText else {
            work()
            return
        }
        inputBar.endEditing(true)
        becomeFirstResponder()
        // The keyboard needs one transition to leave and the flipped list moves with it. The
        // cell is measured after that, or the overlay would lift a snapshot from where the
        // bubble used to be.
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Animation.medium) {
            work()
        }
    }

    private func presentOverlay(for cell: MessageCellView, message: Message, showDetails: Bool) {
        let cellFrame = cell.convert(cell.bounds, to: nil)
        guard let snapshot = cell.snapshotView(afterScreenUpdates: false) else { return }

        let currentUserId = AuthService.shared.currentUserId ?? UUID()
        let isFromCurrentUser = message.fromId == AuthService.shared.currentUserId
        let currentReaction = message.reactions?.currentUserReaction(userId: currentUserId)

        let overlay = MessageOverlayController(
            snapshot: snapshot,
            sourceFrame: cellFrame,
            message: message,
            isFromCurrentUser: isFromCurrentUser,
            currentUserReaction: currentReaction,
            isConversationFrozen: configuration.isConversationFrozen,
            onAction: { [weak self] action in
                self?.routeOverlayAction(action, for: message)
            },
            showDetails: showDetails,
            individualReactions: message.individualReactions ?? [],
            reactionProfiles: Dictionary(uniqueKeysWithValues: configuration.participantProfiles.map { ($0.id, $0) }),
            currentUserId: currentUserId
        )
        present(overlay, animated: false)
    }

    /// Hands an overlay action to the host. Delete for Me asks first: it sits next to Unsend in
    /// the same red and took the message out of the transcript on one tap, with no way back
    /// in the app (Unsend is confirmed by the host).
    private func routeOverlayAction(_ action: OverlayAction, for message: Message) {
        guard case .deleteForMe = action else {
            configuration.onOverlayAction?(action, message)
            return
        }
        let alert = UIAlertController(
            title: "messaging_delete_for_me".localized,
            message: MessageOverlayAvailability.deleteForMeConfirmationText(for: message),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "common_cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "common_delete".localized, style: .destructive) { [weak self] _ in
            self?.configuration.onOverlayAction?(.deleteForMe, message)
        })
        present(alert, animated: true)
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

    func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message) {
        configuration.onViewThread?(message)
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
        inputBar.setImagePreview(image)
        onCameraCapturedImage?(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
