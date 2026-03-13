//
//  UnreadDividerView.swift
//  NaarsCars
//
//  UICollectionViewCell — "X New Messages" divider shown above unread messages.
//

import UIKit

/// Collection view cell showing an unread-messages divider with a centered pill label
/// and horizontal hairlines extending to both edges.
final class UnreadDividerView: UICollectionViewCell {

    static let reuseIdentifier = "UnreadDividerView"
    static let fixedHeight: CGFloat = 30

    // MARK: - Subviews

    private let leftLine = UIView()
    private let rightLine = UIView()
    private let pillView = UIView()
    private let label = UILabel()

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
        let lineColor = UIColor.naarsPrimary.withAlphaComponent(0.25)
        leftLine.backgroundColor = lineColor
        rightLine.backgroundColor = lineColor
        contentView.addSubview(leftLine)
        contentView.addSubview(rightLine)

        pillView.backgroundColor = UIColor.naarsPrimary.withAlphaComponent(0.1)
        contentView.addSubview(pillView)

        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        label.font = UIFont(descriptor: descriptor, size: 0)
        label.textColor = .naarsPrimary
        label.textAlignment = .center
        pillView.addSubview(label)
    }

    // MARK: - Configure

    func configure(count: Int) {
        if count == 1 {
            label.text = NSLocalizedString("messaging_unread_divider_one", comment: "")
        } else {
            let format = NSLocalizedString("messaging_unread_divider_many", comment: "")
            label.text = String(format: format, count)
        }

        contentView.isAccessibilityElement = true
        contentView.accessibilityLabel = label.text
        contentView.accessibilityTraits = .header

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        let hPad: CGFloat = 8
        let vPad: CGFloat = 4
        let lineHeight: CGFloat = 1.0 / UIScreen.main.scale  // hairline
        let lineInset: CGFloat = 0

        let textSize = label.sizeThatFits(CGSize(width: b.width - 80, height: 20))
        let pillW = textSize.width + hPad * 2
        let pillH = textSize.height + vPad * 2
        let pillX = (b.width - pillW) / 2
        let pillY = (b.height - pillH) / 2

        pillView.frame = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        pillView.layer.cornerRadius = pillH / 2
        label.frame = CGRect(x: hPad, y: vPad, width: textSize.width, height: textSize.height)

        let lineY = b.height / 2 - lineHeight / 2
        leftLine.frame = CGRect(x: lineInset, y: lineY, width: pillX - lineInset - 6, height: lineHeight)
        rightLine.frame = CGRect(x: pillX + pillW + 6, y: lineY, width: b.width - (pillX + pillW + 6) - lineInset, height: lineHeight)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = nil
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: Self.fixedHeight)
    }
}
