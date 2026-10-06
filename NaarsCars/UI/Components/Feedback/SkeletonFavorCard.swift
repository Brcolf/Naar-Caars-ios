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
            SkeletonRectangle(width: 150, height: 20, cornerRadius: Constants.Radius.sm)
            
            // Description skeleton
            SkeletonRectangle(width: 200, height: 16, cornerRadius: Constants.Radius.xs)
            
            // Location skeleton
            SkeletonRectangle(width: 180, height: 16, cornerRadius: Constants.Radius.xs)
            
            // Date skeleton
            SkeletonRectangle(width: 120, height: 14, cornerRadius: Constants.Radius.xs)
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(Constants.Radius.card)
        .cardShadow()
    }
}

#Preview {
    VStack(spacing: 16) {
        SkeletonFavorCard()
        SkeletonFavorCard()
    }
    .padding()
}


