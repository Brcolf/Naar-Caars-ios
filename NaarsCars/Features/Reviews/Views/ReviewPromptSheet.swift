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
    
    var onReviewSubmitted: (() -> Void)?
    var onReviewSkipped: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "star.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                
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
                .cornerRadius(8)
                .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "review_prompt_leave_review".localized) {
                        showLeaveReview = true
                    }
                    
                    SecondaryButton(title: "review_prompt_skip".localized) {
                        Task {
                            await skipReview()
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("review_prompt_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
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
        do {
            try await ReviewService.shared.skipReview(
                requestType: requestType,
                requestId: requestId
            )
            
            onReviewSkipped?()
            dismiss()
        } catch {
            AppLogger.error("reviews", "Error skipping review: \(error.localizedDescription)")
        }
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

