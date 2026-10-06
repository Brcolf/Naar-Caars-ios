//
//  LeaderboardRow.swift
//  NaarsCars
//
//  Leaderboard row component
//

import SwiftUI

/// Leaderboard row component
struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // One line cannot hold the rank, the name and the score at accessibility text
                // sizes (each broke a character or two per line), so the name and the score
                // get lines of their own under the rank and avatar.
                VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                    HStack(spacing: 12) {
                        rankBadge
                        avatar
                    }
                    nameText
                    xpScore
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    rankBadge
                    avatar
                    nameText
                    Spacer()
                    xpScore
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(entry.isCurrentUser ? Color.naarsPrimary.opacity(0.1) : Color.clear)
        .cornerRadius(Constants.Radius.sm)
        .contentShape(Rectangle())
    }

    /// Avatar with badge overlay
    private var avatar: some View {
        AvatarView(
            imageUrl: entry.avatarUrl,
            name: entry.name,
            size: 44,
            badges: entry.badges
        )
    }

    private var nameText: some View {
        Text(entry.name)
            .font(.naarsHeadline)
            .foregroundColor(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
    }

    /// XP score: the number over its unit beside the name, or the two on one line where the
    /// score has a line to itself (accessibility text sizes).
    private var xpScore: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Constants.Spacing.xs))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 2))
        return layout {
            Text("\(entry.xp)")
                .font(.naarsTitle3)
                .fontWeight(.semibold)
                .foregroundColor(.naarsPrimary)

            Text("leaderboard_xp".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("leaderboard_xp_accessibility".localized(with: entry.xp))
    }

    // A minimum, not a fixed width: 40 pt keeps the avatars in a column at standard sizes and
    // lets "#12" or a medal take the room it needs when the text is larger.
    @ViewBuilder
    private var rankBadge: some View {
        if let rank = entry.rank {
            switch rank {
            case 1:
                Text("🥇")
                    .font(.naarsTitle2)
                    .frame(minWidth: 40)
            case 2:
                Text("🥈")
                    .font(.naarsTitle2)
                    .frame(minWidth: 40)
            case 3:
                Text("🥉")
                    .font(.naarsTitle2)
                    .frame(minWidth: 40)
            default:
                Text("#\(rank)")
                    .font(.naarsHeadline)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 40)
            }
        } else {
            Text("—")
                .font(.naarsHeadline)
                .foregroundColor(.secondary)
                .frame(minWidth: 40)
        }
    }
}

#Preview {
    List {
        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: UUID(),
                name: "Bob M.",
                avatarUrl: nil,
                xp: 450,
                badges: [.roadWarrior, .bigSaver],
                streakWeeks: 5,
                requestsFulfilled: 15,
                requestsMade: 8,
                rank: 1
            )
        )

        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: UUID(),
                name: "Jane D.",
                avatarUrl: nil,
                xp: 310,
                badges: [.fiveStar],
                streakWeeks: 3,
                requestsFulfilled: 12,
                requestsMade: 5,
                rank: 2
            )
        )

        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: UUID(),
                name: "Sara K.",
                avatarUrl: nil,
                xp: 85,
                badges: [],
                streakWeeks: 0,
                requestsFulfilled: 8,
                requestsMade: 6,
                rank: 4
            )
        )
    }
    .listStyle(.plain)
}



