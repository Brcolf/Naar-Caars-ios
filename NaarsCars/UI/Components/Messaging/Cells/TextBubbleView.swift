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

    private let interiorPad: CGFloat = 14
    private let tailSidePad: CGFloat = 18
    private let vPad: CGFloat = 7

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

        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds

        let tailPad = showTail ? tailSidePad : interiorPad
        let leftPad = isFromCurrentUser ? interiorPad : tailPad
        let rightPad = isFromCurrentUser ? tailPad : interiorPad
        let textWidth = b.width - leftPad - rightPad - (showTail ? 6 : 0)
        let textSize = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))

        textLabel.frame = CGRect(x: leftPad + (showTail && !isFromCurrentUser ? 6 : 0), y: vPad, width: textSize.width, height: textSize.height)

        let bezier = BubblePath.path(
            in: b,
            isFromCurrentUser: isFromCurrentUser,
            showTail: showTail
        )
        bubbleLayer.path = bezier.cgPath
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let tailPad = showTail ? tailSidePad : interiorPad
        let leftPad = isFromCurrentUser ? interiorPad : tailPad
        let rightPad = isFromCurrentUser ? tailPad : interiorPad
        let maxTextWidth = size.width - leftPad - rightPad - (showTail ? 6 : 0)
        let textSize = textLabel.sizeThatFits(CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
        let totalWidth = textSize.width + leftPad + rightPad + (showTail ? 6 : 0)
        let totalHeight = textSize.height + vPad * 2
        return CGSize(width: totalWidth, height: totalHeight)
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
