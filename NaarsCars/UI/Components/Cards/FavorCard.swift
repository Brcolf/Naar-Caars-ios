//
//  FavorCard.swift
//  NaarsCars
//
//  Card component for displaying favor requests
//

import SwiftUI

/// Card component for displaying favor requests
struct FavorCard: View {
    let favor: Favor
    var unreadCount: Int = 0

    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsHiddenPlaceholder: Bool {
        favor.isModerationHidden && AuthService.shared.currentUserId == favor.userId
    }

    private var hidesContentCompletely: Bool {
        favor.isModerationHidden && AuthService.shared.currentUserId != favor.userId
    }

    var body: some View {
        Group {
            if hidesContentCompletely {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    headerContent

                    Divider()

                    if showsHiddenPlaceholder {
                        hiddenPlaceholderContent
                    } else {
                        regularCardContent
                    }
                }
                .padding()
                .background(Color.naarsCardBackground)
                .overlay(
                    Rectangle()
                        .fill(Color.favorAccent)
                        .frame(width: 4),
                    alignment: .leading
                )
                .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.card, style: .continuous))
                .cardShadow()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("card_favor_details_hint".localized)
            }
        }
    }

    private var accessibilityLabel: String {
        if showsHiddenPlaceholder {
            return "requests_hidden_title".localized
        }

        // Everything the card shows, in reading order. The explicit label replaces the combined
        // children (which would read the decorative symbols and never say "Favor"), so it has
        // to carry the poster, time, duration, claimer and unread count itself. Guests get no
        // address, as on the card.
        var parts: [String] = ["common_favor".localized, favor.title]
        if let poster = favor.poster {
            parts.append("favor_detail_requested_by".localized(with: poster.name))
        }
        if !appState.isGuest {
            parts.append("card_favor_location_accessibility".localized(with: favor.location))
        }
        parts.append(favor.date.dateString)
        if let time = favor.time {
            parts.append(Date.displayTime(fromDatabaseTime: time))
        }
        parts.append(favor.duration.displayText)
        parts.append(favor.statusDisplayText)
        if favor.claimedBy != nil, let claimer = favor.claimer {
            parts.append("\("card_claimed_by".localized) \(claimer.name)")
        }
        if unreadCount > 0 {
            parts.append("common_unseen_notifications_accessibility".localized(with: unreadCount))
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var headerContent: some View {
        // At accessibility sizes the name hyphenates ("Bren-dan Col-ford") and the status
        // badge wraps mid-word beside it; stack the badges under the poster row instead.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        layout {
            HStack {
                if let poster = favor.poster {
                    UserAvatarLink(profile: poster, size: 40)
                } else {
                    AvatarView(imageUrl: nil, name: "Unknown", size: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let poster = favor.poster {
                        Text(poster.name)
                            .font(.naarsHeadline)
                            .lineLimit(2)
                    } else {
                        Text("common_unknown_user".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.secondary)
                    }

                    Text(favor.date.dateString)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }

            HStack(spacing: 8) {
                NotificationBadge(count: unreadCount, cap: 9)
                    .accessibilityLabel("common_unseen_notifications_accessibility".localized(with: unreadCount))
                NaarsChip(text: favor.statusDisplayText, tint: favor.status.color)
            }
        }
    }

    @ViewBuilder
    private var hiddenPlaceholderContent: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Label("requests_hidden_title".localized, systemImage: "eye.slash")
                .font(.naarsHeadline)
                .foregroundColor(.secondary)

            Text("requests_hidden_body".localized)
                .font(.naarsBody)
                .foregroundColor(.secondary)

            if let hiddenReason = favor.hiddenReason, !hiddenReason.isEmpty {
                Text("moderation_hidden_reason".localized(with: hiddenReason))
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var regularCardContent: some View {
        Text(favor.title)
            .font(.naarsTitle3)
            .lineLimit(2)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.favorAccent)
                    .font(.naarsCallout)
                AddressText(favor.location, isRedacted: appState.isGuest)
            }

            HStack(spacing: 8) {
                Image(systemName: favor.duration.icon)
                    .foregroundColor(.favorAccent)
                    .font(.naarsCallout)
                Text(favor.duration.displayText)
                    .font(.naarsBody)
            }
        }

        HStack(spacing: 16) {
            if let time = favor.time {
                Label(Date.displayTime(fromDatabaseTime: time), systemImage: "clock")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }

        if favor.claimedBy != nil {
            Divider()

            HStack(spacing: 8) {
                if let claimer = favor.claimer {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.naarsPrimary)
                        .font(.naarsSubheadline)
                    Text("card_claimed_by".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    Text(claimer.name)
                        .font(.naarsCaption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.naarsPrimary)
                        .font(.naarsSubheadline)
                    Text("card_claimed".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        FavorCard(favor: Favor(
            userId: UUID(),
            title: "Help moving boxes",
            location: "123 Main St",
            duration: .underHour,
            date: Date(),
            status: .open
        ))
        
        FavorCard(favor: Favor(
            userId: UUID(),
            title: "Pet sitting needed",
            location: "Downtown",
            duration: .coupleDays,
            date: Date().addingTimeInterval(86400),
            status: .confirmed
        ))
    }
    .padding()
}

