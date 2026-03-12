//
//  ReplyPreviewView.swift
//  NaarsCars
//
//  UIKit reply preview — accent bar + sender name + preview text
//

import UIKit

/// Displays a compact preview of the message being replied to.
final class ReplyPreviewUIView: UIView {

    // MARK: - Subviews

    private let accentBar = UIView()
    private let senderLabel = UILabel()
    private let previewLabel = UILabel()
    private let photoIcon = UIImageView()

    // MARK: - State

    private var onTap: ((UUID) -> Void)?
    private var replyId: UUID?

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
        layer.cornerRadius = 10
        clipsToBounds = true

        accentBar.backgroundColor = UIColor.naarsPrimary
        accentBar.layer.cornerRadius = 1.5
        addSubview(accentBar)

        senderLabel.font = .preferredFont(forTextStyle: .footnote).withTraits(.traitBold)
        senderLabel.textColor = UIColor.naarsPrimary
        senderLabel.numberOfLines = 1
        addSubview(senderLabel)

        let iconConfig = UIImage.SymbolConfiguration(textStyle: .caption1)
        photoIcon.image = UIImage(systemName: "photo", withConfiguration: iconConfig)
        photoIcon.tintColor = .secondaryLabel
        photoIcon.isHidden = true
        addSubview(photoIcon)

        previewLabel.font = .preferredFont(forTextStyle: .footnote)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 3
        addSubview(previewLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    // MARK: - Configure

    func configure(reply: ReplyContext, isFromCurrentUser: Bool, onTap: ((UUID) -> Void)? = nil) {
        self.replyId = reply.id
        self.onTap = onTap

        senderLabel.text = reply.senderName
        previewLabel.text = reply.text.isEmpty ? NSLocalizedString("messaging_photo", comment: "") : reply.text
        photoIcon.isHidden = reply.imageUrl == nil

        backgroundColor = isFromCurrentUser
            ? UIColor.naarsPrimary.withAlphaComponent(0.12)
            : UIColor.systemGray5

        isAccessibilityElement = true
        accessibilityLabel = "\(senderLabel.text ?? ""), \(previewLabel.text ?? "")"
        accessibilityTraits = .button
        accessibilityHint = NSLocalizedString("accessibility_tap_to_scroll_to_reply", comment: "")

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let hPad: CGFloat = 10
        let vPad: CGFloat = 6
        let barW: CGFloat = 3
        let spacing: CGFloat = 8

        accentBar.frame = CGRect(x: hPad, y: vPad, width: barW, height: b.height - vPad * 2)

        let contentX = hPad + barW + spacing
        let contentW = b.width - contentX - hPad

        let senderH = senderLabel.sizeThatFits(CGSize(width: contentW, height: 20)).height
        senderLabel.frame = CGRect(x: contentX, y: vPad, width: contentW, height: senderH)

        let previewY = senderLabel.frame.maxY + 2
        if !photoIcon.isHidden {
            let iconS: CGFloat = 14
            photoIcon.frame = CGRect(x: contentX, y: previewY + 1, width: iconS, height: iconS)
            let labelX = photoIcon.frame.maxX + 4
            let previewW = contentW - iconS - 4
            let previewH = previewLabel.sizeThatFits(CGSize(width: previewW, height: 60)).height
            previewLabel.frame = CGRect(x: labelX, y: previewY, width: previewW, height: previewH)
        } else {
            let previewH = previewLabel.sizeThatFits(CGSize(width: contentW, height: 60)).height
            previewLabel.frame = CGRect(x: contentX, y: previewY, width: contentW, height: previewH)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let hPad: CGFloat = 10
        let vPad: CGFloat = 6
        let barW: CGFloat = 3
        let spacing: CGFloat = 8

        let contentW = min(size.width, 260) - hPad * 2 - barW - spacing
        let senderH = senderLabel.sizeThatFits(CGSize(width: contentW, height: 20)).height
        let previewH = previewLabel.sizeThatFits(CGSize(width: contentW, height: 60)).height
        let h = vPad + senderH + 2 + previewH + vPad
        return CGSize(width: min(size.width, 260), height: h)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        senderLabel.text = nil
        previewLabel.text = nil
        photoIcon.isHidden = true
        onTap = nil
        replyId = nil
    }

    // MARK: - Tap

    @objc private func handleTap() {
        guard let id = replyId else { return }
        onTap?(id)
    }
}

// MARK: - UIFont traits helper

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
