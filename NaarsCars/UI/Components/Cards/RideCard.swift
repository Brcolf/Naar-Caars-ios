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
            
            Divider()
            
            // Route addresses
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.rideAccent)
                        .font(.system(size: 16))
                    Text(ride.pickup)
                        .font(.naarsBody)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .padding(.leading, 4)
                    Text("")
                        .font(.system(size: 1))
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.rideAccent)
                        .font(.system(size: 16))
                    Text(ride.destination)
                        .font(.naarsBody)
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
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            // Red accent border on the left for rides
            Rectangle()
                .fill(Color.rideAccent)
                .frame(width: 4)
                .cornerRadius(2),
            alignment: .leading
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
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
