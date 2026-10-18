//
//  RideCard.swift
//  NaarsCars
//
//  Card component for displaying ride requests
//

import SwiftUI

/// Card component for displaying ride requests
struct RideCard: View {
    let ride: Ride
    var unreadCount: Int = 0
    /// Name of the request's community; set only when the person belongs to several.
    var communityChipText: String? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsHiddenPlaceholder: Bool {
        ride.isModerationHidden && AuthService.shared.currentUserId == ride.userId
    }

    private var hidesContentCompletely: Bool {
        ride.isModerationHidden && AuthService.shared.currentUserId != ride.userId
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
                        .fill(Color.rideAccent)
                        .frame(width: 4),
                    alignment: .leading
                )
                .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.card, style: .continuous))
                .cardShadow()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("card_ride_details_hint".localized)
            }
        }
    }

    private var accessibilityLabel: String {
        if showsHiddenPlaceholder {
            return "requests_hidden_title".localized
        }

        // Everything the card shows, in reading order. The explicit label replaces the combined
        // children (which would read the decorative symbols and never say "Ride"), so it has
        // to carry the poster, time, seats, flight, claimer and unread count itself. Guests
        // get no addresses, as on the card.
        var parts: [String] = ["common_ride".localized]
        parts.append("ride_detail_requested_by".localized(with: ride.poster?.name ?? "community_former_member".localized))
        if !appState.isGuest {
            parts.append("card_ride_route_accessibility".localized(with: ride.pickup, ride.destination))
        }
        parts.append(ride.date.dateString)
        parts.append(Date.displayTime(fromDatabaseTime: ride.time))
        parts.append(ride.seatsDisplayText)
        if let flightInfo = FlightInfo.displayInfo(for: ride) {
            parts.append("\("ride_detail_flight".localized) \(flightInfo.normalizedFlightNumber)")
        }
        parts.append(ride.statusDisplayText)
        if ride.claimedBy != nil {
            parts.append("\("card_claimed_by".localized) \(ride.claimer?.name ?? "community_former_member".localized)")
        }
        if let communityChipText {
            parts.append("community_chip_accessibility".localized(with: communityChipText))
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
                if let poster = ride.poster {
                    UserAvatarLink(profile: poster, size: 40)
                } else {
                    AvatarView(imageUrl: nil, name: "community_former_member".localized, size: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let poster = ride.poster {
                        Text(poster.name)
                            .font(.naarsHeadline)
                            .lineLimit(2)
                    } else {
                        Text("community_former_member".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.secondary)
                    }

                    Text(ride.date.dateString)
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
                if let communityChipText {
                    NaarsChip(text: communityChipText, tint: nil)
                        .accessibilityLabel("community_chip_accessibility".localized(with: communityChipText))
                }
                NaarsChip(text: ride.statusDisplayText, tint: ride.status.color)
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

            if let hiddenReason = ride.hiddenReason, !hiddenReason.isEmpty {
                Text("moderation_hidden_reason".localized(with: hiddenReason))
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var regularCardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .foregroundColor(.naarsSuccess)
                    .font(.naarsCaption)
                AddressText(ride.pickup, isRedacted: appState.isGuest)
            }

            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 16)
                    .padding(.leading, 4)
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.rideAccent)
                    .font(.naarsCallout)
                AddressText(ride.destination, isRedacted: appState.isGuest)
            }
        }

        // Stacked at accessibility sizes, where side by side the seats label broke inside the word.
        timeAndSeatsLayout {
            Label(Date.displayTime(fromDatabaseTime: ride.time), systemImage: "clock")
                .font(.naarsCaption)
                .foregroundColor(.secondary)

            Label(ride.seatsDisplayText, systemImage: "person.2")
                .font(.naarsCaption)
                .foregroundColor(.secondary)
        }

        if let flightInfo = FlightInfo.displayInfo(for: ride) {
            FlightRowView(flightInfo: flightInfo, style: .compact)
        }

        if ride.claimedBy != nil {
            Divider()

            claimedByRow
        }
    }

    private var timeAndSeatsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 16))
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
                Text(ride.claimer?.name ?? "community_former_member".localized)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .foregroundColor(ride.claimer == nil ? .secondary : .primary)
                    .lineLimit(isAccessibilitySize ? 3 : 1)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RideCard(ride: Ride(
            userId: UUID(),
            date: Date(),
            time: "14:30:00",
            pickup: "123 Main St",
            destination: "Airport Terminal 1",
            seats: 2,
            status: .open
        ))
        
        RideCard(ride: Ride(
            userId: UUID(),
            date: Date().addingTimeInterval(86400),
            time: "09:00:00",
            pickup: "Downtown",
            destination: "Shopping Mall",
            seats: 1,
            status: .confirmed
        ))
    }
    .padding()
}

#Preview("Former member poster") {
    RideCard(ride: Ride(
        userId: UUID(),
        date: Date(),
        time: "14:30:00",
        pickup: "123 Main St",
        destination: "Airport Terminal 1",
        seats: 2,
        status: .open,
        poster: nil
    ))
    .padding()
    .environment(AppState())
}

#Preview("Former member claimer") {
    RideCard(ride: Ride(
        userId: UUID(),
        date: Date(),
        time: "14:30:00",
        pickup: "123 Main St",
        destination: "Airport Terminal 1",
        seats: 2,
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
        RideCard(ride: Ride(
            userId: UUID(),
            date: Date(),
            time: "14:30:00",
            pickup: "123 Main St",
            destination: "Airport Terminal 1",
            seats: 2,
            status: .open
        ), communityChipText: "Capitol Hill")
    }
    .padding()
    .environment(AppState())
}
#endif
