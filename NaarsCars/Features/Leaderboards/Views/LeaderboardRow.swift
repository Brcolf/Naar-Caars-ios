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
            
            // Avatar
            AvatarView(
                imageUrl: entry.avatarUrl,
                name: entry.name,
                size: 44
            )
            
            // Name and stats
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Label("\(entry.requestsFulfilled)", systemImage: "checkmark.circle.fill")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    
                    Label("\(entry.requestsMade)", systemImage: "plus.circle")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Score (requests fulfilled)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.requestsFulfilled)")
                    .font(.naarsTitle3)
                    .fontWeight(.semibold)
                    .foregroundColor(.naarsPrimary)
                
                Text("fulfilled")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
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
                    .font(.title2)
                    .frame(width: 40)
            case 2:
                Text("🥈")
                    .font(.title2)
                    .frame(width: 40)
            case 3:
                Text("🥉")
                    .font(.title2)
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
                requestsFulfilled: 12,
                requestsMade: 5,
                rank: 2
            )
        )
        
        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: AuthService.shared.currentUserId ?? UUID(),
                name: "You",
                avatarUrl: nil,
                requestsFulfilled: 10,
                requestsMade: 3,
                rank: 3
            )
        )
        
        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: UUID(),
                name: "Sara K.",
                avatarUrl: nil,
                requestsFulfilled: 8,
                requestsMade: 6,
                rank: 4
            )
        )
    }
    .listStyle(.plain)
}


