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
                        title: "No Reviews Yet",
                        message: "Reviews from people you've helped will appear here."
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
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
