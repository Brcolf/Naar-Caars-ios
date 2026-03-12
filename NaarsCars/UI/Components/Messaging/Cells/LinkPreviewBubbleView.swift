//
//  LinkPreviewBubbleView.swift
//  NaarsCars
//
//  UIKit link preview card — full (thumbnail+title+domain) or compact (pill)
//

import UIKit

/// Pure UIKit link preview bubble with generation counter for async metadata fetch.
final class LinkPreviewBubbleView: UIView {

    // MARK: - Full preview subviews

    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    private let chevronView = UIImageView()
    private let cardBackground = UIView()

    // MARK: - Compact pill subviews

    private let pillContainer = UIView()
    private let pillIcon = UIImageView()
    private let pillLabel = UILabel()

    // MARK: - State

    private var loadGeneration: UInt64 = 0
    private var url: URL?
    private var isFromCurrentUser = false
    private var isCompact = false

    // MARK: - Constants

    private let thumbSize: CGFloat = 60
    private let maxWidth: CGFloat = 260

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
        // Full card
        cardBackground.layer.cornerRadius = 12
        cardBackground.clipsToBounds = true
        addSubview(cardBackground)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        cardBackground.addSubview(thumbnailView)

        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.numberOfLines = 2
        cardBackground.addSubview(titleLabel)

        domainLabel.font = .preferredFont(forTextStyle: .caption1)
        domainLabel.numberOfLines = 1
        cardBackground.addSubview(domainLabel)

        let chevConfig = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        chevronView.image = UIImage(systemName: "chevron.right", withConfiguration: chevConfig)
        cardBackground.addSubview(chevronView)

        // Compact pill
        pillContainer.layer.cornerRadius = 14
        pillContainer.clipsToBounds = true
        addSubview(pillContainer)

        let linkConfig = UIImage.SymbolConfiguration(textStyle: .footnote)
        pillIcon.image = UIImage(systemName: "link", withConfiguration: linkConfig)
        pillContainer.addSubview(pillIcon)

        pillLabel.font = .preferredFont(forTextStyle: .footnote)
        pillLabel.numberOfLines = 1
        pillContainer.addSubview(pillLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(openLink))
        addGestureRecognizer(tap)
    }

    // MARK: - Configure

    func configure(url: URL, isFromCurrentUser: Bool) {
        self.url = url
        self.isFromCurrentUser = isFromCurrentUser
        let prefValue = UserDefaults.standard.object(forKey: "messaging_showLinkPreviews") as? Bool ?? true
        self.isCompact = !prefValue

        applyColors()

        if isCompact {
            cardBackground.isHidden = true
            pillContainer.isHidden = false
            pillLabel.text = url.host ?? url.absoluteString
        } else {
            cardBackground.isHidden = false
            pillContainer.isHidden = true

            thumbnailView.image = nil
            titleLabel.text = nil
            domainLabel.text = url.host ?? url.absoluteString

            loadGeneration &+= 1
            let gen = loadGeneration

            Task { [weak self] in
                let preview = await LinkPreviewService.shared.fetchPreview(for: url)
                guard let self, self.loadGeneration == gen else { return }
                if let data = preview?.imageData, let img = UIImage(data: data) {
                    self.thumbnailView.image = img
                }
                self.titleLabel.text = preview?.title
                self.domainLabel.text = preview?.siteName ?? url.host ?? url.absoluteString
                self.setNeedsLayout()
            }
        }
        setNeedsLayout()
    }

    private func applyColors() {
        if isFromCurrentUser {
            cardBackground.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            titleLabel.textColor = .white
            domainLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            chevronView.tintColor = UIColor.white.withAlphaComponent(0.5)
            pillContainer.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            pillIcon.tintColor = UIColor.white.withAlphaComponent(0.9)
            pillLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        } else {
            cardBackground.backgroundColor = UIColor.naarsCardBackground
            titleLabel.textColor = .label
            domainLabel.textColor = .secondaryLabel
            chevronView.tintColor = .secondaryLabel
            pillContainer.backgroundColor = UIColor.naarsPrimary.withAlphaComponent(0.1)
            pillIcon.tintColor = UIColor.naarsPrimary
            pillLabel.textColor = UIColor.naarsPrimary
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds

        if isCompact {
            let iconW: CGFloat = 16
            let pad: CGFloat = 10
            let labelSize = pillLabel.sizeThatFits(CGSize(width: 200, height: 20))
            let pillW = pad + iconW + 6 + labelSize.width + pad
            let pillH: CGFloat = 28
            pillContainer.frame = CGRect(x: 0, y: 0, width: min(pillW, b.width), height: pillH)
            pillIcon.frame = CGRect(x: pad, y: (pillH - iconW) / 2, width: iconW, height: iconW)
            pillLabel.frame = CGRect(x: pillIcon.frame.maxX + 6, y: 0, width: labelSize.width, height: pillH)
        } else {
            cardBackground.frame = b
            let pad: CGFloat = 10
            let chevW: CGFloat = 14

            let showThumb = thumbnailView.image != nil
            let thumbX: CGFloat = pad
            let thumbY: CGFloat = pad
            if showThumb {
                thumbnailView.frame = CGRect(x: thumbX, y: thumbY, width: thumbSize, height: thumbSize)
                thumbnailView.isHidden = false
            } else {
                thumbnailView.isHidden = true
            }

            let textX = showThumb ? thumbX + thumbSize + 10 : pad
            let textMaxW = b.width - textX - pad - chevW - 8
            let titleSize = titleLabel.sizeThatFits(CGSize(width: textMaxW, height: 40))
            let domainSize = domainLabel.sizeThatFits(CGSize(width: textMaxW, height: 20))

            let textBlockH = titleSize.height + 4 + domainSize.height
            let textY = (b.height - textBlockH) / 2
            titleLabel.frame = CGRect(x: textX, y: textY, width: textMaxW, height: titleSize.height)
            domainLabel.frame = CGRect(x: textX, y: titleLabel.frame.maxY + 4, width: textMaxW, height: domainSize.height)

            chevronView.sizeToFit()
            chevronView.center = CGPoint(x: b.width - pad - chevW / 2, y: b.midY)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if isCompact {
            let iconW: CGFloat = 16
            let pad: CGFloat = 10
            let labelSize = pillLabel.sizeThatFits(CGSize(width: 200, height: 20))
            return CGSize(width: min(pad + iconW + 6 + labelSize.width + pad, maxWidth), height: 28)
        } else {
            return CGSize(width: maxWidth, height: thumbSize + 20)
        }
    }

    // MARK: - Reuse

    func prepareForReuse() {
        loadGeneration &+= 1
        thumbnailView.image = nil
        titleLabel.text = nil
        domainLabel.text = nil
        pillLabel.text = nil
        url = nil
    }

    // MARK: - Tap

    @objc private func openLink() {
        guard let url else { return }
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }
}
