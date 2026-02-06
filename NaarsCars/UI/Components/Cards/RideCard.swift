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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Poster info and status
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
                        Text("Unknown User")
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
                    
                    // Status badge
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
            
            Divider()
            
            // Route addresses (long-press to copy or open in maps)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.naarsCaption)
                    AddressText(ride.pickup)
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
                    AddressText(ride.destination)
                }
            }
            
            // Date, time, and seats
            HStack(spacing: 16) {
                Label(ride.time, systemImage: "clock")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                
                Label("\(ride.seats) seat\(ride.seats == 1 ? "" : "s")", systemImage: "person.2")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            
            // Claimer info (when claimed or completed)
            if ride.claimedBy != nil {
                Divider()
                
                HStack(spacing: 8) {
                    if let claimer = ride.claimer {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.naarsPrimary)
                            .font(.naarsSubheadline)
                        Text("Claimed by")
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
                        Text("Claimed")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .overlay(
            // Red accent border on the left for rides
            Rectangle()
                .fill(Color.rideAccent)
                .frame(width: 4)
                .cornerRadius(2),
            alignment: .leading
        )
        .cornerRadius(12)
        .shadow(color: Color.primary.opacity(0.08), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ride from \(ride.pickup) to \(ride.destination) on \(ride.date.dateString), \(ride.status.displayText)")
        .accessibilityHint("Double-tap to view ride details")
    }

    private var badgeText: String? {
        guard unreadCount > 0 else { return nil }
        return unreadCount > 9 ? "9+" : "\(unreadCount)"
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
