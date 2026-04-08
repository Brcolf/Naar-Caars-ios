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
                        .frame(width: 4)
                        .cornerRadius(2),
                    alignment: .leading
                )
                .cornerRadius(12)
                .shadow(color: Color.primary.opacity(0.08), radius: 4, x: 0, y: 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Double-tap to view ride details")
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
            ? "Ride on \(ride.date.dateString), \(ride.status.displayText)"
            : "Ride from \(ride.pickup) to \(ride.destination) on \(ride.date.dateString), \(ride.status.displayText)"
    }

    @ViewBuilder
    private var headerContent: some View {
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
                } else {
                    Text("common_unknown_user".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.secondary)
                }

                Text(ride.date.dateString)
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

                Text(ride.status.displayText)
                    .font(.naarsCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ride.status.color)
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
                    .foregroundColor(.green)
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
            Label(ride.time, systemImage: "clock")
                .font(.naarsCaption)
                .foregroundColor(.secondary)

            Label("\(ride.seats) seat\(ride.seats == 1 ? "" : "s")", systemImage: "person.2")
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
