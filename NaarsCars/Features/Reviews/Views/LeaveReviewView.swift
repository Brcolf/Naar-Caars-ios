//
//  LeaveReviewView.swift
//  NaarsCars
//
//  View for leaving a review
//

import SwiftUI
import PhotosUI

/// View for leaving a review
struct LeaveReviewView: View {
    @StateObject private var viewModel = LeaveReviewViewModel()
    @Environment(\.dismiss) private var dismiss
    
    let requestType: String // "ride" or "favor"
    let requestId: UUID
    let requestTitle: String
    let fulfillerId: UUID
    let fulfillerName: String
    
    var onReviewSubmitted: (() -> Void)?
    var onReviewSkipped: (() -> Void)?
    
    @State private var showSkipConfirmation = false
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Request Summary Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(requestTitle)
                            .font(.naarsHeadline)
                            .foregroundColor(.primary)
                        
                        Text("review_for_user".localized(with: fulfillerName))
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("review_section_request".localized)
                }
                
                // Rating Section
                Section {
                    VStack(spacing: 16) {
                        Text("review_how_was_experience".localized)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                        
                        StarRatingInput(rating: $viewModel.rating, size: 40, spacing: 8)
                        
                        if viewModel.rating == 0 {
                            Text("review_tap_to_rate".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("review_section_rating".localized)
                }
                
                // Comment Section
                Section {
                    TextEditor(text: $viewModel.comment)
                        .frame(minHeight: 100)
                        .font(.naarsBody)
                } header: {
                    Text("review_section_comment".localized)
                }
                
                // Image Section
                Section {
                    VStack(spacing: 12) {
                        if let reviewImage = viewModel.reviewImage {
                            Image(uiImage: reviewImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                                .overlay(alignment: .topTrailing) {
                                    Button(action: {
                                        viewModel.reviewImage = nil
                                        viewModel.selectedPhoto = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .padding(8)
                                }
                        }
                        
                        PhotosPicker(
                            selection: Binding(
                                get: { viewModel.selectedPhoto },
                                set: { item in
                                    viewModel.selectedPhoto = item
                                    Task {
                                        await viewModel.handlePhotoSelection(item)
                                    }
                                }
                            ),
                            matching: .images
                        ) {
                            HStack {
                                Image(systemName: "photo")
                                Text(viewModel.reviewImage == nil ? "review_add_photo".localized : "review_change_photo".localized)
                            }
                            .font(.naarsBody)
                        }
                    }
                } header: {
                    Text("review_section_photo".localized)
                }
                
                // Error Display
                if let error = viewModel.error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundColor(.naarsError)
                            .font(.naarsCaption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("review_leave_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("review_skip".localized) {
                        showSkipConfirmation = true
                    }
                    .disabled(viewModel.isSubmitting)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("review_submit".localized) {
                        Task {
                            await submitReview()
                        }
                    }
                    .disabled(viewModel.rating == 0 || viewModel.isSubmitting)
                }
            }
            .overlay {
                if viewModel.isSubmitting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                        if viewModel.isUploadingImage {
                            Text("review_uploading_image".localized)
                                .padding(.top)
                        } else {
                            Text("review_submitting".localized)
                                .padding(.top)
                        }
                    }
                    .padding()
                    .background(Color.naarsBackgroundSecondary)
                    .cornerRadius(12)
                }
            }
            .alert("review_skip_title".localized, isPresented: $showSkipConfirmation) {
                Button("review_skip_cancel".localized, role: .cancel) {}
                Button("review_skip".localized) {
                    Task {
                        await skipReview()
                    }
                }
            } message: {
                Text("review_skip_message".localized)
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
    
    // MARK: - Private Methods
    
    private func submitReview() async {
        do {
            let review = try await viewModel.submitReview(
                requestType: requestType,
                requestId: requestId,
                fulfillerId: fulfillerId
            )
            
            HapticManager.success()
            showSuccess = true
            await viewModel.navigateToReviewPost(reviewId: review.id)
            onReviewSubmitted?()
            try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
            dismiss()
        } catch {
            // Error is handled by viewModel
            AppLogger.error("reviews", "Error submitting review: \(error.localizedDescription)")
        }
    }
    
    private func skipReview() async {
        do {
            try await viewModel.skipReview(
                requestType: requestType,
                requestId: requestId
            )
            
            onReviewSkipped?()
            dismiss()
        } catch {
            // Error is handled by viewModel
            AppLogger.error("reviews", "Error skipping review: \(error.localizedDescription)")
        }
    }
}

#Preview {
    LeaveReviewView(
        requestType: "ride",
        requestId: UUID(),
        requestTitle: "Capitol Hill → SEA Airport",
        fulfillerId: UUID(),
        fulfillerName: "John Doe"
    )
}

