//
//  ReactionBadgeView.swift
//  NaarsCars
//
//  UIKit emoji capsule badge with tap and long-press callbacks
//

import UIKit

/// Displays up to 5 reaction emoji capsules with counts.
final class ReactionBadgeView: UIView {

    // MARK: - Callbacks

    var onReactionTap: ((String) -> Void)?
    var onReactionLongPress: ((String) -> Void)?

    // MARK: - State

    private var capsules: [(view: UIView, reaction: String)] = []

    // MARK: - Constants

    private let capsuleSpacing: CGFloat = 4
    private let capsuleHPad: CGFloat = 8
    private let capsuleVPad: CGFloat = 4

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Configure

    func configure(reactions: MessageReactions) {
        // Remove old capsules
        for item in capsules { item.view.removeFromSuperview() }
        capsules.removeAll()

        let sorted = reactions.sortedReactions.prefix(5)
        for reactionData in sorted {
            let capsule = makeCapsule(emoji: reactionData.reaction, count: reactionData.count)
            addSubview(capsule)
            capsules.append((view: capsule, reaction: reactionData.reaction))
        }
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        for item in capsules {
            item.view.sizeToFit()
            item.view.frame.origin = CGPoint(x: x, y: 0)
            x += item.view.frame.width + capsuleSpacing
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var totalW: CGFloat = 0
        var maxH: CGFloat = 0
        for item in capsules {
            let s = item.view.sizeThatFits(size)
            totalW += s.width + capsuleSpacing
            maxH = max(maxH, s.height)
        }
        if totalW > 0 { totalW -= capsuleSpacing }
        return CGSize(width: min(totalW, size.width), height: maxH)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        for item in capsules { item.view.removeFromSuperview() }
        capsules.removeAll()
        onReactionTap = nil
        onReactionLongPress = nil
    }

    // MARK: - Capsule factory

    private func makeCapsule(emoji: String, count: Int) -> UIView {
        let container = ReactionCapsuleView()
        container.configure(emoji: emoji, count: count)

        container.isAccessibilityElement = true
        container.accessibilityLabel = count > 1 ? "\(emoji) \(count)" : emoji
        container.accessibilityTraits = .button

        let tap = UITapGestureRecognizer(target: self, action: #selector(capsuleTapped(_:)))
        container.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(capsuleLongPressed(_:)))
        longPress.minimumPressDuration = 0.3
        container.addGestureRecognizer(longPress)

        return container
    }

    @objc private func capsuleTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        if let match = capsules.first(where: { $0.view === view }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onReactionTap?(match.reaction)
        }
    }

    @objc private func capsuleLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view else { return }
        if let match = capsules.first(where: { $0.view === view }) {
            onReactionLongPress?(match.reaction)
        }
    }
}

// MARK: - Single capsule view

private final class ReactionCapsuleView: UIView {

    private let emojiLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .systemGray5
        layer.borderWidth = 2
        layer.borderColor = UIColor.systemBackground.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 2

        emojiLabel.font = .preferredFont(forTextStyle: .subheadline)
        addSubview(emojiLabel)

        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.textColor = .secondaryLabel
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func configure(emoji: String, count: Int) {
        emojiLabel.text = emoji
        countLabel.text = count > 1 ? "\(count)" : nil
        countLabel.isHidden = count <= 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let hPad: CGFloat = 8
        let spacing: CGFloat = 2
        let emojiSize = emojiLabel.sizeThatFits(bounds.size)
        emojiLabel.frame = CGRect(x: hPad, y: (bounds.height - emojiSize.height) / 2, width: emojiSize.width, height: emojiSize.height)
        if !countLabel.isHidden {
            let countSize = countLabel.sizeThatFits(bounds.size)
            countLabel.frame = CGRect(x: emojiLabel.frame.maxX + spacing, y: (bounds.height - countSize.height) / 2, width: countSize.width, height: countSize.height)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let hPad: CGFloat = 8
        let vPad: CGFloat = 4
        let spacing: CGFloat = 2
        let emojiSize = emojiLabel.sizeThatFits(size)
        var w = hPad + emojiSize.width + hPad
        if !countLabel.isHidden {
            let countSize = countLabel.sizeThatFits(size)
            w = hPad + emojiSize.width + spacing + countSize.width + hPad
        }
        return CGSize(width: w, height: emojiSize.height + vPad * 2)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = UIColor.systemBackground.cgColor
        }
    }
}
