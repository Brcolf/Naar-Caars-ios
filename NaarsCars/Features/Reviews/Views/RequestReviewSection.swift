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
                    .cornerRadius(12)
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
                    fulfillerName: reviewerProfile?.name ?? "Someone",
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
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(12)
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
