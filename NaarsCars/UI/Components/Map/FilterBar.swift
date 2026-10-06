//
//  FilterBar.swift
//  NaarsCars
//
//  Filter controls for map view (rides/favors toggle)
//

import SwiftUI

/// Filter bar for toggling ride and favor display
struct FilterBar: View {
    @Binding var showRides: Bool
    @Binding var showFavors: Bool
    let requestCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Rides filter chip
            FilterChip(
                title: "Rides",
                icon: "car.fill",
                isSelected: showRides,
                color: .rideAccent
            ) {
                showRides.toggle()
            }
            
            // Favors filter chip
            FilterChip(
                title: "Favors",
                icon: "wrench.fill",
                isSelected: showFavors,
                color: .favorAccent
            ) {
                showFavors.toggle()
            }
            
            Spacer()
            
            // Request count badge
            if requestCount > 0 {
                Text(requestCount == 1 ? "requests_count_singular".localized(with: requestCount) : "requests_count_plural".localized(with: requestCount))
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

/// Individual filter chip button
struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.naarsSubheadline)
                Text(title)
                    .font(.naarsSubheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color.naarsInsetBackground)
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        FilterBar(
            showRides: .constant(true),
            showFavors: .constant(true),
            requestCount: 12
        )
        
        FilterBar(
            showRides: .constant(true),
            showFavors: .constant(false),
            requestCount: 5
        )
        
        FilterBar(
            showRides: .constant(false),
            showFavors: .constant(true),
            requestCount: 7
        )
    }
    .padding()
}


