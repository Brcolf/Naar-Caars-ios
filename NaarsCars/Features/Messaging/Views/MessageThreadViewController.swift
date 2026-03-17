//
//  MessageThreadViewController.swift
//  NaarsCars
//
//  UIKit-based thread view controller using compositional layout
//  and diffable data source. Normal top-to-bottom scroll (parent at top).
//

import UIKit
import SwiftUI
import PhotosUI
internal import Combine

// Section indices for the thread collection view
private let kSectionParent = 0
private let kSectionDivider = 1
private let kSectionReplies = 2

// Item key prefixes
private let kParentPrefix = "parent:"
private let kReplyPrefix = "reply:"
private let kDividerKey = "divider"
private let kEmptyKey = "empty"
private let kLoadingKey = "loading"

/// Non-flipped cell that hosts a MessageCellView (thread view is normal top-to-bottom).
private final class ThreadMessageCell: UICollectionViewCell {
    let messageCellView = MessageCellView()
    private var layoutInvalidationWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(messageCellView)

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

/// Simple divider cell — pure UIKit separator line.
private final class DividerCell: UICollectionViewCell {
    private let line = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        line.backgroundColor = .separator
        contentView.addSubview(line)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = 1.0 / (window?.screen.scale ?? UIScreen.main.scale)
        line.frame = CGRect(x: 0, y: (contentView.bounds.height - h) / 2, width: contentView.bounds.width, height: h)
    }

    override func preferredLayoutAttributesFitting(_ attrs: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let a = super.preferredLayoutAttributesFitting(attrs)
        a.frame.size.height = 24
        return a
    }
}

/// Simple centered label cell — used for empty state and loading.
private final class CenteredLabelCell: UICollectionViewCell {
    let label = UILabel()
    let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        contentView.addSubview(label)

        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configureAsEmpty() {
        label.text = NSLocalizedString("messaging_no_replies_yet", comment: "")
        label.isHidden = false
        spinner.stopAnimating()
    }

    func configureAsLoading() {
        label.isHidden = true
        spinner.startAnimating()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        spinner.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    }

    override func preferredLayoutAttributesFitting(_ attrs: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let a = super.preferredLayoutAttributesFitting(attrs)
        a.frame.size.height = 48
        return a
    }
}

final class MessageThreadViewController: UIViewController {

    // MARK: - Dependencies

    private let conversationId: UUID
    private let parentMessageId: UUID
    private let conversationViewModel: ConversationDetailViewModel
    private let isGroup: Bool
    private let totalParticipants: Int
    private let participantProfiles: [Profile]
    private let hasLeftConversation: Bool

    private let threadViewModel: MessageThreadViewModel

    // MARK: - UI

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    let inputBarController = InputBarController()
    private var inputHostingController: UIHostingController<MessageInputBar>?
    private var frozenBannerController: UIHostingController<FrozenConversationBanner>?

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var messageObserverId: UUID?

    private var mergeRepliesTask: Task<Void, Never>?

    deinit {
        mergeRepliesTask?.cancel()
        // Schedule observer cleanup on MainActor since deinit is nonisolated.
        // The callback uses [weak self] so it is inert after deallocation regardless.
        if let id = messageObserverId {
            let vm = conversationViewModel
            Task { @MainActor in vm.removeMessageObserver(id: id) }
        }
    }

    // MARK: - Init

