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

    var body: some View {
        NavigationStack {
            Group {
                if reviews.isEmpty {
                    EmptyStateView(
                        icon: "star.fill",
                        title: "reviews_empty_title".localized,
                        message: "reviews_empty_message".localized
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(reviews) { review in
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
