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
                if let reviewerAvatarUrl = reviewerAvatarUrl {
                    AvatarView(
                        imageUrl: reviewerAvatarUrl,
                        name: reviewerName ?? "common_anonymous".localized,
                        size: 40,
                        userId: reviewerId
                    )
                } else {
                    AvatarView(
                        imageUrl: nil,
                        name: reviewerName ?? "common_anonymous".localized,
                        size: 40,
                        userId: reviewerId
                    )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(reviewerName ?? "common_anonymous".localized)
                        .font(.naarsSubheadline)
                        .fontWeight(.semibold)
                    
                    StarRatingView(rating: Double(review.rating))
                }
                
                Spacer()
                
                Text(review.createdAt.timeAgo)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)

                ReviewReportButton(review: review)
            }

            // Review Comment
            if let comment = review.comment, !comment.isEmpty {
                Text(comment)
                    .font(.naarsBody)
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
                .cornerRadius(Constants.Radius.sm)
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(Constants.Radius.card)
        .cardShadow()
    }
}

/// Flag control that reports a review. Shown to signed-in members other than the reviewer, on
/// every surface that renders a review (ReviewCard and ReviewRowView).
/// Reports have no review target yet, so ReportContentViewModel files the report against the
/// review's Town Hall post or, when there is none, against the reviewer.
struct ReviewReportButton: View {
    let review: Review

    @State private var showReportSheet = false
    @State private var hasReported = false
    /// Height of the caption-size glyph, which grows with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var glyphHeight: CGFloat = 16

    private var canReport: Bool {
        guard let currentUserId = AuthService.shared.currentUserId else { return false }
        return currentUserId != review.reviewerId
    }

    private var reviewPreview: String {
        guard let comment = review.comment, !comment.isEmpty else {
            return "review_rating_accessibility".localized(with: "\(review.rating)")
        }
        return comment.count > 100 ? String(comment.prefix(100)) + "..." : comment
    }

    var body: some View {
        if canReport {
            Button {
                showReportSheet = true
            } label: {
                Image(systemName: hasReported ? "flag.fill" : "flag")
                    .font(.naarsCaption)
                    .foregroundColor(hasReported ? .secondary.opacity(0.5) : .secondary)
                    // A 44-pt tap target around the glyph that takes no extra room in the row it
                    // sits in: the padding is given back after the shape is set. The vertical part
                    // shrinks as the glyph grows and is gone at accessibility sizes.
                    .padding(.horizontal, Constants.Spacing.md)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .padding(.horizontal, -Constants.Spacing.md)
                    .padding(.vertical, -max(0, (44 - glyphHeight) / 2))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(hasReported)
            .accessibilityLabel(hasReported ? "townhall_reported".localized : "review_report_accessibility".localized)
            .sheet(isPresented: $showReportSheet) {
                ReportContentSheet(
                    context: .review(
                        id: review.id,
                        authorId: review.reviewerId,
                        preview: reviewPreview
                    ),
                    onReported: { hasReported = true }
                )
            }
        }
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





