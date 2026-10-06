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
        if let poster = ride.poster {
            parts.append("ride_detail_requested_by".localized(with: poster.name))
        }
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
        if ride.claimedBy != nil, let claimer = ride.claimer {
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
                if let poster = ride.poster {
                    UserAvatarLink(profile: poster, size: 40)
                } else {
                    AvatarView(imageUrl: nil, name: "Unknown", size: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let poster = ride.poster {
                        Text(poster.name)
                            .font(.naarsHeadline)
                            .lineLimit(2)
                    } else {
                        Text("common_unknown_user".localized)
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

        HStack(spacing: 16) {
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

            HStack(spacing: 8) {
                if let claimer = ride.claimer {
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
