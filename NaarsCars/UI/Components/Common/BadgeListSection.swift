//
//  BadgeListSection.swift
//  NaarsCars
//
//  Shared badge list showing earned/unearned badges
//

import SwiftUI

struct BadgeListSection: View {
    let earnedBadges: [LeaderboardBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("badge_section_title".localized)
                .font(.naarsHeadline)
                .foregroundColor(.primary)

            ForEach(LeaderboardBadge.allCases, id: \.self) { badge in
                HStack(spacing: 12) {
                    Text(badge.emoji)
                        .font(.title2)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.displayName)
                            .font(.naarsSubheadline)
                            .fontWeight(.medium)

                        Text(badge.badgeDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if earnedBadges.contains(badge) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.naarsSuccess)
                    }
                }
                .opacity(earnedBadges.contains(badge) ? 1.0 : 0.4)
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(12)
    }
}
