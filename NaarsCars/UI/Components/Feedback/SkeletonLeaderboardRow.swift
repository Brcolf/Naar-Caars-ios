//
//  SkeletonLeaderboardRow.swift
//  NaarsCars
//
//  Skeleton loading component for leaderboard rows
//

import SwiftUI

/// Skeleton loading view for leaderboard rows
struct SkeletonLeaderboardRow: View {
    let rank: Int
    
    init(rank: Int = 1) {
        self.rank = rank
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank number skeleton
            SkeletonRectangle(width: 30, height: 30, cornerRadius: 15)
            
            // Avatar skeleton
            SkeletonCircle(size: 50)
            
            VStack(alignment: .leading, spacing: 6) {
                // Name skeleton
                SkeletonRectangle(width: 120, height: 18, cornerRadius: Constants.Radius.xs)
                
                // Stats skeleton
                SkeletonRectangle(width: 100, height: 14, cornerRadius: Constants.Radius.xs)
            }
            
            Spacer()
            
            // Points skeleton
            SkeletonRectangle(width: 60, height: 20, cornerRadius: Constants.Radius.sm)
        }
        .padding()
    }
}

#Preview {
    VStack(spacing: 0) {
        SkeletonLeaderboardRow(rank: 1)
        Divider()
        SkeletonLeaderboardRow(rank: 2)
        Divider()
        SkeletonLeaderboardRow(rank: 3)
    }
}


