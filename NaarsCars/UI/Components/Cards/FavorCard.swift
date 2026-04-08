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
                        .frame(width: 4)
                        .cornerRadius(2),
                    alignment: .leading
                )
                .cornerRadius(12)
                .shadow(color: Color.primary.opacity(0.08), radius: 4, x: 0, y: 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Double-tap to view favor details")
            }
        }
    }

    private var badgeText: String? {
        guard unreadCount > 0 else { return nil }
        return unreadCount > 9 ? "9+" : "\(unreadCount)"
    }

    private var accessibilityLabel: String {
        if showsHiddenPlaceholder {
            return "requests_hidden_title".localized
        }

        return appState.isGuest
            ? "Favor \(favor.title) on \(favor.date.dateString), \(favor.status.displayText)"
            : "Favor \(favor.title) at \(favor.location) on \(favor.date.dateString), \(favor.status.displayText)"
    }

    @ViewBuilder
    private var headerContent: some View {
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
                } else {
                    Text("common_unknown_user".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.secondary)
                }

                Text(favor.date.dateString)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if let badgeText {
                    Text(badgeText)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .accessibilityLabel("\(unreadCount) unseen notifications")
                }

                Text(favor.status.displayText)
                    .font(.naarsCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(favor.status.color)
                    .cornerRadius(8)
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
                    .foregroundColor(.naarsAccent)
                    .font(.naarsCallout)
                Text(favor.duration.displayText)
                    .font(.naarsBody)
            }
        }

        HStack(spacing: 16) {
            if let time = favor.time {
                Label(time, systemImage: "clock")
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

