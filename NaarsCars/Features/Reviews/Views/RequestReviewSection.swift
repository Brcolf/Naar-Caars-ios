//
//  RequestReviewSection.swift
//  NaarsCars
//
//  Inline review display for completed request detail views
//

import SwiftUI

/// Displays an existing review inline, or a "Leave a Review" button if the poster hasn't reviewed yet.
struct RequestReviewSection: View {
    let requestType: String
    let requestId: UUID
    let posterId: UUID
    let claimerId: UUID?
    let isCompleted: Bool
    let requestTitle: String
    /// Name of the person who fulfilled the request (the one being reviewed). The detail screens
    /// already hold the claimer's profile, so it is passed in rather than fetched again.
    var claimerName: String? = nil
    var onReviewSubmitted: (() -> Void)?

    @State private var review: Review?
    @State private var reviewerProfile: Profile?
    @State private var isLoading = true
    @State private var showLeaveReview = false

    private var isCurrentUserPoster: Bool {
        AuthService.shared.currentUserId == posterId
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.naarsCardBackground)
                    .cornerRadius(Constants.Radius.card)
            } else if let review = review {
                reviewDisplay(review)
            } else if isCurrentUserPoster && isCompleted && claimerId != nil {
                addReviewButton
            }
        }
        .task {
            await loadReview()
        }
        .sheet(isPresented: $showLeaveReview) {
            if let claimerId = claimerId {
                LeaveReviewView(
                    requestType: requestType,
                    requestId: requestId,
                    requestTitle: requestTitle,
                    fulfillerId: claimerId,
                    // reviewerProfile is the reviewer (the poster) and is only loaded once a review
                    // exists, so it can never name the person being reviewed here.
                    fulfillerName: claimerName ?? "common_someone".localized,
                    onReviewSubmitted: {
                        Task {
                            await loadReview()
                            onReviewSubmitted?()
                        }
                    },
                    onReviewSkipped: {}
                )
            }
        }
    }

    // MARK: - Review Display

    private func reviewDisplay(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("review_section_title".localized)
                .font(.naarsTitle3)

            ReviewCard(
                review: review,
                reviewerName: reviewerProfile?.name,
                reviewerAvatarUrl: reviewerProfile?.avatarUrl
            )
        }
        .cardStyle()
    }

    // MARK: - Add Review Button

    private var addReviewButton: some View {
        Button {
            showLeaveReview = true
        } label: {
            HStack {
                Image(systemName: "star.bubble")
                Text("review_leave_review".localized)
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(Constants.Radius.card)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Data Loading

    private func loadReview() async {
        defer { isLoading = false }
        do {
            let fetchedReview = try await ReviewService.shared.fetchReviewForRequest(
                requestType: requestType,
                requestId: requestId
            )
            self.review = fetchedReview
            if let reviewerId = fetchedReview?.reviewerId {
                self.reviewerProfile = try? await ProfileService.shared.fetchProfile(userId: reviewerId)
            }
        } catch {
            AppLogger.error("reviews", "Failed to load review for request: \(error)")
        }
    }
}
