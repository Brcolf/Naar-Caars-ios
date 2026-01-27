//
//  SkeletonFavorCard.swift
//  NaarsCars
//
//  Skeleton loading component matching FavorCard layout
//

import SwiftUI

/// Skeleton loading view matching FavorCard layout
struct SkeletonFavorCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title skeleton
            SkeletonRectangle(width: 150, height: 20, cornerRadius: 8)
            
            // Description skeleton
            SkeletonRectangle(width: 200, height: 16, cornerRadius: 6)
            
            // Location skeleton
            SkeletonRectangle(width: 180, height: 16, cornerRadius: 6)
            
            // Date skeleton
            SkeletonRectangle(width: 120, height: 14, cornerRadius: 6)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    VStack(spacing: 16) {
        SkeletonFavorCard()
        SkeletonFavorCard()
    }
    .padding()
}


