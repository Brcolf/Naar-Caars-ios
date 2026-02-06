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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Poster info and status
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
                        Text("Unknown User")
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
                    
                    // Status badge
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
            
            Divider()
            
            // Title
            Text(favor.title)
                .font(.naarsTitle3)
                .lineLimit(2)
            
            // Location and Duration (long-press location to copy or open in maps)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.favorAccent) // Teal/cyan for favors
                        .font(.naarsCallout)
                    AddressText(favor.location)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: favor.duration.icon)
                        .foregroundColor(.naarsAccent)
                        .font(.naarsCallout)
                    Text(favor.duration.displayText)
                        .font(.naarsBody)
                }
            }
            
            // Date and time
            HStack(spacing: 16) {
                if let time = favor.time {
                    Label(time, systemImage: "clock")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Claimer info (when claimed or completed)
            if favor.claimedBy != nil {
                Divider()
                
                HStack(spacing: 8) {
                    if let claimer = favor.claimer {
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
            // Teal/blue accent border on the left for favors (complementary to red)
            Rectangle()
                .fill(Color.favorAccent) // Teal/cyan accent for favors
                .frame(width: 4)
                .cornerRadius(2),
            alignment: .leading
        )
        .cornerRadius(12)
        .shadow(color: Color.primary.opacity(0.08), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Favor \(favor.title) at \(favor.location) on \(favor.date.dateString), \(favor.status.displayText)")
        .accessibilityHint("Double-tap to view favor details")
    }

    private var badgeText: String? {
        guard unreadCount > 0 else { return nil }
        return unreadCount > 9 ? "9+" : "\(unreadCount)"
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