    init(
        conversationId: UUID,
        parentMessageId: UUID,
        conversationViewModel: ConversationDetailViewModel,
        isGroup: Bool,
        totalParticipants: Int,
        participantProfiles: [Profile] = [],
        hasLeftConversation: Bool = false
    ) {
        self.conversationId = conversationId
        self.parentMessageId = parentMessageId
        self.conversationViewModel = conversationViewModel
        self.isGroup = isGroup
        self.totalParticipants = totalParticipants
        self.participantProfiles = participantProfiles
        self.hasLeftConversation = hasLeftConversation
        self.threadViewModel = MessageThreadViewModel(
            conversationId: conversationId,
            parentMessageId: parentMessageId
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupCollectionView()
        setupDataSource()
        setupBottomView()
        setupKeyboardObservers()
        bindViewModel()

        Task {
            await threadViewModel.loadThread(seedMessages: conversationViewModel.messages)
        }
    }

    // MARK: - Navigation Bar

    private func setupNavigationBar() {
        title = "messaging_thread".localized
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Collection View

    private func setupCollectionView() {
        let layout = createLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Bottom constraint set relative to input bar in setupInputBar()
        ])
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

    // MARK: - Item Key Helpers

    private static func parentKey(_ id: UUID) -> String { "\(kParentPrefix)\(id.uuidString)" }
    private static func replyKey(_ id: UUID) -> String { "\(kReplyPrefix)\(id.uuidString)" }

    private static func messageId(from key: String) -> UUID? {
        if key.hasPrefix(kParentPrefix) {
            return UUID(uuidString: String(key.dropFirst(kParentPrefix.count)))
        } else if key.hasPrefix(kReplyPrefix) {
            return UUID(uuidString: String(key.dropFirst(kReplyPrefix.count)))
        }
        return nil
    }

    // MARK: - Data Source

    private func setupDataSource() {
        let messageCellRegistration = UICollectionView.CellRegistration<ThreadMessageCell, String> {
            [weak self] cell, indexPath, itemKey in
            guard let self, let messageId = Self.messageId(from: itemKey) else { return }
            self.configureMessageCell(cell, messageId: messageId, isParent: itemKey.hasPrefix(kParentPrefix))
        }

        let dividerRegistration = UICollectionView.CellRegistration<DividerCell, String> { _, _, _ in }

        let emptyRegistration = UICollectionView.CellRegistration<CenteredLabelCell, String> { cell, _, _ in
            cell.configureAsEmpty()
        }

        let loadingRegistration = UICollectionView.CellRegistration<CenteredLabelCell, String> { cell, _, _ in
            cell.configureAsLoading()
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { collectionView, indexPath, itemKey in
            if itemKey.hasPrefix(kParentPrefix) || itemKey.hasPrefix(kReplyPrefix) {
                return collectionView.dequeueConfiguredReusableCell(using: messageCellRegistration, for: indexPath, item: itemKey)
            } else if itemKey == kDividerKey {
                return collectionView.dequeueConfiguredReusableCell(using: dividerRegistration, for: indexPath, item: itemKey)
            } else if itemKey == kEmptyKey {
                return collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: itemKey)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: loadingRegistration, for: indexPath, item: itemKey)
            }
        }
    }

    private func configureMessageCell(_ cell: ThreadMessageCell, messageId: UUID, isParent: Bool) {
        let message: Message?
        if isParent {
            message = threadViewModel.parentMessage
        } else {
            message = threadViewModel.replies.first(where: { $0.id == messageId })
        }
        guard let message else { return }

        let isFromCurrentUser = message.fromId == AuthService.shared.currentUserId
        let showAvatar = isGroup && !isFromCurrentUser

        var isFirst = true
        var isLast = true
        if !isParent {
            if let index = threadViewModel.replies.firstIndex(where: { $0.id == messageId }) {
                isFirst = MessageSeriesHelper.isFirstInSeries(messages: threadViewModel.replies, at: index)
                isLast = MessageSeriesHelper.isLastInSeries(messages: threadViewModel.replies, at: index)
            }
        }

        let config = MessageCellConfig(
            message: message,
            isFromCurrentUser: isFromCurrentUser,
            showAvatar: showAvatar,
            isFirstInSeries: isFirst,
            isLastInSeries: isLast,
            isGroupConversation: isGroup,
            totalParticipants: totalParticipants,
            participantProfiles: participantProfiles,
            showReplyPreview: false,
            replySpine: nil,
            isHighlighted: false,
            shouldAnimate: false,
            replyCount: 0
        )

        cell.messageCellView.delegate = self
        cell.messageCellView.configure(with: config)
    }

    // MARK: - Bottom View (Input Bar or Frozen Banner)

