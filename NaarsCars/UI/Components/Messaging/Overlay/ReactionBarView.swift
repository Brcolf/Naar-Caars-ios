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

    private let buttonSize: CGFloat = 40
    private let buttonSpacing: CGFloat = 6

    // MARK: - State

    private var currentUserReaction: String?
    private let emojiTextField = EmojiTextField()

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

        // Hidden text field for emoji keyboard
        emojiTextField.onEmojiInput = { [weak self] emoji in
            RecentReactionsStore.record(emoji)
            self?.onReact?(emoji)
        }
        emojiTextField.isHidden = true
        addSubview(emojiTextField)

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

        // Standard tapbacks
        for emoji in MessageReaction.standardTapbacks {
            stackView.addArrangedSubview(makeReactionButton(emoji: emoji))
        }

        // Recent emoji (non-standard only, filtered by RecentReactionsStore)
        for emoji in RecentReactionsStore.recents {
            stackView.addArrangedSubview(makeReactionButton(emoji: emoji))
        }

        // Divider
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: buttonSize - 16),
        ])
        stackView.addArrangedSubview(divider)

        // Emoji keyboard button
        stackView.addArrangedSubview(makeEmojiKeyboardButton())
    }

    // MARK: - Button Factories

    private func makeReactionButton(emoji: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        if TapbackArtwork.isHaha(emoji) {
            let isSelected = emoji == currentUserReaction
            let img = TapbackArtwork.hahaImage(pointSize: 22, color: isSelected ? .white : .systemBlue)
            button.setImage(img, for: .normal)
            button.setTitle(nil, for: .normal)
            button.accessibilityLabel = "Ha ha"
        } else {
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 22)
            button.accessibilityLabel = emoji
        }

        button.layer.cornerRadius = buttonSize / 2
        button.clipsToBounds = true

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize),
            button.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        let isSelected = emoji == currentUserReaction
        if isSelected {
            button.backgroundColor = .systemBlue
            button.accessibilityTraits = [.button, .selected]
            button.accessibilityHint = NSLocalizedString("accessibility_reaction_remove_hint", comment: "")
        } else {
            button.accessibilityHint = NSLocalizedString("accessibility_reaction_add_hint", comment: "")
        }
        button.accessibilityIdentifier = "overlay.reaction.\(emoji)"

        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if emoji == self.currentUserReaction {
                self.onRemoveReaction?()
            } else {
                if !MessageReaction.standardTapbacks.contains(emoji) {
                    RecentReactionsStore.record(emoji)
                }
                self.onReact?(emoji)
            }
        }, for: .touchUpInside)

        return button
    }

    private func makeEmojiKeyboardButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.setImage(UIImage(systemName: "face.smiling", withConfiguration: config), for: .normal)
        button.tintColor = UIColor.white.withAlphaComponent(0.6)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = buttonSize / 2
        button.clipsToBounds = true
        button.accessibilityLabel = NSLocalizedString("accessibility_emoji_picker", comment: "Open emoji picker")

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize),
            button.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        button.addAction(UIAction { [weak self] _ in
            self?.emojiTextField.becomeFirstResponder()
        }, for: .touchUpInside)

        return button
    }
}

// MARK: - Hidden emoji text field

/// A zero-frame UITextField that opens the emoji keyboard.
/// Validates input to accept only emoji characters.
private final class EmojiTextField: UITextField, UITextFieldDelegate {

    var onEmojiInput: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: .zero)
        delegate = self
        textContentType = .none
        autocorrectionType = .no
        spellCheckingType = .no
    }

    required init?(coder: NSCoder) { fatalError() }

    override var textInputMode: UITextInputMode? {
        // Prefer emoji keyboard if available
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard !string.isEmpty else { return false }
        for character in string {
            if character.isActualEmoji {
                onEmojiInput?(String(character))
                DispatchQueue.main.async { textField.resignFirstResponder() }
                return false
            }
        }
        return false
    }
}
