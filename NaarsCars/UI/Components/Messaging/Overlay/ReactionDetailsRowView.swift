//
//  ReactionDetailsRowView.swift
//  NaarsCars
//
//  Horizontal scrollable row showing individual reaction stickers with
//  avatar circles below, displayed in the message overlay when the user
//  taps a reaction badge.
//

import UIKit

final class ReactionDetailsRowView: UIView {

    // MARK: - Constants

    private enum Layout {
        static let stickerSize: CGFloat = 50
        static let avatarSize: CGFloat = 24
        static let avatarOverlap: CGFloat = 6
        static let itemSpacing: CGFloat = 12
        static let verticalSpacing: CGFloat = 4
        static let cornerRadius: CGFloat = 16
        static let contentInset: CGFloat = 12
        static let tailCornerRadius: CGFloat = 6
        static let bodyCornerRadius: CGFloat = 20
        static let borderWidth: CGFloat = 2
    }

    // MARK: - Callbacks

    var onRemoveReaction: ((String) -> Void)?

    // MARK: - State

    private var currentUserId: UUID = UUID()
    private var itemViews: [UIView] = []

    // MARK: - Subviews

    private let blurView: UIVisualEffectView = {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = Layout.cornerRadius
        blur.clipsToBounds = true
        return blur
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceHorizontal = true
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.spacing = Layout.itemSpacing
        sv.alignment = .top
        return sv
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(blurView)
        blurView.contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Layout.contentInset),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Layout.contentInset),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Layout.contentInset),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Layout.contentInset),
        ])
    }

    // MARK: - Public API

    func configure(reactions: [MessageReaction], profiles: [UUID: Profile], currentUserId: UUID) {
        self.currentUserId = currentUserId
        clearItems()

        // Group by reaction type
        let grouped = Dictionary(grouping: reactions, by: { $0.reaction })

        // Sort groups: count descending, ties by earliest createdAt
        let sortedGroups = grouped
            .map { (reaction: $0.key, items: $0.value) }
            .sorted {
                if $0.items.count != $1.items.count {
                    return $0.items.count > $1.items.count
                }
                let earliest0 = $0.items.map(\.createdAt).min() ?? .distantFuture
                let earliest1 = $1.items.map(\.createdAt).min() ?? .distantFuture
                return earliest0 < earliest1
            }

        for group in sortedGroups {
            // Within each group, order avatars by createdAt ascending
            let sortedItems = group.items.sorted { $0.createdAt < $1.createdAt }
            let itemView = makeGroupItemView(
                reaction: group.reaction,
                reactions: sortedItems,
                profiles: profiles
            )
            stackView.addArrangedSubview(itemView)
            itemViews.append(itemView)
        }

        isAccessibilityElement = false
        accessibilityElements = itemViews
    }

    func prepareForReuse() {
        clearItems()
        onRemoveReaction = nil
    }

    // MARK: - Private Helpers

    private func clearItems() {
        for v in itemViews { v.removeFromSuperview() }
        itemViews.removeAll()
    }

    private func makeGroupItemView(reaction: String, reactions: [MessageReaction], profiles: [UUID: Profile]) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Sticker
        let sticker = makeStickerView(reaction: reaction)
        container.addSubview(sticker)

        // Avatar row
        let avatarRow = makeAvatarRow(reactions: reactions, profiles: profiles)
        container.addSubview(avatarRow)

        let stickerWidth = Layout.stickerSize
        let avatarRowWidth = avatarRowWidth(count: reactions.count)
        let totalWidth = max(stickerWidth, avatarRowWidth)
        let totalHeight = Layout.stickerSize + Layout.verticalSpacing + Layout.avatarSize

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: totalWidth),
            container.heightAnchor.constraint(equalToConstant: totalHeight),
        ])

        // Center sticker horizontally
        sticker.frame = CGRect(
            x: (totalWidth - stickerWidth) / 2,
            y: 0,
            width: stickerWidth,
            height: Layout.stickerSize
        )

        // Center avatar row horizontally
        avatarRow.frame = CGRect(
            x: (totalWidth - avatarRowWidth) / 2,
            y: Layout.stickerSize + Layout.verticalSpacing,
            width: avatarRowWidth,
            height: Layout.avatarSize
        )

        // Tap gesture: only own reactions are removable
        let containsOwnReaction = reactions.contains { $0.userId == currentUserId }
        if containsOwnReaction {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleGroupTap(_:)))
            container.addGestureRecognizer(tap)
            container.tag = reaction.hashValue
            container.accessibilityTraits = .button
            container.accessibilityHint = NSLocalizedString("accessibility_reaction_remove_hint", comment: "")

            // Store reaction string in accessibility identifier for retrieval on tap
            container.accessibilityIdentifier = "details.reaction.\(reaction)"
        }

        container.isAccessibilityElement = true
        let reactionName = accessibleReactionName(for: reaction)
        let names = reactions.compactMap { profiles[$0.userId]?.name ?? "Unknown" }
        container.accessibilityLabel = "\(reactionName) by \(names.joined(separator: ", "))"

        return container
    }

    private func makeStickerView(reaction: String) -> UIView {
        let size = Layout.stickerSize
        let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        container.backgroundColor = UIColor.systemGray.withAlphaComponent(0.6)

        // Speech-bubble mask with asymmetric corners (same as ReactionStickerBadgeView)
        applySpeechBubbleMask(to: container, size: CGSize(width: size, height: size))

        if TapbackArtwork.isHaha(reaction) {
            let imageView = UIImageView(image: TapbackArtwork.hahaImage(pointSize: size))
            imageView.contentMode = .scaleAspectFit
            imageView.accessibilityLabel = "Ha ha"
            let inset: CGFloat = 6
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
        let body = Layout.bodyCornerRadius
        let tail = Layout.tailCornerRadius

        let path = UIBezierPath()
        path.move(to: CGPoint(x: body, y: 0))
        path.addLine(to: CGPoint(x: size.width - body, y: 0))
        path.addArc(withCenter: CGPoint(x: size.width - body, y: body),
                     radius: body, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: size.width, y: size.height - body))
        path.addArc(withCenter: CGPoint(x: size.width - body, y: size.height - body),
                     radius: body, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: tail, y: size.height))
        path.addArc(withCenter: CGPoint(x: tail, y: size.height - tail),
                     radius: tail, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: body))
        path.addArc(withCenter: CGPoint(x: body, y: body),
                     radius: body, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        path.close()

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        view.layer.mask = mask
    }

    private func makeAvatarRow(reactions: [MessageReaction], profiles: [UUID: Profile]) -> UIView {
        let count = reactions.count
        let rowWidth = avatarRowWidth(count: count)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: rowWidth, height: Layout.avatarSize))

        let step = Layout.avatarSize - Layout.avatarOverlap

        for (index, reaction) in reactions.enumerated() {
            let profile = profiles[reaction.userId]
            let avatar = makeAvatarCircle(profile: profile)
            avatar.frame = CGRect(
                x: CGFloat(index) * step,
                y: 0,
                width: Layout.avatarSize,
                height: Layout.avatarSize
            )
            avatar.layer.zPosition = CGFloat(index)
            container.addSubview(avatar)
        }

        return container
    }

    private func avatarRowWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let step = Layout.avatarSize - Layout.avatarOverlap
        return Layout.avatarSize + step * CGFloat(count - 1)
    }

    private func makeAvatarCircle(profile: Profile?) -> UIView {
        let size = Layout.avatarSize
        let circle = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        circle.layer.cornerRadius = size / 2
        circle.clipsToBounds = true
        circle.layer.borderWidth = 1.5
        circle.layer.borderColor = UIColor.systemBackground.cgColor

        if let avatarUrlString = profile?.avatarUrl, let url = URL(string: avatarUrlString) {
            // Use async image loading
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.frame = circle.bounds
            imageView.clipsToBounds = true
            circle.addSubview(imageView)

            Task { @MainActor in
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    imageView.image = image
                }
            }
        } else {
            // Show initials
            let initial = profile?.name.first.map(String.init) ?? "?"
            let label = UILabel(frame: circle.bounds)
            label.text = initial.uppercased()
            label.font = .systemFont(ofSize: size * 0.45, weight: .semibold)
            label.textAlignment = .center
            label.textColor = .white

            // Deterministic color from name
            let colorIndex = abs((profile?.name ?? "").hashValue) % avatarColors.count
            circle.backgroundColor = avatarColors[colorIndex]

            circle.addSubview(label)
        }

        return circle
    }

    private let avatarColors: [UIColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPurple,
        .systemPink, .systemTeal, .systemIndigo, .systemRed
    ]

    // MARK: - Gesture

    @objc private func handleGroupTap(_ gesture: UITapGestureRecognizer) {
        guard let container = gesture.view,
              let identifier = container.accessibilityIdentifier,
              identifier.hasPrefix("details.reaction.") else { return }
        let reaction = String(identifier.dropFirst("details.reaction.".count))
        onRemoveReaction?(reaction)
    }

    // MARK: - Accessibility

    private func accessibleReactionName(for emoji: String) -> String {
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
}
