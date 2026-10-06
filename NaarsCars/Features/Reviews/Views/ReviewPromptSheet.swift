//
//  ReviewPromptSheet.swift
//  NaarsCars
//
//  Review prompt sheet that appears immediately after completion
//

import SwiftUI

/// Review prompt sheet that appears immediately after completion
struct ReviewPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let requestType: String // "ride" or "favor"
    let requestId: UUID
    let requestTitle: String
    let fulfillerId: UUID
    let fulfillerName: String
    
    @State private var showLeaveReview = false
    @State private var isSkipping = false
    @StateObject private var viewModel = ReviewPromptViewModel()
    
    var onReviewSubmitted: (() -> Void)?
    var onReviewSkipped: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "star.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsRating)
                
                Text("review_prompt_heading".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("review_prompt_completed".localized)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                
                Text("review_prompt_ask".localized(with: fulfillerName))
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Request Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(requestTitle)
                        .font(.naarsHeadline)
                        .foregroundColor(.primary)
                    
                    Text("review_prompt_status_completed".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.naarsCardBackground)
                .cornerRadius(Constants.Radius.sm)
                .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(
                        title: "review_prompt_leave_review".localized,
                        action: { showLeaveReview = true },
                        isDisabled: isSkipping
                    )

                    SecondaryButton(
                        title: "review_prompt_skip".localized,
                        action: {
                            Task {
                                await skipReview()
                            }
                        },
                        isDisabled: isSkipping
                    )

                    if isSkipping {
                        ProgressView()
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("review_prompt_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            // This prompt covers the whole app and cannot be swiped away, so a skip that fails
            // (offline, timeout) must say so and still offer a way out.
            .alert("review_prompt_skip_failed_title".localized, isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("common_retry".localized) {
                    Task { await skipReview() }
                }
                Button("common_not_now".localized, role: .cancel) {
                    // Close without recording the skip, through the same callback as a recorded
                    // one so the prompt queue advances. The server still has the review pending,
                    // so the prompt comes back on a later launch.
                    onReviewSkipped?()
                    dismiss()
                }
            } message: {
                Text("review_prompt_skip_failed_message".localized)
            }
            .sheet(isPresented: $showLeaveReview) {
                LeaveReviewView(
                    requestType: requestType,
                    requestId: requestId,
                    requestTitle: requestTitle,
                    fulfillerId: fulfillerId,
                    fulfillerName: fulfillerName,
                    onReviewSubmitted: {
                        onReviewSubmitted?()
                        dismiss()
                    },
                    onReviewSkipped: {
                        onReviewSkipped?()
                        dismiss()
                    }
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func skipReview() async {
        // The skip is a network write; ignore further taps until it returns.
        guard !isSkipping else { return }
        isSkipping = true
        defer { isSkipping = false }
        guard await viewModel.skipReview(requestType: requestType, requestId: requestId) else { return }
        onReviewSkipped?()
        dismiss()
    }
}

#Preview {
    ReviewPromptSheet(
        requestType: "ride",
        requestId: UUID(),
        requestTitle: "Capitol Hill → SEA Airport",
        fulfillerId: UUID(),
        fulfillerName: "John Doe"
    )
}

