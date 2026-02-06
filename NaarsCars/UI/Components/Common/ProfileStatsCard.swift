//
//  ProfileStatsCard.swift
//  NaarsCars
//
//  Reusable stats card showing rating, review count, and fulfilled count
//

import SwiftUI

/// A reusable card that displays profile statistics (rating, reviews, fulfilled)
/// Used by both MyProfileView and PublicProfileView
struct ProfileStatsCard: View {
    let rating: Double?
    let reviewCount: Int?
    let fulfilledCount: Int

    /// Convenience initializer with all three stats (used by MyProfileView)
    init(rating: Double?, reviewCount: Int, fulfilledCount: Int) {
        self.rating = rating
        self.reviewCount = reviewCount
        self.fulfilledCount = fulfilledCount
    }

    /// Convenience initializer without review count (used by PublicProfileView)
    init(rating: Double?, fulfilledCount: Int) {
        self.rating = rating
        self.reviewCount = nil
        self.fulfilledCount = fulfilledCount
    }

    var body: some View {
        HStack(spacing: 32) {
            // Rating
            VStack {
                if let rating = rating {
                    Text(String(format: "%.1f", rating))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("No Rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Review count (optional)
            if let reviewCount = reviewCount {
                VStack {
                    Text("\(reviewCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Reviews")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
            }

            // Fulfilled count
            VStack {
                Text("\(fulfilledCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Fulfilled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        ProfileStatsCard(rating: 4.5, reviewCount: 12, fulfilledCount: 8)
        ProfileStatsCard(rating: nil, fulfilledCount: 3)
    }
    .padding()
}
