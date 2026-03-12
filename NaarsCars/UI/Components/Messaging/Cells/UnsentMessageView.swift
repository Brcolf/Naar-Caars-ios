//
//  UnsentMessageView.swift
//  NaarsCars
//
//  UIKit unsent message placeholder — "nosign" icon + italic text
//

import UIKit

/// Displays a placeholder for unsent (deleted) messages.
final class UnsentMessageView: UIView {

    // MARK: - Subviews

    private let iconView = UIImageView()
    private let textLabel = UILabel()
    private let borderLayer = CAShapeLayer()

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
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.systemGray4.cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)

        let config = UIImage.SymbolConfiguration(textStyle: .footnote)
        iconView.image = UIImage(systemName: "nosign", withConfiguration: config)
        iconView.tintColor = .secondaryLabel
        addSubview(iconView)

        textLabel.font = UIFont.italicSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize)
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 1
        addSubview(textLabel)
    }

    // MARK: - Configure

    func configure(isFromCurrentUser: Bool) {
        textLabel.text = isFromCurrentUser
            ? "messaging_you_unsent_a_message".localized
            : "messaging_this_message_was_unsent".localized
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let cornerRadius: CGFloat = 18
        borderLayer.path = UIBezierPath(roundedRect: b, cornerRadius: cornerRadius).cgPath

        let hPad: CGFloat = 14
        let spacing: CGFloat = 6
        let iconSize: CGFloat = 16

        iconView.frame = CGRect(x: hPad, y: (b.height - iconSize) / 2, width: iconSize, height: iconSize)

        let labelX = iconView.frame.maxX + spacing
        let labelW = b.width - labelX - hPad
        let labelSize = textLabel.sizeThatFits(CGSize(width: labelW, height: 20))
        textLabel.frame = CGRect(x: labelX, y: (b.height - labelSize.height) / 2, width: labelW, height: labelSize.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let hPad: CGFloat = 14
        let spacing: CGFloat = 6
        let iconSize: CGFloat = 16
        let labelSize = textLabel.sizeThatFits(CGSize(width: size.width - hPad * 2 - iconSize - spacing, height: 20))
        let w = hPad + iconSize + spacing + labelSize.width + hPad
        let h = max(labelSize.height, iconSize) + 20 // vPad 10 each side
        return CGSize(width: w, height: h)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        textLabel.text = nil
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            borderLayer.strokeColor = UIColor.systemGray4.cgColor
        }
    }
}
