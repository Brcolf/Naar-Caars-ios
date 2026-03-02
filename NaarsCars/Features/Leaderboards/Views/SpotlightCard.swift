//
//  SpotlightCard.swift
//  NaarsCars
//
//  Compact card for a leaderboard spotlight winner
//

import SwiftUI

struct SpotlightCard: View {
    let spotlight: SpotlightEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: spotlight.iconName)
                .font(.naarsTitle3)
                .foregroundColor(.naarsPrimary)
                .frame(width: 32)

            AvatarView(
                imageUrl: spotlight.avatarUrl,
                name: spotlight.name,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(spotlight.displayCategory)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)

                Text(spotlight.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.primary)
            }

            Spacer()

            Text(spotlight.formattedValue)
                .font(.naarsSubheadline)
                .fontWeight(.semibold)
                .foregroundColor(.naarsPrimary)
        }
        .padding(12)
        .background(Color.naarsCardBackground)
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spotlight.displayCategory): \(spotlight.name), \(spotlight.formattedValue)")
    }
}
