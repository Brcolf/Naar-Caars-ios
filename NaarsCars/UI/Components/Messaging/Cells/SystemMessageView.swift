//
//  SystemMessageView.swift
//  NaarsCars
//
//  UIKit system message pill — centered icon + text
//

import UIKit

/// Centered pill view for system/announcement messages.
final class SystemMessageView: UIView {

    // MARK: - Subviews

    private let iconView = UIImageView()
    private let textLabel = UILabel()
    private let pillBackground = UIView()

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
        pillBackground.backgroundColor = UIColor.naarsCardBackground
        pillBackground.layer.masksToBounds = true
        addSubview(pillBackground)

        let config = UIImage.SymbolConfiguration(textStyle: .caption1)
        iconView.preferredSymbolConfiguration = config
        iconView.tintColor = .secondaryLabel
        pillBackground.addSubview(iconView)

        textLabel.font = .preferredFont(forTextStyle: .caption1)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        pillBackground.addSubview(textLabel)
    }

    // MARK: - Configure

    func configure(text: String, action: SystemAction) {
        textLabel.text = text
        iconView.image = UIImage(systemName: Self.iconName(for: action))

        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let hPad: CGFloat = 12
        let vPad: CGFloat = 6
        let spacing: CGFloat = 6
        let iconSize: CGFloat = 14

        let maxTextW = bounds.width - hPad * 2 - iconSize - spacing - 40 // margin
        let textSize = textLabel.sizeThatFits(CGSize(width: maxTextW, height: .greatestFiniteMagnitude))

        let pillW = hPad + iconSize + spacing + textSize.width + hPad
        let pillH = max(textSize.height, iconSize) + vPad * 2
        let pillX = (bounds.width - pillW) / 2
        let pillY = (bounds.height - pillH) / 2

        pillBackground.frame = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        pillBackground.layer.cornerRadius = pillH / 2

        iconView.frame = CGRect(x: hPad, y: (pillH - iconSize) / 2, width: iconSize, height: iconSize)
        textLabel.frame = CGRect(x: iconView.frame.maxX + spacing, y: vPad, width: textSize.width, height: textSize.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let hPad: CGFloat = 12
        let vPad: CGFloat = 6
        let spacing: CGFloat = 6
        let iconSize: CGFloat = 14

        let maxTextW = size.width - hPad * 2 - iconSize - spacing - 40
        let textSize = textLabel.sizeThatFits(CGSize(width: maxTextW, height: .greatestFiniteMagnitude))
        let w = hPad + iconSize + spacing + textSize.width + hPad
        let h = max(textSize.height, iconSize) + vPad * 2 + 16 // vertical padding around pill
        return CGSize(width: min(w + 40, size.width), height: h)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        textLabel.text = nil
        iconView.image = nil
    }

    // MARK: - Icon selection

    private static func iconName(for action: SystemAction) -> String {
        switch action {
        case .memberAdded: return "person.badge.plus"
        case .memberRemoved, .memberLeft: return "person.badge.minus"
        case .groupNameChanged: return "pencil"
        case .groupAvatarChanged: return "photo"
        case .groupCreated: return "sparkles"
        case .unknown: return "info.circle"
        }
    }
}
