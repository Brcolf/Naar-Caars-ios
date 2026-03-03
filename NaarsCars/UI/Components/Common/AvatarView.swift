//
//  AvatarView.swift
//  NaarsCars
//
//  User avatar with AsyncImage and initials fallback
//

import SwiftUI

/// Avatar view with image loading and initials fallback
struct AvatarView: View {
    let imageUrl: String?
    let name: String
    var size: CGFloat = 50
    var badges: [LeaderboardBadge] = []
    var userId: UUID? = nil

    private var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        } else if !components.isEmpty {
            return String(components[0].prefix(2))
        }
        return "??"
    }

    /// Size of each badge background circle
    private var badgeContainerSize: CGFloat {
        size * 0.36
    }

    /// Font size for the emoji text
    private var badgeEmojiSize: CGFloat {
        size * 0.3
    }

    /// Radius from center of avatar to center of each badge
    private var badgeRingRadius: CGFloat {
        size / 2
    }

    /// Clock angles (degrees clockwise from 12 o'clock) for each badge count
    private var badgeAngles: [Double] {
        let displayBadges = Array(resolvedBadges.prefix(3))
        switch displayBadges.count {
        case 1: return [180]
        case 2: return [150, 210]
        case 3: return [120, 180, 240]
        default: return []
        }
    }

    private var resolvedBadges: [LeaderboardBadge] {
        if !badges.isEmpty { return badges }
        guard let userId = userId, size >= 40 else { return [] }
        return BadgeCache.shared.badges(for: userId)
    }

    var body: some View {
        ZStack {
            // Base avatar
            Group {
                if let imageUrl = imageUrl, !imageUrl.isEmpty {
                    CachedAsyncImage(
                        url: URL(string: imageUrl),
                        placeholder: { ProgressView() },
                        errorView: { initialsView }
                    )
                    .aspectRatio(contentMode: .fill)
                } else {
                    initialsView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            // Badge overlay
            let displayBadges = Array(resolvedBadges.prefix(3))
            let angles = badgeAngles
            ForEach(Array(zip(displayBadges.indices, displayBadges)), id: \.0) { index, badge in
                badgeView(emoji: badge.emoji)
                    .offset(
                        x: badgeOffset(angleDegrees: angles[index]).x,
                        y: badgeOffset(angleDegrees: angles[index]).y
                    )
            }
        }
        .frame(
            width: resolvedBadges.isEmpty ? size : size + badgeContainerSize,
            height: resolvedBadges.isEmpty ? size : size + badgeContainerSize
        )
        .accessibilityLabel("Avatar for \(name)")
    }

    private var initialsView: some View {
        Text(initials.uppercased())
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color.naarsPrimary)
            .clipShape(Circle())
    }

    /// Individual badge emoji in a circular container
    private func badgeView(emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: badgeEmojiSize))
            .frame(width: badgeContainerSize, height: badgeContainerSize)
            .background(Color(uiColor: .systemBackground))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    /// Compute offset for a badge given a clock angle (degrees clockwise from 12 o'clock)
    private func badgeOffset(angleDegrees: Double) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        let x = badgeRingRadius * sin(radians)
        let y = -badgeRingRadius * cos(radians)
        return CGPoint(x: x, y: y)
    }
}

#Preview {
    VStack(spacing: 30) {
        // No badges — original behavior
        HStack(spacing: 20) {
            AvatarView(imageUrl: nil, name: "John Doe")
            AvatarView(imageUrl: nil, name: "Jane Smith", size: 80)
            AvatarView(imageUrl: "https://example.com/avatar.jpg", name: "Bob Johnson")
        }

        // 1 badge
        AvatarView(imageUrl: nil, name: "One Badge", size: 80, badges: [.roadWarrior])

        // 2 badges
        AvatarView(imageUrl: nil, name: "Two Badges", size: 80, badges: [.roadWarrior, .fiveStar])

        // 3 badges
        AvatarView(imageUrl: nil, name: "Three Badges", size: 80, badges: [.roadWarrior, .fiveStar, .streakChampion])
    }
    .padding()
}
