//
//  CommunityBadges.swift
//  NaarsCars
//
//  The join-policy chip and the monogram circle shown for a community
//

import SwiftUI

/// A neutral chip naming how a community is joined (Open, Ask to join, Invite only).
struct CommunityPolicyChip: View {
    let policy: CommunityJoinPolicy
    var size: NaarsChip.Size = .regular

    var body: some View {
        NaarsChip(text: policy.chipText, systemImage: policy.systemImage, tint: nil, size: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: "community_policy_accessibility".localized, policy.chipText))
    }
}

/// A circle with the initials of a community's name, for communities that have no picture.
struct CommunityMonogram: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(Self.initials(for: name))
            .font(.naarsHeadline)
            .foregroundColor(.naarsPrimary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.naarsPrimary.opacity(0.12)))
            .accessibilityHidden(true)
    }

    /// The first letters of the first two words, uppercased; "?" for a blank name.
    static func initials(for name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }
}

#Preview("Policy chips") {
    VStack(alignment: .leading, spacing: 12) {
        CommunityPolicyChip(policy: .open)
        CommunityPolicyChip(policy: .approve)
        CommunityPolicyChip(policy: .invite, size: .large)
    }
    .padding()
    .background(Color.naarsBackground)
}

#Preview("Monograms") {
    HStack(spacing: 12) {
        CommunityMonogram(name: "Ballard Neighbors")
        CommunityMonogram(name: "test community seattle", size: 56)
        CommunityMonogram(name: "Solo")
    }
    .padding()
    .background(Color.naarsBackground)
}
