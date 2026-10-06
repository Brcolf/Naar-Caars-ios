//
//  NotificationBadge.swift
//  NaarsCars
//
//  The count badge and the label chip: the two small capsules used across cards, rows and tiles
//

import SwiftUI

/// Unread-count capsule. The one badge recipe: use it wherever a count sits on a card, tile,
/// row or toolbar icon instead of building another capsule inline.
struct NotificationBadge: View {
    enum Style {
        /// Needs attention: `naarsBadge` red, the same meaning as the tab bar badge
        case alert
        /// Counted but silenced, such as a muted conversation
        case muted
    }

    let count: Int
    var style: Style = .alert
    /// Largest number shown before the badge reads "N+"
    var cap: Int = 99

    var body: some View {
        if count > 0 {
            Text(count > cap ? "\(cap)+" : "\(count)")
                .font(.naarsCaption2).fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 18)
                .background(style == .alert ? Color.naarsBadge : Color.naarsBadgeMuted)
                .clipShape(Capsule())
                .fixedSize()
        }
    }
}

/// Short label on a tinted capsule: request status, post type, invite state.
/// The text takes the tint and the fill is the same tint at 12%, so one color carries the
/// meaning and the label stays readable in both appearances.
struct NaarsChip: View {
    enum Size {
        /// Caption, for cards and rows
        case regular
        /// Subheadline, for the header of a detail screen
        case large
    }

    let text: String
    var systemImage: String? = nil
    /// `nil` draws a neutral chip: secondary text on the inset fill
    var tint: Color? = Color.naarsPrimary
    var size: Size = .regular

    var body: some View {
        HStack(spacing: Constants.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(size == .large ? Font.naarsCaption : Font.naarsCaption2)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(size == .large ? Font.naarsSubheadline : Font.naarsCaption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundColor(tint ?? .secondary)
        .padding(.horizontal, size == .large ? Constants.Spacing.ms : Constants.Spacing.sm)
        .padding(.vertical, size == .large ? 6 : Constants.Spacing.xs)
        .background(tint.map { $0.opacity(0.12) } ?? Color.naarsInsetBackground)
        .clipShape(Capsule())
    }
}

#Preview("Badges") {
    HStack(spacing: 20) {
        NotificationBadge(count: 0)
        NotificationBadge(count: 5)
        NotificationBadge(count: 12, cap: 9)
        NotificationBadge(count: 150)
        NotificationBadge(count: 3, style: .muted)
    }
    .padding()
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            NaarsChip(text: "Open", tint: .naarsSuccess)
            NaarsChip(text: "Pending", tint: .naarsWarning)
            NaarsChip(text: "Claimed", tint: .naarsPrimary)
            NaarsChip(text: "Completed", tint: nil)
        }
        HStack {
            NaarsChip(text: "Announcement", systemImage: "megaphone.fill")
            NaarsChip(text: "Review", systemImage: "star.fill", tint: .naarsWarning)
        }
        NaarsChip(text: "Claimed", tint: .naarsPrimary, size: .large)
    }
    .padding()
}
