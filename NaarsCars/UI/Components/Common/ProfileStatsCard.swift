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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // Four columns leave about 50 pt each on a phone. At accessibility text sizes the
        // values and labels broke one or two characters per line, so the stats stack as
        // full-width rows there (label on the left, value on the right).
        // Real stacks, not AnyLayout: a Divider takes its direction from the stack around it,
        // and the default four-column form stays exactly the HStack it has always been.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Constants.Spacing.sm) {
                    stats
                }
            } else {
                HStack(spacing: 20) {
                    stats
                }
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.card, style: .continuous))
        .cardShadow()
    }

    /// The stat cells and the dividers between them; `body` puts them in a row or a column.
    @ViewBuilder
    private var stats: some View {
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

    @ViewBuilder
    private func statContent(icon: String, iconColor: Color, value: String, label: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // One stat per row; the label may wrap, the value keeps its width.
            HStack(spacing: Constants.Spacing.sm) {
                Image(systemName: icon)
                    .font(.naarsCaption)
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.naarsCaption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Constants.Spacing.sm)
                Text(value)
                    .font(.naarsHeadline)
                    .fontWeight(.bold)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), \(value)")
        } else {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.naarsCaption)
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.naarsHeadline)
                    .fontWeight(.bold)
                Text(label)
                    .font(.naarsCaption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), \(value)")
        }
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
