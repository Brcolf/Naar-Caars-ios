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
    
    init(review: Review, reviewerName: String? = nil, reviewerAvatarUrl: String? = nil) {
        self.review = review
        self.reviewerName = reviewerName
        self.reviewerAvatarUrl = reviewerAvatarUrl
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Reviewer Info
            HStack {
                if let reviewerAvatarUrl = reviewerAvatarUrl {
                    AvatarView(
                        imageUrl: reviewerAvatarUrl,
                        name: reviewerName ?? "Anonymous",
                        size: 40
                    )
                } else {
                    AvatarView(
                        imageUrl: nil,
                        name: reviewerName ?? "Anonymous",
                        size: 40
                    )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(reviewerName ?? "Anonymous")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 200)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .frame(height: 200)
                    @unknown default:
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .frame(height: 200)
                    }
                }
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