    private func setupBottomView() {
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
                collectionView.bottomAnchor.constraint(equalTo: banner.view.topAnchor),
            ])
            banner.didMove(toParent: self)
            frozenBannerController = banner
        } else {
            setupInputBar()
        }
    }

    // MARK: - Input Bar

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
            self?.conversationViewModel.typingManager.userDidType()
        }

        let inputBar = MessageInputBar(controller: inputBarController, isDisabled: false)
        let hostingController = UIHostingController(rootView: inputBar)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.bottomAnchor.constraint(equalTo: hostingController.view.topAnchor),
        ])

        inputHostingController = hostingController
    }

    private func handleSend(_ payload: InputBarController.SendPayload) {
        guard let parentId = threadViewModel.parentMessage?.id else { return }
        Task {
            if let editId = payload.editMessageId {
                conversationViewModel.editingMessage = conversationViewModel.messages.first { $0.id == editId }
                await conversationViewModel.editMessage(newContent: payload.text)
            } else if let attachment = payload.attachment {
                await conversationViewModel.sendMessage(
                    textOverride: payload.text.isEmpty ? nil : payload.text,
                    image: attachment.image,
                    replyToId: parentId
                )
            } else {
                await conversationViewModel.sendMessage(
                    textOverride: payload.text,
                    replyToId: parentId
                )
            }
        }
    }

    private func presentLocationPicker() {
        let picker = LocationPickerSheet { [weak self] coordinate, name in
            guard let self else { return }
            Task {
                await self.conversationViewModel.sendLocationMessage(
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

    // MARK: - Keyboard

    private func setupKeyboardObservers() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                guard let self,
                      let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let bottomInset = frame.height - self.view.safeAreaInsets.bottom
                self.additionalSafeAreaInsets.bottom = max(bottomInset, 0)
                self.animateAlongsideKeyboard(notification: notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] notification in
                self?.additionalSafeAreaInsets.bottom = 0
                self?.animateAlongsideKeyboard(notification: notification)
            }
            .store(in: &cancellables)
    }

    /// Animate layout changes using the keyboard's own animation parameters
    /// so the collection view and input bar move in sync with the keyboard.
    private func animateAlongsideKeyboard(notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curveRaw << 16), animations: {
            self.view.layoutIfNeeded()
        })
    }

    // MARK: - Bindings

    private func bindViewModel() {
        // Observe @Observable threadViewModel for snapshot rebuilds
        observeThreadViewModel()

        // Observe conversation messages for realtime reply merging via callback
        messageObserverId = conversationViewModel.addMessageObserver { [weak self] messages in
            guard let self else { return }
            self.mergeRepliesTask?.cancel()
            let current = messages
            self.mergeRepliesTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.threadViewModel.mergeReplies(from: current)
                }
            }
        }
    }

    /// Tracks @Observable threadViewModel properties and rebuilds snapshot on change.
    /// Re-registers after each change since withObservationTracking fires once per session.
    private func observeThreadViewModel() {
        withObservationTracking {
            let _ = self.threadViewModel.parentMessage
            let _ = self.threadViewModel.replies
            let _ = self.threadViewModel.isLoading
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applySnapshot()
                self?.observeThreadViewModel()
            }
        }
    }

    // MARK: - Snapshot

    private func applySnapshot(animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()

        // Parent section
        snapshot.appendSections([kSectionParent])
        if threadViewModel.parentMessage != nil {
            snapshot.appendItems([Self.parentKey(parentMessageId)], toSection: kSectionParent)
        } else if threadViewModel.isLoading {
            snapshot.appendItems([kLoadingKey], toSection: kSectionParent)
        }

        // Divider section
        snapshot.appendSections([kSectionDivider])
        if threadViewModel.parentMessage != nil {
            snapshot.appendItems([kDividerKey], toSection: kSectionDivider)
        }

        // Replies section (chronological order, oldest first)
        snapshot.appendSections([kSectionReplies])
        if threadViewModel.replies.isEmpty && !threadViewModel.isLoading {
            snapshot.appendItems([kEmptyKey], toSection: kSectionReplies)
        } else {
            let replyItems = threadViewModel.replies.map { Self.replyKey($0.id) }
            snapshot.appendItems(replyItems, toSection: kSectionReplies)
        }

        let wasAtBottom = isScrolledNearBottom()
        dataSource.apply(snapshot, animatingDifferences: animated)

        // Auto-scroll to bottom when new replies arrive
        if wasAtBottom && !threadViewModel.replies.isEmpty {
            scrollToBottom(animated: animated)
        }
    }

    private func isScrolledNearBottom() -> Bool {
        let offsetY = collectionView.contentOffset.y
        let contentHeight = collectionView.contentSize.height
        let frameHeight = collectionView.frame.height
        // Consider "near bottom" if within 80pt of bottom
        return contentHeight <= frameHeight || offsetY >= contentHeight - frameHeight - 80
    }

    private func scrollToBottom(animated: Bool) {
        let snapshot = dataSource.snapshot()
        guard let lastItem = snapshot.itemIdentifiers(inSection: kSectionReplies).last else { return }
        guard let indexPath = dataSource.indexPath(for: lastItem) else { return }
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
    }
}

// MARK: - MessageCellDelegate

