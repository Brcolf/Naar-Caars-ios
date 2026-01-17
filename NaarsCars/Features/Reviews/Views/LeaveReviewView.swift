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
    
    var body: some View {
        NavigationStack {
            Form {
                // Request Summary Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(requestTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Review for \(fulfillerName)")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Request")
                }
                
                // Rating Section
                Section {
                    VStack(spacing: 16) {
                        Text("How was your experience?")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        StarRatingInput(rating: $viewModel.rating, size: 40, spacing: 8)
                        
                        if viewModel.rating == 0 {
                            Text("Tap to rate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Rating")
                }
                
                // Comment Section
                Section {
                    TextEditor(text: $viewModel.comment)
                        .frame(minHeight: 100)
                        .font(.body)
                } header: {
                    Text("Comment (Optional)")
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
                                Text(viewModel.reviewImage == nil ? "Add Photo (Optional)" : "Change Photo")
                            }
                            .font(.body)
                        }
                    }
                } header: {
                    Text("Photo (Optional)")
                }
                
                // Error Display
                if let error = viewModel.error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Leave Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        showSkipConfirmation = true
                    }
                    .disabled(viewModel.isSubmitting)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
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
                            Text("Uploading image...")
                                .padding(.top)
                        } else {
                            Text("Submitting review...")
                                .padding(.top)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
            }
            .alert("Skip Review?", isPresented: $showSkipConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Skip") {
                    Task {
                        await skipReview()
                    }
                }
            } message: {
                Text("You can add a review later from your past requests.")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func submitReview() async {
        do {
            _ = try await viewModel.submitReview(
                requestType: requestType,
                requestId: requestId,
                fulfillerId: fulfillerId
            )
            
            onReviewSubmitted?()
            dismiss()
        } catch {
            // Error is handled by viewModel
            print("❌ Error submitting review: \(error.localizedDescription)")
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
            print("❌ Error skipping review: \(error.localizedDescription)")
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

