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
        let messageCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> {
            [weak self] cell, indexPath, itemKey in
            guard let self, let messageId = Self.messageId(from: itemKey) else { return }
            self.configureMessageCell(cell, messageId: messageId, isParent: itemKey.hasPrefix(kParentPrefix))
        }

        let dividerRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                Divider()
                    .padding(.vertical, 8)
            }
            .margins(.all, 0)
        }

        let emptyRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                Text("messaging_no_replies_yet".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .margins(.all, 0)
        }

        let loadingRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .margins(.all, 0)
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

    private func configureMessageCell(_ cell: UICollectionViewCell, messageId: UUID, isParent: Bool) {
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

        cell.contentConfiguration = UIHostingConfiguration {
            MessageBubble(
                message: message,
                isFromCurrentUser: isFromCurrentUser,
                showAvatar: showAvatar,
                isFirstInSeries: isFirst,
                isLastInSeries: isLast,
                totalParticipants: totalParticipants,
                showReplyPreview: false
            )
            .padding(.vertical, 2)
        }
        .margins(.all, 0)
    }

    // MARK: - Input Bar

    private func setupInputBar() {
        let inputBar = MessageInputBar(
            text: Binding(
                get: { [weak self] in self?.messageText ?? "" },
                set: { [weak self] in self?.messageText = $0 }
            ),
            imageToSend: Binding(
                get: { [weak self] in self?.imageToSend },
                set: { [weak self] in self?.imageToSend = $0 }
            ),
            onSend: { [weak self] in self?.sendReply() },
            onImagePickerTapped: { },
            isDisabled: false
        )

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
        updateInputBarDisabledState()
    }

    private func updateInputBarDisabledState() {
        let hasParent = threadViewModel.parentMessage != nil
        let hasContent = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageToSend != nil

        let inputBar = MessageInputBar(
            text: Binding(
                get: { [weak self] in self?.messageText ?? "" },
                set: { [weak self] in self?.messageText = $0 }
            ),
            imageToSend: Binding(
                get: { [weak self] in self?.imageToSend },
                set: { [weak self] in self?.imageToSend = $0 }
            ),
            onSend: { [weak self] in self?.sendReply() },
            onImagePickerTapped: { },
            isDisabled: !hasParent || !hasContent
        )
        inputHostingController?.rootView = inputBar
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
