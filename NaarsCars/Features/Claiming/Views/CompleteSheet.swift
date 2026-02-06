//
//  CompleteSheet.swift
//  NaarsCars
//
//  Confirmation sheet for completing a request
//

import SwiftUI

/// Confirmation sheet for completing a request
struct CompleteSheet: View {
    let requestType: String
    let requestTitle: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsSuccess)
                
                Text("claim_complete_title".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("claim_complete_description".localized)
                    .foregroundColor(.secondary)
                
                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.naarsCardBackground)
                    .cornerRadius(8)
                
                Text("claim_complete_review_hint".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "claim_complete_confirm".localized) {
                        onConfirm()
                        showSuccess = true
                    }
                    .accessibilityIdentifier("complete.confirm")
                    
                    SecondaryButton(title: "claim_complete_cancel".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("complete.cancel")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("claim_complete_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
        .successCheckmark(isShowing: $showSuccess)
        .onChange(of: showSuccess) { _, newValue in
            if !newValue {
                dismiss()
            }
        }
    }
}

#Preview {
    CompleteSheet(
        requestType: "ride",
        requestTitle: "Ride to Airport",
        onConfirm: {}
    )
}





