//
//  UnsentMessageView.swift
//  NaarsCars
//
//  UIKit unsent message placeholder — a centered caption line, as in iMessage
//

import UIKit

/// Displays the line left behind by an unsent message ("You unsent a message").
///
/// iMessage shows this as plain secondary text in the transcript, not as a bubble. The earlier
/// outlined full-width pill with an icon read as a control, so it is now a centered caption in
/// the same style as the time headers and system lines.
final class UnsentMessageView: UIView {

    // MARK: - Layout constants

    private static let horizontalPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 6

    // MARK: - Subviews

    private let textLabel = UILabel()

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
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 2
        addSubview(textLabel)
    }

    // MARK: - Configure

    func configure(isFromCurrentUser: Bool) {
        // Set on every configure, like the other transcript cells: the row is measured once
        // per configuration, so a label that resized itself live would outgrow its row.
        textLabel.font = .preferredFont(forTextStyle: .caption1)
        textLabel.text = isFromCurrentUser
            ? "messaging_you_unsent_a_message".localized
            : "messaging_this_message_was_unsent".localized

        isAccessibilityElement = true
        accessibilityLabel = textLabel.text
        accessibilityTraits = .staticText

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        textLabel.frame = bounds.insetBy(dx: Self.horizontalPadding, dy: 0)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let availableWidth = max(0, size.width - Self.horizontalPadding * 2)
        let labelSize = textLabel.sizeThatFits(
            CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: size.width, height: ceil(labelSize.height) + Self.verticalPadding * 2)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        textLabel.text = nil
    }
}
