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

    init(message: Message, isFromCurrentUser: Bool) {
        super.init(frame: .zero)
        let items = Self.buildActions(message: message, isFromCurrentUser: isFromCurrentUser)
        setupViews(items: items)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Action building

    private static func buildActions(message: Message, isFromCurrentUser: Bool) -> [ActionItem] {
        var items: [ActionItem] = []

        // Reply — always
        items.append(ActionItem(action: .reply, title: "Reply", icon: "arrow.uturn.left", isDestructive: false))

        // Copy — if text is non-empty
        if !message.text.isEmpty {
            items.append(ActionItem(action: .copy, title: "Copy", icon: "doc.on.doc", isDestructive: false))
        }

        // Edit — sent messages, text-only (not audio, not location, not image-only)
        if isFromCurrentUser,
           message.messageType == .text || message.messageType == nil,
           !message.isAudioMessage,
           !message.isLocationMessage {
            items.append(ActionItem(action: .edit, title: "Edit", icon: "pencil", isDestructive: false))
        }

        // Undo Send — sent messages within 15 min
        if isFromCurrentUser, message.canUnsend {
            items.append(ActionItem(action: .unsend, title: "Undo Send", icon: "arrow.uturn.backward", isDestructive: true))
        }

        // Delete for Me — always
        items.append(ActionItem(action: .deleteForMe, title: "Delete for Me", icon: "trash", isDestructive: false))

        // Report — received messages only
        if !isFromCurrentUser {
            items.append(ActionItem(action: .report, title: "Report", icon: "exclamationmark.triangle", isDestructive: true))
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
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        return separator
    }
}
