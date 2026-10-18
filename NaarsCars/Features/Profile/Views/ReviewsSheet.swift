//
//  ReviewsSheet.swift
//  NaarsCars
//
//  Sheet displaying list of reviews for the current user
//

import SwiftUI

struct ReviewsSheet: View {
    let reviews: [Review]
    @Environment(\.dismiss) private var dismiss

    /// Display-layer filter: hide reviews authored by users the viewer has blocked.
    /// Mirrors the Town Hall block-filtering pattern; RLS remains the security boundary.
    private var visibleReviews: [Review] {
        let blockedIds = MessageService.shared.cachedBlockedUserIds
        guard !blockedIds.isEmpty else { return reviews }
        return reviews.filter { !blockedIds.contains($0.reviewerId) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleReviews.isEmpty {
                    EmptyStateView(
                        icon: "star.fill",
                        title: "reviews_empty_title".localized,
                        message: "reviews_empty_message".localized
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleReviews) { review in
                                ReviewRowView(review: review)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("reviews_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common_done".localized) { dismiss() }
                }
            }
        }
    }
}
