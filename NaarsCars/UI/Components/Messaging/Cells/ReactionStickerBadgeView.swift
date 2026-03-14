//
//  ReactionStickerBadgeView.swift
//  NaarsCars
//
//  Per-person iMessage-style speech-bubble reaction stickers.
//  Each MessageReaction gets its own bubble; overlapping left-to-right.
//

import UIKit

final class ReactionStickerBadgeView: UIView {

    // MARK: - Constants

    private static let stickerSize: CGFloat = 28
    private static let horizontalOverlap: CGFloat = 8
    private static let tailCornerRadius: CGFloat = 4
    private static let bodyCornerRadius: CGFloat = 14
    private static let maxCompactTypes = 3
    private static let compactThreshold = 4
    private static let borderWidth: CGFloat = 2

    // MARK: - Callbacks

    var onTap: (() -> Void)?

    // MARK: - State

    private var stickerViews: [UIView] = []
    private var currentReactions: [MessageReaction] = []
    private var currentUserId: UUID = UUID()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isAccessibilityElement = true
        accessibilityTraits = .button

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ReactionStickerBadgeView, _: UITraitCollection) in
            view.updateBorderColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Public API

    func configure(reactions: [MessageReaction], currentUserId: UUID) {
        self.currentUserId = currentUserId

        // Remove old stickers
        for v in stickerViews { v.removeFromSuperview() }
        stickerViews.removeAll()
        currentReactions = reactions

        let isCompact = uniqueReactionTypes(reactions).count >= Self.compactThreshold

        if isCompact {
            configureCompact(reactions: reactions)
        } else {
            configureExpanded(reactions: reactions, currentUserId: currentUserId)
        }

        updateAccessibility(reactions: reactions)
        setNeedsLayout()
    }

    func prepareForReuse() {
        for v in stickerViews { v.removeFromSuperview() }
        stickerViews.removeAll()
        currentReactions = []
        onTap = nil
    }

    // MARK: - Expanded Mode (per-person stickers)

    private func configureExpanded(reactions: [MessageReaction], currentUserId: UUID) {
        // Sort by createdAt ascending, ties broken by userId lexicographic
        let sorted = reactions.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.userId.uuidString < $1.userId.uuidString
        }

        for (index, reaction) in sorted.enumerated() {
            let sticker = makeStickerView(
                reaction: reaction.reaction,
                tintColor: reaction.userId == currentUserId ? .systemBlue : UIColor.systemGray.withAlphaComponent(0.6)
            )
            sticker.layer.zPosition = CGFloat(index)
            addSubview(sticker)
            stickerViews.append(sticker)
        }
    }

    // MARK: - Compact Mode (max 3 unique types, all gray)

    private func configureCompact(reactions: [MessageReaction]) {
        // Group by reaction type, pick top 3 by count (ties by earliest createdAt)
        let grouped = Dictionary(grouping: reactions, by: { $0.reaction })
        let topTypes = grouped
            .map { (reaction: $0.key, count: $0.value.count, earliest: $0.value.map(\.createdAt).min() ?? Date.distantFuture) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.earliest < $1.earliest
            }
            .prefix(Self.maxCompactTypes)

        for (index, typeInfo) in topTypes.enumerated() {
            let sticker = makeStickerView(
                reaction: typeInfo.reaction,
                tintColor: UIColor.systemGray.withAlphaComponent(0.6)
            )
            sticker.layer.zPosition = CGFloat(index)
            addSubview(sticker)
            stickerViews.append(sticker)
        }
    }

    // MARK: - Sticker Factory

    private func makeStickerView(reaction: String, tintColor: UIColor) -> UIView {
        let size = Self.stickerSize
        let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        container.backgroundColor = tintColor
        // Speech-bubble mask with asymmetric corners
        applySpeechBubbleMask(to: container, size: CGSize(width: size, height: size))

        // Content: emoji or HAHA artwork
        if TapbackArtwork.isHaha(reaction) {
            let imageView = UIImageView(image: TapbackArtwork.hahaImage(pointSize: size))
            imageView.contentMode = .scaleAspectFit
            let inset: CGFloat = 4
            imageView.frame = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
            container.addSubview(imageView)
        } else {
            let label = UILabel()
            label.text = reaction
            label.font = .systemFont(ofSize: size * 0.5)
            label.textAlignment = .center
            label.frame = CGRect(x: 0, y: 0, width: size, height: size)
            container.addSubview(label)
        }

        return container
    }

    private func applySpeechBubbleMask(to view: UIView, size: CGSize) {
        let body = Self.bodyCornerRadius
        let tail = Self.tailCornerRadius

        let path = UIBezierPath()
        // Start at top-left, after corner
        path.move(to: CGPoint(x: body, y: 0))
        // Top edge
        path.addLine(to: CGPoint(x: size.width - body, y: 0))
        // Top-right corner
        path.addArc(withCenter: CGPoint(x: size.width - body, y: body),
                     radius: body, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        // Right edge
        path.addLine(to: CGPoint(x: size.width, y: size.height - body))
        // Bottom-right corner
        path.addArc(withCenter: CGPoint(x: size.width - body, y: size.height - body),
                     radius: body, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        // Bottom edge
        path.addLine(to: CGPoint(x: tail, y: size.height))
        // Bottom-left corner (tail — small radius)
        path.addArc(withCenter: CGPoint(x: tail, y: size.height - tail),
                     radius: tail, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        // Left edge
        path.addLine(to: CGPoint(x: 0, y: body))
        // Top-left corner
        path.addArc(withCenter: CGPoint(x: body, y: body),
                     radius: body, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        path.close()

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        view.layer.mask = mask

        // Add a separate border sublayer that won't be clipped by the mask
        let borderLayer = CAShapeLayer()
        borderLayer.path = path.cgPath
        borderLayer.strokeColor = UIColor.systemBackground.cgColor
        borderLayer.lineWidth = Self.borderWidth
        borderLayer.fillColor = nil
        borderLayer.name = "stickerBorder"
        view.layer.addSublayer(borderLayer)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = Self.stickerSize
        let step = size - Self.horizontalOverlap

        for (index, sticker) in stickerViews.enumerated() {
            sticker.frame = CGRect(x: CGFloat(index) * step, y: 0, width: size, height: size)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let count = stickerViews.count
        guard count > 0 else { return .zero }
        let stickerSize = Self.stickerSize
        let step = stickerSize - Self.horizontalOverlap
        let totalWidth = stickerSize + step * CGFloat(count - 1)
        return CGSize(width: totalWidth, height: stickerSize)
    }

    // MARK: - Accessibility

    private func updateAccessibility(reactions: [MessageReaction]) {
        let types = uniqueReactionTypes(reactions)
        let typeNames = types.map { reactionName(for: $0) }
        let count = reactions.count
        let typesString = typeNames.joined(separator: ", ")
        accessibilityLabel = "\(count) \(count == 1 ? "reaction" : "reactions"): \(typesString)"
    }

    private func reactionName(for emoji: String) -> String {
        switch emoji {
        case "\u{2764}\u{FE0F}": return "heart"
        case "\u{1F44D}": return "thumbs up"
        case "\u{1F44E}": return "thumbs down"
        case "\u{1F602}": return "ha ha"
        case "\u{203C}\u{FE0F}": return "exclamation"
        case "\u{2753}": return "question mark"
        default: return emoji
        }
    }

    private func uniqueReactionTypes(_ reactions: [MessageReaction]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for r in reactions {
            if seen.insert(r.reaction).inserted {
                result.append(r.reaction)
            }
        }
        return result
    }

    // MARK: - Trait Changes

    private func updateBorderColors() {
        for sticker in stickerViews {
            if let sublayers = sticker.layer.sublayers {
                for sublayer in sublayers where sublayer.name == "stickerBorder" {
                    (sublayer as? CAShapeLayer)?.strokeColor = UIColor.systemBackground.cgColor
                }
            }
        }
    }

    // MARK: - Gesture

    @objc private func handleTap() {
        onTap?()
    }
}
