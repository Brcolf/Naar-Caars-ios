//
//  AllReviewsView.swift
//  NaarsCars
//
//  Scrollable list of all reviews left for the current user
//

import SwiftUI

struct AllReviewsView: View {
    let userId: UUID
    @State private var reviews: [Review] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading && reviews.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonReviewCard()
                        }
                    }
                    .padding()
                }
            } else if let error = error, reviews.isEmpty {
                ErrorView(
                    error: error.localizedDescription,
                    retryAction: { Task { await loadReviews() } }
                )
            } else if reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "profile_no_reviews".localized,
                    message: "profile_no_reviews_message".localized,
                    customImage: "naars_Profile_icon"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(reviews) { review in
                            VStack(alignment: .leading, spacing: 8) {
                                ReviewCard(
                                    review: review,
                                    reviewerName: review.reviewerName,
                                    reviewerAvatarUrl: review.reviewerAvatarUrl
                                )

                                // Request context
                                if let requestTitle = review.requestTitle {
                                    HStack(spacing: 4) {
                                        Image(systemName: review.rideId != nil ? "car.fill" : "hand.raised.fill")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(requestTitle)
                                            .font(.naarsCaption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await loadReviews()
                }
            }
        }
        .navigationTitle("review_all_reviews_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReviews()
        }
    }

    private func loadReviews() async {
        defer { isLoading = false }
        do {
            reviews = try await ProfileService.shared.fetchReviews(forUserId: userId)
            error = nil
        } catch {
            self.error = error
            AppLogger.error("reviews", "Failed to load all reviews: \(error)")
        }
    }
}

// MARK: - Skeleton

private struct SkeletonReviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.naarsBackgroundSecondary)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.naarsBackgroundSecondary)
                        .frame(width: 100, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.naarsBackgroundSecondary)
                        .frame(width: 80, height: 12)
                }
                Spacer()
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.naarsBackgroundSecondary)
                .frame(height: 40)
        }
        .padding()
        .background(Color.naarsBackgroundSecondary.opacity(0.5))
        .cornerRadius(12)
    }
}
