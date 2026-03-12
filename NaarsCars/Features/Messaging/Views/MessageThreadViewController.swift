//
//  MessageThreadViewController.swift
//  NaarsCars
//
//  UIKit-based thread view controller using compositional layout
//  and diffable data source. Normal top-to-bottom scroll (parent at top).
//

import UIKit
import SwiftUI
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(messageCellView)

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

    private let threadViewModel: MessageThreadViewModel

    // MARK: - UI

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var inputHostingController: UIHostingController<MessageInputBar>?

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var mergeRepliesTask: Task<Void, Never>?
    private var messageText = ""
    private var imageToSend: UIImage?

    // MARK: - Init

    init(
        conversationId: UUID,
        parentMessageId: UUID,
        conversationViewModel: ConversationDetailViewModel,
        isGroup: Bool,
        totalParticipants: Int,
        participantProfiles: [Profile] = []
    ) {
        self.conversationId = conversationId
        self.parentMessageId = parentMessageId
        self.conversationViewModel = conversationViewModel
        self.isGroup = isGroup
        self.totalParticipants = totalParticipants
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
        setupInputBar()
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
            shouldAnimate: false
        )

        cell.messageCellView.delegate = self
        cell.messageCellView.configure(with: config)
    }

    // MARK: - Input Bar

    private func makeInputBar() -> MessageInputBar {
        let hasParent = threadViewModel.parentMessage != nil
        let hasContent = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageToSend != nil

        return MessageInputBar(
            text: Binding(
                get: { [weak self] in self?.messageText ?? "" },
                set: { [weak self] in
                    self?.messageText = $0
                    self?.updateInputBarDisabledState()
                }
            ),
            imageToSend: Binding(
                get: { [weak self] in self?.imageToSend },
                set: { [weak self] in
                    self?.imageToSend = $0
                    self?.updateInputBarDisabledState()
                }
            ),
            onSend: { [weak self] in self?.sendReply() },
            onImagePickerTapped: { },
            isDisabled: !hasParent || !hasContent
        )
    }

    private func setupInputBar() {
        let inputBar = makeInputBar()

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

    private func updateInputBarDisabledState() {
        inputHostingController?.rootView = makeInputBar()
    }

    private func sendReply() {
        let textToSend = messageText
        let image = imageToSend
        messageText = ""
        imageToSend = nil
        updateInputBarDisabledState()

        Task {
            await conversationViewModel.sendMessage(
                textOverride: textToSend,
                image: image,
                replyToId: parentMessageId
            )
        }
    }

    // MARK: - Keyboard

    private func setupKeyboardObservers() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
            .sink { [weak self] frame in
                guard let self else { return }
                let bottomInset = frame.height - self.view.safeAreaInsets.bottom
                self.additionalSafeAreaInsets.bottom = max(bottomInset, 0)
                UIView.animate(withDuration: 0.25) {
                    self.view.layoutIfNeeded()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.additionalSafeAreaInsets.bottom = 0
                UIView.animate(withDuration: 0.25) {
                    self?.view.layoutIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Bindings

    private func bindViewModel() {
        // Rebuild snapshot when parent or replies change
        threadViewModel.$parentMessage
            .combineLatest(threadViewModel.$replies, threadViewModel.$isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.applySnapshot()
                self?.updateInputBarDisabledState()
            }
            .store(in: &cancellables)

        // Merge real-time replies from the conversation view model
        conversationViewModel.$messages
            .sink { [weak self] messages in
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
            .store(in: &cancellables)
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
        // Thread view doesn't present the overlay
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

        Task {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                iv.image = img
            }
        }

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = .white
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
}
