//
//  ReviewCard.swift
//  NaarsCars
//
//  Review display card component
//

import SwiftUI

/// Card view for displaying a review
struct ReviewCard: View {
    let review: Review
    let reviewerName: String?
    let reviewerAvatarUrl: String?
    let reviewerId: UUID?

    init(review: Review, reviewerName: String? = nil, reviewerAvatarUrl: String? = nil, reviewerId: UUID? = nil) {
        self.review = review
        self.reviewerName = reviewerName
        self.reviewerAvatarUrl = reviewerAvatarUrl
        self.reviewerId = reviewerId
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Reviewer Info
            HStack {
                let displayName = reviewerName ?? "Anonymous"

                // Tap-through to the reviewer's public profile (Report/Block reachability).
                // Only enabled when the reviewer's id is known; otherwise falls back to
                // a non-interactive avatar so existing callers keep working.
                if let reviewerId {
                    UserAvatarLink(
                        profile: Profile(
                            id: reviewerId,
                            name: displayName,
                            email: "",
                            avatarUrl: reviewerAvatarUrl
                        ),
                        size: 40
                    )
                    .accessibilityLabel("review_view_reviewer_profile".localized(with: displayName))
                } else {
                    AvatarView(
                        imageUrl: reviewerAvatarUrl,
                        name: displayName,
                        size: 40,
                        userId: reviewerId
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let reviewerId {
                        NavigationLink(destination: PublicProfileView(userId: reviewerId)) {
                            Text(displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("review_view_reviewer_profile".localized(with: displayName))
                    } else {
                        Text(displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    StarRatingView(rating: Double(review.rating))
                }

                Spacer()

                Text(review.createdAt.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Review Comment
            if let comment = review.comment, !comment.isEmpty {
                Text(comment)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            // Review Image
            if let imageUrl = review.imageUrl, let url = URL(string: imageUrl) {
                CachedAsyncImage(
                    url: url,
                    placeholder: {
                        ProgressView()
                            .frame(height: 200)
                    },
                    errorView: {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .frame(height: 200)
                    }
                )
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    ReviewCard(
        review: Review(
            reviewerId: UUID(),
            fulfillerId: UUID(),
            rating: 5,
            comment: "Great ride! Very punctual and friendly."
        ),
        reviewerName: "Jane Smith",
        reviewerAvatarUrl: nil
    )
    .padding()
}





