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
                
                Text("Leave a Review")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Your request has been completed!")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("Please take a moment to review \(fulfillerName) for their help.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Request Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(requestTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "Leave Review") {
                        showLeaveReview = true
                    }
                    
                    SecondaryButton(title: "Skip for now") {
                        Task {
                            await skipReview()
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Review Request")
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
            print("❌ Error skipping review: \(error.localizedDescription)")
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

