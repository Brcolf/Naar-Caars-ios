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
                            .foregroundColor(.naarsRating)
                            .font(.naarsCaption)
                    }
                }
                // One spoken value instead of five separate star images
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("review_rating_accessibility".localized(with: "\(review.rating)"))

                Spacer()

                Text(review.createdAt.timeAgo)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)

                ReviewReportButton(review: review)
            }

            if let comment = review.comment, !comment.isEmpty {
                Text(comment)
                    .font(.naarsSubheadline)
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(Constants.Radius.sm)
    }
}
