//
//  ProfileStatsCard.swift
//  NaarsCars
//
//  Reusable stats card showing rating, savings, fulfilled count, and XP
//

import SwiftUI

/// A reusable card that displays profile statistics
/// Used by both MyProfileView (interactive) and PublicProfileView (static)
struct ProfileStatsCard: View {
    let rating: Double?
    let totalSavings: Double?
    let fulfilledCount: Int
    let xp: Int?

    // Optional tap actions (nil = non-interactive)
    var onRatingTap: (() -> Void)?
    var onSavingsTap: (() -> Void)?
    var onFulfilledTap: (() -> Void)?
    var onXPTap: (() -> Void)?

    /// Full initializer with all 4 stats and tap actions (used by MyProfileView)
    init(
        rating: Double?,
        totalSavings: Double,
        fulfilledCount: Int,
        xp: Int,
        onRatingTap: (() -> Void)? = nil,
        onSavingsTap: (() -> Void)? = nil,
        onFulfilledTap: (() -> Void)? = nil,
        onXPTap: (() -> Void)? = nil
    ) {
        self.rating = rating
        self.totalSavings = totalSavings
        self.fulfilledCount = fulfilledCount
        self.xp = xp
        self.onRatingTap = onRatingTap
        self.onSavingsTap = onSavingsTap
        self.onFulfilledTap = onFulfilledTap
        self.onXPTap = onXPTap
    }

    /// Minimal initializer without savings/XP (used by PublicProfileView)
    init(rating: Double?, fulfilledCount: Int) {
        self.rating = rating
        self.totalSavings = nil
        self.fulfilledCount = fulfilledCount
        self.xp = nil
    }

    var body: some View {
        HStack(spacing: 20) {
            // Rating
            statColumn(
                icon: "star.fill",
                iconColor: .naarsPrimary,
                value: rating.map { String(format: "%.1f", $0) } ?? "—",
                label: rating != nil ? "Rating" : "No Rating",
                action: onRatingTap
            )

            if totalSavings != nil || xp != nil {
                Divider()
            }

            // My Savings (only shown in full mode)
            if let savings = totalSavings {
                statColumn(
                    icon: "dollarsign.circle.fill",
                    iconColor: .naarsSuccess,
                    value: formatSavings(savings),
                    label: "My Savings",
                    action: onSavingsTap
                )

                Divider()
            }

            // Fulfilled
            statColumn(
                icon: "checkmark.circle.fill",
                iconColor: .naarsSuccess,
                value: "\(fulfilledCount)",
                label: "Fulfilled",
                action: onFulfilledTap
            )

            // XP (only shown in full mode)
            if let xpValue = xp {
                Divider()

                statColumn(
                    icon: "bolt.fill",
                    iconColor: .naarsWarning,
                    value: "\(xpValue)",
                    label: "XP",
                    action: onXPTap
                )
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statColumn(icon: String, iconColor: Color, value: String, label: String, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                statContent(icon: icon, iconColor: iconColor, value: value, label: label)
            }
            .buttonStyle(.plain)
        } else {
            statContent(icon: icon, iconColor: iconColor, value: value, label: label)
        }
    }

    private func statContent(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.naarsCaption)
                .foregroundColor(iconColor)
            Text(value)
                .font(.naarsHeadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func formatSavings(_ amount: Double) -> String {
        if amount >= 1000 {
            return "$\(Int(amount / 1000))k"
        }
        return "$\(Int(amount))"
    }
}

#Preview {
    VStack(spacing: 20) {
        ProfileStatsCard(
            rating: 4.5,
            totalSavings: 1240,
            fulfilledCount: 8,
            xp: 350
        )
        ProfileStatsCard(rating: nil, fulfilledCount: 3)
    }
    .padding()
}