extension MessageThreadViewController: MessageCellDelegate {
    func messageCellDidLongPress(_ cell: MessageCellView, message: Message) {
        let cellFrame = cell.convert(cell.bounds, to: nil)
        guard let snapshot = cell.snapshotView(afterScreenUpdates: false) else { return }

        let isFromCurrentUser = message.fromId == AuthService.shared.currentUserId
        let currentReaction = message.reactions?.currentUserReaction(
            userId: AuthService.shared.currentUserId ?? UUID()
        )
        let profilesById = Dictionary(uniqueKeysWithValues: participantProfiles.map { ($0.id, $0) })

        let overlay = MessageOverlayController(
            snapshot: snapshot,
            sourceFrame: cellFrame,
            message: message,
            isFromCurrentUser: isFromCurrentUser,
            currentUserReaction: currentReaction,
            isConversationFrozen: hasLeftConversation,
            onAction: { [weak self] action in
                self?.handleOverlayAction(action, for: message)
            },
            showDetails: !(message.individualReactions ?? []).isEmpty,
            individualReactions: message.individualReactions ?? [],
            reactionProfiles: profilesById,
            currentUserId: AuthService.shared.currentUserId ?? UUID()
        )
        present(overlay, animated: false)
    }

    func messageCellDidTapReaction(_ cell: MessageCellView, message: Message, reaction: String?) {
        // Thread view doesn't handle reactions directly
    }

    func messageCellDidSwipeToReply(_ cell: MessageCellView, message: Message) {
        // Thread view doesn't support nested replies
    }

    func messageCellDidTapImage(_ cell: MessageCellView, url: URL) {
        let imageVC = UIViewController()
        imageVC.modalPresentationStyle = .fullScreen
        imageVC.view.backgroundColor = .black

        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        imageVC.view.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: imageVC.view.topAnchor),
            iv.bottomAnchor.constraint(equalTo: imageVC.view.bottomAnchor),
            iv.leadingAnchor.constraint(equalTo: imageVC.view.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: imageVC.view.trailingAnchor),
        ])

        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return }
            await MainActor.run {
                iv.image = img
            }
        }

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.accessibilityLabel = NSLocalizedString("accessibility_close", comment: "")
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        imageVC.view.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: imageVC.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeBtn.trailingAnchor.constraint(equalTo: imageVC.view.trailingAnchor, constant: -16),
        ])
        closeBtn.addAction(UIAction { _ in imageVC.dismiss(animated: true) }, for: .touchUpInside)

        present(imageVC, animated: true)
    }

    func messageCellDidTapReplyPreview(_ cell: MessageCellView, replyToId: UUID) {
        // No-op in thread context
    }

    func messageCellDidTapRetry(_ cell: MessageCellView, message: Message) {
        Task { await conversationViewModel.retryMessage(id: message.id) }
    }

    func messageCellDidTapViewThread(_ cell: MessageCellView, message: Message) {
        // Thread view doesn't support nested thread navigation
    }

    func messageCellDidTapReactionBadge(_ cell: MessageCellView, message: Message) {
        let cellFrame = cell.convert(cell.bounds, to: nil)
        guard let snapshot = cell.snapshotView(afterScreenUpdates: false) else { return }

        let isFromCurrentUser = message.fromId == AuthService.shared.currentUserId
        let currentReaction = message.reactions?.currentUserReaction(
            userId: AuthService.shared.currentUserId ?? UUID()
        )
        let currentUserId = AuthService.shared.currentUserId ?? UUID()
        let profilesById = Dictionary(uniqueKeysWithValues: participantProfiles.map { ($0.id, $0) })

        let overlay = MessageOverlayController(
            snapshot: snapshot,
            sourceFrame: cellFrame,
            message: message,
            isFromCurrentUser: isFromCurrentUser,
            currentUserReaction: currentReaction,
            isConversationFrozen: hasLeftConversation,
            onAction: { [weak self] action in
                self?.handleOverlayAction(action, for: message)
            },
            showDetails: true,
            individualReactions: message.individualReactions ?? [],
            reactionProfiles: profilesById,
            currentUserId: currentUserId
        )
        present(overlay, animated: false)
    }

    private func handleOverlayAction(_ action: OverlayAction, for message: Message) {
        switch action {
        case .react(let emoji):
            Task { await conversationViewModel.addReaction(messageId: message.id, reaction: emoji) }
        case .removeReaction:
            Task { await conversationViewModel.removeReaction(messageId: message.id) }
        case .copy:
            UIPasteboard.general.string = message.text
        case .reply:
            // Thread replies go to the parent; no separate reply-to handling needed
            break
        case .viewThread:
            // Already in thread view
            break
        case .edit:
            conversationViewModel.startEditing(message)
        case .unsend:
            Task { await conversationViewModel.unsendMessage(id: message.id) }
        case .deleteForMe:
            Task { await conversationViewModel.deleteMessageForMe(message) }
        case .report:
            break
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension MessageThreadViewController: PHPickerViewControllerDelegate {

    func presentImagePicker() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async {
                self?.inputBarController.setImage(image)
            }
        }
    }
}
