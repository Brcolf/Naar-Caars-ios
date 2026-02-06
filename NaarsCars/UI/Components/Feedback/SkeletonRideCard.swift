//
//  SkeletonRideCard.swift
//  NaarsCars
//
//  Skeleton loading component matching RideCard layout
//

import SwiftUI

/// Skeleton loading view matching RideCard layout
struct SkeletonRideCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title skeleton
            SkeletonRectangle(width: 150, height: 20, cornerRadius: 8)
            
            // Pickup location skeleton
            SkeletonRectangle(width: 200, height: 16, cornerRadius: 6)
            
            // Destination location skeleton
            SkeletonRectangle(width: 180, height: 16, cornerRadius: 6)
            
            // Date skeleton
            SkeletonRectangle(width: 120, height: 14, cornerRadius: 6)
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    VStack(spacing: 16) {
        SkeletonRideCard()
        SkeletonRideCard()
    }
    .padding()
}


