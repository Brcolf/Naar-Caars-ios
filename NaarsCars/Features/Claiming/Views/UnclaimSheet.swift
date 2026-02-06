//
//  UnclaimSheet.swift
//  NaarsCars
//
//  Confirmation sheet for unclaiming a request
//

import SwiftUI

/// Confirmation sheet for unclaiming a request
struct UnclaimSheet: View {
    let requestType: String
    let requestTitle: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsWarning)
                
                Text("claiming_unclaim_title".localized(with: requestType.capitalized))
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("claiming_unclaim_subtitle".localized)
                    .foregroundColor(.secondary)
                
                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.naarsCardBackground)
                    .cornerRadius(8)
                
                Text("claiming_unclaim_message".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "claiming_unclaim_confirm".localized) {
                        onConfirm()
                        dismiss()
                    }
                    .accessibilityIdentifier("unclaim.confirm")
                    
                    SecondaryButton(title: "common_cancel".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("unclaim.cancel")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("claiming_unclaim_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    UnclaimSheet(
        requestType: "ride",
        requestTitle: "Ride to Airport",
        onConfirm: {}
    )
}





