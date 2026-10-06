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
                
                // A whole sentence per type. Inserting the raw "ride" / "favor" identifier into
                // one translated sentence read "¿Reclamar este Ride?" outside English.
                Text((requestType == "ride" ? "claim_title_ride" : "claim_title_favor").localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("claim_volunteering".localized)
                    .foregroundColor(.secondary)

                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.naarsInsetBackground)
                    .cornerRadius(Constants.Radius.sm)
                
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
            // Stays until dismissed. The toast vanished after two seconds with a success
            // haptic, which is the wrong signal for "someone else already claimed this".
            .errorBanner(message: $errorMessage)
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





