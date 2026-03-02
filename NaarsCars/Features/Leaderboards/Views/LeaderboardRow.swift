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
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            rankBadge
            
            // Avatar with badge overlay
            AvatarView(
                imageUrl: entry.avatarUrl,
                name: entry.name,
                size: 44,
                badges: entry.badges
            )

            // Name
            Text(entry.name)
                .font(.naarsHeadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // XP score
            VStack(alignment: .trailing, spacing: 2) {
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(entry.isCurrentUser ? Color.naarsPrimary.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var rankBadge: some View {
        if let rank = entry.rank {
            switch rank {
            case 1:
                Text("🥇")
                    .font(.naarsTitle2)
                    .frame(width: 40)
            case 2:
                Text("🥈")
                    .font(.naarsTitle2)
                    .frame(width: 40)
            case 3:
                Text("🥉")
                    .font(.naarsTitle2)
                    .frame(width: 40)
            default:
                Text("#\(rank)")
                    .font(.naarsHeadline)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
        } else {
            Text("—")
                .font(.naarsHeadline)
                .foregroundColor(.secondary)
                .frame(width: 40)
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



