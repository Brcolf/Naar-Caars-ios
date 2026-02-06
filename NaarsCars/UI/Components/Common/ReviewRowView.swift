//
//  ReviewRowView.swift
//  NaarsCars
//
//  Reusable review row displaying star rating, time ago, and comment
//

import SwiftUI

/// A reusable row for displaying a single review with star rating and optional comment
/// Used by both MyProfileView and PublicProfileView
struct ReviewRowView: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Star rating
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: index <= review.rating ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }

                Spacer()

                Text(review.createdAt.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let comment = review.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(8)
    }
}
