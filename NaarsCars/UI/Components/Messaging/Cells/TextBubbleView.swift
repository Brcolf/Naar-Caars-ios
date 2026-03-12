//
//  TextBubbleView.swift
//  NaarsCars
//
//  UIKit text bubble with BubblePath background — manual frame layout
//

import UIKit

/// Pure UIKit text bubble with iMessage-style BubblePath background.
final class TextBubbleView: UIView {

    // MARK: - Subviews

    private let textLabel = UILabel()
    private let bubbleLayer = CAShapeLayer()

    // MARK: - State

    private var isFromCurrentUser = false
    private var showTail = true

    // MARK: - Constants

    private let hPad: CGFloat = 14
    private let vPad: CGFloat = 10

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.insertSublayer(bubbleLayer, at: 0)

        textLabel.numberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.font = .preferredFont(forTextStyle: .body)
        addSubview(textLabel)
    }

    // MARK: - Configure

    func configure(text: String, isFromCurrentUser: Bool, showTail: Bool) {
        self.isFromCurrentUser = isFromCurrentUser
        self.showTail = showTail

        textLabel.text = text
        textLabel.textColor = isFromCurrentUser ? .white : .label
        bubbleLayer.fillColor = isFromCurrentUser
            ? UIColor.naarsPrimary.cgColor
            : UIColor.systemGray5.cgColor

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds

        let tailWidth: CGFloat = showTail ? 6 : 0
        let textOriginX: CGFloat = isFromCurrentUser ? hPad : hPad + tailWidth
        let textWidth = b.width - hPad * 2 - tailWidth
        let textSize = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))

        textLabel.frame = CGRect(x: textOriginX, y: vPad, width: textSize.width, height: textSize.height)

        let path = BubblePath.make(
            in: b,
            isFromCurrentUser: isFromCurrentUser,
            showTail: showTail
        )
        bubbleLayer.path = path
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let tailWidth: CGFloat = showTail ? 6 : 0
        let maxTextWidth = size.width - hPad * 2 - tailWidth
        let textSize = textLabel.sizeThatFits(CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
        return CGSize(
            width: textSize.width + hPad * 2 + tailWidth,
            height: textSize.height + vPad * 2
        )
    }

    // MARK: - Reuse

    func prepareForReuse() {
        textLabel.text = nil
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            bubbleLayer.fillColor = isFromCurrentUser
                ? UIColor.naarsPrimary.cgColor
                : UIColor.systemGray5.cgColor
        }
    }
}
