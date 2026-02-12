//
//  MessagesCollectionView.swift
//  NaarsCars
//
//  UICollectionView wrapper for the message list, providing perfect scroll
//  position maintenance during top-insertion (pagination) and smooth
//  animated updates via NSDiffableDataSourceSnapshot.
//

import SwiftUI
import UIKit

/// Data passed from SwiftUI to configure each message cell
struct MessageCellConfiguration: Hashable {
    let messageId: UUID
    let isFirstInSeries: Bool
    let isLastInSeries: Bool
    let showDateSeparator: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.messageId == rhs.messageId
    }
}

/// Cell that keeps its content right-side up when used inside a vertically flipped collection view.
private final class MessageCollectionViewCell: UICollectionViewCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        // Unflip content so SwiftUI text and bubbles render right-side up (collection view uses y: -1).
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
    }
}

/// UIViewRepresentable wrapping UICollectionView for the messages list
struct MessagesCollectionView: UIViewRepresentable {
    let messages: [Message]
    let cellConfigurations: [UUID: MessageCellConfiguration]
    let messageCellContent: (Message, MessageCellConfiguration) -> AnyView
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
        
        // Build snapshot from messages (reversed because of the transform trick)
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        // Reverse because the collection view is flipped — newest messages appear at top (bottom visually)
        let reversedIds = messages.reversed().map { $0.id }
        snapshot.appendItems(reversedIds, toSection: 0)
        
        // Store messages for the data source
        coordinator.messagesById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        coordinator.cellConfigurations = cellConfigurations
        coordinator.messageCellContent = messageCellContent
        
        let isInitialLoad = coordinator.lastSnapshotCount == 0 && !messages.isEmpty
        let isPagination = messages.count > coordinator.lastSnapshotCount && coordinator.lastSnapshotCount > 0
        let isSingleNewMessage = messages.count == coordinator.lastSnapshotCount + 1 && coordinator.lastSnapshotCount > 0
        coordinator.lastSnapshotCount = messages.count
        
        if isInitialLoad {
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        } else if isPagination || !isSingleNewMessage {
            // Pagination or bulk/ambiguous update — no animation to avoid jank
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        } else {
            // Single new message at bottom — smooth insert animation
            coordinator.dataSource?.apply(snapshot, animatingDifferences: true)
        }
        
        // Handle scroll-to-message
        if let targetId = scrollToMessageId,
           let index = reversedIds.firstIndex(of: targetId) {
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
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
    
    class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        var parent: MessagesCollectionView
        var dataSource: UICollectionViewDiffableDataSource<Int, UUID>?
        var messagesById: [UUID: Message] = [:]
        var cellConfigurations: [UUID: MessageCellConfiguration] = [:]
        var messageCellContent: ((Message, MessageCellConfiguration) -> AnyView)?
        var lastSnapshotCount = 0
        private var isAtBottom = true
        
        init(parent: MessagesCollectionView) {
            self.parent = parent
        }
        
        func setupDataSource(collectionView: UICollectionView) {
            let cellRegistration = UICollectionView.CellRegistration<MessageCollectionViewCell, UUID> { [weak self] cell, indexPath, messageId in
                guard let self = self,
                      let message = self.messagesById[messageId],
                      let config = self.cellConfigurations[messageId],
                      let contentBuilder = self.messageCellContent else { return }
                
                let swiftUIView = contentBuilder(message, config)
                
                cell.contentConfiguration = UIHostingConfiguration {
                    swiftUIView
                }
                .margins(.all, 0)
                
                // MessageCollectionViewCell applies contentView.transform in layoutSubviews so content is right-side up.
            }
            
            dataSource = UICollectionViewDiffableDataSource<Int, UUID>(
                collectionView: collectionView
            ) { collectionView, indexPath, messageId in
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: messageId)
            }
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
