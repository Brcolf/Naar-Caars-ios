//
//  ClaimSheet.swift
//  NaarsCars
//
//  Confirmation sheet for claiming a request
//

import SwiftUI

/// Confirmation sheet for claiming a request
struct ClaimSheet: View {
    let requestType: String
    let requestTitle: String
    let onConfirm: () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsPrimary)
                
                Text("claim_title".localized(with: requestType.capitalized))
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("claim_volunteering".localized)
                    .foregroundColor(.secondary)
                
                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.naarsCardBackground)
                    .cornerRadius(8)
                
                Text("claim_message_hint".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(
                        title: "claim_confirm".localized,
                        action: {
                            Task {
                                isLoading = true
                                errorMessage = nil
                                do {
                                    try await onConfirm()
                                    showSuccess = true
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isLoading = false
                            }
                        },
                        isLoading: isLoading
                    )
                    .accessibilityIdentifier("claim.confirm")
                    
                    SecondaryButton(title: "claim_cancel".localized) {
                        dismiss()
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("claim.cancel")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("claim_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toast(message: $errorMessage, style: .warning)
        }
        .successCheckmark(isShowing: $showSuccess)
        .onChange(of: showSuccess) { _, newValue in
            if !newValue {
                dismiss()
            }
        }
        .interactiveDismissDisabled(isLoading)
    }
}

#Preview {
    ClaimSheet(
        requestType: "ride",
        requestTitle: "Ride to Airport",
        onConfirm: { /* no-op */ }
    )
}





