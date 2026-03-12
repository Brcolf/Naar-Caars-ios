//
//  ReactionBarView.swift
//  NaarsCars
//
//  Horizontal scrollable reaction bar for the message interaction overlay
//

import UIKit

/// Horizontal scrollable bar of reaction emoji buttons displayed above/below the message snapshot
final class ReactionBarView: UIView {

    // MARK: - Callbacks

    var onReact: ((String) -> Void)?
    var onRemoveReaction: (() -> Void)?

    // MARK: - Configuration

    private static let allReactions: [String] = [
        "\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F44E}", "\u{1F602}", "\u{203C}\u{FE0F}",
        "\u{2753}", "\u{1F525}", "\u{1F44F}", "\u{1F622}", "\u{1F62E}",
        "\u{1F64F}", "\u{1F4AF}", "\u{1F389}", "\u{1F60D}", "\u{1F914}",
        "\u{1F480}", "\u{1F631}", "\u{1F440}", "\u{2705}", "\u{274C}", "\u{1F64C}"
    ]

    private let buttonSize: CGFloat = 40
    private let buttonSpacing: CGFloat = 6

    // MARK: - State

    private var currentUserReaction: String?

    // MARK: - Subviews

    private let blurView: UIVisualEffectView = {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 24
        blur.clipsToBounds = true
        return blur
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceHorizontal = true
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()

    // MARK: - Init

    init(currentUserReaction: String? = nil) {
        self.currentUserReaction = currentUserReaction
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(blurView)
        blurView.contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            stackView.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        for emoji in Self.allReactions {
            let button = makeReactionButton(emoji: emoji)
            stackView.addArrangedSubview(button)
        }
    }

    private func makeReactionButton(emoji: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(emoji, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22)
        button.layer.cornerRadius = buttonSize / 2
        button.clipsToBounds = true

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize),
            button.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        let isSelected = emoji == currentUserReaction
        if isSelected {
            button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.25)
            button.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        }

        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if emoji == self.currentUserReaction {
                self.onRemoveReaction?()
            } else {
                self.onReact?(emoji)
            }
        }, for: .touchUpInside)

        return button
    }
}
