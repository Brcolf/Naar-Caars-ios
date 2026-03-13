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

    init(message: Message, isFromCurrentUser: Bool, isConversationFrozen: Bool = false) {
        super.init(frame: .zero)
        let items = Self.buildActions(message: message, isFromCurrentUser: isFromCurrentUser, isConversationFrozen: isConversationFrozen)
        setupViews(items: items)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Action building

    private static func buildActions(message: Message, isFromCurrentUser: Bool, isConversationFrozen: Bool) -> [ActionItem] {
        var items: [ActionItem] = []

        if !isConversationFrozen {
            // Reply — only when participating
            items.append(ActionItem(action: .reply, title: NSLocalizedString("Reply", comment: "Message action: reply to this message"), icon: "arrow.uturn.left", isDestructive: false))
        }

        // View Thread — always available (read-only navigation)
        if let replyToId = message.replyToId {
            items.append(ActionItem(
                action: .viewThread(replyToId),
                title: NSLocalizedString("messaging_view_thread", comment: "Message action: open the reply thread"),
                icon: "bubble.left.and.bubble.right",
                isDestructive: false
            ))
        }

        // Copy — always available
        if !message.text.isEmpty {
            items.append(ActionItem(action: .copy, title: NSLocalizedString("Copy", comment: "Message action: copy message text to clipboard"), icon: "doc.on.doc", isDestructive: false))
        }

        if !isConversationFrozen {
            // Edit — only when participating
            if isFromCurrentUser,
               message.messageType == .text || message.messageType == nil,
               !message.isAudioMessage,
               !message.isLocationMessage {
                items.append(ActionItem(action: .edit, title: NSLocalizedString("Edit", comment: "Message action: edit own message text"), icon: "pencil", isDestructive: false))
            }

            // Undo Send — only when participating
            if isFromCurrentUser, message.canUnsend {
                items.append(ActionItem(action: .unsend, title: NSLocalizedString("messaging_undo_send", comment: "Message action: recall sent message within time limit"), icon: "arrow.uturn.backward", isDestructive: true))
            }
        }

        // Delete for Me — always available (local-only action)
        items.append(ActionItem(action: .deleteForMe, title: NSLocalizedString("messaging_delete_for_me", comment: "Message action: delete message for current user only"), icon: "trash", isDestructive: true))

        // Report — always available (moderation action)
        if !isFromCurrentUser {
            items.append(ActionItem(action: .report, title: NSLocalizedString("messaging_report_message", comment: "Message action: report inappropriate message"), icon: "exclamationmark.triangle", isDestructive: true))
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
