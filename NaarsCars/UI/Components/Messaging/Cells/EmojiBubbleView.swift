//
//  EmojiBubbleView.swift
//  NaarsCars
//
//  Lightweight UIKit view for displaying enlarged emoji (1-3) without a bubble
//  background. Part of the iMessage parity series.
//

import UIKit

/// Displays 1-3 emoji at an enlarged size without a bubble background.
/// Tiered font sizing matches iMessage: 42pt for 1 emoji, 36pt for 2, 30pt for 3.
final class EmojiBubbleView: UIView {

    // MARK: - Subviews

    private let emojiLabel = UILabel()

    // MARK: - Constants

    private let margin: CGFloat = 4

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
        emojiLabel.numberOfLines = 1
        emojiLabel.textAlignment = .natural
        addSubview(emojiLabel)
    }

    // MARK: - Configure

    func configure(text: String, emojiCount: Int) {
        emojiLabel.text = text
        emojiLabel.font = .systemFont(ofSize: fontSize(for: emojiCount))

        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelSize = emojiLabel.sizeThatFits(CGSize(
            width: bounds.width - margin * 2,
            height: .greatestFiniteMagnitude
        ))
        emojiLabel.frame = CGRect(x: margin, y: margin, width: labelSize.width, height: labelSize.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let labelSize = emojiLabel.sizeThatFits(CGSize(
            width: .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        ))
        return CGSize(
            width: labelSize.width + margin * 2,
            height: labelSize.height + margin * 2
        )
    }

    // MARK: - Reuse

    func prepareForReuse() {
        emojiLabel.text = nil
    }

    // MARK: - Helpers

    private func fontSize(for count: Int) -> CGFloat {
        switch count {
        case 1: return 42
        case 2: return 36
        default: return 30
        }
    }
}
