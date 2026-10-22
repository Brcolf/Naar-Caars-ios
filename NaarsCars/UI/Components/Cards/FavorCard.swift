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
    /// Name of the request's community; set only when the person belongs to several.
    var communityChipText: String? = nil
    /// How the request's community is joined; shown on every card whose community is known.
    var policy: CommunityJoinPolicy? = nil

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
        parts.append("favor_detail_requested_by".localized(with: favor.poster?.name ?? "community_former_member".localized))
        if !appState.isGuest {
            parts.append("card_favor_location_accessibility".localized(with: favor.location))
        }
        parts.append(favor.date.dateString)
        if let time = favor.time {
            parts.append(Date.displayTime(fromDatabaseTime: time))
        }
        parts.append(favor.duration.displayText)
        parts.append(favor.statusDisplayText)
        if favor.claimedBy != nil {
            parts.append("\("card_claimed_by".localized) \(favor.claimer?.name ?? "community_former_member".localized)")
        }
        if let communityChipText {
            parts.append("community_chip_accessibility".localized(with: communityChipText))
        }
        if let policy {
            parts.append("community_policy_accessibility".localized(with: policy.chipText))
        }
        if unreadCount > 0 {
            parts.append("common_unseen_notifications_accessibility".localized(with: unreadCount))
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var headerContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // At accessibility sizes the name hyphenates ("Bren-dan Col-ford") and the status
            // badge wraps mid-word beside it; stack the badges under the poster row instead.
            VStack(alignment: .leading, spacing: 8) {
                posterRow
                stackedChips
            }
        } else {
            // The chips sit beside the poster when they fit at full width. With the community
            // chip and the policy chip they often do not, and they go under the poster instead
            // of truncating ("Capit…", "As…").
            ViewThatFits(in: .horizontal) {
                HStack {
                    posterRow
                    Spacer()
                    chipsInOneRow
                }
                VStack(alignment: .leading, spacing: 8) {
                    posterRow
                    stackedChips
                }
            }
        }
    }

    private var posterRow: some View {
        HStack {
            if let poster = favor.poster {
                UserAvatarLink(profile: poster, size: 40)
            } else {
                AvatarView(imageUrl: nil, name: "community_former_member".localized, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let poster = favor.poster {
                    Text(poster.name)
                        .font(.naarsHeadline)
                        .lineLimit(2)
                } else {
                    Text("community_former_member".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.secondary)
                }

                Text(favor.date.dateString)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var chipsInOneRow: some View {
        HStack(spacing: 8) {
            chips
        }
    }

    /// The chips on one line when they fit, otherwise one under the other.
    private var stackedChips: some View {
        ViewThatFits(in: .horizontal) {
            chipsInOneRow
            VStack(alignment: .leading, spacing: 8) {
                chips
            }
        }
    }

    /// The unread count, the community chip, the join-policy chip and the status chip.
    @ViewBuilder
    private var chips: some View {
        NotificationBadge(count: unreadCount, cap: 9)
            .accessibilityLabel("common_unseen_notifications_accessibility".localized(with: unreadCount))
        if let communityChipText {
            NaarsChip(text: communityChipText, tint: nil)
                .accessibilityLabel("community_chip_accessibility".localized(with: communityChipText))
        }
        if let policy {
            CommunityPolicyChip(policy: policy)
        }
        NaarsChip(text: favor.statusDisplayText, tint: favor.status.color)
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

            claimedByRow
        }
    }

    /// "Claimed by" and the helper's name. At accessibility sizes the name goes under the label
    /// and may wrap, so neither breaks inside a word.
    private var claimedByRow: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return HStack(spacing: 0) {
            layout {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.naarsPrimary)
                        .font(.naarsSubheadline)
                    Text("card_claimed_by".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                // The label keeps its full width; a long name truncates instead.
                .layoutPriority(1)
                Text(favor.claimer?.name ?? "community_former_member".localized)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .foregroundColor(favor.claimer == nil ? .secondary : .primary)
                    .lineLimit(isAccessibilitySize ? 3 : 1)
            }
            Spacer(minLength: 0)
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
        ), policy: .invite)
        
        FavorCard(favor: Favor(
            userId: UUID(),
            title: "Pet sitting needed",
            location: "Downtown",
            duration: .coupleDays,
            date: Date().addingTimeInterval(86400),
            status: .confirmed
        ), policy: .open)
    }
    .padding()
    .environment(AppState())
}

#Preview("Former member poster") {
    FavorCard(favor: Favor(
        userId: UUID(),
        title: "Help moving boxes",
        location: "123 Main St",
        duration: .underHour,
        date: Date(),
        status: .open,
        poster: nil
    ))
    .padding()
    .environment(AppState())
}

#Preview("Former member claimer") {
    FavorCard(favor: Favor(
        userId: UUID(),
        title: "Help moving boxes",
        location: "123 Main St",
        duration: .underHour,
        date: Date(),
        status: .confirmed,
        claimedBy: UUID(),
        claimer: nil
    ))
    .padding()
    .environment(AppState())
}

#if DEBUG
#Preview("Three communities") {
    let _ = CommunityContext.shared.debugSetMemberships([
        CommunityMembership(communityId: UUID(), name: "Capitol Hill", description: nil, role: .member, status: .active, isPrimary: true, joinPolicy: "invite", isPublic: false, isDefault: false, membersCanInvite: true, timezone: "America/Los_Angeles", canInvite: true, memberCount: 1, pendingCount: nil, notificationsMuted: false, mutedUntil: nil, joinedAt: Date(timeIntervalSince1970: 0), activatedAt: nil),
        CommunityMembership(communityId: UUID(), name: "Ballard", description: nil, role: .member, status: .active, isPrimary: false, joinPolicy: "invite", isPublic: false, isDefault: false, membersCanInvite: true, timezone: "America/Los_Angeles", canInvite: true, memberCount: 1, pendingCount: nil, notificationsMuted: false, mutedUntil: nil, joinedAt: Date(timeIntervalSince1970: 0), activatedAt: nil),
        CommunityMembership(communityId: UUID(), name: "Fremont", description: nil, role: .member, status: .active, isPrimary: false, joinPolicy: "invite", isPublic: false, isDefault: false, membersCanInvite: true, timezone: "America/Los_Angeles", canInvite: true, memberCount: 1, pendingCount: nil, notificationsMuted: false, mutedUntil: nil, joinedAt: Date(timeIntervalSince1970: 0), activatedAt: nil)
    ])
    VStack(spacing: 16) {
        FavorCard(favor: Favor(
            userId: UUID(),
            title: "Help moving boxes",
            location: "123 Main St",
            duration: .underHour,
            date: Date(),
            status: .open
        ), unreadCount: 2, communityChipText: "Capitol Hill", policy: .approve)
    }
    .padding()
    .environment(AppState())
}
#endif
