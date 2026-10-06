//
//  OverlayActionListView.swift
//  NaarsCars
//
//  Contextual action list for the message interaction overlay
//

import UIKit

/// Contextual action list shown below/above the message snapshot in the overlay
final class OverlayActionListView: UIView {

    // MARK: - Callback

    var onAction: ((OverlayAction) -> Void)?

    // MARK: - Types

    private struct ActionItem {
        let action: OverlayAction
        let title: String
        let icon: String
        let isDestructive: Bool
    }

    // MARK: - Subviews

    private let backgroundBlur: UIVisualEffectView = {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 13
        blur.clipsToBounds = true
        return blur
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.spacing = 0
        return sv
    }()

    // MARK: - Init

    /// - Parameter isInThread: true when shown from the reply thread, where Reply and
    ///   View Thread have nothing to do (every message there already replies to the parent).
    init(message: Message, isFromCurrentUser: Bool, isConversationFrozen: Bool = false, isInThread: Bool = false) {
        super.init(frame: .zero)
        let items = Self.buildActions(
            message: message,
            isFromCurrentUser: isFromCurrentUser,
            isConversationFrozen: isConversationFrozen,
            isInThread: isInThread
        )
        isHidden = items.isEmpty
        setupViews(items: items)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Action building

    // Titles go through `.localized` (not a bare NSLocalizedString): it falls back to the
    // English text when the current language has no entry, instead of showing the key.
    private static func buildActions(message: Message, isFromCurrentUser: Bool, isConversationFrozen: Bool, isInThread: Bool) -> [ActionItem] {
        // A system line is not a message to reply to, copy, edit or delete, but another member's
        // line can carry text they typed (a group name), so it keeps Report and nothing else.
        if message.messageType == .system, !message.isUnsent, !message.isModerationHidden {
            guard !isFromCurrentUser else { return [] }
            return [ActionItem(action: .report, title: "messaging_report_message".localized, icon: "exclamationmark.triangle", isDestructive: true)]
        }
        // An unsent or hidden placeholder is not a message: nothing applies to it.
        guard !MessageOverlayAvailability.isPlaceholder(message) else { return [] }

        let copyItem = ActionItem(action: .copy, title: "Copy".localized, icon: "doc.on.doc", isDestructive: false)
        let deleteForMeItem = ActionItem(action: .deleteForMe, title: "messaging_delete_for_me".localized, icon: "trash", isDestructive: true)

        // Still sending or failed: the row is only on this device, so the server would refuse
        // reply, edit, unsend and report. Copy is always safe, and a failed row can be removed
        // from the transcript. Retry stays on the bubble ("Not sent. Tap to retry").
        if MessageOverlayAvailability.isLocalOnly(message) {
            var localItems: [ActionItem] = []
            if !message.text.isEmpty { localItems.append(copyItem) }
            if message.sendStatus == .failed { localItems.append(deleteForMeItem) }
            return localItems
        }

        var items: [ActionItem] = []

        if !isConversationFrozen, !isInThread {
            // Reply — only when participating
            items.append(ActionItem(action: .reply, title: "Reply".localized, icon: "arrow.uturn.left", isDestructive: false))
        }

        // View Thread — read-only navigation (not from inside the thread itself)
        if !isInThread, let replyToId = message.replyToId {
            items.append(ActionItem(
                action: .viewThread(replyToId),
                title: "messaging_view_thread".localized,
                icon: "bubble.left.and.bubble.right",
                isDestructive: false
            ))
        }

        // Copy — always available
        if !message.text.isEmpty {
            items.append(copyItem)
        }

        if !isConversationFrozen {
            // Edit — only when participating
            if isFromCurrentUser,
               message.messageType == .text || message.messageType == nil,
               !message.isAudioMessage,
               !message.isLocationMessage {
                items.append(ActionItem(action: .edit, title: "Edit".localized, icon: "pencil", isDestructive: false))
            }

            // Undo Send — only when participating
            if isFromCurrentUser, message.canUnsend {
                items.append(ActionItem(action: .unsend, title: "messaging_undo_send".localized, icon: "arrow.uturn.backward", isDestructive: true))
            }
        }

        // Delete for Me — always available (local-only action)
        items.append(deleteForMeItem)

        // Report — always available (moderation action)
        if !isFromCurrentUser {
            items.append(ActionItem(action: .report, title: "messaging_report_message".localized, icon: "exclamationmark.triangle", isDestructive: true))
        }

        return items
    }

    // MARK: - Setup

    private func setupViews(items: [ActionItem]) {
        addSubview(backgroundBlur)
        backgroundBlur.contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            backgroundBlur.topAnchor.constraint(equalTo: topAnchor),
            backgroundBlur.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundBlur.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundBlur.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: backgroundBlur.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: backgroundBlur.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: backgroundBlur.contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: backgroundBlur.contentView.bottomAnchor),
        ])

        for (index, item) in items.enumerated() {
            let row = makeRow(item: item)
            stackView.addArrangedSubview(row)

            // Add separator between rows (not after the last)
            if index < items.count - 1 {
                let separator = makeSeparator()
                stackView.addArrangedSubview(separator)
            }
        }
    }

    private func makeRow(item: ActionItem) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: item.icon)
        config.title = item.title
        config.imagePlacement = .leading
        config.imagePadding = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        config.baseForegroundColor = item.isDestructive ? .systemRed : .label
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "overlay.action.\(item.action.accessibilityName)"

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
        ])

        button.addAction(UIAction { [weak self] _ in
            self?.onAction?(item.action)
        }, for: .touchUpInside)

        return button
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UITraitCollection.current.displayScale),
        ])
        return separator
    }
}
